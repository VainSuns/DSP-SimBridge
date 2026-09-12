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
    c2837x_w5300_fifo_swap = 0u;
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

static void assert_no_datagram_writes(Uint16 sn)
{
    assert(writes_of(Sn_DIPR(sn)) == 0u);
    assert(writes_of(Sn_DIPR2(sn)) == 0u);
    assert(writes_of(Sn_DPORTR(sn)) == 0u);
    assert(writes_of(Sn_TX_FIFOR(sn)) == 0u);
    assert(writes_of(Sn_TX_WRSR(sn)) == 0u);
    assert(writes_of(Sn_TX_WRSR2(sn)) == 0u);
    assert(writes_of(Sn_CR(sn)) == 0u);
}

static C2837xW5300Socket make_socket(void)
{
    C2837xW5300Socket socket =
        C2837X_W5300_SOCKET_INITIALIZER(2u, 8192u, 8192u);
    return socket;
}

static void test_insufficient_free_space_is_no_write(void)
{
    C2837xW5300Socket socket = make_socket();
    static const Uint16 data[] = {0x2211u, 0x4433u, 0x6655u};

    reset_fixture();
    set_register(Sn_SSR(2u), SOCK_UDP);
    set_tx_space(2u, 4u);
    assert(c2837x_w5300_socket_udp_send(
               &socket, 0xC0A8010Au, 0x1F90u, data, 6u) == 0);
    assert_no_datagram_writes(2u);
}

static void test_full_datagram_submission(void)
{
    C2837xW5300Socket socket = make_socket();
    static const Uint16 data[] = {0x2211u, 0x4433u, 0x6655u};
    Uint16 ir;

    reset_fixture();
    set_register(Sn_SSR(2u), SOCK_UDP);
    set_register(Sn_IR(2u), Sn_IR_SENDOK | Sn_IR_TIMEOUT | Sn_IR_RECV);
    set_tx_space(2u, 8u);
    assert(c2837x_w5300_socket_udp_send(
               &socket, 0xC0A8010Au, 0x1F90u, data, 6u) == 6);
    assert(writes[0].address == Sn_DIPR(2u) &&
           writes[0].value == 0xC0A8u);
    assert(writes[1].address == Sn_DIPR2(2u) &&
           writes[1].value == 0x010Au);
    assert(writes[2].address == Sn_DPORTR(2u) &&
           writes[2].value == 0x1F90u);
    assert(writes[3].address == Sn_IR(2u) &&
           writes[3].value == (Sn_IR_SENDOK | Sn_IR_TIMEOUT));
    assert(writes[4].address == Sn_TX_FIFOR(2u) &&
           writes[4].value == 0x1122u);
    assert(writes[5].address == Sn_TX_FIFOR(2u) &&
           writes[5].value == 0x3344u);
    assert(writes[6].address == Sn_TX_FIFOR(2u) &&
           writes[6].value == 0x5566u);
    assert(writes[7].address == Sn_TX_WRSR(2u) &&
           writes[7].value == 0u);
    assert(writes[8].address == Sn_TX_WRSR2(2u) &&
           writes[8].value == 6u);
    assert(writes[9].address == Sn_CR(2u) &&
           writes[9].value == Sn_CR_SEND);
    assert(write_count == 10u);
    assert(writes_of(Sn_DIPR(2u)) == 1u);
    assert(writes_of(Sn_DIPR2(2u)) == 1u);
    assert(writes_of(Sn_DPORTR(2u)) == 1u);
    assert(writes_of(Sn_TX_FIFOR(2u)) == 3u);
    assert(writes_of(Sn_TX_WRSR(2u)) == 1u);
    assert(writes_of(Sn_TX_WRSR2(2u)) == 1u);
    assert(writes_of(Sn_CR(2u)) == 1u);
    ir = c2837x_w5300_get_sn_ir(2u);
    assert(ir == Sn_IR_RECV);
    assert(socket.pending_command == C2837X_W5300_COMMAND_SEND);
    assert(socket.command_phase == C2837X_W5300_COMMAND_PHASE_WAIT_CR_CLEAR);
}

static void test_pending_send_does_not_recopy_or_reissue(void)
{
    C2837xW5300Socket socket = make_socket();
    static const Uint16 first_data[] = {0x2211u, 0x4433u};
    static const Uint16 replacement_data[] = {0xA5A5u, 0x5A5Au};
    Uint16 writes_after_submit;

    reset_fixture();
    set_register(Sn_SSR(2u), SOCK_UDP);
    set_tx_space(2u, 4u);
    assert(c2837x_w5300_socket_udp_send(
               &socket, 0x01020304u, 1234u, first_data, 4u) == 4);
    writes_after_submit = write_count;
    set_register(Sn_CR(2u), Sn_CR_SEND);
    assert(c2837x_w5300_socket_udp_send(
               &socket, 0x0A000001u, 4321u, replacement_data, 4u) == 0);
    assert(write_count == writes_after_submit);
    assert(writes_of(Sn_TX_FIFOR(2u)) == 2u);
    assert(writes_of(Sn_TX_WRSR(2u)) == 1u);
    assert(writes_of(Sn_TX_WRSR2(2u)) == 1u);
    assert(writes_of(Sn_CR(2u)) == 1u);

    set_register(Sn_CR(2u), 0u);
    assert(c2837x_w5300_socket_udp_send(
               &socket, 0x0A000001u, 4321u, replacement_data, 4u) == 0);
    assert(write_count == writes_after_submit);
    assert(socket.pending_command == C2837X_W5300_COMMAND_NONE);
    assert(socket.command_phase == C2837X_W5300_COMMAND_PHASE_IDLE);
    assert(writes_of(Sn_CR(2u)) == 1u);
}

static void test_completion_bits_remain_visible(void)
{
    C2837xW5300Socket socket = make_socket();

    reset_fixture();
    set_register(Sn_IR(2u), Sn_IR_SENDOK);
    assert(c2837x_w5300_get_sn_ir(socket.sn) == Sn_IR_SENDOK);
    set_register(Sn_IR(2u), Sn_IR_TIMEOUT);
    assert(c2837x_w5300_get_sn_ir(socket.sn) == Sn_IR_TIMEOUT);
}

static void test_odd_length_is_rejected_without_write(void)
{
    C2837xW5300Socket socket = make_socket();
    static const Uint16 data[] = {0x2211u, 0x4433u, 0x0055u};

    reset_fixture();
    set_register(Sn_SSR(2u), SOCK_UDP);
    set_tx_space(2u, 8u);
    assert(c2837x_w5300_socket_udp_send(
               &socket, 0xC0A8010Au, 0x1F90u, data, 5u) < 0);
    assert_no_datagram_writes(2u);
}

static void test_datagram_larger_than_socket_memory_is_no_write(void)
{
    C2837xW5300Socket socket = make_socket();
    static const Uint16 data[] = {0x2211u, 0x4433u, 0x6655u};

    reset_fixture();
    socket.tx_mem_size = 4u;
    set_register(Sn_SSR(2u), SOCK_UDP);
    set_tx_space(2u, 8u);
    assert(c2837x_w5300_socket_udp_send(
               &socket, 0xC0A8010Au, 0x1F90u, data, 6u) == 0);
    assert_no_datagram_writes(2u);
}

static void test_tcp_partial_send_remains_separate(void)
{
    C2837xW5300Socket socket = make_socket();
    static const Uint16 data[] = {0x2211u, 0x4433u, 0x6655u};

    reset_fixture();
    set_register(Sn_SSR(2u), SOCK_ESTABLISHED);
    set_tx_space(2u, 4u);
    assert(c2837x_w5300_socket_send(&socket, data, 6u) == 4);
    assert(writes_of(Sn_TX_FIFOR(2u)) == 2u);
    assert(writes_of(Sn_CR(2u)) == 1u);
}

int main(void)
{
    test_insufficient_free_space_is_no_write();
    test_full_datagram_submission();
    test_pending_send_does_not_recopy_or_reissue();
    test_completion_bits_remain_visible();
    test_odd_length_is_rejected_without_write();
    test_datagram_larger_than_socket_memory_is_no_write();
    test_tcp_partial_send_remains_separate();
    return 0;
}
