#include "c2837x_w5300_udp_channel.h"
#include "c2837x_block_platform.h"

#define C2837X_W5300_UDP_HEADER_BYTES 4u
#define C2837X_W5300_UDP_MAX_DATA_BYTES 1472u

static void clear_socket_runtime(C2837xW5300Socket *socket)
{
    socket->pending_command = C2837X_W5300_COMMAND_NONE;
    socket->command_phase = C2837X_W5300_COMMAND_PHASE_IDLE;
    socket->udp_rx_datagram_active = 0u;
    socket->udp_rx_data_remaining = 0u;
    socket->udp_rx_residual_byte = 0u;
    socket->udp_rx_residual_valid = 0u;
}

static void clear_datagram(C2837xW5300UdpChannel *channel)
{
    channel->datagram_active = 0u;
    channel->datagram_data_size = 0u;
    channel->datagram_consumed = 0u;
}

static void clear_candidate_and_datagram(C2837xW5300UdpChannel *channel)
{
    channel->candidate_ip = 0u;
    channel->candidate_port = 0u;
    channel->candidate_valid = 0u;
    clear_datagram(channel);
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

static int16 acquire_packet_info(C2837xW5300UdpChannel *channel,
                                 C2837xW5300UdpPacketInfo *packet_info)
{
    int16 available = c2837x_w5300_socket_udp_rx_available(&channel->socket);

    if (available <= 0)
        return available;
    return c2837x_w5300_socket_udp_read_packet_info(
        &channel->socket, packet_info);
}

static void stage_datagram(C2837xW5300UdpChannel *channel,
                           const C2837xW5300UdpPacketInfo *packet_info)
{
    channel->datagram_active = 1u;
    channel->datagram_data_size = (Uint32)packet_info->data_size;
    channel->datagram_consumed = 0u;
}

static int16 commit_datagram(C2837xW5300UdpChannel *channel)
{
    int16 result = c2837x_w5300_socket_udp_commit_recv(&channel->socket);

    if (result > 0)
        clear_datagram(channel);
    return result;
}

static int16 drop_datagram(C2837xW5300UdpChannel *channel)
{
    int32 dropped = c2837x_w5300_socket_udp_drop_data(&channel->socket);

    if (dropped < 0)
        return -1;
    if ((channel->socket.udp_rx_data_remaining != 0u) ||
        (channel->socket.udp_rx_residual_valid != 0u))
        return -1;

    channel->datagram_consumed = channel->datagram_data_size;
    return commit_datagram(channel);
}

static int16 acquire_next_receive_datagram(
    C2837xW5300UdpChannel *channel)
{
    C2837xW5300UdpPacketInfo packet_info;
    int16 result = acquire_packet_info(channel, &packet_info);

    if (result <= 0)
        return result;

    stage_datagram(channel, &packet_info);
    if ((channel->candidate_valid != 0u) &&
        ((packet_info.source_ip != channel->candidate_ip) ||
         (packet_info.source_port != channel->candidate_port)))
    {
        /* Filtering happens before any V1 framing interpretation. */
        result = drop_datagram(channel);
        if (result < 0)
            return -1;
        return 0;
    }

    return 1;
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

        packet_result = acquire_packet_info(channel, &packet_info);
        if (packet_result < 0)
            return C2837X_IODEVICE_CONNECTION_ERROR;
        if (packet_result == 0)
            return C2837X_IODEVICE_CONNECTION_LISTENING;

        channel->candidate_ip = packet_info.source_ip;
        channel->candidate_port = packet_info.source_port;
        channel->candidate_valid = 1u;
        stage_datagram(channel, &packet_info);
        return C2837X_IODEVICE_CONNECTION_CONNECTED;

    default:
        return C2837X_IODEVICE_CONNECTION_ERROR;
    }
}

static int32 receive(void *channel_ref, Uint16 *data_words,
                     Uint32 capacity_octets)
{
    C2837xW5300UdpChannel *channel =
        (C2837xW5300UdpChannel *)channel_ref;
    Uint32 consumed_before;
    Uint32 read_capacity;
    Uint32 remaining;
    Uint16 payload_length;
    int16 commit_result;
    int16 acquire_result;
    int32 received;

    if (!control_operation_allowed(channel))
        return -1;

    if (channel->datagram_active != 0u)
    {
        if (channel->socket.pending_command == C2837X_W5300_COMMAND_RECV)
        {
            commit_result = commit_datagram(channel);
            return (commit_result < 0) ? -1 : 0;
        }
        if (channel->socket.pending_command != C2837X_W5300_COMMAND_NONE)
            return -1;
        if (channel->socket.udp_rx_datagram_active == 0u)
            return -1;
    }
    else
    {
        if (channel->socket.pending_command != C2837X_W5300_COMMAND_NONE)
            return -1;
        if (channel->candidate_valid == 0u)
            return 0;

        acquire_result = acquire_next_receive_datagram(channel);
        if (acquire_result < 0)
            return -1;
        if (acquire_result == 0)
            return 0;
    }

    if ((channel->datagram_data_size < C2837X_W5300_UDP_HEADER_BYTES) ||
        (channel->datagram_data_size > C2837X_W5300_UDP_MAX_DATA_BYTES))
        return -1;

    if (channel->datagram_consumed < C2837X_W5300_UDP_HEADER_BYTES)
    {
        if (capacity_octets == 0u)
            return 0;

        read_capacity = C2837X_W5300_UDP_HEADER_BYTES -
            channel->datagram_consumed;
        if (read_capacity > capacity_octets)
            read_capacity = capacity_octets;
        consumed_before = channel->datagram_consumed;
        received = c2837x_w5300_socket_udp_read_data(
            &channel->socket, data_words, read_capacity);
        if (received < 0)
            return -1;
        if (received == 0)
            return 0;
        if ((((Uint32)received & 1u) != 0u) ||
            ((Uint32)received > read_capacity))
            return -1;

        channel->datagram_consumed += (Uint32)received;
        if (channel->datagram_consumed < C2837X_W5300_UDP_HEADER_BYTES)
            return received;

        if (consumed_before == 0u)
            payload_length = data_words[1];
        else if (consumed_before == 2u)
            payload_length = data_words[0];
        else
            return -1;

        if (channel->datagram_data_size !=
            (C2837X_W5300_UDP_HEADER_BYTES + (Uint32)payload_length))
            return -1;

        if (channel->datagram_data_size ==
            C2837X_W5300_UDP_HEADER_BYTES)
        {
            commit_result = commit_datagram(channel);
            if (commit_result < 0)
                return -1;
        }
        return received;
    }

    remaining = channel->datagram_data_size - channel->datagram_consumed;
    if (remaining == 0u)
    {
        commit_result = commit_datagram(channel);
        return (commit_result < 0) ? -1 : 0;
    }
    if (capacity_octets == 0u)
        return 0;

    read_capacity = (capacity_octets < remaining) ?
        capacity_octets : remaining;
    consumed_before = channel->datagram_consumed;
    received = c2837x_w5300_socket_udp_read_data(
        &channel->socket, data_words, read_capacity);
    if (received < 0)
        return -1;
    if (received == 0)
        return 0;
    if ((((Uint32)received & 1u) != 0u) ||
        ((Uint32)received > read_capacity))
        return -1;

    channel->datagram_consumed = consumed_before + (Uint32)received;
    if (channel->datagram_consumed == channel->datagram_data_size)
    {
        commit_result = commit_datagram(channel);
        if (commit_result < 0)
            return -1;
    }
    return received;
}

static int32 send(void *channel_ref, const Uint16 *data_words,
                  Uint32 count_octets)
{
    C2837xW5300UdpChannel *channel =
        (C2837xW5300UdpChannel *)channel_ref;
    Uint32 completed_octets;
    int32 submitted_octets;
    int16 command_result;
    Uint16 status;
    Uint16 ir;
    Uint16 clear_mask;

    if (!control_operation_allowed(channel))
        return -1;

    if (channel->send_state == C2837X_W5300_UDP_SEND_PENDING)
    {
        if ((channel->pending_octets == 0u) ||
            ((channel->pending_octets & 1u) != 0u) ||
            (channel->pending_octets > C2837X_W5300_UDP_MAX_DATA_BYTES))
            goto send_error;

        if (channel->socket.pending_command == C2837X_W5300_COMMAND_SEND)
        {
            command_result = c2837x_w5300_socket_advance_send_command(
                &channel->socket);
            if (command_result < 0)
                goto send_error;
            return 0;
        }
        if (channel->socket.pending_command != C2837X_W5300_COMMAND_NONE)
            goto send_error;
        if (c2837x_w5300_socket_advance_send_command(&channel->socket) < 0)
            goto send_error;

        status = c2837x_w5300_get_sn_ssr(channel->socket.sn);
        ir = c2837x_w5300_get_sn_ir(channel->socket.sn);
        clear_mask = ir & (Sn_IR_SENDOK | Sn_IR_TIMEOUT);
        if ((ir & Sn_IR_TIMEOUT) != 0u)
        {
            if (clear_mask != 0u)
                c2837x_w5300_set_sn_ir(channel->socket.sn, clear_mask);
            goto send_error;
        }
        if (status != SOCK_UDP)
        {
            if (clear_mask != 0u)
                c2837x_w5300_set_sn_ir(channel->socket.sn, clear_mask);
            goto send_error;
        }
        if ((ir & Sn_IR_SENDOK) == 0u)
            return 0;

        /* SENDOK confirms only the local W5300 UDP operation. */
        completed_octets = channel->pending_octets;
        c2837x_w5300_set_sn_ir(channel->socket.sn, Sn_IR_SENDOK);
        channel->send_state = C2837X_W5300_UDP_SEND_IDLE;
        channel->pending_octets = 0u;
        return (int32)completed_octets;
    }

    if ((channel->send_state != C2837X_W5300_UDP_SEND_IDLE) ||
        (channel->pending_octets != 0u))
        goto send_error;

    if (channel->candidate_valid == 0u)
        goto send_error;
    if (channel->socket.pending_command == C2837X_W5300_COMMAND_RECV)
    {
        command_result = c2837x_w5300_socket_advance_recv_command(
            &channel->socket);
        if (command_result < 0)
            goto send_error;
        return 0;
    }
    if (channel->socket.pending_command != C2837X_W5300_COMMAND_NONE)
        goto send_error;
    if (count_octets == 0u)
        return 0;
    if (((count_octets & 1u) != 0u) ||
        (count_octets > C2837X_W5300_UDP_MAX_DATA_BYTES))
        goto send_error;

    submitted_octets = c2837x_w5300_socket_udp_send(
        &channel->socket,
        channel->candidate_ip,
        channel->candidate_port,
        data_words,
        count_octets);
    if (submitted_octets < 0)
        goto send_error;
    if (submitted_octets == 0)
        return 0;
    if ((Uint32)submitted_octets != count_octets)
        goto send_error;

    channel->send_state = C2837X_W5300_UDP_SEND_PENDING;
    channel->pending_octets = count_octets;
    return 0;

send_error:
    channel->send_state = C2837X_W5300_UDP_SEND_IDLE;
    channel->pending_octets = 0u;
    return -1;
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
