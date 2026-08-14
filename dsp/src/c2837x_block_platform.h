#ifndef C2837X_BLOCK_PLATFORM_H
#define C2837X_BLOCK_PLATFORM_H

#include "F28x_Project.h"

/* Current fixed C2837x target clock. Override only for matching hardware. */
#ifndef C2837X_BLOCK_CPU_CLOCK_MHZ
#define C2837X_BLOCK_CPU_CLOCK_MHZ  200u
#endif

/*
 * Stage 2 uses a project-level bring-up clock only when SCI is present.
 * The value is the TI LOSPCP encoding for SYSCLK / 14 on F2837xD.
 */
#define C2837X_BLOCK_SCI_LSPCLK_DIVISOR  14u
#define C2837X_BLOCK_SCI_LOSPCP_VALUE     7u

/* SCI-S2-03 owns the concrete descriptor fields. */
typedef struct C2837xBlock_SciDescriptor C2837xBlock_SciDescriptor;

typedef struct
{
    const C2837xBlock_SciDescriptor *items;
    Uint16 count;
} C2837xBlock_SciDescriptorCollection;

/*
 * Project-owned, immutable Platform contract.  The SCI collection is
 * intentionally opaque until SCI-S2-03 defines the hardware descriptor.
 */
typedef struct
{
    Uint16 use_w5300;
    C2837xBlock_SciDescriptorCollection sci_descriptors;
} C2837xBlock_PlatformConfig;

extern const C2837xBlock_PlatformConfig c2837x_block_platform_config;

/* Define C2837X_BLOCK_PLATFORM_CONFIG_EXTERN when the project owns it. */

/* Project-level SYSCLK/14 bring-up action; no read-back is performed. */
void c2837x_block_sci_lspclk_bringup(void);
int16 c2837x_block_sci_platform_init(
    const C2837xBlock_SciDescriptorCollection *descriptors);

int16 c2837x_block_timer2_init(void);
Uint32 c2837x_block_time_us(void);
Uint32 c2837x_block_platform_generation(void);

#endif /* C2837X_BLOCK_PLATFORM_H */
