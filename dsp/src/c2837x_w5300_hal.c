/*
 * W5300 hardware abstraction layer implementation for C2837x.
 */

#include "c2837x_w5300_hal.h"

Uint16 c2837x_w5300_fifo_swap = 0;

static int16 c2837x_w5300_init_emif1(void)
{
    Uint16 ErrCount = 0;

    /* EMIF1 control signals used by the asynchronous W5300 CS4 bus. */
    GPIO_SetupPinMux(28, 0, 2); /* EM1CS4N */
    GPIO_SetupPinMux(31, 0, 2); /* EM1WEN */
    GPIO_SetupPinMux(37, 0, 2); /* EM1OEN */

    /* Keep the existing direct-mode address bus configuration. */
    GPIO_SetupPinMux(38, 0, 2);
    GPIO_SetupPinMux(39, 0, 2);
    GPIO_SetupPinMux(40, 0, 2);
    GPIO_SetupPinMux(41, 0, 2);
    GPIO_SetupPinMux(44, 0, 2);
    GPIO_SetupPinMux(45, 0, 2);
    GPIO_SetupPinMux(46, 0, 2);
    GPIO_SetupPinMux(47, 0, 2);
    GPIO_SetupPinMux(48, 0, 2);
    GPIO_SetupPinMux(49, 0, 2);
    GPIO_SetupPinMux(50, 0, 2);
    GPIO_SetupPinMux(51, 0, 2);
    GPIO_SetupPinMux(52, 0, 2);
    GPIO_SetupPinMux(86, 0, 2);
    GPIO_SetupPinMux(87, 0, 2);
    GPIO_SetupPinMux(88, 0, 3);
    GPIO_SetupPinMux(89, 0, 3);
    GPIO_SetupPinMux(90, 0, 3);
    GPIO_SetupPinMux(91, 0, 3);
    GPIO_SetupPinMux(92, 0, 3);
    GPIO_SetupPinMux(93, 0, 3);

    /* EM1D0-EM1D15 are GPIO69-83 and GPIO85. */
    GPIO_SetupPinMux(69, 0, 2);
    GPIO_SetupPinMux(70, 0, 2);
    GPIO_SetupPinMux(71, 0, 2);
    GPIO_SetupPinMux(72, 0, 2);
    GPIO_SetupPinMux(73, 0, 2);
    GPIO_SetupPinMux(74, 0, 2);
    GPIO_SetupPinMux(75, 0, 2);
    GPIO_SetupPinMux(76, 0, 2);
    GPIO_SetupPinMux(77, 0, 2);
    GPIO_SetupPinMux(78, 0, 2);
    GPIO_SetupPinMux(79, 0, 2);
    GPIO_SetupPinMux(80, 0, 2);
    GPIO_SetupPinMux(81, 0, 2);
    GPIO_SetupPinMux(82, 0, 2);
    GPIO_SetupPinMux(83, 0, 2);
    GPIO_SetupPinMux(85, 0, 2);

    GPIO_SetupPinOptions(69, 0, 0x31);
    GPIO_SetupPinOptions(70, 0, 0x31);
    GPIO_SetupPinOptions(71, 0, 0x31);
    GPIO_SetupPinOptions(72, 0, 0x31);
    GPIO_SetupPinOptions(73, 0, 0x31);
    GPIO_SetupPinOptions(74, 0, 0x31);
    GPIO_SetupPinOptions(75, 0, 0x31);
    GPIO_SetupPinOptions(76, 0, 0x31);
    GPIO_SetupPinOptions(77, 0, 0x31);
    GPIO_SetupPinOptions(78, 0, 0x31);
    GPIO_SetupPinOptions(79, 0, 0x31);
    GPIO_SetupPinOptions(80, 0, 0x31);
    GPIO_SetupPinOptions(81, 0, 0x31);
    GPIO_SetupPinOptions(82, 0, 0x31);
    GPIO_SetupPinOptions(83, 0, 0x31);
    GPIO_SetupPinOptions(85, 0, 0x31);

    EALLOW;
#ifdef CPU1
    CpuSysRegs.PCLKCR1.bit.EMIF1 = 1;
#endif
    EDIS;

    EALLOW;
#ifdef CPU1
    DevCfgRegs.SOFTPRES1.all = 0x1;
    __asm(" nop");
    DevCfgRegs.SOFTPRES1.all = 0x0;
#endif
    EDIS;

    EALLOW;
    ClkCfgRegs.PERCLKDIVSEL.bit.EMIF1CLKDIV = 0x0;
    EDIS;

    EALLOW;
    Emif1ConfigRegs.EMIF1ACCPROT0.all = 0x0;
    if (Emif1ConfigRegs.EMIF1ACCPROT0.all != 0x0)
    {
        ErrCount++;
    }

    Emif1ConfigRegs.EMIF1COMMIT.all = 0x1;
    if (Emif1ConfigRegs.EMIF1COMMIT.all != 0x1)
    {
        ErrCount++;
    }

    Emif1ConfigRegs.EMIF1LOCK.all = 0x1;
    if (Emif1ConfigRegs.EMIF1LOCK.all != 1)
    {
        ErrCount++;
    }

    EDIS;

    Emif1Regs.ASYNC_CS4_CR.bit.ASIZE = 1;
    Emif1Regs.ASYNC_CS4_CR.bit.TA = 2;
    Emif1Regs.ASYNC_CS4_CR.bit.R_HOLD = 2;
    Emif1Regs.ASYNC_CS4_CR.bit.R_STROBE = 7;
    Emif1Regs.ASYNC_CS4_CR.bit.R_SETUP = 2;
    Emif1Regs.ASYNC_CS4_CR.bit.W_HOLD = 2;
    Emif1Regs.ASYNC_CS4_CR.bit.W_STROBE = 7;
    Emif1Regs.ASYNC_CS4_CR.bit.W_SETUP = 2;
    Emif1Regs.ASYNC_CS4_CR.bit.EW = 0;
    Emif1Regs.ASYNC_CS4_CR.bit.SS = 0;

    return (ErrCount == 0u) ? 0 : -1;
}

void c2837x_w5300_reset(void)
{
    GPIO_WritePin(C2837X_W5300_RESET_PIN, 0);
    DELAY_US(C2837X_W5300_RESET_ASSERT_US);
    GPIO_WritePin(C2837X_W5300_RESET_PIN, 1);
    DELAY_US(C2837X_W5300_RESET_SETTLE_US);
}

int16 c2837x_w5300_init(void)
{
    GPIO_SetupPinMux(C2837X_W5300_RESET_PIN, GPIO_MUX_CPU1, 0);
    GPIO_SetupPinOptions(C2837X_W5300_RESET_PIN, GPIO_OUTPUT, GPIO_PUSHPULL);

    if (c2837x_w5300_init_emif1() != 0)
        return -1;

    c2837x_w5300_reset();
    return 0;
}

static inline Uint16 c2837x_w5300_swap16(Uint16 value)
{
    return (Uint16)((value << 8) | (value >> 8));
}

#if __TI_COMPILER_VERSION__ >= 15009000
    #pragma CODE_SECTION(c2837x_w5300_read16, ".TI.ramfunc");
#else
    #pragma CODE_SECTION(c2837x_w5300_read16, "ramfuncs");
#endif
Uint16 c2837x_w5300_read16(Uint32 addr)
{
#ifdef C2837X_W5300_HOST_TEST
    extern Uint16 c2837x_w5300_host_read16(Uint32 address);
    return c2837x_w5300_host_read16(addr);
#else
#if (C2837X_W5300_ADDRESS_MODE == C2837X_W5300_DIRECT_MODE)
    return (*((volatile Uint16*)(addr)));
#else
    volatile Uint16 data;
    *((volatile Uint16*)IDM_AR) = (Uint16)addr;
    data = *((volatile Uint16*)IDM_DR);
    return data;
#endif
#endif
}

#if __TI_COMPILER_VERSION__ >= 15009000
    #pragma CODE_SECTION(c2837x_w5300_write16, ".TI.ramfunc");
#else
    #pragma CODE_SECTION(c2837x_w5300_write16, "ramfuncs");
#endif
void c2837x_w5300_write16(Uint32 addr, Uint16 data)
{
#ifdef C2837X_W5300_HOST_TEST
    extern void c2837x_w5300_host_write16(Uint32 address, Uint16 value);
    c2837x_w5300_host_write16(addr, data);
#else
#if (C2837X_W5300_ADDRESS_MODE == C2837X_W5300_DIRECT_MODE)
    (*((volatile Uint16*)(addr))) = data;
#else
    *((volatile Uint16*)IDM_AR) = addr;
    *((volatile Uint16*)IDM_DR) = data;
#endif
#endif
}

#if __TI_COMPILER_VERSION__ >= 15009000
    #pragma CODE_SECTION(c2837x_w5300_issue_sn_cr, ".TI.ramfunc");
#else
    #pragma CODE_SECTION(c2837x_w5300_issue_sn_cr, "ramfuncs");
#endif
int16 c2837x_w5300_issue_sn_cr(Uint16 sn, Uint16 command)
{
    if ((sn >= C2837X_W5300_MAX_SOCK_NUM) || (command == 0u))
        return -1;
    c2837x_w5300_write8(Sn_CR(sn), command);
    return 0;
}

int16 c2837x_w5300_poll_sn_cr(Uint16 sn)
{
    if (sn >= C2837X_W5300_MAX_SOCK_NUM)
        return -1;
    return (c2837x_w5300_read8(Sn_CR(sn)) == 0u) ? 1 : 0;
}

#if __TI_COMPILER_VERSION__ >= 15009000
    #pragma CODE_SECTION(c2837x_w5300_get_sn_tx_fsr, ".TI.ramfunc");
#else
    #pragma CODE_SECTION(c2837x_w5300_get_sn_tx_fsr, "ramfuncs");
#endif
int16 c2837x_w5300_get_sn_tx_fsr(Uint16 sn, Uint32 *value)
{
    Uint16 attempt;
    Uint32 v1;
    Uint32 v2;

    if ((sn >= C2837X_W5300_MAX_SOCK_NUM) || (value == 0))
        return -1;
    for (attempt = 0u; attempt < C2837X_W5300_STABLE_READ_ATTEMPTS; attempt++)
    {
        v1 = ((Uint32)c2837x_w5300_read16(Sn_TX_FSR(sn)) << 16) | c2837x_w5300_read16(Sn_TX_FSR2(sn));
        v2 = ((Uint32)c2837x_w5300_read16(Sn_TX_FSR(sn)) << 16) | c2837x_w5300_read16(Sn_TX_FSR2(sn));
        if (v1 == v2)
        {
            *value = v1;
            return 0;
        }
    }
    return -1;
}

#if __TI_COMPILER_VERSION__ >= 15009000
    #pragma CODE_SECTION(c2837x_w5300_get_sn_rx_rsr, ".TI.ramfunc");
#else
    #pragma CODE_SECTION(c2837x_w5300_get_sn_rx_rsr, "ramfuncs");
#endif
int16 c2837x_w5300_get_sn_rx_rsr(Uint16 sn, Uint32 *value)
{
    Uint16 attempt;
    Uint32 v1;
    Uint32 v2;

    if ((sn >= C2837X_W5300_MAX_SOCK_NUM) || (value == 0))
        return -1;
    for (attempt = 0u; attempt < C2837X_W5300_STABLE_READ_ATTEMPTS; attempt++)
    {
        v1 = ((Uint32)c2837x_w5300_read16(Sn_RX_RSR(sn)) << 16) | c2837x_w5300_read16(Sn_RX_RSR2(sn));
        v2 = ((Uint32)c2837x_w5300_read16(Sn_RX_RSR(sn)) << 16) | c2837x_w5300_read16(Sn_RX_RSR2(sn));
        if (v1 == v2)
        {
            *value = v1;
            return 0;
        }
    }
    return -1;
}

#if __TI_COMPILER_VERSION__ >= 15009000
    #pragma CODE_SECTION(c2837x_w5300_write_stream, ".TI.ramfunc");
#else
    #pragma CODE_SECTION(c2837x_w5300_write_stream, "ramfuncs");
#endif
Uint32 c2837x_w5300_write_stream(Uint16 sn, const Uint16* dsp_data, Uint32 wire_byte_count)
{
    Uint32 i;
    const Uint32 word_count = (wire_byte_count + 1U) >> 1;

    for (i = 0; i < word_count; i++)
    {
        Uint16 word = dsp_data[i];
        Uint32 bi = i << 1;

        if ((bi + 1U) >= wire_byte_count)
            word &= 0x00FFu;

        if (!c2837x_w5300_fifo_swap)
            word = c2837x_w5300_swap16(word);

        c2837x_w5300_write16(Sn_TX_FIFOR(sn), word);
    }
    return wire_byte_count;
}

#if __TI_COMPILER_VERSION__ >= 15009000
    #pragma CODE_SECTION(c2837x_w5300_read_stream, ".TI.ramfunc");
#else
    #pragma CODE_SECTION(c2837x_w5300_read_stream, "ramfuncs");
#endif
Uint32 c2837x_w5300_read_stream(Uint16 sn, Uint16* dsp_data, Uint32 wire_byte_count)
{
    Uint32 i;
    const Uint32 word_count = (wire_byte_count + 1U) >> 1;

    for (i = 0; i < word_count; i++)
    {
        Uint16 word = c2837x_w5300_read16(Sn_RX_FIFOR(sn));
        Uint32 bi = i << 1;

        if (!c2837x_w5300_fifo_swap)
            word = c2837x_w5300_swap16(word);

        if ((bi + 1U) >= wire_byte_count)
            word &= 0x00FFu;

        dsp_data[i] = word;
    }
    return wire_byte_count;
}
