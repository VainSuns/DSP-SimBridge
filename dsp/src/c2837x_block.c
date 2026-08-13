/* Device-independent, non-blocking C2837xBlock protocol Core. */

#define C2837X_BLOCK_EXPECTED_CORE_API_VERSION 2u
#include "c2837x_block.h"
#include "c2837x_block_internal.h"
#include "c2837x_block_protocol.h"
#include <string.h>

typedef enum
{
    C2837X_BLOCK_HEADER_VALID = 0,
    C2837X_BLOCK_HEADER_UNKNOWN_TYPE,
    C2837X_BLOCK_HEADER_STATE_ERROR,
    C2837X_BLOCK_HEADER_LENGTH_ERROR
} C2837xBlock_HeaderResult;

typedef enum
{
    C2837X_BLOCK_TERMINATE_ERROR = 0,
    C2837X_BLOCK_TERMINATE_NORMAL
} C2837xBlock_TerminationKind;

static Uint32 c2837x_block_maximum_inbound_payload_octets(
    const C2837xBlock_Config *config)
{
    return (config->input_payload_octets >
            C2837X_BLOCK_SIM_START_PAYLOAD_SIZE_BYTES)
        ? config->input_payload_octets
        : C2837X_BLOCK_SIM_START_PAYLOAD_SIZE_BYTES;
}

static int16 c2837x_block_config_is_valid(const C2837xBlock_Config *config)
{
    const C2837xBlock_IoDeviceOps *ops;
    const C2837xBlock_AlgorithmAdapter *algorithm;
    Uint32 minimum_rx_octets;
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
        (config->output_payload_octets > config->max_payload_octets))
        return 0;

    minimum_rx_octets = (Uint32)C2837X_BLOCK_HEADER_SIZE_BYTES +
        c2837x_block_maximum_inbound_payload_octets(config);
    minimum_tx_octets = (Uint32)C2837X_BLOCK_HEADER_SIZE_BYTES +
        ((config->output_payload_octets > C2837X_BLOCK_RESPONSE_PAYLOAD_SIZE_BYTES)
            ? config->output_payload_octets
            : C2837X_BLOCK_RESPONSE_PAYLOAD_SIZE_BYTES);
    if ((config->rx_frame_capacity_octets < minimum_rx_octets) ||
        (config->tx_frame_capacity_octets < minimum_tx_octets) ||
        (config->time_us == NULL) ||
        (config->interaction_timeout_us == 0u) ||
        (config->interaction_timeout_us >= 0x80000000u) ||
        (config->transfer_timeout_us == 0u) ||
        (config->transfer_timeout_us >= 0x80000000u))
        return 0;

    return 1;
}

static void c2837x_block_latch_error(C2837xBlock *ctx,
                                     C2837xBlock_Error error)
{
    if (ctx->runtime.primary_error_latched == 0u)
    {
        ctx->runtime.last_error = error;
        ctx->runtime.primary_error_latched = 1u;
    }
}

static int16 c2837x_block_timeout_expired(const C2837xBlock *ctx,
                                           Uint32 start_us,
                                           Uint32 timeout_us)
{
    Uint32 now_us = ctx->config->time_us();
    Uint32 elapsed_us = now_us - start_us;

    return (elapsed_us >= timeout_us) ? 1 : 0;
}

static void c2837x_block_reset_rx(C2837xBlock *ctx)
{
    C2837xBlock_Runtime *runtime = &ctx->runtime;
    runtime->rx_phase = C2837X_BLOCK_RX_HEADER;
    runtime->rx_header_received_octets = 0u;
    runtime->rx_msg_type = 0u;
    runtime->rx_payload_length_octets = 0u;
    runtime->rx_payload_received_octets = 0u;
}

static void c2837x_block_reset_tx(C2837xBlock *ctx)
{
    ctx->runtime.tx_total_octets = 0u;
    ctx->runtime.tx_sent_octets = 0u;
    ctx->runtime.response_error = C2837X_ERR_OK;
    ctx->runtime.tx_done_action = C2837X_BLOCK_TX_DONE_CLOSE;
}

static void c2837x_block_start_receiving(C2837xBlock *ctx,
                                          C2837xBlock_WaitKind wait_kind,
                                          Uint32 start_us)
{
    c2837x_block_reset_rx(ctx);
    ctx->runtime.receive_wait_kind = wait_kind;
    ctx->runtime.progress_start_us = start_us;
    ctx->runtime.state = C2837X_BLOCK_STATE_RECEIVING;
}

static void c2837x_block_start_sending(C2837xBlock *ctx,
                                       Uint32 total_octets,
                                       C2837xBlock_TxDoneAction action)
{
    ctx->runtime.tx_total_octets = total_octets;
    ctx->runtime.tx_sent_octets = 0u;
    ctx->runtime.tx_done_action = action;
    ctx->runtime.progress_start_us = ctx->config->time_us();
    ctx->runtime.state = C2837X_BLOCK_STATE_SENDING;
}

static void c2837x_block_terminate_session(
    C2837xBlock *ctx, C2837xBlock_TerminationKind kind)
{
    C2837xBlock_Runtime *runtime = &ctx->runtime;

    if (runtime->algorithm_started != 0u)
    {
        ctx->config->algorithm->on_stop(ctx->config->algorithm_context);
        runtime->algorithm_started = 0u;
    }
    ctx->config->algorithm->reset_io(ctx->config->algorithm_context,
                                     ctx->config->input_object,
                                     ctx->config->output_object);
    c2837x_block_reset_rx(ctx);
    c2837x_block_reset_tx(ctx);
    runtime->protocol_phase = C2837X_BLOCK_PROTOCOL_WAIT_SIM_START;
    runtime->expected_step_index = 0u;
    runtime->close_pending = 1u;
    runtime->normal_end_pending =
        (kind == C2837X_BLOCK_TERMINATE_NORMAL) ? 1u : 0u;
    runtime->state = C2837X_BLOCK_STATE_WAIT_CONNECTION;
}

static void c2837x_block_start_error_response(C2837xBlock *ctx,
                                              C2837xBlock_Error primary_error,
                                              Uint16 wire_error)
{
    Uint32 frame_octets;

    c2837x_block_latch_error(ctx, primary_error);
    ctx->runtime.response_error = wire_error;
    frame_octets = c2837x_block_build_response(ctx->config->tx_frame_words,
                                               wire_error);
    c2837x_block_start_sending(ctx, frame_octets,
                               C2837X_BLOCK_TX_DONE_CLOSE);
}

static C2837xBlock_HeaderResult c2837x_block_validate_header(
    C2837xBlock *ctx)
{
    C2837xBlock_Runtime *runtime = &ctx->runtime;
    Uint16 type = ctx->config->rx_frame_words[0];
    Uint16 length = ctx->config->rx_frame_words[1];
    Uint16 expected_length;
    int16 allowed;

    switch (type)
    {
    case C2837X_MSG_SIM_START:
        allowed = (runtime->protocol_phase ==
                   C2837X_BLOCK_PROTOCOL_WAIT_SIM_START) ? 1 : 0;
        expected_length = C2837X_BLOCK_SIM_START_PAYLOAD_SIZE_BYTES;
        break;
    case C2837X_MSG_INPUT_DATA:
        allowed = (runtime->protocol_phase ==
                   C2837X_BLOCK_PROTOCOL_SIM_RUNNING) ? 1 : 0;
        expected_length = ctx->config->input_payload_octets;
        break;
    case C2837X_MSG_SIM_STOP:
        allowed = (runtime->protocol_phase ==
                   C2837X_BLOCK_PROTOCOL_SIM_RUNNING) ? 1 : 0;
        expected_length = 0u;
        break;
    case C2837X_MSG_OUTPUT_DATA:
    case C2837X_MSG_RESPONSE:
        return C2837X_BLOCK_HEADER_STATE_ERROR;
    default:
        return C2837X_BLOCK_HEADER_UNKNOWN_TYPE;
    }

    if (allowed == 0)
        return C2837X_BLOCK_HEADER_STATE_ERROR;

    if (((length & 1u) != 0u) ||
        (length > ctx->config->max_payload_octets) ||
        (((Uint32)C2837X_BLOCK_HEADER_SIZE_BYTES + (Uint32)length) >
         ctx->config->rx_frame_capacity_octets) ||
        (length != expected_length))
        return C2837X_BLOCK_HEADER_LENGTH_ERROR;

    runtime->rx_msg_type = type;
    runtime->rx_payload_length_octets = length;
    return C2837X_BLOCK_HEADER_VALID;
}

static void c2837x_block_handle_header_result(C2837xBlock *ctx,
                                               C2837xBlock_HeaderResult result)
{
    if (result == C2837X_BLOCK_HEADER_UNKNOWN_TYPE)
        c2837x_block_start_error_response(ctx, C2837X_BLOCK_ERROR_PROTOCOL,
                                          C2837X_ERR_UNKNOWN_TYPE);
    else if (result == C2837X_BLOCK_HEADER_STATE_ERROR)
        c2837x_block_start_error_response(ctx, C2837X_BLOCK_ERROR_PROTOCOL,
                                          C2837X_ERR_STATE);
    else if (result == C2837X_BLOCK_HEADER_LENGTH_ERROR)
        c2837x_block_start_error_response(ctx, C2837X_BLOCK_ERROR_PROTOCOL,
                                          C2837X_ERR_PAYLOAD_LENGTH);
}

static void c2837x_block_service_receiving(C2837xBlock *ctx)
{
    C2837xBlock_Runtime *runtime = &ctx->runtime;
    Uint16 *destination;
    Uint32 remaining_octets;
    int32 received_octets;

    if (runtime->rx_phase == C2837X_BLOCK_RX_HEADER)
    {
        remaining_octets = C2837X_BLOCK_HEADER_SIZE_BYTES -
            runtime->rx_header_received_octets;
        destination = &ctx->config->rx_frame_words[
            runtime->rx_header_received_octets / 2u];
    }
    else
    {
        remaining_octets = (Uint32)runtime->rx_payload_length_octets -
            runtime->rx_payload_received_octets;
        destination = &ctx->config->rx_frame_words[
            (C2837X_BLOCK_HEADER_SIZE_BYTES +
             runtime->rx_payload_received_octets) / 2u];
    }

    received_octets = ctx->config->iodevice_ops->receive(
        ctx->config->iodevice_channel, destination, remaining_octets);
    if (received_octets < 0)
    {
        c2837x_block_latch_error(ctx, C2837X_BLOCK_ERROR_IODEVICE);
        c2837x_block_terminate_session(ctx, C2837X_BLOCK_TERMINATE_ERROR);
        return;
    }
    if (received_octets == 0)
    {
        Uint32 timeout_us =
            (runtime->receive_wait_kind == C2837X_BLOCK_WAIT_INTERACTION)
                ? ctx->config->interaction_timeout_us
                : ctx->config->transfer_timeout_us;
        if (c2837x_block_timeout_expired(
                ctx, runtime->progress_start_us, timeout_us) != 0)
        {
            c2837x_block_latch_error(ctx, C2837X_BLOCK_ERROR_TIMEOUT);
            c2837x_block_terminate_session(
                ctx, C2837X_BLOCK_TERMINATE_ERROR);
        }
        return;
    }
    if ((((Uint32)received_octets & 1u) != 0u) ||
        ((Uint32)received_octets > remaining_octets))
    {
        c2837x_block_latch_error(ctx, C2837X_BLOCK_ERROR_IODEVICE);
        c2837x_block_terminate_session(ctx, C2837X_BLOCK_TERMINATE_ERROR);
        return;
    }

    if (runtime->receive_wait_kind == C2837X_BLOCK_WAIT_INTERACTION)
        runtime->receive_wait_kind = C2837X_BLOCK_WAIT_TRANSFER;

    if (runtime->rx_phase == C2837X_BLOCK_RX_HEADER)
    {
        C2837xBlock_HeaderResult result;
        runtime->rx_header_received_octets += (Uint32)received_octets;
        if (runtime->rx_header_received_octets <
            C2837X_BLOCK_HEADER_SIZE_BYTES)
        {
            runtime->progress_start_us = ctx->config->time_us();
            return;
        }

        result = c2837x_block_validate_header(ctx);
        if (result != C2837X_BLOCK_HEADER_VALID)
        {
            c2837x_block_handle_header_result(ctx, result);
            return;
        }
        if (runtime->rx_payload_length_octets == 0u)
            runtime->state = C2837X_BLOCK_STATE_FRAME_READY;
        else
            runtime->rx_phase = C2837X_BLOCK_RX_PAYLOAD;
        runtime->progress_start_us = ctx->config->time_us();
        return;
    }

    runtime->rx_payload_received_octets += (Uint32)received_octets;
    if (runtime->rx_payload_received_octets ==
        (Uint32)runtime->rx_payload_length_octets)
        runtime->state = C2837X_BLOCK_STATE_FRAME_READY;
    runtime->progress_start_us = ctx->config->time_us();
}

static void c2837x_block_handle_sim_start(C2837xBlock *ctx)
{
    C2837xBlock_Runtime *runtime = &ctx->runtime;
    const C2837xBlock_Config *config = ctx->config;
    const Uint16 *payload = &config->rx_frame_words[2];
    Uint32 interface_hash = (Uint32)payload[1] | ((Uint32)payload[2] << 16);
    Uint32 frame_octets;

    if (runtime->protocol_phase != C2837X_BLOCK_PROTOCOL_WAIT_SIM_START)
    {
        c2837x_block_start_error_response(ctx, C2837X_BLOCK_ERROR_PROTOCOL,
                                          C2837X_ERR_STATE);
        return;
    }
    if (payload[0] != config->protocol_version)
    {
        c2837x_block_start_error_response(ctx, C2837X_BLOCK_ERROR_PROTOCOL,
                                          C2837X_ERR_PROTOCOL_VERSION);
        return;
    }
    if (interface_hash != config->interface_hash)
    {
        c2837x_block_start_error_response(ctx, C2837X_BLOCK_ERROR_PROTOCOL,
                                          C2837X_ERR_CONFIG_MISMATCH);
        return;
    }
    if (config->algorithm->on_start(config->algorithm_context) != 0)
    {
        c2837x_block_start_error_response(
            ctx, C2837X_BLOCK_ERROR_ALGORITHM_START, C2837X_ERR_INTERNAL);
        return;
    }

    runtime->algorithm_started = 1u;
    frame_octets = c2837x_block_build_response(config->tx_frame_words,
                                               C2837X_ERR_OK);
    c2837x_block_start_sending(ctx, frame_octets,
                               C2837X_BLOCK_TX_DONE_ENTER_SIM_RUNNING);
}

static void c2837x_block_handle_input_data(C2837xBlock *ctx)
{
    C2837xBlock_Runtime *runtime = &ctx->runtime;
    const C2837xBlock_Config *config = ctx->config;
    const Uint16 *payload = &config->rx_frame_words[2];
    Uint16 *tx = config->tx_frame_words;
    Uint32 step_index = (Uint32)payload[0] | ((Uint32)payload[1] << 16);

    if (step_index != runtime->expected_step_index)
    {
        c2837x_block_start_error_response(ctx, C2837X_BLOCK_ERROR_PROTOCOL,
                                          C2837X_ERR_STEP_INDEX);
        return;
    }
    config->algorithm->decode_input(config->input_object, &payload[2]);
    if (config->algorithm->on_step(config->algorithm_context,
            config->input_object, config->output_object) != 0)
    {
        c2837x_block_start_error_response(
            ctx, C2837X_BLOCK_ERROR_ALGORITHM_STEP, C2837X_ERR_INTERNAL);
        return;
    }

    tx[0] = C2837X_MSG_OUTPUT_DATA;
    tx[1] = config->output_payload_octets;
    tx[2] = (Uint16)(step_index & 0xffffu);
    tx[3] = (Uint16)(step_index >> 16);
    config->algorithm->encode_output(config->output_object, &tx[4]);

    c2837x_block_start_sending(
        ctx, C2837X_BLOCK_HEADER_SIZE_BYTES + config->output_payload_octets,
        C2837X_BLOCK_TX_DONE_ADVANCE_STEP);
}

static void c2837x_block_service_frame_ready(C2837xBlock *ctx)
{
    switch (ctx->runtime.rx_msg_type)
    {
    case C2837X_MSG_SIM_START:
        c2837x_block_handle_sim_start(ctx);
        break;
    case C2837X_MSG_INPUT_DATA:
        c2837x_block_handle_input_data(ctx);
        break;
    case C2837X_MSG_SIM_STOP:
        c2837x_block_terminate_session(ctx, C2837X_BLOCK_TERMINATE_NORMAL);
        break;
    default:
        c2837x_block_start_error_response(ctx, C2837X_BLOCK_ERROR_PROTOCOL,
                                          C2837X_ERR_UNKNOWN_TYPE);
        break;
    }
}

static void c2837x_block_finish_sending(C2837xBlock *ctx, Uint32 now_us)
{
    C2837xBlock_TxDoneAction action = ctx->runtime.tx_done_action;
    ctx->runtime.tx_done_action = C2837X_BLOCK_TX_DONE_CLOSE;

    if (action == C2837X_BLOCK_TX_DONE_ENTER_SIM_RUNNING)
    {
        ctx->runtime.protocol_phase = C2837X_BLOCK_PROTOCOL_SIM_RUNNING;
        ctx->runtime.expected_step_index = 0u;
        c2837x_block_start_receiving(
            ctx, C2837X_BLOCK_WAIT_INTERACTION, now_us);
    }
    else if (action == C2837X_BLOCK_TX_DONE_RECEIVE_NEXT)
    {
        c2837x_block_start_receiving(
            ctx, C2837X_BLOCK_WAIT_INTERACTION, now_us);
    }
    else if (action == C2837X_BLOCK_TX_DONE_ADVANCE_STEP)
    {
        ctx->runtime.expected_step_index++;
        c2837x_block_start_receiving(
            ctx, C2837X_BLOCK_WAIT_INTERACTION, now_us);
    }
    else
    {
        c2837x_block_terminate_session(ctx, C2837X_BLOCK_TERMINATE_ERROR);
    }
}

static void c2837x_block_service_sending(C2837xBlock *ctx)
{
    C2837xBlock_Runtime *runtime = &ctx->runtime;
    Uint32 remaining_octets = runtime->tx_total_octets -
        runtime->tx_sent_octets;
    int32 sent_octets = ctx->config->iodevice_ops->send(
        ctx->config->iodevice_channel,
        &ctx->config->tx_frame_words[runtime->tx_sent_octets / 2u],
        remaining_octets);

    if (sent_octets < 0)
    {
        c2837x_block_latch_error(ctx, C2837X_BLOCK_ERROR_IODEVICE);
        c2837x_block_terminate_session(ctx, C2837X_BLOCK_TERMINATE_ERROR);
        return;
    }
    if (sent_octets == 0)
    {
        if (c2837x_block_timeout_expired(
                ctx, runtime->progress_start_us,
                ctx->config->transfer_timeout_us) != 0)
        {
            c2837x_block_latch_error(ctx, C2837X_BLOCK_ERROR_TIMEOUT);
            c2837x_block_terminate_session(
                ctx, C2837X_BLOCK_TERMINATE_ERROR);
        }
        return;
    }
    if ((((Uint32)sent_octets & 1u) != 0u) ||
        ((Uint32)sent_octets > remaining_octets))
    {
        c2837x_block_latch_error(ctx, C2837X_BLOCK_ERROR_IODEVICE);
        c2837x_block_terminate_session(ctx, C2837X_BLOCK_TERMINATE_ERROR);
        return;
    }

    runtime->tx_sent_octets += (Uint32)sent_octets;
    runtime->progress_start_us = ctx->config->time_us();
    if (runtime->tx_sent_octets == runtime->tx_total_octets)
        c2837x_block_finish_sending(ctx, runtime->progress_start_us);
}

static void c2837x_block_accept_connection(C2837xBlock *ctx)
{
    C2837xBlock_Runtime *runtime = &ctx->runtime;
    c2837x_block_reset_rx(ctx);
    c2837x_block_reset_tx(ctx);
    ctx->config->algorithm->reset_io(ctx->config->algorithm_context,
                                     ctx->config->input_object,
                                     ctx->config->output_object);
    runtime->protocol_phase = C2837X_BLOCK_PROTOCOL_WAIT_SIM_START;
    runtime->expected_step_index = 0u;
    runtime->algorithm_started = 0u;
    runtime->close_pending = 0u;
    runtime->normal_end_pending = 0u;
    runtime->primary_error_latched = 0u;
    c2837x_block_start_receiving(
        ctx, C2837X_BLOCK_WAIT_TRANSFER, ctx->config->time_us());
}

static void c2837x_block_service_wait_connection(C2837xBlock *ctx)
{
    C2837xBlock_Runtime *runtime = &ctx->runtime;
    C2837xBlock_IoConnectionState connection_state;
    int16 result;

    if (runtime->close_pending != 0u)
    {
        result = ctx->config->iodevice_ops->close(
            ctx->config->iodevice_channel);
        if (result == 0)
            return;
        runtime->close_pending = 0u;
        if (result < 0)
        {
            runtime->normal_end_pending = 0u;
            c2837x_block_latch_error(ctx, C2837X_BLOCK_ERROR_IODEVICE);
        }
        else
        {
            if (runtime->normal_end_pending != 0u)
                runtime->last_error = C2837X_BLOCK_ERROR_NONE;
            runtime->normal_end_pending = 0u;
            runtime->primary_error_latched = 0u;
        }
        return;
    }

    connection_state = ctx->config->iodevice_ops->get_connection_state(
        ctx->config->iodevice_channel);
    switch (connection_state)
    {
    case C2837X_IODEVICE_CONNECTION_CLOSED:
        if (ctx->config->iodevice_ops->open(
                ctx->config->iodevice_channel) < 0)
            c2837x_block_latch_error(ctx, C2837X_BLOCK_ERROR_IODEVICE);
        return;
    case C2837X_IODEVICE_CONNECTION_OPEN:
        if (ctx->config->iodevice_ops->listen(
                ctx->config->iodevice_channel) < 0)
            c2837x_block_latch_error(ctx, C2837X_BLOCK_ERROR_IODEVICE);
        return;
    case C2837X_IODEVICE_CONNECTION_LISTENING:
        return;
    case C2837X_IODEVICE_CONNECTION_CONNECTED:
        c2837x_block_accept_connection(ctx);
        return;
    case C2837X_IODEVICE_CONNECTION_PEER_CLOSED:
        c2837x_block_latch_error(ctx, C2837X_BLOCK_ERROR_DISCONNECTED);
        c2837x_block_terminate_session(ctx, C2837X_BLOCK_TERMINATE_ERROR);
        return;
    case C2837X_IODEVICE_CONNECTION_ERROR:
    default:
        c2837x_block_latch_error(ctx, C2837X_BLOCK_ERROR_IODEVICE);
        return;
    }
}

void C2837xBlock_Init(C2837xBlock *instance)
{
    if (instance == NULL)
        return;

    memset(&instance->runtime, 0, sizeof(instance->runtime));
    instance->runtime.state = C2837X_BLOCK_STATE_INERT;
    if (!c2837x_block_config_is_valid(instance->config))
    {
        instance->runtime.last_error = C2837X_BLOCK_ERROR_INVALID_ARGUMENT;
        return;
    }

    instance->runtime.protocol_phase =
        C2837X_BLOCK_PROTOCOL_WAIT_SIM_START;
    instance->config->iodevice_ops->channel_init(
        instance->config->iodevice_channel);
    instance->config->algorithm->reset_io(
        instance->config->algorithm_context,
        instance->config->input_object,
        instance->config->output_object);
    instance->runtime.state = C2837X_BLOCK_STATE_WAIT_CONNECTION;
}

void C2837xBlock_Run(C2837xBlock *instance)
{
    if (instance == NULL)
        return;

    switch (instance->runtime.state)
    {
    case C2837X_BLOCK_STATE_INERT:
        return;
    case C2837X_BLOCK_STATE_WAIT_CONNECTION:
        c2837x_block_service_wait_connection(instance);
        break;
    case C2837X_BLOCK_STATE_RECEIVING:
        c2837x_block_service_receiving(instance);
        break;
    case C2837X_BLOCK_STATE_FRAME_READY:
        c2837x_block_service_frame_ready(instance);
        break;
    case C2837X_BLOCK_STATE_SENDING:
        c2837x_block_service_sending(instance);
        break;
    default:
        c2837x_block_latch_error(instance, C2837X_BLOCK_ERROR_INTERNAL);
        c2837x_block_terminate_session(
            instance, C2837X_BLOCK_TERMINATE_ERROR);
        break;
    }
}

C2837xBlock_Error C2837xBlock_GetLastError(const C2837xBlock *instance)
{
    return (instance != NULL) ? instance->runtime.last_error
                              : C2837X_BLOCK_ERROR_INVALID_ARGUMENT;
}
