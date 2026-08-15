#include "c2837x_block_sci.h"

#define C2837X_BLOCK_SCI_TX_FIFO_DEPTH 16u

static Uint16 c2837x_block_sci_ctrl_rx_level(
    C2837xBlock_SciCtrlTxActiveLevel active_level)
{
    return (active_level == C2837X_BLOCK_SCI_CTRL_TX_ACTIVE_HIGH) ? 0u : 1u;
}

static Uint16 c2837x_block_sci_ctrl_tx_level(
    C2837xBlock_SciCtrlTxActiveLevel active_level)
{
    return (active_level == C2837X_BLOCK_SCI_CTRL_TX_ACTIVE_HIGH) ? 1u : 0u;
}

static Uint16 c2837x_block_sci_has_ctrl(
    const C2837xBlock_SciDescriptor *config)
{
    return (config != 0) &&
        (config->ctrl.gpio != C2837X_BLOCK_SCI_NO_CTRL_GPIO);
}

static volatile struct SCI_REGS *c2837x_block_sci_registers(
    C2837xBlock_SciModule module)
{
#if defined(__TI_COMPILER_VERSION__) || defined(C2837X_BLOCK_SCI_HOST_TEST)
    switch (module)
    {
    case C2837X_BLOCK_SCI_MODULE_A:
        return &SciaRegs;
    case C2837X_BLOCK_SCI_MODULE_B:
        return &ScibRegs;
    case C2837X_BLOCK_SCI_MODULE_C:
        return &ScicRegs;
    case C2837X_BLOCK_SCI_MODULE_D:
        return &ScidRegs;
    default:
        return 0;
    }
#else
    (void)module;
    return 0;
#endif
}

static void c2837x_block_sci_clear_tx_pending(
    C2837xBlock_SciChannelRuntime *runtime)
{
    runtime->software_pending = 0u;
    runtime->tx_pending_data_words = 0;
    runtime->tx_pending_total_octets = 0u;
    runtime->tx_pending_queued_octets = 0u;
}

static void c2837x_block_sci_reset_software_runtime(
    C2837xBlock_SciChannel *channel)
{
    const C2837xBlock_SciDescriptor *config;

    config = channel->hardware_config;
    channel->runtime.rx_staging_octet = 0u;
    channel->runtime.rx_staging_valid = 0u;
    c2837x_block_sci_clear_tx_pending(&channel->runtime);
    channel->runtime.ctrl_tx_active = 0u;

    /* PlatformInit owns PinMux/pad configuration; cleanup only drives RX. */
    if (c2837x_block_sci_has_ctrl(config) != 0u)
    {
        GPIO_WritePin(config->ctrl.gpio,
                      c2837x_block_sci_ctrl_rx_level(
                          config->ctrl.tx_active_level));
    }
}

static int16 c2837x_block_sci_session_cleanup(
    C2837xBlock_SciChannel *channel)
{
    const C2837xBlock_SciDescriptor *config;
    volatile struct SCI_REGS *sci;

    if (channel == 0)
        return -1;

    config = channel->hardware_config;
    c2837x_block_sci_reset_software_runtime(channel);

    if (config == 0)
        return -1;
    sci = c2837x_block_sci_registers(config->module);
    if (sci == 0)
        return 0;

    /* SWRESET clears the latched SCI RX error without reconfiguring format. */
    sci->SCICTL1.bit.SWRESET = 0u;
    sci->SCIFFRX.bit.RXFFOVRCLR = 1u;
    sci->SCIFFRX.bit.RXFIFORESET = 0u;
    sci->SCIFFTX.bit.TXFIFORESET = 0u;
    sci->SCIFFRX.bit.RXFIFORESET = 1u;
    sci->SCIFFTX.bit.TXFIFORESET = 1u;
    sci->SCICTL1.bit.SWRESET = 1u;
    return 0;
}

static Uint16 c2837x_block_sci_has_rx_error(
    volatile struct SCI_REGS *sci)
{
    return (sci != 0) &&
        ((sci->SCIRXST.bit.RXERROR != 0u) ||
         (sci->SCIFFRX.bit.RXFFOVF != 0u));
}

static void c2837x_block_sci_close_after_error(
    C2837xBlock_SciChannel *channel)
{
    (void)c2837x_block_sci_session_cleanup(channel);
    channel->runtime.connection_state = C2837X_IODEVICE_CONNECTION_CLOSED;
    channel->runtime.session_cleanup_done = 1u;
}

static Uint16 c2837x_block_sci_read_octet(
    volatile struct SCI_REGS *sci)
{
    return (Uint16)(sci->SCIRXBUF.all & 0x00FFu);
}

void c2837x_block_sci_channel_init(C2837xBlock_SciChannel *channel)
{
    if (channel == 0)
        return;

    channel->runtime.connection_state =
        C2837X_IODEVICE_CONNECTION_CLOSED;
    channel->runtime.session_cleanup_done = 0u;
    c2837x_block_sci_reset_software_runtime(channel);
}

static void channel_init(void *channel_ref)
{
    c2837x_block_sci_channel_init(
        (C2837xBlock_SciChannel *)channel_ref);
}

static int16 open_channel(void *channel_ref)
{
    C2837xBlock_SciChannel *channel =
        (C2837xBlock_SciChannel *)channel_ref;

    if ((channel == 0) ||
        (channel->runtime.connection_state !=
         C2837X_IODEVICE_CONNECTION_CLOSED))
        return -1;

    channel->runtime.connection_state = C2837X_IODEVICE_CONNECTION_OPEN;
    return 0;
}

static int16 listen_channel(void *channel_ref)
{
    C2837xBlock_SciChannel *channel =
        (C2837xBlock_SciChannel *)channel_ref;

    if ((channel == 0) ||
        (channel->runtime.connection_state !=
         C2837X_IODEVICE_CONNECTION_OPEN))
        return -1;

    if (channel->runtime.session_cleanup_done == 0u)
    {
        if (c2837x_block_sci_session_cleanup(channel) < 0)
            return -1;
        channel->runtime.session_cleanup_done = 1u;
    }
    channel->runtime.connection_state =
        C2837X_IODEVICE_CONNECTION_LISTENING;
    return 0;
}

static C2837xBlock_IoConnectionState get_connection_state(
    void *channel_ref)
{
    C2837xBlock_SciChannel *channel =
        (C2837xBlock_SciChannel *)channel_ref;
    volatile struct SCI_REGS *sci;

    if (channel == 0)
        return C2837X_IODEVICE_CONNECTION_ERROR;

    switch (channel->runtime.connection_state)
    {
    case C2837X_IODEVICE_CONNECTION_CLOSED:
    case C2837X_IODEVICE_CONNECTION_OPEN:
    case C2837X_IODEVICE_CONNECTION_CONNECTED:
        return channel->runtime.connection_state;
    case C2837X_IODEVICE_CONNECTION_LISTENING:
        if (channel->hardware_config == 0)
        {
            c2837x_block_sci_close_after_error(channel);
            return C2837X_IODEVICE_CONNECTION_ERROR;
        }
        sci = c2837x_block_sci_registers(channel->hardware_config->module);
        if ((sci == 0) || c2837x_block_sci_has_rx_error(sci) != 0u)
        {
            c2837x_block_sci_close_after_error(channel);
            return C2837X_IODEVICE_CONNECTION_ERROR;
        }
        if (sci->SCIFFRX.bit.RXFFST != 0u)
        {
            channel->runtime.connection_state =
                C2837X_IODEVICE_CONNECTION_CONNECTED;
            return C2837X_IODEVICE_CONNECTION_CONNECTED;
        }
        return C2837X_IODEVICE_CONNECTION_LISTENING;
    default:
        c2837x_block_sci_close_after_error(channel);
        return C2837X_IODEVICE_CONNECTION_ERROR;
    }
}

static int32 receive(void *channel_ref, Uint16 *data_words,
                     Uint32 capacity_octets)
{
    C2837xBlock_SciChannel *channel =
        (C2837xBlock_SciChannel *)channel_ref;
    const C2837xBlock_SciDescriptor *config;
    volatile struct SCI_REGS *sci;
    Uint32 capacity_even;
    Uint32 produced_octets = 0u;
    Uint16 available_octets;
    Uint16 first_octet;
    Uint16 second_octet;

    if ((channel == 0) ||
        (channel->runtime.connection_state !=
         C2837X_IODEVICE_CONNECTION_CONNECTED))
        return -1;

    config = channel->hardware_config;
    if (config == 0)
    {
        c2837x_block_sci_close_after_error(channel);
        return -1;
    }

    if ((c2837x_block_sci_has_ctrl(config) != 0u) &&
        (channel->runtime.ctrl_tx_active != 0u))
    {
        c2837x_block_sci_close_after_error(channel);
        return -1;
    }

    sci = c2837x_block_sci_registers(config->module);
    if ((sci == 0) || c2837x_block_sci_has_rx_error(sci) != 0u)
    {
        c2837x_block_sci_close_after_error(channel);
        return -1;
    }
    capacity_even = capacity_octets & ~1u;
    if (capacity_even == 0u)
        return 0;
    if (data_words == 0)
        return -1;

    available_octets = sci->SCIFFRX.bit.RXFFST;

    if ((channel->runtime.rx_staging_valid != 0u) &&
        (available_octets != 0u))
    {
        first_octet = (Uint16)(channel->runtime.rx_staging_octet & 0x00FFu);
        second_octet = c2837x_block_sci_read_octet(sci);
        data_words[0] = (Uint16)(first_octet | (second_octet << 8));
        channel->runtime.rx_staging_valid = 0u;
        available_octets--;
        produced_octets = 2u;
    }

    while ((available_octets >= 2u) &&
           ((produced_octets + 2u) <= capacity_even))
    {
        first_octet = c2837x_block_sci_read_octet(sci);
        second_octet = c2837x_block_sci_read_octet(sci);
        data_words[produced_octets / 2u] =
            (Uint16)(first_octet | (second_octet << 8));
        available_octets -= 2u;
        produced_octets += 2u;
    }

    if ((available_octets != 0u) &&
        (channel->runtime.rx_staging_valid == 0u) &&
        (produced_octets < capacity_even))
    {
        channel->runtime.rx_staging_octet =
            c2837x_block_sci_read_octet(sci);
        channel->runtime.rx_staging_valid = 1u;
    }

    return (int32)produced_octets;
}

static int32 send(void *channel_ref, const Uint16 *data_words,
                  Uint32 count_octets)
{
    C2837xBlock_SciChannel *channel =
        (C2837xBlock_SciChannel *)channel_ref;
    const C2837xBlock_SciDescriptor *config;
    volatile struct SCI_REGS *sci;
    Uint16 has_ctrl;
    Uint16 fifo_occupied;
    Uint32 available_slots;
    Uint32 remaining_octets;
    Uint32 write_octets;
    Uint32 index;
    Uint32 wire_offset;
    Uint16 word;
    int32 completed_octets;

    if ((channel == 0) ||
        (channel->runtime.connection_state !=
         C2837X_IODEVICE_CONNECTION_CONNECTED))
        return -1;

    if (channel->runtime.software_pending != 0u)
    {
        if ((data_words != channel->runtime.tx_pending_data_words) ||
            (count_octets != channel->runtime.tx_pending_total_octets))
        {
            c2837x_block_sci_close_after_error(channel);
            return -1;
        }
        if ((channel->runtime.tx_pending_data_words == 0) ||
            (channel->runtime.tx_pending_total_octets == 0u) ||
            ((channel->runtime.tx_pending_total_octets & 1u) != 0u) ||
            (channel->runtime.tx_pending_queued_octets >
             channel->runtime.tx_pending_total_octets))
        {
            c2837x_block_sci_close_after_error(channel);
            return -1;
        }
    }
    else
    {
        if (count_octets == 0u)
            return 0;
        if ((data_words == 0) || ((count_octets & 1u) != 0u))
        {
            c2837x_block_sci_close_after_error(channel);
            return -1;
        }
    }

    config = channel->hardware_config;
    if (config == 0)
    {
        c2837x_block_sci_close_after_error(channel);
        return -1;
    }
    has_ctrl = c2837x_block_sci_has_ctrl(config);

    if (channel->runtime.software_pending != 0u)
    {
        if (((has_ctrl != 0u) &&
             (channel->runtime.ctrl_tx_active != 1u)) ||
            ((has_ctrl == 0u) &&
             (channel->runtime.ctrl_tx_active != 0u)))
        {
            c2837x_block_sci_close_after_error(channel);
            return -1;
        }
    }
    else if (channel->runtime.ctrl_tx_active != 0u)
    {
        c2837x_block_sci_close_after_error(channel);
        return -1;
    }

    sci = c2837x_block_sci_registers(config->module);
    if (sci == 0)
    {
        c2837x_block_sci_close_after_error(channel);
        return -1;
    }

    if (channel->runtime.software_pending == 0u)
    {
        channel->runtime.software_pending = 1u;
        channel->runtime.tx_pending_data_words = data_words;
        channel->runtime.tx_pending_total_octets = count_octets;
        channel->runtime.tx_pending_queued_octets = 0u;

        if (has_ctrl != 0u)
        {
            GPIO_WritePin(
                config->ctrl.gpio,
                c2837x_block_sci_ctrl_tx_level(
                    config->ctrl.tx_active_level));
            channel->runtime.ctrl_tx_active = 1u;
            return 0;
        }
    }

    if (channel->runtime.tx_pending_queued_octets ==
        channel->runtime.tx_pending_total_octets)
    {
        fifo_occupied = sci->SCIFFTX.bit.TXFFST;
        if (fifo_occupied > C2837X_BLOCK_SCI_TX_FIFO_DEPTH)
        {
            c2837x_block_sci_close_after_error(channel);
            return -1;
        }
        if ((fifo_occupied == 0u) &&
            (sci->SCICTL2.bit.TXEMPTY != 0u))
        {
            completed_octets =
                (int32)channel->runtime.tx_pending_total_octets;

            if (has_ctrl != 0u)
            {
                GPIO_WritePin(
                    config->ctrl.gpio,
                    c2837x_block_sci_ctrl_rx_level(
                        config->ctrl.tx_active_level));
                channel->runtime.ctrl_tx_active = 0u;
            }
            c2837x_block_sci_clear_tx_pending(&channel->runtime);
            return completed_octets;
        }
        return 0;
    }

    fifo_occupied = sci->SCIFFTX.bit.TXFFST;
    if (fifo_occupied > C2837X_BLOCK_SCI_TX_FIFO_DEPTH)
    {
        c2837x_block_sci_close_after_error(channel);
        return -1;
    }
    available_slots = C2837X_BLOCK_SCI_TX_FIFO_DEPTH - fifo_occupied;
    remaining_octets = channel->runtime.tx_pending_total_octets -
        channel->runtime.tx_pending_queued_octets;
    write_octets = (available_slots < remaining_octets) ?
        available_slots : remaining_octets;

    /* One bounded pass: never wait for FIFO space or TXEMPTY. */
    for (index = 0u; index < write_octets; index++)
    {
        wire_offset = channel->runtime.tx_pending_queued_octets + index;
        word = channel->runtime.tx_pending_data_words[wire_offset / 2u];
        if ((wire_offset & 1u) == 0u)
            sci->SCITXBUF.all = (Uint16)(word & 0x00FFu);
        else
            sci->SCITXBUF.all = (Uint16)((word >> 8) & 0x00FFu);
    }

    channel->runtime.tx_pending_queued_octets += write_octets;
    return 0;
}

static int16 close_channel(void *channel_ref)
{
    C2837xBlock_SciChannel *channel =
        (C2837xBlock_SciChannel *)channel_ref;
    int16 result = 0;

    if (channel == 0)
        return -1;

    if ((channel->runtime.session_cleanup_done == 0u) ||
        (channel->runtime.connection_state !=
         C2837X_IODEVICE_CONNECTION_CLOSED))
        result = c2837x_block_sci_session_cleanup(channel);
    channel->runtime.connection_state = C2837X_IODEVICE_CONNECTION_CLOSED;
    channel->runtime.session_cleanup_done = 1u;
    return (result < 0) ? -1 : 1;
}

const C2837xBlock_IoDeviceOps c2837x_block_sci_iodevice_ops = {
    channel_init,
    open_channel,
    listen_channel,
    get_connection_state,
    receive,
    send,
    close_channel
};
