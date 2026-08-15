#ifndef C2837X_BLOCK_PROJECT_H
#define C2837X_BLOCK_PROJECT_H

/*
 * Host-fixture fallback for the project header.
 *
 * Generated DSP trees replace this file with the project-owned header,
 * which exports the actual transport facts.  The repository fixture keeps
 * both transport implementations enabled so the existing platform host
 * tests can compile the common source directly.
 */

#include "c2837x_block.h"

#ifndef C2837X_BLOCK_PLATFORM_HAS_W5300
#define C2837X_BLOCK_PLATFORM_HAS_W5300  1u
#endif
#ifndef C2837X_BLOCK_PLATFORM_HAS_SCI
#define C2837X_BLOCK_PLATFORM_HAS_SCI    1u
#endif

#endif /* C2837X_BLOCK_PROJECT_H */
