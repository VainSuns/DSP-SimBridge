#include <assert.h>
#include <string.h>

#include "c2837x_block_internal.h"
#include "c2837x_w5300_udp_channel.h"

volatile struct TEST_CPU_SYS_REGS CpuSysRegs;
volatile struct TEST_DEVICE_CONFIG_REGS DevCfgRegs;
volatile struct TEST_CLOCK_CONFIG_REGS ClkCfgRegs;
volatile struct TEST_EMIF_REGS Emif1Regs;
static volatile struct TEST_EMIF_CONFIG_REGS emif_config_regs;

typedef struct
{
    Uint32 address;
    Uint16 value;
} RegisterValue;

static RegisterValue registers[256];
static Uint16 register_count;

#define RX_FIFO_WORD_CAPACITY 1024u
static Uint16 rx_fifo_words[RX_FIFO_WORD_CAPACITY];
static Uint16 rx_fifo_bytes[2048];
static Uint16 rx_fifo_sn;
static Uint16 rx_fifo_count;
static Uint16 rx_fifo_index;

static Uint32 now_us;
static Uint32 generation;
static Uint16 udp_open_command_count;
static Uint16 udp_recv_command_count;
static Uint16 udp_send_command_count;
static Uint16 udp_close_command_count;
static Uint32 last_tx_destination_ip;
static Uint16 last_tx_destination_port;
static Uint16 receive_stall;

static Uint32 fake_time_us(void);

typedef struct
{
    Uint16 reset_calls;
    Uint16 start_calls;
    Uint16 decode_calls;
    Uint16 step_calls;
    Uint16 encode_calls;
    Uint16 stop_calls;
} FakeAlgorithm;

static FakeAlgorithm algorithm_context;
static Uint16 input_object[2];
static Uint16 output_object[2];
static Uint16 rx_frame[16];
static Uint16 tx_frame[16];

static C2837xW5300UdpChannel channel =
    C2837X_W5300_UDP_CHANNEL_INITIALIZER(
        0u, 8192u, 8192u, 5500u, fake_time_us, 100u);

static Uint32 fake_time_us(void)
{
    return now_us;
}

volatile struct TEST_EMIF_CONFIG_REGS *test_emif_config_regs(void)
{
    return &emif_config_regs;
}

void GPIO_SetupPinMux(Uint16 pin, Uint16 cpu, Uint16 mux)
{
    (void)pin;
    (void)cpu;
    (void)mux;
}

void GPIO_SetupPinOptions(Uint16 pin, Uint16 output, Uint16 options)
{
    (void)pin;
    (void)output;
    (void)options;
}

void GPIO_WritePin(Uint16 pin, Uint16 value)
{
    (void)pin;
    (void)value;
}

void test_delay_us(Uint32 value)
{
    (void)value;
}

Uint32 c2837x_block_platform_generation(void)
{
    return generation;
}

static RegisterValue *find_register(Uint32 address)
{
    Uint16 index;

    for (index = 0u; index < register_count; index++)
    {
        if (registers[index].address == address)
            return &registers[index];
    }

    assert(register_count < (Uint16)(sizeof(registers) /
                                     sizeof(registers[0])));
    registers[register_count].address = address;
    registers[register_count].value = 0u;
    register_count++;
    return &registers[register_count - 1u];
}

static void set_register(Uint32 address, Uint16 value)
{
    find_register(address)->value = value;
}

static void clear_rx_fifo(Uint16 sn)
{
    if (rx_fifo_sn == sn)
        rx_fifo_index = rx_fifo_count;
    set_register(Sn_RX_RSR(sn), 0u);
    set_register(Sn_RX_RSR2(sn), 0u);
}

Uint16 c2837x_w5300_host_read16(Uint32 address)
{
    Uint16 sn;
    RegisterValue *reg;
    Uint16 command;

    if ((rx_fifo_index < rx_fifo_count) &&
        (address == Sn_RX_FIFOR(rx_fifo_sn)))
        return rx_fifo_words[rx_fifo_index++];

    for (sn = 0u; sn < C2837X_W5300_MAX_SOCK_NUM; sn++)
    {
        if (receive_stall != 0u && address == Sn_SSR(sn))
            return SOCK_INIT;
        if (address != Sn_CR(sn))
            continue;

        reg = find_register(address);
        command = reg->value;
        if (command != 0u)
        {
            reg->value = 0u;
            if (command == Sn_CR_OPEN)
                set_register(Sn_SSR(sn), SOCK_UDP);
            else if (command == Sn_CR_CLOSE)
                set_register(Sn_SSR(sn), SOCK_CLOSED);
        }
        return reg->value;
    }

    return find_register(address)->value;
}

void c2837x_w5300_host_write16(Uint32 address, Uint16 value)
{
    Uint16 sn;
    RegisterValue *reg;

    for (sn = 0u; sn < C2837X_W5300_MAX_SOCK_NUM; sn++)
    {
        if (address == Sn_IR(sn))
        {
            reg = find_register(address);
            reg->value &= (Uint16)~value;
            return;
        }
    }

    for (sn = 0u; sn < C2837X_W5300_MAX_SOCK_NUM; sn++)
    {
        if (address != Sn_CR(sn))
            continue;

        if (value == Sn_CR_OPEN)
            udp_open_command_count++;
        else if (value == Sn_CR_RECV)
        {
            udp_recv_command_count++;
            clear_rx_fifo(sn);
        }
        else if (value == Sn_CR_SEND)
            udp_send_command_count++;
        else if (value == Sn_CR_CLOSE)
        {
            udp_close_command_count++;
            clear_rx_fifo(sn);
        }
        set_register(address, value);
        return;
    }

    for (sn = 0u; sn < C2837X_W5300_MAX_SOCK_NUM; sn++)
    {
        if (address == Sn_DIPR(sn))
        {
            last_tx_destination_ip =
                (last_tx_destination_ip & 0x0000FFFFu) |
                ((Uint32)value << 16);
            set_register(address, value);
            return;
        }
        if (address == Sn_DIPR2(sn))
        {
            last_tx_destination_ip =
                (last_tx_destination_ip & 0xFFFF0000u) | (Uint32)value;
            set_register(address, value);
            return;
        }
        if (address == Sn_DPORTR(sn))
        {
            last_tx_destination_port = value;
            set_register(address, value);
            return;
        }
    }

    set_register(address, value);
}

static Uint16 fifo_word_for_wire(Uint16 first, Uint16 second)
{
    Uint16 normalized = (Uint16)((first & 0x00FFu) |
                                 ((second & 0x00FFu) << 8));

    if (c2837x_w5300_fifo_swap != 0u)
        return normalized;
    return (Uint16)((normalized << 8) | (normalized >> 8));
}

static void set_rx_size(Uint16 sn, Uint16 size)
{
    set_register(Sn_RX_RSR(sn), 0u);
    set_register(Sn_RX_RSR2(sn), size);
}

static void set_tx_space(Uint16 sn, Uint32 size)
{
    set_register(Sn_TX_FSR(sn), (Uint16)(size >> 16));
    set_register(Sn_TX_FSR2(sn), (Uint16)size);
}

static void set_udp_datagram(Uint32 source_ip, Uint16 source_port,
                             const Uint16 *data_bytes, Uint16 data_size)
{
    Uint32 total_bytes = C2837X_W5300_UDP_PACKET_INFO_BYTES +
        (Uint32)data_size;
    Uint32 word_count = (total_bytes + 1u) >> 1;
    Uint32 index;

    assert((data_size == 0u) || (data_bytes != 0));
    assert(total_bytes <= (Uint32)sizeof(rx_fifo_bytes) /
                             sizeof(rx_fifo_bytes[0]));
    assert(word_count <= RX_FIFO_WORD_CAPACITY);

    rx_fifo_bytes[0] = (Uint16)((source_ip >> 24) & 0xFFu);
    rx_fifo_bytes[1] = (Uint16)((source_ip >> 16) & 0xFFu);
    rx_fifo_bytes[2] = (Uint16)((source_ip >> 8) & 0xFFu);
    rx_fifo_bytes[3] = (Uint16)(source_ip & 0xFFu);
    rx_fifo_bytes[4] = (Uint16)((source_port >> 8) & 0xFFu);
    rx_fifo_bytes[5] = (Uint16)(source_port & 0xFFu);
    rx_fifo_bytes[6] = (Uint16)((data_size >> 8) & 0xFFu);
    rx_fifo_bytes[7] = (Uint16)(data_size & 0xFFu);
    for (index = 0u; index < (Uint32)data_size; index++)
        rx_fifo_bytes[8u + index] = (Uint16)(data_bytes[index] & 0xFFu);

    rx_fifo_sn = channel.socket.sn;
    rx_fifo_count = (Uint16)word_count;
    rx_fifo_index = 0u;
    for (index = 0u; index < total_bytes; index += 2u)
    {
        rx_fifo_words[index >> 1] = fifo_word_for_wire(
            rx_fifo_bytes[index],
            (index + 1u < total_bytes) ? rx_fifo_bytes[index + 1u] : 0u);
    }
    set_rx_size(rx_fifo_sn, (Uint16)total_bytes);
}

static void algorithm_reset(void *context, void *input, void *output)
{
    FakeAlgorithm *algorithm = (FakeAlgorithm *)context;

    algorithm->reset_calls++;
    memset(input, 0, sizeof(input_object));
    memset(output, 0, sizeof(output_object));
}

static int16 algorithm_start(void *context)
{
    ((FakeAlgorithm *)context)->start_calls++;
    return 0;
}

static void algorithm_decode(void *input, const Uint16 *data)
{
    FakeAlgorithm *algorithm = &algorithm_context;

    algorithm->decode_calls++;
    ((Uint16 *)input)[0] = data[0];
    ((Uint16 *)input)[1] = data[1];
}

static int16 algorithm_step(void *context, const void *input,
                            void *output)
{
    FakeAlgorithm *algorithm = (FakeAlgorithm *)context;

    algorithm->step_calls++;
    ((Uint16 *)output)[0] = ((const Uint16 *)input)[0] + 1u;
    ((Uint16 *)output)[1] = ((const Uint16 *)input)[1] + 1u;
    return 0;
}

static void algorithm_encode(const void *output, Uint16 *data)
{
    FakeAlgorithm *algorithm = &algorithm_context;

    algorithm->encode_calls++;
    data[0] = ((const Uint16 *)output)[0];
    data[1] = ((const Uint16 *)output)[1];
}

static void algorithm_stop(void *context)
{
    ((FakeAlgorithm *)context)->stop_calls++;
}

static const C2837xBlock_AlgorithmAdapter algorithm = {
    algorithm_reset, algorithm_start, algorithm_decode,
    algorithm_step, algorithm_encode, algorithm_stop
};

static const C2837xBlock_Config config = {
    &c2837x_w5300_udp_iodevice_ops, &channel,
    rx_frame, 16u, tx_frame, 16u,
    input_object, output_object, &algorithm, &algorithm_context,
    1u, 0x12345678u, 8u, 6u, 12u,
    fake_time_us, 50u, 20u
};

static C2837xBlock instance =
    C2837X_BLOCK_INSTANCE_INITIALIZER(&config);

static const Uint32 PEER_A_IP = 0xC0A8010Au;
static const Uint32 PEER_B_IP = 0xC0A8010Bu;
static const Uint16 PEER_A_PORT = 0x1F90u;
static const Uint16 PEER_B_PORT = 0x1F91u;

static const Uint16 sim_start_frame[] = {
    0x01u, 0x00u, 0x06u, 0x00u,
    0x01u, 0x00u, 0x78u, 0x56u, 0x34u, 0x12u
};

static const Uint16 sim_stop_frame[] = {
    0x04u, 0x00u, 0x00u, 0x00u
};

static const Uint16 input_frame[] = {
    0x02u, 0x00u, 0x08u, 0x00u,
    0x00u, 0x00u, 0x00u, 0x00u,
    0x11u, 0x22u, 0x33u, 0x44u
};

static void reset_fixture(void)
{
    memset(registers, 0, sizeof(registers));
    memset(rx_fifo_words, 0, sizeof(rx_fifo_words));
    memset(rx_fifo_bytes, 0, sizeof(rx_fifo_bytes));
    memset(&algorithm_context, 0, sizeof(algorithm_context));
    memset(rx_frame, 0, sizeof(rx_frame));
    memset(tx_frame, 0, sizeof(tx_frame));
    register_count = 0u;
    rx_fifo_sn = 0u;
    rx_fifo_count = 0u;
    rx_fifo_index = 0u;
    now_us = 0u;
    generation = 1u;
    udp_open_command_count = 0u;
    udp_recv_command_count = 0u;
    udp_send_command_count = 0u;
    udp_close_command_count = 0u;
    last_tx_destination_ip = 0u;
    last_tx_destination_port = 0u;
    receive_stall = 0u;
    c2837x_w5300_fifo_swap = 0u;
    set_register(Sn_SSR(channel.socket.sn), SOCK_CLOSED);
    set_tx_space(channel.socket.sn, channel.socket.tx_mem_size);

    C2837xBlock_Init(&instance);
    assert(C2837xBlock_GetLastError(&instance) ==
           C2837X_BLOCK_ERROR_NONE);
    assert(instance.runtime.state == C2837X_BLOCK_STATE_WAIT_CONNECTION);
    assert(instance.runtime.protocol_phase ==
           C2837X_BLOCK_PROTOCOL_WAIT_SIM_START);
    assert(instance.runtime.close_pending == 0u);
    assert(channel.candidate_valid == 0u);
    assert(algorithm_context.reset_calls == 1u);
}

static void drive_to_listening(void)
{
    C2837xBlock_Run(&instance);
    C2837xBlock_Run(&instance);
    C2837xBlock_Run(&instance);
    C2837xBlock_Run(&instance);

    assert(instance.runtime.state == C2837X_BLOCK_STATE_WAIT_CONNECTION);
    assert(instance.runtime.close_pending == 0u);
    assert(channel.socket.pending_command ==
           C2837X_W5300_COMMAND_NONE);
    assert(channel.close_state == C2837X_W5300_UDP_CLOSE_IDLE);
    assert(channel.candidate_valid == 0u);
    assert(c2837x_w5300_get_sn_ssr(channel.socket.sn) == SOCK_UDP);
    assert(udp_open_command_count == 1u);
}

static void assert_candidate(Uint32 ip, Uint16 port)
{
    assert(channel.candidate_valid != 0u);
    assert(channel.candidate_ip == ip);
    assert(channel.candidate_port == port);
}

static void assert_runtime_cleared(void)
{
    assert(channel.candidate_valid == 0u);
    assert(channel.candidate_ip == 0u);
    assert(channel.candidate_port == 0u);
    assert(channel.datagram_active == 0u);
    assert(channel.datagram_data_size == 0u);
    assert(channel.datagram_consumed == 0u);
    assert(channel.send_state == C2837X_W5300_UDP_SEND_IDLE);
    assert(channel.pending_octets == 0u);
    assert(channel.close_state == C2837X_W5300_UDP_CLOSE_IDLE);
    assert(channel.faulted == 0u);
    assert(channel.socket.pending_command ==
           C2837X_W5300_COMMAND_NONE);
    assert(channel.socket.command_phase ==
           C2837X_W5300_COMMAND_PHASE_IDLE);
    assert(channel.socket.udp_rx_datagram_active == 0u);
    assert(channel.socket.udp_rx_data_remaining == 0u);
    assert(channel.socket.udp_rx_residual_byte == 0u);
    assert(channel.socket.udp_rx_residual_valid == 0u);
}

static void drive_close_and_reopen(void)
{
    Uint16 open_count_before = udp_open_command_count;
    Uint16 close_count_before = udp_close_command_count;

    assert(instance.runtime.close_pending != 0u);
    C2837xBlock_Run(&instance);
    if (channel.close_state ==
        C2837X_W5300_UDP_CLOSE_WAIT_EXISTING_CR)
        C2837xBlock_Run(&instance);
    C2837xBlock_Run(&instance);
    C2837xBlock_Run(&instance);
    C2837xBlock_Run(&instance);

    assert(instance.runtime.close_pending == 0u);
    assert(udp_close_command_count ==
           (Uint16)(close_count_before + 1u));
    assert_runtime_cleared();
    assert(c2837x_w5300_get_sn_ssr(channel.socket.sn) == SOCK_CLOSED);

    C2837xBlock_Run(&instance);
    C2837xBlock_Run(&instance);
    C2837xBlock_Run(&instance);
    C2837xBlock_Run(&instance);

    assert(instance.runtime.state == C2837X_BLOCK_STATE_WAIT_CONNECTION);
    assert(channel.socket.pending_command ==
           C2837X_W5300_COMMAND_NONE);
    assert(channel.close_state == C2837X_W5300_UDP_CLOSE_IDLE);
    assert(channel.candidate_valid == 0u);
    assert(c2837x_w5300_get_sn_ssr(channel.socket.sn) == SOCK_UDP);
    assert(udp_open_command_count ==
           (Uint16)(open_count_before + 1u));
}

static void complete_send(void)
{
    C2837xBlock_Run(&instance);
    assert(channel.socket.pending_command ==
           C2837X_W5300_COMMAND_NONE);
    set_register(Sn_IR(channel.socket.sn), Sn_IR_SENDOK);
    C2837xBlock_Run(&instance);
}

static void run_valid_sim_start(Uint32 ip, Uint16 port)
{
    Uint16 send_count_before = udp_send_command_count;
    Uint16 start_count_before = algorithm_context.start_calls;
    Uint16 stop_count_before = algorithm_context.stop_calls;

    set_udp_datagram(ip, port, sim_start_frame,
                     (Uint16)sizeof(sim_start_frame) /
                     (Uint16)sizeof(sim_start_frame[0]));

    /* WAIT_CONNECTION observes the UDP packet and accepts its endpoint. */
    C2837xBlock_Run(&instance);
    assert_candidate(ip, port);
    assert(instance.runtime.state == C2837X_BLOCK_STATE_RECEIVING);

    /* Core receives the real UDP header and payload through the channel. */
    C2837xBlock_Run(&instance);
    assert(instance.runtime.rx_phase == C2837X_BLOCK_RX_PAYLOAD);
    C2837xBlock_Run(&instance);
    assert(instance.runtime.state == C2837X_BLOCK_STATE_FRAME_READY);
    assert(channel.socket.pending_command ==
           C2837X_W5300_COMMAND_RECV);

    /* Core validates SIM_START and the channel sends its RESPONSE. */
    C2837xBlock_Run(&instance);
    assert(instance.runtime.state == C2837X_BLOCK_STATE_SENDING);
    C2837xBlock_Run(&instance);
    assert(channel.socket.pending_command ==
           C2837X_W5300_COMMAND_NONE);
    C2837xBlock_Run(&instance);
    assert(channel.socket.pending_command ==
           C2837X_W5300_COMMAND_SEND);
    complete_send();

    assert(instance.runtime.state == C2837X_BLOCK_STATE_RECEIVING);
    assert(instance.runtime.protocol_phase ==
           C2837X_BLOCK_PROTOCOL_SIM_RUNNING);
    assert(channel.datagram_active == 0u);
    assert(channel.datagram_data_size == 0u);
    assert(channel.datagram_consumed == 0u);
    assert(channel.socket.udp_rx_datagram_active == 0u);
    assert(channel.socket.udp_rx_data_remaining == 0u);
    assert(channel.socket.udp_rx_residual_valid == 0u);
    assert(algorithm_context.start_calls ==
           (Uint16)(start_count_before + 1u));
    assert(algorithm_context.stop_calls == stop_count_before);
    assert(tx_frame[0] == C2837X_MSG_RESPONSE);
    assert(tx_frame[1] == 2u);
    assert(tx_frame[2] == C2837X_ERR_OK);
    assert(last_tx_destination_ip == ip);
    assert(last_tx_destination_port == port);
    assert(udp_send_command_count ==
           (Uint16)(send_count_before + 1u));
}

static void assert_response(Uint16 error, Uint32 ip, Uint16 port)
{
    assert(tx_frame[0] == C2837X_MSG_RESPONSE);
    assert(tx_frame[1] == 2u);
    assert(tx_frame[2] == error);
    assert(last_tx_destination_ip == ip);
    assert(last_tx_destination_port == port);
}

static void complete_error_response(Uint16 error, Uint32 ip, Uint16 port)
{
    C2837xBlock_Run(&instance);
    assert(channel.socket.pending_command ==
           C2837X_W5300_COMMAND_SEND);
    complete_send();
    assert_response(error, ip, port);
    assert(instance.runtime.close_pending != 0u);
    assert(C2837xBlock_GetLastError(&instance) ==
           C2837X_BLOCK_ERROR_PROTOCOL);
}

static void test_valid_sim_start_integrated(void)
{
    reset_fixture();
    drive_to_listening();
    run_valid_sim_start(PEER_A_IP, PEER_A_PORT);
    assert(C2837xBlock_GetLastError(&instance) ==
           C2837X_BLOCK_ERROR_NONE);
    assert(channel.candidate_ip == PEER_A_IP);
    assert(channel.candidate_port == PEER_A_PORT);

    /* A later same-peer INPUT_DATA datagram starts as a fresh frame. */
    set_udp_datagram(PEER_A_IP, PEER_A_PORT, input_frame,
                     (Uint16)sizeof(input_frame) /
                     (Uint16)sizeof(input_frame[0]));
    C2837xBlock_Run(&instance);
    assert(instance.runtime.rx_phase == C2837X_BLOCK_RX_PAYLOAD);
    assert(instance.runtime.rx_header_received_octets ==
           C2837X_BLOCK_HEADER_SIZE_BYTES);
    C2837xBlock_Run(&instance);
    assert(instance.runtime.state == C2837X_BLOCK_STATE_FRAME_READY);
    assert(instance.runtime.rx_payload_received_octets ==
           config.input_payload_octets);
    assert(C2837xBlock_GetLastError(&instance) ==
           C2837X_BLOCK_ERROR_NONE);
}

static void test_invalid_candidate_is_rejected_and_reopened(void)
{
    reset_fixture();
    drive_to_listening();
    set_udp_datagram(PEER_A_IP, PEER_A_PORT, input_frame,
                     (Uint16)sizeof(input_frame) /
                     (Uint16)sizeof(input_frame[0]));

    C2837xBlock_Run(&instance);
    assert_candidate(PEER_A_IP, PEER_A_PORT);
    C2837xBlock_Run(&instance);
    assert(instance.runtime.state == C2837X_BLOCK_STATE_SENDING);
    assert(instance.runtime.response_error == C2837X_ERR_STATE);
    complete_error_response(C2837X_ERR_STATE, PEER_A_IP, PEER_A_PORT);
    assert(udp_send_command_count == 1u);
    drive_close_and_reopen();

    run_valid_sim_start(PEER_B_IP, PEER_B_PORT);
    assert_candidate(PEER_B_IP, PEER_B_PORT);
}

static void test_same_peer_repeated_sim_start_terminates(void)
{
    reset_fixture();
    drive_to_listening();
    run_valid_sim_start(PEER_A_IP, PEER_A_PORT);

    set_udp_datagram(PEER_A_IP, PEER_A_PORT, sim_start_frame,
                     (Uint16)sizeof(sim_start_frame) /
                     (Uint16)sizeof(sim_start_frame[0]));
    C2837xBlock_Run(&instance);
    assert(instance.runtime.state == C2837X_BLOCK_STATE_SENDING);
    assert(instance.runtime.response_error == C2837X_ERR_STATE);
    assert_candidate(PEER_A_IP, PEER_A_PORT);
    complete_error_response(C2837X_ERR_STATE, PEER_A_IP, PEER_A_PORT);
    assert(algorithm_context.stop_calls == 1u);
    drive_close_and_reopen();
}

static void test_normal_sim_stop_clears_and_reacquires(void)
{
    reset_fixture();
    drive_to_listening();
    run_valid_sim_start(PEER_A_IP, PEER_A_PORT);

    set_udp_datagram(PEER_A_IP, PEER_A_PORT, sim_stop_frame,
                     (Uint16)sizeof(sim_stop_frame) /
                     (Uint16)sizeof(sim_stop_frame[0]));
    C2837xBlock_Run(&instance);
    assert(instance.runtime.state == C2837X_BLOCK_STATE_FRAME_READY);
    assert(channel.socket.pending_command ==
           C2837X_W5300_COMMAND_RECV);
    C2837xBlock_Run(&instance);
    assert(instance.runtime.close_pending != 0u);
    assert(algorithm_context.stop_calls == 1u);
    assert(C2837xBlock_GetLastError(&instance) ==
           C2837X_BLOCK_ERROR_NONE);
    drive_close_and_reopen();

    run_valid_sim_start(PEER_B_IP, PEER_B_PORT);
    assert_candidate(PEER_B_IP, PEER_B_PORT);
}

static void test_alien_sim_start_cannot_refresh_timeout(void)
{
    Uint32 progress_start;
    Uint16 send_count_before;

    reset_fixture();
    drive_to_listening();
    run_valid_sim_start(PEER_A_IP, PEER_A_PORT);
    progress_start = instance.runtime.progress_start_us;
    send_count_before = udp_send_command_count;

    set_udp_datagram(PEER_B_IP, PEER_B_PORT, sim_start_frame,
                     (Uint16)sizeof(sim_start_frame) /
                     (Uint16)sizeof(sim_start_frame[0]));
    C2837xBlock_Run(&instance);
    assert(instance.runtime.state == C2837X_BLOCK_STATE_RECEIVING);
    assert_candidate(PEER_A_IP, PEER_A_PORT);
    assert(instance.runtime.progress_start_us == progress_start);
    assert(udp_send_command_count == send_count_before);

    now_us = progress_start + config.interaction_timeout_us;
    C2837xBlock_Run(&instance);
    assert(C2837xBlock_GetLastError(&instance) ==
           C2837X_BLOCK_ERROR_TIMEOUT);
    assert(instance.runtime.close_pending != 0u);
    assert(algorithm_context.stop_calls == 1u);
    assert(udp_send_command_count == send_count_before);
    drive_close_and_reopen();
}

static void test_lost_sim_stop_times_out_and_reopens(void)
{
    Uint32 progress_start;

    reset_fixture();
    drive_to_listening();
    run_valid_sim_start(PEER_A_IP, PEER_A_PORT);
    progress_start = instance.runtime.progress_start_us;
    now_us = progress_start + config.interaction_timeout_us;

    C2837xBlock_Run(&instance);
    assert(C2837xBlock_GetLastError(&instance) ==
           C2837X_BLOCK_ERROR_TIMEOUT);
    assert(instance.runtime.close_pending != 0u);
    assert(algorithm_context.stop_calls == 1u);
    drive_close_and_reopen();
}

static void test_partial_udp_transfer_times_out_and_reopens(void)
{
    Uint32 progress_start;

    reset_fixture();
    drive_to_listening();
    run_valid_sim_start(PEER_A_IP, PEER_A_PORT);

    /* A real UDP datagram has delivered its V1 header, then the socket
     * stops making progress before the payload arrives. */
    set_udp_datagram(PEER_A_IP, PEER_A_PORT, input_frame,
                     (Uint16)sizeof(input_frame) /
                     (Uint16)sizeof(input_frame[0]));
    C2837xBlock_Run(&instance);
    assert(instance.runtime.rx_phase == C2837X_BLOCK_RX_PAYLOAD);
    assert(channel.datagram_consumed == 4u);
    assert(channel.socket.udp_rx_data_remaining ==
           config.input_payload_octets);
    progress_start = instance.runtime.progress_start_us;

    receive_stall = 1u;
    now_us = progress_start + config.transfer_timeout_us - 1u;
    C2837xBlock_Run(&instance);
    assert(instance.runtime.state == C2837X_BLOCK_STATE_RECEIVING);
    assert(instance.runtime.progress_start_us == progress_start);
    assert(channel.socket.udp_rx_data_remaining ==
           config.input_payload_octets);

    now_us = progress_start + config.transfer_timeout_us;
    C2837xBlock_Run(&instance);
    assert(C2837xBlock_GetLastError(&instance) ==
           C2837X_BLOCK_ERROR_TIMEOUT);
    assert(instance.runtime.close_pending != 0u);
    assert(algorithm_context.stop_calls == 1u);

    receive_stall = 0u;
    drive_close_and_reopen();
}

static void test_late_stale_input_rejected_before_new_candidate(void)
{
    reset_fixture();
    drive_to_listening();
    run_valid_sim_start(PEER_A_IP, PEER_A_PORT);

    set_udp_datagram(PEER_A_IP, PEER_A_PORT, sim_stop_frame,
                     (Uint16)sizeof(sim_stop_frame) /
                     (Uint16)sizeof(sim_stop_frame[0]));
    C2837xBlock_Run(&instance);
    C2837xBlock_Run(&instance);
    assert(instance.runtime.close_pending != 0u);
    drive_close_and_reopen();
    assert_runtime_cleared();

    set_udp_datagram(PEER_A_IP, PEER_A_PORT, input_frame,
                     (Uint16)sizeof(input_frame) /
                     (Uint16)sizeof(input_frame[0]));
    C2837xBlock_Run(&instance);
    assert_candidate(PEER_A_IP, PEER_A_PORT);
    C2837xBlock_Run(&instance);
    assert(instance.runtime.state == C2837X_BLOCK_STATE_SENDING);
    complete_error_response(C2837X_ERR_STATE, PEER_A_IP, PEER_A_PORT);
    drive_close_and_reopen();

    run_valid_sim_start(PEER_B_IP, PEER_B_PORT);
    assert_candidate(PEER_B_IP, PEER_B_PORT);
}

int main(int argc, char **argv)
{
    test_valid_sim_start_integrated();
    if ((argc > 1) && (strcmp(argv[1], "full") == 0))
    {
        test_invalid_candidate_is_rejected_and_reopened();
        test_same_peer_repeated_sim_start_terminates();
        test_normal_sim_stop_clears_and_reacquires();
        test_alien_sim_start_cannot_refresh_timeout();
        test_lost_sim_stop_times_out_and_reopens();
        test_partial_udp_transfer_times_out_and_reopens();
        test_late_stale_input_rejected_before_new_candidate();
    }
    return 0;
}
