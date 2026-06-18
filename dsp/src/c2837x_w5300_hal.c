/*
 * W5300 hardware abstraction layer implementation for C2837x.
 */

#include "c2837x_w5300_hal.h"

Uint16 c2837x_w5300_fifo_swap = 0;

static void c2837x_w5300_init_emif1(void)
{
    Uint16 ErrCount = 0, i = 0;

    for (i = 28; i <= 52; i++)
    {
        if ((i != 42) && (i != 43))
        {
            GPIO_SetupPinMux(i, 0, 2);
        }
    }
    for (i = 63; i <= 87; i++)
    {
        if (i != 84)
        {
            GPIO_SetupPinMux(i, 0, 2);
        }
    }

    GPIO_SetupPinMux(88, 0, 3);
    GPIO_SetupPinMux(89, 0, 3);
    GPIO_SetupPinMux(90, 0, 3);
    GPIO_SetupPinMux(91, 0, 3);
    GPIO_SetupPinMux(92, 0, 3);
    GPIO_SetupPinMux(93, 0, 3);
    GPIO_SetupPinMux(94, 0, 2);

    for (i = 69; i <= 85; i++)
    {
        if (i != 84)
        {
            GPIO_SetupPinOptions(i, 0, 0x31);
        }
    }

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
}

void c2837x_w5300_reset(void)
{
    GPIO_WritePin(C2837X_W5300_RESET_PIN, 1);
    DELAY_US(1000);
    GPIO_WritePin(C2837X_W5300_RESET_PIN, 0);
    DELAY_US(20000);
    GPIO_WritePin(C2837X_W5300_RESET_PIN, 1);
    DELAY_US(1000);
}

void c2837x_w5300_init(void)
{
    GPIO_SetupPinMux(C2837X_W5300_RESET_PIN, GPIO_MUX_CPU1, 0);
    GPIO_SetupPinOptions(C2837X_W5300_RESET_PIN, GPIO_OUTPUT, GPIO_PUSHPULL);

    c2837x_w5300_init_emif1();

    GPIO_SetupPinMux(30, GPIO_MUX_CPU1, 0);
    GPIO_SetupPinOptions(30, GPIO_OUTPUT, GPIO_PUSHPULL);
    GPIO_WritePin(30, 1);

    c2837x_w5300_reset();
}

int16 c2837x_w5300_configure_socket_memory(Uint16 sn,
                                            Uint16 tx_kb,
                                            Uint16 rx_kb,
                                            Uint32* out_tx_bytes,
                                            Uint32* out_rx_bytes)
{
    /*
     * W5300 has 128 KB total socket buffer.
     * TMS01R..TMS67R: TX memory size per socket (in KB), packed as pairs.
     * RMS01R..RMS67R: RX memory size per socket (in KB), packed as pairs.
     * MTYPER: bit mask indicating which 8 KB blocks are allocated to TX.
     *
     * Constraints:
     *   - Each socket TX/RX <= 64 KB.
     *   - Total TX must be multiple of 8 KB.
     *   - Total TX + RX <= 128 KB.
     */
    Uint16 tx_sizes[C2837X_W5300_MAX_SOCK_NUM];
    Uint16 rx_sizes[C2837X_W5300_MAX_SOCK_NUM];
    Uint16 i;
    Uint16 tx_sum = 0;
    Uint16 rx_sum = 0;
    Uint16 mem_cfg = 0;

    /* Zero out all socket sizes */
    for (i = 0; i < C2837X_W5300_MAX_SOCK_NUM; i++)
    {
        tx_sizes[i] = 0;
        rx_sizes[i] = 0;
    }

    /* Set the target socket */
    if (sn >= C2837X_W5300_MAX_SOCK_NUM)
        return -1;

    tx_sizes[sn] = tx_kb;
    rx_sizes[sn] = rx_kb;

    /* Validate per-socket limit */
    if (tx_kb > 64U || rx_kb > 64U)
        return -1;

    /* Validate total constraints */
    tx_sum = tx_kb;
    rx_sum = rx_kb;
    if ((tx_sum % 8U) != 0U)
        return -1;
    if ((tx_sum + rx_sum) > 128U)
        return -1;

    /* Write TX memory size registers (packed pairs) */
    c2837x_w5300_write16(TMS01R, (Uint16)((tx_sizes[0] << 8) | tx_sizes[1]));
    c2837x_w5300_write16(TMS23R, (Uint16)((tx_sizes[2] << 8) | tx_sizes[3]));
    c2837x_w5300_write16(TMS45R, (Uint16)((tx_sizes[4] << 8) | tx_sizes[5]));
    c2837x_w5300_write16(TMS67R, (Uint16)((tx_sizes[6] << 8) | tx_sizes[7]));

    /* Write RX memory size registers (packed pairs) */
    c2837x_w5300_write16(RMS01R, (Uint16)((rx_sizes[0] << 8) | rx_sizes[1]));
    c2837x_w5300_write16(RMS23R, (Uint16)((rx_sizes[2] << 8) | rx_sizes[3]));
    c2837x_w5300_write16(RMS45R, (Uint16)((rx_sizes[4] << 8) | rx_sizes[5]));
    c2837x_w5300_write16(RMS67R, (Uint16)((rx_sizes[6] << 8) | rx_sizes[7]));

    /* Write memory type register (TX block allocation bitmask) */
    for (i = 0; i < (tx_sum / 8U); i++)
    {
        mem_cfg = (Uint16)((mem_cfg << 1) | 1U);
    }
    c2837x_w5300_write16(MTYPER, mem_cfg);

    /* Return actual buffer sizes in bytes */
    *out_tx_bytes = ((Uint32)tx_kb) << 10;
    *out_rx_bytes = ((Uint32)rx_kb) << 10;

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
#if (C2837X_W5300_ADDRESS_MODE == C2837X_W5300_DIRECT_MODE)
    return (*((volatile Uint16*)(addr)));
#else
    volatile Uint16 data;
    *((volatile Uint16*)IDM_AR) = (Uint16)addr;
    data = *((volatile Uint16*)IDM_DR);
    return data;
#endif
}

#if __TI_COMPILER_VERSION__ >= 15009000
    #pragma CODE_SECTION(c2837x_w5300_write16, ".TI.ramfunc");
#else
    #pragma CODE_SECTION(c2837x_w5300_write16, "ramfuncs");
#endif
void c2837x_w5300_write16(Uint32 addr, Uint16 data)
{
#if (C2837X_W5300_ADDRESS_MODE == C2837X_W5300_DIRECT_MODE)
    (*((volatile Uint16*)(addr))) = data;
#else
    *((volatile Uint16*)IDM_AR) = addr;
    *((volatile Uint16*)IDM_DR) = data;
#endif
}

#if __TI_COMPILER_VERSION__ >= 15009000
    #pragma CODE_SECTION(c2837x_w5300_set_sn_cr, ".TI.ramfunc");
#else
    #pragma CODE_SECTION(c2837x_w5300_set_sn_cr, "ramfuncs");
#endif
int16 c2837x_w5300_set_sn_cr(Uint16 sn, Uint16 data)
{
    const Uint32 SN_CR_TIMEOUT = 1000000U;
    Uint32 t = SN_CR_TIMEOUT;

    c2837x_w5300_write8(Sn_CR(sn), data);
    while (c2837x_w5300_read8(Sn_CR(sn)))
    {
        if (--t == 0) return -1;
    }
    return 0;
}

#if __TI_COMPILER_VERSION__ >= 15009000
    #pragma CODE_SECTION(c2837x_w5300_get_sn_tx_fsr, ".TI.ramfunc");
#else
    #pragma CODE_SECTION(c2837x_w5300_get_sn_tx_fsr, "ramfuncs");
#endif
Uint32 c2837x_w5300_get_sn_tx_fsr(Uint16 sn)
{
    Uint32 v1, v2;
    do {
        v1 = ((Uint32)c2837x_w5300_read16(Sn_TX_FSR(sn)) << 16) | c2837x_w5300_read16(Sn_TX_FSR2(sn));
        v2 = ((Uint32)c2837x_w5300_read16(Sn_TX_FSR(sn)) << 16) | c2837x_w5300_read16(Sn_TX_FSR2(sn));
    } while (v1 != v2);
    return v1;
}

#if __TI_COMPILER_VERSION__ >= 15009000
    #pragma CODE_SECTION(c2837x_w5300_get_sn_rx_rsr, ".TI.ramfunc");
#else
    #pragma CODE_SECTION(c2837x_w5300_get_sn_rx_rsr, "ramfuncs");
#endif
Uint32 c2837x_w5300_get_sn_rx_rsr(Uint16 sn)
{
    Uint32 v1, v2;
    do {
        v1 = ((Uint32)c2837x_w5300_read16(Sn_RX_RSR(sn)) << 16) | c2837x_w5300_read16(Sn_RX_RSR2(sn));
        v2 = ((Uint32)c2837x_w5300_read16(Sn_RX_RSR(sn)) << 16) | c2837x_w5300_read16(Sn_RX_RSR2(sn));
    } while (v1 != v2);
    return v1;
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
