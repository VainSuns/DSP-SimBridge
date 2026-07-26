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
static Uint16 register_count;
static Uint16 write_count;
static Uint16 read_count;
static Uint32 size_high;
static Uint32 size_low;
static Uint16 size_values[12];
static Uint16 size_count;
static Uint16 size_index;

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
    read_count++;
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
    register_count = 0u;
    write_count = 0u;
    read_count = 0u;
    size_high = 0u;
    size_low = 0u;
    size_count = 0u;
    size_index = 0u;
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

static Uint16 reads_of(Uint32 address)
{
    Uint16 i;
    Uint16 count = 0u;
    for (i = 0u; i < size_index; i++)
        if (((i & 1u) ? size_low : size_high) == address)
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

static void test_open_listen_and_isolation(void)
{
    C2837xW5300Socket first = {1u, 8192u, 8192u, C2837X_W5300_COMMAND_NONE};
    C2837xW5300Socket second = {6u, 8192u, 8192u, C2837X_W5300_COMMAND_NONE};
    Uint16 before;

    reset_fixture();
    assert(c2837x_w5300_socket_open(&first, Sn_MR_TCP, 5001u,
                                     Sn_MR_ALIGN) == 0);
    assert(first.pending_command == C2837X_W5300_COMMAND_OPEN);
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
    assert(c2837x_w5300_socket_open(&first, Sn_MR_TCP, 5001u, 0u) == 0);
    assert(write_count == before && read_count == 1u);
    set_register(Sn_CR(1u), 0u);
    assert(c2837x_w5300_socket_open(&first, Sn_MR_TCP, 5001u, 0u) == 0);
    assert(first.pending_command == C2837X_W5300_COMMAND_NONE);
    assert(write_count == before && read_count == 2u);

    assert(c2837x_w5300_socket_open(&second, Sn_MR_TCP, 5006u, 0u) == 0);
    assert(first.pending_command == C2837X_W5300_COMMAND_NONE);
    assert(second.pending_command == C2837X_W5300_COMMAND_OPEN);

    reset_fixture();
    first.pending_command = C2837X_W5300_COMMAND_NONE;
    set_register(Sn_SSR(1u), SOCK_INIT);
    assert(c2837x_w5300_socket_listen(&first) == 0);
    assert(first.pending_command == C2837X_W5300_COMMAND_LISTEN);
    assert(read_count == 1u && write_count == 3u);
    assert(writes[0].address == Sn_IR(1u));
    assert(writes[1].address == IR);
    assert(writes[2].address == Sn_CR(1u));
    before = write_count;
    assert(c2837x_w5300_socket_listen(&first) == 0);
    assert(write_count == before && read_count == 2u);
}

static void test_send_and_receive(void)
{
    static const Uint16 stable_four[] = {0u, 4u, 0u, 4u};
    static const Uint16 unstable[] = {
        0u, 1u, 0u, 2u, 0u, 3u, 0u, 4u, 0u, 5u, 0u, 6u};
    C2837xW5300Socket sk = {3u, 8192u, 8192u, C2837X_W5300_COMMAND_NONE};
    Uint16 data[2] = {0x0102u, 0x0304u};
    Uint16 before;

    reset_fixture();
    set_register(Sn_SSR(3u), SOCK_ESTABLISHED);
    script_size(Sn_TX_FSR(3u), Sn_TX_FSR2(3u), stable_four, 4u);
    assert(c2837x_w5300_socket_send(&sk, data, 4u) == 4);
    assert(sk.pending_command == C2837X_W5300_COMMAND_SEND);
    assert(write_count == 5u);
    assert(writes[0].address == Sn_TX_FIFOR(3u));
    assert(writes[1].address == Sn_TX_FIFOR(3u));
    assert(writes[2].address == Sn_TX_WRSR(3u));
    assert(writes[3].address == Sn_TX_WRSR2(3u));
    assert(writes[4].address == Sn_CR(3u));
    before = write_count;
    assert(c2837x_w5300_socket_send(&sk, data, 4u) == 0);
    assert(write_count == before);
    set_register(Sn_CR(3u), 0u);
    assert(c2837x_w5300_socket_send(&sk, data, 4u) == 0);
    assert(sk.pending_command == C2837X_W5300_COMMAND_NONE);
    script_size(Sn_TX_FSR(3u), Sn_TX_FSR2(3u), stable_four, 4u);
    assert(c2837x_w5300_socket_send(&sk, data, 4u) == 4);

    reset_fixture();
    sk.pending_command = C2837X_W5300_COMMAND_NONE;
    set_register(Sn_SSR(3u), SOCK_ESTABLISHED);
    script_size(Sn_TX_FSR(3u), Sn_TX_FSR2(3u), unstable, 12u);
    assert(c2837x_w5300_socket_send(&sk, data, 4u) < 0);
    assert(write_count == 0u && size_index == 12u);

    reset_fixture();
    sk.pending_command = C2837X_W5300_COMMAND_NONE;
    set_register(Sn_SSR(3u), SOCK_ESTABLISHED);
    script_size(Sn_RX_RSR(3u), Sn_RX_RSR2(3u), unstable, 12u);
    assert(c2837x_w5300_socket_recv(&sk, data, 4u) < 0);
    assert(write_count == 0u && reads_of(Sn_RX_RSR(3u)) == 6u);

    reset_fixture();
    sk.pending_command = C2837X_W5300_COMMAND_NONE;
    set_register(Sn_SSR(3u), SOCK_ESTABLISHED);
    set_register(Sn_RX_FIFOR(3u), 0x1122u);
    script_size(Sn_RX_RSR(3u), Sn_RX_RSR2(3u), stable_four, 4u);
    assert(c2837x_w5300_socket_recv(&sk, data, 4u) == 4);
    assert(sk.pending_command == C2837X_W5300_COMMAND_RECV);
    assert(write_count == 1u && writes[0].address == Sn_CR(3u));
    before = read_count;
    assert(c2837x_w5300_socket_recv(&sk, data, 4u) == 0);
    assert(read_count == (Uint16)(before + 1u) && write_count == 1u);
    set_register(Sn_CR(3u), 0u);
    assert(c2837x_w5300_socket_recv(&sk, data, 4u) == 0);
    assert(sk.pending_command == C2837X_W5300_COMMAND_NONE);
    script_size(Sn_RX_RSR(3u), Sn_RX_RSR2(3u), stable_four, 4u);
    assert(c2837x_w5300_socket_recv(&sk, data, 4u) == 4);
}

static void test_close_is_bounded_and_isolated(void)
{
    C2837xW5300Socket first = {1u, 8192u, 8192u, C2837X_W5300_COMMAND_NONE};
    C2837xW5300Socket second = {6u, 8192u, 8192u, C2837X_W5300_COMMAND_NONE};
    Uint16 before;

    reset_fixture();
    set_register(Sn_SSR(1u), SOCK_ESTABLISHED);
    set_register(Sn_SSR(6u), SOCK_CLOSE_WAIT);
    assert(c2837x_w5300_socket_close(&first) == 0);
    assert(first.pending_command == C2837X_W5300_COMMAND_CLOSE);
    assert(second.pending_command == C2837X_W5300_COMMAND_NONE);
    assert(read_count == 1u && write_count == 3u);
    before = write_count;
    assert(c2837x_w5300_socket_close(&first) == 0);
    assert(write_count == before && read_count == 2u);
    set_register(Sn_CR(1u), 0u);
    assert(c2837x_w5300_socket_close(&first) == 0);
    assert(first.pending_command == C2837X_W5300_COMMAND_NONE);

    assert(c2837x_w5300_socket_close(&second) == 0);
    assert(second.pending_command == C2837X_W5300_COMMAND_DISCONNECT);
    assert(first.pending_command == C2837X_W5300_COMMAND_NONE);
    assert(write_count == (Uint16)(before + 1u));
    assert(writes[before].address == Sn_CR(6u));
    assert(writes[before].value == Sn_CR_DISCON);

    reset_fixture();
    first.pending_command = C2837X_W5300_COMMAND_NONE;
    set_register(Sn_SSR(1u), SOCK_CLOSED);
    assert(c2837x_w5300_socket_close(&first) > 0);
    assert(read_count == 1u && write_count == 0u);
}

int main(void)
{
    test_command_issue_and_poll();
    test_stable_size_reads();
    test_open_listen_and_isolation();
    test_send_and_receive();
    test_close_is_bounded_and_isolated();
    return 0;
}
