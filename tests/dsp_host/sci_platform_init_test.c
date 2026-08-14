#include <assert.h>
#include <string.h>
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
    {0u, 0u, 0u, 0u, 0u, 0u},
    0u,
    0u,
    0u
};

static const C2837xBlock_SciDescriptor descriptors[] =
{
    {
        C2837X_BLOCK_SCI_MODULE_A,
        0x1234u,
        {{9u, 6u}, C2837X_BLOCK_SCI_PIN_PULLUP,
         C2837X_BLOCK_SCI_QUALIFICATION_SYNC},
        {{8u, 6u}, C2837X_BLOCK_SCI_PIN_STANDARD},
        {30u, C2837X_BLOCK_SCI_PIN_PULLUP,
         C2837X_BLOCK_SCI_CTRL_TX_ACTIVE_HIGH}
    },
    {
        C2837X_BLOCK_SCI_MODULE_B,
        0xABCDu,
        {{11u, 2u}, C2837X_BLOCK_SCI_PIN_STANDARD,
         C2837X_BLOCK_SCI_QUALIFICATION_ASYNC},
        {{10u, 6u}, C2837X_BLOCK_SCI_PIN_PULLUP},
        {C2837X_BLOCK_SCI_NO_CTRL_GPIO, C2837X_BLOCK_SCI_PIN_STANDARD,
         C2837X_BLOCK_SCI_CTRL_TX_ACTIVE_LOW}
    },
    {
        C2837X_BLOCK_SCI_MODULE_C,
        0x0001u,
        {{13u, 6u}, C2837X_BLOCK_SCI_PIN_PULLUP,
         C2837X_BLOCK_SCI_QUALIFICATION_ASYNC},
        {{12u, 6u}, C2837X_BLOCK_SCI_PIN_STANDARD},
        {C2837X_BLOCK_SCI_NO_CTRL_GPIO, C2837X_BLOCK_SCI_PIN_STANDARD,
         C2837X_BLOCK_SCI_CTRL_TX_ACTIVE_LOW}
    },
    {
        C2837X_BLOCK_SCI_MODULE_D,
        0xFFFFu,
        {{46u, 6u}, C2837X_BLOCK_SCI_PIN_STANDARD,
         C2837X_BLOCK_SCI_QUALIFICATION_SYNC},
        {{47u, 6u}, C2837X_BLOCK_SCI_PIN_PULLUP},
        {C2837X_BLOCK_SCI_NO_CTRL_GPIO, C2837X_BLOCK_SCI_PIN_STANDARD,
         C2837X_BLOCK_SCI_CTRL_TX_ACTIVE_LOW}
    }
};

const C2837xBlock_PlatformConfig c2837x_block_platform_config =
{
    0u,
    {descriptors, (Uint16)(sizeof(descriptors) / sizeof(descriptors[0]))}
};

static Uint16 timer_calls;
static Uint16 mux_calls;
static Uint16 option_calls;
static Uint16 write_calls;

struct MuxCall
{
    Uint16 gpio;
    Uint16 cpu;
    Uint16 mux;
};

struct OptionCall
{
    Uint16 gpio;
    Uint16 output;
    Uint16 flags;
};

static struct MuxCall mux_log[16];
static struct OptionCall option_log[16];
static struct { Uint16 gpio; Uint16 value; } write_log[8];

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
    return 0;
}

void c2837x_w5300_write16(Uint32 address, Uint16 data)
{
    (void)address;
    (void)data;
}

Uint16 c2837x_w5300_read16(Uint32 address)
{
    (void)address;
    return 0u;
}

void GPIO_SetupPinMux(Uint16 gpio, Uint16 cpu, Uint16 mux)
{
    mux_log[mux_calls].gpio = gpio;
    mux_log[mux_calls].cpu = cpu;
    mux_log[mux_calls].mux = mux;
    mux_calls++;
}

void GPIO_SetupPinOptions(Uint16 gpio, Uint16 output, Uint16 flags)
{
    option_log[option_calls].gpio = gpio;
    option_log[option_calls].output = output;
    option_log[option_calls].flags = flags;
    option_calls++;
}

void GPIO_WritePin(Uint16 gpio, Uint16 value)
{
    write_log[write_calls].gpio = gpio;
    write_log[write_calls].value = value;
    write_calls++;
}

static void reset_fixture(void)
{
    memset((void *)&SciaRegs, 0, sizeof(SciaRegs));
    memset((void *)&ScibRegs, 0, sizeof(ScibRegs));
    memset((void *)&ScicRegs, 0, sizeof(ScicRegs));
    memset((void *)&ScidRegs, 0, sizeof(ScidRegs));
    memset(mux_log, 0, sizeof(mux_log));
    memset(option_log, 0, sizeof(option_log));
    memset(write_log, 0, sizeof(write_log));
    timer_calls = 0u;
    mux_calls = 0u;
    option_calls = 0u;
    write_calls = 0u;
}

static void assert_format(const volatile struct SCI_REGS *sci,
                          Uint16 brr)
{
    assert(sci->SCIHBAUD.bit.BAUD ==
           (Uint16)((brr >> 8) & 0x00FFu));
    assert(sci->SCILBAUD.bit.BAUD ==
           (Uint16)(brr & 0x00FFu));
    assert(sci->SCICCR.bit.SCICHAR == 7u);
    assert(sci->SCICCR.bit.ADDRIDLE_MODE == 0u);
    assert(sci->SCICCR.bit.LOOPBKENA == 0u);
    assert(sci->SCICCR.bit.PARITYENA == 0u);
    assert(sci->SCICCR.bit.PARITY == 0u);
    assert(sci->SCICCR.bit.STOPBITS == 0u);
    assert(sci->SCICTL1.bit.RXENA == 1u);
    assert(sci->SCICTL1.bit.TXENA == 1u);
    assert(sci->SCICTL1.bit.SWRESET == 1u);
    assert(sci->SCICTL1.bit.RXERRINTENA == 0u);
    assert(sci->SCICTL2.bit.TXINTENA == 0u);
    assert(sci->SCICTL2.bit.RXBKINTENA == 0u);
    assert(sci->SCIFFTX.bit.SCIFFENA == 1u);
    assert(sci->SCIFFTX.bit.TXFIFORESET == 1u);
    assert(sci->SCIFFTX.bit.SCIRST == 1u);
    assert(sci->SCIFFTX.bit.TXFFIENA == 0u);
    assert(sci->SCIFFTX.bit.TXFFINTCLR == 1u);
    assert(sci->SCIFFRX.bit.RXFIFORESET == 1u);
    assert(sci->SCIFFRX.bit.RXFFIENA == 0u);
    assert(sci->SCIFFRX.bit.RXFFINTCLR == 1u);
    assert(sci->SCIFFRX.bit.RXFFOVRCLR == 1u);
    assert(sci->SCIFFCT.bit.FFTXDLY == 0u);
    assert(sci->SCIFFCT.bit.CDC == 0u);
    assert(sci->SCIFFCT.bit.ABD == 0u);
}

static void test_all_modules_and_pin_branches(void)
{
    reset_fixture();
    assert(C2837xBlock_PlatformInit() == C2837X_BLOCK_PLATFORM_OK);
    assert(timer_calls == 1u);
    assert(mux_calls == 9u);
    assert(option_calls == 9u);
    assert(write_calls == 1u);

    assert(mux_log[0].gpio == 9u && mux_log[0].cpu == GPIO_MUX_CPU1 &&
           mux_log[0].mux == 6u);
    assert(option_log[0].gpio == 9u && option_log[0].output == GPIO_INPUT &&
           option_log[0].flags == (GPIO_PULLUP | GPIO_SYNC));
    assert(mux_log[1].gpio == 8u && mux_log[1].mux == 6u);
    assert(option_log[1].gpio == 8u && option_log[1].output == GPIO_OUTPUT &&
           option_log[1].flags == 0u);
    assert(mux_log[2].gpio == 30u && mux_log[2].mux == 0u);
    assert(option_log[2].gpio == 30u && option_log[2].output == GPIO_OUTPUT &&
           option_log[2].flags == GPIO_PULLUP);
    assert(write_log[0].gpio == 30u && write_log[0].value == 0u);

    assert(option_log[3].gpio == 11u && option_log[3].output == GPIO_INPUT &&
           option_log[3].flags == GPIO_ASYNC);
    assert(option_log[4].gpio == 10u && option_log[4].output == GPIO_OUTPUT &&
           option_log[4].flags == GPIO_PULLUP);
    assert(option_log[5].gpio == 13u && option_log[5].output == GPIO_INPUT &&
           option_log[5].flags == (GPIO_PULLUP | GPIO_ASYNC));
    assert(option_log[6].gpio == 12u && option_log[6].output == GPIO_OUTPUT &&
           option_log[6].flags == 0u);
    assert(option_log[7].gpio == 46u && option_log[7].output == GPIO_INPUT &&
           option_log[7].flags == GPIO_SYNC);
    assert(option_log[8].gpio == 47u && option_log[8].output == GPIO_OUTPUT &&
           option_log[8].flags == GPIO_PULLUP);

    assert_format(&SciaRegs, 0x1234u);
    assert_format(&ScibRegs, 0xABCDu);
    assert_format(&ScicRegs, 0x0001u);
    assert_format(&ScidRegs, 0xFFFFu);
}

static void test_unused_modules_are_untouched(void)
{
    const C2837xBlock_SciDescriptorCollection one = {&descriptors[0], 1u};
    struct SCI_REGS before_b;
    struct SCI_REGS before_c;
    struct SCI_REGS before_d;

    reset_fixture();
    memset((void *)&ScibRegs, 0x5Au, sizeof(ScibRegs));
    memset((void *)&ScicRegs, 0x6Bu, sizeof(ScicRegs));
    memset((void *)&ScidRegs, 0x7Cu, sizeof(ScidRegs));
    memcpy(&before_b, (const void *)&ScibRegs, sizeof(before_b));
    memcpy(&before_c, (const void *)&ScicRegs, sizeof(before_c));
    memcpy(&before_d, (const void *)&ScidRegs, sizeof(before_d));

    assert(c2837x_block_sci_platform_init(&one) == 0);
    assert(memcmp(&before_b, (const void *)&ScibRegs, sizeof(before_b)) == 0);
    assert(memcmp(&before_c, (const void *)&ScicRegs, sizeof(before_c)) == 0);
    assert(memcmp(&before_d, (const void *)&ScidRegs, sizeof(before_d)) == 0);
}

static void assert_invalid(const C2837xBlock_SciDescriptorCollection *collection)
{
    reset_fixture();
    assert(c2837x_block_sci_platform_init(collection) != 0);
    assert(mux_calls == 0u);
    assert(option_calls == 0u);
    assert(write_calls == 0u);
}

static void test_descriptor_validation(void)
{
    C2837xBlock_SciDescriptor invalid = descriptors[0];
    C2837xBlock_SciDescriptor duplicate = descriptors[1];
    C2837xBlock_SciDescriptor pair[2];
    C2837xBlock_SciDescriptorCollection collection;

    collection.items = 0;
    collection.count = 1u;
    assert_invalid(&collection);
    assert_invalid(0);

    invalid.module = (C2837xBlock_SciModule)99u;
    collection.items = &invalid;
    collection.count = 1u;
    assert_invalid(&collection);

    invalid = descriptors[0];
    invalid.brr = 0u;
    assert_invalid(&((C2837xBlock_SciDescriptorCollection){&invalid, 1u}));

    invalid = descriptors[0];
    invalid.rx.pin.mux = 0u;
    assert_invalid(&((C2837xBlock_SciDescriptorCollection){&invalid, 1u}));

    duplicate.module = C2837X_BLOCK_SCI_MODULE_A;
    pair[0] = descriptors[0];
    pair[1] = duplicate;
    assert_invalid(&((C2837xBlock_SciDescriptorCollection){pair, 2u}));
}

int main(void)
{
    test_all_modules_and_pin_branches();
    test_unused_modules_are_untouched();
    test_descriptor_validation();
    return 0;
}
