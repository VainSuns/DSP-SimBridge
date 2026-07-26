#include "c2837x_w5300_channel.h"
#include "c2837x_block_platform.h"
#include "c2837x_w5300_hal.h"

#define C2837X_W5300_ERRATUM_DUMMY_IP   0x00000001u
#define C2837X_W5300_ERRATUM_DUMMY_PORT 5000u

static void reset_runtime(C2837xW5300Channel *channel)
{
    channel->connected = 0u;
    channel->socket.pending_command = C2837X_W5300_COMMAND_NONE;
    channel->socket.command_phase = C2837X_W5300_COMMAND_PHASE_IDLE;
    channel->send_state = C2837X_W5300_SEND_IDLE;
    channel->pending_octets = 0u;
    channel->faulted = 0u;
    channel->close_state = C2837X_W5300_CLOSE_IDLE;
    channel->close_start_us = 0u;
}

static void sync_platform_generation(C2837xW5300Channel *channel)
{
    Uint32 generation = c2837x_block_platform_generation();

    if (generation != channel->observed_platform_generation)
    {
        reset_runtime(channel);
        channel->observed_platform_generation = generation;
    }
}

static void channel_init(void *channel_ref)
{
    C2837xW5300Channel *channel = (C2837xW5300Channel *)channel_ref;

    reset_runtime(channel);
    channel->observed_platform_generation =
        c2837x_block_platform_generation();
}

static int16 operation_allowed(C2837xW5300Channel *channel)
{
    sync_platform_generation(channel);
    return ((channel->faulted == 0u) &&
            (channel->close_state == C2837X_W5300_CLOSE_IDLE)) ? 1 : 0;
}

static int16 open_channel(void *channel_ref)
{
    C2837xW5300Channel *channel = (C2837xW5300Channel *)channel_ref;

    if (!operation_allowed(channel))
        return -1;
    return c2837x_w5300_socket_open(&channel->socket, Sn_MR_TCP,
                                     channel->tcp_port, Sn_MR_ALIGN);
}

static int16 listen_channel(void *channel_ref)
{
    C2837xW5300Channel *channel = (C2837xW5300Channel *)channel_ref;

    if (!operation_allowed(channel))
        return -1;
    return c2837x_w5300_socket_listen(&channel->socket);
}

static C2837xBlock_IoConnectionState get_connection_state(void *channel_ref)
{
    C2837xW5300Channel *channel = (C2837xW5300Channel *)channel_ref;
    Uint16 status;

    if (!operation_allowed(channel))
        return C2837X_IODEVICE_CONNECTION_ERROR;
    status = c2837x_w5300_get_sn_ssr(channel->socket.sn);
    if (status != SOCK_ESTABLISHED)
        channel->connected = 0u;
    switch (status)
    {
    case SOCK_CLOSED:
        return C2837X_IODEVICE_CONNECTION_CLOSED;
    case SOCK_ARP:
    case SOCK_SYNSENT:
    case SOCK_SYNRECV:
    case SOCK_LISTEN:
        return C2837X_IODEVICE_CONNECTION_LISTENING;
    case SOCK_INIT:
        return C2837X_IODEVICE_CONNECTION_OPEN;
    case SOCK_ESTABLISHED:
        if (channel->connected == 0u)
        {
            c2837x_w5300_set_sn_ir(channel->socket.sn, Sn_IR_CON);
            channel->connected = 1u;
        }
        return C2837X_IODEVICE_CONNECTION_CONNECTED;
    case SOCK_FIN_WAIT:
    case SOCK_CLOSING:
    case SOCK_TIME_WAIT:
    case SOCK_CLOSE_WAIT:
    case SOCK_LAST_ACK:
        return C2837X_IODEVICE_CONNECTION_PEER_CLOSED;
    default:
        return C2837X_IODEVICE_CONNECTION_ERROR;
    }
}

static int32 receive(void *channel_ref, Uint16 *data_words,
                     Uint32 capacity_octets)
{
    C2837xW5300Channel *channel = (C2837xW5300Channel *)channel_ref;

    if (!operation_allowed(channel))
        return -1;
    capacity_octets &= ~1u;
    if (capacity_octets == 0u)
        return 0;
    return c2837x_w5300_socket_recv(&channel->socket, data_words,
                                     capacity_octets);
}

static int32 send(void *channel_ref, const Uint16 *data_words,
                  Uint32 count_octets)
{
    C2837xW5300Channel *channel = (C2837xW5300Channel *)channel_ref;
    Uint32 completed_octets;
    int32 submitted_octets;
    int16 command_result;
    Uint16 status;
    Uint16 ir;
    Uint16 clear_mask;

    if (!operation_allowed(channel))
        return -1;
    if (channel->send_state == C2837X_W5300_SEND_PENDING)
    {
        if ((channel->pending_octets == 0u) ||
            ((channel->pending_octets & 1u) != 0u))
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
            c2837x_w5300_set_sn_ir(channel->socket.sn, clear_mask);
            goto send_error;
        }
        if ((status != SOCK_ESTABLISHED) && (status != SOCK_CLOSE_WAIT))
            goto send_error;
        if ((ir & Sn_IR_SENDOK) == 0u)
            return 0;

        completed_octets = channel->pending_octets;
        c2837x_w5300_set_sn_ir(channel->socket.sn, Sn_IR_SENDOK);
        channel->send_state = C2837X_W5300_SEND_IDLE;
        channel->pending_octets = 0u;
        return (int32)completed_octets;
    }

    if ((channel->send_state != C2837X_W5300_SEND_IDLE) ||
        (channel->pending_octets != 0u) ||
        (channel->socket.pending_command != C2837X_W5300_COMMAND_NONE))
        goto send_error;

    count_octets &= ~1u;
    if (count_octets == 0u)
        return 0;
    submitted_octets = c2837x_w5300_socket_send(&channel->socket, data_words,
                                                 count_octets);
    if (submitted_octets < 0)
        goto send_error;
    if (submitted_octets == 0)
        return 0;
    if ((((Uint32)submitted_octets & 1u) != 0u) ||
        ((Uint32)submitted_octets > count_octets))
        goto send_error;

    channel->pending_octets = (Uint32)submitted_octets;
    channel->send_state = C2837X_W5300_SEND_PENDING;
    return 0;

send_error:
    channel->send_state = C2837X_W5300_SEND_IDLE;
    channel->pending_octets = 0u;
    return -1;
}

static int16 close_fault(C2837xW5300Channel *channel)
{
    channel->faulted = 1u;
    channel->close_state = C2837X_W5300_CLOSE_FAULTED;
    channel->send_state = C2837X_W5300_SEND_IDLE;
    channel->pending_octets = 0u;
    return -1;
}

static int16 close_done(C2837xW5300Channel *channel)
{
    reset_runtime(channel);
    return 1;
}

static int16 close_channel(void *channel_ref)
{
    C2837xW5300Channel *channel = (C2837xW5300Channel *)channel_ref;
    int16 result;
    Uint16 status;
    Uint16 ir;
    Uint16 needed;

    sync_platform_generation(channel);
    if (channel->faulted != 0u)
        return -1;
    if ((channel->socket.sn >= C2837X_W5300_MAX_SOCK_NUM) ||
        (channel->time_us == 0) || (channel->close_timeout_us == 0u) ||
        (channel->close_timeout_us >= 0x80000000u))
        return close_fault(channel);

    if (channel->close_state == C2837X_W5300_CLOSE_IDLE)
    {
        channel->close_start_us = channel->time_us();
        if ((channel->socket.pending_command == C2837X_W5300_COMMAND_NONE) &&
            (channel->socket.command_phase == C2837X_W5300_COMMAND_PHASE_IDLE) &&
            (c2837x_w5300_get_sn_ssr(channel->socket.sn) == SOCK_CLOSED))
            return close_done(channel);
        channel->send_state = C2837X_W5300_SEND_IDLE;
        channel->pending_octets = 0u;
        channel->close_state =
            (channel->socket.pending_command == C2837X_W5300_COMMAND_NONE) ?
            C2837X_W5300_CLOSE_CHECK_ERRATUM :
            C2837X_W5300_CLOSE_WAIT_EXISTING_CR;
        return 0;
    }
    if (channel->close_state == C2837X_W5300_CLOSE_FAULTED)
        return close_fault(channel);
    if ((channel->time_us() - channel->close_start_us) >=
        channel->close_timeout_us)
        return close_fault(channel);

    switch (channel->close_state)
    {
    case C2837X_W5300_CLOSE_WAIT_EXISTING_CR:
        result = c2837x_w5300_socket_take_pending(&channel->socket);
        if (result < 0)
            return close_fault(channel);
        if (result > 0)
            channel->close_state = C2837X_W5300_CLOSE_CHECK_ERRATUM;
        return 0;

    case C2837X_W5300_CLOSE_CHECK_ERRATUM:
        result = c2837x_w5300_socket_check_close_erratum(&channel->socket,
                                                         &needed);
        if (result < 0)
            return close_fault(channel);
        if (result == 0)
            return 0;
        channel->close_state = needed ?
            C2837X_W5300_CLOSE_UDP_OPEN_ISSUE :
            C2837X_W5300_CLOSE_CLOSE_ISSUE;
        return 0;

    case C2837X_W5300_CLOSE_UDP_OPEN_ISSUE:
        if (c2837x_w5300_socket_issue_udp_open(
                &channel->socket, C2837X_W5300_ERRATUM_DUMMY_PORT) < 0)
            return close_fault(channel);
        channel->close_state = C2837X_W5300_CLOSE_UDP_OPEN_WAIT_CR;
        return 0;

    case C2837X_W5300_CLOSE_UDP_OPEN_WAIT_CR:
        result = c2837x_w5300_socket_poll_close_command(
            &channel->socket, C2837X_W5300_COMMAND_UDP_OPEN);
        if (result < 0)
            return close_fault(channel);
        if (result > 0)
            channel->close_state = C2837X_W5300_CLOSE_UDP_OPEN_WAIT_STATE;
        return 0;

    case C2837X_W5300_CLOSE_UDP_OPEN_WAIT_STATE:
        status = c2837x_w5300_get_sn_ssr(channel->socket.sn);
        if (status == SOCK_UDP)
        {
            if (c2837x_w5300_socket_complete_close_command(
                    &channel->socket, C2837X_W5300_COMMAND_UDP_OPEN) < 0)
                return close_fault(channel);
            channel->close_state = C2837X_W5300_CLOSE_DUMMY_WAIT_TX_SPACE;
        }
        else if (!c2837x_w5300_is_socket_status(status))
            return close_fault(channel);
        return 0;

    case C2837X_W5300_CLOSE_DUMMY_WAIT_TX_SPACE:
        result = c2837x_w5300_socket_dummy_tx_ready(&channel->socket);
        if (result < 0)
            return close_fault(channel);
        if (result > 0)
            channel->close_state = C2837X_W5300_CLOSE_DUMMY_SEND_ISSUE;
        return 0;

    case C2837X_W5300_CLOSE_DUMMY_SEND_ISSUE:
        if (c2837x_w5300_socket_issue_dummy_send(
                &channel->socket, C2837X_W5300_ERRATUM_DUMMY_IP,
                C2837X_W5300_ERRATUM_DUMMY_PORT) < 0)
            return close_fault(channel);
        channel->close_state = C2837X_W5300_CLOSE_DUMMY_SEND_WAIT_CR;
        return 0;

    case C2837X_W5300_CLOSE_DUMMY_SEND_WAIT_CR:
        result = c2837x_w5300_socket_poll_close_command(
            &channel->socket, C2837X_W5300_COMMAND_DUMMY_SEND);
        if (result < 0)
            return close_fault(channel);
        if (result > 0)
            channel->close_state = C2837X_W5300_CLOSE_DUMMY_SEND_WAIT_RESULT;
        return 0;

    case C2837X_W5300_CLOSE_DUMMY_SEND_WAIT_RESULT:
        status = c2837x_w5300_get_sn_ssr(channel->socket.sn);
        if (status == SOCK_CLOSED)
            return close_done(channel);
        if (!c2837x_w5300_is_socket_status(status))
            return close_fault(channel);
        ir = c2837x_w5300_get_sn_ir(channel->socket.sn);
        ir &= (Sn_IR_SENDOK | Sn_IR_TIMEOUT);
        if (ir != 0u)
        {
            c2837x_w5300_set_sn_ir(channel->socket.sn, ir);
            if (c2837x_w5300_socket_complete_close_command(
                    &channel->socket, C2837X_W5300_COMMAND_DUMMY_SEND) < 0)
                return close_fault(channel);
            channel->close_state = C2837X_W5300_CLOSE_CLOSE_ISSUE;
        }
        return 0;

    case C2837X_W5300_CLOSE_CLOSE_ISSUE:
        if (c2837x_w5300_socket_issue_close(&channel->socket) < 0)
            return close_fault(channel);
        channel->close_state = C2837X_W5300_CLOSE_CLOSE_WAIT_CR;
        return 0;

    case C2837X_W5300_CLOSE_CLOSE_WAIT_CR:
        result = c2837x_w5300_socket_poll_close_command(
            &channel->socket, C2837X_W5300_COMMAND_CLOSE);
        if (result < 0)
            return close_fault(channel);
        if (result > 0)
            channel->close_state = C2837X_W5300_CLOSE_CLOSE_WAIT_STATE;
        return 0;

    case C2837X_W5300_CLOSE_CLOSE_WAIT_STATE:
        status = c2837x_w5300_get_sn_ssr(channel->socket.sn);
        if (status == SOCK_CLOSED)
        {
            if (c2837x_w5300_socket_complete_close_command(
                    &channel->socket, C2837X_W5300_COMMAND_CLOSE) < 0)
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

const C2837xBlock_IoDeviceOps c2837x_w5300_iodevice_ops = {
    channel_init,
    open_channel,
    listen_channel,
    get_connection_state,
    receive,
    send,
    close_channel
};
