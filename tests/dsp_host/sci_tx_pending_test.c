#include <assert.h>
#include <string.h>
#include "c2837x_block_sci.h"

volatile struct SCI_REGS SciaRegs;
volatile struct SCI_REGS ScibRegs;
volatile struct SCI_REGS ScicRegs;
volatile struct SCI_REGS ScidRegs;

static Uint16 gpio_write_calls;

void GPIO_WritePin(Uint16 gpio, Uint16 value)
{
    (void)gpio;
    (void)value;
    gpio_write_calls++;
}

static const C2837xBlock_SciDescriptor config_a =
{
    C2837X_BLOCK_SCI_MODULE_A,
    1u,
    {{9u, 6u}, C2837X_BLOCK_SCI_PIN_STANDARD,
     C2837X_BLOCK_SCI_QUALIFICATION_ASYNC},
    {{8u, 6u}, C2837X_BLOCK_SCI_PIN_STANDARD},
    {C2837X_BLOCK_SCI_NO_CTRL_GPIO, C2837X_BLOCK_SCI_PIN_STANDARD,
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

static void test_byte_order_and_physical_completion(void)
{
    C2837xBlock_SciChannel channel =
        C2837X_BLOCK_SCI_CHANNEL_INITIALIZER(&config_a);
    Uint16 words[2] = {0x3412u, 0x7856u};

    reset_registers();
    c2837x_block_sci_iodevice_ops.channel_init(&channel);
    connect_channel(&channel, &SciaRegs);
    SciaRegs.SCICTL2.bit.TXEMPTY = 0u;

    SciaRegs.SCIFFTX.bit.TXFFST = 15u;
    assert(c2837x_block_sci_iodevice_ops.send(&channel, words, 4u) == 0);
    assert(channel.runtime.tx_pending_queued_octets == 1u);
    assert(SciaRegs.SCITXBUF.all == 0x12u);

    SciaRegs.SCIFFTX.bit.TXFFST = 15u;
    assert(c2837x_block_sci_iodevice_ops.send(&channel, words, 4u) == 0);
    assert(channel.runtime.tx_pending_queued_octets == 2u);
    assert(SciaRegs.SCITXBUF.all == 0x34u);

    SciaRegs.SCIFFTX.bit.TXFFST = 15u;
    assert(c2837x_block_sci_iodevice_ops.send(&channel, words, 4u) == 0);
    assert(channel.runtime.tx_pending_queued_octets == 3u);
    assert(SciaRegs.SCITXBUF.all == 0x56u);

    SciaRegs.SCIFFTX.bit.TXFFST = 15u;
    assert(c2837x_block_sci_iodevice_ops.send(&channel, words, 4u) == 0);
    assert(channel.runtime.tx_pending_queued_octets == 4u);
    assert(SciaRegs.SCITXBUF.all == 0x78u);

    SciaRegs.SCIFFTX.bit.TXFFST = 1u;
    SciaRegs.SCICTL2.bit.TXEMPTY = 1u;
    assert(c2837x_block_sci_iodevice_ops.send(&channel, words, 4u) == 0);
    assert(channel.runtime.software_pending == 1u);
    assert(SciaRegs.SCITXBUF.all == 0x78u);

    SciaRegs.SCIFFTX.bit.TXFFST = 0u;
    SciaRegs.SCICTL2.bit.TXEMPTY = 0u;
    assert(c2837x_block_sci_iodevice_ops.send(&channel, words, 4u) == 0);
    assert(channel.runtime.software_pending == 1u);
    assert(SciaRegs.SCITXBUF.all == 0x78u);

    SciaRegs.SCICTL2.bit.TXEMPTY = 1u;
    assert(c2837x_block_sci_iodevice_ops.send(&channel, words, 4u) == 4);
    assert(channel.runtime.software_pending == 0u);
    assert(channel.runtime.tx_pending_data_words == 0);
    assert(channel.runtime.tx_pending_total_octets == 0u);
    assert(channel.runtime.tx_pending_queued_octets == 0u);
}

static void test_fifo_capacity_and_multi_run_progression(void)
{
    C2837xBlock_SciChannel channel =
        C2837X_BLOCK_SCI_CHANNEL_INITIALIZER(&config_a);
    Uint16 words[16] = {0u};

    reset_registers();
    c2837x_block_sci_iodevice_ops.channel_init(&channel);
    connect_channel(&channel, &SciaRegs);
    SciaRegs.SCIFFTX.bit.TXFFST = 0u;

    assert(c2837x_block_sci_iodevice_ops.send(&channel, words, 32u) == 0);
    assert(channel.runtime.tx_pending_queued_octets == 16u);
    assert(channel.runtime.software_pending == 1u);

    SciaRegs.SCIFFTX.bit.TXFFST = 0u;
    assert(c2837x_block_sci_iodevice_ops.send(&channel, words, 32u) == 0);
    assert(channel.runtime.tx_pending_queued_octets == 32u);

    SciaRegs.SCICTL2.bit.TXEMPTY = 1u;
    assert(c2837x_block_sci_iodevice_ops.send(&channel, words, 32u) == 32);
    assert(channel.runtime.software_pending == 0u);
}

static void test_second_operation_is_rejected_and_cleaned(void)
{
    C2837xBlock_SciChannel channel =
        C2837X_BLOCK_SCI_CHANNEL_INITIALIZER(&config_a);
    Uint16 first_word = 0x3412u;
    Uint16 second_word = 0x7856u;
    Uint16 last_tx_value;

    reset_registers();
    c2837x_block_sci_iodevice_ops.channel_init(&channel);
    connect_channel(&channel, &SciaRegs);
    SciaRegs.SCIFFTX.bit.TXFFST = 15u;
    assert(c2837x_block_sci_iodevice_ops.send(&channel, &first_word, 2u) ==
           0);
    last_tx_value = SciaRegs.SCITXBUF.all;

    assert(c2837x_block_sci_iodevice_ops.send(&channel, &second_word, 2u) <
           0);
    assert(channel.runtime.connection_state ==
           C2837X_IODEVICE_CONNECTION_CLOSED);
    assert(channel.runtime.software_pending == 0u);
    assert(channel.runtime.tx_pending_data_words == 0);
    assert(channel.runtime.tx_pending_total_octets == 0u);
    assert(channel.runtime.tx_pending_queued_octets == 0u);
    assert(SciaRegs.SCITXBUF.all == last_tx_value);
    assert(SciaRegs.SCIFFTX.bit.TXFIFORESET == 1u);
}

static void test_operation_boundaries(void)
{
    C2837xBlock_SciChannel channel =
        C2837X_BLOCK_SCI_CHANNEL_INITIALIZER(&config_a);
    Uint16 word = 0x3412u;

    reset_registers();
    c2837x_block_sci_iodevice_ops.channel_init(&channel);
    connect_channel(&channel, &SciaRegs);
    assert(c2837x_block_sci_iodevice_ops.send(&channel, 0, 0u) == 0);
    assert(channel.runtime.software_pending == 0u);

    assert(c2837x_block_sci_iodevice_ops.send(&channel, 0, 2u) < 0);
    assert(channel.runtime.connection_state ==
           C2837X_IODEVICE_CONNECTION_CLOSED);

    reset_registers();
    c2837x_block_sci_iodevice_ops.channel_init(&channel);
    connect_channel(&channel, &SciaRegs);
    assert(c2837x_block_sci_iodevice_ops.send(&channel, &word, 1u) < 0);
    assert(channel.runtime.connection_state ==
           C2837X_IODEVICE_CONNECTION_CLOSED);
}

static void test_cleanup_and_new_session_do_not_inherit_pending(void)
{
    C2837xBlock_SciChannel channel =
        C2837X_BLOCK_SCI_CHANNEL_INITIALIZER(&config_a);
    Uint16 old_words[2] = {0x3412u, 0x7856u};
    Uint16 new_word = 0xBBAAu;

    reset_registers();
    c2837x_block_sci_iodevice_ops.channel_init(&channel);
    connect_channel(&channel, &SciaRegs);
    SciaRegs.SCIFFTX.bit.TXFFST = 15u;
    assert(c2837x_block_sci_iodevice_ops.send(&channel, old_words, 4u) == 0);
    assert(channel.runtime.software_pending == 1u);

    assert(c2837x_block_sci_iodevice_ops.close(&channel) > 0);
    assert(channel.runtime.software_pending == 0u);
    assert(channel.runtime.tx_pending_data_words == 0);
    assert(channel.runtime.tx_pending_total_octets == 0u);
    assert(channel.runtime.tx_pending_queued_octets == 0u);
    assert(SciaRegs.SCIFFTX.bit.TXFIFORESET == 1u);

    SciaRegs.SCIFFRX.bit.RXFFST = 0u;
    start_listening(&channel);
    SciaRegs.SCIFFRX.bit.RXFFST = 1u;
    assert(c2837x_block_sci_iodevice_ops.get_connection_state(&channel) ==
           C2837X_IODEVICE_CONNECTION_CONNECTED);
    SciaRegs.SCIFFTX.bit.TXFFST = 15u;
    assert(c2837x_block_sci_iodevice_ops.send(&channel, &new_word, 2u) == 0);
    assert(channel.runtime.tx_pending_data_words == &new_word);
    assert(channel.runtime.tx_pending_queued_octets == 1u);
    assert(SciaRegs.SCITXBUF.all == 0xAAu);
}

static void test_channel_isolation(void)
{
    C2837xBlock_SciChannel channel_a =
        C2837X_BLOCK_SCI_CHANNEL_INITIALIZER(&config_a);
    C2837xBlock_SciChannel channel_b =
        C2837X_BLOCK_SCI_CHANNEL_INITIALIZER(&config_b);
    Uint16 word_a = 0x3412u;
    Uint16 word_b = 0x7856u;

    reset_registers();
    c2837x_block_sci_iodevice_ops.channel_init(&channel_a);
    c2837x_block_sci_iodevice_ops.channel_init(&channel_b);
    connect_channel(&channel_a, &SciaRegs);
    connect_channel(&channel_b, &ScibRegs);

    SciaRegs.SCIFFTX.bit.TXFFST = 15u;
    ScibRegs.SCIFFTX.bit.TXFFST = 15u;
    assert(c2837x_block_sci_iodevice_ops.send(&channel_a, &word_a, 2u) == 0);
    assert(channel_a.runtime.software_pending == 1u);
    assert(channel_a.runtime.tx_pending_queued_octets == 1u);
    assert(channel_b.runtime.software_pending == 0u);
    assert(channel_b.runtime.tx_pending_queued_octets == 0u);
    assert(ScibRegs.SCITXBUF.all == 0u);

    assert(c2837x_block_sci_iodevice_ops.send(&channel_b, &word_b, 2u) == 0);
    assert(channel_a.runtime.tx_pending_queued_octets == 1u);
    assert(channel_b.runtime.software_pending == 1u);
    assert(channel_b.runtime.tx_pending_queued_octets == 1u);
    assert(SciaRegs.SCITXBUF.all == 0x12u);
    assert(ScibRegs.SCITXBUF.all == 0x56u);
}

int main(void)
{
    test_byte_order_and_physical_completion();
    test_fifo_capacity_and_multi_run_progression();
    test_second_operation_is_rejected_and_cleaned();
    test_operation_boundaries();
    test_cleanup_and_new_session_do_not_inherit_pending();
    test_channel_isolation();
    return 0;
}
