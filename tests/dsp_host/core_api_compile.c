#define C2837X_BLOCK_EXPECTED_CORE_API_VERSION 1u
#include "c2837x_block.h"

C2837xBlock *core_instance_pointer;
int16 (*platform_init_function)(void) = C2837xBlock_PlatformInit;
void (*instance_init_function)(C2837xBlock *) = C2837xBlock_Init;
void (*instance_run_function)(C2837xBlock *) = C2837xBlock_Run;
C2837xBlock_Error (*last_error_function)(const C2837xBlock *) =
    C2837xBlock_GetLastError;

_Static_assert(C2837X_BLOCK_ERROR_INTERNAL == 8,
               "C2837xBlock_Error values changed");
_Static_assert(C2837X_BLOCK_PLATFORM_OK == 0,
               "platform OK value changed");
_Static_assert(C2837X_BLOCK_PLATFORM_ERROR_TIMER_INIT == -1,
               "timer error value changed");
_Static_assert(C2837X_BLOCK_PLATFORM_ERROR_W5300_INIT == -2,
               "W5300 error value changed");
_Static_assert(C2837X_BLOCK_PLATFORM_ERROR_W5300_MEMORY == -3,
               "memory error value changed");
_Static_assert(C2837X_BLOCK_PLATFORM_ERROR_NETWORK_CONFIG == -4,
               "network error value changed");

int main(void)
{
    return (C2837X_BLOCK_CORE_API_VERSION == 1u) ? 0 : 1;
}
