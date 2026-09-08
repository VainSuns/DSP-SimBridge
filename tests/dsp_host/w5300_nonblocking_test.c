#include <assert.h>
#include <string.h>
#include "c2837x_w5300_socket.h"

volatile struct TEST_CPU_SYS_REGS CpuSysRegs;
volatile struct TEST_DEVICE_CONFIG_REGS DevCfgRegs;
volatile struct TEST_CLOCK_CONFIG_REGS ClkCfgRegs;
volatile struct TEST_EMIF_REGS Emif1Regs;
static volatile struct TEST_EMIF_CONFIG_REGS emif_config_regs;

typedef struct { Uint32 address; Uint16 value; } RegisterValue;
static RegisterValue registers[64];
static RegisterValue writes[128];
static Uint32 reads[128];
static Uint16 register_count;
static Uint16 write_count;
static Uint16 read_count;
static Uint32 size_high;
static Uint32 size_low;
static Uint16 size_values[12];
static Uint16 size_count;
static Uint16 size_index;
static Uint16 rx_fifo_words[64];
static Uint16 rx_fifo_sn;
static Uint16 rx_fifo_count;
static Uint16 rx_fifo_index;

volatile struct TEST_EMIF_CONFIG_REGS *test_emif_config_regs(void)
{
    return &emif_config_regs;
}
void GPIO_SetupPinMux(Uint16 pin, Uint16 cpu, Uint16 mux)
{ (void)pin; (void)cpu; (void)mux; }
void GPIO_SetupPinOptions(Uint16 pin, Uint16 output, Uint16 options)
{ (void)pin; (void)output; (void)options; }
void GPIO_WritePin(Uint16 pin, Uint16 value) { (void)pin; (void)value; }
void test_delay_us(Uint32 value) { (void)value; }

static RegisterValue *find_register(Uint32 address)
{
    Uint16 i;
    for (i = 0u; i < register_count; i++)
        if (registers[i].address == address)
            return &registers[i];
    registers[register_count].address = address;
    registers[register_count].value = 0u;
    return &registers[register_count++];
}

static void set_register(Uint32 address, Uint16 value)
{
    find_register(address)->value = value;
}

Uint16 c2837x_w5300_host_read16(Uint32 address)
{
    reads[read_count++] = address;
    if ((rx_fifo_index < rx_fifo_count) &&
        (address == Sn_RX_FIFOR(rx_fifo_sn)))
        return rx_fifo_words[rx_fifo_index++];
    if ((size_index < size_count) &&
        ((address == size_high) || (address == size_low)))
    {
        assert(address == ((size_index & 1u) ? size_low : size_high));
        return size_values[size_index++];
    }
    return find_register(address)->value;
}

void c2837x_w5300_host_write16(Uint32 address, Uint16 value)
{
    writes[write_count].address = address;
    writes[write_count].value = value;
    write_count++;
    set_register(address, value);
}

static void reset_fixture(void)
{
    memset(registers, 0, sizeof(registers));
    memset(writes, 0, sizeof(writes));
    memset(reads, 0, sizeof(reads));
    register_count = 0u;
    write_count = 0u;
    read_count = 0u;
    size_high = 0u;
    size_low = 0u;
    size_count = 0u;
    size_index = 0u;
    rx_fifo_sn = 0u;
    rx_fifo_count = 0u;
    rx_fifo_index = 0u;
    c2837x_w5300_fifo_swap = 0u;
}

static void script_size(Uint32 high, Uint32 low, const Uint16 *values,
                        Uint16 count)
{
    size_high = high;
    size_low = low;
    memcpy(size_values, values, count * sizeof(values[0]));
    size_count = count;
    size_index = 0u;
}

static Uint16 fifo_word_for_wire(Uint16 first, Uint16 second)
{
    Uint16 normalized = (Uint16)((first & 0x00FFu) |
                                 ((second & 0x00FFu) << 8));

    if (c2837x_w5300_fifo_swap != 0u)
        return normalized;
    return (Uint16)((normalized << 8) | (normalized >> 8));
}

static void script_rx_fifo_bytes(Uint16 sn, const Uint16 *bytes,
                                 Uint16 count)
{
    Uint16 i;

    assert((((Uint32)count + 1u) >> 1) <=
           (sizeof(rx_fifo_words) / sizeof(rx_fifo_words[0])));
    rx_fifo_sn = sn;
    rx_fifo_count = (Uint16)(((Uint32)count + 1u) >> 1);
    rx_fifo_index = 0u;
    for (i = 0u; i < count; i = (Uint16)(i + 2u))
    {
        Uint16 second = ((Uint16)(i + 1u) < count) ? bytes[i + 1u] : 0u;
        rx_fifo_words[i >> 1] = fifo_word_for_wire(bytes[i], second);
    }
}

static Uint16 reads_of(Uint32 address)
{
    Uint16 i;
    Uint16 count = 0u;
    for (i = 0u; i < read_count; i++)
        if (reads[i] == address)
            count++;
    return count;
}

static Uint16 writes_of(Uint32 address)
{
    Uint16 i;
    Uint16 count = 0u;
    for (i = 0u; i < write_count; i++)
        if (writes[i].address == address)
            count++;
    return count;
}

static void test_command_issue_and_poll(void)
{
    reset_fixture();
    assert(c2837x_w5300_issue_sn_cr(2u, Sn_CR_OPEN) == 0);
    assert(write_count == 1u && read_count == 0u);
    assert(writes[0].address == Sn_CR(2u) && writes[0].value == Sn_CR_OPEN);
    assert(c2837x_w5300_poll_sn_cr(2u) == 0);
    assert(c2837x_w5300_poll_sn_cr(2u) == 0);
    assert(read_count == 2u);
    set_register(Sn_CR(2u), 0u);
    assert(c2837x_w5300_poll_sn_cr(2u) > 0 && read_count == 3u);
    assert(c2837x_w5300_issue_sn_cr(8u, Sn_CR_OPEN) < 0);
    assert(c2837x_w5300_poll_sn_cr(8u) < 0);
}

typedef int16 (*SizeReader)(Uint16 sn, Uint32 *value);

static void check_stable_size_reader(SizeReader reader, Uint32 high,
                                     Uint32 low)
{
    static const Uint16 first[] = {0u, 4u, 0u, 4u};
    static const Uint16 second[] = {0u, 2u, 0u, 4u, 0u, 8u, 0u, 8u};
    static const Uint16 fail[] = {
        0u, 1u, 0u, 2u, 0u, 3u, 0u, 4u, 0u, 5u, 0u, 6u};
    Uint32 value;

    reset_fixture();
    script_size(high, low, first, 4u);
    assert(reader(1u, &value) == 0 && value == 4u);
    assert(read_count == 4u);

    reset_fixture();
    script_size(high, low, second, 8u);
    assert(reader(1u, &value) == 0 && value == 8u);
    assert(read_count == 8u);

    reset_fixture();
    value = 0xA5A5A5A5u;
    script_size(high, low, fail, 12u);
    assert(reader(1u, &value) < 0);
    assert(value == 0xA5A5A5A5u && read_count == 12u);
    assert(reader(1u, 0) < 0);
}

static void test_stable_size_reads(void)
{
    check_stable_size_reader(c2837x_w5300_get_sn_tx_fsr,
                             Sn_TX_FSR(1u), Sn_TX_FSR2(1u));
    check_stable_size_reader(c2837x_w5300_get_sn_rx_rsr,
                             Sn_RX_RSR(1u), Sn_RX_RSR2(1u));
}

static void test_open_and_listen_state_windows(void)
{
    C2837xW5300Socket sk =
        C2837X_W5300_SOCKET_INITIALIZER(1u, 8192u, 8192u);
    Uint16 before;

    reset_fixture();
    assert(c2837x_w5300_socket_open(&sk, Sn_MR_TCP, 5001u,
                                     Sn_MR_ALIGN) == 0);
    assert(sk.pending_command == C2837X_W5300_COMMAND_OPEN);
    assert(sk.command_phase == C2837X_W5300_COMMAND_PHASE_WAIT_CR_CLEAR);
    assert(write_count == 9u && read_count == 0u);
    assert(writes[0].address == Sn_IR(1u));
    assert(writes[1].address == IR);
    assert(writes[2].address == Sn_MR(1u));
    assert(writes[3].address == Sn_TTLR(1u));
    assert(writes[4].address == Sn_TOSR(1u));
    assert(writes[5].address == Sn_IMR(1u));
    assert(writes[6].address == Sn_PROTOR(1u));
    assert(writes[7].address == Sn_PORTR(1u));
    assert(writes[8].address == Sn_CR(1u));

    before = write_count;
    assert(c2837x_w5300_socket_open(&sk, Sn_MR_TCP, 5001u, 0u) == 0);
    assert(write_count == before && read_count == 1u);
    set_register(Sn_CR(1u), 0u);
    assert(c2837x_w5300_socket_open(&sk, Sn_MR_TCP, 5001u, 0u) == 0);
    assert(sk.pending_command == C2837X_W5300_COMMAND_OPEN);
    assert(sk.command_phase ==
           C2837X_W5300_COMMAND_PHASE_WAIT_TARGET_STATE);
    assert(write_count == before && read_count == 2u);
    assert(reads_of(Sn_SSR(1u)) == 0u);
    assert(c2837x_w5300_socket_open(&sk, Sn_MR_TCP, 5001u, 0u) == 0);
    assert(reads_of(Sn_SSR(1u)) == 1u && write_count == before);
    assert(sk.pending_command == C2837X_W5300_COMMAND_OPEN);
    set_register(Sn_SSR(1u), SOCK_INIT);
    assert(c2837x_w5300_socket_open(&sk, Sn_MR_TCP, 5001u, 0u) > 0);
    assert(sk.pending_command == C2837X_W5300_COMMAND_NONE);
    assert(sk.command_phase == C2837X_W5300_COMMAND_PHASE_IDLE);
    assert(writes_of(Sn_CR(1u)) == 1u);
    assert(writes_of(Sn_IR(1u)) == 1u && writes_of(IR) == 1u);

    reset_fixture();
    sk.pending_command = C2837X_W5300_COMMAND_NONE;
    sk.command_phase = C2837X_W5300_COMMAND_PHASE_IDLE;
    set_register(Sn_SSR(1u), SOCK_INIT);
    assert(c2837x_w5300_socket_listen(&sk) == 0);
    assert(sk.pending_command == C2837X_W5300_COMMAND_LISTEN);
    assert(sk.command_phase == C2837X_W5300_COMMAND_PHASE_WAIT_CR_CLEAR);
    assert(read_count == 1u && write_count == 3u);
    assert(writes[0].address == Sn_IR(1u));
    assert(writes[1].address == IR);
    assert(writes[2].address == Sn_CR(1u));
    before = write_count;
    set_register(Sn_CR(1u), 0u);
    assert(c2837x_w5300_socket_listen(&sk) == 0);
    assert(write_count == before && read_count == 2u);
    assert(sk.pending_command == C2837X_W5300_COMMAND_LISTEN);
    assert(sk.command_phase ==
           C2837X_W5300_COMMAND_PHASE_WAIT_TARGET_STATE);
    assert(c2837x_w5300_socket_listen(&sk) == 0);
    assert(write_count == before && reads_of(Sn_SSR(1u)) == 2u);
    set_register(Sn_SSR(1u), SOCK_LISTEN);
    assert(c2837x_w5300_socket_listen(&sk) > 0);
    assert(sk.pending_command == C2837X_W5300_COMMAND_NONE);
    assert(sk.command_phase == C2837X_W5300_COMMAND_PHASE_IDLE);
    assert(writes_of(Sn_CR(1u)) == 1u);
    assert(writes_of(Sn_IR(1u)) == 1u && writes_of(IR) == 1u);
}

static void test_native_udp_open_and_simple_close(void)
{
    C2837xW5300Socket sk =
        C2837X_W5300_SOCKET_INITIALIZER(1u, 8192u, 8192u);
    Uint16 before;

    reset_fixture();
    set_register(Sn_SSR(1u), SOCK_CLOSED);
    assert(c2837x_w5300_socket_udp_open(&sk, 4321u) == 0);
    assert(sk.pending_command == C2837X_W5300_COMMAND_NATIVE_UDP_OPEN);
    assert(sk.command_phase == C2837X_W5300_COMMAND_PHASE_WAIT_CR_CLEAR);
    assert(write_count == 5u && read_count == 0u);
    assert(writes[0].address == Sn_IR(1u));
    assert(writes[1].address == IR && writes[1].value == (1u << 1));
    assert(writes[2].address == Sn_MR(1u) &&
           writes[2].value == Sn_MR_UDP);
    assert(writes[3].address == Sn_PORTR(1u) &&
           writes[3].value == 4321u);
    assert(writes[4].address == Sn_CR(1u) &&
           writes[4].value == Sn_CR_OPEN);
    before = write_count;

    set_register(Sn_CR(1u), Sn_CR_OPEN);
    assert(c2837x_w5300_socket_udp_open(&sk, 4321u) == 0);
    assert(read_count == 1u && write_count == before);
    set_register(Sn_CR(1u), 0u);
    assert(c2837x_w5300_socket_udp_open(&sk, 4321u) == 0);
    assert(sk.pending_command == C2837X_W5300_COMMAND_NATIVE_UDP_OPEN);
    assert(sk.command_phase ==
           C2837X_W5300_COMMAND_PHASE_WAIT_TARGET_STATE);
    assert(reads_of(Sn_SSR(1u)) == 0u && write_count == before);

    set_register(Sn_SSR(1u), SOCK_INIT);
    assert(c2837x_w5300_socket_udp_open(&sk, 4321u) == 0);
    assert(sk.pending_command == C2837X_W5300_COMMAND_NATIVE_UDP_OPEN);
    assert(reads_of(Sn_SSR(1u)) == 1u && write_count == before);
    set_register(Sn_SSR(1u), SOCK_UDP);
    assert(c2837x_w5300_socket_udp_open(&sk, 4321u) > 0);
    assert(sk.pending_command == C2837X_W5300_COMMAND_NONE);
    assert(sk.command_phase == C2837X_W5300_COMMAND_PHASE_IDLE);
    assert(writes_of(Sn_CR(1u)) == 1u);

    reset_fixture();
    sk.pending_command = C2837X_W5300_COMMAND_NONE;
    sk.command_phase = C2837X_W5300_COMMAND_PHASE_IDLE;
    assert(c2837x_w5300_socket_open(&sk, Sn_MR_UDP, 4322u, 0u) == 0);
    assert(sk.pending_command == C2837X_W5300_COMMAND_NATIVE_UDP_OPEN);
    assert(writes_of(Sn_MR(1u)) == 1u &&
           writes_of(Sn_PORTR(1u)) == 1u && writes_of(Sn_CR(1u)) == 1u);
    reset_fixture();
    sk.pending_command = C2837X_W5300_COMMAND_NONE;
    sk.command_phase = C2837X_W5300_COMMAND_PHASE_IDLE;
    assert(c2837x_w5300_socket_open(
               &sk, Sn_MR_UDP, 4322u, Sn_MR_ALIGN) < 0);
    assert(read_count == 0u && write_count == 0u);

    reset_fixture();
    sk.pending_command = C2837X_W5300_COMMAND_NONE;
    sk.command_phase = C2837X_W5300_COMMAND_PHASE_IDLE;
    set_register(Sn_MR(1u), Sn_MR_UDP);
    set_register(Sn_SSR(1u), SOCK_UDP);
    assert(c2837x_w5300_socket_issue_close(&sk) == 0);
    assert(sk.pending_command == C2837X_W5300_COMMAND_CLOSE);
    assert(sk.command_phase == C2837X_W5300_COMMAND_PHASE_WAIT_CR_CLEAR);
    assert(read_count == 0u && write_count == 3u);
    assert(writes_of(Sn_MR(1u)) == 0u);
    assert(writes_of(Sn_DIPR(1u)) == 0u &&
           writes_of(Sn_DPORTR(1u)) == 0u);
    assert(writes_of(Sn_TX_FIFOR(1u)) == 0u &&
           writes_of(Sn_TX_WRSR(1u)) == 0u);
    set_register(Sn_CR(1u), Sn_CR_CLOSE);
    assert(c2837x_w5300_socket_poll_close_command(
               &sk, C2837X_W5300_COMMAND_CLOSE) == 0);
    assert(read_count == 1u && write_count == 3u);
    set_register(Sn_CR(1u), 0u);
    assert(c2837x_w5300_socket_poll_close_command(
               &sk, C2837X_W5300_COMMAND_CLOSE) > 0);
    assert(sk.command_phase ==
           C2837X_W5300_COMMAND_PHASE_WAIT_TARGET_STATE);
    set_register(Sn_SSR(1u), SOCK_CLOSED);
    assert(c2837x_w5300_socket_get_status(&sk) == SOCK_CLOSED);
    assert(c2837x_w5300_socket_complete_close_command(
               &sk, C2837X_W5300_COMMAND_CLOSE) > 0);
    assert(sk.pending_command == C2837X_W5300_COMMAND_NONE);
    assert(sk.command_phase == C2837X_W5300_COMMAND_PHASE_IDLE);
    assert(writes_of(Sn_CR(1u)) == 1u);

    reset_fixture();
    sk.pending_command = C2837X_W5300_COMMAND_RECV;
    sk.command_phase = C2837X_W5300_COMMAND_PHASE_WAIT_CR_CLEAR;
    set_register(Sn_CR(1u), Sn_CR_RECV);
    assert(c2837x_w5300_socket_take_pending(&sk) == 0);
    assert(read_count == 1u && write_count == 0u);
    set_register(Sn_CR(1u), 0u);
    assert(c2837x_w5300_socket_take_pending(&sk) > 0);
    assert(sk.pending_command == C2837X_W5300_COMMAND_NONE);
    assert(c2837x_w5300_socket_issue_close(&sk) == 0);
    assert(writes_of(Sn_CR(1u)) == 1u);
}

static void set_rx_size(Uint16 sn, Uint16 size)
{
    set_register(Sn_RX_RSR(sn), 0u);
    set_register(Sn_RX_RSR2(sn), size);
}

static void test_udp_packet_info_fifo_swap(Uint16 fifo_swap)
{
    static const Uint16 packet_info_bytes[] = {
        0xC0u, 0xA8u, 0x01u, 0x0Au,
        0x1Fu, 0x90u, 0x00u, 0x04u
    };
    C2837xW5300Socket sk =
        C2837X_W5300_SOCKET_INITIALIZER(4u, 8192u, 8192u);
    C2837xW5300UdpPacketInfo info;

    reset_fixture();
    c2837x_w5300_fifo_swap = fifo_swap;
    set_register(Sn_SSR(4u), SOCK_UDP);
    set_rx_size(4u, C2837X_W5300_UDP_PACKET_INFO_BYTES + 4u);
    script_rx_fifo_bytes(4u, packet_info_bytes,
                         (Uint16)(sizeof(packet_info_bytes) /
                                  sizeof(packet_info_bytes[0])));

    assert(c2837x_w5300_socket_udp_rx_available(&sk) > 0);
    assert(reads_of(Sn_RX_FIFOR(4u)) == 0u);
    assert(c2837x_w5300_socket_udp_read_packet_info(&sk, &info) > 0);
    assert(info.source_ip == 0xC0A8010Au);
    assert(info.source_port == 0x1F90u);
    assert(info.data_size == 4u);
    assert(reads_of(Sn_RX_FIFOR(4u)) == 4u);
    assert(writes_of(Sn_CR(4u)) == 0u);
    assert(sk.udp_rx_datagram_active == 1u);
    assert(sk.udp_rx_data_remaining == 4u);
    assert(c2837x_w5300_socket_udp_rx_available(&sk) > 0);
}

static void test_udp_rx_availability_and_packet_info(void)
{
    C2837xW5300Socket sk =
        C2837X_W5300_SOCKET_INITIALIZER(4u, 8192u, 8192u);
    C2837xW5300UdpPacketInfo info;
    Uint16 data_words[1] = {0u};

    test_udp_packet_info_fifo_swap(0u);
    test_udp_packet_info_fifo_swap(1u);

    reset_fixture();
    set_register(Sn_SSR(4u), SOCK_UDP);
    set_rx_size(4u, 0u);
    assert(c2837x_w5300_socket_udp_rx_available(&sk) == 0);
    assert(c2837x_w5300_socket_udp_read_packet_info(&sk, &info) == 0);
    assert(c2837x_w5300_socket_udp_read_data(&sk, data_words, 2u) == 0);
    assert(reads_of(Sn_RX_FIFOR(4u)) == 0u);
    assert(writes_of(Sn_CR(4u)) == 0u);

    reset_fixture();
    set_register(Sn_SSR(4u), SOCK_ESTABLISHED);
    set_rx_size(4u, 12u);
    assert(c2837x_w5300_socket_udp_rx_available(&sk) == 0);
    assert(c2837x_w5300_socket_udp_read_packet_info(&sk, &info) == 0);
    assert(reads_of(Sn_RX_FIFOR(4u)) == 0u);
    assert(writes_of(Sn_CR(4u)) == 0u);
}

static void test_udp_staged_data_and_delayed_recv(void)
{
    static const Uint16 datagram_bytes[] = {
        0xC0u, 0xA8u, 0x01u, 0x0Au,
        0x1Fu, 0x90u, 0x00u, 0x06u,
        0xA1u, 0xB2u, 0xC3u, 0xD4u, 0xE5u, 0xF6u,
        0xEEu, 0xFFu
    };
    C2837xW5300Socket sk =
        C2837X_W5300_SOCKET_INITIALIZER(4u, 8192u, 8192u);
    C2837xW5300UdpPacketInfo info;
    Uint16 first_part[1] = {0u};
    Uint16 remaining_part[2] = {0u, 0u};

    reset_fixture();
    set_register(Sn_SSR(4u), SOCK_UDP);
    set_rx_size(4u, 14u);
    script_rx_fifo_bytes(4u, datagram_bytes,
                         (Uint16)(sizeof(datagram_bytes) /
                                  sizeof(datagram_bytes[0])));

    assert(c2837x_w5300_socket_udp_read_packet_info(&sk, &info) > 0);
    assert(info.data_size == 6u);
    assert(c2837x_w5300_socket_udp_commit_recv(&sk) < 0);
    assert(writes_of(Sn_CR(4u)) == 0u);

    assert(c2837x_w5300_socket_udp_read_data(&sk, first_part, 2u) == 2);
    assert(first_part[0] == 0xB2A1u);
    assert(sk.udp_rx_data_remaining == 4u);
    assert(writes_of(Sn_CR(4u)) == 0u);
    assert(c2837x_w5300_socket_udp_commit_recv(&sk) < 0);

    assert(c2837x_w5300_socket_udp_read_data(
               &sk, remaining_part, 10u) == 4);
    assert(remaining_part[0] == 0xD4C3u);
    assert(remaining_part[1] == 0xF6E5u);
    assert(sk.udp_rx_data_remaining == 0u);
    assert(rx_fifo_index == 7u);
    assert(c2837x_w5300_socket_udp_read_data(
               &sk, remaining_part, 2u) == 0);
    assert(rx_fifo_index == 7u);
    assert(writes_of(Sn_CR(4u)) == 0u);

    assert(c2837x_w5300_socket_udp_commit_recv(&sk) == 0);
    assert(sk.pending_command == C2837X_W5300_COMMAND_RECV);
    assert(writes_of(Sn_CR(4u)) == 1u);
    set_register(Sn_CR(4u), Sn_CR_RECV);
    assert(c2837x_w5300_socket_udp_commit_recv(&sk) == 0);
    assert(writes_of(Sn_CR(4u)) == 1u);
    set_register(Sn_CR(4u), 0u);
    assert(c2837x_w5300_socket_udp_commit_recv(&sk) > 0);
    assert(sk.pending_command == C2837X_W5300_COMMAND_NONE);
    assert(sk.udp_rx_datagram_active == 0u);
    assert(sk.udp_rx_data_remaining == 0u);
    assert(writes_of(Sn_CR(4u)) == 1u);
    assert(c2837x_w5300_socket_udp_commit_recv(&sk) < 0);
    assert(writes_of(Sn_CR(4u)) == 1u);
}

static void test_udp_odd_staged_read_3_plus_1(void)
{
    static const Uint16 datagram_bytes[] = {
        0xC0u, 0xA8u, 0x01u, 0x0Au,
        0x1Fu, 0x90u, 0x00u, 0x04u,
        0x11u, 0x22u, 0x33u, 0x44u,
        0xEEu, 0xFFu
    };
    C2837xW5300Socket sk =
        C2837X_W5300_SOCKET_INITIALIZER(4u, 8192u, 8192u);
    C2837xW5300UdpPacketInfo info;
    Uint16 first_part[2] = {0u, 0u};
    Uint16 second_part[1] = {0u};

    reset_fixture();
    set_register(Sn_SSR(4u), SOCK_UDP);
    set_rx_size(4u, 14u);
    script_rx_fifo_bytes(4u, datagram_bytes,
                         (Uint16)(sizeof(datagram_bytes) /
                                  sizeof(datagram_bytes[0])));

    assert(c2837x_w5300_socket_udp_read_packet_info(&sk, &info) > 0);
    assert(info.data_size == 4u);
    assert(c2837x_w5300_socket_udp_read_data(&sk, first_part, 3u) == 3);
    assert(first_part[0] == 0x2211u && first_part[1] == 0x0033u);
    assert(sk.udp_rx_data_remaining == 1u);
    assert(sk.udp_rx_residual_byte == 0x44u);
    assert(sk.udp_rx_residual_valid == 1u);
    assert(rx_fifo_index == 6u);
    assert(c2837x_w5300_socket_udp_commit_recv(&sk) < 0);
    assert(writes_of(Sn_CR(4u)) == 0u);

    assert(c2837x_w5300_socket_udp_read_data(&sk, second_part, 1u) == 1);
    assert(second_part[0] == 0x0044u);
    assert(sk.udp_rx_data_remaining == 0u);
    assert(sk.udp_rx_residual_valid == 0u);
    assert(rx_fifo_index == 6u);
    assert(c2837x_w5300_socket_udp_commit_recv(&sk) == 0);
    assert(writes_of(Sn_CR(4u)) == 1u);
    set_register(Sn_CR(4u), 0u);
    assert(c2837x_w5300_socket_udp_commit_recv(&sk) > 0);
    assert(writes_of(Sn_CR(4u)) == 1u);
    assert(sk.udp_rx_datagram_active == 0u);
}

static void test_udp_odd_staged_read_1_plus_remaining(void)
{
    static const Uint16 datagram_bytes[] = {
        0xC0u, 0xA8u, 0x01u, 0x0Au,
        0x1Fu, 0x90u, 0x00u, 0x05u,
        0x51u, 0x52u, 0x53u, 0x54u, 0x55u, 0x00u,
        0xEEu, 0xFFu
    };
    C2837xW5300Socket sk =
        C2837X_W5300_SOCKET_INITIALIZER(4u, 8192u, 8192u);
    C2837xW5300UdpPacketInfo info;
    Uint16 first_part[1] = {0u};
    Uint16 remaining_part[2] = {0u, 0u};

    reset_fixture();
    set_register(Sn_SSR(4u), SOCK_UDP);
    set_rx_size(4u, 13u);
    script_rx_fifo_bytes(4u, datagram_bytes,
                         (Uint16)(sizeof(datagram_bytes) /
                                  sizeof(datagram_bytes[0])));

    assert(c2837x_w5300_socket_udp_read_packet_info(&sk, &info) > 0);
    assert(info.data_size == 5u);
    assert(c2837x_w5300_socket_udp_read_data(&sk, first_part, 1u) == 1);
    assert(first_part[0] == 0x0051u);
    assert(sk.udp_rx_residual_byte == 0x52u);
    assert(sk.udp_rx_residual_valid == 1u);
    assert(rx_fifo_index == 5u);

    assert(c2837x_w5300_socket_udp_read_data(
               &sk, remaining_part, 4u) == 4);
    assert(remaining_part[0] == 0x5352u);
    assert(remaining_part[1] == 0x5554u);
    assert(sk.udp_rx_data_remaining == 0u);
    assert(sk.udp_rx_residual_valid == 0u);
    assert(rx_fifo_index == 7u);
    assert(c2837x_w5300_socket_udp_commit_recv(&sk) == 0);
    assert(writes_of(Sn_CR(4u)) == 1u);
    set_register(Sn_CR(4u), 0u);
    assert(c2837x_w5300_socket_udp_commit_recv(&sk) > 0);
}

static void test_udp_drop_and_zero_data_commit(void)
{
    static const Uint16 dropped_bytes[] = {
        0xC0u, 0xA8u, 0x01u, 0x0Au,
        0x1Fu, 0x90u, 0x00u, 0x04u,
        0x10u, 0x20u, 0x30u, 0x40u,
        0xEEu, 0xFFu
    };
    static const Uint16 zero_data_bytes[] = {
        0xC0u, 0xA8u, 0x01u, 0x0Au,
        0x1Fu, 0x90u, 0x00u, 0x00u
    };
    C2837xW5300Socket sk =
        C2837X_W5300_SOCKET_INITIALIZER(4u, 8192u, 8192u);
    C2837xW5300UdpPacketInfo info;

    reset_fixture();
    set_register(Sn_SSR(4u), SOCK_UDP);
    set_rx_size(4u, 12u);
    script_rx_fifo_bytes(4u, dropped_bytes,
                         (Uint16)(sizeof(dropped_bytes) /
                                  sizeof(dropped_bytes[0])));
    assert(c2837x_w5300_socket_udp_read_packet_info(&sk, &info) > 0);
    assert(c2837x_w5300_socket_udp_drop_data(&sk) == 4);
    assert(sk.udp_rx_data_remaining == 0u);
    assert(rx_fifo_index == 6u);
    assert(writes_of(Sn_CR(4u)) == 0u);
    assert(c2837x_w5300_socket_udp_commit_recv(&sk) == 0);
    assert(writes_of(Sn_CR(4u)) == 1u);
    set_register(Sn_CR(4u), 0u);
    assert(c2837x_w5300_socket_udp_commit_recv(&sk) > 0);

    reset_fixture();
    set_register(Sn_SSR(4u), SOCK_UDP);
    set_rx_size(4u, C2837X_W5300_UDP_PACKET_INFO_BYTES);
    script_rx_fifo_bytes(4u, zero_data_bytes,
                         (Uint16)(sizeof(zero_data_bytes) /
                                  sizeof(zero_data_bytes[0])));
    assert(c2837x_w5300_socket_udp_read_packet_info(&sk, &info) > 0);
    assert(info.data_size == 0u);
    assert(sk.udp_rx_datagram_active == 1u);
    assert(sk.udp_rx_data_remaining == 0u);
    assert(reads_of(Sn_RX_FIFOR(4u)) == 4u);
    assert(writes_of(Sn_CR(4u)) == 0u);
    assert(c2837x_w5300_socket_udp_commit_recv(&sk) == 0);
    assert(writes_of(Sn_CR(4u)) == 1u);
    set_register(Sn_CR(4u), 0u);
    assert(c2837x_w5300_socket_udp_commit_recv(&sk) > 0);
    assert(writes_of(Sn_CR(4u)) == 1u);
}

static void test_udp_odd_remaining_drop(void)
{
    static const Uint16 datagram_bytes[] = {
        0xC0u, 0xA8u, 0x01u, 0x0Au,
        0x1Fu, 0x90u, 0x00u, 0x05u,
        0x61u, 0x62u, 0x63u, 0x64u, 0x65u, 0x00u,
        0xEEu, 0xFFu
    };
    C2837xW5300Socket sk =
        C2837X_W5300_SOCKET_INITIALIZER(4u, 8192u, 8192u);
    C2837xW5300UdpPacketInfo info;
    Uint16 first_part[1] = {0u};

    reset_fixture();
    set_register(Sn_SSR(4u), SOCK_UDP);
    set_rx_size(4u, 13u);
    script_rx_fifo_bytes(4u, datagram_bytes,
                         (Uint16)(sizeof(datagram_bytes) /
                                  sizeof(datagram_bytes[0])));

    assert(c2837x_w5300_socket_udp_read_packet_info(&sk, &info) > 0);
    assert(c2837x_w5300_socket_udp_read_data(&sk, first_part, 1u) == 1);
    assert(first_part[0] == 0x0061u);
    assert(sk.udp_rx_data_remaining == 4u);
    assert(sk.udp_rx_residual_byte == 0x62u);
    assert(sk.udp_rx_residual_valid == 1u);
    assert(rx_fifo_index == 5u);
    assert(c2837x_w5300_socket_udp_drop_data(&sk) == 4);
    assert(sk.udp_rx_data_remaining == 0u);
    assert(sk.udp_rx_residual_valid == 0u);
    assert(rx_fifo_index == 7u);
    assert(writes_of(Sn_CR(4u)) == 0u);
    assert(c2837x_w5300_socket_udp_commit_recv(&sk) == 0);
    assert(writes_of(Sn_CR(4u)) == 1u);
    set_register(Sn_CR(4u), 0u);
    assert(c2837x_w5300_socket_udp_commit_recv(&sk) > 0);
    assert(writes_of(Sn_CR(4u)) == 1u);
}

static void test_send_and_receive(void)
{
    static const Uint16 stable_four[] = {0u, 4u, 0u, 4u};
    static const Uint16 unstable[] = {
        0u, 1u, 0u, 2u, 0u, 3u, 0u, 4u, 0u, 5u, 0u, 6u};
    C2837xW5300Socket sk =
        C2837X_W5300_SOCKET_INITIALIZER(3u, 8192u, 8192u);
    Uint16 data[2] = {0x0102u, 0x0304u};
    Uint16 before;

    reset_fixture();
    set_register(Sn_SSR(3u), SOCK_ESTABLISHED);
    script_size(Sn_TX_FSR(3u), Sn_TX_FSR2(3u), stable_four, 4u);
    assert(c2837x_w5300_socket_send(&sk, data, 4u) == 4);
    assert(sk.pending_command == C2837X_W5300_COMMAND_SEND);
    assert(sk.command_phase == C2837X_W5300_COMMAND_PHASE_WAIT_CR_CLEAR);
    assert(write_count == 6u);
    assert(writes[0].address == Sn_IR(3u));
    assert(writes[0].value == (Sn_IR_SENDOK | Sn_IR_TIMEOUT));
    assert(writes[1].address == Sn_TX_FIFOR(3u));
    assert(writes[2].address == Sn_TX_FIFOR(3u));
    assert(writes[3].address == Sn_TX_WRSR(3u));
    assert(writes[4].address == Sn_TX_WRSR2(3u));
    assert(writes[5].address == Sn_CR(3u));
    before = write_count;
    assert(c2837x_w5300_socket_advance_send_command(&sk) == 0);
    assert(write_count == before);
    set_register(Sn_CR(3u), 0u);
    assert(c2837x_w5300_socket_advance_send_command(&sk) > 0);
    assert(sk.pending_command == C2837X_W5300_COMMAND_NONE);
    assert(sk.command_phase == C2837X_W5300_COMMAND_PHASE_IDLE);
    script_size(Sn_TX_FSR(3u), Sn_TX_FSR2(3u), stable_four, 4u);
    assert(c2837x_w5300_socket_send(&sk, data, 4u) == 4);

    reset_fixture();
    sk.pending_command = C2837X_W5300_COMMAND_NONE;
    sk.command_phase = C2837X_W5300_COMMAND_PHASE_IDLE;
    set_register(Sn_SSR(3u), SOCK_ESTABLISHED);
    script_size(Sn_TX_FSR(3u), Sn_TX_FSR2(3u), unstable, 12u);
    assert(c2837x_w5300_socket_send(&sk, data, 4u) < 0);
    assert(write_count == 0u && size_index == 12u);

    reset_fixture();
    sk.pending_command = C2837X_W5300_COMMAND_NONE;
    sk.command_phase = C2837X_W5300_COMMAND_PHASE_IDLE;
    set_register(Sn_SSR(3u), SOCK_ESTABLISHED);
    script_size(Sn_RX_RSR(3u), Sn_RX_RSR2(3u), unstable, 12u);
    assert(c2837x_w5300_socket_recv(&sk, data, 4u) < 0);
    assert(write_count == 0u && reads_of(Sn_RX_RSR(3u)) == 6u);

    reset_fixture();
    sk.pending_command = C2837X_W5300_COMMAND_NONE;
    sk.command_phase = C2837X_W5300_COMMAND_PHASE_IDLE;
    set_register(Sn_SSR(3u), SOCK_ESTABLISHED);
    set_register(Sn_RX_FIFOR(3u), 0x1122u);
    script_size(Sn_RX_RSR(3u), Sn_RX_RSR2(3u), stable_four, 4u);
    assert(c2837x_w5300_socket_recv(&sk, data, 4u) == 4);
    assert(sk.pending_command == C2837X_W5300_COMMAND_RECV);
    assert(sk.command_phase == C2837X_W5300_COMMAND_PHASE_WAIT_CR_CLEAR);
    assert(write_count == 1u && writes[0].address == Sn_CR(3u));
    before = read_count;
    assert(c2837x_w5300_socket_recv(&sk, data, 4u) == 0);
    assert(read_count == (Uint16)(before + 1u) && write_count == 1u);
    set_register(Sn_CR(3u), 0u);
    before = read_count;
    assert(c2837x_w5300_socket_advance_recv_command(&sk) > 0);
    assert(read_count == (Uint16)(before + 1u));
    assert(sk.pending_command == C2837X_W5300_COMMAND_NONE);
    assert(sk.command_phase == C2837X_W5300_COMMAND_PHASE_IDLE);
    script_size(Sn_RX_RSR(3u), Sn_RX_RSR2(3u), stable_four, 4u);
    assert(c2837x_w5300_socket_recv(&sk, data, 4u) == 4);
}

static void test_hot_path_command_state_contracts(void)
{
    C2837xW5300Socket sk =
        C2837X_W5300_SOCKET_INITIALIZER(3u, 8192u, 8192u);
    Uint16 data[2] = {0x0102u, 0x0304u};

    reset_fixture();
    sk.pending_command = C2837X_W5300_COMMAND_NONE;
    sk.command_phase = C2837X_W5300_COMMAND_PHASE_IDLE;
    assert(c2837x_w5300_socket_advance_send_command(&sk) > 0);
    assert(c2837x_w5300_socket_advance_recv_command(&sk) > 0);
    assert(read_count == 0u && write_count == 0u);

    reset_fixture();
    sk.pending_command = C2837X_W5300_COMMAND_NONE;
    sk.command_phase = C2837X_W5300_COMMAND_PHASE_WAIT_CR_CLEAR;
    set_register(Sn_SSR(3u), SOCK_ESTABLISHED);
    assert(c2837x_w5300_socket_send(&sk, data, 4u) < 0);
    assert(write_count == 0u && read_count == 0u);
    assert(c2837x_w5300_socket_advance_send_command(&sk) < 0);
    assert(read_count == 0u && write_count == 0u);

    reset_fixture();
    sk.pending_command = C2837X_W5300_COMMAND_SEND;
    sk.command_phase = C2837X_W5300_COMMAND_PHASE_IDLE;
    set_register(Sn_SSR(3u), SOCK_ESTABLISHED);
    assert(c2837x_w5300_socket_send(&sk, data, 4u) < 0);
    assert(write_count == 0u && read_count == 0u);
    assert(c2837x_w5300_socket_advance_send_command(&sk) < 0);
    assert(read_count == 0u && write_count == 0u);

    reset_fixture();
    sk.pending_command = C2837X_W5300_COMMAND_NONE;
    sk.command_phase = C2837X_W5300_COMMAND_PHASE_WAIT_CR_CLEAR;
    set_register(Sn_SSR(3u), SOCK_ESTABLISHED);
    assert(c2837x_w5300_socket_recv(&sk, data, 4u) < 0);
    assert(read_count == 0u && write_count == 0u);
    assert(c2837x_w5300_socket_advance_recv_command(&sk) < 0);
    assert(read_count == 0u && write_count == 0u);

    reset_fixture();
    sk.pending_command = C2837X_W5300_COMMAND_RECV;
    sk.command_phase = C2837X_W5300_COMMAND_PHASE_IDLE;
    set_register(Sn_SSR(3u), SOCK_ESTABLISHED);
    assert(c2837x_w5300_socket_recv(&sk, data, 4u) < 0);
    assert(read_count == 0u && write_count == 0u);
    assert(c2837x_w5300_socket_advance_recv_command(&sk) < 0);
    assert(read_count == 0u && write_count == 0u);

    reset_fixture();
    sk.pending_command = C2837X_W5300_COMMAND_RECV;
    sk.command_phase = C2837X_W5300_COMMAND_PHASE_WAIT_CR_CLEAR;
    set_register(Sn_CR(3u), Sn_CR_RECV);
    assert(c2837x_w5300_socket_advance_send_command(&sk) < 0);
    assert(read_count == 0u && write_count == 0u);

    reset_fixture();
    sk.pending_command = C2837X_W5300_COMMAND_SEND;
    sk.command_phase = C2837X_W5300_COMMAND_PHASE_WAIT_TARGET_STATE;
    set_register(Sn_CR(3u), 0u);
    assert(c2837x_w5300_socket_advance_send_command(&sk) < 0);
    assert(read_count == 0u && write_count == 0u);

    reset_fixture();
    sk.pending_command = C2837X_W5300_COMMAND_SEND;
    sk.command_phase = C2837X_W5300_COMMAND_PHASE_WAIT_CR_CLEAR;
    set_register(Sn_CR(3u), Sn_CR_SEND);
    assert(c2837x_w5300_socket_advance_recv_command(&sk) < 0);
    assert(read_count == 0u && write_count == 0u);

    reset_fixture();
    sk.pending_command = C2837X_W5300_COMMAND_RECV;
    sk.command_phase = C2837X_W5300_COMMAND_PHASE_WAIT_TARGET_STATE;
    set_register(Sn_CR(3u), 0u);
    assert(c2837x_w5300_socket_advance_recv_command(&sk) < 0);
    assert(read_count == 0u && write_count == 0u);
}

static void test_close_primitives_and_disconnect_state_windows(void)
{
    C2837xW5300Socket sk =
        C2837X_W5300_SOCKET_INITIALIZER(1u, 8192u, 8192u);

    reset_fixture();
    assert(c2837x_w5300_socket_issue_close(&sk) == 0);
    assert(sk.pending_command == C2837X_W5300_COMMAND_CLOSE);
    assert(sk.command_phase == C2837X_W5300_COMMAND_PHASE_WAIT_CR_CLEAR);
    assert(read_count == 0u && write_count == 3u);
    assert(c2837x_w5300_socket_poll_close_command(
               &sk, C2837X_W5300_COMMAND_CLOSE) == 0);
    assert(read_count == 1u && write_count == 3u);
    set_register(Sn_CR(1u), 0u);
    assert(c2837x_w5300_socket_poll_close_command(
               &sk, C2837X_W5300_COMMAND_CLOSE) > 0);
    assert(sk.command_phase ==
           C2837X_W5300_COMMAND_PHASE_WAIT_TARGET_STATE);
    assert(c2837x_w5300_socket_complete_close_command(
               &sk, C2837X_W5300_COMMAND_CLOSE) > 0);
    assert(sk.pending_command == C2837X_W5300_COMMAND_NONE);
    assert(sk.command_phase == C2837X_W5300_COMMAND_PHASE_IDLE);
    assert(writes_of(Sn_CR(1u)) == 1u);
    assert(writes_of(Sn_IR(1u)) == 1u && writes_of(IR) == 1u);

    reset_fixture();
    sk.pending_command = C2837X_W5300_COMMAND_NONE;
    sk.command_phase = C2837X_W5300_COMMAND_PHASE_IDLE;
    set_register(Sn_SSR(1u), SOCK_CLOSE_WAIT);
    assert(c2837x_w5300_socket_disconnect(&sk) == 0);
    assert(writes_of(Sn_CR(1u)) == 1u);
    set_register(Sn_CR(1u), 0u);
    assert(c2837x_w5300_socket_disconnect(&sk) == 0);
    assert(c2837x_w5300_socket_disconnect(&sk) == 0);
    set_register(Sn_SSR(1u), SOCK_CLOSED);
    assert(c2837x_w5300_socket_disconnect(&sk) > 0);
    assert(sk.pending_command == C2837X_W5300_COMMAND_NONE);
    assert(sk.command_phase == C2837X_W5300_COMMAND_PHASE_IDLE);
    assert(writes_of(Sn_CR(1u)) == 1u);

}

static void test_conflicting_operations_do_not_issue(void)
{
    C2837xW5300Socket sk =
        C2837X_W5300_SOCKET_INITIALIZER(2u, 8192u, 8192u);
    Uint16 data[2] = {0u};

    reset_fixture();
    sk.pending_command = C2837X_W5300_COMMAND_OPEN;
    sk.command_phase = C2837X_W5300_COMMAND_PHASE_WAIT_CR_CLEAR;
    set_register(Sn_CR(2u), Sn_CR_OPEN);
    assert(c2837x_w5300_socket_listen(&sk) == 0);
    assert(read_count == 1u && write_count == 0u);
    assert(sk.pending_command == C2837X_W5300_COMMAND_OPEN);

    reset_fixture();
    sk.pending_command = C2837X_W5300_COMMAND_LISTEN;
    sk.command_phase = C2837X_W5300_COMMAND_PHASE_WAIT_TARGET_STATE;
    set_register(Sn_SSR(2u), SOCK_INIT);
    assert(c2837x_w5300_socket_open(&sk, Sn_MR_TCP, 5002u, 0u) == 0);
    assert(read_count == 1u && write_count == 0u);
    assert(sk.pending_command == C2837X_W5300_COMMAND_LISTEN);

    reset_fixture();
    sk.pending_command = C2837X_W5300_COMMAND_RECV;
    sk.command_phase = C2837X_W5300_COMMAND_PHASE_WAIT_CR_CLEAR;
    set_register(Sn_CR(2u), Sn_CR_RECV);
    assert(c2837x_w5300_socket_send(&sk, data, 4u) == 0);
    assert(read_count == 0u && write_count == 0u);

    reset_fixture();
    sk.pending_command = C2837X_W5300_COMMAND_SEND;
    sk.command_phase = C2837X_W5300_COMMAND_PHASE_WAIT_CR_CLEAR;
    set_register(Sn_CR(2u), Sn_CR_SEND);
    assert(c2837x_w5300_socket_recv(&sk, data, 4u) == 0);
    assert(read_count == 1u && write_count == 0u);
    assert(reads_of(Sn_RX_FIFOR(2u)) == 0u);

    reset_fixture();
    sk.pending_command = C2837X_W5300_COMMAND_CLOSE;
    sk.command_phase = C2837X_W5300_COMMAND_PHASE_WAIT_TARGET_STATE;
    set_register(Sn_SSR(2u), SOCK_ESTABLISHED);
    assert(c2837x_w5300_socket_open(&sk, Sn_MR_TCP, 5002u, 0u) == 0);
    assert(c2837x_w5300_socket_listen(&sk) == 0);
    assert(c2837x_w5300_socket_send(&sk, data, 4u) == 0);
    assert(c2837x_w5300_socket_recv(&sk, data, 4u) == 0);
    assert(read_count == 3u && write_count == 0u);
    assert(sk.pending_command == C2837X_W5300_COMMAND_CLOSE);

    reset_fixture();
    sk.pending_command = C2837X_W5300_COMMAND_DISCONNECT;
    sk.command_phase = C2837X_W5300_COMMAND_PHASE_WAIT_TARGET_STATE;
    set_register(Sn_SSR(2u), SOCK_CLOSE_WAIT);
    assert(c2837x_w5300_socket_open(&sk, Sn_MR_TCP, 5002u, 0u) == 0);
    assert(c2837x_w5300_socket_listen(&sk) == 0);
    assert(c2837x_w5300_socket_send(&sk, data, 4u) == 0);
    assert(c2837x_w5300_socket_recv(&sk, data, 4u) == 0);
    assert(read_count == 3u && write_count == 0u);
    assert(sk.pending_command == C2837X_W5300_COMMAND_DISCONNECT);
}

static void test_two_socket_command_phase_isolation(void)
{
    C2837xW5300Socket first =
        C2837X_W5300_SOCKET_INITIALIZER(1u, 8192u, 8192u);
    C2837xW5300Socket second =
        C2837X_W5300_SOCKET_INITIALIZER(6u, 8192u, 8192u);

    reset_fixture();
    set_register(Sn_SSR(1u), SOCK_CLOSED);
    set_register(Sn_SSR(6u), SOCK_INIT);
    assert(c2837x_w5300_socket_open(&first, Sn_MR_TCP, 5001u, 0u) == 0);
    assert(c2837x_w5300_socket_listen(&second) == 0);
    assert(first.pending_command == C2837X_W5300_COMMAND_OPEN);
    assert(second.pending_command == C2837X_W5300_COMMAND_LISTEN);
    assert(first.command_phase ==
           C2837X_W5300_COMMAND_PHASE_WAIT_CR_CLEAR);
    assert(second.command_phase ==
           C2837X_W5300_COMMAND_PHASE_WAIT_CR_CLEAR);
    assert(writes_of(Sn_CR(1u)) == 1u && writes_of(Sn_CR(6u)) == 1u);

    set_register(Sn_CR(1u), 0u);
    set_register(Sn_CR(6u), 0u);
    assert(c2837x_w5300_socket_open(&first, Sn_MR_TCP, 5001u, 0u) == 0);
    assert(c2837x_w5300_socket_listen(&second) == 0);
    assert(first.command_phase ==
           C2837X_W5300_COMMAND_PHASE_WAIT_TARGET_STATE);
    assert(second.command_phase ==
           C2837X_W5300_COMMAND_PHASE_WAIT_TARGET_STATE);

    assert(c2837x_w5300_socket_open(&first, Sn_MR_TCP, 5001u, 0u) == 0);
    assert(c2837x_w5300_socket_listen(&second) == 0);
    set_register(Sn_SSR(1u), SOCK_INIT);
    assert(c2837x_w5300_socket_open(&first, Sn_MR_TCP, 5001u, 0u) > 0);
    assert(first.pending_command == C2837X_W5300_COMMAND_NONE);
    assert(second.pending_command == C2837X_W5300_COMMAND_LISTEN);
    assert(second.command_phase ==
           C2837X_W5300_COMMAND_PHASE_WAIT_TARGET_STATE);
    set_register(Sn_SSR(6u), SOCK_LISTEN);
    assert(c2837x_w5300_socket_listen(&second) > 0);
    assert(second.pending_command == C2837X_W5300_COMMAND_NONE);
    assert(writes_of(Sn_CR(1u)) == 1u && writes_of(Sn_CR(6u)) == 1u);
}

static void assert_invalid_enum_state(C2837xW5300Socket sk)
{
    C2837xW5300Socket before = sk;

    reset_fixture();
    assert(c2837x_w5300_socket_take_pending(&sk) < 0);
    assert(read_count == 0u && write_count == 0u);
    assert(memcmp(&sk, &before, sizeof(sk)) == 0);
}

static void test_socket_enum_range_validation(void)
{
    C2837xW5300Socket sk =
        C2837X_W5300_SOCKET_INITIALIZER(1u, 8192u, 8192u);

    reset_fixture();
    assert(c2837x_w5300_socket_take_pending(&sk) > 0);
    assert(read_count == 0u && write_count == 0u);

    sk.pending_command = C2837X_W5300_COMMAND_DUMMY_SEND;
    sk.command_phase = C2837X_W5300_COMMAND_PHASE_WAIT_TARGET_STATE;
    assert(c2837x_w5300_socket_complete_close_command(
               &sk, C2837X_W5300_COMMAND_DUMMY_SEND) > 0);
    assert(read_count == 0u && write_count == 0u);

    sk.pending_command = (C2837xW5300PendingCommand)
        (C2837X_W5300_COMMAND_DUMMY_SEND + 1);
    assert_invalid_enum_state(sk);
    sk.pending_command = C2837X_W5300_COMMAND_NONE;
    sk.command_phase = (C2837xW5300CommandPhase)
        (C2837X_W5300_COMMAND_PHASE_WAIT_TARGET_STATE + 1);
    assert_invalid_enum_state(sk);
    sk.pending_command = (C2837xW5300PendingCommand)-1;
    sk.command_phase = C2837X_W5300_COMMAND_PHASE_IDLE;
    assert_invalid_enum_state(sk);
    sk.pending_command = C2837X_W5300_COMMAND_NONE;
    sk.command_phase = (C2837xW5300CommandPhase)-1;
    assert_invalid_enum_state(sk);
}

int main(void)
{
    test_command_issue_and_poll();
    test_stable_size_reads();
    test_open_and_listen_state_windows();
    test_native_udp_open_and_simple_close();
    test_udp_rx_availability_and_packet_info();
    test_udp_staged_data_and_delayed_recv();
    test_udp_odd_staged_read_3_plus_1();
    test_udp_odd_staged_read_1_plus_remaining();
    test_udp_drop_and_zero_data_commit();
    test_udp_odd_remaining_drop();
    test_send_and_receive();
    test_hot_path_command_state_contracts();
    test_close_primitives_and_disconnect_state_windows();
    test_conflicting_operations_do_not_issue();
    test_two_socket_command_phase_isolation();
    test_socket_enum_range_validation();
    return 0;
}
