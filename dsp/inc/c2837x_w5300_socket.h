#ifndef C2837X_W5300_SOCKET_H
#define C2837X_W5300_SOCKET_H

/*
 * W5300 socket abstraction for C2837xBlock project.
 * Provides TCP stream send/recv without PIL packet-length semantics.
 * All functions are non-blocking or short-timeout.
 */

#include "F28x_Project.h"
#include "c2837x_w5300_hal.h"

typedef struct {
    Uint16 sn;                    /* socket number (0-7) */
    Uint32 tx_mem_size;           /* TX buffer size in bytes */
    Uint32 rx_mem_size;           /* RX buffer size in bytes */
} C2837xW5300Socket;

/*
 * Open a socket with the given protocol, port, and flags.
 * Returns 0 on success, negative on error.
 */
int16 c2837x_w5300_socket_open(C2837xW5300Socket* sk,
                                Uint16 protocol,
                                Uint16 port,
                                Uint16 flags);

/*
 * Close a socket. Non-blocking: does not wait for TX buffer to drain.
 * Returns 0 on success, negative on error.
 */
int16 c2837x_w5300_socket_close(C2837xW5300Socket* sk);

/*
 * Put socket into TCP LISTEN mode.
 * Socket must be in SOCK_INIT state.
 * Returns 0 on success, negative on error.
 */
int16 c2837x_w5300_socket_listen(C2837xW5300Socket* sk);

/*
 * Send TCP data. Sends only what W5300 TX buffer can accept right now.
 * This is a raw TCP stream send — no packet-length prefix is added.
 * @param data_words  Pointer to DSP-native Uint16 array.
 * @param wire_byte_count  Number of wire bytes to send.
 * @return Wire bytes actually sent, 0 if TX buffer full or not connected,
 *         -1 on socket error.
 */
int32 c2837x_w5300_socket_send(C2837xW5300Socket* sk,
                                const Uint16* data_words,
                                Uint32 wire_byte_count);

/**
 * Disconnect a socket.
 * @param sk  Pointer to the socket structure.
 */
void c2837x_w5300_socket_disconnect(C2837xW5300Socket* sk);

/*
 * Receive TCP data. Reads whatever is available in the RX FIFO,
 * up to the caller's capacity. This is a raw TCP stream recv —
 * no packet-length prefix is consumed.
 * @param data_words  Destination DSP-native Uint16 array.
 * @param wire_capacity_bytes  Max wire bytes to receive.
 * @return Wire bytes received, 0 if none available or socket closed,
 *         -1 on socket error.
 */
int32 c2837x_w5300_socket_recv(C2837xW5300Socket* sk,
                                Uint16* data_words,
                                Uint32 wire_capacity_bytes);

/*
 * Get current socket status register value.
 */
static inline Uint16 c2837x_w5300_socket_get_status(const C2837xW5300Socket* sk)
{
    return c2837x_w5300_read8(Sn_SSR(sk->sn));
}

/*
 * Get TX free size in bytes.
 */
Uint32 c2837x_w5300_socket_get_tx_free(const C2837xW5300Socket* sk);

/*
 * Get RX received size in bytes.
 */
Uint32 c2837x_w5300_socket_get_rx_size(const C2837xW5300Socket* sk);

#endif /* C2837X_W5300_SOCKET_H */
