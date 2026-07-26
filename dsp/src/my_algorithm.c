/*
 * User algorithm: 3-input addition with saturation.
 * Phase 1 verification algorithm.
 */

#include "c2837x_block_algorithm.h"

int16_t C2837xBlock_OnSimStart(void)
{
    return 0;
}

int16_t C2837xBlock_OnStep(const C2837xBlock_InputData *input,
                           C2837xBlock_OutputData *output)
{
    int32_t tmp = (int32_t)input->a
                + (int32_t)input->b
                + (int32_t)input->c;

    if (tmp > 32767) {
        tmp = 32767;
    } else if (tmp < -32768) {
        tmp = -32768;
    }

    output->sum = (int16_t)tmp;
    return 0;
}

void C2837xBlock_OnSimStop(void)
{
    /* Nothing to clean up */
}
