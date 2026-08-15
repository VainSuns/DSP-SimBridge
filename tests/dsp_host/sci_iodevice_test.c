#include <assert.h>
#include <string.h>
#include "c2837x_block_sci.h"

volatile struct SCI_REGS SciaRegs;
volatile struct SCI_REGS ScibRegs;
volatile struct SCI_REGS ScicRegs;
volatile struct SCI_REGS ScidRegs;

static Uint16 gpio_write_calls;
static Uint16 last_gpio;
static Uint16 last_gpio_value;

void GPIO_WritePin(Uint16 gpio, Uint16 value)
{
    gpio_write_calls++;
    last_gpio = gpio;
    last_gpio_value = value;
}

static const C2837xBlock_SciDescriptor config_a =
{
    C2837X_BLOCK_SCI_MODULE_A,
    1u,
    {{9u, 6u}, C2837X_BLOCK_SCI_PIN_STANDARD,
     C2837X_BLOCK_SCI_QUALIFICATION_ASYNC},
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

static void reset_registers(void)
{
    memset((void *)&SciaRegs, 0, sizeof(SciaRegs));
    memset((void *)&ScibRegs, 0, sizeof(ScibRegs));
    memset((void *)&ScicRegs, 0, sizeof(ScicRegs));
    memset((void *)&ScidRegs, 0, sizeof(ScidRegs));
    gpio_write_calls = 0u;
    last_gpio = 0u;
    last_gpio_value = 0u;
}

static void start_listening(C2837xBlock_SciChannel *channel)
{
    assert(c2837x_block_sci_iodevice_ops.channel_init != 0);
    assert(c2837x_block_sci_iodevice_ops.open(channel) == 0);
    assert(c2837x_block_sci_iodevice_ops.get_connection_state(channel) ==
           C2837X_IODEVICE_CONNECTION_OPEN);
    assert(c2837x_block_sci_iodevice_ops.listen(channel) == 0);
    assert(c2837x_block_sci_iodevice_ops.get_connection_state(channel) ==
           C2837X_IODEVICE_CONNECTION_LISTENING);
}

static void test_logical_state_and_first_byte(void)
{
    C2837xBlock_SciChannel channel =
        C2837X_BLOCK_SCI_CHANNEL_INITIALIZER(&config_a);
    Uint16 words[2] = {0u, 0u};
    Uint16 probe_value;

    reset_registers();
    c2837x_block_sci_iodevice_ops.channel_init(&channel);
    assert(c2837x_block_sci_iodevice_ops.get_connection_state(&channel) ==
           C2837X_IODEVICE_CONNECTION_CLOSED);
    assert(channel.runtime.session_cleanup_done == 0u);
    assert(SciaRegs.SCIFFRX.bit.RXFIFORESET == 0u);

    start_listening(&channel);
    assert(channel.runtime.session_cleanup_done == 1u);

    SciaRegs.SCIRXBUF.all = 0x0012u;
    probe_value = SciaRegs.SCIRXBUF.all;
    SciaRegs.SCIFFRX.bit.RXFFST = 1u;
    assert(c2837x_block_sci_iodevice_ops.get_connection_state(&channel) ==
           C2837X_IODEVICE_CONNECTION_CONNECTED);
    assert(SciaRegs.SCIRXBUF.all == probe_value);
    assert(channel.runtime.rx_staging_valid == 0u);

    assert(c2837x_block_sci_iodevice_ops.receive(&channel, words, 2u) == 0);
    assert(channel.runtime.rx_staging_valid == 1u);
    assert(channel.runtime.rx_staging_octet == 0x12u);

    SciaRegs.SCIRXBUF.all = 0x0034u;
    SciaRegs.SCIFFRX.bit.RXFFST = 1u;
    assert(c2837x_block_sci_iodevice_ops.receive(&channel, words, 2u) == 2);
    assert(words[0] == 0x3412u);
    assert(channel.runtime.rx_staging_valid == 0u);
}

static void test_capacity_and_odd_staging(void)
{
    C2837xBlock_SciChannel channel =
        C2837X_BLOCK_SCI_CHANNEL_INITIALIZER(&config_a);
    Uint16 words[2] = {0u, 0u};

    reset_registers();
    c2837x_block_sci_iodevice_ops.channel_init(&channel);
    start_listening(&channel);
    SciaRegs.SCIRXBUF.all = 0x0056u;
    SciaRegs.SCIFFRX.bit.RXFFST = 1u;
    assert(c2837x_block_sci_iodevice_ops.get_connection_state(&channel) ==
           C2837X_IODEVICE_CONNECTION_CONNECTED);

    assert(c2837x_block_sci_iodevice_ops.receive(&channel, words, 1u) == 0);
    assert(channel.runtime.rx_staging_valid == 0u);
    assert(SciaRegs.SCIFFRX.bit.RXFFST == 1u);
    assert(c2837x_block_sci_iodevice_ops.receive(&channel, words, 3u) == 0);
    assert(channel.runtime.rx_staging_valid == 1u);

    SciaRegs.SCIRXBUF.all = 0x0078u;
    SciaRegs.SCIFFRX.bit.RXFFST = 1u;
    assert(c2837x_block_sci_iodevice_ops.receive(&channel, words, 3u) == 2);
    assert(words[0] == 0x7856u);
}

static void test_one_time_cleanup_and_close(void)
{
    C2837xBlock_SciChannel channel =
        C2837X_BLOCK_SCI_CHANNEL_INITIALIZER(&config_a);

    reset_registers();
    c2837x_block_sci_iodevice_ops.channel_init(&channel);
    start_listening(&channel);

    SciaRegs.SCIFFRX.bit.RXFIFORESET = 0u;
    SciaRegs.SCIFFTX.bit.TXFIFORESET = 0u;
    assert(c2837x_block_sci_iodevice_ops.get_connection_state(&channel) ==
           C2837X_IODEVICE_CONNECTION_LISTENING);
    assert(c2837x_block_sci_iodevice_ops.get_connection_state(&channel) ==
           C2837X_IODEVICE_CONNECTION_LISTENING);
    assert(SciaRegs.SCIFFRX.bit.RXFIFORESET == 0u);
    assert(SciaRegs.SCIFFTX.bit.TXFIFORESET == 0u);

    channel.runtime.rx_staging_octet = 0xAAu;
    channel.runtime.rx_staging_valid = 1u;
    channel.runtime.software_pending = 1u;
    channel.runtime.ctrl_tx_active = 1u;
    assert(c2837x_block_sci_iodevice_ops.close(&channel) > 0);
    assert(channel.runtime.connection_state ==
           C2837X_IODEVICE_CONNECTION_CLOSED);
    assert(channel.runtime.rx_staging_valid == 0u);
    assert(channel.runtime.software_pending == 0u);
    assert(channel.runtime.ctrl_tx_active == 0u);
    assert(channel.runtime.session_cleanup_done == 1u);
    assert(SciaRegs.SCIFFRX.bit.RXFIFORESET == 1u);
    assert(SciaRegs.SCIFFTX.bit.TXFIFORESET == 1u);
    assert(SciaRegs.SCIFFRX.bit.RXFFOVRCLR == 1u);
    assert(SciaRegs.SCICTL1.bit.SWRESET == 1u);
    assert(gpio_write_calls == 3u);
    assert(last_gpio == 30u && last_gpio_value == 0u);

    SciaRegs.SCIFFRX.bit.RXFFST = 0u;
    start_listening(&channel);
    SciaRegs.SCIFFRX.bit.RXFIFORESET = 0u;
    assert(c2837x_block_sci_iodevice_ops.get_connection_state(&channel) ==
           C2837X_IODEVICE_CONNECTION_LISTENING);
    assert(SciaRegs.SCIFFRX.bit.RXFIFORESET == 0u);
}

static void test_rx_error_is_finite(void)
{
    C2837xBlock_SciChannel channel =
        C2837X_BLOCK_SCI_CHANNEL_INITIALIZER(&config_a);
    Uint16 words[1] = {0u};

    reset_registers();
    c2837x_block_sci_iodevice_ops.channel_init(&channel);
    start_listening(&channel);
    SciaRegs.SCIRXST.all = 0x0080u;
    assert(SciaRegs.SCIRXST.bit.RXERROR == 1u);
    assert(c2837x_block_sci_iodevice_ops.get_connection_state(&channel) ==
           C2837X_IODEVICE_CONNECTION_ERROR);
    assert(channel.runtime.connection_state ==
           C2837X_IODEVICE_CONNECTION_CLOSED);
    assert(c2837x_block_sci_iodevice_ops.get_connection_state(&channel) ==
           C2837X_IODEVICE_CONNECTION_CLOSED);
    assert(c2837x_block_sci_iodevice_ops.close(&channel) > 0);

    reset_registers();
    c2837x_block_sci_iodevice_ops.channel_init(&channel);
    start_listening(&channel);
    SciaRegs.SCIFFRX.bit.RXFFST = 1u;
    assert(c2837x_block_sci_iodevice_ops.get_connection_state(&channel) ==
           C2837X_IODEVICE_CONNECTION_CONNECTED);
    SciaRegs.SCIFFRX.bit.RXFFOVF = 1u;
    assert(c2837x_block_sci_iodevice_ops.receive(&channel, words, 2u) < 0);
    assert(channel.runtime.connection_state ==
           C2837X_IODEVICE_CONNECTION_CLOSED);
    assert(c2837x_block_sci_iodevice_ops.close(&channel) > 0);
}

static void test_runtime_isolation_and_send_boundary(void)
{
    C2837xBlock_SciChannel channel_a =
        C2837X_BLOCK_SCI_CHANNEL_INITIALIZER(&config_a);
    C2837xBlock_SciChannel channel_b =
        C2837X_BLOCK_SCI_CHANNEL_INITIALIZER(&config_b);
    Uint16 words[1] = {0u};

    reset_registers();
    c2837x_block_sci_iodevice_ops.channel_init(&channel_a);
    c2837x_block_sci_iodevice_ops.channel_init(&channel_b);
    channel_b.runtime.rx_staging_octet = 0x55u;
    channel_b.runtime.rx_staging_valid = 1u;
    channel_b.runtime.software_pending = 1u;
    channel_b.runtime.ctrl_tx_active = 1u;
    channel_b.runtime.connection_state =
        C2837X_IODEVICE_CONNECTION_LISTENING;
    channel_b.runtime.session_cleanup_done = 0u;

    start_listening(&channel_a);
    SciaRegs.SCIFFRX.bit.RXFFST = 1u;
    assert(c2837x_block_sci_iodevice_ops.get_connection_state(&channel_a) ==
           C2837X_IODEVICE_CONNECTION_CONNECTED);
    assert(c2837x_block_sci_iodevice_ops.send(&channel_a, words, 2u) < 0);

    assert(channel_b.runtime.rx_staging_octet == 0x55u);
    assert(channel_b.runtime.rx_staging_valid == 1u);
    assert(channel_b.runtime.software_pending == 1u);
    assert(channel_b.runtime.ctrl_tx_active == 1u);
    assert(channel_b.runtime.connection_state ==
           C2837X_IODEVICE_CONNECTION_LISTENING);
    assert(channel_b.runtime.session_cleanup_done == 0u);
    assert(ScibRegs.SCIFFRX.bit.RXFIFORESET == 0u);
}

int main(void)
{
    test_logical_state_and_first_byte();
    test_capacity_and_odd_staging();
    test_one_time_cleanup_and_close();
    test_rx_error_is_finite();
    test_runtime_isolation_and_send_boundary();
    return 0;
}
