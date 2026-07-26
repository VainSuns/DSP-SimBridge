#include <assert.h>
#include <string.h>

#define C2837X_BLOCK_EXPECTED_CORE_API_VERSION 1u
#include "c2837x_block_internal.h"
#include "c2837x_block_protocol.h"

typedef struct
{
    C2837xBlock_IoConnectionState state;
    Uint16 init_calls;
    Uint16 open_calls;
    Uint16 listen_calls;
    Uint16 receive_calls;
    Uint16 send_calls;
    Uint16 close_calls;
    Uint16 rx_words[8];
    Uint32 rx_octets;
    Uint32 rx_offset_octets;
    Uint16 last_tx_words[8];
    Uint32 last_tx_octets;
} FakeChannel;

typedef struct
{
    Uint16 values[2];
} TestInput;

typedef struct
{
    Uint16 values[2];
} TestOutput;

typedef struct
{
    Uint16 input_data_octets;
    Uint16 output_data_octets;
    Uint16 bias;
    Uint16 reset_calls;
    Uint16 start_calls;
    Uint16 decode_calls;
    Uint16 step_calls;
    Uint16 encode_calls;
    Uint16 stop_calls;
    Uint16 fail_step;
} AdapterContext;

static FakeChannel channel_a;
static FakeChannel channel_b;
static TestInput input_a;
static TestInput input_b;
static TestOutput output_a;
static TestOutput output_b;
static AdapterContext adapter_context_a = { 2u, 2u, 10u, 0u, 0u, 0u,
                                             0u, 0u, 0u, 0u };
static AdapterContext adapter_context_b = { 4u, 4u, 20u, 0u, 0u, 0u,
                                             0u, 0u, 0u, 0u };
static Uint16 rx_a[6];
static Uint16 tx_a[5];
static Uint16 rx_b[7];
static Uint16 tx_b[6];
static Uint16 platform_init_calls;

static void fake_init(void *ref)
{
    FakeChannel *channel = (FakeChannel *)ref;
    channel->state = C2837X_IODEVICE_CONNECTION_CLOSED;
    channel->open_calls = 0u;
    channel->listen_calls = 0u;
    channel->receive_calls = 0u;
    channel->send_calls = 0u;
    channel->close_calls = 0u;
    channel->rx_octets = 0u;
    channel->rx_offset_octets = 0u;
    channel->last_tx_octets = 0u;
    channel->init_calls++;
}

static int16 fake_open(void *ref)
{
    ((FakeChannel *)ref)->open_calls++;
    return 0;
}

static int16 fake_listen(void *ref)
{
    ((FakeChannel *)ref)->listen_calls++;
    return 0;
}

static C2837xBlock_IoConnectionState fake_state(void *ref)
{
    return ((FakeChannel *)ref)->state;
}

static int32 fake_receive(void *ref, Uint16 *data, Uint32 capacity_octets)
{
    FakeChannel *channel = (FakeChannel *)ref;
    Uint32 available = channel->rx_octets - channel->rx_offset_octets;
    Uint32 count = (available < capacity_octets) ? available : capacity_octets;
    Uint32 index;

    channel->receive_calls++;
    for (index = 0u; index < (count / 2u); index++)
        data[index] = channel->rx_words[channel->rx_offset_octets / 2u + index];
    channel->rx_offset_octets += count;
    return (int32)count;
}

static int32 fake_send(void *ref, const Uint16 *data, Uint32 count_octets)
{
    FakeChannel *channel = (FakeChannel *)ref;
    Uint32 index;

    channel->send_calls++;
    channel->last_tx_octets = count_octets;
    for (index = 0u; index < (count_octets / 2u); index++)
        channel->last_tx_words[index] = data[index];
    return (int32)count_octets;
}

static int16 fake_close(void *ref)
{
    ((FakeChannel *)ref)->close_calls++;
    return 1;
}

static const C2837xBlock_IoDeviceOps fake_ops_a = {
    fake_init, fake_open, fake_listen, fake_state,
    fake_receive, fake_send, fake_close
};
static const C2837xBlock_IoDeviceOps fake_ops_b = {
    fake_init, fake_open, fake_listen, fake_state,
    fake_receive, fake_send, fake_close
};

static void adapter_reset(void *context, void *input, void *output)
{
    AdapterContext *adapter = (AdapterContext *)context;
    adapter->reset_calls++;
    memset(input, 0, sizeof(TestInput));
    memset(output, 0, sizeof(TestOutput));
}

static int16 adapter_start(void *context)
{
    ((AdapterContext *)context)->start_calls++;
    return 0;
}

static int16 adapter_decode(void *context, void *input,
                            const Uint16 *words, Uint16 octets)
{
    AdapterContext *adapter = (AdapterContext *)context;
    TestInput decoded = {{ 0u, 0u }};

    if (octets != adapter->input_data_octets)
        return -1;
    decoded.values[0] = words[0];
    if (octets == 4u)
        decoded.values[1] = words[1];
    *(TestInput *)input = decoded;
    adapter->decode_calls++;
    return 0;
}

static int16 adapter_step(void *context, const void *input, void *output)
{
    AdapterContext *adapter = (AdapterContext *)context;
    const TestInput *typed_input = (const TestInput *)input;
    TestOutput *typed_output = (TestOutput *)output;

    adapter->step_calls++;
    if (adapter->fail_step != 0u)
        return -1;
    typed_output->values[0] = typed_input->values[0] + adapter->bias;
    typed_output->values[1] = typed_input->values[1] + adapter->bias;
    return 0;
}

static int16 adapter_encode(void *context, const void *output,
                            Uint16 *words, Uint16 capacity_octets)
{
    AdapterContext *adapter = (AdapterContext *)context;
    const TestOutput *typed_output = (const TestOutput *)output;

    if (capacity_octets != adapter->output_data_octets)
        return -1;
    words[0] = typed_output->values[0];
    if (capacity_octets == 4u)
        words[1] = typed_output->values[1];
    adapter->encode_calls++;
    return 0;
}

static void adapter_stop(void *context)
{
    ((AdapterContext *)context)->stop_calls++;
}

static const C2837xBlock_AlgorithmAdapter adapter_a = {
    adapter_reset, adapter_start, adapter_decode,
    adapter_step, adapter_encode, adapter_stop
};
static const C2837xBlock_AlgorithmAdapter adapter_b = {
    adapter_reset, adapter_start, adapter_decode,
    adapter_step, adapter_encode, adapter_stop
};

static const C2837xBlock_Config config_a = {
    &fake_ops_a, &channel_a,
    rx_a, 12u, tx_a, 10u,
    &input_a, &output_a, &adapter_a, &adapter_context_a,
    0x0001u, 0x11112222u, 6u, 6u, 8u,
    5000000u, 1000000u
};
static const C2837xBlock_Config config_b = {
    &fake_ops_b, &channel_b,
    rx_b, 14u, tx_b, 12u,
    &input_b, &output_b, &adapter_b, &adapter_context_b,
    0x0002u, 0x33334444u, 8u, 8u, 10u,
    7000000u, 2000000u
};

static C2837xBlock instance_a = C2837X_BLOCK_INSTANCE_INITIALIZER(&config_a);
static C2837xBlock instance_b = C2837X_BLOCK_INSTANCE_INITIALIZER(&config_b);

int16 C2837xBlock_PlatformInit(void)
{
    platform_init_calls++;
    return C2837X_BLOCK_PLATFORM_OK;
}

int16 c2837x_block_parse_header(const Uint16 *words, Uint16 *type,
                                Uint16 *length)
{
    if ((words[1] & 1u) != 0u)
        return -1;
    *type = words[0];
    *length = words[1];
    return 0;
}

Uint32 c2837x_block_build_response(Uint16 *words, Uint16 error)
{
    words[0] = C2837X_MSG_RESPONSE;
    words[1] = 2u;
    words[2] = error;
    return 6u;
}

Uint32 c2837x_block_build_frame(Uint16 *frame, Uint16 type,
                                Uint16 length, const Uint16 *payload)
{
    Uint32 index;
    frame[0] = type;
    frame[1] = length;
    for (index = 0u; index < (Uint32)length / 2u; index++)
        frame[index + 2u] = payload[index];
    return 4u + length;
}

static void load_frame(FakeChannel *channel, Uint16 type, Uint16 length,
                       const Uint16 *payload)
{
    Uint32 index;
    channel->rx_words[0] = type;
    channel->rx_words[1] = length;
    for (index = 0u; index < (Uint32)length / 2u; index++)
        channel->rx_words[index + 2u] = payload[index];
    channel->rx_octets = 4u + length;
    channel->rx_offset_octets = 0u;
}

static void run_received_frame(C2837xBlock *instance)
{
    C2837xBlock_Run(instance);
    C2837xBlock_Run(instance);
}

static void test_init_and_static_isolation(void)
{
    const C2837xBlock_Config *saved_config = instance_a.config;

    C2837xBlock_Init(NULL);
    C2837xBlock_Run(NULL);
    assert(C2837xBlock_GetLastError(NULL) ==
           C2837X_BLOCK_ERROR_INVALID_ARGUMENT);

    input_b.values[0] = 77u;
    output_b.values[0] = 88u;
    rx_b[0] = 99u;
    instance_b.runtime.tick_counter = 123u;
    C2837xBlock_Init(&instance_a);

    assert(instance_a.config == saved_config);
    assert(channel_a.init_calls == 1u && channel_b.init_calls == 0u);
    assert(adapter_context_a.reset_calls == 1u);
    assert(adapter_context_b.reset_calls == 0u);
    assert(input_b.values[0] == 77u && output_b.values[0] == 88u);
    assert(rx_b[0] == 99u && instance_b.runtime.tick_counter == 123u);
    assert(platform_init_calls == 0u);

    C2837xBlock_Init(&instance_b);
    assert(channel_b.init_calls == 1u);
    assert(adapter_context_b.reset_calls == 1u);
    assert(instance_a.config == &config_a && instance_b.config == &config_b);
    assert(config_a.iodevice_ops != config_b.iodevice_ops);
    assert(config_a.iodevice_channel != config_b.iodevice_channel);
    assert(config_a.rx_frame_words != config_b.rx_frame_words);
    assert(config_a.tx_frame_words != config_b.tx_frame_words);
    assert(config_a.input_object != config_b.input_object);
    assert(config_a.output_object != config_b.output_object);
    assert(config_a.algorithm != config_b.algorithm);
    assert(config_a.algorithm_context != config_b.algorithm_context);
}

static void test_config_driven_adapter_routing(void)
{
    const Uint16 start_a[] = { 0x0001u, 0x2222u, 0x1111u };
    const Uint16 start_b[] = { 0x0002u, 0x4444u, 0x3333u };
    const Uint16 input_payload_a[] = { 0u, 0u, 5u };
    const Uint16 input_payload_b[] = { 0u, 0u, 6u, 7u };
    const Uint16 wrong_step_b[] = { 2u, 0u, 9u, 10u };

    channel_a.state = C2837X_IODEVICE_CONNECTION_CONNECTED;
    load_frame(&channel_a, C2837X_MSG_SIM_START, 6u, start_a);
    run_received_frame(&instance_a);
    assert(adapter_context_a.start_calls == 1u);
    assert(adapter_context_b.start_calls == 0u);
    C2837xBlock_Run(&instance_a);
    assert(channel_a.last_tx_words[0] == C2837X_MSG_RESPONSE);

    channel_b.state = C2837X_IODEVICE_CONNECTION_CONNECTED;
    load_frame(&channel_b, C2837X_MSG_SIM_START, 6u, start_b);
    run_received_frame(&instance_b);
    assert(adapter_context_b.start_calls == 1u);
    C2837xBlock_Run(&instance_b);

    load_frame(&channel_a, C2837X_MSG_INPUT_DATA, 6u, input_payload_a);
    run_received_frame(&instance_a);
    assert(adapter_context_a.decode_calls == 1u);
    assert(adapter_context_a.step_calls == 1u);
    assert(adapter_context_a.encode_calls == 1u);
    assert(input_a.values[0] == 5u && output_a.values[0] == 15u);
    assert(adapter_context_b.decode_calls == 0u);
    C2837xBlock_Run(&instance_a);
    assert(channel_a.last_tx_words[0] == C2837X_MSG_OUTPUT_DATA);
    assert(channel_a.last_tx_words[1] == config_a.output_payload_octets);
    assert(channel_a.last_tx_words[2] == 0u && channel_a.last_tx_words[3] == 0u);
    assert(channel_a.last_tx_words[4] == 15u);

    load_frame(&channel_b, C2837X_MSG_INPUT_DATA, 8u, wrong_step_b);
    run_received_frame(&instance_b);
    assert(adapter_context_b.decode_calls == 0u);
    assert(channel_b.last_tx_octets == 6u);
    C2837xBlock_Run(&instance_b);
    assert(channel_b.last_tx_words[0] == C2837X_MSG_RESPONSE);

    C2837xBlock_Init(&instance_b);
    channel_b.state = C2837X_IODEVICE_CONNECTION_CONNECTED;
    load_frame(&channel_b, C2837X_MSG_SIM_START, 6u, start_b);
    run_received_frame(&instance_b);
    C2837xBlock_Run(&instance_b);
    load_frame(&channel_b, C2837X_MSG_INPUT_DATA, 8u, input_payload_b);
    C2837xBlock_Run(&instance_b);
    assert(adapter_context_b.decode_calls == 0u);
    C2837xBlock_Run(&instance_b);
    assert(adapter_context_b.decode_calls == 1u);
    assert(input_b.values[0] == 6u && input_b.values[1] == 7u);
    assert(output_b.values[0] == 26u && output_b.values[1] == 27u);
}

static void test_step_failure_has_no_normal_output(void)
{
    const Uint16 input_payload[] = { 1u, 0u, 8u };
    Uint16 encode_calls = adapter_context_a.encode_calls;
    Uint16 stop_calls_a = adapter_context_a.stop_calls;
    Uint16 stop_calls_b = adapter_context_b.stop_calls;

    C2837xBlock_Run(&instance_b);
    adapter_context_a.fail_step = 1u;
    load_frame(&channel_a, C2837X_MSG_INPUT_DATA, 6u, input_payload);
    run_received_frame(&instance_a);
    assert(adapter_context_a.decode_calls == 2u);
    assert(adapter_context_a.encode_calls == encode_calls);
    assert(instance_a.runtime.state == C2837X_STATE_SEND);
    C2837xBlock_Run(&instance_a);
    assert(channel_a.last_tx_words[0] == C2837X_MSG_RESPONSE);
    assert(channel_a.last_tx_words[2] == C2837X_ERR_INTERNAL);
    assert(adapter_context_a.stop_calls == stop_calls_a + 1u);
    assert(adapter_context_b.stop_calls == stop_calls_b);
    adapter_context_a.fail_step = 0u;
}

static void assert_invalid_config(C2837xBlock_Config config)
{
    C2837xBlock instance = C2837X_BLOCK_INSTANCE_INITIALIZER(&config);
    Uint16 init_calls = channel_a.init_calls;
    Uint16 reset_calls = adapter_context_a.reset_calls;

    C2837xBlock_Init(&instance);
    assert(C2837xBlock_GetLastError(&instance) ==
           C2837X_BLOCK_ERROR_INVALID_ARGUMENT);
    C2837xBlock_Run(&instance);
    assert(channel_a.init_calls == init_calls);
    assert(adapter_context_a.reset_calls == reset_calls);
}

static void test_invalid_config_boundaries(void)
{
    C2837xBlock_Config invalid = config_a;
    C2837xBlock_AlgorithmAdapter invalid_adapter = adapter_a;

    invalid.rx_frame_capacity_octets = 11u;
    assert_invalid_config(invalid);
    invalid = config_a;
    invalid.rx_frame_capacity_octets = 10u;
    assert_invalid_config(invalid);
    invalid = config_a;
    invalid.tx_frame_capacity_octets = 8u;
    assert_invalid_config(invalid);
    invalid = config_a;
    invalid.tx_frame_capacity_octets = 9u;
    assert_invalid_config(invalid);
    invalid = config_a;
    invalid.input_payload_octets = 5u;
    assert_invalid_config(invalid);
    invalid = config_a;
    invalid.input_payload_octets = 10u;
    assert_invalid_config(invalid);
    invalid = config_a;
    invalid.max_payload_octets = 7u;
    assert_invalid_config(invalid);
    invalid = config_a;
    invalid.rx_frame_words = NULL;
    assert_invalid_config(invalid);
    invalid = config_a;
    invalid_adapter.on_step = NULL;
    invalid.algorithm = &invalid_adapter;
    assert_invalid_config(invalid);
    invalid = config_a;
    invalid.interaction_timeout_us = 0u;
    assert_invalid_config(invalid);
}

int main(void)
{
    test_init_and_static_isolation();
    test_config_driven_adapter_routing();
    test_step_failure_has_no_normal_output();
    test_invalid_config_boundaries();
    return 0;
}
