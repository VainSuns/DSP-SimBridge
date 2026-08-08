#include <assert.h>
#include <string.h>

#include "c2837x_block_internal.h"

typedef struct
{
    C2837xBlock_IoConnectionState state;
    Uint16 rx[16];
    Uint32 rx_octets;
    Uint32 rx_offset;
    int32 receive_results[16];
    Uint16 receive_result_count;
    Uint16 receive_result_index;
    int32 send_results[16];
    Uint16 send_result_count;
    Uint16 send_result_index;
    Uint16 sent[16];
    Uint32 sent_octets;
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
} FakeAlgorithm;

static FakeChannel channel;
static FakeAlgorithm algorithm_context;
static Uint16 rx_frame[16];
static Uint16 tx_frame[16];
static Uint16 input_object[2];
static Uint16 output_object[2];

static Uint32 fake_time_us(void)
{
    return 0u;
}

static void fake_init(void *context)
{
    (void)context;
}

static int16 fake_progress(void *context)
{
    (void)context;
    return 0;
}

static C2837xBlock_IoConnectionState fake_state(void *context)
{
    FakeChannel *fake = (FakeChannel *)context;
    fake->state_calls++;
    return fake->state;
}

static int32 fake_receive(void *context, Uint16 *destination,
                          Uint32 capacity_octets)
{
    FakeChannel *fake = (FakeChannel *)context;
    int32 result;
    Uint32 copy_octets;
    Uint32 index;

    fake->receive_calls++;
    if (fake->receive_result_index < fake->receive_result_count)
        result = fake->receive_results[fake->receive_result_index++];
    else
        result = (int32)capacity_octets;
    if (result <= 0)
        return result;

    copy_octets = ((Uint32)result < capacity_octets)
        ? (Uint32)result : capacity_octets;
    if (copy_octets > (fake->rx_octets - fake->rx_offset))
        copy_octets = fake->rx_octets - fake->rx_offset;
    for (index = 0u; index < copy_octets / 2u; index++)
        destination[index] = fake->rx[fake->rx_offset / 2u + index];
    fake->rx_offset += copy_octets;
    return result;
}

static int32 fake_send(void *context, const Uint16 *source,
                       Uint32 count_octets)
{
    FakeChannel *fake = (FakeChannel *)context;
    int32 result;
    Uint32 copy_octets;
    Uint32 index;

    fake->send_calls++;
    if (fake->send_result_index < fake->send_result_count)
        result = fake->send_results[fake->send_result_index++];
    else
        result = (int32)count_octets;
    if (result <= 0)
        return result;

    copy_octets = ((Uint32)result < count_octets)
        ? (Uint32)result : count_octets;
    for (index = 0u; index < copy_octets / 2u; index++)
        fake->sent[fake->sent_octets / 2u + index] = source[index];
    fake->sent_octets += copy_octets;
    return result;
}

static int16 fake_close(void *context)
{
    ((FakeChannel *)context)->close_calls++;
    return 1;
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
    if (fake->fail_step != 0u)
        return -1;
    ((Uint16 *)output)[0] = ((const Uint16 *)input)[0] + 10u;
    ((Uint16 *)output)[1] = ((const Uint16 *)input)[1] + 10u;
    return 0;
}

static void algorithm_encode(const void *output, Uint16 *data)
{
    FakeAlgorithm *fake = &algorithm_context;
    fake->encode_calls++;
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

static const C2837xBlock_Config config = {
    &ops, &channel, rx_frame, 12u, tx_frame, 16u,
    input_object, output_object, &algorithm, &algorithm_context,
    1u, 0x12345678u, 8u, 8u, 12u,
    fake_time_us, 1000u, 1000u
};

static C2837xBlock instance = C2837X_BLOCK_INSTANCE_INITIALIZER(&config);

static void reset_fixture(void)
{
    memset(&channel, 0, sizeof(channel));
    memset(&algorithm_context, 0, sizeof(algorithm_context));
    memset(rx_frame, 0, sizeof(rx_frame));
    memset(tx_frame, 0, sizeof(tx_frame));
    channel.state = C2837X_IODEVICE_CONNECTION_CONNECTED;
    C2837xBlock_Init(&instance);
    C2837xBlock_Run(&instance);
    assert(instance.runtime.state == C2837X_BLOCK_STATE_RECEIVING);
    assert(channel.receive_calls == 0u);
}

static void load_frame(Uint16 type, Uint16 length, const Uint16 *payload)
{
    Uint32 index;
    channel.rx[0] = type;
    channel.rx[1] = length;
    for (index = 0u; index < (Uint32)length / 2u && index < 14u; index++)
        channel.rx[index + 2u] = payload[index];
    channel.rx_octets = 4u + length;
    channel.rx_offset = 0u;
}

static void drive_to_frame_ready(void)
{
    Uint16 budget = 16u;
    while ((instance.runtime.state == C2837X_BLOCK_STATE_RECEIVING) &&
           (budget-- != 0u))
        C2837xBlock_Run(&instance);
    assert(instance.runtime.state == C2837X_BLOCK_STATE_FRAME_READY);
}

static void enter_running(void)
{
    static const Uint16 start[] = { 1u, 0x5678u, 0x1234u };
    load_frame(C2837X_MSG_SIM_START, 6u, start);
    drive_to_frame_ready();
    C2837xBlock_Run(&instance);
    assert(instance.runtime.protocol_phase ==
           C2837X_BLOCK_PROTOCOL_WAIT_SIM_START);
    C2837xBlock_Run(&instance);
    assert(instance.runtime.protocol_phase ==
           C2837X_BLOCK_PROTOCOL_SIM_RUNNING);
}

static void test_header_and_payload_are_separate(void)
{
    static const Uint16 start[] = { 1u, 0x5678u, 0x1234u };
    reset_fixture();
    load_frame(C2837X_MSG_SIM_START, 6u, start);
    channel.receive_results[0] = 2;
    channel.receive_results[1] = 2;
    channel.receive_results[2] = 2;
    channel.receive_results[3] = 4;
    channel.receive_result_count = 4u;

    C2837xBlock_Run(&instance);
    assert(channel.receive_calls == 1u);
    assert(instance.runtime.rx_phase == C2837X_BLOCK_RX_HEADER);
    C2837xBlock_Run(&instance);
    assert(channel.receive_calls == 2u);
    assert(instance.runtime.rx_phase == C2837X_BLOCK_RX_PAYLOAD);
    assert(algorithm_context.start_calls == 0u);
    C2837xBlock_Run(&instance);
    assert(channel.receive_calls == 3u);
    assert(instance.runtime.state == C2837X_BLOCK_STATE_RECEIVING);
    C2837xBlock_Run(&instance);
    assert(channel.receive_calls == 4u);
    assert(instance.runtime.state == C2837X_BLOCK_STATE_FRAME_READY);
    assert(algorithm_context.start_calls == 0u && channel.send_calls == 0u);
    C2837xBlock_Run(&instance);
    assert(algorithm_context.start_calls == 1u);
    assert(instance.runtime.state == C2837X_BLOCK_STATE_SENDING);
}

static void assert_header(Uint16 running, Uint16 type, Uint16 length,
                          Uint16 expected_error, Uint16 valid)
{
    static const Uint16 payload[8] = { 0u };
    reset_fixture();
    if (running != 0u)
        instance.runtime.protocol_phase = C2837X_BLOCK_PROTOCOL_SIM_RUNNING;
    load_frame(type, length, payload);
    C2837xBlock_Run(&instance);
    if (valid != 0u)
    {
        if (length == 0u)
            assert(instance.runtime.state == C2837X_BLOCK_STATE_FRAME_READY);
        else
            assert(instance.runtime.rx_phase == C2837X_BLOCK_RX_PAYLOAD);
    }
    else
    {
        assert(instance.runtime.state == C2837X_BLOCK_STATE_SENDING);
        assert(tx_frame[0] == C2837X_MSG_RESPONSE);
        assert(tx_frame[1] == 2u && tx_frame[2] == expected_error);
        assert(channel.rx_offset == 4u);
        assert(algorithm_context.decode_calls == 0u);
    }
}

static void test_fixed_length_matrix(void)
{
    assert_header(0u, C2837X_MSG_SIM_START, 6u, 0u, 1u);
    assert_header(0u, C2837X_MSG_SIM_START, 4u,
                  C2837X_ERR_PAYLOAD_LENGTH, 0u);
    assert_header(0u, C2837X_MSG_SIM_START, 8u,
                  C2837X_ERR_PAYLOAD_LENGTH, 0u);
    assert_header(0u, C2837X_MSG_INPUT_DATA, 8u, C2837X_ERR_STATE, 0u);
    assert_header(0u, C2837X_MSG_SIM_STOP, 0u, C2837X_ERR_STATE, 0u);
    assert_header(1u, C2837X_MSG_INPUT_DATA, 8u, 0u, 1u);
    assert_header(1u, C2837X_MSG_INPUT_DATA, 6u,
                  C2837X_ERR_PAYLOAD_LENGTH, 0u);
    assert_header(1u, C2837X_MSG_SIM_STOP, 0u, 0u, 1u);
    assert_header(1u, C2837X_MSG_SIM_STOP, 2u,
                  C2837X_ERR_PAYLOAD_LENGTH, 0u);
    assert_header(1u, C2837X_MSG_SIM_START, 6u, C2837X_ERR_STATE, 0u);
    assert_header(0u, 0x9999u, 7u, C2837X_ERR_UNKNOWN_TYPE, 0u);
    assert_header(0u, C2837X_MSG_OUTPUT_DATA, 8u, C2837X_ERR_STATE, 0u);
    assert_header(1u, C2837X_MSG_RESPONSE, 2u, C2837X_ERR_STATE, 0u);
    assert_header(0u, C2837X_MSG_SIM_START, 7u,
                  C2837X_ERR_PAYLOAD_LENGTH, 0u);
    assert_header(0u, C2837X_MSG_SIM_START, 14u,
                  C2837X_ERR_PAYLOAD_LENGTH, 0u);
}

static void test_sim_start_boundaries(void)
{
    Uint16 start[] = { 2u, 0x5678u, 0x1234u };

    reset_fixture();
    load_frame(C2837X_MSG_SIM_START, 6u, start);
    drive_to_frame_ready();
    C2837xBlock_Run(&instance);
    assert(algorithm_context.start_calls == 0u);
    assert(tx_frame[2] == C2837X_ERR_PROTOCOL_VERSION);

    reset_fixture();
    start[0] = 1u;
    start[1] = 0u;
    load_frame(C2837X_MSG_SIM_START, 6u, start);
    drive_to_frame_ready();
    C2837xBlock_Run(&instance);
    assert(algorithm_context.start_calls == 0u);
    assert(tx_frame[2] == C2837X_ERR_CONFIG_MISMATCH);

    reset_fixture();
    start[1] = 0x5678u;
    algorithm_context.fail_start = 1u;
    load_frame(C2837X_MSG_SIM_START, 6u, start);
    drive_to_frame_ready();
    C2837xBlock_Run(&instance);
    assert(algorithm_context.start_calls == 1u);
    assert(instance.runtime.algorithm_started == 0u);
    assert(instance.runtime.last_error ==
           C2837X_BLOCK_ERROR_ALGORITHM_START);

    reset_fixture();
    load_frame(C2837X_MSG_SIM_START, 6u, start);
    drive_to_frame_ready();
    C2837xBlock_Run(&instance);
    assert(algorithm_context.start_calls == 1u);
    assert(instance.runtime.algorithm_started == 1u);
    channel.send_results[0] = 2;
    channel.send_results[1] = 0;
    channel.send_results[2] = 4;
    channel.send_result_count = 3u;
    C2837xBlock_Run(&instance);
    assert(instance.runtime.protocol_phase ==
           C2837X_BLOCK_PROTOCOL_WAIT_SIM_START);
    assert(channel.receive_calls == 2u);
    C2837xBlock_Run(&instance);
    assert(instance.runtime.protocol_phase ==
           C2837X_BLOCK_PROTOCOL_WAIT_SIM_START);
    assert(channel.receive_calls == 2u);
    C2837xBlock_Run(&instance);
    assert(instance.runtime.protocol_phase ==
           C2837X_BLOCK_PROTOCOL_SIM_RUNNING);
    assert(instance.runtime.state == C2837X_BLOCK_STATE_RECEIVING);
}

static void test_input_and_step_commit(void)
{
    Uint16 input[] = { 1u, 0u, 5u, 6u };

    reset_fixture();
    enter_running();
    input_object[0] = 0xaaaau;
    input_object[1] = 0xbbbbu;
    load_frame(C2837X_MSG_INPUT_DATA, 8u, input);
    drive_to_frame_ready();
    C2837xBlock_Run(&instance);
    assert(algorithm_context.decode_calls == 0u);
    assert(algorithm_context.step_calls == 0u);
    assert(input_object[0] == 0xaaaau && input_object[1] == 0xbbbbu);
    assert(tx_frame[2] == C2837X_ERR_STEP_INDEX);

    reset_fixture();
    enter_running();
    input[0] = 0u;
    load_frame(C2837X_MSG_INPUT_DATA, 8u, input);
    drive_to_frame_ready();
    C2837xBlock_Run(&instance);
    assert(algorithm_context.decode_calls == 1u);
    assert(algorithm_context.step_calls == 1u);
    assert(algorithm_context.encode_calls == 1u);
    assert(tx_frame[0] == C2837X_MSG_OUTPUT_DATA);
    assert(tx_frame[2] == 0u && tx_frame[3] == 0u);
    assert(tx_frame[4] == 15u && tx_frame[5] == 16u);
    channel.send_results[0] = 4;
    channel.send_results[1] = 8;
    channel.send_result_count = 2u;
    C2837xBlock_Run(&instance);
    assert(instance.runtime.expected_step_index == 0u);
    C2837xBlock_Run(&instance);
    assert(instance.runtime.expected_step_index == 1u);

    reset_fixture();
    instance.runtime.protocol_phase = C2837X_BLOCK_PROTOCOL_SIM_RUNNING;
    instance.runtime.algorithm_started = 1u;
    instance.runtime.expected_step_index = 0xffffffffu;
    input[0] = 0xffffu;
    input[1] = 0xffffu;
    load_frame(C2837X_MSG_INPUT_DATA, 8u, input);
    drive_to_frame_ready();
    C2837xBlock_Run(&instance);
    C2837xBlock_Run(&instance);
    assert(instance.runtime.expected_step_index == 0u);
}

static void test_stop_and_error_paths(void)
{
    static const Uint16 excess[] = { 0u, 0u, 0u, 0u, 0u };
    Uint16 resets;

    reset_fixture();
    enter_running();
    resets = algorithm_context.reset_calls;
    load_frame(C2837X_MSG_SIM_STOP, 0u, excess);
    C2837xBlock_Run(&instance);
    assert(instance.runtime.state == C2837X_BLOCK_STATE_FRAME_READY);
    C2837xBlock_Run(&instance);
    assert(channel.send_calls == 1u);
    assert(instance.runtime.close_pending == 1u);
    assert(instance.runtime.state == C2837X_BLOCK_STATE_WAIT_CONNECTION);
    assert(algorithm_context.stop_calls == 1u);
    assert(algorithm_context.reset_calls == (Uint16)(resets + 1u));

    reset_fixture();
    load_frame(C2837X_MSG_SIM_START, 10u, excess);
    C2837xBlock_Run(&instance);
    assert(instance.runtime.state == C2837X_BLOCK_STATE_SENDING);
    assert(channel.rx_offset == 4u);
    channel.send_results[0] = 2;
    channel.send_results[1] = 4;
    channel.send_result_count = 2u;
    C2837xBlock_Run(&instance);
    assert(instance.runtime.state == C2837X_BLOCK_STATE_SENDING);
    C2837xBlock_Run(&instance);
    assert(instance.runtime.close_pending == 1u);
    assert(channel.close_calls == 0u);

    reset_fixture();
    load_frame(0x9999u, 0u, excess);
    C2837xBlock_Run(&instance);
    assert(instance.runtime.last_error == C2837X_BLOCK_ERROR_PROTOCOL);
    channel.send_results[0] = -1;
    channel.send_result_count = 1u;
    C2837xBlock_Run(&instance);
    assert(instance.runtime.last_error == C2837X_BLOCK_ERROR_PROTOCOL);
    assert(instance.runtime.close_pending == 1u);

    reset_fixture();
    channel.receive_results[0] = -1;
    channel.receive_result_count = 1u;
    C2837xBlock_Run(&instance);
    assert(instance.runtime.last_error == C2837X_BLOCK_ERROR_IODEVICE);
    assert(instance.runtime.close_pending == 1u);
    assert(channel.send_calls == 0u);
}

static void test_step_failure_uses_error_response(void)
{
    Uint16 input[] = { 0u, 0u, 5u, 6u };

    reset_fixture();
    enter_running();
    algorithm_context.fail_step = 1u;
    load_frame(C2837X_MSG_INPUT_DATA, 8u, input);
    drive_to_frame_ready();
    C2837xBlock_Run(&instance);
    assert(algorithm_context.decode_calls == 1u);
    assert(algorithm_context.step_calls == 1u);
    assert(algorithm_context.encode_calls == 0u);
    assert(tx_frame[0] == C2837X_MSG_RESPONSE);
    assert(tx_frame[2] == C2837X_ERR_INTERNAL);
    assert(instance.runtime.last_error == C2837X_BLOCK_ERROR_ALGORITHM_STEP);
    channel.send_results[0] = -1;
    channel.send_result_count = 1u;
    C2837xBlock_Run(&instance);
    assert(instance.runtime.last_error == C2837X_BLOCK_ERROR_ALGORITHM_STEP);
    assert(algorithm_context.stop_calls == 1u);

}

static void test_invalid_iodevice_progress(void)
{
    static const Uint16 empty[] = { 0u };

    reset_fixture();
    channel.receive_results[0] = 1;
    channel.receive_result_count = 1u;
    C2837xBlock_Run(&instance);
    assert(instance.runtime.last_error == C2837X_BLOCK_ERROR_IODEVICE);
    assert(instance.runtime.close_pending == 1u);
    assert(channel.send_calls == 0u);

    reset_fixture();
    channel.receive_results[0] = 6;
    channel.receive_result_count = 1u;
    C2837xBlock_Run(&instance);
    assert(instance.runtime.last_error == C2837X_BLOCK_ERROR_IODEVICE);
    assert(instance.runtime.close_pending == 1u);

    reset_fixture();
    load_frame(0x9999u, 0u, empty);
    C2837xBlock_Run(&instance);
    channel.send_results[0] = 1;
    channel.send_result_count = 1u;
    C2837xBlock_Run(&instance);
    assert(instance.runtime.last_error == C2837X_BLOCK_ERROR_PROTOCOL);
    assert(instance.runtime.close_pending == 1u);

    reset_fixture();
    load_frame(0x9999u, 0u, empty);
    C2837xBlock_Run(&instance);
    channel.send_results[0] = 8;
    channel.send_result_count = 1u;
    C2837xBlock_Run(&instance);
    assert(instance.runtime.last_error == C2837X_BLOCK_ERROR_PROTOCOL);
    assert(instance.runtime.close_pending == 1u);
}

int main(void)
{
    test_header_and_payload_are_separate();
    test_fixed_length_matrix();
    test_sim_start_boundaries();
    test_input_and_step_commit();
    test_stop_and_error_paths();
    test_step_failure_uses_error_response();
    test_invalid_iodevice_progress();
    return 0;
}
