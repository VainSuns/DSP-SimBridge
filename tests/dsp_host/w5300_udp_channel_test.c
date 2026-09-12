#include <assert.h>
#include <string.h>
#include "c2837x_w5300_udp_channel.h"

volatile struct TEST_CPU_SYS_REGS CpuSysRegs;
volatile struct TEST_DEVICE_CONFIG_REGS DevCfgRegs;
volatile struct TEST_CLOCK_CONFIG_REGS ClkCfgRegs;
volatile struct TEST_EMIF_REGS Emif1Regs;
static volatile struct TEST_EMIF_CONFIG_REGS emif_config_regs;

typedef struct { Uint32 address; Uint16 value; } RegisterValue;
static RegisterValue registers[128];
static RegisterValue writes[256];
static Uint32 reads[512];
static Uint16 register_count;
static Uint16 write_count;
static Uint16 read_count;
static Uint16 rx_fifo_words[8];
static Uint16 rx_fifo_sn;
static Uint16 rx_fifo_count;
static Uint16 rx_fifo_index;
static Uint32 now_us;
static Uint32 generation;

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
    return find_register(address)->value;
}

void c2837x_w5300_host_write16(Uint32 address, Uint16 value)
{
    Uint16 sn;

    writes[write_count].address = address;
    writes[write_count].value = value;
    write_count++;
    for (sn = 0u; sn < C2837X_W5300_MAX_SOCK_NUM; sn++)
    {
        if (address == Sn_IR(sn))
        {
            find_register(address)->value &= (Uint16)~value;
            return;
        }
    }
    set_register(address, value);
}

Uint32 c2837x_block_platform_generation(void)
{
    return generation;
}

static Uint32 fake_time_us(void)
{
    return now_us;
}

static void reset_fixture(void)
{
    memset(registers, 0, sizeof(registers));
    memset(writes, 0, sizeof(writes));
    memset(reads, 0, sizeof(reads));
    memset(rx_fifo_words, 0, sizeof(rx_fifo_words));
    register_count = 0u;
    write_count = 0u;
    read_count = 0u;
    rx_fifo_sn = 0u;
    rx_fifo_count = 0u;
    rx_fifo_index = 0u;
    now_us = 0u;
    generation = 1u;
    c2837x_w5300_fifo_swap = 0u;
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

static Uint16 reads_of(Uint32 address)
{
    Uint16 i;
    Uint16 count = 0u;

    for (i = 0u; i < read_count; i++)
        if (reads[i] == address)
            count++;
    return count;
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

static void set_packet_info(Uint16 sn)
{
    static const Uint16 packet_info[] = {
        0xC0u, 0xA8u, 0x01u, 0x0Au,
        0x1Fu, 0x90u, 0x00u, 0x04u
    };
    Uint16 i;

    rx_fifo_sn = sn;
    rx_fifo_count = 4u;
    rx_fifo_index = 0u;
    for (i = 0u; i < 8u; i = (Uint16)(i + 2u))
    {
        rx_fifo_words[i >> 1] = fifo_word_for_wire(
            packet_info[i], packet_info[i + 1u]);
    }
    set_rx_size(sn, C2837X_W5300_UDP_PACKET_INFO_BYTES + 4u);
}

static C2837xW5300UdpChannel make_channel(Uint16 sn)
{
    return (C2837xW5300UdpChannel)C2837X_W5300_UDP_CHANNEL_INITIALIZER(
        sn, 8192u, 8192u, 5500u, fake_time_us, 100u);
}

static void finish_udp_open(C2837xW5300UdpChannel *channel)
{
    Uint16 sn = channel->socket.sn;
    Uint16 mr_writes = writes_of(Sn_MR(sn));
    Uint16 port_writes = writes_of(Sn_PORTR(sn));
    Uint16 cr_writes = writes_of(Sn_CR(sn));

    assert(c2837x_w5300_udp_iodevice_ops.open(channel) == 0);
    assert(writes_of(Sn_MR(sn)) == (Uint16)(mr_writes + 1u));
    assert(writes_of(Sn_PORTR(sn)) == (Uint16)(port_writes + 1u));
    assert(writes_of(Sn_CR(sn)) == (Uint16)(cr_writes + 1u));
    assert(writes[write_count - 1u].address == Sn_CR(sn));
    assert(writes[write_count - 1u].value == Sn_CR_OPEN);

    set_register(Sn_CR(sn), 0u);
    assert(c2837x_w5300_udp_iodevice_ops.open(channel) == 0);
    set_register(Sn_SSR(sn), SOCK_UDP);
    assert(c2837x_w5300_udp_iodevice_ops.open(channel) > 0);
    assert(channel->socket.pending_command == C2837X_W5300_COMMAND_NONE);
}

static void test_open_logical_listen_candidate_and_repeated_state(void)
{
    C2837xW5300UdpChannel channel;
    Uint16 fifo_reads;
    Uint16 writes_before_placeholder;
    Uint16 words[2] = {0u, 0u};

    reset_fixture();
    channel = make_channel(2u);
    c2837x_w5300_udp_iodevice_ops.channel_init(&channel);
    set_register(Sn_SSR(2u), SOCK_CLOSED);
    assert(c2837x_w5300_udp_iodevice_ops.get_connection_state(&channel) ==
           C2837X_IODEVICE_CONNECTION_CLOSED);

    finish_udp_open(&channel);
    assert(c2837x_w5300_udp_iodevice_ops.listen(&channel) > 0);
    assert(writes_of(Sn_CR(2u)) == 1u);
    assert(c2837x_w5300_udp_iodevice_ops.get_connection_state(&channel) ==
           C2837X_IODEVICE_CONNECTION_LISTENING);
    assert(channel.candidate_valid == 0u);

    set_packet_info(2u);
    assert(c2837x_w5300_udp_iodevice_ops.get_connection_state(&channel) ==
           C2837X_IODEVICE_CONNECTION_CONNECTED);
    assert(channel.candidate_ip == 0xC0A8010Au);
    assert(channel.candidate_port == 0x1F90u);
    assert(channel.candidate_valid == 1u);
    assert(channel.datagram_active == 1u);
    assert(channel.datagram_data_size == 4u);
    assert(channel.datagram_consumed == 0u);
    assert(channel.socket.udp_rx_datagram_active == 1u);
    assert(channel.socket.udp_rx_data_remaining == 4u);
    fifo_reads = reads_of(Sn_RX_FIFOR(2u));
    assert(fifo_reads == 4u);

    assert(c2837x_w5300_udp_iodevice_ops.get_connection_state(&channel) ==
           C2837X_IODEVICE_CONNECTION_CONNECTED);
    assert(reads_of(Sn_RX_FIFOR(2u)) == fifo_reads);
    assert(channel.socket.udp_rx_data_remaining == 4u);

    writes_before_placeholder = write_count;
    assert(c2837x_w5300_udp_iodevice_ops.receive(&channel, words, 4u) == 0);
    assert(c2837x_w5300_udp_iodevice_ops.send(&channel, words, 4u) == 0);
    assert(reads_of(Sn_RX_FIFOR(2u)) == fifo_reads);
    assert(write_count == writes_before_placeholder);
}

static void test_simple_close_clears_state_and_reopens(void)
{
    C2837xW5300UdpChannel channel;

    reset_fixture();
    channel = make_channel(3u);
    c2837x_w5300_udp_iodevice_ops.channel_init(&channel);
    set_register(Sn_SSR(3u), SOCK_UDP);
    finish_udp_open(&channel);
    set_packet_info(3u);
    assert(c2837x_w5300_udp_iodevice_ops.get_connection_state(&channel) ==
           C2837X_IODEVICE_CONNECTION_CONNECTED);

    assert(c2837x_w5300_udp_iodevice_ops.close(&channel) == 0);
    assert(channel.close_state == C2837X_W5300_UDP_CLOSE_ISSUE);
    assert(c2837x_w5300_udp_iodevice_ops.close(&channel) == 0);
    assert(channel.close_state == C2837X_W5300_UDP_CLOSE_WAIT_CR);
    assert(writes_of(Sn_CR(3u)) == 2u);
    assert(writes[write_count - 1u].value == Sn_CR_CLOSE);
    assert(writes_of(Sn_CR(3u)) != 3u);
    assert(writes_of(Sn_MR(3u)) == 1u);
    assert(writes_of(Sn_DIPR(3u)) == 0u);
    assert(writes_of(Sn_DIPR2(3u)) == 0u);
    assert(writes_of(Sn_DPORTR(3u)) == 0u);
    assert(writes_of(Sn_TX_FIFOR(3u)) == 0u);
    assert(writes_of(Sn_TX_WRSR(3u)) == 0u);
    assert(writes_of(Sn_TX_WRSR2(3u)) == 0u);
    set_register(Sn_CR(3u), 0u);
    assert(c2837x_w5300_udp_iodevice_ops.close(&channel) == 0);
    assert(channel.close_state == C2837X_W5300_UDP_CLOSE_WAIT_STATE);
    set_register(Sn_SSR(3u), SOCK_CLOSED);
    assert(c2837x_w5300_udp_iodevice_ops.close(&channel) > 0);

    assert(channel.candidate_valid == 0u);
    assert(channel.candidate_ip == 0u && channel.candidate_port == 0u);
    assert(channel.datagram_active == 0u);
    assert(channel.datagram_data_size == 0u);
    assert(channel.datagram_consumed == 0u);
    assert(channel.send_state == C2837X_W5300_UDP_SEND_IDLE);
    assert(channel.pending_octets == 0u);
    assert(channel.close_state == C2837X_W5300_UDP_CLOSE_IDLE);
    assert(channel.faulted == 0u);
    assert(channel.socket.udp_rx_datagram_active == 0u);
    assert(channel.socket.udp_rx_data_remaining == 0u);
    assert(channel.socket.pending_command == C2837X_W5300_COMMAND_NONE);

    set_register(Sn_SSR(3u), SOCK_CLOSED);
    set_rx_size(3u, 0u);
    finish_udp_open(&channel);
    assert(c2837x_w5300_udp_iodevice_ops.get_connection_state(&channel) ==
           C2837X_IODEVICE_CONNECTION_LISTENING);
}

int main(void)
{
    test_open_logical_listen_candidate_and_repeated_state();
    test_simple_close_clears_state_and_reopens();
    return 0;
}
