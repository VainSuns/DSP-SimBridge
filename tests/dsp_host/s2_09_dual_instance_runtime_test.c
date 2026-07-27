#include <assert.h>
#include <stdio.h>
#include <string.h>

#define C2837X_BLOCK_EXPECTED_CORE_API_VERSION 1u
#include "c2837x_block_internal.h"

#define NO_RESULT_OVERRIDE  ((int32)0x7fffffffL)
#define TRACE_CAPACITY      64u

typedef struct
{
    char id;
    C2837xBlock_IoConnectionState state;
    Uint16 init_calls;
    Uint16 open_calls;
    Uint16 listen_calls;
    Uint16 state_calls;
    Uint16 receive_calls;
    Uint16 send_calls;
    Uint16 close_calls;
    Uint16 rx_words[8];
    Uint32 rx_octets;
    Uint32 rx_offset_octets;
    Uint16 tx_words[8];
    Uint32 tx_octets;
    int32 receive_result;
    int32 send_result;
    int16 close_result;
} FakeChannel;

typedef struct
{
    Uint16 values[2];
} TestData;

typedef struct
{
    char id;
    Uint16 data_octets;
    Uint16 bias;
    Uint16 reset_calls;
    Uint16 start_calls;
    Uint16 decode_calls;
    Uint16 step_calls;
    Uint16 encode_calls;
    Uint16 stop_calls;
    Uint16 fail_step;
} AlgorithmContext;

typedef struct
{
    char instance;
    const char *operation;
} TraceEntry;

static FakeChannel channel_a;
static FakeChannel channel_b;
static TestData input_a;
static TestData input_b;
static TestData output_a;
static TestData output_b;
static AlgorithmContext algorithm_a;
static AlgorithmContext algorithm_b;
static Uint16 rx_a[5];
static Uint16 tx_a[5];
static Uint16 rx_b[6];
static Uint16 tx_b[6];
static TraceEntry trace_entries[TRACE_CAPACITY];
static Uint16 trace_count;
static Uint16 platform_init_calls;
static Uint32 now_us;

static void trace(char instance, const char *operation)
{
    assert(trace_count < TRACE_CAPACITY);
    trace_entries[trace_count].instance = instance;
    trace_entries[trace_count].operation = operation;
    trace_count++;
}

static void fake_init(void *ref)
{
    FakeChannel *channel = (FakeChannel *)ref;
    channel->init_calls++;
    trace(channel->id, "init");
}

static int16 fake_open(void *ref)
{
    FakeChannel *channel = (FakeChannel *)ref;
    channel->open_calls++;
    trace(channel->id, "open");
    return 0;
}

static int16 fake_listen(void *ref)
{
    FakeChannel *channel = (FakeChannel *)ref;
    channel->listen_calls++;
    trace(channel->id, "listen");
    return 0;
}

static C2837xBlock_IoConnectionState fake_state(void *ref)
{
    FakeChannel *channel = (FakeChannel *)ref;
    channel->state_calls++;
    trace(channel->id, "state");
    return channel->state;
}

static int32 fake_receive(void *ref, Uint16 *data, Uint32 capacity_octets)
{
    FakeChannel *channel = (FakeChannel *)ref;
    Uint32 available;
    Uint32 count;
    Uint32 index;

    channel->receive_calls++;
    trace(channel->id, "receive");
    if (channel->receive_result != NO_RESULT_OVERRIDE)
    {
        int32 result = channel->receive_result;
        channel->receive_result = NO_RESULT_OVERRIDE;
        return result;
    }
    available = channel->rx_octets - channel->rx_offset_octets;
    count = (available < capacity_octets) ? available : capacity_octets;
    for (index = 0u; index < count / 2u; index++)
        data[index] = channel->rx_words[channel->rx_offset_octets / 2u + index];
    channel->rx_offset_octets += count;
    return (int32)count;
}

static int32 fake_send(void *ref, const Uint16 *data, Uint32 count_octets)
{
    FakeChannel *channel = (FakeChannel *)ref;
    Uint32 index;
    int32 result = channel->send_result;

    channel->send_calls++;
    trace(channel->id, "send");
    if (result != NO_RESULT_OVERRIDE)
    {
        channel->send_result = NO_RESULT_OVERRIDE;
        return result;
    }
    channel->tx_octets = count_octets;
    for (index = 0u; index < count_octets / 2u; index++)
        channel->tx_words[index] = data[index];
    return (int32)count_octets;
}

static int16 fake_close(void *ref)
{
    FakeChannel *channel = (FakeChannel *)ref;
    channel->close_calls++;
    trace(channel->id, "close");
    return channel->close_result;
}

static const C2837xBlock_IoDeviceOps fake_ops = {
    fake_init, fake_open, fake_listen, fake_state,
    fake_receive, fake_send, fake_close
};

static void algorithm_reset(void *context, void *input, void *output)
{
    AlgorithmContext *algorithm = (AlgorithmContext *)context;
    algorithm->reset_calls++;
    trace(algorithm->id, "reset");
    memset(input, 0, sizeof(TestData));
    memset(output, 0, sizeof(TestData));
}

static int16 algorithm_start(void *context)
{
    AlgorithmContext *algorithm = (AlgorithmContext *)context;
    algorithm->start_calls++;
    trace(algorithm->id, "start");
    return 0;
}

static int16 algorithm_decode(void *context, void *input,
                              const Uint16 *words, Uint16 octets)
{
    AlgorithmContext *algorithm = (AlgorithmContext *)context;
    TestData decoded = {{ 0u, 0u }};

    assert(octets == algorithm->data_octets);
    decoded.values[0] = words[0];
    if (octets == 4u)
        decoded.values[1] = words[1];
    *(TestData *)input = decoded;
    algorithm->decode_calls++;
    trace(algorithm->id, "decode");
    return 0;
}

static int16 algorithm_step(void *context, const void *input, void *output)
{
    AlgorithmContext *algorithm = (AlgorithmContext *)context;
    const TestData *source = (const TestData *)input;
    TestData *destination = (TestData *)output;

    algorithm->step_calls++;
    trace(algorithm->id, "step");
    if (algorithm->fail_step != 0u)
        return -1;
    destination->values[0] = source->values[0] + algorithm->bias;
    destination->values[1] = source->values[1] + algorithm->bias;
    return 0;
}

static int16 algorithm_encode(void *context, const void *output,
                              Uint16 *words, Uint16 capacity_octets)
{
    AlgorithmContext *algorithm = (AlgorithmContext *)context;
    const TestData *data = (const TestData *)output;

    assert(capacity_octets == algorithm->data_octets);
    words[0] = data->values[0];
    if (capacity_octets == 4u)
        words[1] = data->values[1];
    algorithm->encode_calls++;
    trace(algorithm->id, "encode");
    return 0;
}

static void algorithm_stop(void *context)
{
    AlgorithmContext *algorithm = (AlgorithmContext *)context;
    algorithm->stop_calls++;
    trace(algorithm->id, "stop");
}

static const C2837xBlock_AlgorithmAdapter algorithm_adapter = {
    algorithm_reset, algorithm_start, algorithm_decode,
    algorithm_step, algorithm_encode, algorithm_stop
};

static Uint32 fake_time_us(void)
{
    return now_us;
}

static const C2837xBlock_Config config_a = {
    &fake_ops, &channel_a, rx_a, 10u, tx_a, 10u,
    &input_a, &output_a, &algorithm_adapter, &algorithm_a,
    0x0001u, 0x11112222u, 6u, 6u, 6u,
    fake_time_us, 5000000u, 1000000u
};
static const C2837xBlock_Config config_b = {
    &fake_ops, &channel_b, rx_b, 12u, tx_b, 12u,
    &input_b, &output_b, &algorithm_adapter, &algorithm_b,
    0x0001u, 0x33334444u, 8u, 8u, 8u,
    fake_time_us, 7000000u, 2000000u
};
static C2837xBlock instance_a = C2837X_BLOCK_INSTANCE_INITIALIZER(&config_a);
static C2837xBlock instance_b = C2837X_BLOCK_INSTANCE_INITIALIZER(&config_b);

int16 C2837xBlock_PlatformInit(void)
{
    platform_init_calls++;
    return C2837X_BLOCK_PLATFORM_OK;
}

static void assert_runtime_equal(const C2837xBlock_Runtime *actual,
                                 const C2837xBlock_Runtime *expected)
{
    assert(actual->state == expected->state);
    assert(actual->protocol_phase == expected->protocol_phase);
    assert(actual->rx_phase == expected->rx_phase);
    assert(actual->rx_header_received_octets == expected->rx_header_received_octets);
    assert(actual->rx_msg_type == expected->rx_msg_type);
    assert(actual->rx_payload_length_octets == expected->rx_payload_length_octets);
    assert(actual->rx_payload_received_octets == expected->rx_payload_received_octets);
    assert(actual->tx_total_octets == expected->tx_total_octets);
    assert(actual->tx_sent_octets == expected->tx_sent_octets);
    assert(actual->expected_step_index == expected->expected_step_index);
    assert(actual->progress_start_us == expected->progress_start_us);
    assert(actual->receive_wait_kind == expected->receive_wait_kind);
    assert(actual->algorithm_started == expected->algorithm_started);
    assert(actual->close_pending == expected->close_pending);
    assert(actual->primary_error_latched == expected->primary_error_latched);
    assert(actual->normal_end_pending == expected->normal_end_pending);
    assert(actual->tx_done_action == expected->tx_done_action);
    assert(actual->response_error == expected->response_error);
    assert(actual->last_error == expected->last_error);
}

static void clear_trace(void)
{
    trace_count = 0u;
}

static void reset_fixture(void)
{
    memset(&channel_a, 0, sizeof(channel_a));
    memset(&channel_b, 0, sizeof(channel_b));
    memset(&algorithm_a, 0, sizeof(algorithm_a));
    memset(&algorithm_b, 0, sizeof(algorithm_b));
    memset(&input_a, 0, sizeof(input_a));
    memset(&input_b, 0, sizeof(input_b));
    memset(&output_a, 0, sizeof(output_a));
    memset(&output_b, 0, sizeof(output_b));
    memset(rx_a, 0, sizeof(rx_a));
    memset(rx_b, 0, sizeof(rx_b));
    memset(tx_a, 0, sizeof(tx_a));
    memset(tx_b, 0, sizeof(tx_b));
    channel_a.id = 'A';
    channel_b.id = 'B';
    channel_a.state = C2837X_IODEVICE_CONNECTION_CONNECTED;
    channel_b.state = C2837X_IODEVICE_CONNECTION_CONNECTED;
    channel_a.receive_result = NO_RESULT_OVERRIDE;
    channel_b.receive_result = NO_RESULT_OVERRIDE;
    channel_a.send_result = NO_RESULT_OVERRIDE;
    channel_b.send_result = NO_RESULT_OVERRIDE;
    channel_a.close_result = 1;
    channel_b.close_result = 1;
    algorithm_a.id = 'A';
    algorithm_a.data_octets = 2u;
    algorithm_a.bias = 10u;
    algorithm_b.id = 'B';
    algorithm_b.data_octets = 4u;
    algorithm_b.bias = 20u;
    now_us = 0u;
    clear_trace();
    C2837xBlock_Init(&instance_a);
    C2837xBlock_Init(&instance_b);
    clear_trace();
}

static void load_frame(FakeChannel *channel, Uint16 type, Uint16 length,
                       const Uint16 *payload)
{
    Uint32 index;
    channel->rx_words[0] = type;
    channel->rx_words[1] = length;
    for (index = 0u; index < (Uint32)length / 2u; index++)
        channel->rx_words[index + 2u] = payload[index];
    channel->rx_octets = C2837X_BLOCK_HEADER_SIZE_BYTES + length;
    channel->rx_offset_octets = 0u;
}

static void start_session(C2837xBlock *instance, FakeChannel *channel,
                          Uint32 hash)
{
    Uint16 payload[3];
    payload[0] = 0x0001u;
    payload[1] = (Uint16)(hash & 0xffffu);
    payload[2] = (Uint16)(hash >> 16);
    if (instance->runtime.state == C2837X_BLOCK_STATE_WAIT_CONNECTION)
        C2837xBlock_Run(instance);
    load_frame(channel, C2837X_MSG_SIM_START, 6u, payload);
    C2837xBlock_Run(instance);
    C2837xBlock_Run(instance);
    C2837xBlock_Run(instance);
    assert(instance->runtime.state == C2837X_BLOCK_STATE_SENDING);
    C2837xBlock_Run(instance);
    assert(instance->runtime.protocol_phase == C2837X_BLOCK_PROTOCOL_SIM_RUNNING);
    assert(instance->runtime.expected_step_index == 0u);
}

static void step_session(C2837xBlock *instance, FakeChannel *channel,
                         Uint32 step, Uint16 first, Uint16 second)
{
    Uint16 payload[4];
    payload[0] = (Uint16)(step & 0xffffu);
    payload[1] = (Uint16)(step >> 16);
    payload[2] = first;
    payload[3] = second;
    load_frame(channel, C2837X_MSG_INPUT_DATA,
               instance->config->input_payload_octets, payload);
    C2837xBlock_Run(instance);
    C2837xBlock_Run(instance);
    C2837xBlock_Run(instance);
    assert(instance->runtime.state == C2837X_BLOCK_STATE_SENDING);
    C2837xBlock_Run(instance);
}

static void stop_session(C2837xBlock *instance, FakeChannel *channel)
{
    load_frame(channel, C2837X_MSG_SIM_STOP, 0u, NULL);
    C2837xBlock_Run(instance);
    C2837xBlock_Run(instance);
    assert(instance->runtime.close_pending == 1u);
    C2837xBlock_Run(instance);
    assert(instance->runtime.close_pending == 0u);
}

static void test_platform_init_and_bindings(void)
{
    assert(platform_init_calls == 1u);
    reset_fixture();
    assert(platform_init_calls == 1u);
    assert(channel_a.init_calls == 1u && channel_b.init_calls == 1u);
    assert(instance_a.config != instance_b.config);
    assert(config_a.iodevice_ops == config_b.iodevice_ops);
    assert(config_a.iodevice_channel != config_b.iodevice_channel);
    assert(config_a.rx_frame_words != config_b.rx_frame_words);
    assert(config_a.tx_frame_words != config_b.tx_frame_words);
    assert(config_a.input_object != config_b.input_object);
    assert(config_a.output_object != config_b.output_object);
    assert(config_a.algorithm_context != config_b.algorithm_context);
    assert(config_a.time_us == config_b.time_us);
    C2837xBlock_Init(NULL);
    C2837xBlock_Run(NULL);
    assert(C2837xBlock_GetLastError(NULL) == C2837X_BLOCK_ERROR_INVALID_ARGUMENT);
}

static void test_explicit_poll_order_and_budget(void)
{
    Uint16 cycle;
    reset_fixture();
    instance_a.runtime.state = C2837X_BLOCK_STATE_RECEIVING;
    instance_b.runtime.state = C2837X_BLOCK_STATE_RECEIVING;
    for (cycle = 0u; cycle < 3u; cycle++)
    {
        C2837xBlock_Run(&instance_a);
        C2837xBlock_Run(&instance_b);
    }
    assert(trace_count == 6u);
    for (cycle = 0u; cycle < 3u; cycle++)
    {
        assert(trace_entries[cycle * 2u].instance == 'A');
        assert(trace_entries[cycle * 2u + 1u].instance == 'B');
    }
    assert(channel_a.receive_calls == 3u && channel_b.receive_calls == 3u);

    clear_trace();
    for (cycle = 0u; cycle < 3u; cycle++)
    {
        C2837xBlock_Run(&instance_b);
        C2837xBlock_Run(&instance_a);
    }
    assert(trace_count == 6u);
    for (cycle = 0u; cycle < 3u; cycle++)
    {
        assert(trace_entries[cycle * 2u].instance == 'B');
        assert(trace_entries[cycle * 2u + 1u].instance == 'A');
    }
}

static void test_complete_runtime_isolation(void)
{
    C2837xBlock_Runtime snapshot;
    reset_fixture();
    instance_a.runtime.state = C2837X_BLOCK_STATE_SENDING;
    instance_a.runtime.protocol_phase = C2837X_BLOCK_PROTOCOL_SIM_RUNNING;
    instance_a.runtime.tx_total_octets = 6u;
    instance_a.runtime.tx_sent_octets = 0u;
    instance_a.runtime.expected_step_index = 9u;
    instance_a.runtime.progress_start_us = 11u;
    instance_a.runtime.algorithm_started = 1u;
    instance_b.runtime.state = C2837X_BLOCK_STATE_RECEIVING;
    instance_b.runtime.protocol_phase = C2837X_BLOCK_PROTOCOL_WAIT_SIM_START;
    instance_b.runtime.rx_phase = C2837X_BLOCK_RX_PAYLOAD;
    instance_b.runtime.rx_header_received_octets = 4u;
    instance_b.runtime.rx_msg_type = C2837X_MSG_SIM_START;
    instance_b.runtime.rx_payload_length_octets = 6u;
    instance_b.runtime.rx_payload_received_octets = 2u;
    instance_b.runtime.expected_step_index = 3u;
    instance_b.runtime.progress_start_us = 22u;
    instance_b.runtime.receive_wait_kind = C2837X_BLOCK_WAIT_TRANSFER;
    instance_b.runtime.algorithm_started = 0u;
    instance_b.runtime.close_pending = 0u;
    instance_b.runtime.primary_error_latched = 1u;
    instance_b.runtime.normal_end_pending = 1u;
    instance_b.runtime.last_error = C2837X_BLOCK_ERROR_PROTOCOL;
    channel_a.send_result = 0;
    snapshot = instance_b.runtime;
    C2837xBlock_Run(&instance_a);
    assert_runtime_equal(&instance_b.runtime, &snapshot);
    snapshot = instance_a.runtime;
    channel_b.receive_result = 0;
    C2837xBlock_Run(&instance_b);
    assert_runtime_equal(&instance_a.runtime, &snapshot);
}

static void test_algorithm_buffers_and_independent_steps(void)
{
    reset_fixture();
    start_session(&instance_a, &channel_a, config_a.interface_hash);
    start_session(&instance_b, &channel_b, config_b.interface_hash);
    step_session(&instance_a, &channel_a, 0u, 5u, 0u);
    step_session(&instance_a, &channel_a, 1u, 6u, 0u);
    step_session(&instance_b, &channel_b, 0u, 7u, 8u);
    assert(input_a.values[0] == 6u && output_a.values[0] == 16u);
    assert(input_b.values[0] == 7u && input_b.values[1] == 8u);
    assert(output_b.values[0] == 27u && output_b.values[1] == 28u);
    assert(algorithm_a.step_calls == 2u && algorithm_b.step_calls == 1u);
    assert(instance_a.runtime.expected_step_index == 2u);
    assert(instance_b.runtime.expected_step_index == 1u);
    assert(channel_a.tx_words[4] == 16u);
    assert(channel_b.tx_words[4] == 27u && channel_b.tx_words[5] == 28u);
}

static void test_multiple_sessions_are_local(void)
{
    C2837xBlock_Runtime snapshot;
    Uint16 b_steps;
    reset_fixture();
    start_session(&instance_a, &channel_a, config_a.interface_hash);
    start_session(&instance_b, &channel_b, config_b.interface_hash);
    step_session(&instance_a, &channel_a, 0u, 1u, 0u);
    step_session(&instance_a, &channel_a, 1u, 2u, 0u);
    step_session(&instance_b, &channel_b, 0u, 3u, 4u);
    snapshot = instance_b.runtime;
    b_steps = algorithm_b.step_calls;
    stop_session(&instance_a, &channel_a);
    assert_runtime_equal(&instance_b.runtime, &snapshot);
    channel_a.state = C2837X_IODEVICE_CONNECTION_CONNECTED;
    start_session(&instance_a, &channel_a, config_a.interface_hash);
    assert(instance_a.runtime.expected_step_index == 0u);
    assert_runtime_equal(&instance_b.runtime, &snapshot);
    assert(algorithm_b.step_calls == b_steps);

    snapshot = instance_a.runtime;
    stop_session(&instance_b, &channel_b);
    assert_runtime_equal(&instance_a.runtime, &snapshot);
}

static void test_protocol_and_timeout_isolation(void)
{
    C2837xBlock_Runtime snapshot;
    Uint16 b_receive_calls;
    const Uint16 unknown_payload[] = { 0u };
    reset_fixture();
    start_session(&instance_a, &channel_a, config_a.interface_hash);
    start_session(&instance_b, &channel_b, config_b.interface_hash);
    load_frame(&channel_a, 0xffffu, 0u, unknown_payload);
    snapshot = instance_b.runtime;
    b_receive_calls = channel_b.receive_calls;
    C2837xBlock_Run(&instance_a);
    assert(instance_a.runtime.last_error == C2837X_BLOCK_ERROR_PROTOCOL);
    assert(instance_a.runtime.response_error == C2837X_ERR_UNKNOWN_TYPE);
    assert_runtime_equal(&instance_b.runtime, &snapshot);
    C2837xBlock_Run(&instance_b);
    assert(channel_b.receive_calls == (Uint16)(b_receive_calls + 1u));
    assert(instance_b.runtime.last_error == C2837X_BLOCK_ERROR_NONE);

    reset_fixture();
    C2837xBlock_Run(&instance_a);
    C2837xBlock_Run(&instance_b);
    instance_a.runtime.algorithm_started = 1u;
    instance_b.runtime.algorithm_started = 1u;
    snapshot = instance_b.runtime;
    now_us = config_a.transfer_timeout_us;
    C2837xBlock_Run(&instance_a);
    assert(instance_a.runtime.last_error == C2837X_BLOCK_ERROR_TIMEOUT);
    assert(instance_a.runtime.close_pending == 1u);
    assert(algorithm_a.stop_calls == 1u);
    assert_runtime_equal(&instance_b.runtime, &snapshot);
    C2837xBlock_Run(&instance_b);
    assert(instance_b.runtime.last_error == C2837X_BLOCK_ERROR_NONE);
    assert(instance_b.runtime.progress_start_us == snapshot.progress_start_us);
}

static void test_iodevice_and_close_error_isolation(void)
{
    C2837xBlock_Runtime snapshot;
    Uint16 b_calls;
    reset_fixture();
    C2837xBlock_Run(&instance_a);
    C2837xBlock_Run(&instance_b);
    channel_a.receive_result = -1;
    snapshot = instance_b.runtime;
    C2837xBlock_Run(&instance_a);
    assert(instance_a.runtime.last_error == C2837X_BLOCK_ERROR_IODEVICE);
    assert_runtime_equal(&instance_b.runtime, &snapshot);
    b_calls = channel_b.receive_calls;
    C2837xBlock_Run(&instance_b);
    assert(channel_b.receive_calls == (Uint16)(b_calls + 1u));

    reset_fixture();
    instance_a.runtime.state = C2837X_BLOCK_STATE_SENDING;
    instance_a.runtime.tx_total_octets = 6u;
    instance_a.runtime.algorithm_started = 1u;
    channel_a.send_result = -1;
    instance_b.runtime.state = C2837X_BLOCK_STATE_RECEIVING;
    snapshot = instance_b.runtime;
    C2837xBlock_Run(&instance_a);
    assert(instance_a.runtime.last_error == C2837X_BLOCK_ERROR_IODEVICE);
    assert_runtime_equal(&instance_b.runtime, &snapshot);
    b_calls = channel_b.receive_calls;
    C2837xBlock_Run(&instance_b);
    assert(channel_b.receive_calls == (Uint16)(b_calls + 1u));

    reset_fixture();
    instance_a.runtime.close_pending = 1u;
    instance_a.runtime.primary_error_latched = 1u;
    instance_a.runtime.last_error = C2837X_BLOCK_ERROR_PROTOCOL;
    channel_a.close_result = -1;
    channel_a.state = C2837X_IODEVICE_CONNECTION_ERROR;
    channel_b.state = C2837X_IODEVICE_CONNECTION_CLOSED;
    C2837xBlock_Run(&instance_a);
    assert(instance_a.runtime.close_pending == 0u);
    assert(instance_a.runtime.last_error == C2837X_BLOCK_ERROR_PROTOCOL);
    assert(channel_a.close_calls == 1u);
    C2837xBlock_Run(&instance_b);
    assert(channel_b.open_calls == 1u);
    C2837xBlock_Run(&instance_a);
    assert(channel_a.close_calls == 1u);
    channel_b.state = C2837X_IODEVICE_CONNECTION_OPEN;
    C2837xBlock_Run(&instance_b);
    assert(channel_b.listen_calls == 1u);
    channel_b.state = C2837X_IODEVICE_CONNECTION_CONNECTED;
    C2837xBlock_Run(&instance_b);
    C2837xBlock_Run(&instance_b);
    assert(channel_b.receive_calls == 1u);
    instance_b.runtime.state = C2837X_BLOCK_STATE_SENDING;
    instance_b.runtime.tx_total_octets = 6u;
    C2837xBlock_Run(&instance_b);
    assert(channel_b.send_calls == 1u);
    assert(instance_b.runtime.last_error == C2837X_BLOCK_ERROR_NONE);
}

static void test_finite_algorithm_failure_isolation(void)
{
    C2837xBlock_Runtime snapshot;
    Uint16 a_encode_calls;
    Uint16 a_stop_calls;
    Uint16 payload_a[] = { 0u, 0u, 9u };
    reset_fixture();
    start_session(&instance_a, &channel_a, config_a.interface_hash);
    start_session(&instance_b, &channel_b, config_b.interface_hash);
    algorithm_a.fail_step = 1u;
    a_encode_calls = algorithm_a.encode_calls;
    a_stop_calls = algorithm_a.stop_calls;
    load_frame(&channel_a, C2837X_MSG_INPUT_DATA, 6u, payload_a);
    C2837xBlock_Run(&instance_a);
    C2837xBlock_Run(&instance_a);
    snapshot = instance_b.runtime;
    C2837xBlock_Run(&instance_a);
    assert(instance_a.runtime.last_error == C2837X_BLOCK_ERROR_ALGORITHM_STEP);
    assert(instance_a.runtime.state == C2837X_BLOCK_STATE_SENDING);
    assert(tx_a[0] == C2837X_MSG_RESPONSE && tx_a[2] == C2837X_ERR_INTERNAL);
    assert(algorithm_a.encode_calls == a_encode_calls);
    assert(algorithm_a.stop_calls == a_stop_calls);
    assert_runtime_equal(&instance_b.runtime, &snapshot);
    step_session(&instance_b, &channel_b, 0u, 12u, 13u);
    assert(algorithm_b.step_calls == 1u);
    C2837xBlock_Run(&instance_a);
    assert(algorithm_a.stop_calls == (Uint16)(a_stop_calls + 1u));
    assert(algorithm_a.stop_calls <= 1u);
}

int main(void)
{
    assert(C2837xBlock_PlatformInit() == C2837X_BLOCK_PLATFORM_OK);
    test_platform_init_and_bindings();
    test_explicit_poll_order_and_budget();
    test_complete_runtime_isolation();
    test_algorithm_buffers_and_independent_steps();
    test_multiple_sessions_are_local();
    test_protocol_and_timeout_isolation();
    test_iodevice_and_close_error_isolation();
    test_finite_algorithm_failure_isolation();
    printf("platform_init=1 init=A,B trace=A.receive,B.receive/B.receive,A.receive\n");
    printf("states=A:SENDING+SIM_RUNNING B:RECEIVING+WAIT_SIM_START steps=A:2 B:1\n");
    printf("isolation=protocol,timeout,receive,send,close,algorithm sessions=multiple\n");
    return 0;
}
