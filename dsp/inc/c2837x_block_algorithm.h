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

extern C2837xBlock_InputData  c2837x_block_input;
extern C2837xBlock_OutputData c2837x_block_output;

/*
 * Called when SIM_START is received.
 * Return 0 on success, non-zero on failure.
 */
int C2837xBlock_OnSimStart(void);

/*
 * Called when INPUT_DATA is received and validated.
 * Input data is in c2837x_block_input.
 * Must write output to c2837x_block_output.
 * Return 0 on success, non-zero on failure.
 */
int C2837xBlock_OnStep(void);

/*
 * Called when SIM_STOP is received or connection is lost.
 */
void C2837xBlock_OnSimStop(void);

#endif /* C2837X_BLOCK_ALGORITHM_H */
