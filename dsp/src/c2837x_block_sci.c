#include "c2837x_block_sci.h"

static Uint16 c2837x_block_sci_ctrl_rx_level(
    C2837xBlock_SciCtrlTxActiveLevel active_level)
{
    return (active_level == C2837X_BLOCK_SCI_CTRL_TX_ACTIVE_HIGH) ? 0u : 1u;
}

void c2837x_block_sci_channel_init(C2837xBlock_SciChannel *channel)
{
    const C2837xBlock_SciDescriptor *config;

    if (channel == 0)
        return;

    config = channel->hardware_config;
    channel->runtime.rx_staging_octet = 0u;
    channel->runtime.rx_staging_valid = 0u;
    channel->runtime.software_pending = 0u;
    channel->runtime.ctrl_tx_active = 0u;

    /* PlatformInit already selected GPIO mode and pad configuration. */
    if ((config != 0) &&
        (config->ctrl.gpio != C2837X_BLOCK_SCI_NO_CTRL_GPIO) &&
        (config->ctrl.gpio <= C2837X_BLOCK_SCI_MAX_GPIO) &&
        ((Uint32)config->ctrl.tx_active_level <=
         (Uint32)C2837X_BLOCK_SCI_CTRL_TX_ACTIVE_HIGH))
    {
        GPIO_WritePin(config->ctrl.gpio,
                      c2837x_block_sci_ctrl_rx_level(
                          config->ctrl.tx_active_level));
    }
}
