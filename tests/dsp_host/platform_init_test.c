#include <assert.h>
#include <string.h>
#include "c2837x_block.h"
#include "c2837x_w5300_hal.h"

enum Failure {
    FAILURE_NONE = 0,
    FAILURE_TIMER,
    FAILURE_W5300,
    FAILURE_ID,
    FAILURE_SOCKET,
    FAILURE_MEMORY,
    FAILURE_NETWORK
};

static Uint16 registers[0x400u];
static enum Failure failure;
static Uint16 timer_calls;
static Uint16 w5300_calls;
static Uint16 socket_status_reads;
static Uint16 socket_command_writes;

Uint16 c2837x_w5300_fifo_swap;

static Uint16 register_index(Uint32 address)
{
    return (Uint16)(address - C2837X_W5300_MAP_BASE);
}

static void reset_fixture(void)
{
    Uint16 sn;

    memset(registers, 0, sizeof(registers));
    failure = FAILURE_NONE;
    timer_calls = 0u;
    w5300_calls = 0u;
    socket_status_reads = 0u;
    socket_command_writes = 0u;
    registers[register_index(IDR)] = 0x5300u;
    for (sn = 0u; sn < C2837X_W5300_MAX_SOCK_NUM; sn++)
        registers[register_index(Sn_SSR(sn))] = SOCK_CLOSED;
}

int16 c2837x_block_timer2_init(void)
{
    timer_calls++;
    return (failure == FAILURE_TIMER) ? -1 : 0;
}

Uint32 c2837x_block_time_us(void)
{
    return 0u;
}

int16 c2837x_w5300_init(void)
{
    w5300_calls++;
    return (failure == FAILURE_W5300) ? -1 : 0;
}

void c2837x_w5300_reset(void) {}

void c2837x_w5300_write16(Uint32 address, Uint16 data)
{
    Uint16 sn;

    registers[register_index(address)] = data;
    for (sn = 0u; sn < C2837X_W5300_MAX_SOCK_NUM; sn++)
    {
        if (address == Sn_CR(sn))
            socket_command_writes++;
    }
}

Uint16 c2837x_w5300_read16(Uint32 address)
{
    Uint16 sn;

    if ((failure == FAILURE_ID) && (address == IDR))
        return 0u;
    if ((failure == FAILURE_MEMORY) && (address == TMS23R))
        return 0u;
    if ((failure == FAILURE_NETWORK) && (address == SIPR2))
        return 0u;

    for (sn = 0u; sn < C2837X_W5300_MAX_SOCK_NUM; sn++)
    {
        if (address == Sn_SSR(sn))
        {
            socket_status_reads++;
            if ((failure == FAILURE_SOCKET) && (sn == 3u))
                return SOCK_INIT;
        }
    }
    return registers[register_index(address)];
}

static void test_success(void)
{
    assert(C2837xBlock_PlatformInit() == C2837X_BLOCK_PLATFORM_OK);
    assert(timer_calls == 1u);
    assert(w5300_calls == 1u);
    assert(socket_status_reads == 8u);
    assert(socket_command_writes == 0u);
    assert(registers[register_index(TMS01R)] == 0x0808u);
    assert(registers[register_index(TMS23R)] == 0x0808u);
    assert(registers[register_index(TMS45R)] == 0x0808u);
    assert(registers[register_index(TMS67R)] == 0x0808u);
    assert(registers[register_index(RMS01R)] == 0x0808u);
    assert(registers[register_index(RMS23R)] == 0x0808u);
    assert(registers[register_index(RMS45R)] == 0x0808u);
    assert(registers[register_index(RMS67R)] == 0x0808u);
    assert(registers[register_index(MTYPER)] == 0x00FFu);
    assert(registers[register_index(SHAR0)] == 0x0008u);
    assert(registers[register_index(SHAR2)] == 0xDC01u);
    assert(registers[register_index(SHAR4)] == 0x0203u);
    assert(registers[register_index(GAR0)] == 0xC0A8u);
    assert(registers[register_index(GAR2)] == 0x0101u);
    assert(registers[register_index(SUBR0)] == 0xFFFFu);
    assert(registers[register_index(SUBR2)] == 0xFF00u);
    assert(registers[register_index(SIPR0)] == 0xC0A8u);
    assert(registers[register_index(SIPR2)] == 0x0164u);
}

static void test_failures_stop(void)
{
    failure = FAILURE_TIMER;
    assert(C2837xBlock_PlatformInit() == C2837X_BLOCK_PLATFORM_ERROR_TIMER_INIT);
    assert(w5300_calls == 0u);

    reset_fixture();
    failure = FAILURE_W5300;
    assert(C2837xBlock_PlatformInit() == C2837X_BLOCK_PLATFORM_ERROR_W5300_INIT);
    assert(registers[register_index(TMS01R)] == 0u);
    assert(registers[register_index(SHAR0)] == 0u);

    reset_fixture();
    failure = FAILURE_ID;
    assert(C2837xBlock_PlatformInit() == C2837X_BLOCK_PLATFORM_ERROR_W5300_INIT);
    assert(registers[register_index(TMS01R)] == 0u);

    reset_fixture();
    failure = FAILURE_SOCKET;
    assert(C2837xBlock_PlatformInit() == C2837X_BLOCK_PLATFORM_ERROR_W5300_INIT);
    assert(registers[register_index(TMS01R)] == 0u);

    reset_fixture();
    failure = FAILURE_MEMORY;
    assert(C2837xBlock_PlatformInit() == C2837X_BLOCK_PLATFORM_ERROR_W5300_MEMORY);
    assert(registers[register_index(SHAR0)] == 0u);

    reset_fixture();
    failure = FAILURE_NETWORK;
    assert(C2837xBlock_PlatformInit() == C2837X_BLOCK_PLATFORM_ERROR_NETWORK_CONFIG);
    assert(socket_command_writes == 0u);
}

int main(void)
{
    reset_fixture();
    test_success();
    reset_fixture();
    test_failures_stop();
    return 0;
}
