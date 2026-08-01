#include "c2837x_block_project.h"

/*
 * This example assumes generated instances named current_loop and
 * voltage_loop. Device, clock, GPIO, EMIF, linker, and startup setup remains
 * the responsibility of the user's existing target project.
 */
static void UserHandlePlatformInitFailure(int16 platform_result)
{
    (void)platform_result;

    /* Replace with the target project's safe fault handling. */
    for (;;)
    {
    }
}

int main(void)
{
    int16 platform_result;

    /* Perform the existing target project's low-level setup before this. */
    platform_result = C2837xBlock_PlatformInit();
    if (platform_result < 0)
    {
        UserHandlePlatformInitFailure(platform_result);
        return 1;
    }

    C2837xBlock_Init(&g_current_loop);
    C2837xBlock_Init(&g_voltage_loop);

    for (;;)
    {
        C2837xBlock_Run(&g_current_loop);
        C2837xBlock_Run(&g_voltage_loop);

        /* Optional non-blocking diagnostics may inspect each instance here
         * with C2837xBlock_GetLastError(). */
    }
}
