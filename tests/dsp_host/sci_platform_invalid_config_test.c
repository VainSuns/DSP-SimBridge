#include <assert.h>
#include "c2837x_block.h"
#include "c2837x_block_platform.h"
#include "c2837x_w5300_hal.h"

volatile struct SCI_REGS SciaRegs;
volatile struct SCI_REGS ScibRegs;
volatile struct SCI_REGS ScicRegs;
volatile struct SCI_REGS ScidRegs;

Uint16 c2837x_w5300_fifo_swap;
const C2837xW5300ProjectConfig c2837x_w5300_project_config =
{
    {0u, 0u, 0u, 0u, 0u, 0u}, 0u, 0u, 0u
};

static const C2837xBlock_SciDescriptor invalid_descriptor =
{
    C2837X_BLOCK_SCI_MODULE_A,
    0u,
    {{9u, 6u}, C2837X_BLOCK_SCI_PIN_STANDARD,
     C2837X_BLOCK_SCI_QUALIFICATION_SYNC},
    {{8u, 6u}, C2837X_BLOCK_SCI_PIN_STANDARD},
    {C2837X_BLOCK_SCI_NO_CTRL_GPIO, C2837X_BLOCK_SCI_PIN_STANDARD,
     C2837X_BLOCK_SCI_CTRL_TX_ACTIVE_LOW}
};

const C2837xBlock_PlatformConfig c2837x_block_platform_config =
{
    0u,
    {&invalid_descriptor, 1u}
};

static Uint16 timer_calls;
static Uint16 gpio_calls;

int16 c2837x_block_timer2_init(void)
{
    timer_calls++;
    return 0;
}

Uint32 c2837x_block_time_us(void)
{
    return 0u;
}

int16 c2837x_w5300_init(void)
{
    assert(0);
    return -1;
}

void c2837x_w5300_write16(Uint32 address, Uint16 data)
{
    (void)address;
    (void)data;
    assert(0);
}

Uint16 c2837x_w5300_read16(Uint32 address)
{
    (void)address;
    assert(0);
    return 0u;
}

void GPIO_SetupPinMux(Uint16 gpio, Uint16 cpu, Uint16 mux)
{
    (void)gpio;
    (void)cpu;
    (void)mux;
    gpio_calls++;
}

void GPIO_SetupPinOptions(Uint16 gpio, Uint16 output, Uint16 flags)
{
    (void)gpio;
    (void)output;
    (void)flags;
    gpio_calls++;
}

void GPIO_WritePin(Uint16 gpio, Uint16 value)
{
    (void)gpio;
    (void)value;
    gpio_calls++;
}

int main(void)
{
    assert(C2837xBlock_PlatformInit() ==
           C2837X_BLOCK_PLATFORM_ERROR_SCI_INIT);
    assert(timer_calls == 1u);
    assert(gpio_calls == 0u);
    assert(c2837x_block_platform_generation() == 0u);
    return 0;
}
