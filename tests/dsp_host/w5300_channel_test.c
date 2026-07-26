#include <assert.h>
#include "c2837x_w5300_channel.h"

static Uint16 socket_status[8];
static Uint16 open_calls[8];
static Uint16 listen_calls[8];
static Uint16 receive_calls[8];
static Uint16 send_calls[8];
static Uint16 close_calls[8];
static Uint16 disconnect_calls[8];
static Uint16 opened_port[8];
static Uint16 connection_clear_calls[8];
static Uint32 last_send_count;
static Uint32 last_receive_capacity;

Uint16 c2837x_w5300_read16(Uint32 address)
{
    Uint16 sn;
    for (sn = 0u; sn < 8u; sn++)
        if (address == Sn_SSR(sn))
            return socket_status[sn];
    return 0u;
}
void c2837x_w5300_write16(Uint32 address, Uint16 data)
{
    Uint16 sn;
    for (sn = 0u; sn < 8u; sn++)
        if ((address == Sn_IR(sn)) && (data == Sn_IR_CON))
            connection_clear_calls[sn]++;
}
int16 c2837x_w5300_socket_open(C2837xW5300Socket *socket, Uint16 protocol,
                               Uint16 port, Uint16 flags)
{
    (void)protocol; (void)flags;
    open_calls[socket->sn]++;
    opened_port[socket->sn] = port;
    return 0;
}
int16 c2837x_w5300_socket_listen(C2837xW5300Socket *socket)
{
    listen_calls[socket->sn]++;
    return 0;
}
int32 c2837x_w5300_socket_recv(C2837xW5300Socket *socket, Uint16 *data,
                               Uint32 capacity)
{
    (void)data;
    receive_calls[socket->sn]++;
    last_receive_capacity = capacity;
    return (int32)capacity;
}
int32 c2837x_w5300_socket_send(C2837xW5300Socket *socket,
                               const Uint16 *data, Uint32 count)
{
    (void)data;
    send_calls[socket->sn]++;
    last_send_count = count;
    return (int32)count;
}
int16 c2837x_w5300_socket_close(C2837xW5300Socket *socket)
{
    close_calls[socket->sn]++;
    return 0;
}
void c2837x_w5300_socket_disconnect(C2837xW5300Socket *socket)
{
    disconnect_calls[socket->sn]++;
}

int main(void)
{
    C2837xW5300Channel first = {
        {1u, 8192u, 8192u}, 5001u, 0u,
        C2837X_W5300_SEND_IDLE, 0u, 0u, 0u};
    C2837xW5300Channel second = {
        {6u, 8192u, 8192u}, 5006u, 0u,
        C2837X_W5300_SEND_IDLE, 0u, 0u, 0u};
    Uint16 words[4] = {0u};

    first.send_state = C2837X_W5300_SEND_PENDING;
    first.pending_octets = 8u;
    first.closing = 1u;
    first.faulted = 1u;
    second.send_state = C2837X_W5300_SEND_PENDING;
    second.pending_octets = 12u;
    second.closing = 1u;
    second.faulted = 1u;

    c2837x_w5300_iodevice_ops.channel_init(&first);
    assert(first.socket.sn == 1u && first.tcp_port == 5001u);
    assert(first.socket.tx_mem_size == 8192u && first.socket.rx_mem_size == 8192u);
    assert(first.connected == 0u);
    assert(first.send_state == C2837X_W5300_SEND_IDLE);
    assert(first.pending_octets == 0u && first.closing == 0u && first.faulted == 0u);
    assert(second.socket.sn == 6u && second.tcp_port == 5006u);
    assert(second.send_state == C2837X_W5300_SEND_PENDING);
    assert(second.pending_octets == 12u && second.closing == 1u && second.faulted == 1u);

    c2837x_w5300_iodevice_ops.channel_init(&second);
    socket_status[1] = SOCK_CLOSED;
    socket_status[6] = SOCK_INIT;
    assert(c2837x_w5300_iodevice_ops.get_connection_state(&first) ==
           C2837X_IODEVICE_CONNECTION_CLOSED);
    assert(c2837x_w5300_iodevice_ops.get_connection_state(&second) ==
           C2837X_IODEVICE_CONNECTION_OPEN);
    socket_status[6] = SOCK_LISTEN;
    assert(c2837x_w5300_iodevice_ops.get_connection_state(&second) ==
           C2837X_IODEVICE_CONNECTION_LISTENING);
    socket_status[6] = SOCK_CLOSE_WAIT;
    assert(c2837x_w5300_iodevice_ops.get_connection_state(&second) ==
           C2837X_IODEVICE_CONNECTION_PEER_CLOSED);
    socket_status[6] = 0xFFFFu;
    assert(c2837x_w5300_iodevice_ops.get_connection_state(&second) ==
           C2837X_IODEVICE_CONNECTION_ERROR);
    socket_status[6] = SOCK_INIT;

    socket_status[1] = SOCK_ESTABLISHED;
    assert(c2837x_w5300_iodevice_ops.get_connection_state(&first) ==
           C2837X_IODEVICE_CONNECTION_CONNECTED);
    assert(connection_clear_calls[1] == 1u && connection_clear_calls[6] == 0u);
    assert(c2837x_w5300_iodevice_ops.get_connection_state(&first) ==
           C2837X_IODEVICE_CONNECTION_CONNECTED);
    assert(connection_clear_calls[1] == 1u);
    socket_status[1] = SOCK_CLOSED;

    assert(c2837x_w5300_iodevice_ops.open(&first) == 0);
    assert(c2837x_w5300_iodevice_ops.listen(&second) == 0);
    assert(open_calls[1] == 1u && opened_port[1] == 5001u);
    assert(listen_calls[6] == 1u);
    assert(open_calls[6] == 0u && listen_calls[1] == 0u);

    assert(c2837x_w5300_iodevice_ops.receive(&first, words, 7u) == 6);
    assert(c2837x_w5300_iodevice_ops.send(&second, words, 7u) == 6);
    assert(last_receive_capacity == 6u && last_send_count == 6u);
    assert(receive_calls[1] == 1u && receive_calls[6] == 0u);
    assert(send_calls[6] == 1u && send_calls[1] == 0u);

    assert(c2837x_w5300_iodevice_ops.close(&first) > 0);
    socket_status[6] = SOCK_ESTABLISHED;
    assert(c2837x_w5300_iodevice_ops.close(&second) == 0);
    assert(close_calls[6] == 1u && close_calls[1] == 0u);
    assert(disconnect_calls[1] == 0u && disconnect_calls[6] == 0u);
    assert(second.closing == 1u && first.closing == 0u);
    return 0;
}
