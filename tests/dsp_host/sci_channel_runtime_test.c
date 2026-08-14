#include <assert.h>
#include "c2837x_block_sci.h"

static Uint16 write_calls;
static Uint16 last_gpio;
static Uint16 last_value;

void GPIO_WritePin(Uint16 gpio, Uint16 value)
{
    write_calls++;
    last_gpio = gpio;
    last_value = value;
}

static const C2837xBlock_SciDescriptor config_a =
{
    C2837X_BLOCK_SCI_MODULE_A,
    1u,
    {{9u, 6u}, C2837X_BLOCK_SCI_PIN_STANDARD,
     C2837X_BLOCK_SCI_QUALIFICATION_SYNC},
    {{8u, 6u}, C2837X_BLOCK_SCI_PIN_STANDARD},
    {30u, C2837X_BLOCK_SCI_PIN_STANDARD,
     C2837X_BLOCK_SCI_CTRL_TX_ACTIVE_HIGH}
};

static const C2837xBlock_SciDescriptor config_b =
{
    C2837X_BLOCK_SCI_MODULE_B,
    1u,
    {{11u, 2u}, C2837X_BLOCK_SCI_PIN_STANDARD,
     C2837X_BLOCK_SCI_QUALIFICATION_ASYNC},
    {{10u, 6u}, C2837X_BLOCK_SCI_PIN_STANDARD},
    {C2837X_BLOCK_SCI_NO_CTRL_GPIO, C2837X_BLOCK_SCI_PIN_STANDARD,
     C2837X_BLOCK_SCI_CTRL_TX_ACTIVE_LOW}
};

int main(void)
{
    C2837xBlock_SciChannel channel_a =
        C2837X_BLOCK_SCI_CHANNEL_INITIALIZER(&config_a);
    C2837xBlock_SciChannel channel_b =
        C2837X_BLOCK_SCI_CHANNEL_INITIALIZER(&config_b);

    channel_a.runtime.rx_staging_octet = 0x00AAu;
    channel_a.runtime.rx_staging_valid = 1u;
    channel_a.runtime.software_pending = 1u;
    channel_a.runtime.ctrl_tx_active = 1u;
    channel_b.runtime.rx_staging_octet = 0x0055u;
    channel_b.runtime.rx_staging_valid = 1u;
    channel_b.runtime.software_pending = 1u;
    channel_b.runtime.ctrl_tx_active = 1u;

    c2837x_block_sci_channel_init(&channel_a);
    assert(channel_a.runtime.rx_staging_octet == 0u);
    assert(channel_a.runtime.rx_staging_valid == 0u);
    assert(channel_a.runtime.software_pending == 0u);
    assert(channel_a.runtime.ctrl_tx_active == 0u);
    assert(channel_b.runtime.rx_staging_octet == 0x0055u);
    assert(channel_b.runtime.rx_staging_valid == 1u);
    assert(channel_b.runtime.software_pending == 1u);
    assert(channel_b.runtime.ctrl_tx_active == 1u);
    assert(write_calls == 1u);
    assert(last_gpio == 30u && last_value == 0u);

    c2837x_block_sci_channel_init(&channel_b);
    assert(channel_b.runtime.rx_staging_octet == 0u);
    assert(channel_b.runtime.rx_staging_valid == 0u);
    assert(channel_b.runtime.software_pending == 0u);
    assert(channel_b.runtime.ctrl_tx_active == 0u);
    assert(write_calls == 1u);
    return 0;
}
