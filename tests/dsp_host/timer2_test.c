#include <assert.h>
#include <string.h>
#include "c2837x_block_platform.h"

volatile struct CPUTIMER_REGS CpuTimer2Regs;

int main(void)
{
    Uint32 start_us;
    Uint32 now_us;

    memset((void*)&CpuTimer2Regs, 0, sizeof(CpuTimer2Regs));
    assert(c2837x_block_timer2_init() == 0);
    assert(CpuTimer2Regs.PRD.all == 0xFFFFFFFFu);
    assert(CpuTimer2Regs.TPR.bit.TDDR == 199u);
    assert(CpuTimer2Regs.TPRH.bit.TDDRH == 0u);
    assert(CpuTimer2Regs.TCR.bit.TIE == 0u);
    assert(CpuTimer2Regs.TCR.bit.FREE == 1u);
    assert(CpuTimer2Regs.TCR.bit.TSS == 0u);

    CpuTimer2Regs.TIM.all = ~((Uint32)10u);
    assert(c2837x_block_time_us() == 10u);
    CpuTimer2Regs.TIM.all = ~((Uint32)25u);
    assert(c2837x_block_time_us() == 25u);

    start_us = 0xFFFFFFF0u;
    now_us = 0x00000010u;
    assert((Uint32)(now_us - start_us) == 32u);
    return 0;
}
