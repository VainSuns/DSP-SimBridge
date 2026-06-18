#include "W5300_C2837x.h"


Uint16 g_w5300_fifo_swap = 0;

static void InitEmif1_5300(void)
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
            GPIO_SetupPinOptions(i, 0, 0x31); /* GPIO_ASYNC || GPIO_PULLUP */
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

void Reset_W5300(void)
{
    GPIO_WritePin(W5300_RESET_PIN, 1);
    DELAY_US(1000);
    GPIO_WritePin(W5300_RESET_PIN, 0);
    DELAY_US(20000);
    GPIO_WritePin(W5300_RESET_PIN, 1);
    DELAY_US(1000);
}

void Init_W5300(void)
{
    GPIO_SetupPinMux(W5300_RESET_PIN, GPIO_MUX_CPU1, 0);
    GPIO_SetupPinOptions(W5300_RESET_PIN, GPIO_OUTPUT, GPIO_PUSHPULL);

    InitEmif1_5300();

    GPIO_SetupPinMux(30, GPIO_MUX_CPU1, 0);
    GPIO_SetupPinOptions(30, GPIO_OUTPUT, GPIO_PUSHPULL);
    GPIO_WritePin(30, 1);

    Reset_W5300();
}

static inline Uint16 W5300_Swap16(Uint16 value)
{
    return (Uint16)((value << 8) | (value >> 8));
}

#if __TI_COMPILER_VERSION__ >= 15009000
    #pragma CODE_SECTION(W5300_Read16, ".TI.ramfunc");
#else
    #pragma CODE_SECTION(W5300_Read16, "ramfuncs");
#endif
Uint16 W5300_Read16(Uint32 addr)
{
    #if (__DEF_IINCHIP_ADDRESS_MODE__ == __DEF_IINCHIP_DIRECT_MODE__)
        return (*((volatile Uint16*)(addr)));
    #else
        volatile Uint16 data;
        *((volatile Uint16*)IDM_AR) = (uint16)addr;
        data = *((volatile Uint16*)IDM_DR);
        return data;
    #endif
}

#if __TI_COMPILER_VERSION__ >= 15009000
    #pragma CODE_SECTION(W5300_Write16, ".TI.ramfunc");
#else
    #pragma CODE_SECTION(W5300_Write16, "ramfuncs");
#endif
void W5300_Write16(Uint32 addr, Uint16 data)
{
    #if (__DEF_IINCHIP_ADDRESS_MODE__ == __DEF_IINCHIP_DIRECT_MODE__)
        (*((volatile Uint16*)(addr))) = data;
    #else
        *((volatile Uint16*)IDM_AR) = addr;
        *((volatile Uint16*)IDM_DR) = data;
    #endif
}

#if __TI_COMPILER_VERSION__ >= 15009000
    #pragma CODE_SECTION(SetSn_CR, ".TI.ramfunc");
#else
    #pragma CODE_SECTION(SetSn_CR, "ramfuncs");
#endif
int16 SetSn_CR(Uint16 sn, Uint16 data)
{
    const Uint32 SN_CR_TIMEOUT = 1000000U;
    Uint32 t = SN_CR_TIMEOUT;

    W5300_Write8(Sn_CR(sn), data);
    while (W5300_Read8(Sn_CR(sn)))
    {
        if (--t == 0) return -1;
    }
    return 0;
}

#if __TI_COMPILER_VERSION__ >= 15009000
    #pragma CODE_SECTION(GetSn_TX_FSR, ".TI.ramfunc");
#else
    #pragma CODE_SECTION(GetSn_TX_FSR, "ramfuncs");
#endif
Uint32 GetSn_TX_FSR(Uint16 sn)
{
   Uint32 v1, v2;
   do {
      v1 = ((Uint32)W5300_Read16(Sn_TX_FSR(sn)) << 16) | W5300_Read16(Sn_TX_FSR2(sn));
      v2 = ((Uint32)W5300_Read16(Sn_TX_FSR(sn)) << 16) | W5300_Read16(Sn_TX_FSR2(sn));
   } while (v1 != v2);
   return v1;
}

#if __TI_COMPILER_VERSION__ >= 15009000
    #pragma CODE_SECTION(GetSn_RX_RSR, ".TI.ramfunc");
#else
    #pragma CODE_SECTION(GetSn_RX_RSR, "ramfuncs");
#endif
Uint32 GetSn_RX_RSR(Uint16 sn)
{
   Uint32 v1, v2;
   do {
      v1 = ((Uint32)W5300_Read16(Sn_RX_RSR(sn)) << 16) | W5300_Read16(Sn_RX_RSR2(sn));
      v2 = ((Uint32)W5300_Read16(Sn_RX_RSR(sn)) << 16) | W5300_Read16(Sn_RX_RSR2(sn));
   } while (v1 != v2);
   return v1;
}

#if __TI_COMPILER_VERSION__ >= 15009000
    #pragma CODE_SECTION(W5300_WriteStream, ".TI.ramfunc");
#else
    #pragma CODE_SECTION(W5300_WriteStream, "ramfuncs");
#endif
Uint32 W5300_WriteStream(Uint16 s, const Uint16* dspData, Uint32 wireByteCount)
{
    Uint32 i;
    const Uint32 wordCount = (wireByteCount + 1U) >> 1;

    if (g_w5300_fifo_swap)
    {
        for (i = 0; i < wordCount; i++)
        {
            Uint16 word;
            Uint32 bi = i << 1;
            if ((bi + 1U) < wireByteCount)
                word = (Uint16)(((dspData[i] & 0xFFU) << 8) | ((dspData[i] >> 8) & 0xFFU));
            else
                word = (Uint16)((dspData[i] & 0xFFU) << 8);
            W5300_Write16(Sn_TX_FIFOR(s), W5300_Swap16(word));
        }
    }
    else
    {
        for (i = 0; i < wordCount; i++)
        {
            Uint16 word;
            Uint32 bi = i << 1;
            if ((bi + 1U) < wireByteCount)
                word = (Uint16)(((dspData[i] & 0xFFU) << 8) | ((dspData[i] >> 8) & 0xFFU));
            else
                word = (Uint16)((dspData[i] & 0xFFU) << 8);
            W5300_Write16(Sn_TX_FIFOR(s), word);
        }
    }
    return wireByteCount;
}

#if __TI_COMPILER_VERSION__ >= 15009000
    #pragma CODE_SECTION(W5300_ReadStream, ".TI.ramfunc");
#else
    #pragma CODE_SECTION(W5300_ReadStream, "ramfuncs");
#endif
Uint32 W5300_ReadStream(Uint16 s, Uint16* dspData, Uint32 wireByteCount)
{
    Uint32 i;
    const Uint32 wordCount = (wireByteCount + 1U) >> 1;

    if (g_w5300_fifo_swap)
    {
        for (i = 0; i < wordCount; i++)
        {
            Uint16 word = W5300_Swap16(W5300_Read16(Sn_RX_FIFOR(s)));
            dspData[i] = ((word >> 8) & 0xFFU) | ((word & 0xFFU) << 8);
        }
    }
    else
    {
        for (i = 0; i < wordCount; i++)
        {
            Uint16 word = W5300_Read16(Sn_RX_FIFOR(s));
            dspData[i] = ((word >> 8) & 0xFFU) | ((word & 0xFFU) << 8);
        }
    }
    return wireByteCount;
}

//
// End of file
//
