#ifndef C2837X_BLOCK_PC_SOCKET_H
#define C2837X_BLOCK_PC_SOCKET_H

/*
 * C2837xBlock PC Socket Abstraction
 * Cross-platform socket API for Windows and POSIX.
 *
 * Reference: MATLAB rtiostream_tcpip.c implementation.
 */

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ---- Socket type ---- */

typedef struct {
#ifdef _WIN32
    unsigned long long fd;  /* SOCKET on Windows (HANDLE-sized) */
#else
    int fd;
#endif
} c2837x_socket_t;

/* ---- Socket API ---- */

/*
 * Initialize socket library (Windows: WSAStartup).
 * Must be called once before any socket operations.
 * Returns 0 on success, -1 on failure.
 */
int c2837x_socket_init(void);

/*
 * Cleanup socket library (Windows: WSACleanup).
 * Called once at process exit.
 */
void c2837x_socket_cleanup(void);

/*
 * Connect to remote host with timeout.
 * - s: socket structure to initialize
 * - ip: IP address string (e.g., "192.168.1.100")
 * - port: TCP port number
 * - timeout_ms: connection timeout in milliseconds
 *
 * Returns 0 on success, -1 on failure/timeout.
 */
int c2837x_socket_connect(c2837x_socket_t* s,
                          const char* ip,
                          uint16_t port,
                          uint32_t timeout_ms);

/*
 * Send exactly 'length' bytes, blocking until all sent or timeout.
 * - s: connected socket
 * - data: data buffer to send
 * - length: number of bytes to send
 * - timeout_ms: send timeout in milliseconds
 *
 * Returns 0 on success, -1 on error/timeout.
 */
int c2837x_socket_send_all(c2837x_socket_t* s,
                           const uint8_t* data,
                           uint32_t length,
                           uint32_t timeout_ms);

/*
 * Receive exactly 'length' bytes, blocking until all received or timeout.
 * - s: connected socket
 * - data: receive buffer
 * - length: number of bytes to receive
 * - timeout_ms: receive timeout in milliseconds
 *
 * Returns 0 on success, -1 on error/timeout.
 */
int c2837x_socket_recv_exact(c2837x_socket_t* s,
                             uint8_t* data,
                             uint32_t length,
                             uint32_t timeout_ms);

/*
 * Close socket and invalidate.
 * - s: socket to close
 */
void c2837x_socket_close(c2837x_socket_t* s);

/*
 * Check if socket is valid (not closed).
 * Returns 1 if valid, 0 if invalid.
 */
int c2837x_socket_is_valid(const c2837x_socket_t* s);

#ifdef __cplusplus
}
#endif

#endif /* C2837X_BLOCK_PC_SOCKET_H */
