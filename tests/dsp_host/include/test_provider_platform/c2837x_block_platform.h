#ifndef TEST_PROVIDER_C2837X_BLOCK_PLATFORM_H
#define TEST_PROVIDER_C2837X_BLOCK_PLATFORM_H

/*
 * Test-only seam for provider/Core binding fixtures.
 *
 * test_provider deliberately renders no W5300 or SCI transport. These
 * fixtures need only the generated instance Config time hook; formal
 * Platform transport compilation is covered by W5300/SCI/mixed projects.
 */

#include "c2837x_block.h"

Uint32 c2837x_block_time_us(void);

#endif /* TEST_PROVIDER_C2837X_BLOCK_PLATFORM_H */
