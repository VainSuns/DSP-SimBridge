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

#define C2837X_BLOCK_EXPECTED_CORE_API_VERSION 1u
#include "c2837x_block.h"
#include "c2837x_block_internal.h"
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

static int16 c2837x_block_config_is_valid(const C2837xBlock_Config *config)
{
    const C2837xBlock_IoDeviceOps *ops;
    const C2837xBlock_AlgorithmAdapter *algorithm;
    Uint32 minimum_tx_octets;

    if ((config == NULL) || (config->iodevice_ops == NULL) ||
        (config->iodevice_channel == NULL) ||
        (config->rx_frame_words == NULL) || (config->tx_frame_words == NULL) ||
        (config->input_object == NULL) || (config->output_object == NULL) ||
        (config->algorithm == NULL))
        return 0;

    ops = config->iodevice_ops;
    algorithm = config->algorithm;
    if ((ops->channel_init == NULL) || (ops->open == NULL) ||
        (ops->listen == NULL) || (ops->get_connection_state == NULL) ||
        (ops->receive == NULL) || (ops->send == NULL) ||
        (ops->close == NULL) || (algorithm->reset_io == NULL) ||
        (algorithm->on_start == NULL) || (algorithm->decode_input == NULL) ||
        (algorithm->on_step == NULL) || (algorithm->encode_output == NULL) ||
        (algorithm->on_stop == NULL))
        return 0;

    if (((config->rx_frame_capacity_octets & 1u) != 0u) ||
        ((config->tx_frame_capacity_octets & 1u) != 0u) ||
        ((config->input_payload_octets & 1u) != 0u) ||
        ((config->output_payload_octets & 1u) != 0u) ||
        ((config->max_payload_octets & 1u) != 0u) ||
        (config->input_payload_octets < 4u) ||
        (config->output_payload_octets < 4u) ||
        (config->max_payload_octets < C2837X_BLOCK_SIM_START_PAYLOAD_SIZE_BYTES) ||
        (config->input_payload_octets > config->max_payload_octets) ||
        (config->output_payload_octets > config->max_payload_octets) ||
        (config->rx_frame_capacity_octets <
            ((Uint32)C2837X_BLOCK_HEADER_SIZE_BYTES +
             (Uint32)config->max_payload_octets)))
        return 0;

    minimum_tx_octets = (Uint32)C2837X_BLOCK_HEADER_SIZE_BYTES +
        ((config->output_payload_octets > C2837X_BLOCK_RESPONSE_PAYLOAD_SIZE_BYTES)
            ? config->output_payload_octets
            : C2837X_BLOCK_RESPONSE_PAYLOAD_SIZE_BYTES);
    if ((config->tx_frame_capacity_octets < minimum_tx_octets) ||
        (config->interaction_timeout_us == 0u) ||
        (config->interaction_timeout_us >= 0x80000000u) ||
        (config->transfer_timeout_us == 0u) ||
        (config->transfer_timeout_us >= 0x80000000u))
        return 0;

    return 1;
}

static inline Uint32 c2837x_block_now(const C2837xBlock* ctx)
{
    return ctx->runtime.tick_counter;
}

static inline void c2837x_block_tick(C2837xBlock* ctx)
{
    ctx->runtime.tick_counter++;
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
    ctx->runtime.state = state;
}

static inline void c2837x_block_reset_rx(C2837xBlock* ctx)
{
    C2837xBlock_Runtime *runtime = &ctx->runtime;
    runtime->rx_state = C2837X_RX_WAIT_HEADER;
    runtime->rx_header_received_bytes = 0;
    runtime->rx_payload_received_bytes = 0;
    runtime->rx_msg_type = 0;
    runtime->rx_payload_length_bytes = 0;
}

static inline void c2837x_block_reset_tx(C2837xBlock* ctx)
{
    ctx->runtime.tx_total_bytes = 0;
    ctx->runtime.tx_sent_bytes = 0;
}

static inline void c2837x_block_reset_session(C2837xBlock* ctx)
{
    c2837x_block_reset_rx(ctx);
    c2837x_block_reset_tx(ctx);
    ctx->runtime.expected_step_index = 0;
    ctx->runtime.tx_done_action = C2837X_TX_DONE_DISCONNECT;
    ctx->runtime.sim_started = 0;
    ctx->runtime.response_error = C2837X_ERR_OK;
}

static inline void c2837x_block_start_tx(C2837xBlock* ctx,
                                   Uint32 total_wire_bytes)
{
    ctx->runtime.tx_total_bytes = total_wire_bytes;
    ctx->runtime.tx_sent_bytes = 0;
    c2837x_block_set_state(ctx, C2837X_STATE_SEND);
    ctx->runtime.frame_start_tick = c2837x_block_now(ctx);
}

static inline void c2837x_block_start_rx(C2837xBlock* ctx)
{
    c2837x_block_reset_rx(ctx);

    c2837x_block_set_state(ctx, C2837X_STATE_RECV);
    ctx->runtime.frame_start_tick = c2837x_block_now(ctx);
}

static inline int16 c2837x_block_tx_pending(const C2837xBlock* ctx)
{
    return (ctx->runtime.tx_sent_bytes < ctx->runtime.tx_total_bytes) ? 1 : 0;
}

static inline void c2837x_block_start_error_response(C2837xBlock* ctx,
                                               Uint16 error_code)
{
    Uint32 frame_bytes;

    ctx->runtime.response_error = error_code;
    ctx->runtime.tx_done_action = C2837X_TX_DONE_DISCONNECT;
    frame_bytes = c2837x_block_build_response(ctx->config->tx_frame_words,
                                               error_code);
    c2837x_block_start_tx(ctx, frame_bytes);
}

static int16 c2837x_block_continue_tx(C2837xBlock* ctx)
{
    C2837xBlock_Runtime *runtime = &ctx->runtime;
    Uint32 remaining_bytes;
    Uint32 offset_words;
    int32 sent_bytes;

    if (!c2837x_block_tx_pending(ctx))
        return 1;

    remaining_bytes = runtime->tx_total_bytes - runtime->tx_sent_bytes;
    offset_words = runtime->tx_sent_bytes / 2u;

    sent_bytes = ctx->config->iodevice_ops->send(
        ctx->config->iodevice_channel,
        &ctx->config->tx_frame_words[offset_words],
        remaining_bytes);
    if (sent_bytes < 0)
        return -1;

    if (sent_bytes == 0)
    {
        if (c2837x_block_timed_out(ctx, runtime->frame_start_tick,
                                    C2837X_BLOCK_FRAME_TIMEOUT_TICKS))
        {
            runtime->last_error = C2837X_BLOCK_ERROR_TIMEOUT;
            return -1;
        }
        return 0;
    }

    if ((((Uint32)sent_bytes & 1u) != 0u) ||
        ((Uint32)sent_bytes > remaining_bytes))
    {
        runtime->last_error = C2837X_BLOCK_ERROR_IODEVICE;
        return -1;
    }

    runtime->frame_start_tick = c2837x_block_now(ctx);
    runtime->tx_sent_bytes += (Uint32)sent_bytes;
    return c2837x_block_tx_pending(ctx) ? 0 : 1;
}

static int16 c2837x_block_continue_rx(C2837xBlock* ctx)
{
    C2837xBlock_Runtime *runtime = &ctx->runtime;
    int32 received_bytes;
    Uint16* data_words;
    Uint32 needed_bytes;
    
    if (runtime->rx_state == C2837X_RX_WAIT_HEADER)
    {
        needed_bytes =
            C2837X_BLOCK_HEADER_SIZE_BYTES - runtime->rx_header_received_bytes;
        Uint32 offset_words = runtime->rx_header_received_bytes / 2u;
        data_words = &ctx->config->rx_frame_words[offset_words];
    }
    else if (runtime->rx_state == C2837X_RX_WAIT_PAYLOAD)
    {
        needed_bytes =
            (Uint32)runtime->rx_payload_length_bytes -
            runtime->rx_payload_received_bytes;
        Uint32 offset_words = (C2837X_BLOCK_HEADER_SIZE_BYTES +
            runtime->rx_payload_received_bytes) / 2u;
        data_words = &ctx->config->rx_frame_words[offset_words];
    }
    else
    {
        return 0;
    }

    received_bytes = ctx->config->iodevice_ops->receive(
        ctx->config->iodevice_channel,
        data_words,
        needed_bytes);

    if (received_bytes < 0)
    {
        runtime->last_error = C2837X_BLOCK_ERROR_IODEVICE;
        return -1;
    }
    else if (received_bytes == 0)
    {
        if (c2837x_block_timed_out(ctx, runtime->frame_start_tick,
                                    C2837X_BLOCK_FRAME_TIMEOUT_TICKS))
        {
            runtime->last_error = C2837X_BLOCK_ERROR_TIMEOUT;
            return -1;
        }
        return 0;
    }

    if ((((Uint32)received_bytes & 1u) != 0u) ||
        ((Uint32)received_bytes > needed_bytes))
    {
        runtime->last_error = C2837X_BLOCK_ERROR_IODEVICE;
        return -1;
    }

    runtime->frame_start_tick = c2837x_block_now(ctx);

    if (runtime->rx_state == C2837X_RX_WAIT_HEADER)
    {
        runtime->rx_header_received_bytes += (Uint32)received_bytes;

        if (runtime->rx_header_received_bytes < C2837X_BLOCK_HEADER_SIZE_BYTES)
        {
            return 0;
        }

        if (c2837x_block_parse_header(ctx->config->rx_frame_words,
                                       &runtime->rx_msg_type,
                                       &runtime->rx_payload_length_bytes) < 0)
        {
            runtime->last_error = C2837X_BLOCK_ERROR_PROTOCOL;
            runtime->response_error = C2837X_ERR_PAYLOAD_LENGTH;
            return -1;
        }

        if (runtime->rx_payload_length_bytes > ctx->config->max_payload_octets)
        {
            runtime->last_error = C2837X_BLOCK_ERROR_PROTOCOL;
            runtime->response_error = C2837X_ERR_PAYLOAD_LENGTH;
            return -1;
        }

        if (runtime->rx_payload_length_bytes == 0u)
        {
            runtime->rx_state = C2837X_RX_PROCESSING;
            return 0;
        }

        runtime->rx_state = C2837X_RX_WAIT_PAYLOAD;
        runtime->rx_payload_received_bytes = 0;
        
        return 0;
    }

    if (runtime->rx_state == C2837X_RX_WAIT_PAYLOAD)
    {
        runtime->rx_payload_received_bytes += (Uint32)received_bytes;
        if (runtime->rx_payload_received_bytes >=
            (Uint32)runtime->rx_payload_length_bytes)
        {
            runtime->rx_state = C2837X_RX_PROCESSING;
            return 0;
        }
    }

    return 0;
}

static void c2837x_block_after_tx_done(C2837xBlock* ctx)
{
    C2837xBlock_TxDoneAction action = ctx->runtime.tx_done_action;

    ctx->runtime.tx_done_action = C2837X_TX_DONE_DISCONNECT;

    if (action == C2837X_TX_DONE_ADVANCE_STEP)
    {
        ctx->runtime.expected_step_index++;
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
    C2837xBlock_Runtime *runtime = &ctx->runtime;
    const C2837xBlock_Config *config = ctx->config;
    const Uint16 *payload_words = &config->rx_frame_words[2];
    Uint16 protocol_version;
    Uint32 config_hash;
    Uint32 frame_bytes;

    if (runtime->rx_payload_length_bytes !=
        C2837X_BLOCK_SIM_START_PAYLOAD_SIZE_BYTES)
    {
        runtime->last_error = C2837X_BLOCK_ERROR_PROTOCOL;
        c2837x_block_start_error_response(ctx, C2837X_ERR_PAYLOAD_LENGTH);
        return;
    }

    protocol_version = payload_words[0];
    config_hash = (Uint32)payload_words[1] |
                  ((Uint32)payload_words[2] << 16);

    if (protocol_version != config->protocol_version)
    {
        runtime->last_error = C2837X_BLOCK_ERROR_PROTOCOL;
        c2837x_block_start_error_response(ctx,
                                           C2837X_ERR_PROTOCOL_VERSION);
        return;
    }

    if (config_hash != config->interface_hash)
    {
        runtime->last_error = C2837X_BLOCK_ERROR_PROTOCOL;
        c2837x_block_start_error_response(ctx,
                                           C2837X_ERR_CONFIG_MISMATCH);
        return;
    }

    if (config->algorithm->on_start(config->algorithm_context) != 0)
    {
        runtime->last_error = C2837X_BLOCK_ERROR_ALGORITHM_START;
        c2837x_block_start_error_response(ctx, C2837X_ERR_INTERNAL);
        return;
    }

    frame_bytes = c2837x_block_build_response(config->tx_frame_words,
                                               C2837X_ERR_OK);
    c2837x_block_start_tx(ctx, frame_bytes);
    runtime->tx_done_action = C2837X_TX_DONE_START_RX;
    runtime->expected_step_index = 0;
    runtime->sim_started = 1;
}

static void c2837x_block_handle_input_data(C2837xBlock* ctx)
{
    C2837xBlock_Runtime *runtime = &ctx->runtime;
    const C2837xBlock_Config *config = ctx->config;
    const Uint16 *payload_words = &config->rx_frame_words[2];
    Uint16 *tx_words = config->tx_frame_words;
    Uint32 step_index;

    if (runtime->rx_payload_length_bytes != config->input_payload_octets)
    {
        runtime->last_error = C2837X_BLOCK_ERROR_PROTOCOL;
        c2837x_block_start_error_response(ctx, C2837X_ERR_PAYLOAD_LENGTH);
        return;
    }

    step_index = (Uint32)payload_words[0] | ((Uint32)payload_words[1] << 16);

    if (step_index != runtime->expected_step_index)
    {
        runtime->last_error = C2837X_BLOCK_ERROR_PROTOCOL;
        c2837x_block_start_error_response(ctx, C2837X_ERR_STEP_INDEX);
        return;
    }

    if (config->algorithm->decode_input(
            config->algorithm_context,
            config->input_object,
            &payload_words[2],
            (Uint16)(config->input_payload_octets - 4u)) != 0)
    {
        runtime->last_error = C2837X_BLOCK_ERROR_INTERNAL;
        c2837x_block_start_error_response(ctx, C2837X_ERR_INTERNAL);
        return;
    }

    if (config->algorithm->on_step(config->algorithm_context,
            config->input_object, config->output_object) != 0)
    {
        runtime->last_error = C2837X_BLOCK_ERROR_ALGORITHM_STEP;
        c2837x_block_start_error_response(ctx, C2837X_ERR_INTERNAL);
        return;
    }

    tx_words[0] = C2837X_MSG_OUTPUT_DATA;
    tx_words[1] = config->output_payload_octets;
    tx_words[2] = (Uint16)(step_index & 0xFFFFu);
    tx_words[3] = (Uint16)(step_index >> 16);
    if (config->algorithm->encode_output(
            config->algorithm_context,
            config->output_object,
            &tx_words[4],
            (Uint16)(config->output_payload_octets - 4u)) != 0)
    {
        runtime->last_error = C2837X_BLOCK_ERROR_INTERNAL;
        c2837x_block_start_error_response(ctx, C2837X_ERR_INTERNAL);
        return;
    }

    c2837x_block_start_tx(ctx, C2837X_BLOCK_HEADER_SIZE_BYTES +
        config->output_payload_octets);
    runtime->tx_done_action = C2837X_TX_DONE_ADVANCE_STEP;
}

static void c2837x_block_handle_sim_stop(C2837xBlock* ctx)
{
    if (ctx->runtime.rx_payload_length_bytes != 0u)
    {
        ctx->runtime.last_error = C2837X_BLOCK_ERROR_PROTOCOL;
        c2837x_block_start_error_response(ctx, C2837X_ERR_PAYLOAD_LENGTH);
        return;
    }

    ctx->config->algorithm->on_stop(ctx->config->algorithm_context);
    ctx->runtime.sim_started = 0;
    ctx->runtime.last_error = C2837X_BLOCK_ERROR_NONE;

    c2837x_block_disconnect(ctx);
}

static void c2837x_block_dispatch_message(C2837xBlock* ctx)
{
    C2837xBlock_Runtime *runtime = &ctx->runtime;

    if ((runtime->rx_msg_type == C2837X_MSG_SIM_START) &&
        (runtime->sim_started != 0u))
    {
        runtime->last_error = C2837X_BLOCK_ERROR_PROTOCOL;
        c2837x_block_start_error_response(ctx, C2837X_ERR_STATE);
        return;
    }

    if (((runtime->rx_msg_type == C2837X_MSG_INPUT_DATA) ||
         (runtime->rx_msg_type == C2837X_MSG_SIM_STOP)) &&
        (runtime->sim_started == 0u))
    {
        runtime->last_error = C2837X_BLOCK_ERROR_PROTOCOL;
        c2837x_block_start_error_response(ctx, C2837X_ERR_STATE);
        return;
    }

    switch (runtime->rx_msg_type)
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
        runtime->last_error = C2837X_BLOCK_ERROR_PROTOCOL;
        c2837x_block_start_error_response(ctx, C2837X_ERR_UNKNOWN_TYPE);
        break;
    }
}

static inline void c2837x_block_disconnect(C2837xBlock* ctx)
{
    if (ctx->runtime.sim_started != 0u)
    {
        ctx->config->algorithm->on_stop(ctx->config->algorithm_context);
        ctx->runtime.sim_started = 0;
    }

    if (ctx->config->iodevice_ops->close(ctx->config->iodevice_channel) < 0)
        ctx->runtime.last_error = C2837X_BLOCK_ERROR_IODEVICE;
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
    if (ctx->runtime.state == C2837X_STATE_RECV)
    {
        int16 rx_result = c2837x_block_continue_rx(ctx);

        if (rx_result < 0)
        {
            if (ctx->runtime.response_error != C2837X_ERR_OK)
            {
                c2837x_block_start_error_response(ctx,
                    ctx->runtime.response_error);
            }
            else
            {
                c2837x_block_disconnect(ctx);
            }
            return;
        }

        if (ctx->runtime.rx_state == C2837X_RX_PROCESSING)
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
                if (ctx->runtime.last_error == C2837X_BLOCK_ERROR_NONE)
                    ctx->runtime.last_error = C2837X_BLOCK_ERROR_IODEVICE;
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
    if (instance == NULL)
        return;

    memset(&instance->runtime, 0, sizeof(instance->runtime));
    if (!c2837x_block_config_is_valid(instance->config))
    {
        instance->runtime.last_error = C2837X_BLOCK_ERROR_INVALID_ARGUMENT;
        return;
    }

    instance->runtime.last_error = C2837X_BLOCK_ERROR_NONE;
    c2837x_block_reset_session(instance);
    instance->config->iodevice_ops->channel_init(
        instance->config->iodevice_channel);
    instance->config->algorithm->reset_io(
        instance->config->algorithm_context,
        instance->config->input_object,
        instance->config->output_object);
}

void C2837xBlock_Run(C2837xBlock* instance)
{
    C2837xBlock_IoConnectionState connection_state;

    if (instance == NULL)
        return;

    if (!c2837x_block_config_is_valid(instance->config))
    {
        instance->runtime.last_error = C2837X_BLOCK_ERROR_INVALID_ARGUMENT;
        return;
    }

    connection_state = instance->config->iodevice_ops->get_connection_state(
        instance->config->iodevice_channel);
    switch (connection_state)
    {
    case C2837X_IODEVICE_CONNECTION_OPEN:
        if (instance->config->iodevice_ops->listen(
                instance->config->iodevice_channel) < 0)
            instance->runtime.last_error = C2837X_BLOCK_ERROR_IODEVICE;
        instance->runtime.first_connected = 0;
        break;
    case C2837X_IODEVICE_CONNECTION_CONNECTED:
        if (instance->runtime.first_connected == 0u)
        {
            instance->runtime.first_connected = 1u;
            c2837x_block_accept_connection(instance);
        }
        c2837x_block_service_running(instance);
        break;
    case C2837X_IODEVICE_CONNECTION_PEER_CLOSED:
        instance->runtime.last_error = C2837X_BLOCK_ERROR_DISCONNECTED;
        if (instance->config->iodevice_ops->close(
                instance->config->iodevice_channel) < 0)
            instance->runtime.last_error = C2837X_BLOCK_ERROR_IODEVICE;
        break;
    case C2837X_IODEVICE_CONNECTION_CLOSED:
        if (instance->config->iodevice_ops->open(
                instance->config->iodevice_channel) < 0)
            instance->runtime.last_error = C2837X_BLOCK_ERROR_IODEVICE;
        break;
    case C2837X_IODEVICE_CONNECTION_ERROR:
        instance->runtime.last_error = C2837X_BLOCK_ERROR_IODEVICE;
        break;
    case C2837X_IODEVICE_CONNECTION_LISTENING:
        break;
    default:
        break;
    }
}

C2837xBlock_Error C2837xBlock_GetLastError(const C2837xBlock* instance)
{
    return (instance != NULL) ? instance->runtime.last_error
                              : C2837X_BLOCK_ERROR_INVALID_ARGUMENT;
}
