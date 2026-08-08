#include <assert.h>
#include <string.h>

#include "c2837x_block_internal.h"

typedef struct
{
    C2837xBlock_IoConnectionState state;
    int32 receive_result;
    int32 send_result;
    int16 close_result;
    Uint16 state_calls;
    Uint16 receive_calls;
    Uint16 send_calls;
    Uint16 close_calls;
} FakeChannel;

typedef struct
{
    Uint16 reset_calls;
    Uint16 start_calls;
    Uint16 decode_calls;
    Uint16 step_calls;
    Uint16 encode_calls;
    Uint16 stop_calls;
    Uint16 fail_start;
    Uint16 fail_step;
    Uint16 advance_start_time;
    Uint16 advance_step_time;
} FakeAlgorithm;

static Uint32 now_us;
static Uint16 time_calls;
static FakeChannel channel;
static FakeAlgorithm algorithm_context;
static Uint16 rx_frame[16];
static Uint16 tx_frame[16];
static Uint16 input_object[2];
static Uint16 output_object[2];

static Uint32 fake_time_us(void)
{
    time_calls++;
    return now_us;
}

static void fake_init(void *context) { (void)context; }
static int16 fake_progress(void *context) { (void)context; return 0; }

static C2837xBlock_IoConnectionState fake_state(void *context)
{
    FakeChannel *fake = (FakeChannel *)context;
    fake->state_calls++;
    return fake->state;
}

static int32 fake_receive(void *context, Uint16 *data, Uint32 capacity)
{
    FakeChannel *fake = (FakeChannel *)context;
    (void)data;
    fake->receive_calls++;
    return (fake->receive_result == 0x7fffffffL)
        ? (int32)capacity : fake->receive_result;
}

static int32 fake_send(void *context, const Uint16 *data, Uint32 count)
{
    FakeChannel *fake = (FakeChannel *)context;
    (void)data;
    fake->send_calls++;
    return (fake->send_result == 0x7fffffffL)
        ? (int32)count : fake->send_result;
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
    memset(input, 0, sizeof(input_object));
    memset(output, 0, sizeof(output_object));
}

static int16 algorithm_start(void *context)
{
    FakeAlgorithm *fake = (FakeAlgorithm *)context;
    fake->start_calls++;
    if (fake->advance_start_time != 0u)
        now_us += 1000u;
    return (fake->fail_start != 0u) ? -1 : 0;
}

static void algorithm_decode(void *input, const Uint16 *data)
{
    FakeAlgorithm *fake = &algorithm_context;
    fake->decode_calls++;
    ((Uint16 *)input)[0] = data[0];
    ((Uint16 *)input)[1] = data[1];
}

static int16 algorithm_step(void *context, const void *input, void *output)
{
    FakeAlgorithm *fake = (FakeAlgorithm *)context;
    fake->step_calls++;
    if (fake->advance_step_time != 0u)
        now_us += 1000u;
    if (fake->fail_step != 0u)
        return -1;
    ((Uint16 *)output)[0] = (Uint16)(((const Uint16 *)input)[0] + 1u);
    ((Uint16 *)output)[1] = (Uint16)(((const Uint16 *)input)[1] + 1u);
    return 0;
}

static void algorithm_encode(const void *output, Uint16 *data)
{
    algorithm_context.encode_calls++;
    data[0] = ((const Uint16 *)output)[0];
    data[1] = ((const Uint16 *)output)[1];
}

static void algorithm_stop(void *context)
{
    ((FakeAlgorithm *)context)->stop_calls++;
}

static const C2837xBlock_IoDeviceOps ops = {
    fake_init, fake_progress, fake_progress, fake_state,
    fake_receive, fake_send, fake_close
};

static const C2837xBlock_AlgorithmAdapter algorithm = {
    algorithm_reset, algorithm_start, algorithm_decode,
    algorithm_step, algorithm_encode, algorithm_stop
};

static C2837xBlock_Config config = {
    &ops, &channel, rx_frame, 32u, tx_frame, 32u,
    input_object, output_object, &algorithm, &algorithm_context,
    1u, 0x12345678u, 8u, 8u, 12u,
    fake_time_us, 100u, 20u
};

static C2837xBlock instance = C2837X_BLOCK_INSTANCE_INITIALIZER(&config);

static void reset_fixture(void)
{
    memset(&channel, 0, sizeof(channel));
    memset(&algorithm_context, 0, sizeof(algorithm_context));
    memset(rx_frame, 0, sizeof(rx_frame));
    memset(tx_frame, 0, sizeof(tx_frame));
    input_object[0] = 0u;
    input_object[1] = 0u;
    output_object[0] = 0u;
    output_object[1] = 0u;
    now_us = 0u;
    time_calls = 0u;
    config.interaction_timeout_us = 100u;
    config.transfer_timeout_us = 20u;
    channel.state = C2837X_IODEVICE_CONNECTION_CONNECTED;
    channel.receive_result = 0x7fffffffL;
    channel.send_result = 0x7fffffffL;
    channel.close_result = 1;
    C2837xBlock_Init(&instance);
}

static void connect_instance(void)
{
    C2837xBlock_Run(&instance);
    assert(instance.runtime.state == C2837X_BLOCK_STATE_RECEIVING);
    assert(instance.runtime.receive_wait_kind == C2837X_BLOCK_WAIT_TRANSFER);
}

static void prepare_start_frame(void)
{
    rx_frame[0] = C2837X_MSG_SIM_START;
    rx_frame[1] = 6u;
    rx_frame[2] = 1u;
    rx_frame[3] = 0x5678u;
    rx_frame[4] = 0x1234u;
}

static void enter_running(void)
{
    prepare_start_frame();
    C2837xBlock_Run(&instance);
    C2837xBlock_Run(&instance);
    C2837xBlock_Run(&instance);
    assert(instance.runtime.state == C2837X_BLOCK_STATE_SENDING);
    C2837xBlock_Run(&instance);
    assert(instance.runtime.protocol_phase ==
           C2837X_BLOCK_PROTOCOL_SIM_RUNNING);
    assert(instance.runtime.receive_wait_kind ==
           C2837X_BLOCK_WAIT_INTERACTION);
}

static void prepare_input_frame(Uint32 step)
{
    rx_frame[0] = C2837X_MSG_INPUT_DATA;
    rx_frame[1] = 8u;
    rx_frame[2] = (Uint16)step;
    rx_frame[3] = (Uint16)(step >> 16);
    rx_frame[4] = 7u;
    rx_frame[5] = 8u;
}

static void test_receive_boundaries_and_progress(void)
{
    reset_fixture();
    connect_instance();
    channel.receive_result = 0;
    now_us = 19u;
    C2837xBlock_Run(&instance);
    assert(instance.runtime.state == C2837X_BLOCK_STATE_RECEIVING);
    now_us = 20u;
    C2837xBlock_Run(&instance);
    assert(instance.runtime.last_error == C2837X_BLOCK_ERROR_TIMEOUT);

    reset_fixture();
    connect_instance();
    prepare_start_frame();
    channel.receive_result = 2;
    now_us = 5u;
    C2837xBlock_Run(&instance);
    assert(instance.runtime.progress_start_us == 5u);
    channel.receive_result = 0;
    now_us = 24u;
    C2837xBlock_Run(&instance);
    assert(instance.runtime.state == C2837X_BLOCK_STATE_RECEIVING);
    now_us = 25u;
    C2837xBlock_Run(&instance);
    assert(instance.runtime.last_error == C2837X_BLOCK_ERROR_TIMEOUT);

    reset_fixture();
    connect_instance();
    prepare_start_frame();
    channel.receive_result = 4;
    now_us = 1u;
    C2837xBlock_Run(&instance);
    assert(instance.runtime.rx_phase == C2837X_BLOCK_RX_PAYLOAD);
    channel.receive_result = 2;
    now_us = 2u;
    C2837xBlock_Run(&instance);
    channel.receive_result = 0;
    now_us = 21u;
    C2837xBlock_Run(&instance);
    assert(instance.runtime.state == C2837X_BLOCK_STATE_RECEIVING);
    now_us = 22u;
    C2837xBlock_Run(&instance);
    assert(instance.runtime.last_error == C2837X_BLOCK_ERROR_TIMEOUT);

    reset_fixture();
    connect_instance();
    enter_running();
    channel.receive_result = 0;
    now_us = 99u;
    C2837xBlock_Run(&instance);
    assert(instance.runtime.state == C2837X_BLOCK_STATE_RECEIVING);
    now_us = 100u;
    C2837xBlock_Run(&instance);
    assert(instance.runtime.last_error == C2837X_BLOCK_ERROR_TIMEOUT);
}

static void test_interaction_switch_refresh_and_wrap(void)
{
    reset_fixture();
    connect_instance();
    enter_running();
    prepare_input_frame(0u);
    channel.receive_result = 2;
    now_us = 90u;
    C2837xBlock_Run(&instance);
    assert(instance.runtime.receive_wait_kind == C2837X_BLOCK_WAIT_TRANSFER);
    assert(instance.runtime.progress_start_us == 90u);
    channel.receive_result = 0;
    now_us = 109u;
    C2837xBlock_Run(&instance);
    assert(instance.runtime.state == C2837X_BLOCK_STATE_RECEIVING);
    now_us = 110u;
    C2837xBlock_Run(&instance);
    assert(instance.runtime.last_error == C2837X_BLOCK_ERROR_TIMEOUT);

    reset_fixture();
    config.transfer_timeout_us = 32u;
    now_us = 0xfffffff0u;
    connect_instance();
    channel.receive_result = 0;
    now_us = 0x0000000fu;
    C2837xBlock_Run(&instance);
    assert(instance.runtime.state == C2837X_BLOCK_STATE_RECEIVING);
    now_us = 0x00000010u;
    C2837xBlock_Run(&instance);
    assert(instance.runtime.last_error == C2837X_BLOCK_ERROR_TIMEOUT);
}

static void test_send_boundaries_wrap_and_algorithm_time(void)
{
    reset_fixture();
    instance.runtime.state = C2837X_BLOCK_STATE_SENDING;
    instance.runtime.tx_total_octets = 6u;
    instance.runtime.tx_done_action = C2837X_BLOCK_TX_DONE_CLOSE;
    instance.runtime.progress_start_us = 10u;
    channel.send_result = 0;
    now_us = 29u;
    C2837xBlock_Run(&instance);
    assert(instance.runtime.state == C2837X_BLOCK_STATE_SENDING);
    now_us = 30u;
    C2837xBlock_Run(&instance);
    assert(instance.runtime.last_error == C2837X_BLOCK_ERROR_TIMEOUT);

    reset_fixture();
    instance.runtime.state = C2837X_BLOCK_STATE_SENDING;
    instance.runtime.tx_total_octets = 6u;
    instance.runtime.tx_done_action = C2837X_BLOCK_TX_DONE_RECEIVE_NEXT;
    channel.send_result = 2;
    now_us = 15u;
    C2837xBlock_Run(&instance);
    assert(instance.runtime.progress_start_us == 15u);
    now_us = 30u;
    C2837xBlock_Run(&instance);
    assert(instance.runtime.progress_start_us == 30u);
    now_us = 45u;
    C2837xBlock_Run(&instance);
    assert(instance.runtime.state == C2837X_BLOCK_STATE_RECEIVING);
    assert(instance.runtime.last_error == C2837X_BLOCK_ERROR_NONE);

    reset_fixture();
    config.transfer_timeout_us = 32u;
    instance.runtime.state = C2837X_BLOCK_STATE_SENDING;
    instance.runtime.tx_total_octets = 6u;
    instance.runtime.progress_start_us = 0xfffffff0u;
    channel.send_result = 0;
    now_us = 0x0000000fu;
    C2837xBlock_Run(&instance);
    assert(instance.runtime.state == C2837X_BLOCK_STATE_SENDING);
    now_us = 0x00000010u;
    C2837xBlock_Run(&instance);
    assert(instance.runtime.last_error == C2837X_BLOCK_ERROR_TIMEOUT);

    reset_fixture();
    connect_instance();
    prepare_start_frame();
    C2837xBlock_Run(&instance);
    C2837xBlock_Run(&instance);
    algorithm_context.advance_start_time = 1u;
    C2837xBlock_Run(&instance);
    assert(instance.runtime.progress_start_us == 1000u);
    channel.send_result = 0;
    C2837xBlock_Run(&instance);
    assert(instance.runtime.state == C2837X_BLOCK_STATE_SENDING);

    reset_fixture();
    connect_instance();
    enter_running();
    prepare_input_frame(0u);
    C2837xBlock_Run(&instance);
    C2837xBlock_Run(&instance);
    algorithm_context.advance_step_time = 1u;
    C2837xBlock_Run(&instance);
    assert(instance.runtime.progress_start_us == 1000u);
    channel.send_result = 0;
    C2837xBlock_Run(&instance);
    assert(instance.runtime.state == C2837X_BLOCK_STATE_SENDING);
}

typedef enum
{
    CASE_NORMAL_STOP,
    CASE_START_FAIL,
    CASE_START_SEND_FAIL,
    CASE_START_SEND_TIMEOUT,
    CASE_STEP_FAIL,
    CASE_STATE_ERROR,
    CASE_TYPE_ERROR,
    CASE_LENGTH_ERROR,
    CASE_STEP_ERROR,
    CASE_RX_TIMEOUT,
    CASE_INTERACTION_TIMEOUT,
    CASE_SEND_TIMEOUT,
    CASE_DISCONNECTED,
    CASE_RECEIVE_FAIL,
    CASE_ERROR_SEND_FAIL,
    CASE_ERROR_SEND_TIMEOUT,
    CASE_CLOSE_ERROR
} CaseKind;

typedef struct
{
    CaseKind kind;
    Uint16 expected_stop;
    Uint16 expected_response;
    Uint16 expected_wire_error;
    C2837xBlock_Error expected_error;
} LifecycleCase;

static const LifecycleCase lifecycle_cases[] = {
    { CASE_NORMAL_STOP, 1u, 0u, 0u, C2837X_BLOCK_ERROR_NONE },
    { CASE_START_FAIL, 0u, 1u, C2837X_ERR_INTERNAL,
      C2837X_BLOCK_ERROR_ALGORITHM_START },
    { CASE_START_SEND_FAIL, 1u, 1u, C2837X_ERR_OK,
      C2837X_BLOCK_ERROR_IODEVICE },
    { CASE_START_SEND_TIMEOUT, 1u, 1u, C2837X_ERR_OK,
      C2837X_BLOCK_ERROR_TIMEOUT },
    { CASE_STEP_FAIL, 1u, 1u, C2837X_ERR_INTERNAL,
      C2837X_BLOCK_ERROR_ALGORITHM_STEP },
    { CASE_STATE_ERROR, 1u, 1u, C2837X_ERR_STATE,
      C2837X_BLOCK_ERROR_PROTOCOL },
    { CASE_TYPE_ERROR, 1u, 1u, C2837X_ERR_UNKNOWN_TYPE,
      C2837X_BLOCK_ERROR_PROTOCOL },
    { CASE_LENGTH_ERROR, 1u, 1u, C2837X_ERR_PAYLOAD_LENGTH,
      C2837X_BLOCK_ERROR_PROTOCOL },
    { CASE_STEP_ERROR, 1u, 1u, C2837X_ERR_STEP_INDEX,
      C2837X_BLOCK_ERROR_PROTOCOL },
    { CASE_RX_TIMEOUT, 1u, 0u, 0u, C2837X_BLOCK_ERROR_TIMEOUT },
    { CASE_INTERACTION_TIMEOUT, 1u, 0u, 0u,
      C2837X_BLOCK_ERROR_TIMEOUT },
    { CASE_SEND_TIMEOUT, 1u, 0u, 0u, C2837X_BLOCK_ERROR_TIMEOUT },
    { CASE_DISCONNECTED, 1u, 0u, 0u,
      C2837X_BLOCK_ERROR_DISCONNECTED },
    { CASE_RECEIVE_FAIL, 1u, 0u, 0u,
      C2837X_BLOCK_ERROR_IODEVICE },
    { CASE_ERROR_SEND_FAIL, 1u, 1u, C2837X_ERR_UNKNOWN_TYPE,
      C2837X_BLOCK_ERROR_PROTOCOL },
    { CASE_ERROR_SEND_TIMEOUT, 1u, 1u, C2837X_ERR_UNKNOWN_TYPE,
      C2837X_BLOCK_ERROR_PROTOCOL },
    { CASE_CLOSE_ERROR, 0u, 0u, 0u, C2837X_BLOCK_ERROR_PROTOCOL }
};

static void set_running_frame(Uint16 type)
{
    instance.runtime.state = C2837X_BLOCK_STATE_FRAME_READY;
    instance.runtime.protocol_phase = C2837X_BLOCK_PROTOCOL_SIM_RUNNING;
    instance.runtime.algorithm_started = 1u;
    instance.runtime.rx_msg_type = type;
}

static void run_error_response(int32 send_result, Uint16 timeout)
{
    assert(instance.runtime.state == C2837X_BLOCK_STATE_SENDING);
    channel.send_result = send_result;
    if (timeout != 0u)
        now_us = instance.runtime.progress_start_us +
            config.transfer_timeout_us;
    C2837xBlock_Run(&instance);
}

static void run_lifecycle_case(const LifecycleCase *test)
{
    reset_fixture();
    switch (test->kind)
    {
    case CASE_NORMAL_STOP:
        set_running_frame(C2837X_MSG_SIM_STOP);
        C2837xBlock_Run(&instance);
        C2837xBlock_Run(&instance);
        break;
    case CASE_START_FAIL:
        prepare_start_frame();
        instance.runtime.state = C2837X_BLOCK_STATE_FRAME_READY;
        instance.runtime.rx_msg_type = C2837X_MSG_SIM_START;
        algorithm_context.fail_start = 1u;
        C2837xBlock_Run(&instance);
        run_error_response(0x7fffffffL, 0u);
        break;
    case CASE_START_SEND_FAIL:
    case CASE_START_SEND_TIMEOUT:
        instance.runtime.state = C2837X_BLOCK_STATE_SENDING;
        instance.runtime.algorithm_started = 1u;
        instance.runtime.tx_total_octets = 6u;
        instance.runtime.tx_done_action =
            C2837X_BLOCK_TX_DONE_ENTER_SIM_RUNNING;
        tx_frame[0] = C2837X_MSG_RESPONSE;
        tx_frame[2] = C2837X_ERR_OK;
        run_error_response((test->kind == CASE_START_SEND_FAIL) ? -1 : 0,
                           (test->kind == CASE_START_SEND_TIMEOUT) ? 1u : 0u);
        break;
    case CASE_STEP_FAIL:
    case CASE_STEP_ERROR:
        set_running_frame(C2837X_MSG_INPUT_DATA);
        prepare_input_frame((test->kind == CASE_STEP_ERROR) ? 1u : 0u);
        algorithm_context.fail_step = (test->kind == CASE_STEP_FAIL);
        C2837xBlock_Run(&instance);
        run_error_response(0x7fffffffL, 0u);
        break;
    case CASE_STATE_ERROR:
        set_running_frame(C2837X_MSG_SIM_START);
        prepare_start_frame();
        C2837xBlock_Run(&instance);
        run_error_response(0x7fffffffL, 0u);
        break;
    case CASE_TYPE_ERROR:
    case CASE_ERROR_SEND_FAIL:
    case CASE_ERROR_SEND_TIMEOUT:
        set_running_frame(0xffffu);
        C2837xBlock_Run(&instance);
        run_error_response(
            (test->kind == CASE_ERROR_SEND_FAIL) ? -1 :
            ((test->kind == CASE_ERROR_SEND_TIMEOUT) ? 0 : 0x7fffffffL),
            (test->kind == CASE_ERROR_SEND_TIMEOUT) ? 1u : 0u);
        if (test->kind != CASE_TYPE_ERROR)
        {
            channel.close_result = -1;
            C2837xBlock_Run(&instance);
        }
        break;
    case CASE_LENGTH_ERROR:
        instance.runtime.state = C2837X_BLOCK_STATE_RECEIVING;
        instance.runtime.protocol_phase = C2837X_BLOCK_PROTOCOL_SIM_RUNNING;
        instance.runtime.algorithm_started = 1u;
        instance.runtime.receive_wait_kind = C2837X_BLOCK_WAIT_TRANSFER;
        rx_frame[0] = C2837X_MSG_INPUT_DATA;
        rx_frame[1] = 6u;
        channel.receive_result = 4;
        C2837xBlock_Run(&instance);
        run_error_response(0x7fffffffL, 0u);
        break;
    case CASE_RX_TIMEOUT:
    case CASE_INTERACTION_TIMEOUT:
        instance.runtime.state = C2837X_BLOCK_STATE_RECEIVING;
        instance.runtime.algorithm_started = 1u;
        instance.runtime.receive_wait_kind =
            (test->kind == CASE_INTERACTION_TIMEOUT)
                ? C2837X_BLOCK_WAIT_INTERACTION
                : C2837X_BLOCK_WAIT_TRANSFER;
        channel.receive_result = 0;
        now_us = (test->kind == CASE_INTERACTION_TIMEOUT) ? 100u : 20u;
        C2837xBlock_Run(&instance);
        break;
    case CASE_SEND_TIMEOUT:
        instance.runtime.state = C2837X_BLOCK_STATE_SENDING;
        instance.runtime.algorithm_started = 1u;
        instance.runtime.tx_total_octets = 6u;
        channel.send_result = 0;
        now_us = 20u;
        C2837xBlock_Run(&instance);
        break;
    case CASE_DISCONNECTED:
        instance.runtime.algorithm_started = 1u;
        channel.state = C2837X_IODEVICE_CONNECTION_PEER_CLOSED;
        C2837xBlock_Run(&instance);
        break;
    case CASE_RECEIVE_FAIL:
        instance.runtime.state = C2837X_BLOCK_STATE_RECEIVING;
        instance.runtime.algorithm_started = 1u;
        channel.receive_result = -1;
        C2837xBlock_Run(&instance);
        break;
    case CASE_CLOSE_ERROR:
        instance.runtime.close_pending = 1u;
        instance.runtime.primary_error_latched = 1u;
        instance.runtime.last_error = C2837X_BLOCK_ERROR_PROTOCOL;
        channel.close_result = -1;
        C2837xBlock_Run(&instance);
        break;
    default:
        assert(0);
    }

    assert(algorithm_context.stop_calls == test->expected_stop);
    assert(algorithm_context.stop_calls <= 1u);
    if (test->expected_response != 0u)
    {
        assert(tx_frame[0] == C2837X_MSG_RESPONSE);
        assert(tx_frame[2] == test->expected_wire_error);
    }
    assert(C2837xBlock_GetLastError(&instance) == test->expected_error);
    assert(instance.runtime.state == C2837X_BLOCK_STATE_WAIT_CONNECTION);
    assert(instance.runtime.normal_end_pending == 0u);
}

static void test_lifecycle_matrix(void)
{
    Uint16 index;
    for (index = 0u;
         index < (Uint16)(sizeof(lifecycle_cases) / sizeof(lifecycle_cases[0]));
         index++)
        run_lifecycle_case(&lifecycle_cases[index]);
}

static void test_recent_error_normal_end_and_getter(void)
{
    Uint16 old_time_calls;
    Uint16 old_state_calls;

    reset_fixture();
    instance.runtime.last_error = C2837X_BLOCK_ERROR_PROTOCOL;
    channel.state = C2837X_IODEVICE_CONNECTION_CLOSED;
    C2837xBlock_Run(&instance);
    assert(C2837xBlock_GetLastError(&instance) ==
           C2837X_BLOCK_ERROR_PROTOCOL);
    channel.state = C2837X_IODEVICE_CONNECTION_OPEN;
    C2837xBlock_Run(&instance);
    assert(C2837xBlock_GetLastError(&instance) ==
           C2837X_BLOCK_ERROR_PROTOCOL);
    channel.state = C2837X_IODEVICE_CONNECTION_LISTENING;
    C2837xBlock_Run(&instance);
    assert(C2837xBlock_GetLastError(&instance) ==
           C2837X_BLOCK_ERROR_PROTOCOL);
    channel.state = C2837X_IODEVICE_CONNECTION_CONNECTED;
    old_time_calls = time_calls;
    old_state_calls = channel.state_calls;
    assert(C2837xBlock_GetLastError(&instance) ==
           C2837X_BLOCK_ERROR_PROTOCOL);
    assert(C2837xBlock_GetLastError(&instance) ==
           C2837X_BLOCK_ERROR_PROTOCOL);
    assert(time_calls == old_time_calls && channel.state_calls == old_state_calls);

    connect_instance();
    assert(C2837xBlock_GetLastError(&instance) ==
           C2837X_BLOCK_ERROR_PROTOCOL);
    channel.receive_result = -1;
    C2837xBlock_Run(&instance);
    assert(C2837xBlock_GetLastError(&instance) ==
           C2837X_BLOCK_ERROR_IODEVICE);

    reset_fixture();
    instance.runtime.last_error = C2837X_BLOCK_ERROR_PROTOCOL;
    connect_instance();
    enter_running();
    input_object[0] = 7u;
    output_object[0] = 9u;
    set_running_frame(C2837X_MSG_SIM_STOP);
    C2837xBlock_Run(&instance);
    assert(input_object[0] == 0u && output_object[0] == 0u);
    channel.close_result = 0;
    C2837xBlock_Run(&instance);
    assert(C2837xBlock_GetLastError(&instance) ==
           C2837X_BLOCK_ERROR_PROTOCOL);
    channel.close_result = 1;
    C2837xBlock_Run(&instance);
    assert(C2837xBlock_GetLastError(&instance) == C2837X_BLOCK_ERROR_NONE);
    assert(algorithm_context.stop_calls == 1u);

    reset_fixture();
    connect_instance();
    enter_running();
    set_running_frame(C2837X_MSG_SIM_STOP);
    C2837xBlock_Run(&instance);
    channel.close_result = -1;
    C2837xBlock_Run(&instance);
    assert(C2837xBlock_GetLastError(&instance) ==
           C2837X_BLOCK_ERROR_IODEVICE);
    assert(channel.close_calls == 1u && algorithm_context.stop_calls == 1u);
}

static void test_direct_decode_overwrites_input(void)
{
    reset_fixture();
    input_object[0] = 0xaaaau;
    input_object[1] = 0xbbbbu;
    set_running_frame(C2837X_MSG_INPUT_DATA);
    prepare_input_frame(0u);
    C2837xBlock_Run(&instance);
    assert(input_object[0] == 7u && input_object[1] == 8u);
    assert(algorithm_context.step_calls == 1u);
    assert(algorithm_context.encode_calls == 1u);
}

static void test_run_time_budget(void)
{
    Uint16 calls;

    reset_fixture();
    connect_instance();
    channel.receive_result = 0;
    calls = time_calls;
    C2837xBlock_Run(&instance);
    assert(time_calls == (Uint16)(calls + 1u));
    channel.receive_result = -1;
    calls = time_calls;
    C2837xBlock_Run(&instance);
    assert(time_calls == calls);

    reset_fixture();
    instance.runtime.state = C2837X_BLOCK_STATE_SENDING;
    instance.runtime.tx_total_octets = 6u;
    channel.send_result = 2;
    calls = time_calls;
    C2837xBlock_Run(&instance);
    assert(time_calls == (Uint16)(calls + 1u));
    channel.send_result = -1;
    calls = time_calls;
    C2837xBlock_Run(&instance);
    assert(time_calls == calls);
}

int main(void)
{
    test_receive_boundaries_and_progress();
    test_interaction_switch_refresh_and_wrap();
    test_send_boundaries_wrap_and_algorithm_time();
    test_lifecycle_matrix();
    test_recent_error_normal_end_and_getter();
    test_direct_decode_overwrites_input();
    test_run_time_budget();
    return 0;
}
