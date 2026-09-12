#include "c2837x_w5300_udp_channel.h"
#include "c2837x_block_platform.h"

static void clear_socket_runtime(C2837xW5300Socket *socket)
{
    socket->pending_command = C2837X_W5300_COMMAND_NONE;
    socket->command_phase = C2837X_W5300_COMMAND_PHASE_IDLE;
    socket->udp_rx_datagram_active = 0u;
    socket->udp_rx_data_remaining = 0u;
    socket->udp_rx_residual_byte = 0u;
    socket->udp_rx_residual_valid = 0u;
}

static void clear_candidate_and_datagram(C2837xW5300UdpChannel *channel)
{
    channel->candidate_ip = 0u;
    channel->candidate_port = 0u;
    channel->candidate_valid = 0u;
    channel->datagram_active = 0u;
    channel->datagram_data_size = 0u;
    channel->datagram_consumed = 0u;
}

static void reset_runtime(C2837xW5300UdpChannel *channel)
{
    clear_candidate_and_datagram(channel);
    clear_socket_runtime(&channel->socket);
    channel->send_state = C2837X_W5300_UDP_SEND_IDLE;
    channel->pending_octets = 0u;
    channel->faulted = 0u;
    channel->close_state = C2837X_W5300_UDP_CLOSE_IDLE;
    channel->close_start_us = 0u;
}

static void sync_platform_generation(C2837xW5300UdpChannel *channel)
{
    Uint32 generation = c2837x_block_platform_generation();

    if (generation != channel->observed_platform_generation)
    {
        reset_runtime(channel);
        channel->observed_platform_generation = generation;
    }
}

static int16 runtime_operation_allowed(
    const C2837xW5300UdpChannel *channel)
{
    return ((channel->faulted == 0u) &&
            (channel->close_state == C2837X_W5300_UDP_CLOSE_IDLE)) ?
        1 : 0;
}

static int16 control_operation_allowed(C2837xW5300UdpChannel *channel)
{
    sync_platform_generation(channel);
    return runtime_operation_allowed(channel);
}

static void channel_init(void *channel_ref)
{
    C2837xW5300UdpChannel *channel =
        (C2837xW5300UdpChannel *)channel_ref;

    reset_runtime(channel);
    channel->observed_platform_generation =
        c2837x_block_platform_generation();
}

static int16 open_channel(void *channel_ref)
{
    C2837xW5300UdpChannel *channel =
        (C2837xW5300UdpChannel *)channel_ref;

    if (!control_operation_allowed(channel))
        return -1;
    return c2837x_w5300_socket_udp_open(&channel->socket, channel->udp_port);
}

static int16 listen_channel(void *channel_ref)
{
    C2837xW5300UdpChannel *channel =
        (C2837xW5300UdpChannel *)channel_ref;

    if (!control_operation_allowed(channel))
        return -1;

    /* W5300 UDP has no LISTEN command; SOCK_UDP is already logical listen. */
    return (c2837x_w5300_get_sn_ssr(channel->socket.sn) == SOCK_UDP) ?
        1 : -1;
}

static C2837xBlock_IoConnectionState get_connection_state(void *channel_ref)
{
    C2837xW5300UdpChannel *channel =
        (C2837xW5300UdpChannel *)channel_ref;
    C2837xW5300UdpPacketInfo packet_info;
    Uint16 status;
    int16 available;
    int16 packet_result;

    if (!control_operation_allowed(channel))
        return C2837X_IODEVICE_CONNECTION_ERROR;

    status = c2837x_w5300_get_sn_ssr(channel->socket.sn);

    /* Keep the Core in its CLOSED -> open() progression until UDP OPEN is
     * completed by the Socket primitive.  SOCK_INIT is not UDP OPEN done. */
    if (channel->socket.pending_command ==
        C2837X_W5300_COMMAND_NATIVE_UDP_OPEN)
    {
        return C2837X_IODEVICE_CONNECTION_CLOSED;
    }

    switch (status)
    {
    case SOCK_CLOSED:
        return C2837X_IODEVICE_CONNECTION_CLOSED;

    case SOCK_UDP:
        if (channel->candidate_valid != 0u)
            return C2837X_IODEVICE_CONNECTION_CONNECTED;
        if (channel->datagram_active != 0u)
            return C2837X_IODEVICE_CONNECTION_ERROR;

        available = c2837x_w5300_socket_udp_rx_available(
            &channel->socket);
        if (available < 0)
            return C2837X_IODEVICE_CONNECTION_ERROR;
        if (available == 0)
            return C2837X_IODEVICE_CONNECTION_LISTENING;

        /* This is the only receive action in S3-01: exactly PACKET-INFO. */
        packet_result = c2837x_w5300_socket_udp_read_packet_info(
            &channel->socket, &packet_info);
        if (packet_result < 0)
            return C2837X_IODEVICE_CONNECTION_ERROR;
        if (packet_result == 0)
            return C2837X_IODEVICE_CONNECTION_LISTENING;

        channel->candidate_ip = packet_info.source_ip;
        channel->candidate_port = packet_info.source_port;
        channel->candidate_valid = 1u;
        channel->datagram_active = 1u;
        channel->datagram_data_size = (Uint32)packet_info.data_size;
        channel->datagram_consumed = 0u;
        return C2837X_IODEVICE_CONNECTION_CONNECTED;

    default:
        return C2837X_IODEVICE_CONNECTION_ERROR;
    }
}

/* S3-01 deliberately does not provide a UDP DATA receive adapter. */
static int32 receive(void *channel_ref, Uint16 *data_words,
                     Uint32 capacity_octets)
{
    C2837xW5300UdpChannel *channel =
        (C2837xW5300UdpChannel *)channel_ref;

    (void)data_words;
    (void)capacity_octets;
    return runtime_operation_allowed(channel) ? 0 : -1;
}

/* S3-01 deliberately does not connect the native UDP TX primitive. */
static int32 send(void *channel_ref, const Uint16 *data_words,
                  Uint32 count_octets)
{
    C2837xW5300UdpChannel *channel =
        (C2837xW5300UdpChannel *)channel_ref;

    (void)data_words;
    (void)count_octets;
    return runtime_operation_allowed(channel) ? 0 : -1;
}

static int16 close_fault(C2837xW5300UdpChannel *channel)
{
    channel->faulted = 1u;
    channel->close_state = C2837X_W5300_UDP_CLOSE_FAULTED;
    channel->send_state = C2837X_W5300_UDP_SEND_IDLE;
    channel->pending_octets = 0u;
    return -1;
}

static int16 close_done(C2837xW5300UdpChannel *channel)
{
    reset_runtime(channel);
    return 1;
}

static int16 close_channel(void *channel_ref)
{
    C2837xW5300UdpChannel *channel =
        (C2837xW5300UdpChannel *)channel_ref;
    int16 result;
    Uint16 status;

    sync_platform_generation(channel);
    if (channel->faulted != 0u)
        return -1;
    if ((channel->socket.sn >= C2837X_W5300_MAX_SOCK_NUM) ||
        (channel->time_us == 0) || (channel->close_timeout_us == 0u) ||
        (channel->close_timeout_us >= 0x80000000u))
        return close_fault(channel);

    if (channel->close_state == C2837X_W5300_UDP_CLOSE_IDLE)
    {
        channel->close_start_us = channel->time_us();
        if ((channel->socket.pending_command ==
             C2837X_W5300_COMMAND_NONE) &&
            (channel->socket.command_phase ==
             C2837X_W5300_COMMAND_PHASE_IDLE) &&
            (c2837x_w5300_get_sn_ssr(channel->socket.sn) == SOCK_CLOSED))
            return close_done(channel);

        channel->send_state = C2837X_W5300_UDP_SEND_IDLE;
        channel->pending_octets = 0u;
        channel->close_state =
            (channel->socket.pending_command ==
             C2837X_W5300_COMMAND_NONE) ?
            C2837X_W5300_UDP_CLOSE_ISSUE :
            C2837X_W5300_UDP_CLOSE_WAIT_EXISTING_CR;
        return 0;
    }
    if (channel->close_state == C2837X_W5300_UDP_CLOSE_FAULTED)
        return close_fault(channel);
    if ((channel->time_us() - channel->close_start_us) >=
        channel->close_timeout_us)
        return close_fault(channel);

    switch (channel->close_state)
    {
    case C2837X_W5300_UDP_CLOSE_WAIT_EXISTING_CR:
        result = c2837x_w5300_socket_take_pending(&channel->socket);
        if (result < 0)
            return close_fault(channel);
        if (result > 0)
            channel->close_state = C2837X_W5300_UDP_CLOSE_ISSUE;
        return 0;

    case C2837X_W5300_UDP_CLOSE_ISSUE:
        if (c2837x_w5300_socket_issue_close(&channel->socket) < 0)
            return close_fault(channel);
        channel->close_state = C2837X_W5300_UDP_CLOSE_WAIT_CR;
        return 0;

    case C2837X_W5300_UDP_CLOSE_WAIT_CR:
        result = c2837x_w5300_socket_poll_close_command(
            &channel->socket, C2837X_W5300_COMMAND_CLOSE);
        if (result < 0)
            return close_fault(channel);
        if (result > 0)
            channel->close_state = C2837X_W5300_UDP_CLOSE_WAIT_STATE;
        return 0;

    case C2837X_W5300_UDP_CLOSE_WAIT_STATE:
        status = c2837x_w5300_get_sn_ssr(channel->socket.sn);
        if (status == SOCK_CLOSED)
        {
            if (c2837x_w5300_socket_complete_close_command(
                    &channel->socket,
                    C2837X_W5300_COMMAND_CLOSE) < 0)
                return close_fault(channel);
            return close_done(channel);
        }
        if (!c2837x_w5300_is_socket_status(status))
            return close_fault(channel);
        return 0;

    default:
        return close_fault(channel);
    }
}

const C2837xBlock_IoDeviceOps c2837x_w5300_udp_iodevice_ops = {
    channel_init,
    open_channel,
    listen_channel,
    get_connection_state,
    receive,
    send,
    close_channel
};
