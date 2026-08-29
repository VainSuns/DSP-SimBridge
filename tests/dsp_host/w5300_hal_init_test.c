#include <assert.h>
#include <string.h>
#include "c2837x_block.h"
#include "c2837x_block_platform.h"
#include "c2837x_w5300_hal.h"

volatile struct TEST_CPU_SYS_REGS CpuSysRegs;
volatile struct TEST_DEVICE_CONFIG_REGS DevCfgRegs;
volatile struct TEST_CLOCK_CONFIG_REGS ClkCfgRegs;
volatile struct TEST_EMIF_REGS Emif1Regs;

const C2837xW5300ProjectConfig c2837x_w5300_project_config =
{
    {0x00u, 0x08u, 0xDCu, 0x01u, 0x02u, 0x03u},
    (Uint32)0xC0A80164UL,
    (Uint32)0xC0A80101UL,
    (Uint32)0xFFFFFF00UL
};

static volatile struct TEST_EMIF_CONFIG_REGS emif_config_regs;
static volatile struct TEST_EMIF_CONFIG_REGS failed_read_regs;
static Uint16 fail_emif_readback;
static Uint16 emif_access_count;
static Uint16 gpio30_mux_count;
static Uint16 gpio30_options_count;
static Uint16 gpio30_write_count;
static Uint16 reset_values[2];
static Uint16 reset_write_count;
static Uint32 delay_values[2];
static Uint16 delay_count;

static void reset_fixture(Uint16 fail_emif)
{
    memset((void*)&emif_config_regs, 0, sizeof(emif_config_regs));
    memset((void*)&failed_read_regs, 0, sizeof(failed_read_regs));
    failed_read_regs.EMIF1ACCPROT0.all = 1u;
    fail_emif_readback = fail_emif;
    emif_access_count = 0u;
    gpio30_mux_count = 0u;
    gpio30_options_count = 0u;
    gpio30_write_count = 0u;
    reset_write_count = 0u;
    delay_count = 0u;
}

volatile struct TEST_EMIF_CONFIG_REGS* test_emif_config_regs(void)
{
    emif_access_count++;
    if ((fail_emif_readback != 0u) && (emif_access_count == 2u))
        return &failed_read_regs;
    return &emif_config_regs;
}

void GPIO_SetupPinMux(Uint16 pin, Uint16 cpu, Uint16 mux)
{
    if ((pin == 30u) && (cpu == GPIO_MUX_CPU1) && (mux == 0u))
        gpio30_mux_count++;
}

void GPIO_SetupPinOptions(Uint16 pin, Uint16 output, Uint16 options)
{
    if ((pin == 30u) && (output == GPIO_OUTPUT) &&
        (options == GPIO_PUSHPULL))
    {
        gpio30_options_count++;
    }
}

void GPIO_WritePin(Uint16 pin, Uint16 value)
{
    if (pin == 30u)
    {
        gpio30_write_count++;
        return;
    }
    if (pin == C2837X_W5300_RESET_PIN)
        reset_values[reset_write_count++] = value;
}

void test_delay_us(Uint32 value)
{
    delay_values[delay_count++] = value;
}

int16 c2837x_block_timer2_init(void)
{
    return 0;
}

Uint32 c2837x_block_time_us(void)
{
    return 0u;
}

static void test_emif_failure_stops_hal(void)
{
    reset_fixture(1u);
    assert(c2837x_w5300_init() != 0);
    assert(gpio30_mux_count == 0u);
    assert(gpio30_options_count == 0u);
    assert(gpio30_write_count == 0u);
    assert(reset_write_count == 0u);
    assert(delay_count == 0u);
}

static void test_emif_success_runs_reset(void)
{
    reset_fixture(0u);
    assert(c2837x_w5300_init() == 0);
    assert(gpio30_mux_count == 0u);
    assert(gpio30_options_count == 0u);
    assert(gpio30_write_count == 0u);
    assert(reset_write_count == 2u);
    assert(reset_values[0] == 0u);
    assert(reset_values[1] == 1u);
    assert(delay_count == 2u);
    assert(delay_values[0] == C2837X_W5300_RESET_ASSERT_US);
    assert(delay_values[1] == C2837X_W5300_RESET_SETTLE_US);
}

static void test_platform_stops_after_hal_failure(void)
{
    reset_fixture(1u);
    assert(C2837xBlock_PlatformInit() ==
           C2837X_BLOCK_PLATFORM_ERROR_W5300_INIT);
    assert(gpio30_mux_count == 0u);
    assert(reset_write_count == 0u);
    assert(delay_count == 0u);
}

int main(void)
{
    test_emif_failure_stops_hal();
    test_emif_success_runs_reset();
    test_platform_stops_after_hal_failure();
    return 0;
}
