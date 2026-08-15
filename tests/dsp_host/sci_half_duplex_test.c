#include <assert.h>
#include <string.h>
#include "c2837x_block_sci.h"

volatile struct SCI_REGS SciaRegs;
volatile struct SCI_REGS ScibRegs;
volatile struct SCI_REGS ScicRegs;
volatile struct SCI_REGS ScidRegs;

#define GPIO_LOG_CAPACITY 16u

static Uint16 gpio_write_calls;
static Uint16 gpio_pins[GPIO_LOG_CAPACITY];
static Uint16 gpio_values[GPIO_LOG_CAPACITY];

void GPIO_WritePin(Uint16 gpio, Uint16 value)
{
    if (gpio_write_calls < GPIO_LOG_CAPACITY)
    {
        gpio_pins[gpio_write_calls] = gpio;
        gpio_values[gpio_write_calls] = value;
    }
    gpio_write_calls++;
}

static const C2837xBlock_SciDescriptor config_half_high =
{
    C2837X_BLOCK_SCI_MODULE_A,
    1u,
    {{9u, 6u}, C2837X_BLOCK_SCI_PIN_STANDARD,
     C2837X_BLOCK_SCI_QUALIFICATION_ASYNC},
    {{8u, 6u}, C2837X_BLOCK_SCI_PIN_STANDARD},
    {30u, C2837X_BLOCK_SCI_PIN_STANDARD,
     C2837X_BLOCK_SCI_CTRL_TX_ACTIVE_HIGH}
};

static const C2837xBlock_SciDescriptor config_half_low =
{
    C2837X_BLOCK_SCI_MODULE_B,
    1u,
    {{11u, 2u}, C2837X_BLOCK_SCI_PIN_STANDARD,
     C2837X_BLOCK_SCI_QUALIFICATION_ASYNC},
    {{10u, 6u}, C2837X_BLOCK_SCI_PIN_STANDARD},
    {31u, C2837X_BLOCK_SCI_PIN_STANDARD,
     C2837X_BLOCK_SCI_CTRL_TX_ACTIVE_LOW}
};

static const C2837xBlock_SciDescriptor config_full_duplex =
{
    C2837X_BLOCK_SCI_MODULE_C,
    1u,
    {{13u, 2u}, C2837X_BLOCK_SCI_PIN_STANDARD,
     C2837X_BLOCK_SCI_QUALIFICATION_ASYNC},
    {{12u, 6u}, C2837X_BLOCK_SCI_PIN_STANDARD},
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
    memset(gpio_pins, 0, sizeof(gpio_pins));
    memset(gpio_values, 0, sizeof(gpio_values));
}

static void clear_gpio_log(void)
{
    gpio_write_calls = 0u;
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

static void connect_channel(C2837xBlock_SciChannel *channel,
                            volatile struct SCI_REGS *sci)
{
    start_listening(channel);
    sci->SCIFFRX.bit.RXFFST = 1u;
    assert(c2837x_block_sci_iodevice_ops.get_connection_state(channel) ==
           C2837X_IODEVICE_CONNECTION_CONNECTED);
}

static void test_ctrl_none_regression(void)
{
    C2837xBlock_SciChannel channel =
        C2837X_BLOCK_SCI_CHANNEL_INITIALIZER(&config_full_duplex);
    Uint16 word = 0x3412u;

    reset_registers();
    c2837x_block_sci_iodevice_ops.channel_init(&channel);
    connect_channel(&channel, &ScicRegs);
    clear_gpio_log();

    ScicRegs.SCIFFTX.bit.TXFFST = 15u;
    ScicRegs.SCICTL2.bit.TXEMPTY = 0u;
    ScicRegs.SCITXBUF.all = 0x00AAu;
    assert(c2837x_block_sci_iodevice_ops.send(&channel, &word, 2u) == 0);
    assert(channel.runtime.ctrl_tx_active == 0u);
    assert(channel.runtime.tx_pending_queued_octets == 1u);
    assert(ScicRegs.SCITXBUF.all == 0x12u);
    assert(gpio_write_calls == 0u);

    ScicRegs.SCIFFTX.bit.TXFFST = 0u;
    ScicRegs.SCICTL2.bit.TXEMPTY = 1u;
    assert(c2837x_block_sci_iodevice_ops.send(&channel, &word, 2u) == 0);
    assert(channel.runtime.tx_pending_queued_octets == 2u);
    assert(c2837x_block_sci_iodevice_ops.send(&channel, &word, 2u) == 2);
    assert(channel.runtime.software_pending == 0u);
    assert(channel.runtime.ctrl_tx_active == 0u);
    assert(gpio_write_calls == 0u);
}

static void test_half_duplex_start_and_progression(void)
{
    C2837xBlock_SciChannel channel =
        C2837X_BLOCK_SCI_CHANNEL_INITIALIZER(&config_half_high);
    Uint16 words[2] = {0x3412u, 0x7856u};

    reset_registers();
    c2837x_block_sci_iodevice_ops.channel_init(&channel);
    connect_channel(&channel, &SciaRegs);
    clear_gpio_log();
    SciaRegs.SCITXBUF.all = 0x00AAu;

    assert(c2837x_block_sci_iodevice_ops.send(&channel, words, 4u) == 0);
    assert(channel.runtime.software_pending == 1u);
    assert(channel.runtime.tx_pending_data_words == words);
    assert(channel.runtime.tx_pending_total_octets == 4u);
    assert(channel.runtime.tx_pending_queued_octets == 0u);
    assert(channel.runtime.ctrl_tx_active == 1u);
    assert(gpio_write_calls == 1u);
    assert(gpio_pins[0] == 30u && gpio_values[0] == 1u);
    assert(SciaRegs.SCITXBUF.all == 0x00AAu);

    SciaRegs.SCIFFTX.bit.TXFFST = 15u;
    assert(c2837x_block_sci_iodevice_ops.send(&channel, words, 4u) == 0);
    assert(channel.runtime.tx_pending_queued_octets == 1u);
    assert(channel.runtime.ctrl_tx_active == 1u);
    assert(gpio_write_calls == 1u);
    assert(SciaRegs.SCITXBUF.all == 0x12u);
}

static void test_physical_completion_switches_to_rx_first(void)
{
    C2837xBlock_SciChannel channel =
        C2837X_BLOCK_SCI_CHANNEL_INITIALIZER(&config_half_high);
    Uint16 words[2] = {0x3412u, 0x7856u};

    reset_registers();
    c2837x_block_sci_iodevice_ops.channel_init(&channel);
    connect_channel(&channel, &SciaRegs);
    clear_gpio_log();

    SciaRegs.SCIFFTX.bit.TXFFST = 0u;
    SciaRegs.SCICTL2.bit.TXEMPTY = 0u;
    assert(c2837x_block_sci_iodevice_ops.send(&channel, words, 4u) == 0);
    assert(channel.runtime.ctrl_tx_active == 1u);
    assert(gpio_write_calls == 1u);

    SciaRegs.SCIFFTX.bit.TXFFST = 0u;
    assert(c2837x_block_sci_iodevice_ops.send(&channel, words, 4u) == 0);
    assert(channel.runtime.tx_pending_queued_octets == 4u);
    assert(channel.runtime.ctrl_tx_active == 1u);

    SciaRegs.SCIFFTX.bit.TXFFST = 1u;
    SciaRegs.SCICTL2.bit.TXEMPTY = 1u;
    assert(c2837x_block_sci_iodevice_ops.send(&channel, words, 4u) == 0);
    assert(channel.runtime.ctrl_tx_active == 1u);
    assert(channel.runtime.software_pending == 1u);

    SciaRegs.SCIFFTX.bit.TXFFST = 0u;
    SciaRegs.SCICTL2.bit.TXEMPTY = 0u;
    assert(c2837x_block_sci_iodevice_ops.send(&channel, words, 4u) == 0);
    assert(channel.runtime.ctrl_tx_active == 1u);

    SciaRegs.SCICTL2.bit.TXEMPTY = 1u;
    assert(c2837x_block_sci_iodevice_ops.send(&channel, words, 4u) == 4);
    assert(gpio_write_calls == 2u);
    assert(gpio_pins[1] == 30u && gpio_values[1] == 0u);
    assert(channel.runtime.ctrl_tx_active == 0u);
    assert(channel.runtime.software_pending == 0u);
    assert(channel.runtime.tx_pending_data_words == 0);
    assert(channel.runtime.tx_pending_total_octets == 0u);
    assert(channel.runtime.tx_pending_queued_octets == 0u);
}

static void test_polarity_low(void)
{
    C2837xBlock_SciChannel channel =
        C2837X_BLOCK_SCI_CHANNEL_INITIALIZER(&config_half_low);
    Uint16 word = 0x7856u;

    reset_registers();
    c2837x_block_sci_iodevice_ops.channel_init(&channel);
    connect_channel(&channel, &ScibRegs);
    clear_gpio_log();

    ScibRegs.SCIFFTX.bit.TXFFST = 0u;
    ScibRegs.SCICTL2.bit.TXEMPTY = 0u;
    assert(c2837x_block_sci_iodevice_ops.send(&channel, &word, 2u) == 0);
    assert(gpio_write_calls == 1u);
    assert(gpio_pins[0] == 31u && gpio_values[0] == 0u);

    ScibRegs.SCICTL2.bit.TXEMPTY = 1u;
    assert(c2837x_block_sci_iodevice_ops.send(&channel, &word, 2u) == 0);
    ScibRegs.SCIFFTX.bit.TXFFST = 0u;
    assert(c2837x_block_sci_iodevice_ops.send(&channel, &word, 2u) == 2);
    assert(gpio_write_calls == 2u);
    assert(gpio_pins[1] == 31u && gpio_values[1] == 1u);
    assert(channel.runtime.ctrl_tx_active == 0u);
}

static void test_receive_while_tx_active_is_error(void)
{
    C2837xBlock_SciChannel channel =
        C2837X_BLOCK_SCI_CHANNEL_INITIALIZER(&config_half_high);
    Uint16 tx_word = 0x3412u;
    Uint16 rx_word = 0xA5A5u;

    reset_registers();
    c2837x_block_sci_iodevice_ops.channel_init(&channel);
    connect_channel(&channel, &SciaRegs);
    clear_gpio_log();

    assert(c2837x_block_sci_iodevice_ops.send(&channel, &tx_word, 2u) == 0);
    SciaRegs.SCIRXBUF.all = 0x005Au;
    SciaRegs.SCIFFRX.bit.RXFFST = 1u;
    assert(c2837x_block_sci_iodevice_ops.receive(&channel, &rx_word, 2u) <
           0);
    assert(SciaRegs.SCIRXBUF.all == 0x005Au);
    assert(rx_word == 0xA5A5u);
    assert(channel.runtime.connection_state ==
           C2837X_IODEVICE_CONNECTION_CLOSED);
    assert(channel.runtime.ctrl_tx_active == 0u);
    assert(channel.runtime.software_pending == 0u);
    assert(channel.runtime.rx_staging_valid == 0u);
    assert(SciaRegs.SCIFFTX.bit.TXFIFORESET == 1u);
    assert(gpio_write_calls == 2u);
    assert(gpio_pins[1] == 30u && gpio_values[1] == 0u);
}

static void test_close_and_state_contradiction_cleanup(void)
{
    C2837xBlock_SciChannel channel =
        C2837X_BLOCK_SCI_CHANNEL_INITIALIZER(&config_half_high);
    Uint16 word = 0x3412u;

    reset_registers();
    c2837x_block_sci_iodevice_ops.channel_init(&channel);
    connect_channel(&channel, &SciaRegs);
    clear_gpio_log();
    assert(c2837x_block_sci_iodevice_ops.send(&channel, &word, 2u) == 0);
    SciaRegs.SCIFFTX.bit.TXFFST = 5u;
    assert(c2837x_block_sci_iodevice_ops.close(&channel) > 0);
    assert(channel.runtime.connection_state ==
           C2837X_IODEVICE_CONNECTION_CLOSED);
    assert(channel.runtime.software_pending == 0u);
    assert(channel.runtime.ctrl_tx_active == 0u);
    assert(SciaRegs.SCIFFTX.bit.TXFIFORESET == 1u);
    assert(gpio_write_calls == 2u);
    assert(gpio_pins[1] == 30u && gpio_values[1] == 0u);

    reset_registers();
    c2837x_block_sci_iodevice_ops.channel_init(&channel);
    connect_channel(&channel, &SciaRegs);
    clear_gpio_log();
    assert(c2837x_block_sci_iodevice_ops.send(&channel, &word, 2u) == 0);
    channel.runtime.ctrl_tx_active = 0u;
    assert(c2837x_block_sci_iodevice_ops.send(&channel, &word, 2u) < 0);
    assert(channel.runtime.connection_state ==
           C2837X_IODEVICE_CONNECTION_CLOSED);
    assert(channel.runtime.software_pending == 0u);
    assert(channel.runtime.ctrl_tx_active == 0u);
    assert(gpio_write_calls == 2u);
    assert(gpio_pins[1] == 30u && gpio_values[1] == 0u);
}

int main(void)
{
    test_ctrl_none_regression();
    test_half_duplex_start_and_progression();
    test_physical_completion_switches_to_rx_first();
    test_polarity_low();
    test_receive_while_tx_active_is_error();
    test_close_and_state_contradiction_cleanup();
    return 0;
}
