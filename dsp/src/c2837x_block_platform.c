#include "c2837x_block.h"
#include "c2837x_block_platform.h"
#if C2837X_BLOCK_PLATFORM_HAS_W5300
#include "c2837x_w5300_hal.h"
#endif

#if C2837X_BLOCK_PLATFORM_HAS_W5300
#define C2837X_W5300_MODE_VALUE       0xB800u
#define C2837X_W5300_ID_VALUE         0x5300u
#define C2837X_W5300_MEMORY_PAIR      \
    ((Uint16)((C2837X_W5300_SOCKET_MEMORY_KB << 8) | \
              C2837X_W5300_SOCKET_MEMORY_KB))
#define C2837X_W5300_MEMORY_TYPE      0x00FFu
#endif

#if C2837X_BLOCK_PLATFORM_HAS_SCI
#define C2837X_BLOCK_SCI_GPIO_WORDS \
    ((C2837X_BLOCK_SCI_MAX_GPIO / 32u) + 1u)
#endif

#ifndef C2837X_BLOCK_PLATFORM_CONFIG_EXTERN
const C2837xBlock_PlatformConfig c2837x_block_platform_config =
{
#if C2837X_BLOCK_PLATFORM_HAS_W5300
    1u,
#endif
#if C2837X_BLOCK_PLATFORM_HAS_SCI
    { 0, 0u }
#endif
};
#endif

static Uint32 platform_generation;

Uint32 c2837x_block_platform_generation(void)
{
    return platform_generation;
}

#if C2837X_BLOCK_PLATFORM_HAS_SCI
static int16 c2837x_block_sci_mark_gpio(Uint32 *used, Uint16 gpio)
{
    const Uint16 word = (Uint16)(gpio / 32u);
    const Uint32 mask = ((Uint32)1u << (gpio % 32u));

    if ((used[word] & mask) != 0u)
        return -1;
    used[word] |= mask;
    return 0;
}

static int16 c2837x_block_sci_config_is_valid(
    const C2837xBlock_SciDescriptorCollection *descriptors)
{
    Uint32 used_gpio[C2837X_BLOCK_SCI_GPIO_WORDS] = {0u};
    Uint16 used_modules = 0u;
    Uint16 index;

    if (descriptors == 0)
        return -1;
    if (descriptors->count == 0u)
        return 0;
    if (descriptors->items == 0)
        return -1;

    for (index = 0u; index < descriptors->count; index++)
    {
        const C2837xBlock_SciDescriptor *descriptor =
            &descriptors->items[index];

        if ((Uint32)descriptor->module >
            (Uint32)C2837X_BLOCK_SCI_MODULE_D)
            return -1;
        /* Uint16 storage enforces the upper bound of C2837X_BLOCK_SCI_BRR_MAX. */
        if ((Uint32)descriptor->brr < C2837X_BLOCK_SCI_BRR_MIN)
            return -1;
        if ((descriptor->rx.pin.gpio > C2837X_BLOCK_SCI_MAX_GPIO) ||
            (descriptor->rx.pin.mux == 0u) ||
            (descriptor->rx.pin.mux > 15u) ||
            (descriptor->tx.pin.gpio > C2837X_BLOCK_SCI_MAX_GPIO) ||
            (descriptor->tx.pin.mux == 0u) ||
            (descriptor->tx.pin.mux > 15u))
        {
            return -1;
        }
        if (((Uint32)descriptor->rx.pin_type >
             (Uint32)C2837X_BLOCK_SCI_PIN_PULLUP) ||
            ((Uint32)descriptor->tx.pin_type >
             (Uint32)C2837X_BLOCK_SCI_PIN_PULLUP) ||
            ((Uint32)descriptor->rx.qualification >
             (Uint32)C2837X_BLOCK_SCI_QUALIFICATION_ASYNC))
        {
            return -1;
        }
        if ((used_modules & ((Uint16)1u << descriptor->module)) != 0u)
            return -1;
        used_modules |= (Uint16)1u << descriptor->module;

        if (c2837x_block_sci_mark_gpio(used_gpio,
                                       descriptor->rx.pin.gpio) != 0)
            return -1;
        if (c2837x_block_sci_mark_gpio(used_gpio,
                                       descriptor->tx.pin.gpio) != 0)
            return -1;

        if (descriptor->ctrl.gpio != C2837X_BLOCK_SCI_NO_CTRL_GPIO)
        {
            if ((descriptor->ctrl.gpio > C2837X_BLOCK_SCI_MAX_GPIO) ||
                ((Uint32)descriptor->ctrl.pin_type >
                 (Uint32)C2837X_BLOCK_SCI_PIN_PULLUP) ||
                ((Uint32)descriptor->ctrl.tx_active_level >
                 (Uint32)C2837X_BLOCK_SCI_CTRL_TX_ACTIVE_HIGH))
            {
                return -1;
            }
            if (c2837x_block_sci_mark_gpio(used_gpio,
                                           descriptor->ctrl.gpio) != 0)
                return -1;
        }
    }

    return 0;
}
#endif

#if C2837X_BLOCK_PLATFORM_HAS_SCI
#if !defined(C2837X_BLOCK_PLATFORM_TEST_SEAM)
#if defined(__TI_COMPILER_VERSION__) || defined(C2837X_BLOCK_SCI_HOST_TEST)
static volatile struct SCI_REGS *c2837x_block_sci_registers(
    C2837xBlock_SciModule module)
{
    switch (module)
    {
    case C2837X_BLOCK_SCI_MODULE_A:
        return &SciaRegs;
    case C2837X_BLOCK_SCI_MODULE_B:
        return &ScibRegs;
    case C2837X_BLOCK_SCI_MODULE_C:
        return &ScicRegs;
    case C2837X_BLOCK_SCI_MODULE_D:
        return &ScidRegs;
    default:
        return 0;
    }
}

static Uint16 c2837x_block_sci_pullup_flag(C2837xBlock_SciPinType pin_type)
{
    return (pin_type == C2837X_BLOCK_SCI_PIN_PULLUP) ? GPIO_PULLUP : 0u;
}

static Uint16 c2837x_block_sci_rx_flags(
    const C2837xBlock_SciRxEndpoint *rx)
{
    const Uint16 qualification =
        (rx->qualification == C2837X_BLOCK_SCI_QUALIFICATION_ASYNC) ?
        GPIO_ASYNC : GPIO_SYNC;

    return (Uint16)(c2837x_block_sci_pullup_flag(rx->pin_type) |
                    qualification);
}

static Uint16 c2837x_block_sci_ctrl_rx_level(
    C2837xBlock_SciCtrlTxActiveLevel active_level)
{
    return (active_level == C2837X_BLOCK_SCI_CTRL_TX_ACTIVE_HIGH) ? 0u : 1u;
}

static void c2837x_block_sci_configure_pins(
    const C2837xBlock_SciDescriptor *descriptor)
{
    GPIO_SetupPinMux(descriptor->rx.pin.gpio, GPIO_MUX_CPU1,
                     descriptor->rx.pin.mux);
    GPIO_SetupPinOptions(descriptor->rx.pin.gpio, GPIO_INPUT,
                         c2837x_block_sci_rx_flags(&descriptor->rx));

    GPIO_SetupPinMux(descriptor->tx.pin.gpio, GPIO_MUX_CPU1,
                     descriptor->tx.pin.mux);
    GPIO_SetupPinOptions(
        descriptor->tx.pin.gpio, GPIO_OUTPUT,
        c2837x_block_sci_pullup_flag(descriptor->tx.pin_type));

    if (descriptor->ctrl.gpio != C2837X_BLOCK_SCI_NO_CTRL_GPIO)
    {
        GPIO_SetupPinMux(descriptor->ctrl.gpio, GPIO_MUX_CPU1, 0u);
        GPIO_SetupPinOptions(
            descriptor->ctrl.gpio, GPIO_OUTPUT,
            c2837x_block_sci_pullup_flag(descriptor->ctrl.pin_type));
        GPIO_WritePin(descriptor->ctrl.gpio,
                      c2837x_block_sci_ctrl_rx_level(
                          descriptor->ctrl.tx_active_level));
    }
}

static void c2837x_block_sci_configure_peripheral(
    const C2837xBlock_SciDescriptor *descriptor)
{
    volatile struct SCI_REGS *sci =
        c2837x_block_sci_registers(descriptor->module);

    /* Validation guarantees that this lookup cannot fail. */
    sci->SCICTL1.all = 0u;
    sci->SCICCR.all = 0u;
    sci->SCICTL2.all = 0u;
    sci->SCIFFTX.all = 0u;
    sci->SCIFFRX.all = 0u;
    sci->SCIFFCT.all = 0u;

    /* BRR is generated/precomputed; the DSP does not recalculate Baud. */
    sci->SCIHBAUD.bit.BAUD =
        (Uint16)((descriptor->brr >> 8) & 0x00FFu);
    sci->SCILBAUD.bit.BAUD =
        (Uint16)(descriptor->brr & 0x00FFu);

    /* 8 data bits, no parity, one stop bit, asynchronous SCI. */
    sci->SCICCR.bit.SCICHAR = 7u;
    sci->SCICCR.bit.ADDRIDLE_MODE = 0u;
    sci->SCICCR.bit.LOOPBKENA = 0u;
    sci->SCICCR.bit.PARITYENA = 0u;
    sci->SCICCR.bit.PARITY = 0u;
    sci->SCICCR.bit.STOPBITS = 0u;

    /* Polling only: SCI and FIFO interrupt sources remain disabled. */
    sci->SCICTL2.bit.TXINTENA = 0u;
    sci->SCICTL2.bit.RXBKINTENA = 0u;
    sci->SCICTL1.bit.RXERRINTENA = 0u;

    /* Enable the SCI FIFO with no transmit delay and no autobaud. */
    sci->SCIFFCT.bit.FFTXDLY = 0u;
    sci->SCIFFCT.bit.CDC = 0u;
    sci->SCIFFCT.bit.ABD = 0u;
    sci->SCIFFTX.bit.TXFFIENA = 0u;
    sci->SCIFFTX.bit.TXFFINTCLR = 1u;
    sci->SCIFFTX.bit.SCIFFENA = 1u;
    sci->SCIFFTX.bit.TXFIFORESET = 1u;
    sci->SCIFFTX.bit.SCIRST = 1u;
    sci->SCIFFRX.bit.RXFFIENA = 0u;
    sci->SCIFFRX.bit.RXFFINTCLR = 1u;
    sci->SCIFFRX.bit.RXFFOVRCLR = 1u;
    sci->SCIFFRX.bit.RXFIFORESET = 1u;

    sci->SCICTL1.bit.RXENA = 1u;
    sci->SCICTL1.bit.TXENA = 1u;
    sci->SCICTL1.bit.SWRESET = 1u;
}
#else
static void c2837x_block_sci_configure_pins(
    const C2837xBlock_SciDescriptor *descriptor)
{
    (void)descriptor;
}

static void c2837x_block_sci_configure_peripheral(
    const C2837xBlock_SciDescriptor *descriptor)
{
    (void)descriptor;
}
#endif
#endif

/* Host fixtures replace these link seams; they are not project config data. */
#if !defined(C2837X_BLOCK_PLATFORM_TEST_SEAM)
#if defined(__TI_COMPILER_VERSION__)
void c2837x_block_sci_lspclk_bringup(void)
{
    EALLOW;
    ClkCfgRegs.LOSPCP.all = C2837X_BLOCK_SCI_LOSPCP_VALUE;
    EDIS;
}
#else
void c2837x_block_sci_lspclk_bringup(void)
{
    /* Host builds do not access TI clock registers. */
}
#endif

int16 c2837x_block_sci_platform_init(
    const C2837xBlock_SciDescriptorCollection *descriptors)
{
    Uint16 index;

    if (descriptors == 0)
        return -1;
    if (descriptors->count == 0u)
        return 0;

    /* Validate the complete collection before touching any hardware. */
    if (c2837x_block_sci_config_is_valid(descriptors) != 0)
        return -1;

    for (index = 0u; index < descriptors->count; index++)
    {
        const C2837xBlock_SciDescriptor *descriptor =
            &descriptors->items[index];

        c2837x_block_sci_configure_pins(descriptor);
        c2837x_block_sci_configure_peripheral(descriptor);
    }

    return 0;
}
#endif
#endif /* C2837X_BLOCK_PLATFORM_HAS_SCI */

#if C2837X_BLOCK_PLATFORM_HAS_W5300
static int16 c2837x_block_w5300_sockets_are_closed(void)
{
    Uint16 sn;

    for (sn = 0u; sn < C2837X_W5300_MAX_SOCK_NUM; sn++)
    {
        if (c2837x_w5300_get_sn_ssr(sn) != SOCK_CLOSED)
            return -1;
    }

    return 0;
}

static int16 c2837x_block_w5300_initialize(void)
{
    Uint16 mode;

    if (c2837x_w5300_init() != 0)
        return -1;
    if (c2837x_w5300_read16(IDR) != C2837X_W5300_ID_VALUE)
        return -1;

    c2837x_w5300_write16(MR, C2837X_W5300_MODE_VALUE);
    mode = c2837x_w5300_read16(MR);
    c2837x_w5300_fifo_swap = (mode & MR_FS) ? 1u : 0u;
    c2837x_w5300_write16(RTR, 2000u);
    c2837x_w5300_write16(RCR, 8u);

    return c2837x_block_w5300_sockets_are_closed();
}

static int16 c2837x_block_w5300_configure_memory(void)
{
    static const Uint32 tx_registers[4] = {TMS01R, TMS23R, TMS45R, TMS67R};
    static const Uint32 rx_registers[4] = {RMS01R, RMS23R, RMS45R, RMS67R};
    Uint16 i;

    for (i = 0u; i < 4u; i++)
    {
        c2837x_w5300_write16(tx_registers[i], C2837X_W5300_MEMORY_PAIR);
        c2837x_w5300_write16(rx_registers[i], C2837X_W5300_MEMORY_PAIR);
    }
    c2837x_w5300_write16(MTYPER, C2837X_W5300_MEMORY_TYPE);

    for (i = 0u; i < 4u; i++)
    {
        if ((c2837x_w5300_read16(tx_registers[i]) != C2837X_W5300_MEMORY_PAIR) ||
            (c2837x_w5300_read16(rx_registers[i]) != C2837X_W5300_MEMORY_PAIR))
        {
            return -1;
        }
    }

    return (c2837x_w5300_read16(MTYPER) == C2837X_W5300_MEMORY_TYPE) ? 0 : -1;
}

static int16 c2837x_block_w5300_configure_network(void)
{
    const Uint16 mac01 =
        (Uint16)((c2837x_w5300_project_config.mac[0] << 8) |
                 c2837x_w5300_project_config.mac[1]);
    const Uint16 mac23 =
        (Uint16)((c2837x_w5300_project_config.mac[2] << 8) |
                 c2837x_w5300_project_config.mac[3]);
    const Uint16 mac45 =
        (Uint16)((c2837x_w5300_project_config.mac[4] << 8) |
                 c2837x_w5300_project_config.mac[5]);

    c2837x_w5300_set_shar(mac01, mac23, mac45);
    c2837x_w5300_set_gar(c2837x_w5300_project_config.gateway);
    c2837x_w5300_set_subr(c2837x_w5300_project_config.subnet);
    c2837x_w5300_set_sipr(c2837x_w5300_project_config.ip_address);

    if ((c2837x_w5300_read16(SHAR0) != mac01) ||
        (c2837x_w5300_read16(SHAR2) != mac23) ||
        (c2837x_w5300_read16(SHAR4) != mac45) ||
        (c2837x_w5300_read16(GAR0) != (Uint16)(c2837x_w5300_project_config.gateway >> 16)) ||
        (c2837x_w5300_read16(GAR2) != (Uint16)c2837x_w5300_project_config.gateway) ||
        (c2837x_w5300_read16(SUBR0) != (Uint16)(c2837x_w5300_project_config.subnet >> 16)) ||
        (c2837x_w5300_read16(SUBR2) != (Uint16)c2837x_w5300_project_config.subnet) ||
        (c2837x_w5300_read16(SIPR0) != (Uint16)(c2837x_w5300_project_config.ip_address >> 16)) ||
        (c2837x_w5300_read16(SIPR2) != (Uint16)c2837x_w5300_project_config.ip_address))
    {
        return -1;
    }

    return 0;
}
#endif /* C2837X_BLOCK_PLATFORM_HAS_W5300 */

int16 C2837xBlock_PlatformInit(void)
{
    if (c2837x_block_timer2_init() != 0)
        return (int16)C2837X_BLOCK_PLATFORM_ERROR_TIMER_INIT;

#if C2837X_BLOCK_PLATFORM_HAS_W5300
    if (c2837x_block_platform_config.use_w5300 != 0u)
    {
        if (c2837x_block_w5300_initialize() != 0)
            return (int16)C2837X_BLOCK_PLATFORM_ERROR_W5300_INIT;

        if (c2837x_block_w5300_configure_memory() != 0)
            return (int16)C2837X_BLOCK_PLATFORM_ERROR_W5300_MEMORY;

        if (c2837x_block_w5300_configure_network() != 0)
            return (int16)C2837X_BLOCK_PLATFORM_ERROR_NETWORK_CONFIG;
    }
#endif

#if C2837X_BLOCK_PLATFORM_HAS_SCI
    if (c2837x_block_platform_config.sci_descriptors.count != 0u)
    {
        if (c2837x_block_sci_config_is_valid(
                &c2837x_block_platform_config.sci_descriptors) != 0)
            return (int16)C2837X_BLOCK_PLATFORM_ERROR_SCI_INIT;

        c2837x_block_sci_lspclk_bringup();
        if (c2837x_block_sci_platform_init(
                &c2837x_block_platform_config.sci_descriptors) != 0)
        {
            return (int16)C2837X_BLOCK_PLATFORM_ERROR_SCI_INIT;
        }
    }
#endif

    platform_generation++;
    if (platform_generation == 0u)
        platform_generation = 1u;

    return (int16)C2837X_BLOCK_PLATFORM_OK;
}
