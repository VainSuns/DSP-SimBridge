#ifndef C2837X_BLOCK_PLATFORM_H
#define C2837X_BLOCK_PLATFORM_H

#include "F28x_Project.h"
#include "c2837x_block_project.h"

#if !defined(C2837X_BLOCK_PLATFORM_HAS_W5300) || \
    !defined(C2837X_BLOCK_PLATFORM_HAS_SCI)
#error "Project transport facts are required by the Platform contract"
#endif

#if !C2837X_BLOCK_PLATFORM_HAS_W5300 && !C2837X_BLOCK_PLATFORM_HAS_SCI
#error "A DSP project must select at least one transport"
#endif

#if C2837X_BLOCK_PLATFORM_HAS_SCI
#include "c2837x_block_sci.h"
#endif

/* Current fixed C2837x target clock. Override only for matching hardware. */
#ifndef C2837X_BLOCK_CPU_CLOCK_MHZ
#define C2837X_BLOCK_CPU_CLOCK_MHZ  200u
#endif

#if C2837X_BLOCK_PLATFORM_HAS_SCI
/*
 * DSP-SimBridge uses one fixed project-level SCI clock when SCI is present.
 * The value is the TI LOSPCP/LSPCLKDIV encoding for SYSCLK / 4 on F2837xD.
 */
#define C2837X_BLOCK_SCI_LSPCLK_DIVISOR  4u
#define C2837X_BLOCK_SCI_LOSPCP_VALUE     2u
#endif

/*
 * Project-owned, immutable Platform contract.  The SCI collection contains
 * only the descriptors used by this project.
 */
typedef struct
{
#if C2837X_BLOCK_PLATFORM_HAS_W5300
    Uint16 use_w5300;
#endif
#if C2837X_BLOCK_PLATFORM_HAS_SCI
    C2837xBlock_SciDescriptorCollection sci_descriptors;
#endif
} C2837xBlock_PlatformConfig;

extern const C2837xBlock_PlatformConfig c2837x_block_platform_config;

/* Define C2837X_BLOCK_PLATFORM_CONFIG_EXTERN when the project owns it. */

#if C2837X_BLOCK_PLATFORM_HAS_SCI
/* Project-level SYSCLK/4 action; no read-back is performed. */
void c2837x_block_sci_lspclk_bringup(void);
int16 c2837x_block_sci_platform_init(
    const C2837xBlock_SciDescriptorCollection *descriptors);
#endif

int16 c2837x_block_timer2_init(void);
Uint32 c2837x_block_time_us(void);
Uint32 c2837x_block_platform_generation(void);

#endif /* C2837X_BLOCK_PLATFORM_H */
