#ifndef C2837X_W5300_SOCKET_H
#define C2837X_W5300_SOCKET_H

/*
 * W5300 socket abstraction for C2837xBlock project.
 * Provides TCP stream send/recv without PIL packet-length semantics.
 * Run-reachable operations do bounded work per call. Platform initialization
 * retains the datasheet reset delays.
 */

#include "F28x_Project.h"
#include "c2837x_w5300_hal.h"

typedef enum {
    C2837X_W5300_COMMAND_NONE = 0,
    C2837X_W5300_COMMAND_OPEN,
    C2837X_W5300_COMMAND_LISTEN,
    C2837X_W5300_COMMAND_RECV,
    C2837X_W5300_COMMAND_SEND,
    C2837X_W5300_COMMAND_DISCONNECT,
    C2837X_W5300_COMMAND_CLOSE,
    C2837X_W5300_COMMAND_UDP_OPEN,
    C2837X_W5300_COMMAND_DUMMY_SEND
} C2837xW5300PendingCommand;

typedef enum {
    C2837X_W5300_COMMAND_PHASE_IDLE = 0,
    C2837X_W5300_COMMAND_PHASE_WAIT_CR_CLEAR,
    C2837X_W5300_COMMAND_PHASE_WAIT_TARGET_STATE
} C2837xW5300CommandPhase;

typedef struct {
    Uint16 sn;                    /* socket number (0-7) */
    Uint32 tx_mem_size;           /* TX buffer size in bytes */
    Uint32 rx_mem_size;           /* RX buffer size in bytes */
    C2837xW5300PendingCommand pending_command;
    C2837xW5300CommandPhase command_phase;
} C2837xW5300Socket;

#define C2837X_W5300_SOCKET_INITIALIZER(sn_, tx_, rx_) \
    { (sn_), (tx_), (rx_), C2837X_W5300_COMMAND_NONE, \
      C2837X_W5300_COMMAND_PHASE_IDLE }

/*
 * Open a socket with the given protocol, port, and flags.
 * Returns >0 when complete, 0 while advancing, negative on error.
 */
int16 c2837x_w5300_socket_open(C2837xW5300Socket* sk,
                                Uint16 protocol,
                                Uint16 port,
                                Uint16 flags);

/* Bounded primitives owned by the Channel close state machine. */
int16 c2837x_w5300_socket_take_pending(C2837xW5300Socket *sk);
int16 c2837x_w5300_socket_check_close_erratum(
    C2837xW5300Socket *sk, Uint16 *needed);
int16 c2837x_w5300_socket_dummy_tx_ready(C2837xW5300Socket *sk);
int16 c2837x_w5300_socket_issue_udp_open(C2837xW5300Socket *sk,
                                         Uint16 port);
int16 c2837x_w5300_socket_issue_dummy_send(C2837xW5300Socket *sk,
                                           Uint32 ip, Uint16 port);
int16 c2837x_w5300_socket_issue_close(C2837xW5300Socket *sk);
int16 c2837x_w5300_socket_poll_close_command(
    C2837xW5300Socket *sk, C2837xW5300PendingCommand expected);
int16 c2837x_w5300_socket_complete_close_command(
    C2837xW5300Socket *sk, C2837xW5300PendingCommand expected);

/*
 * Put socket into TCP LISTEN mode.
 * Socket must be in SOCK_INIT state.
 * Returns >0 when complete, 0 while advancing, negative on error.
 */
int16 c2837x_w5300_socket_listen(C2837xW5300Socket* sk);

/*
 * Send TCP data. Sends only what W5300 TX buffer can accept right now.
 * This is a raw TCP stream send — no packet-length prefix is added.
 * @param data_words  Pointer to DSP-native Uint16 array.
 * @param wire_byte_count  Number of wire bytes to send.
 * @return Bytes submitted to the W5300 FIFO and SEND command, 0 if no segment
 *         was submitted, negative on error. A positive value is only for the
 *         owning Channel to save as pending_octets; it is not IoDevice send
 *         progress and must not be returned directly to the Core.
 */
int32 c2837x_w5300_socket_send(C2837xW5300Socket* sk,
                                const Uint16* data_words,
                                Uint32 wire_byte_count);

/*
 * Advance only a pending SEND command by one Sn_CR read.
 * Returns >0 when no SEND command-register phase remains, 0 while Sn_CR is
 * nonzero, and negative for an invalid or conflicting command state.
 * This does not inspect SEND_OK/TIMEOUT or submit data.
 */
int16 c2837x_w5300_socket_advance_send_command(C2837xW5300Socket* sk);

/**
 * Disconnect a socket.
 * @param sk  Pointer to the socket structure.
 * @return >0 when SOCK_CLOSED is confirmed, 0 while advancing,
 *         negative on error.
 */
int16 c2837x_w5300_socket_disconnect(C2837xW5300Socket* sk);

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

#endif /* C2837X_W5300_SOCKET_H */
