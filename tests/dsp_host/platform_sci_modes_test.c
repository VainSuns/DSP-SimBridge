#include <assert.h>
#include <string.h>
#include "c2837x_block.h"
#include "c2837x_block_platform.h"
#include "c2837x_w5300_hal.h"

#define PLATFORM_TEST_W5300_ONLY  1
#define PLATFORM_TEST_SCI_ONLY    2
#define PLATFORM_TEST_MIXED       3

#ifndef C2837X_BLOCK_PLATFORM_TEST_MODE
#define C2837X_BLOCK_PLATFORM_TEST_MODE PLATFORM_TEST_W5300_ONLY
#endif

#if (C2837X_BLOCK_PLATFORM_TEST_MODE == PLATFORM_TEST_SCI_ONLY) || \
    (C2837X_BLOCK_PLATFORM_TEST_MODE == PLATFORM_TEST_MIXED)
#define PLATFORM_TEST_HAS_SCI  1
#else
#define PLATFORM_TEST_HAS_SCI  0
#endif

static Uint16 registers[0x400u];
static Uint16 w5300_init_calls;
static Uint16 w5300_memory_writes;
static Uint16 w5300_network_writes;
static Uint16 w5300_failure;

Uint16 c2837x_w5300_fifo_swap;
const C2837xW5300ProjectConfig c2837x_w5300_project_config =
{
    {0x00u, 0x08u, 0xDCu, 0x01u, 0x02u, 0x03u},
    (Uint32)0xC0A80164UL,
    (Uint32)0xC0A80101UL,
    (Uint32)0xFFFFFF00UL
};

static Uint16 register_index(Uint32 address)
{
    return (Uint16)(address - C2837X_W5300_MAP_BASE);
}

int16 c2837x_w5300_init(void)
{
    w5300_init_calls++;
    return (w5300_failure != 0u) ? -1 : 0;
}

void c2837x_w5300_reset(void) {}

void c2837x_w5300_write16(Uint32 address, Uint16 data)
{
    registers[register_index(address)] = data;
    if ((address == TMS01R) || (address == TMS23R) ||
        (address == TMS45R) || (address == TMS67R) ||
        (address == RMS01R) || (address == RMS23R) ||
        (address == RMS45R) || (address == RMS67R) ||
        (address == MTYPER))
    {
        w5300_memory_writes++;
    }
    if ((address == SHAR0) || (address == SHAR2) || (address == SHAR4) ||
        (address == GAR0) || (address == GAR2) ||
        (address == SUBR0) || (address == SUBR2) ||
        (address == SIPR0) || (address == SIPR2))
    {
        w5300_network_writes++;
    }
}

Uint16 c2837x_w5300_read16(Uint32 address)
{
    Uint16 sn;

    if (address == IDR)
        return 0x5300u;
    for (sn = 0u; sn < C2837X_W5300_MAX_SOCK_NUM; sn++)
    {
        if (address == Sn_SSR(sn))
            return SOCK_CLOSED;
    }
    return registers[register_index(address)];
}

static Uint16 timer_calls;
static Uint16 lspclk_calls;
static Uint16 sci_init_calls;
static Uint16 timer_failure;
static Uint16 sci_failure;
static const C2837xBlock_SciDescriptorCollection *observed_sci_descriptors;

#if PLATFORM_TEST_HAS_SCI
static const C2837xBlock_SciDescriptor platform_test_sci_descriptor =
{
    C2837X_BLOCK_SCI_MODULE_A,
    1u,
    {{9u, 6u}, C2837X_BLOCK_SCI_PIN_STANDARD,
     C2837X_BLOCK_SCI_QUALIFICATION_SYNC},
    {{8u, 6u}, C2837X_BLOCK_SCI_PIN_STANDARD},
    {C2837X_BLOCK_SCI_NO_CTRL_GPIO, C2837X_BLOCK_SCI_PIN_STANDARD,
     C2837X_BLOCK_SCI_CTRL_TX_ACTIVE_LOW}
};
#endif

void c2837x_block_sci_lspclk_bringup(void)
{
    lspclk_calls++;
}

int16 c2837x_block_sci_platform_init(
    const C2837xBlock_SciDescriptorCollection *descriptors)
{
    sci_init_calls++;
    observed_sci_descriptors = descriptors;
    return (sci_failure != 0u) ? -1 : 0;
}

const C2837xBlock_PlatformConfig c2837x_block_platform_config =
{
#if C2837X_BLOCK_PLATFORM_TEST_MODE == PLATFORM_TEST_W5300_ONLY
    1u,
    { 0, 0u }
#else
    (C2837X_BLOCK_PLATFORM_TEST_MODE == PLATFORM_TEST_MIXED) ? 1u : 0u,
    { &platform_test_sci_descriptor, 1u }
#endif
};

int16 c2837x_block_timer2_init(void)
{
    timer_calls++;
    return (timer_failure != 0u) ? -1 : 0;
}

Uint32 c2837x_block_time_us(void)
{
    return 0u;
}

static void reset_fixture(void)
{
    timer_calls = 0u;
    lspclk_calls = 0u;
    sci_init_calls = 0u;
    timer_failure = 0u;
    sci_failure = 0u;
    observed_sci_descriptors = 0;
    memset(registers, 0, sizeof(registers));
    w5300_init_calls = 0u;
    w5300_memory_writes = 0u;
    w5300_network_writes = 0u;
    w5300_failure = 0u;
    registers[register_index(IDR)] = 0x5300u;
}

static void test_success(void)
{
    reset_fixture();
    assert(C2837xBlock_PlatformInit() == C2837X_BLOCK_PLATFORM_OK);
    assert(timer_calls == 1u);
    assert(w5300_init_calls ==
           ((C2837X_BLOCK_PLATFORM_TEST_MODE == PLATFORM_TEST_SCI_ONLY)
                ? 0u : 1u));
    if (C2837X_BLOCK_PLATFORM_TEST_MODE != PLATFORM_TEST_SCI_ONLY)
    {
        assert(w5300_memory_writes != 0u);
        assert(w5300_network_writes != 0u);
    }
#if PLATFORM_TEST_HAS_SCI
    assert(lspclk_calls == 1u);
    assert(sci_init_calls == 1u);
    assert(observed_sci_descriptors == &c2837x_block_platform_config.sci_descriptors);
#else
    assert(lspclk_calls == 0u);
    assert(sci_init_calls == 0u);
#endif
    assert(c2837x_block_platform_generation() == 1u);
}

static void test_timer_failure_does_not_advance_generation(void)
{
    Uint32 generation = c2837x_block_platform_generation();

    reset_fixture();
    timer_failure = 1u;
    assert(C2837xBlock_PlatformInit() ==
           C2837X_BLOCK_PLATFORM_ERROR_TIMER_INIT);
    assert(c2837x_block_platform_generation() == generation);
    assert(timer_calls == 1u);
    assert(w5300_init_calls == 0u);
    assert(lspclk_calls == 0u);
    assert(sci_init_calls == 0u);
}

static void test_w5300_failure_does_not_start_later_resources(void)
{
    Uint32 generation = c2837x_block_platform_generation();

    if (C2837X_BLOCK_PLATFORM_TEST_MODE == PLATFORM_TEST_SCI_ONLY)
        return;

    reset_fixture();
    w5300_failure = 1u;
    assert(C2837xBlock_PlatformInit() ==
           C2837X_BLOCK_PLATFORM_ERROR_W5300_INIT);
    assert(c2837x_block_platform_generation() == generation);
    assert(w5300_init_calls == 1u);
    assert(lspclk_calls == 0u);
    assert(sci_init_calls == 0u);
}

#if PLATFORM_TEST_HAS_SCI
static void test_sci_failure_does_not_advance_generation(void)
{
    Uint32 generation = c2837x_block_platform_generation();

    reset_fixture();
    sci_failure = 1u;
    assert(C2837xBlock_PlatformInit() ==
           C2837X_BLOCK_PLATFORM_ERROR_SCI_INIT);
    assert(c2837x_block_platform_generation() == generation);
    assert(timer_calls == 1u);
    assert(lspclk_calls == 1u);
    assert(sci_init_calls == 1u);
    assert(w5300_init_calls ==
           ((C2837X_BLOCK_PLATFORM_TEST_MODE == PLATFORM_TEST_MIXED)
                ? 1u : 0u));
}
#endif

int main(void)
{
    test_success();
    test_timer_failure_does_not_advance_generation();
    test_w5300_failure_does_not_start_later_resources();
#if PLATFORM_TEST_HAS_SCI
    test_sci_failure_does_not_advance_generation();
#endif
    return 0;
}
