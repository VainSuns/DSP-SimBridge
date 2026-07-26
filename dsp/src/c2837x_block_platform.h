#ifndef C2837X_BLOCK_PLATFORM_H
#define C2837X_BLOCK_PLATFORM_H

#include "F28x_Project.h"

/* Current fixed C2837x target clock. Override only for matching hardware. */
#ifndef C2837X_BLOCK_CPU_CLOCK_MHZ
#define C2837X_BLOCK_CPU_CLOCK_MHZ  200u
#endif

int16 c2837x_block_timer2_init(void);
Uint32 c2837x_block_time_us(void);

#endif /* C2837X_BLOCK_PLATFORM_H */
