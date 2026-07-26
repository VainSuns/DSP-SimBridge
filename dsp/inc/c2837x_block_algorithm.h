#ifndef C2837X_BLOCK_ALGORITHM_H
#define C2837X_BLOCK_ALGORITHM_H

/*
 * User algorithm interface for C2837xBlock.
 * Phase 1: 3x int16 input, 1x int16 output (addition with saturation).
 */

#include <stdint.h>

typedef struct {
    int16_t a;
    int16_t b;
    int16_t c;
} C2837xBlock_InputData;

typedef struct {
    int16_t sum;
} C2837xBlock_OutputData;

/*
 * Called when SIM_START is received.
 * Return 0 on success, non-zero on failure.
 */
int16_t C2837xBlock_OnSimStart(void);

/*
 * Called when INPUT_DATA is received and validated.
 * Input is read-only and output belongs to this sample instance.
 * Return 0 on success, non-zero on failure.
 */
int16_t C2837xBlock_OnStep(const C2837xBlock_InputData *input,
                           C2837xBlock_OutputData *output);

/*
 * Called when SIM_STOP is received or connection is lost.
 */
void C2837xBlock_OnSimStop(void);

#endif /* C2837X_BLOCK_ALGORITHM_H */
