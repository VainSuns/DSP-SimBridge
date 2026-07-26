#include "c2837x_block_platform.h"

#if (C2837X_BLOCK_CPU_CLOCK_MHZ < 1u) || \
    (C2837X_BLOCK_CPU_CLOCK_MHZ > 65536u)
#error "C2837X_BLOCK_CPU_CLOCK_MHZ cannot produce a 1 MHz CPU Timer 2 clock"
#endif

int16 c2837x_block_timer2_init(void)
{
    const Uint16 prescaler = (Uint16)(C2837X_BLOCK_CPU_CLOCK_MHZ - 1u);

    CpuTimer2Regs.TCR.bit.TSS = 1u;
    CpuTimer2Regs.PRD.all = 0xFFFFFFFFu;
    CpuTimer2Regs.TPR.bit.TDDR = (Uint16)(prescaler & 0x00FFu);
    CpuTimer2Regs.TPRH.bit.TDDRH = (Uint16)(prescaler >> 8);
    CpuTimer2Regs.TCR.bit.TIE = 0u;
    CpuTimer2Regs.TCR.bit.FREE = 1u;
    CpuTimer2Regs.TCR.bit.SOFT = 0u;
    CpuTimer2Regs.TCR.bit.TRB = 1u;
    CpuTimer2Regs.TCR.bit.TIF = 1u;
    CpuTimer2Regs.TCR.bit.TSS = 0u;

    if ((CpuTimer2Regs.PRD.all != 0xFFFFFFFFu) ||
        (CpuTimer2Regs.TPR.bit.TDDR != (prescaler & 0x00FFu)) ||
        (CpuTimer2Regs.TPRH.bit.TDDRH != (prescaler >> 8)) ||
        (CpuTimer2Regs.TCR.bit.TIE != 0u) ||
        (CpuTimer2Regs.TCR.bit.FREE != 1u) ||
        (CpuTimer2Regs.TCR.bit.TSS != 0u))
    {
        return -1;
    }

    return 0;
}

Uint32 c2837x_block_time_us(void)
{
    return ~CpuTimer2Regs.TIM.all;
}
