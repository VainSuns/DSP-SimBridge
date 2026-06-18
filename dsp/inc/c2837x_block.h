#ifndef C2837X_BLOCK_H
#define C2837X_BLOCK_H

/*
 * C2837xBlock DSP communication library core API.
 * Implements the non-blocking state machine for Simulink-DSP communication.
 */

#include "F28x_Project.h"

/*
 * Initialize the communication library.
 * - Initializes W5300 hardware
 * - Configures network parameters
 * - Opens Socket 0 as TCP server
 * - Enters LISTEN state
 *
 * Returns 0 on success, negative on failure.
 */
int16 C2837xBlock_Init(void);

/*
 * Non-blocking state machine tick.
 * Must be called repeatedly from the main loop.
 * Processes at most one event per call, then returns.
 */
void C2837xBlock_Run(void);

#endif /* C2837X_BLOCK_H */
