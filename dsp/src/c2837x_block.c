/*
 * C2837xBlock non-blocking DSP communication state machine.
 *
 * Protocol flow:
 *   LISTEN      -> wait for a client through the bound IoDevice
 *   CONNECTED   -> receive SIM_START, validate version/config, send RESPONSE(0)
 *   SIM_RUNNING -> receive INPUT_DATA/SIM_STOP, send OUTPUT_DATA or RESPONSE(error)
 *   ERROR       -> finish sending RESPONSE(error), then disconnect
 *
 * One C2837xBlock_Run(instance) call performs a bounded amount of work and returns.
 */

#include "c2837x_block.h"
#include "c2837x_block_internal.h"
#include "c2837x_block_algorithm.h"
#include "c2837x_block_config.h"
#include "c2837x_block_protocol.h"
#include <string.h>

/*
 * These are loop-count budgets, not wall-clock ticks.  Keep them large because
 * the bare-metal main loop can spin much faster than the PC can complete
 * connect/write operations.
 */
#define C2837X_BLOCK_STATE_TIMEOUT_TICKS  1000000000u
#define C2837X_BLOCK_FRAME_TIMEOUT_TICKS  1000000000u

static void c2837x_block_disconnect(C2837xBlock* ctx);

static inline Uint32 c2837x_block_now(const C2837xBlock* ctx)
{
    return ctx->tick_counter;
}

static inline void c2837x_block_tick(C2837xBlock* ctx)
{
    ctx->tick_counter++;
}

static inline int16 c2837x_block_timed_out(const C2837xBlock* ctx,
                                           Uint32 start_tick,
                                           Uint32 timeout_ticks)
{
    if (start_tick < timeout_ticks)
    {
        return (c2837x_block_now(ctx) >= (start_tick + timeout_ticks)) ? 1 : 0;
    }
    else
    {
        return (c2837x_block_now(ctx) < (start_tick - timeout_ticks)) ? 1 : 0;
    }
}

static inline void c2837x_block_set_state(C2837xBlock* ctx,
                                    C2837xBlock_State state)
{
    ctx->state = state;
}

static inline void c2837x_block_reset_rx(C2837xBlock* ctx)
{
    ctx->rx_state = C2837X_RX_WAIT_HEADER;
    ctx->rx_header_received_bytes = 0;
    ctx->rx_payload_received_bytes = 0;
    ctx->rx_msg_type = 0;
    ctx->rx_payload_length_bytes = 0;
}

static inline void c2837x_block_reset_tx(C2837xBlock* ctx)
{
    ctx->tx_total_bytes = 0;
    ctx->tx_sent_bytes = 0;
}

static inline void c2837x_block_reset_session(C2837xBlock* ctx)
{
    c2837x_block_reset_rx(ctx);
    c2837x_block_reset_tx(ctx);
    ctx->expected_step_index = 0;
    ctx->tx_done_action = C2837X_TX_DONE_DISCONNECT;
    ctx->sim_started = 0;
    ctx->response_error = C2837X_ERR_OK;
}

static inline void c2837x_block_start_tx(C2837xBlock* ctx,
                                   Uint32 total_wire_bytes)
{
    ctx->tx_total_bytes = total_wire_bytes;
    ctx->tx_sent_bytes = 0;
    c2837x_block_set_state(ctx, C2837X_STATE_SEND);
    ctx->frame_start_tick = c2837x_block_now(ctx);
}

static inline void c2837x_block_start_rx(C2837xBlock* ctx)
{
    c2837x_block_reset_rx(ctx);

    c2837x_block_set_state(ctx, C2837X_STATE_RECV);
    ctx->frame_start_tick = c2837x_block_now(ctx);
}

static inline int16 c2837x_block_tx_pending(const C2837xBlock* ctx)
{
    return (ctx->tx_sent_bytes < ctx->tx_total_bytes) ? 1 : 0;
}

static inline void c2837x_block_start_error_response(C2837xBlock* ctx,
                                               Uint16 error_code)
{
    Uint32 frame_bytes;

    ctx->response_error = error_code;
    ctx->tx_done_action = C2837X_TX_DONE_DISCONNECT;
    frame_bytes = c2837x_block_build_response(ctx->tx_frame_words,
                                               error_code);
    c2837x_block_start_tx(ctx, frame_bytes);
}

static int16 c2837x_block_continue_tx(C2837xBlock* ctx)
{
    Uint32 remaining_bytes;
    Uint32 offset_words;
    int32 sent_bytes;

    if (!c2837x_block_tx_pending(ctx))
        return 1;

    remaining_bytes = ctx->tx_total_bytes - ctx->tx_sent_bytes;
    offset_words = ctx->tx_sent_bytes / 2u;

    sent_bytes = ctx->iodevice_ops->send(
        ctx->iodevice_channel,
        &ctx->tx_frame_words[offset_words],
        remaining_bytes);
    if (sent_bytes < 0)
        return -1;

    if (sent_bytes == 0)
    {
        if (c2837x_block_timed_out(ctx, ctx->frame_start_tick,
                                    C2837X_BLOCK_FRAME_TIMEOUT_TICKS))
        {
            ctx->last_error = C2837X_BLOCK_ERROR_TIMEOUT;
            return -1;
        }
        return 0;
    }

    ctx->frame_start_tick = c2837x_block_now(ctx);
    ctx->tx_sent_bytes += (Uint32)sent_bytes;
    return c2837x_block_tx_pending(ctx) ? 0 : 1;
}

static int16 c2837x_block_continue_rx(C2837xBlock* ctx)
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

    received_bytes = ctx->iodevice_ops->receive(
        ctx->iodevice_channel,
        data_words,
        needed_bytes);

    if (received_bytes < 0)
    {
        ctx->last_error = C2837X_BLOCK_ERROR_IODEVICE;
        return -1;
    }
    else if (received_bytes == 0)
    {
        if (c2837x_block_timed_out(ctx, ctx->frame_start_tick,
                                    C2837X_BLOCK_FRAME_TIMEOUT_TICKS))
        {
            ctx->last_error = C2837X_BLOCK_ERROR_TIMEOUT;
            return -1;
        }
        return 0;
    }

    ctx->frame_start_tick = c2837x_block_now(ctx);

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
            ctx->last_error = C2837X_BLOCK_ERROR_PROTOCOL;
            ctx->response_error = C2837X_ERR_PAYLOAD_LENGTH;
            return -1;
        }

        if (ctx->rx_payload_length_bytes > C2837X_BLOCK_RX_PAYLOAD_SIZE_BYTES)
        {
            ctx->last_error = C2837X_BLOCK_ERROR_PROTOCOL;
            ctx->response_error = C2837X_ERR_PAYLOAD_LENGTH;
            return -1;
        }

        if (ctx->rx_payload_length_bytes == 0u)
        {
            ctx->rx_state = C2837X_RX_PROCESSING;
            return 0;
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

static void c2837x_block_after_tx_done(C2837xBlock* ctx)
{
    C2837xBlock_TxDoneAction action = ctx->tx_done_action;

    ctx->tx_done_action = C2837X_TX_DONE_DISCONNECT;

    if (action == C2837X_TX_DONE_ADVANCE_STEP)
    {
        ctx->expected_step_index++;
        c2837x_block_start_rx(ctx);
    }
    else if (action == C2837X_TX_DONE_START_RX)
    {
        c2837x_block_start_rx(ctx);
    }
    else
    {
        c2837x_block_disconnect(ctx);
    }
}

static void c2837x_block_handle_sim_start(C2837xBlock* ctx)
{
    Uint16 protocol_version;
    Uint32 config_hash;
    Uint32 frame_bytes;

    if (ctx->rx_payload_length_bytes != C2837X_BLOCK_SIM_START_PAYLOAD_SIZE_BYTES)
    {
        ctx->last_error = C2837X_BLOCK_ERROR_PROTOCOL;
        c2837x_block_start_error_response(ctx, C2837X_ERR_PAYLOAD_LENGTH);
        return;
    }

    protocol_version = ctx->rx_payload_words[0];
    config_hash = (Uint32)ctx->rx_payload_words[1] |
                  ((Uint32)ctx->rx_payload_words[2] << 16);

    if (protocol_version != C2837X_BLOCK_PROTOCOL_VERSION)
    {
        ctx->last_error = C2837X_BLOCK_ERROR_PROTOCOL;
        c2837x_block_start_error_response(ctx,
                                           C2837X_ERR_PROTOCOL_VERSION);
        return;
    }

    if (config_hash != C2837X_BLOCK_CONFIG_HASH)
    {
        ctx->last_error = C2837X_BLOCK_ERROR_PROTOCOL;
        c2837x_block_start_error_response(ctx,
                                           C2837X_ERR_CONFIG_MISMATCH);
        return;
    }

    if (C2837xBlock_OnSimStart() != 0)
    {
        ctx->last_error = C2837X_BLOCK_ERROR_ALGORITHM_START;
        c2837x_block_start_error_response(ctx, C2837X_ERR_INTERNAL);
        return;
    }

    frame_bytes = c2837x_block_build_response(ctx->tx_frame_words,
                                               C2837X_ERR_OK);
    c2837x_block_start_tx(ctx, frame_bytes);
    ctx->tx_done_action = C2837X_TX_DONE_START_RX;
    ctx->expected_step_index = 0;
    ctx->sim_started = 1;
}

static void c2837x_block_handle_input_data(C2837xBlock* ctx)
{
    Uint32 step_index;
    Uint32 frame_bytes;

    if (ctx->rx_payload_length_bytes != C2837X_BLOCK_INPUT_PAYLOAD_SIZE_BYTES)
    {
        ctx->last_error = C2837X_BLOCK_ERROR_PROTOCOL;
        c2837x_block_start_error_response(ctx, C2837X_ERR_PAYLOAD_LENGTH);
        return;
    }

    c2837x_block_unpack_input_payload(ctx->rx_payload_words, &step_index);

    if (step_index != ctx->expected_step_index)
    {
        ctx->last_error = C2837X_BLOCK_ERROR_PROTOCOL;
        c2837x_block_start_error_response(ctx, C2837X_ERR_STEP_INDEX);
        return;
    }

    if (C2837xBlock_OnStep() != 0)
    {
        ctx->last_error = C2837X_BLOCK_ERROR_ALGORITHM_STEP;
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
    ctx->tx_done_action = C2837X_TX_DONE_ADVANCE_STEP;
}

static void c2837x_block_handle_sim_stop(C2837xBlock* ctx)
{
    if (ctx->rx_payload_length_bytes != 0u)
    {
        ctx->last_error = C2837X_BLOCK_ERROR_PROTOCOL;
        c2837x_block_start_error_response(ctx, C2837X_ERR_PAYLOAD_LENGTH);
        return;
    }

    C2837xBlock_OnSimStop();
    ctx->sim_started = 0;
    ctx->last_error = C2837X_BLOCK_ERROR_NONE;

    c2837x_block_disconnect(ctx);
}

static void c2837x_block_dispatch_message(C2837xBlock* ctx)
{
    if ((ctx->rx_msg_type == C2837X_MSG_SIM_START) &&
        (ctx->sim_started != 0u))
    {
        ctx->last_error = C2837X_BLOCK_ERROR_PROTOCOL;
        c2837x_block_start_error_response(ctx, C2837X_ERR_STATE);
        return;
    }

    if (((ctx->rx_msg_type == C2837X_MSG_INPUT_DATA) ||
         (ctx->rx_msg_type == C2837X_MSG_SIM_STOP)) &&
        (ctx->sim_started == 0u))
    {
        ctx->last_error = C2837X_BLOCK_ERROR_PROTOCOL;
        c2837x_block_start_error_response(ctx, C2837X_ERR_STATE);
        return;
    }

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
        ctx->last_error = C2837X_BLOCK_ERROR_PROTOCOL;
        c2837x_block_start_error_response(ctx, C2837X_ERR_UNKNOWN_TYPE);
        break;
    }
}

static inline void c2837x_block_disconnect(C2837xBlock* ctx)
{
    if (ctx->sim_started != 0u)
    {
        C2837xBlock_OnSimStop();
        ctx->sim_started = 0;
    }

    if (ctx->iodevice_ops->close(ctx->iodevice_channel) < 0)
        ctx->last_error = C2837X_BLOCK_ERROR_IODEVICE;
    c2837x_block_reset_session(ctx);
}

static inline void c2837x_block_accept_connection(C2837xBlock* ctx)
{
    c2837x_block_reset_session(ctx);
    c2837x_block_start_rx(ctx);
}

static void c2837x_block_service_running(C2837xBlock* ctx)
{
    c2837x_block_tick(ctx);
    if (ctx->state == C2837X_STATE_RECV)
    {
        int16 rx_result = c2837x_block_continue_rx(ctx);

        if (rx_result < 0)
        {
            if (ctx->response_error != C2837X_ERR_OK)
            {
                c2837x_block_start_error_response(ctx, ctx->response_error);
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
                if (ctx->last_error == C2837X_BLOCK_ERROR_NONE)
                    ctx->last_error = C2837X_BLOCK_ERROR_IODEVICE;
                c2837x_block_disconnect(ctx);
                return;
            }

            if (tx_result == 0)
                return;

            c2837x_block_after_tx_done(ctx);
        }
    }
}

void C2837xBlock_Init(C2837xBlock* instance)
{
    const C2837xBlock_IoDeviceOps *ops;
    void *channel;

    if (instance == NULL)
        return;

    ops = instance->iodevice_ops;
    channel = instance->iodevice_channel;
    memset(instance, 0, sizeof(*instance));
    instance->iodevice_ops = ops;
    instance->iodevice_channel = channel;
    instance->last_error = C2837X_BLOCK_ERROR_NONE;
    c2837x_block_reset_session(instance);
    if ((ops != NULL) && (channel != NULL))
        ops->channel_init(channel);
}

void C2837xBlock_Run(C2837xBlock* instance)
{
    C2837xBlock_IoConnectionState connection_state;

    if (instance == NULL)
        return;

    if ((instance->iodevice_ops == NULL) ||
        (instance->iodevice_channel == NULL))
    {
        instance->last_error = C2837X_BLOCK_ERROR_IODEVICE;
        return;
    }

    connection_state = instance->iodevice_ops->get_connection_state(
        instance->iodevice_channel);
    switch (connection_state)
    {
    case C2837X_IODEVICE_CONNECTION_OPEN:
        if (instance->iodevice_ops->listen(instance->iodevice_channel) < 0)
            instance->last_error = C2837X_BLOCK_ERROR_IODEVICE;
        instance->first_connected = 0;
        break;
    case C2837X_IODEVICE_CONNECTION_CONNECTED:
        if (instance->first_connected == 0u)
        {
            instance->first_connected = 1u;
            c2837x_block_accept_connection(instance);
        }
        c2837x_block_service_running(instance);
        break;
    case C2837X_IODEVICE_CONNECTION_PEER_CLOSED:
        instance->last_error = C2837X_BLOCK_ERROR_DISCONNECTED;
        if (instance->iodevice_ops->close(instance->iodevice_channel) < 0)
            instance->last_error = C2837X_BLOCK_ERROR_IODEVICE;
        break;
    case C2837X_IODEVICE_CONNECTION_CLOSED:
        if (instance->iodevice_ops->open(instance->iodevice_channel) < 0)
            instance->last_error = C2837X_BLOCK_ERROR_IODEVICE;
        break;
    case C2837X_IODEVICE_CONNECTION_ERROR:
        instance->last_error = C2837X_BLOCK_ERROR_IODEVICE;
        break;
    case C2837X_IODEVICE_CONNECTION_LISTENING:
        break;
    default:
        break;
    }
}

C2837xBlock_Error C2837xBlock_GetLastError(const C2837xBlock* instance)
{
    return (instance != NULL) ? instance->last_error
                              : C2837X_BLOCK_ERROR_INVALID_ARGUMENT;
}

void c2837x_block_bind_iodevice(C2837xBlock *instance,
                                const C2837xBlock_IoDeviceOps *ops,
                                void *channel)
{
    if (instance == NULL)
        return;
    instance->iodevice_ops = ops;
    instance->iodevice_channel = channel;
}
