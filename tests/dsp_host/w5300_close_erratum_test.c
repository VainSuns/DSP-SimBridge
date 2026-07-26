#include <assert.h>
#include <string.h>
#include "c2837x_w5300_channel.h"

volatile struct TEST_CPU_SYS_REGS CpuSysRegs;
volatile struct TEST_DEVICE_CONFIG_REGS DevCfgRegs;
volatile struct TEST_CLOCK_CONFIG_REGS ClkCfgRegs;
volatile struct TEST_EMIF_REGS Emif1Regs;
static volatile struct TEST_EMIF_CONFIG_REGS emif_config_regs;

typedef struct { Uint32 address; Uint16 value; } Write;
static Uint16 registers[0x400u];
static Write writes[1024];
static Uint32 reads[1024];
static Uint16 write_count;
static Uint16 read_count;
static Uint32 now_us;
static Uint32 generation;
static Uint16 tx_script[12];
static Uint16 tx_script_count;
static Uint16 tx_script_index;
static Uint16 tx_script_sn;

volatile struct TEST_EMIF_CONFIG_REGS *test_emif_config_regs(void)
{ return &emif_config_regs; }
void GPIO_SetupPinMux(Uint16 pin, Uint16 cpu, Uint16 mux)
{ (void)pin; (void)cpu; (void)mux; }
void GPIO_SetupPinOptions(Uint16 pin, Uint16 output, Uint16 options)
{ (void)pin; (void)output; (void)options; }
void GPIO_WritePin(Uint16 pin, Uint16 value) { (void)pin; (void)value; }
void test_delay_us(Uint32 value) { (void)value; }

static Uint16 index_of(Uint32 address)
{ return (Uint16)(address - C2837X_W5300_MAP_BASE); }
static void set_register(Uint32 address, Uint16 value)
{ registers[index_of(address)] = value; }

Uint16 c2837x_w5300_host_read16(Uint32 address)
{
    reads[read_count++] = address;
    if ((tx_script_index < tx_script_count) &&
        ((address == Sn_TX_FSR(tx_script_sn)) ||
         (address == Sn_TX_FSR2(tx_script_sn))))
        return tx_script[tx_script_index++];
    return registers[index_of(address)];
}

void c2837x_w5300_host_write16(Uint32 address, Uint16 value)
{
    Uint16 sn;
    writes[write_count].address = address;
    writes[write_count++].value = value;
    for (sn = 0u; sn < C2837X_W5300_MAX_SOCK_NUM; sn++)
        if (address == Sn_IR(sn))
        {
            registers[index_of(address)] &= (Uint16)~value;
            return;
        }
    set_register(address, value);
}

static Uint32 fake_time_us(void) { return now_us; }
Uint32 c2837x_block_platform_generation(void) { return generation; }

static C2837xW5300Channel make_channel(Uint16 sn)
{
    C2837xW5300Channel channel = C2837X_W5300_CHANNEL_INITIALIZER(
        sn, 8192u, 8192u, (Uint16)(5000u + sn), fake_time_us, 100u);
    channel.observed_platform_generation = generation;
    return channel;
}

static void reset_fixture(void)
{
    memset(registers, 0, sizeof(registers));
    memset(writes, 0, sizeof(writes));
    memset(reads, 0, sizeof(reads));
    write_count = 0u;
    read_count = 0u;
    now_us = 100u;
    tx_script_count = 0u;
    tx_script_index = 0u;
}

static void set_tx_space(Uint16 sn, Uint32 octets)
{
    set_register(Sn_TX_FSR(sn), (Uint16)(octets >> 16));
    set_register(Sn_TX_FSR2(sn), (Uint16)octets);
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

static void finish_close(C2837xW5300Channel *channel)
{
    Uint16 sn = channel->socket.sn;
    assert(c2837x_w5300_iodevice_ops.close(channel) == 0);
    assert(channel->close_state == C2837X_W5300_CLOSE_CLOSE_WAIT_CR);
    set_register(Sn_CR(sn), 0u);
    assert(c2837x_w5300_iodevice_ops.close(channel) == 0);
    assert(channel->close_state == C2837X_W5300_CLOSE_CLOSE_WAIT_STATE);
    set_register(Sn_SSR(sn), SOCK_CLOSED);
    assert(c2837x_w5300_iodevice_ops.close(channel) > 0);
    assert(channel->close_state == C2837X_W5300_CLOSE_IDLE);
}

static void test_direct_close(void)
{
    C2837xW5300Channel channel = make_channel(1u);

    reset_fixture();
    set_register(Sn_MR(1u), Sn_MR_TCP | Sn_MR_ALIGN);
    set_register(Sn_SSR(1u), SOCK_ESTABLISHED);
    set_tx_space(1u, 8192u);
    assert(c2837x_w5300_iodevice_ops.close(&channel) == 0);
    assert(channel.close_state == C2837X_W5300_CLOSE_CHECK_ERRATUM);
    assert(writes_of(Sn_CR(1u)) == 0u);
    assert(c2837x_w5300_iodevice_ops.close(&channel) == 0);
    assert(channel.close_state == C2837X_W5300_CLOSE_CLOSE_ISSUE);
    finish_close(&channel);
    assert(writes_of(Sn_CR(1u)) == 1u);
    assert(writes_of(Sn_MR(1u)) == 0u);
    assert(writes_of(Sn_DIPR(1u)) == 0u);
    assert(writes_of(Sn_TX_FIFOR(1u)) == 0u);
    assert(c2837x_w5300_iodevice_ops.close(&channel) > 0);
    assert(writes_of(Sn_CR(1u)) == 1u);
}

static void run_erratum(Uint16 event)
{
    C2837xW5300Channel channel = make_channel(1u);
    C2837xW5300Channel other = make_channel(6u);
    Uint16 begin;

    reset_fixture();
    other.send_state = C2837X_W5300_SEND_PENDING;
    other.pending_octets = 6u;
    other.socket.pending_command = C2837X_W5300_COMMAND_RECV;
    other.socket.command_phase = C2837X_W5300_COMMAND_PHASE_WAIT_CR_CLEAR;
    other.close_state = C2837X_W5300_CLOSE_CLOSE_WAIT_STATE;
    other.faulted = 1u;
    set_register(Sn_MR(1u), Sn_MR_TCP);
    set_register(Sn_SSR(1u), SOCK_ESTABLISHED);
    set_tx_space(1u, 8190u);

    assert(c2837x_w5300_iodevice_ops.close(&channel) == 0);
    assert(channel.send_state == C2837X_W5300_SEND_IDLE);
    assert(channel.pending_octets == 0u);
    assert(c2837x_w5300_iodevice_ops.close(&channel) == 0);
    assert(channel.close_state == C2837X_W5300_CLOSE_UDP_OPEN_ISSUE);
    begin = write_count;
    assert(c2837x_w5300_iodevice_ops.close(&channel) == 0);
    assert(writes[begin + 0u].address == Sn_IR(1u));
    assert(writes[begin + 1u].address == IR);
    assert(writes[begin + 2u].address == Sn_MR(1u));
    assert(writes[begin + 2u].value == Sn_MR_UDP);
    assert(writes[begin + 3u].address == Sn_PORTR(1u));
    assert(writes[begin + 3u].value == 5000u);
    assert(writes[begin + 4u].address == Sn_CR(1u));
    assert(writes[begin + 4u].value == Sn_CR_OPEN);
    set_register(Sn_CR(1u), 0u);
    assert(c2837x_w5300_iodevice_ops.close(&channel) == 0);
    set_register(Sn_SSR(1u), SOCK_UDP);
    assert(c2837x_w5300_iodevice_ops.close(&channel) == 0);
    set_tx_space(1u, 1u);
    assert(c2837x_w5300_iodevice_ops.close(&channel) == 0);

    begin = write_count;
    assert(c2837x_w5300_iodevice_ops.close(&channel) == 0);
    assert(writes[begin + 0u].address == Sn_DIPR(1u));
    assert(writes[begin + 0u].value == 0u);
    assert(writes[begin + 1u].address == Sn_DIPR2(1u));
    assert(writes[begin + 1u].value == 1u);
    assert(writes[begin + 2u].address == Sn_DPORTR(1u));
    assert(writes[begin + 2u].value == 5000u);
    assert(writes[begin + 3u].address == Sn_IR(1u));
    assert(writes[begin + 3u].value == (Sn_IR_SENDOK | Sn_IR_TIMEOUT));
    assert(writes[begin + 4u].address == Sn_TX_FIFOR(1u));
    assert(writes[begin + 4u].value == 0u);
    assert(writes[begin + 5u].address == Sn_TX_WRSR(1u));
    assert(writes[begin + 6u].address == Sn_TX_WRSR2(1u));
    assert(writes[begin + 6u].value == 1u);
    assert(writes[begin + 7u].address == Sn_CR(1u));
    assert(writes[begin + 7u].value == Sn_CR_SEND);
    set_register(Sn_CR(1u), 0u);
    assert(c2837x_w5300_iodevice_ops.close(&channel) == 0);
    set_register(Sn_IR(1u), event);
    assert(c2837x_w5300_iodevice_ops.close(&channel) == 0);
    assert(channel.close_state == C2837X_W5300_CLOSE_CLOSE_ISSUE);
    assert(writes[write_count - 1u].address == Sn_IR(1u));
    assert(writes[write_count - 1u].value == event);
    finish_close(&channel);

    assert(other.send_state == C2837X_W5300_SEND_PENDING);
    assert(other.pending_octets == 6u);
    assert(other.socket.pending_command == C2837X_W5300_COMMAND_RECV);
    assert(other.close_state == C2837X_W5300_CLOSE_CLOSE_WAIT_STATE);
    assert(other.faulted == 1u);
    assert(writes_of(Sn_CR(6u)) == 0u && writes_of(Sn_IR(6u)) == 0u);
    assert(writes_of(SIPR0) == 0u && writes_of(SIPR2) == 0u);
    assert(writes_of(SUBR0) == 0u && writes_of(SUBR2) == 0u);
    assert(writes_of(GAR0) == 0u && writes_of(GAR2) == 0u);
    assert(writes_of(SHAR0) == 0u && writes_of(SHAR2) == 0u &&
           writes_of(SHAR4) == 0u);
}

static void test_existing_command_takeover(void)
{
    C2837xW5300Channel channel = make_channel(1u);
    Uint16 before;

    reset_fixture();
    channel.socket.pending_command = C2837X_W5300_COMMAND_SEND;
    channel.socket.command_phase = C2837X_W5300_COMMAND_PHASE_WAIT_CR_CLEAR;
    channel.send_state = C2837X_W5300_SEND_PENDING;
    channel.pending_octets = 8u;
    set_register(Sn_CR(1u), Sn_CR_SEND);
    assert(c2837x_w5300_iodevice_ops.close(&channel) == 0);
    assert(channel.send_state == C2837X_W5300_SEND_IDLE &&
           channel.pending_octets == 0u);
    before = reads_of(Sn_CR(1u));
    assert(c2837x_w5300_iodevice_ops.close(&channel) == 0);
    assert(reads_of(Sn_CR(1u)) == (Uint16)(before + 1u));
    set_register(Sn_CR(1u), 0u);
    assert(c2837x_w5300_iodevice_ops.close(&channel) == 0);
    assert(channel.close_state == C2837X_W5300_CLOSE_CHECK_ERRATUM);

    reset_fixture();
    channel = make_channel(1u);
    channel.socket.pending_command = C2837X_W5300_COMMAND_LISTEN;
    channel.socket.command_phase = C2837X_W5300_COMMAND_PHASE_WAIT_TARGET_STATE;
    assert(c2837x_w5300_iodevice_ops.close(&channel) == 0);
    before = read_count;
    assert(c2837x_w5300_iodevice_ops.close(&channel) == 0);
    assert(read_count == before);
    assert(channel.socket.pending_command == C2837X_W5300_COMMAND_NONE);
}

static void assert_stage_times_out(C2837xW5300CloseState state,
                                   C2837xW5300PendingCommand command,
                                   C2837xW5300CommandPhase phase)
{
    C2837xW5300Channel channel = make_channel(1u);
    Uint16 cr_reads;

    reset_fixture();
    channel.close_state = state;
    channel.close_start_us = 100u;
    channel.socket.pending_command = command;
    channel.socket.command_phase = phase;
    set_register(Sn_CR(1u), (command == C2837X_W5300_COMMAND_NONE) ? 0u : 1u);
    set_register(Sn_SSR(1u), SOCK_ARP);
    set_tx_space(1u, 0u);
    now_us = 199u;
    cr_reads = reads_of(Sn_CR(1u));
    assert(c2837x_w5300_iodevice_ops.close(&channel) == 0);
    if (phase == C2837X_W5300_COMMAND_PHASE_WAIT_CR_CLEAR)
        assert(reads_of(Sn_CR(1u)) == (Uint16)(cr_reads + 1u));
    now_us = 200u;
    assert(c2837x_w5300_iodevice_ops.close(&channel) < 0);
    assert(channel.faulted == 1u);
    assert(channel.close_state == C2837X_W5300_CLOSE_FAULTED);
}

static void test_all_waits_have_deadlines_and_wrap(void)
{
    C2837xW5300Channel channel = make_channel(1u);
    static const Uint16 unstable[12] =
        {0u, 1u, 0u, 2u, 0u, 3u, 0u, 4u, 0u, 5u, 0u, 6u};

    assert_stage_times_out(C2837X_W5300_CLOSE_WAIT_EXISTING_CR,
        C2837X_W5300_COMMAND_SEND,
        C2837X_W5300_COMMAND_PHASE_WAIT_CR_CLEAR);
    assert_stage_times_out(C2837X_W5300_CLOSE_UDP_OPEN_WAIT_CR,
        C2837X_W5300_COMMAND_UDP_OPEN,
        C2837X_W5300_COMMAND_PHASE_WAIT_CR_CLEAR);
    assert_stage_times_out(C2837X_W5300_CLOSE_UDP_OPEN_WAIT_STATE,
        C2837X_W5300_COMMAND_UDP_OPEN,
        C2837X_W5300_COMMAND_PHASE_WAIT_TARGET_STATE);
    assert_stage_times_out(C2837X_W5300_CLOSE_DUMMY_WAIT_TX_SPACE,
        C2837X_W5300_COMMAND_NONE, C2837X_W5300_COMMAND_PHASE_IDLE);
    assert_stage_times_out(C2837X_W5300_CLOSE_DUMMY_SEND_WAIT_CR,
        C2837X_W5300_COMMAND_DUMMY_SEND,
        C2837X_W5300_COMMAND_PHASE_WAIT_CR_CLEAR);
    assert_stage_times_out(C2837X_W5300_CLOSE_DUMMY_SEND_WAIT_RESULT,
        C2837X_W5300_COMMAND_DUMMY_SEND,
        C2837X_W5300_COMMAND_PHASE_WAIT_TARGET_STATE);
    assert_stage_times_out(C2837X_W5300_CLOSE_CLOSE_WAIT_CR,
        C2837X_W5300_COMMAND_CLOSE,
        C2837X_W5300_COMMAND_PHASE_WAIT_CR_CLEAR);
    assert_stage_times_out(C2837X_W5300_CLOSE_CLOSE_WAIT_STATE,
        C2837X_W5300_COMMAND_CLOSE,
        C2837X_W5300_COMMAND_PHASE_WAIT_TARGET_STATE);

    reset_fixture();
    channel = make_channel(1u);
    channel.close_state = C2837X_W5300_CLOSE_CHECK_ERRATUM;
    channel.close_start_us = 100u;
    set_register(Sn_MR(1u), Sn_MR_TCP);
    memcpy(tx_script, unstable, sizeof(unstable));
    tx_script_sn = 1u;
    tx_script_count = 12u;
    now_us = 199u;
    assert(c2837x_w5300_iodevice_ops.close(&channel) == 0);
    assert(channel.close_state == C2837X_W5300_CLOSE_CHECK_ERRATUM);
    assert(tx_script_index == 12u);
    now_us = 200u;
    assert(c2837x_w5300_iodevice_ops.close(&channel) < 0);

    reset_fixture();
    channel = make_channel(1u);
    channel.close_state = C2837X_W5300_CLOSE_DUMMY_SEND_WAIT_RESULT;
    channel.close_start_us = 0xFFFFFFF0u;
    channel.close_timeout_us = 32u;
    channel.socket.pending_command = C2837X_W5300_COMMAND_DUMMY_SEND;
    channel.socket.command_phase = C2837X_W5300_COMMAND_PHASE_WAIT_TARGET_STATE;
    set_register(Sn_SSR(1u), SOCK_UDP);
    now_us = 0x0000000Fu;
    assert(c2837x_w5300_iodevice_ops.close(&channel) == 0);
    now_us = 0x00000010u;
    assert(c2837x_w5300_iodevice_ops.close(&channel) < 0);
}

static void test_fault_gate_and_generation(void)
{
    C2837xW5300Channel first = make_channel(1u);
    C2837xW5300Channel second = make_channel(6u);
    Uint16 words[1] = {0u};
    Uint16 before_reads;
    Uint16 before_writes;

    reset_fixture();
    first.faulted = 1u;
    first.close_state = C2837X_W5300_CLOSE_FAULTED;
    second.faulted = 1u;
    second.close_state = C2837X_W5300_CLOSE_FAULTED;
    before_reads = read_count;
    before_writes = write_count;
    assert(c2837x_w5300_iodevice_ops.open(&first) < 0);
    assert(c2837x_w5300_iodevice_ops.listen(&first) < 0);
    assert(c2837x_w5300_iodevice_ops.send(&first, words, 2u) < 0);
    assert(c2837x_w5300_iodevice_ops.receive(&first, words, 2u) < 0);
    assert(c2837x_w5300_iodevice_ops.get_connection_state(&first) ==
           C2837X_IODEVICE_CONNECTION_ERROR);
    assert(c2837x_w5300_iodevice_ops.close(&first) < 0);
    assert(read_count == before_reads && write_count == before_writes);

    /* A failed PlatformInit leaves generation unchanged. */
    assert(c2837x_w5300_iodevice_ops.open(&first) < 0);
    assert(first.faulted == 1u);
    generation++;
    assert(c2837x_w5300_iodevice_ops.open(&first) == 0);
    assert(first.faulted == 0u);
    assert(first.observed_platform_generation == generation);
    assert(second.faulted == 1u);
    assert(second.observed_platform_generation != generation);
    assert(c2837x_w5300_iodevice_ops.open(&second) == 0);
    assert(second.faulted == 0u);
}

static void test_invalid_configuration_faults_without_access(void)
{
    C2837xW5300Channel channel = make_channel(1u);

    reset_fixture();
    channel.time_us = 0;
    assert(c2837x_w5300_iodevice_ops.close(&channel) < 0);
    assert(read_count == 0u && write_count == 0u);
    channel = make_channel(1u);
    channel.close_timeout_us = 0x80000000u;
    assert(c2837x_w5300_iodevice_ops.close(&channel) < 0);
    assert(read_count == 0u && write_count == 0u);

    reset_fixture();
    channel = make_channel(1u);
    channel.close_state = C2837X_W5300_CLOSE_UDP_OPEN_WAIT_STATE;
    channel.close_start_us = 100u;
    channel.socket.pending_command = C2837X_W5300_COMMAND_UDP_OPEN;
    channel.socket.command_phase =
        C2837X_W5300_COMMAND_PHASE_WAIT_TARGET_STATE;
    set_register(Sn_SSR(1u), 0xFFFFu);
    now_us = 101u;
    assert(c2837x_w5300_iodevice_ops.close(&channel) < 0);
    assert(channel.faulted == 1u);

    reset_fixture();
    channel = make_channel(1u);
    channel.socket.command_phase =
        C2837X_W5300_COMMAND_PHASE_WAIT_CR_CLEAR;
    assert(c2837x_w5300_iodevice_ops.close(&channel) == 0);
    assert(c2837x_w5300_iodevice_ops.close(&channel) < 0);
    assert(writes_of(Sn_CR(1u)) == 0u);
}

int main(void)
{
    generation = 0u;
    test_direct_close();
    run_erratum(Sn_IR_SENDOK);
    run_erratum(Sn_IR_TIMEOUT);
    run_erratum(Sn_IR_SENDOK | Sn_IR_TIMEOUT);
    test_existing_command_takeover();
    test_all_waits_have_deadlines_and_wrap();
    test_fault_gate_and_generation();
    test_invalid_configuration_faults_without_access();
    return 0;
}
