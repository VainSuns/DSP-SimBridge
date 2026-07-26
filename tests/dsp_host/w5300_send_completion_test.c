#include <assert.h>
#include <string.h>
#include "c2837x_w5300_channel.h"

volatile struct TEST_CPU_SYS_REGS CpuSysRegs;
volatile struct TEST_DEVICE_CONFIG_REGS DevCfgRegs;
volatile struct TEST_CLOCK_CONFIG_REGS ClkCfgRegs;
volatile struct TEST_EMIF_REGS Emif1Regs;
static volatile struct TEST_EMIF_CONFIG_REGS emif_config_regs;

typedef struct { Uint32 address; Uint16 value; } RegisterValue;
static RegisterValue registers[128];
static RegisterValue writes[1024];
static Uint32 reads[1024];
static Uint16 register_count;
static Uint16 write_count;
static Uint16 read_count;

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

static void reset_fixture(void)
{
    memset(registers, 0, sizeof(registers));
    memset(writes, 0, sizeof(writes));
    memset(reads, 0, sizeof(reads));
    register_count = 0u;
    write_count = 0u;
    read_count = 0u;
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

static C2837xW5300Channel make_channel(Uint16 sn)
{
    C2837xW5300Channel channel = {
        C2837X_W5300_SOCKET_INITIALIZER(sn, 8192u, 8192u), 5000u, 0u,
        C2837X_W5300_SEND_IDLE, 0u, 0u, 0u};
    return channel;
}

static void set_tx_space(Uint16 sn, Uint32 octets)
{
    set_register(Sn_TX_FSR(sn), (Uint16)(octets >> 16));
    set_register(Sn_TX_FSR2(sn), (Uint16)octets);
}

static void finish_command(C2837xW5300Channel *channel,
                           const Uint16 *data, Uint32 count)
{
    Uint16 sn = channel->socket.sn;
    Uint16 ir_reads = reads_of(Sn_IR(sn));
    set_register(Sn_CR(sn), 0u);
    assert(c2837x_w5300_iodevice_ops.send(channel, data, count) == 0);
    assert(channel->socket.pending_command == C2837X_W5300_COMMAND_NONE);
    assert(channel->send_state == C2837X_W5300_SEND_PENDING);
    assert(reads_of(Sn_IR(sn)) == ir_reads);
}

static void test_delayed_progress_and_stale_events(void)
{
    C2837xW5300Channel channel = make_channel(1u);
    Uint16 first[2] = {0x0102u, 0x0304u};
    Uint16 replacement[1] = {0xA5A5u};
    Uint16 i;
    Uint16 writes_after_submit;

    reset_fixture();
    set_register(Sn_SSR(1u), SOCK_ESTABLISHED);
    set_register(Sn_IR(1u), Sn_IR_SENDOK | Sn_IR_TIMEOUT | Sn_IR_RECV);
    set_tx_space(1u, 4u);
    assert(c2837x_w5300_iodevice_ops.send(&channel, first, 4u) == 0);
    assert(channel.send_state == C2837X_W5300_SEND_PENDING);
    assert(channel.pending_octets == 4u);
    assert(channel.socket.pending_command == C2837X_W5300_COMMAND_SEND);
    assert(writes[0].address == Sn_IR(1u));
    assert(writes[0].value == (Sn_IR_SENDOK | Sn_IR_TIMEOUT));
    assert(find_register(Sn_IR(1u))->value == Sn_IR_RECV);
    assert(writes_of(Sn_TX_FIFOR(1u)) == 2u);
    assert(writes_of(Sn_TX_WRSR(1u)) == 1u);
    assert(writes_of(Sn_TX_WRSR2(1u)) == 1u);
    assert(writes_of(Sn_CR(1u)) == 1u);

    writes_after_submit = write_count;
    for (i = 0u; i < 10u; i++)
        assert(c2837x_w5300_iodevice_ops.send(&channel, replacement, 2u) == 0);
    assert(write_count == writes_after_submit);
    assert(reads_of(Sn_CR(1u)) == 10u);
    assert(reads_of(Sn_IR(1u)) == 0u);

    finish_command(&channel, replacement, 2u);
    assert(reads_of(Sn_CR(1u)) == 11u);
    assert(c2837x_w5300_iodevice_ops.send(&channel, replacement, 2u) == 0);
    assert(reads_of(Sn_SSR(1u)) == 2u);
    assert(reads_of(Sn_IR(1u)) == 1u);
    assert(channel.pending_octets == 4u);

    set_register(Sn_IR(1u), Sn_IR_SENDOK | Sn_IR_RECV);
    assert(c2837x_w5300_iodevice_ops.send(&channel, 0, 0u) == 4);
    assert(channel.send_state == C2837X_W5300_SEND_IDLE);
    assert(channel.pending_octets == 0u);
    assert(find_register(Sn_IR(1u))->value == Sn_IR_RECV);
    assert(writes_of(Sn_TX_FIFOR(1u)) == 2u);
    assert(writes_of(Sn_CR(1u)) == 1u);
}

static void prepare_pending(C2837xW5300Channel *channel, Uint32 octets)
{
    static const Uint16 words[4] = {1u, 2u, 3u, 4u};
    Uint16 sn = channel->socket.sn;
    set_register(Sn_SSR(sn), SOCK_ESTABLISHED);
    set_tx_space(sn, octets);
    assert(c2837x_w5300_iodevice_ops.send(channel, words, octets) == 0);
    finish_command(channel, words, octets);
}

static void test_timeout_and_status_priority(void)
{
    static const Uint16 invalid[] = {
        SOCK_CLOSED, SOCK_INIT, SOCK_LISTEN, 0x00FEu};
    C2837xW5300Channel channel;
    Uint16 i;

    reset_fixture();
    channel = make_channel(2u);
    prepare_pending(&channel, 4u);
    set_register(Sn_IR(2u), Sn_IR_SENDOK | Sn_IR_TIMEOUT | Sn_IR_RECV);
    assert(c2837x_w5300_iodevice_ops.send(&channel, 0, 0u) < 0);
    assert(channel.send_state == C2837X_W5300_SEND_IDLE);
    assert(channel.pending_octets == 0u);
    assert(find_register(Sn_IR(2u))->value == Sn_IR_RECV);
    assert(writes[write_count - 1u].value ==
           (Sn_IR_SENDOK | Sn_IR_TIMEOUT));

    for (i = 0u; i < (Uint16)(sizeof(invalid) / sizeof(invalid[0])); i++)
    {
        reset_fixture();
        channel = make_channel(2u);
        prepare_pending(&channel, 4u);
        set_register(Sn_SSR(2u), invalid[i]);
        set_register(Sn_IR(2u), Sn_IR_SENDOK);
        assert(c2837x_w5300_iodevice_ops.send(&channel, 0, 0u) < 0);
        assert(channel.send_state == C2837X_W5300_SEND_IDLE);
        assert(channel.pending_octets == 0u);
    }

    reset_fixture();
    channel = make_channel(2u);
    prepare_pending(&channel, 4u);
    set_register(Sn_SSR(2u), SOCK_CLOSE_WAIT);
    set_register(Sn_IR(2u), Sn_IR_SENDOK);
    assert(c2837x_w5300_iodevice_ops.send(&channel, 0, 0u) == 4);
}

static void complete_segment(C2837xW5300Channel *channel,
                             const Uint16 *data, Uint32 count)
{
    Uint16 sn = channel->socket.sn;
    set_tx_space(sn, count);
    assert(c2837x_w5300_iodevice_ops.send(channel, data, count) == 0);
    finish_command(channel, data, count);
    set_register(Sn_IR(sn), Sn_IR_SENDOK);
    assert(c2837x_w5300_iodevice_ops.send(channel, data, count) ==
           (int32)count);
}

static void test_segments_and_socket_isolation(void)
{
    C2837xW5300Channel first = make_channel(1u);
    C2837xW5300Channel second = make_channel(6u);
    Uint16 data[5] = {1u, 2u, 3u, 4u, 5u};
    Uint16 first_ir_writes;

    reset_fixture();
    set_register(Sn_SSR(1u), SOCK_ESTABLISHED);
    complete_segment(&first, data, 4u);
    complete_segment(&first, data + 2u, 4u);
    complete_segment(&first, data + 4u, 2u);
    assert(writes_of(Sn_CR(1u)) == 3u);
    assert(writes_of(Sn_TX_FIFOR(1u)) == 5u);
    assert(writes_of(Sn_TX_WRSR(1u)) == 3u);
    assert(writes_of(Sn_TX_WRSR2(1u)) == 3u);
    assert(writes_of(Sn_IR(1u)) == 6u);

    reset_fixture();
    prepare_pending(&first, 4u);
    prepare_pending(&second, 8u);
    set_register(Sn_IR(1u), Sn_IR_SENDOK);
    first_ir_writes = writes_of(Sn_IR(6u));
    assert(c2837x_w5300_iodevice_ops.send(&first, data, 10u) == 4);
    assert(second.send_state == C2837X_W5300_SEND_PENDING);
    assert(second.pending_octets == 8u);
    assert(writes_of(Sn_IR(6u)) == first_ir_writes);
    assert(c2837x_w5300_iodevice_ops.send(&second, data, 2u) == 0);
    set_register(Sn_IR(6u), Sn_IR_TIMEOUT);
    assert(c2837x_w5300_iodevice_ops.send(&second, data, 2u) < 0);
    assert(first.send_state == C2837X_W5300_SEND_IDLE);
    assert(second.send_state == C2837X_W5300_SEND_IDLE);
}

static void test_conflicts_and_init_isolation(void)
{
    C2837xW5300Channel first = make_channel(1u);
    C2837xW5300Channel second = make_channel(6u);
    Uint16 data[2] = {0u};

    reset_fixture();
    first.socket.pending_command = C2837X_W5300_COMMAND_RECV;
    first.socket.command_phase = C2837X_W5300_COMMAND_PHASE_WAIT_CR_CLEAR;
    assert(c2837x_w5300_iodevice_ops.send(&first, data, 4u) < 0);
    assert(read_count == 0u && write_count == 0u);

    first = make_channel(1u);
    first.send_state = C2837X_W5300_SEND_PENDING;
    first.pending_octets = 4u;
    first.socket.pending_command = C2837X_W5300_COMMAND_CLOSE;
    first.socket.command_phase = C2837X_W5300_COMMAND_PHASE_WAIT_CR_CLEAR;
    assert(c2837x_w5300_iodevice_ops.send(&first, data, 4u) < 0);
    assert(first.send_state == C2837X_W5300_SEND_IDLE);
    assert(first.pending_octets == 0u);
    assert(first.socket.pending_command == C2837X_W5300_COMMAND_CLOSE);
    assert(read_count == 0u && write_count == 0u);

    first.send_state = C2837X_W5300_SEND_PENDING;
    first.pending_octets = 3u;
    assert(c2837x_w5300_iodevice_ops.send(&first, data, 4u) < 0);
    assert(first.pending_octets == 0u);

    second.send_state = C2837X_W5300_SEND_PENDING;
    second.pending_octets = 8u;
    second.socket.pending_command = C2837X_W5300_COMMAND_SEND;
    second.socket.command_phase = C2837X_W5300_COMMAND_PHASE_WAIT_CR_CLEAR;
    c2837x_w5300_iodevice_ops.channel_init(&first);
    assert(second.send_state == C2837X_W5300_SEND_PENDING);
    assert(second.pending_octets == 8u);
    assert(second.socket.pending_command == C2837X_W5300_COMMAND_SEND);
}

int main(void)
{
    test_delayed_progress_and_stale_events();
    test_timeout_and_status_priority();
    test_segments_and_socket_isolation();
    test_conflicts_and_init_isolation();
    return 0;
}
