/*
 * C2837xBlock non-blocking DSP communication state machine.
 *
 * Protocol flow:
 *   LISTEN      -> wait for a TCP client on W5300 socket 0
 *   CONNECTED   -> receive SIM_START, validate version/config, send RESPONSE(0)
 *   SIM_RUNNING -> receive INPUT_DATA/SIM_STOP, send OUTPUT_DATA or RESPONSE(error)
 *   ERROR       -> finish sending RESPONSE(error), then disconnect
 *
 * One C2837xBlock_Run() call performs a bounded amount of work and returns.
 */

#include "c2837x_block.h"
#include "c2837x_block_algorithm.h"
#include "c2837x_block_config.h"
#include "c2837x_block_protocol.h"
#include "c2837x_w5300_hal.h"
#include "c2837x_w5300_socket.h"
#include <string.h>

typedef enum {
    C2837X_STATE_RECV = 0,
    C2837X_STATE_SEND
} C2837xBlock_State;

typedef enum {
    C2837X_RX_WAIT_HEADER = 0,
    C2837X_RX_WAIT_PAYLOAD,
    C2837X_RX_PROCESSING
} C2837xBlock_RxState;

typedef struct {
    C2837xBlock_State state;
    C2837xBlock_RxState rx_state;
    C2837xW5300Socket socket;

    Uint16 rx_header_words[2];
    Uint32 rx_header_received_bytes;
    Uint16 rx_payload_words[C2837X_BLOCK_MAX_PAYLOAD_SIZE_WORDS];
    Uint16 rx_msg_type;
    Uint16 rx_payload_length_bytes;
    Uint32 rx_payload_received_bytes;

    Uint16 tx_frame_words[(C2837X_BLOCK_MAX_FRAME_SIZE_BYTES + 1u) / 2u];
    Uint32 tx_total_bytes;
    Uint32 tx_sent_bytes;

    Uint32 expected_step_index;
    Uint16 sim_started;
    Uint16 advance_step_after_tx;

    Uint32 frame_start_tick;
    Uint16 last_error;
} C2837xBlock_Context;

static C2837xBlock_Context g_ctx;
static Uint32 g_tick_counter;

/*
 * These are loop-count budgets, not wall-clock ticks.  Keep them large because
 * the bare-metal main loop can spin much faster than the PC can complete
 * connect/write operations.
 */
#define C2837X_BLOCK_STATE_TIMEOUT_TICKS  1000000000u
#define C2837X_BLOCK_FRAME_TIMEOUT_TICKS  1000000000u
#define C2837X_BLOCK_UINT32_MAX           (~((Uint32)0))

static void c2837x_block_disconnect(C2837xBlock_Context* ctx);

static inline Uint32 c2837x_block_now(void)
{
    return g_tick_counter;
}

static inline void c2837x_block_tick(void)
{
    g_tick_counter++;
}

static inline int16 c2837x_block_timed_out(Uint32 start_tick, Uint32 timeout_ticks)
{
    return ((Uint32)(c2837x_block_now() - start_tick) >= timeout_ticks) ? 1 : 0;
}

static inline  void c2837x_block_set_state(C2837xBlock_Context* ctx,
                                    C2837xBlock_State state)
{
    ctx->state = state;
}

static inline void c2837x_block_reset_rx(C2837xBlock_Context* ctx)
{
    ctx->rx_state = C2837X_RX_WAIT_HEADER;
    ctx->rx_header_received_bytes = 0;
    ctx->rx_payload_received_bytes = 0;
    ctx->rx_msg_type = 0;
    ctx->rx_payload_length_bytes = 0;
}

static inline void c2837x_block_reset_tx(C2837xBlock_Context* ctx)
{
    ctx->tx_total_bytes = 0;
    ctx->tx_sent_bytes = 0;
}

static inline void c2837x_block_reset_session(C2837xBlock_Context* ctx)
{
    c2837x_block_reset_rx(ctx);
    c2837x_block_reset_tx(ctx);
    ctx->expected_step_index = 0;
    ctx->advance_step_after_tx = 0;
    ctx->sim_started = 0;
    ctx->last_error = C2837X_ERR_OK;
}

static inline void c2837x_block_start_tx(C2837xBlock_Context* ctx,
                                   Uint32 total_wire_bytes)
{
    ctx->tx_total_bytes = total_wire_bytes;
    ctx->tx_sent_bytes = 0;
    c2837x_block_set_state(ctx, C2837X_STATE_SEND);
    ctx->last_error = C2837X_ERR_OK;
    ctx->frame_start_tick = c2837x_block_now();
}

static inline void c2837x_block_start_rx(C2837xBlock_Context* ctx)
{
    c2837x_block_reset_rx(ctx);

    c2837x_block_set_state(ctx, C2837X_STATE_RECV);
    ctx->last_error = C2837X_ERR_OK;
    ctx->frame_start_tick = c2837x_block_now();
}

static inline int16 c2837x_block_tx_pending(const C2837xBlock_Context* ctx)
{
    return (ctx->tx_sent_bytes < ctx->tx_total_bytes) ? 1 : 0;
}

static inline void c2837x_block_start_error_response(C2837xBlock_Context* ctx,
                                               Uint16 error_code)
{
    Uint32 frame_bytes;

    ctx->last_error = error_code;
    ctx->advance_step_after_tx = 0;
    frame_bytes = c2837x_block_build_response(ctx->tx_frame_words,
                                               error_code);
    c2837x_block_start_tx(ctx, frame_bytes);
}

static int16 c2837x_block_continue_tx(C2837xBlock_Context* ctx)
{
    Uint32 remaining_bytes;
    Uint32 offset_words;
    int32 sent_bytes;

    if (!c2837x_block_tx_pending(ctx))
        return 1;

    remaining_bytes = ctx->tx_total_bytes - ctx->tx_sent_bytes;
    offset_words = ctx->tx_sent_bytes / 2u;

    sent_bytes = c2837x_w5300_socket_send(&ctx->socket,
                                           &ctx->tx_frame_words[offset_words],
                                           remaining_bytes);
    if (sent_bytes < 0)
        return -1;

    if (sent_bytes == 0)
    {
        if (c2837x_block_timed_out(ctx->frame_start_tick,
                                    C2837X_BLOCK_FRAME_TIMEOUT_TICKS))
        {
            return -1;
        }
        return 0;
    }

    ctx->frame_start_tick = c2837x_block_now();
    ctx->tx_sent_bytes += (Uint32)sent_bytes;
    return c2837x_block_tx_pending(ctx) ? 0 : 1;
}

static int16 c2837x_block_continue_rx(C2837xBlock_Context* ctx)
{
    int32 received_bytes;
    Uint16* data_words;
    Uint32 needed_bytes;
    
    if (ctx->rx_state == C2837X_RX_WAIT_HEADER)
    {
        needed_bytes =
            C2837X_BLOCK_HEADER_SIZE_BYTES - ctx->rx_header_received_bytes;
        Uint32 offset_words = ctx->rx_header_received_bytes / 2u;
        data_words = &ctx->rx_header_words[offset_words];
    }
    else if (ctx->rx_state == C2837X_RX_WAIT_PAYLOAD)
    {
        needed_bytes =
            (Uint32)ctx->rx_payload_length_bytes - ctx->rx_payload_received_bytes;
        Uint32 offset_words = ctx->rx_payload_received_bytes / 2u;
        data_words = &ctx->rx_payload_words[offset_words];
    }
    else
    {
        return 0;
    }

    received_bytes = c2837x_w5300_socket_recv(
        &ctx->socket,
        data_words,
        needed_bytes);

    if (received_bytes < 0)
    {
        return -1;
    }
    else if (received_bytes == 0)
    {
        if (c2837x_block_timed_out(ctx->frame_start_tick,
                                    C2837X_BLOCK_FRAME_TIMEOUT_TICKS))
        {
            return -1;
        }
        return 0;
    }

    ctx->frame_start_tick = c2837x_block_now();

    if (ctx->rx_state == C2837X_RX_WAIT_HEADER)
    {
        ctx->rx_header_received_bytes += (Uint32)received_bytes;

        if (ctx->rx_header_received_bytes < C2837X_BLOCK_HEADER_SIZE_BYTES)
        {
            return 0;
        }

        if (c2837x_block_parse_header(ctx->rx_header_words,
                                       &ctx->rx_msg_type,
                                       &ctx->rx_payload_length_bytes) < 0)
        {
            ctx->last_error = C2837X_ERR_PAYLOAD_LENGTH;
            return -1;
        }

        if (ctx->rx_payload_length_bytes > C2837X_BLOCK_MAX_PAYLOAD_SIZE_BYTES)
        {
            ctx->last_error = C2837X_ERR_PAYLOAD_LENGTH;
            return -1;
        }

        if (ctx->rx_payload_length_bytes == 0u)
        {
            ctx->rx_state = C2837X_RX_PROCESSING;
        }

        ctx->rx_state = C2837X_RX_WAIT_PAYLOAD;
        ctx->rx_payload_received_bytes = 0;
        
        return 0;
    }

    if (ctx->rx_state == C2837X_RX_WAIT_PAYLOAD)
    {
        ctx->rx_payload_received_bytes += (Uint32)received_bytes;
        if (ctx->rx_payload_received_bytes >= (Uint32)ctx->rx_payload_length_bytes)
        {
            ctx->rx_state = C2837X_RX_PROCESSING;
            return 0;
        }
    }

    return 0;
}

static void c2837x_block_after_tx_done(C2837xBlock_Context* ctx)
{
    if (ctx->advance_step_after_tx != 0u)
    {
        ctx->advance_step_after_tx = 0;
        ctx->expected_step_index++;
        
        c2837x_block_start_rx(ctx);
    }
    else
    {
        c2837x_block_disconnect(ctx);
    }
}

static void c2837x_block_handle_sim_start(C2837xBlock_Context* ctx)
{
    Uint16 protocol_version;
    Uint32 config_hash;
    Uint32 frame_bytes;

    if (ctx->rx_payload_length_bytes != 6u)
    {
        c2837x_block_start_error_response(ctx, C2837X_ERR_PAYLOAD_LENGTH);
        return;
    }

    protocol_version = ctx->rx_payload_words[0];
    config_hash = (Uint32)ctx->rx_payload_words[1] |
                  ((Uint32)ctx->rx_payload_words[2] << 16);

    if (protocol_version != C2837X_BLOCK_PROTOCOL_VERSION)
    {
        c2837x_block_start_error_response(ctx,
                                           C2837X_ERR_PROTOCOL_VERSION);
        return;
    }

    if (config_hash != C2837X_BLOCK_CONFIG_HASH)
    {
        c2837x_block_start_error_response(ctx,
                                           C2837X_ERR_CONFIG_MISMATCH);
        return;
    }

    if (C2837xBlock_OnSimStart() != 0)
    {
        c2837x_block_start_error_response(ctx, C2837X_ERR_INTERNAL);
        return;
    }

    frame_bytes = c2837x_block_build_response(ctx->tx_frame_words,
                                               C2837X_ERR_OK);
    c2837x_block_start_tx(ctx, frame_bytes);
    ctx->advance_step_after_tx = 1;
    ctx->expected_step_index = C2837X_BLOCK_UINT32_MAX;
    ctx->sim_started = 1;
    ctx->last_error = C2837X_ERR_OK;
}

static void c2837x_block_handle_input_data(C2837xBlock_Context* ctx)
{
    Uint32 step_index;
    Uint32 frame_bytes;

    if (ctx->rx_payload_length_bytes != C2837X_BLOCK_INPUT_PAYLOAD_SIZE_BYTES)
    {
        c2837x_block_start_error_response(ctx, C2837X_ERR_PAYLOAD_LENGTH);
        return;
    }

    c2837x_block_unpack_input_payload(ctx->rx_payload_words, &step_index);

    if (step_index != ctx->expected_step_index)
    {
        c2837x_block_start_error_response(ctx, C2837X_ERR_STEP_INDEX);
        return;
    }

    if (C2837xBlock_OnStep() != 0)
    {
        c2837x_block_start_error_response(ctx, C2837X_ERR_INTERNAL);
        return;
    }

    c2837x_block_pack_output_payload(ctx->rx_payload_words, step_index);
    frame_bytes = c2837x_block_build_frame(
        ctx->tx_frame_words,
        C2837X_MSG_OUTPUT_DATA,
        C2837X_BLOCK_OUTPUT_PAYLOAD_SIZE_BYTES,
        ctx->rx_payload_words);

    c2837x_block_start_tx(ctx, frame_bytes);
    ctx->advance_step_after_tx = 1;
    ctx->last_error = C2837X_ERR_OK;
}

static void c2837x_block_handle_sim_stop(C2837xBlock_Context* ctx)
{
    if (ctx->rx_payload_length_bytes != 0u)
    {
        c2837x_block_start_error_response(ctx, C2837X_ERR_PAYLOAD_LENGTH);
        return;
    }

    C2837xBlock_OnSimStop();
    ctx->sim_started = 0;

    c2837x_block_disconnect(ctx);
}

static void c2837x_block_dispatch_message(C2837xBlock_Context* ctx)
{
    switch (ctx->rx_msg_type)
    {
    case C2837X_MSG_INPUT_DATA:
        c2837x_block_handle_input_data(ctx);
        break;

    case C2837X_MSG_SIM_STOP:
        c2837x_block_handle_sim_stop(ctx);
        break;

    case C2837X_MSG_SIM_START:
        c2837x_block_handle_sim_start(ctx);
        break;

    default:
        c2837x_block_start_error_response(ctx, C2837X_ERR_UNKNOWN_TYPE);
        break;
    }
}

static inline void c2837x_block_disconnect(C2837xBlock_Context* ctx)
{
    if (ctx->sim_started != 0u)
    {
        C2837xBlock_OnSimStop();
        ctx->sim_started = 0;
    }

    c2837x_w5300_socket_close(&ctx->socket);
    c2837x_block_reset_session(ctx);
}

static inline void c2837x_block_accept_connection(C2837xBlock_Context* ctx)
{
    c2837x_w5300_set_sn_ir(ctx->socket.sn, Sn_IR_CON);
    c2837x_block_reset_session(ctx);
    c2837x_block_start_rx(ctx);
}

static void c2837x_block_service_running(C2837xBlock_Context* ctx)
{
    c2837x_block_tick();
    if (ctx->state == C2837X_STATE_RECV)
    {
        int16 rx_result = c2837x_block_continue_rx(ctx);

        if (rx_result < 0)
        {
            if (ctx->last_error != C2837X_ERR_OK)
            {
                c2837x_block_start_error_response(ctx, ctx->last_error);
            }
            else
            {
                c2837x_block_disconnect(ctx);
            }
            return;
        }

        if (ctx->rx_state == C2837X_RX_PROCESSING)
        {
            c2837x_block_dispatch_message(ctx);
        }
    }
    else
    {
        if (c2837x_block_tx_pending(ctx))
        {
            int16 tx_result = c2837x_block_continue_tx(ctx);
            if (tx_result < 0)
            {
                c2837x_block_disconnect(ctx);
                return;
            }

            if (tx_result == 0)
                return;

            c2837x_block_after_tx_done(ctx);
        }
    }
}

int16 C2837xBlock_Init(void)
{
    C2837xBlock_Context* ctx = &g_ctx;

    memset(ctx, 0, sizeof(*ctx));
    g_tick_counter = 0;
    
    c2837x_w5300_init();

    c2837x_w5300_write16(MR, 0xB800);
    c2837x_w5300_fifo_swap =
        (c2837x_w5300_read16(MR) & MR_FS) ? 1u : 0u;

    c2837x_w5300_write16(RTR, 2000);
    c2837x_w5300_write16(RCR, 8);

    c2837x_w5300_set_shar(
        (Uint16)((C2837X_BLOCK_MAC0 << 8) | C2837X_BLOCK_MAC1),
        (Uint16)((C2837X_BLOCK_MAC2 << 8) | C2837X_BLOCK_MAC3),
        (Uint16)((C2837X_BLOCK_MAC4 << 8) | C2837X_BLOCK_MAC5));
    c2837x_w5300_set_gar(C2837X_BLOCK_GATEWAY);
    c2837x_w5300_set_subr(C2837X_BLOCK_SUBNET);
    c2837x_w5300_set_sipr(C2837X_BLOCK_IP_ADDR);

    ctx->socket.sn = C2837X_BLOCK_SOCKET_NUM;
    if (c2837x_w5300_configure_socket_memory(
            C2837X_BLOCK_SOCKET_NUM,
            C2837X_BLOCK_SOCKET0_TX_KB,
            C2837X_BLOCK_SOCKET0_RX_KB,
            &ctx->socket.tx_mem_size,
            &ctx->socket.rx_mem_size) != 0)
    {
        return -1;
    }

    return 0;
}

void C2837xBlock_Run(void)
{
    C2837xBlock_Context* ctx = &g_ctx;
    static Uint16 first_connected = 0;
    Uint16 sn_ssr;

    sn_ssr = c2837x_w5300_get_sn_ssr(ctx->socket.sn);
    switch (sn_ssr)
    {
    case SOCK_INIT:
        c2837x_w5300_socket_listen(&ctx->socket);
        first_connected = 0;
        break;
    case SOCK_ESTABLISHED:
        if (!first_connected)
        {
            first_connected = 1;
            c2837x_block_accept_connection(ctx);
        }
        c2837x_block_service_running(ctx);
        break;
    case SOCK_CLOSE_WAIT:
        c2837x_w5300_socket_disconnect(&ctx->socket);
        break;
    case SOCK_CLOSED:
        c2837x_w5300_socket_close(&ctx->socket);
        c2837x_w5300_socket_open(&ctx->socket,
                                  Sn_MR_TCP,
                                  C2837X_BLOCK_TCP_PORT,
                                  Sn_MR_ALIGN);
        break;
    default:
        break;
    }
}
