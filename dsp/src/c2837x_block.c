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
    C2837X_STATE_LISTEN = 0,
    C2837X_STATE_CONNECTED,
    C2837X_STATE_SIM_RUNNING,
    C2837X_STATE_DISCONNECTED,
    C2837X_STATE_ERROR
} C2837xBlock_State;

typedef enum {
    C2837X_RX_WAIT_HEADER = 0,
    C2837X_RX_WAIT_PAYLOAD
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
    Uint16 step_index_exhausted;
    Uint16 socket_lost_count;

    Uint32 state_start_tick;
    Uint32 frame_start_tick;
    Uint16 last_error;
} C2837xBlock_Context;

static C2837xBlock_Context g_ctx;
static Uint32 g_tick_counter;

volatile Uint16 c2837x_block_debug_state;
volatile Uint16 c2837x_block_debug_socket_status;
volatile Uint16 c2837x_block_debug_socket_status_raw;
volatile Uint16 c2837x_block_debug_socket_status_hi;
volatile Uint16 c2837x_block_debug_socket_status_lo;
volatile Uint16 c2837x_block_debug_socket_status_chosen;
volatile Uint16 c2837x_block_debug_socket_ir;
volatile Uint32 c2837x_block_debug_tx_free;
volatile Uint32 c2837x_block_debug_rx_size;
volatile Uint16 c2837x_block_debug_last_error;
volatile Uint16 c2837x_block_debug_rx_msg_type;
volatile Uint16 c2837x_block_debug_rx_payload_length;
volatile Uint32 c2837x_block_debug_expected_step;
volatile Uint32 c2837x_block_debug_tick;
volatile Uint16 c2837x_block_debug_last_nonlisten_status;
volatile Uint16 c2837x_block_debug_close_reason;
volatile Uint32 c2837x_block_debug_accept_count;
volatile Uint32 c2837x_block_debug_disconnect_count;
volatile Uint32 c2837x_block_debug_error_count;
volatile Uint16 c2837x_block_debug_prev_socket_status;
volatile Uint16 c2837x_block_debug_status_history0;
volatile Uint16 c2837x_block_debug_status_history1;
volatile Uint16 c2837x_block_debug_status_history2;
volatile Uint16 c2837x_block_debug_status_history3;
volatile Uint32 c2837x_block_debug_synrecv_count;
volatile Uint32 c2837x_block_debug_established_count;
volatile Uint32 c2837x_block_debug_closewait_count;
volatile Uint32 c2837x_block_debug_listen_return_count;
volatile Uint16 c2837x_block_debug_socket_lost_status;
volatile Uint16 c2837x_block_debug_socket_lost_count;

/*
 * These are loop-count budgets, not wall-clock ticks.  Keep them large because
 * the bare-metal main loop can spin much faster than the PC can complete
 * connect/write operations.
 */
#define C2837X_BLOCK_STATE_TIMEOUT_TICKS  1000000000u
#define C2837X_BLOCK_FRAME_TIMEOUT_TICKS  1000000000u
#define C2837X_BLOCK_UINT32_MAX           (~((Uint32)0))

#define C2837X_CLOSE_NONE                 0u
#define C2837X_CLOSE_SOCKET_LOST          1u
#define C2837X_CLOSE_STATE_TIMEOUT        2u
#define C2837X_CLOSE_RX_TX_ERROR          3u
#define C2837X_CLOSE_PROTOCOL_ERROR       4u
#define C2837X_CLOSE_SIM_STOP             5u
#define C2837X_CLOSE_LISTEN_CLEANUP       6u
#define C2837X_BLOCK_SOCKET_LOST_LIMIT    3u

static Uint32 c2837x_block_now(void)
{
    return g_tick_counter;
}

static void c2837x_block_tick(void)
{
    g_tick_counter++;
    c2837x_block_debug_tick = g_tick_counter;
}

static int16 c2837x_block_timed_out(Uint32 start_tick, Uint32 timeout_ticks)
{
    return ((Uint32)(c2837x_block_now() - start_tick) >= timeout_ticks) ? 1 : 0;
}

static void c2837x_block_set_state(C2837xBlock_Context* ctx,
                                    C2837xBlock_State state)
{
    ctx->state = state;
    c2837x_block_debug_state = (Uint16)state;
}

static void c2837x_block_update_debug(C2837xBlock_Context* ctx,
                                       Uint16 socket_status)
{
    Uint16 raw_status = c2837x_w5300_read16(Sn_SSR(ctx->socket.sn));

    c2837x_block_debug_socket_status_raw = raw_status;
    c2837x_block_debug_socket_status_hi =
        (Uint16)((raw_status >> 8) & 0x00FFu);
    c2837x_block_debug_socket_status_lo =
        (Uint16)(raw_status & 0x00FFu);
    c2837x_block_debug_socket_status_chosen = socket_status;

    if (socket_status != c2837x_block_debug_socket_status)
    {
        c2837x_block_debug_prev_socket_status =
            c2837x_block_debug_socket_status;
        c2837x_block_debug_status_history3 =
            c2837x_block_debug_status_history2;
        c2837x_block_debug_status_history2 =
            c2837x_block_debug_status_history1;
        c2837x_block_debug_status_history1 =
            c2837x_block_debug_status_history0;
        c2837x_block_debug_status_history0 = socket_status;

        if (socket_status == SOCK_SYNRECV)
            c2837x_block_debug_synrecv_count++;
        else if (socket_status == SOCK_ESTABLISHED)
            c2837x_block_debug_established_count++;
        else if (socket_status == SOCK_CLOSE_WAIT)
            c2837x_block_debug_closewait_count++;
        else if (socket_status == SOCK_LISTEN)
            c2837x_block_debug_listen_return_count++;
    }

    c2837x_block_debug_state = (Uint16)ctx->state;
    c2837x_block_debug_socket_status = socket_status;
    if (socket_status != SOCK_LISTEN)
        c2837x_block_debug_last_nonlisten_status = socket_status;
    c2837x_block_debug_socket_ir =
        c2837x_w5300_get_sn_ir(ctx->socket.sn);
    c2837x_block_debug_tx_free =
        c2837x_w5300_socket_get_tx_free(&ctx->socket);
    c2837x_block_debug_rx_size =
        c2837x_w5300_socket_get_rx_size(&ctx->socket);
    c2837x_block_debug_last_error = ctx->last_error;
    c2837x_block_debug_rx_msg_type = ctx->rx_msg_type;
    c2837x_block_debug_rx_payload_length = ctx->rx_payload_length_bytes;
    c2837x_block_debug_expected_step = ctx->expected_step_index;
}

static Uint16 c2837x_block_read_socket_status(C2837xBlock_Context* ctx)
{
    Uint16 status = c2837x_w5300_get_sn_ssr(ctx->socket.sn);
    c2837x_block_update_debug(ctx, status);
    return status;
}

static void c2837x_block_reset_rx(C2837xBlock_Context* ctx)
{
    ctx->rx_state = C2837X_RX_WAIT_HEADER;
    ctx->rx_header_received_bytes = 0;
    ctx->rx_payload_received_bytes = 0;
    ctx->rx_msg_type = 0;
    ctx->rx_payload_length_bytes = 0;
    ctx->frame_start_tick = c2837x_block_now();
}

static void c2837x_block_reset_tx(C2837xBlock_Context* ctx)
{
    ctx->tx_total_bytes = 0;
    ctx->tx_sent_bytes = 0;
    ctx->advance_step_after_tx = 0;
}

static void c2837x_block_reset_session(C2837xBlock_Context* ctx)
{
    c2837x_block_reset_rx(ctx);
    c2837x_block_reset_tx(ctx);
    ctx->expected_step_index = 0;
    ctx->step_index_exhausted = 0;
    ctx->sim_started = 0;
    ctx->socket_lost_count = 0;
    ctx->last_error = C2837X_ERR_OK;
    ctx->state_start_tick = c2837x_block_now();
}

static void c2837x_block_start_tx(C2837xBlock_Context* ctx,
                                   Uint32 total_wire_bytes)
{
    ctx->tx_total_bytes = total_wire_bytes;
    ctx->tx_sent_bytes = 0;
    ctx->frame_start_tick = c2837x_block_now();
}

static int16 c2837x_block_tx_pending(const C2837xBlock_Context* ctx)
{
    return (ctx->tx_sent_bytes < ctx->tx_total_bytes) ? 1 : 0;
}

static void c2837x_block_start_error_response(C2837xBlock_Context* ctx,
                                               Uint16 error_code)
{
    Uint32 frame_bytes;

    ctx->last_error = error_code;
    c2837x_block_debug_error_count++;
    c2837x_block_debug_close_reason = C2837X_CLOSE_PROTOCOL_ERROR;
    ctx->advance_step_after_tx = 0;
    frame_bytes = c2837x_block_build_response(ctx->tx_frame_words,
                                               error_code);
    c2837x_block_start_tx(ctx, frame_bytes);
    c2837x_block_set_state(ctx, C2837X_STATE_ERROR);
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
            return -1;
        return 0;
    }

    ctx->tx_sent_bytes += (Uint32)sent_bytes;
    return c2837x_block_tx_pending(ctx) ? 0 : 1;
}

static int16 c2837x_block_continue_rx(C2837xBlock_Context* ctx)
{
    int32 received_bytes;

    if (ctx->rx_state == C2837X_RX_WAIT_HEADER)
    {
        Uint32 needed_bytes =
            C2837X_BLOCK_HEADER_SIZE_BYTES - ctx->rx_header_received_bytes;
        Uint32 offset_words = ctx->rx_header_received_bytes / 2u;

        received_bytes = c2837x_w5300_socket_recv(
            &ctx->socket,
            &ctx->rx_header_words[offset_words],
            needed_bytes);

        if (received_bytes < 0)
            return -1;

        if (received_bytes == 0)
        {
            if (c2837x_block_timed_out(ctx->frame_start_tick,
                                        C2837X_BLOCK_FRAME_TIMEOUT_TICKS))
            {
                ctx->last_error = C2837X_ERR_LENGTH;
                return -1;
            }
            return 0;
        }

        ctx->rx_header_received_bytes += (Uint32)received_bytes;

        if (ctx->rx_header_received_bytes < C2837X_BLOCK_HEADER_SIZE_BYTES)
            return 0;

        if (c2837x_block_parse_header(ctx->rx_header_words,
                                       &ctx->rx_msg_type,
                                       &ctx->rx_payload_length_bytes) < 0)
        {
            ctx->last_error = C2837X_ERR_LENGTH;
            return -1;
        }

        if (ctx->rx_payload_length_bytes > C2837X_BLOCK_MAX_PAYLOAD_SIZE_BYTES)
        {
            ctx->last_error = C2837X_ERR_LENGTH;
            return -1;
        }

        c2837x_block_debug_rx_msg_type = ctx->rx_msg_type;
        c2837x_block_debug_rx_payload_length = ctx->rx_payload_length_bytes;

        if (ctx->rx_payload_length_bytes == 0u)
            return 1;

        ctx->rx_state = C2837X_RX_WAIT_PAYLOAD;
        ctx->rx_payload_received_bytes = 0;
        ctx->frame_start_tick = c2837x_block_now();
    }

    if (ctx->rx_state == C2837X_RX_WAIT_PAYLOAD)
    {
        Uint32 needed_bytes =
            (Uint32)ctx->rx_payload_length_bytes - ctx->rx_payload_received_bytes;
        Uint32 offset_words = ctx->rx_payload_received_bytes / 2u;

        received_bytes = c2837x_w5300_socket_recv(
            &ctx->socket,
            &ctx->rx_payload_words[offset_words],
            needed_bytes);

        if (received_bytes < 0)
            return -1;

        if (received_bytes == 0)
        {
            if (c2837x_block_timed_out(ctx->frame_start_tick,
                                        C2837X_BLOCK_FRAME_TIMEOUT_TICKS))
            {
                ctx->last_error = C2837X_ERR_LENGTH;
                return -1;
            }
            return 0;
        }

        ctx->rx_payload_received_bytes += (Uint32)received_bytes;
        if (ctx->rx_payload_received_bytes >= (Uint32)ctx->rx_payload_length_bytes)
            return 1;
    }

    return 0;
}

static void c2837x_block_after_tx_done(C2837xBlock_Context* ctx)
{
    if (ctx->advance_step_after_tx != 0u)
    {
        ctx->advance_step_after_tx = 0;
        if (ctx->expected_step_index == C2837X_BLOCK_UINT32_MAX)
            ctx->step_index_exhausted = 1;
        else
            ctx->expected_step_index++;
    }

    c2837x_block_reset_tx(ctx);
    c2837x_block_reset_rx(ctx);
    ctx->state_start_tick = c2837x_block_now();
}

static void c2837x_block_handle_sim_start(C2837xBlock_Context* ctx)
{
    Uint16 protocol_version;
    Uint32 config_hash;
    Uint32 frame_bytes;

    if (ctx->rx_payload_length_bytes != 6u)
    {
        c2837x_block_start_error_response(ctx, C2837X_ERR_LENGTH);
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

    ctx->expected_step_index = 0;
    ctx->step_index_exhausted = 0;
    ctx->sim_started = 1;
    ctx->last_error = C2837X_ERR_OK;
    c2837x_block_set_state(ctx, C2837X_STATE_SIM_RUNNING);
}

static void c2837x_block_handle_input_data(C2837xBlock_Context* ctx)
{
    Uint32 step_index;
    Uint32 frame_bytes;

    if (ctx->rx_payload_length_bytes != C2837X_BLOCK_INPUT_PAYLOAD_SIZE_BYTES)
    {
        c2837x_block_start_error_response(ctx, C2837X_ERR_LENGTH);
        return;
    }

    c2837x_block_unpack_input_payload(ctx->rx_payload_words, &step_index);

    if ((ctx->step_index_exhausted != 0u) ||
        (step_index != ctx->expected_step_index))
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
        c2837x_block_start_error_response(ctx, C2837X_ERR_LENGTH);
        return;
    }

    C2837xBlock_OnSimStop();
    ctx->sim_started = 0;
    c2837x_block_debug_close_reason = C2837X_CLOSE_SIM_STOP;
    c2837x_block_set_state(ctx, C2837X_STATE_DISCONNECTED);
}

static void c2837x_block_dispatch_connected(C2837xBlock_Context* ctx)
{
    if (ctx->rx_msg_type == C2837X_MSG_SIM_START)
        c2837x_block_handle_sim_start(ctx);
    else
        c2837x_block_start_error_response(ctx, C2837X_ERR_STATE);
}

static void c2837x_block_dispatch_running(C2837xBlock_Context* ctx)
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
        c2837x_block_start_error_response(ctx, C2837X_ERR_STATE);
        break;

    default:
        c2837x_block_start_error_response(ctx, C2837X_ERR_UNKNOWN_TYPE);
        break;
    }
}

static void c2837x_block_disconnect(C2837xBlock_Context* ctx)
{
    c2837x_block_debug_disconnect_count++;

    if (ctx->sim_started != 0u)
    {
        C2837xBlock_OnSimStop();
        ctx->sim_started = 0;
    }

    c2837x_w5300_socket_close(&ctx->socket);
    if (c2837x_block_debug_close_reason == C2837X_CLOSE_NONE)
        c2837x_block_debug_close_reason = C2837X_CLOSE_LISTEN_CLEANUP;
    c2837x_block_reset_session(ctx);
    c2837x_block_set_state(ctx, C2837X_STATE_LISTEN);
}

static void c2837x_block_accept_connection(C2837xBlock_Context* ctx)
{
    c2837x_block_debug_accept_count++;
    c2837x_block_debug_close_reason = C2837X_CLOSE_NONE;
    c2837x_w5300_set_sn_ir(ctx->socket.sn, Sn_IR_CON);
    c2837x_block_reset_session(ctx);
    c2837x_block_set_state(ctx, C2837X_STATE_CONNECTED);
}

static void c2837x_block_service_listen(C2837xBlock_Context* ctx)
{
    Uint16 status = c2837x_block_read_socket_status(ctx);

    switch (status)
    {
    case SOCK_ESTABLISHED:
        c2837x_block_accept_connection(ctx);
        break;

    case SOCK_LISTEN:
    case SOCK_SYNRECV:
    case SOCK_SYNSENT:
    case SOCK_ARP:
        break;

    case SOCK_INIT:
        if (c2837x_w5300_socket_listen(&ctx->socket) < 0)
            c2837x_w5300_socket_close(&ctx->socket);
        break;

    case SOCK_CLOSED:
        if (c2837x_w5300_socket_open(&ctx->socket,
                                      Sn_MR_TCP,
                                      C2837X_BLOCK_TCP_PORT,
                                      0) == 0)
        {
            if (c2837x_w5300_get_sn_ssr(ctx->socket.sn) == SOCK_INIT)
                (void)c2837x_w5300_socket_listen(&ctx->socket);
        }
        break;

    case SOCK_FIN_WAIT:
    case SOCK_CLOSING:
    case SOCK_TIME_WAIT:
    case SOCK_CLOSE_WAIT:
    case SOCK_LAST_ACK:
        c2837x_block_debug_close_reason = C2837X_CLOSE_SOCKET_LOST;
        c2837x_w5300_socket_close(&ctx->socket);
        break;

    default:
        c2837x_block_debug_socket_lost_status = status;
        break;
    }
}

static int16 c2837x_block_socket_session_alive(C2837xBlock_Context* ctx)
{
    Uint16 status = c2837x_block_read_socket_status(ctx);

    if (status == SOCK_ESTABLISHED)
    {
        ctx->socket_lost_count = 0;
        c2837x_block_debug_socket_lost_count = 0;
        return 1;
    }

    if ((status == SOCK_CLOSED) ||
        (status == SOCK_INIT) ||
        (status == SOCK_LISTEN) ||
        (status == SOCK_FIN_WAIT) ||
        (status == SOCK_CLOSING) ||
        (status == SOCK_TIME_WAIT) ||
        (status == SOCK_CLOSE_WAIT) ||
        (status == SOCK_LAST_ACK))
    {
        ctx->socket_lost_count++;
        c2837x_block_debug_socket_lost_status = status;
        c2837x_block_debug_socket_lost_count = ctx->socket_lost_count;

        if (ctx->socket_lost_count >= C2837X_BLOCK_SOCKET_LOST_LIMIT)
            return 0;
    }

    return 1;
}

static void c2837x_block_service_connected(C2837xBlock_Context* ctx)
{
    int16 rx_result;

    if (!c2837x_block_socket_session_alive(ctx))
    {
        c2837x_block_debug_close_reason = C2837X_CLOSE_SOCKET_LOST;
        c2837x_block_set_state(ctx, C2837X_STATE_DISCONNECTED);
        return;
    }

    if (c2837x_block_timed_out(ctx->state_start_tick,
                                C2837X_BLOCK_STATE_TIMEOUT_TICKS))
    {
        c2837x_block_debug_close_reason = C2837X_CLOSE_STATE_TIMEOUT;
        c2837x_block_set_state(ctx, C2837X_STATE_DISCONNECTED);
        return;
    }

    rx_result = c2837x_block_continue_rx(ctx);
    if (rx_result < 0)
    {
        if (ctx->last_error != C2837X_ERR_OK)
            c2837x_block_start_error_response(ctx, ctx->last_error);
        else
        {
            c2837x_block_debug_close_reason = C2837X_CLOSE_RX_TX_ERROR;
            c2837x_block_set_state(ctx, C2837X_STATE_DISCONNECTED);
        }
        return;
    }

    if (rx_result == 1)
        c2837x_block_dispatch_connected(ctx);
}

static void c2837x_block_service_running(C2837xBlock_Context* ctx)
{
    int16 tx_result;
    int16 rx_result;

    if (!c2837x_block_socket_session_alive(ctx))
    {
        c2837x_block_debug_close_reason = C2837X_CLOSE_SOCKET_LOST;
        c2837x_block_set_state(ctx, C2837X_STATE_DISCONNECTED);
        return;
    }

    if (c2837x_block_tx_pending(ctx))
    {
        tx_result = c2837x_block_continue_tx(ctx);
        if (tx_result < 0)
        {
            c2837x_block_debug_close_reason = C2837X_CLOSE_RX_TX_ERROR;
            c2837x_block_set_state(ctx, C2837X_STATE_DISCONNECTED);
            return;
        }

        if (tx_result == 0)
            return;

        c2837x_block_after_tx_done(ctx);
    }

    if (c2837x_block_timed_out(ctx->state_start_tick,
                                C2837X_BLOCK_STATE_TIMEOUT_TICKS))
    {
        c2837x_block_debug_close_reason = C2837X_CLOSE_STATE_TIMEOUT;
        c2837x_block_set_state(ctx, C2837X_STATE_DISCONNECTED);
        return;
    }

    rx_result = c2837x_block_continue_rx(ctx);
    if (rx_result < 0)
    {
        if (ctx->last_error != C2837X_ERR_OK)
            c2837x_block_start_error_response(ctx, ctx->last_error);
        else
        {
            c2837x_block_debug_close_reason = C2837X_CLOSE_RX_TX_ERROR;
            c2837x_block_set_state(ctx, C2837X_STATE_DISCONNECTED);
        }
        return;
    }

    if (rx_result == 1)
    {
        ctx->state_start_tick = c2837x_block_now();
        c2837x_block_dispatch_running(ctx);

        if ((ctx->state == C2837X_STATE_SIM_RUNNING) &&
            !c2837x_block_tx_pending(ctx))
        {
            c2837x_block_reset_rx(ctx);
        }
    }
}

static void c2837x_block_service_error(C2837xBlock_Context* ctx)
{
    int16 tx_result;

    if (!c2837x_block_socket_session_alive(ctx))
    {
        c2837x_block_debug_close_reason = C2837X_CLOSE_SOCKET_LOST;
        c2837x_block_set_state(ctx, C2837X_STATE_DISCONNECTED);
        return;
    }

    tx_result = c2837x_block_continue_tx(ctx);

    if (tx_result < 0)
    {
        c2837x_block_debug_close_reason = C2837X_CLOSE_RX_TX_ERROR;
        c2837x_block_set_state(ctx, C2837X_STATE_DISCONNECTED);
    }
    else if (tx_result == 1)
    {
        c2837x_block_set_state(ctx, C2837X_STATE_DISCONNECTED);
    }
}

int16 C2837xBlock_Init(void)
{
    C2837xBlock_Context* ctx = &g_ctx;

    memset(ctx, 0, sizeof(*ctx));
    g_tick_counter = 0;
    c2837x_block_debug_close_reason = C2837X_CLOSE_NONE;

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

    c2837x_block_reset_session(ctx);
    c2837x_block_set_state(ctx, C2837X_STATE_LISTEN);

    if (c2837x_w5300_socket_open(&ctx->socket,
                                  Sn_MR_TCP,
                                  C2837X_BLOCK_TCP_PORT,
                                  0) != 0)
    {
        return -1;
    }

    return 0;
}

void C2837xBlock_Run(void)
{
    C2837xBlock_Context* ctx = &g_ctx;

    c2837x_block_tick();
    c2837x_block_debug_state = (Uint16)ctx->state;
    c2837x_block_debug_last_error = ctx->last_error;

    switch (ctx->state)
    {
    case C2837X_STATE_LISTEN:
        c2837x_block_service_listen(ctx);
        break;

    case C2837X_STATE_CONNECTED:
        c2837x_block_service_connected(ctx);
        break;

    case C2837X_STATE_SIM_RUNNING:
        c2837x_block_service_running(ctx);
        break;

    case C2837X_STATE_ERROR:
        c2837x_block_service_error(ctx);
        break;

    case C2837X_STATE_DISCONNECTED:
        c2837x_block_disconnect(ctx);
        break;

    default:
        c2837x_block_set_state(ctx, C2837X_STATE_DISCONNECTED);
        break;
    }
}
