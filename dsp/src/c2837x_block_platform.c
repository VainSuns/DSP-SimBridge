#include "c2837x_block.h"
#include "c2837x_block_platform.h"
#include "c2837x_w5300_hal.h"

#define C2837X_W5300_MODE_VALUE       0xB800u
#define C2837X_W5300_ID_VALUE         0x5300u
#define C2837X_W5300_MEMORY_PAIR      \
    ((Uint16)((C2837X_W5300_SOCKET_MEMORY_KB << 8) | \
              C2837X_W5300_SOCKET_MEMORY_KB))
#define C2837X_W5300_MEMORY_TYPE      0x00FFu

static Uint32 platform_generation;

Uint32 c2837x_block_platform_generation(void)
{
    return platform_generation;
}

static int16 c2837x_block_w5300_sockets_are_closed(void)
{
    Uint16 sn;

    for (sn = 0u; sn < C2837X_W5300_MAX_SOCK_NUM; sn++)
    {
        if (c2837x_w5300_get_sn_ssr(sn) != SOCK_CLOSED)
            return -1;
    }

    return 0;
}

static int16 c2837x_block_w5300_initialize(void)
{
    Uint16 mode;

    if (c2837x_w5300_init() != 0)
        return -1;
    if (c2837x_w5300_read16(IDR) != C2837X_W5300_ID_VALUE)
        return -1;

    c2837x_w5300_write16(MR, C2837X_W5300_MODE_VALUE);
    mode = c2837x_w5300_read16(MR);
    c2837x_w5300_fifo_swap = (mode & MR_FS) ? 1u : 0u;
    c2837x_w5300_write16(RTR, 2000u);
    c2837x_w5300_write16(RCR, 8u);

    return c2837x_block_w5300_sockets_are_closed();
}

static int16 c2837x_block_w5300_configure_memory(void)
{
    static const Uint32 tx_registers[4] = {TMS01R, TMS23R, TMS45R, TMS67R};
    static const Uint32 rx_registers[4] = {RMS01R, RMS23R, RMS45R, RMS67R};
    Uint16 i;

    for (i = 0u; i < 4u; i++)
    {
        c2837x_w5300_write16(tx_registers[i], C2837X_W5300_MEMORY_PAIR);
        c2837x_w5300_write16(rx_registers[i], C2837X_W5300_MEMORY_PAIR);
    }
    c2837x_w5300_write16(MTYPER, C2837X_W5300_MEMORY_TYPE);

    for (i = 0u; i < 4u; i++)
    {
        if ((c2837x_w5300_read16(tx_registers[i]) != C2837X_W5300_MEMORY_PAIR) ||
            (c2837x_w5300_read16(rx_registers[i]) != C2837X_W5300_MEMORY_PAIR))
        {
            return -1;
        }
    }

    return (c2837x_w5300_read16(MTYPER) == C2837X_W5300_MEMORY_TYPE) ? 0 : -1;
}

static int16 c2837x_block_w5300_configure_network(void)
{
    const Uint16 mac01 =
        (Uint16)((c2837x_w5300_project_config.mac[0] << 8) |
                 c2837x_w5300_project_config.mac[1]);
    const Uint16 mac23 =
        (Uint16)((c2837x_w5300_project_config.mac[2] << 8) |
                 c2837x_w5300_project_config.mac[3]);
    const Uint16 mac45 =
        (Uint16)((c2837x_w5300_project_config.mac[4] << 8) |
                 c2837x_w5300_project_config.mac[5]);

    c2837x_w5300_set_shar(mac01, mac23, mac45);
    c2837x_w5300_set_gar(c2837x_w5300_project_config.gateway);
    c2837x_w5300_set_subr(c2837x_w5300_project_config.subnet);
    c2837x_w5300_set_sipr(c2837x_w5300_project_config.ip_address);

    if ((c2837x_w5300_read16(SHAR0) != mac01) ||
        (c2837x_w5300_read16(SHAR2) != mac23) ||
        (c2837x_w5300_read16(SHAR4) != mac45) ||
        (c2837x_w5300_read16(GAR0) != (Uint16)(c2837x_w5300_project_config.gateway >> 16)) ||
        (c2837x_w5300_read16(GAR2) != (Uint16)c2837x_w5300_project_config.gateway) ||
        (c2837x_w5300_read16(SUBR0) != (Uint16)(c2837x_w5300_project_config.subnet >> 16)) ||
        (c2837x_w5300_read16(SUBR2) != (Uint16)c2837x_w5300_project_config.subnet) ||
        (c2837x_w5300_read16(SIPR0) != (Uint16)(c2837x_w5300_project_config.ip_address >> 16)) ||
        (c2837x_w5300_read16(SIPR2) != (Uint16)c2837x_w5300_project_config.ip_address))
    {
        return -1;
    }

    return 0;
}

int16 C2837xBlock_PlatformInit(void)
{
    if (c2837x_block_timer2_init() != 0)
        return (int16)C2837X_BLOCK_PLATFORM_ERROR_TIMER_INIT;

    if (c2837x_block_w5300_initialize() != 0)
        return (int16)C2837X_BLOCK_PLATFORM_ERROR_W5300_INIT;

    if (c2837x_block_w5300_configure_memory() != 0)
        return (int16)C2837X_BLOCK_PLATFORM_ERROR_W5300_MEMORY;

    if (c2837x_block_w5300_configure_network() != 0)
        return (int16)C2837X_BLOCK_PLATFORM_ERROR_NETWORK_CONFIG;

    platform_generation++;
    if (platform_generation == 0u)
        platform_generation = 1u;

    return (int16)C2837X_BLOCK_PLATFORM_OK;
}
