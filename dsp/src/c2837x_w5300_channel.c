#include "c2837x_w5300_channel.h"
#include "c2837x_w5300_hal.h"

static void channel_init(void *channel_ref)
{
    C2837xW5300Channel *channel = (C2837xW5300Channel *)channel_ref;

    channel->connected = 0u;
    channel->socket.pending_command = C2837X_W5300_COMMAND_NONE;
    channel->send_state = C2837X_W5300_SEND_IDLE;
    channel->pending_octets = 0u;
    channel->closing = 0u;
    channel->faulted = 0u;
}

static int16 open_channel(void *channel_ref)
{
    C2837xW5300Channel *channel = (C2837xW5300Channel *)channel_ref;

    return c2837x_w5300_socket_open(&channel->socket, Sn_MR_TCP,
                                     channel->tcp_port, Sn_MR_ALIGN);
}

static int16 listen_channel(void *channel_ref)
{
    C2837xW5300Channel *channel = (C2837xW5300Channel *)channel_ref;

    return c2837x_w5300_socket_listen(&channel->socket);
}

static C2837xBlock_IoConnectionState get_connection_state(void *channel_ref)
{
    C2837xW5300Channel *channel = (C2837xW5300Channel *)channel_ref;
    Uint16 status;

    if (channel->faulted != 0u)
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

    count_octets &= ~1u;
    if (count_octets == 0u)
        return 0;
    /* S2-05 will use send_state/pending_octets to wait for SEND_OK. */
    return c2837x_w5300_socket_send(&channel->socket, data_words,
                                     count_octets);
}

static int16 close_channel(void *channel_ref)
{
    C2837xW5300Channel *channel = (C2837xW5300Channel *)channel_ref;
    int16 result;

    result = c2837x_w5300_socket_close(&channel->socket);
    if (result > 0)
    {
        channel->closing = 0u;
        return 1;
    }
    channel->closing = 1u;
    return result;
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
