#include <assert.h>
#include <string.h>

#include "c2837x_block_internal.h"

typedef struct
{
    C2837xBlock_IoConnectionState state;
    int16 open_result;
    int16 listen_result;
    int16 close_result;
    Uint16 init_calls;
    Uint16 state_calls;
    Uint16 open_calls;
    Uint16 listen_calls;
    Uint16 receive_calls;
    Uint16 send_calls;
    Uint16 close_calls;
} FakeChannel;

typedef struct
{
    Uint16 reset_calls;
    Uint16 stop_calls;
} FakeAlgorithm;

static Uint16 rx_words[8];
static Uint16 tx_words[8];
static Uint16 input_words[2];
static Uint16 output_words[2];
static FakeChannel channel;
static FakeAlgorithm algorithm_context;

static void fake_init(void *context)
{
    ((FakeChannel *)context)->init_calls++;
}

static int16 fake_open(void *context)
{
    FakeChannel *fake = (FakeChannel *)context;
    fake->open_calls++;
    return fake->open_result;
}

static int16 fake_listen(void *context)
{
    FakeChannel *fake = (FakeChannel *)context;
    fake->listen_calls++;
    return fake->listen_result;
}

static C2837xBlock_IoConnectionState fake_state(void *context)
{
    FakeChannel *fake = (FakeChannel *)context;
    fake->state_calls++;
    return fake->state;
}

static int32 fake_receive(void *context, Uint16 *data, Uint32 capacity)
{
    (void)data;
    (void)capacity;
    ((FakeChannel *)context)->receive_calls++;
    return 0;
}

static int32 fake_send(void *context, const Uint16 *data, Uint32 count)
{
    (void)data;
    (void)count;
    ((FakeChannel *)context)->send_calls++;
    return 0;
}

static int16 fake_close(void *context)
{
    FakeChannel *fake = (FakeChannel *)context;
    fake->close_calls++;
    return fake->close_result;
}

static void algorithm_reset(void *context, void *input, void *output)
{
    ((FakeAlgorithm *)context)->reset_calls++;
    memset(input, 0, sizeof(input_words));
    memset(output, 0, sizeof(output_words));
}

static int16 algorithm_ok(void *context)
{
    (void)context;
    return 0;
}

static int16 algorithm_decode(void *context, void *input,
                              const Uint16 *data, Uint16 count)
{
    (void)context;
    (void)input;
    (void)data;
    (void)count;
    return 0;
}

static int16 algorithm_step(void *context, const void *input, void *output)
{
    (void)context;
    (void)input;
    (void)output;
    return 0;
}

static int16 algorithm_encode(void *context, const void *output,
                              Uint16 *data, Uint16 count)
{
    (void)context;
    (void)output;
    (void)data;
    (void)count;
    return 0;
}

static void algorithm_stop(void *context)
{
    ((FakeAlgorithm *)context)->stop_calls++;
}

static const C2837xBlock_IoDeviceOps ops = {
    fake_init, fake_open, fake_listen, fake_state,
    fake_receive, fake_send, fake_close
};

static const C2837xBlock_AlgorithmAdapter algorithm = {
    algorithm_reset, algorithm_ok, algorithm_decode,
    algorithm_step, algorithm_encode, algorithm_stop
};

static const C2837xBlock_Config config = {
    &ops, &channel, rx_words, 16u, tx_words, 16u,
    input_words, output_words, &algorithm, &algorithm_context,
    1u, 0x12345678u, 8u, 8u, 12u, 1000u, 1000u
};

static C2837xBlock instance = C2837X_BLOCK_INSTANCE_INITIALIZER(&config);

static void reset_fixture(void)
{
    memset(&channel, 0, sizeof(channel));
    memset(&algorithm_context, 0, sizeof(algorithm_context));
    channel.state = C2837X_IODEVICE_CONNECTION_CLOSED;
    C2837xBlock_Init(&instance);
    assert(instance.runtime.state == C2837X_BLOCK_STATE_WAIT_CONNECTION);
    assert(instance.runtime.protocol_phase ==
           C2837X_BLOCK_PROTOCOL_WAIT_SIM_START);
    assert(instance.runtime.close_pending == 0u);
    assert(instance.runtime.algorithm_started == 0u);
    assert(channel.init_calls == 1u);
    assert(algorithm_context.reset_calls == 1u);
}

static void clear_operation_counts(void)
{
    channel.state_calls = 0u;
    channel.open_calls = 0u;
    channel.listen_calls = 0u;
    channel.receive_calls = 0u;
    channel.send_calls = 0u;
    channel.close_calls = 0u;
}

static void assert_only_close(Uint16 expected)
{
    assert(channel.close_calls == expected);
    assert(channel.state_calls == 0u);
    assert(channel.open_calls == 0u && channel.listen_calls == 0u);
    assert(channel.receive_calls == 0u && channel.send_calls == 0u);
}

static void test_close_busy_done_error(void)
{
    reset_fixture();
    instance.runtime.close_pending = 1u;
    channel.close_result = 0;
    clear_operation_counts();
    C2837xBlock_Run(&instance);
    assert_only_close(1u);
    assert(instance.runtime.close_pending == 1u);
    C2837xBlock_Run(&instance);
    assert_only_close(2u);

    channel.close_result = 1;
    clear_operation_counts();
    C2837xBlock_Run(&instance);
    assert_only_close(1u);
    assert(instance.runtime.close_pending == 0u);
    C2837xBlock_Run(&instance);
    assert(channel.state_calls == 1u && channel.open_calls == 1u);
    assert(channel.listen_calls == 0u && channel.close_calls == 1u);

    reset_fixture();
    instance.runtime.close_pending = 1u;
    channel.close_result = -1;
    clear_operation_counts();
    C2837xBlock_Run(&instance);
    assert_only_close(1u);
    assert(instance.runtime.close_pending == 0u);
    assert(instance.runtime.last_error == C2837X_BLOCK_ERROR_IODEVICE);
    C2837xBlock_Run(&instance);
    assert(channel.close_calls == 1u && channel.state_calls == 1u);

    reset_fixture();
    instance.runtime.last_error = C2837X_BLOCK_ERROR_PROTOCOL;
    instance.runtime.close_pending = 1u;
    channel.close_result = -1;
    C2837xBlock_Run(&instance);
    assert(instance.runtime.last_error == C2837X_BLOCK_ERROR_PROTOCOL);
}

static void test_close_error_stays_fault_waiting(void)
{
    Uint16 run;
    Uint16 resets;
    Uint16 stops;

    reset_fixture();
    channel.state = C2837X_IODEVICE_CONNECTION_ERROR;
    channel.close_result = -1;
    instance.runtime.close_pending = 1u;
    resets = algorithm_context.reset_calls;
    stops = algorithm_context.stop_calls;
    clear_operation_counts();

    C2837xBlock_Run(&instance);
    assert_only_close(1u);
    assert(instance.runtime.close_pending == 0u);
    assert(instance.runtime.last_error == C2837X_BLOCK_ERROR_IODEVICE);

    for (run = 1u; run < 10u; run++)
    {
        C2837xBlock_Run(&instance);
        assert(channel.state_calls == run);
        assert(channel.close_calls == 1u);
        assert(channel.open_calls == 0u && channel.listen_calls == 0u);
        assert(channel.receive_calls == 0u && channel.send_calls == 0u);
        assert(instance.runtime.close_pending == 0u);
        assert(instance.runtime.state == C2837X_BLOCK_STATE_WAIT_CONNECTION);
        assert(instance.runtime.last_error == C2837X_BLOCK_ERROR_IODEVICE);
        assert(algorithm_context.reset_calls == resets);
        assert(algorithm_context.stop_calls == stops);
    }
}

static void assert_close_error_preserves(C2837xBlock_Error primary_error)
{
    Uint16 run;
    Uint16 resets;

    reset_fixture();
    channel.state = C2837X_IODEVICE_CONNECTION_ERROR;
    channel.close_result = -1;
    instance.runtime.close_pending = 1u;
    instance.runtime.last_error = primary_error;
    resets = algorithm_context.reset_calls;
    clear_operation_counts();

    C2837xBlock_Run(&instance);
    for (run = 0u; run < 4u; run++)
        C2837xBlock_Run(&instance);

    assert(channel.close_calls == 1u && channel.state_calls == 4u);
    assert(instance.runtime.close_pending == 0u);
    assert(instance.runtime.last_error == primary_error);
    assert(algorithm_context.reset_calls == resets);
    assert(algorithm_context.stop_calls == 0u);
}

static void test_close_error_preserves_primary_error(void)
{
    assert_close_error_preserves(C2837X_BLOCK_ERROR_PROTOCOL);
    assert_close_error_preserves(C2837X_BLOCK_ERROR_ALGORITHM_STEP);
}

static void test_connection_error_recovers_to_closed(void)
{
    Uint16 run;

    reset_fixture();
    channel.state = C2837X_IODEVICE_CONNECTION_ERROR;
    channel.close_result = -1;
    instance.runtime.close_pending = 1u;
    clear_operation_counts();
    C2837xBlock_Run(&instance);
    for (run = 0u; run < 3u; run++)
        C2837xBlock_Run(&instance);

    channel.state = C2837X_IODEVICE_CONNECTION_CLOSED;
    C2837xBlock_Run(&instance);
    assert(channel.state_calls == 4u);
    assert(channel.open_calls == 1u && channel.listen_calls == 0u);
    assert(channel.close_calls == 1u);

    channel.state = C2837X_IODEVICE_CONNECTION_OPEN;
    C2837xBlock_Run(&instance);
    assert(channel.state_calls == 5u);
    assert(channel.open_calls == 1u && channel.listen_calls == 1u);
    assert(channel.close_calls == 1u);
}

static void test_startup_connection_error_waits(void)
{
    Uint16 run;
    Uint16 resets;

    reset_fixture();
    channel.state = C2837X_IODEVICE_CONNECTION_ERROR;
    resets = algorithm_context.reset_calls;
    clear_operation_counts();
    for (run = 1u; run <= 10u; run++)
    {
        C2837xBlock_Run(&instance);
        assert(channel.state_calls == run);
        assert(channel.close_calls == 0u);
        assert(channel.open_calls == 0u && channel.listen_calls == 0u);
        assert(instance.runtime.close_pending == 0u);
        assert(instance.runtime.state == C2837X_BLOCK_STATE_WAIT_CONNECTION);
        assert(instance.runtime.last_error == C2837X_BLOCK_ERROR_IODEVICE);
        assert(algorithm_context.reset_calls == resets);
        assert(algorithm_context.stop_calls == 0u);
    }
}

static void test_normal_connection_budget(void)
{
    reset_fixture();
    clear_operation_counts();
    channel.state = C2837X_IODEVICE_CONNECTION_CLOSED;
    C2837xBlock_Run(&instance);
    assert(channel.state_calls == 1u && channel.open_calls == 1u);
    assert(channel.listen_calls == 0u);

    clear_operation_counts();
    channel.state = C2837X_IODEVICE_CONNECTION_OPEN;
    C2837xBlock_Run(&instance);
    assert(channel.state_calls == 1u && channel.listen_calls == 1u);
    assert(channel.open_calls == 0u);

    clear_operation_counts();
    channel.state = C2837X_IODEVICE_CONNECTION_LISTENING;
    C2837xBlock_Run(&instance);
    assert(channel.state_calls == 1u);
    assert(channel.open_calls == 0u && channel.listen_calls == 0u);

    input_words[0] = 7u;
    output_words[0] = 9u;
    clear_operation_counts();
    channel.state = C2837X_IODEVICE_CONNECTION_CONNECTED;
    C2837xBlock_Run(&instance);
    assert(channel.state_calls == 1u && channel.receive_calls == 0u);
    assert(instance.runtime.state == C2837X_BLOCK_STATE_RECEIVING);
    assert(input_words[0] == 0u && output_words[0] == 0u);
}

static void test_termination_and_primary_error(void)
{
    Uint16 resets;

    reset_fixture();
    channel.state = C2837X_IODEVICE_CONNECTION_PEER_CLOSED;
    instance.runtime.algorithm_started = 1u;
    instance.runtime.protocol_phase = C2837X_BLOCK_PROTOCOL_SIM_RUNNING;
    instance.runtime.expected_step_index = 42u;
    instance.runtime.rx_header_received_octets = 2u;
    instance.runtime.tx_total_octets = 6u;
    input_words[0] = 1u;
    output_words[0] = 2u;
    resets = algorithm_context.reset_calls;
    clear_operation_counts();
    C2837xBlock_Run(&instance);
    assert(channel.state_calls == 1u && channel.close_calls == 0u);
    assert(instance.runtime.state == C2837X_BLOCK_STATE_WAIT_CONNECTION);
    assert(instance.runtime.protocol_phase ==
           C2837X_BLOCK_PROTOCOL_WAIT_SIM_START);
    assert(instance.runtime.close_pending == 1u);
    assert(instance.runtime.expected_step_index == 0u);
    assert(instance.runtime.rx_header_received_octets == 0u);
    assert(instance.runtime.tx_total_octets == 0u);
    assert(instance.runtime.last_error == C2837X_BLOCK_ERROR_DISCONNECTED);
    assert(algorithm_context.stop_calls == 1u);
    assert(algorithm_context.reset_calls == (Uint16)(resets + 1u));
    assert(input_words[0] == 0u && output_words[0] == 0u);

    channel.close_result = -1;
    C2837xBlock_Run(&instance);
    assert(instance.runtime.last_error == C2837X_BLOCK_ERROR_DISCONNECTED);
    assert(instance.runtime.close_pending == 0u);
    assert(channel.close_calls == 1u);

    reset_fixture();
    channel.state = C2837X_IODEVICE_CONNECTION_ERROR;
    C2837xBlock_Run(&instance);
    assert(instance.runtime.last_error == C2837X_BLOCK_ERROR_IODEVICE);
    assert(instance.runtime.close_pending == 0u);
    assert(channel.close_calls == 0u);
    assert(algorithm_context.reset_calls == 1u);
    assert(algorithm_context.stop_calls == 0u);
}

int main(void)
{
    test_close_busy_done_error();
    test_close_error_stays_fault_waiting();
    test_close_error_preserves_primary_error();
    test_connection_error_recovers_to_closed();
    test_startup_connection_error_waits();
    test_normal_connection_budget();
    test_termination_and_primary_error();
    return 0;
}
