/*
 * C2837xBlock PC Socket Implementation
 * Cross-platform socket API for Windows and POSIX.
 *
 * Reference: MATLAB rtiostream_tcpip.c implementation.
 */

#include "c2837x_block_pc_socket.h"

#ifdef _WIN32
/* Windows - use winsock.h like MATLAB does */
#include <windows.h>
#include <winsock.h>
#define close closesocket
#define SOCK_ERR SOCKET_ERROR
#define RTIOSTREAM_ECONNRESET WSAECONNRESET
#define GET_SOCK_ERROR() WSAGetLastError()
#define WOULD_BLOCK(err) ((err) == WSAEWOULDBLOCK)
#else
/* POSIX socket */
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/poll.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <arpa/inet.h>
#include <netdb.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
#define INVALID_SOCKET (-1)
#define SOCK_ERR (-1)
#define RTIOSTREAM_ECONNRESET ECONNRESET
typedef int SOCKET;
#define GET_SOCK_ERROR() errno
#define WOULD_BLOCK(err) ((err) == EAGAIN || (err) == EWOULDBLOCK)
#endif

#include <string.h>
#include <limits.h>

/* MIN utility */
#ifndef MIN
#define MIN(a,b) ((a) < (b) ? (a) : (b))
#endif

/* ---- Platform-specific types ---- */

#if defined(_WIN32)
typedef const char * send_buffer_t;
typedef int socklen_t;
#else
typedef const void * send_buffer_t;
#endif

/* ---- Helper functions ---- */

static void set_nonblocking(SOCKET sock, int enable)
{
#ifdef _WIN32
    u_long mode = enable ? 1 : 0;
    ioctlsocket(sock, FIONBIO, &mode);
#else
    int flags = fcntl(sock, F_GETFL, 0);
    if (flags < 0) return;
    if (enable) {
        fcntl(sock, F_SETFL, flags | O_NONBLOCK);
    } else {
        fcntl(sock, F_SETFL, flags & ~O_NONBLOCK);
    }
#endif
}

static int wait_writable(SOCKET sock, uint32_t timeout_ms)
{
#ifdef _WIN32
    fd_set write_fds;
    struct timeval tv;
    int result;

    FD_ZERO(&write_fds);
    FD_SET(sock, &write_fds);

    tv.tv_sec = timeout_ms / 1000u;
    tv.tv_usec = (timeout_ms % 1000u) * 1000u;

    result = select(0, NULL, &write_fds, NULL, &tv);
    return (result > 0) ? 0 : -1;
#else
    struct pollfd pfd;
    int result;

    pfd.fd = sock;
    pfd.events = POLLOUT;
    pfd.revents = 0;

    result = poll(&pfd, 1, (int)timeout_ms);
    return (result > 0 && (pfd.revents & POLLOUT)) ? 0 : -1;
#endif
}

static int wait_readable(SOCKET sock, uint32_t timeout_ms)
{
#ifdef _WIN32
    fd_set read_fds;
    struct timeval tv;
    int result;

    FD_ZERO(&read_fds);
    FD_SET(sock, &read_fds);

    tv.tv_sec = timeout_ms / 1000u;
    tv.tv_usec = (timeout_ms % 1000u) * 1000u;

    result = select(0, &read_fds, NULL, NULL, &tv);
    return (result > 0) ? 0 : -1;
#else
    struct pollfd pfd;
    int result;

    pfd.fd = sock;
    pfd.events = POLLIN;
    pfd.revents = 0;

    result = poll(&pfd, 1, (int)timeout_ms);
    return (result > 0 && (pfd.revents & POLLIN)) ? 0 : -1;
#endif
}

/* ---- Socket API implementation ---- */

int c2837x_socket_init(void)
{
#ifdef _WIN32
    WSADATA data;
    if (WSAStartup(MAKEWORD(1, 1), &data)) {
        return -1;
    }
#endif
    return 0;
}

void c2837x_socket_cleanup(void)
{
#ifdef _WIN32
    WSACleanup();
#endif
}

int c2837x_socket_connect(c2837x_socket_t* s,
                          const char* ip,
                          uint16_t port,
                          uint32_t timeout_ms)
{
    struct sockaddr_in sa;
    SOCKET cSock;
    int errStatus = 0;

    if (s == NULL || ip == NULL) {
        return -1;
    }

    /* Initialize socket as invalid */
    s->fd = INVALID_SOCKET;

    /* Use inet_addr like MATLAB does (not inet_pton) */
    sa.sin_addr.s_addr = inet_addr(ip);
    if (sa.sin_addr.s_addr == INADDR_NONE) {
        return -1;
    }

    sa.sin_family = AF_INET;
    sa.sin_port = htons((unsigned short)port);

    /* Create TCP socket */
    cSock = socket(PF_INET, SOCK_STREAM, 0);
    if (cSock == INVALID_SOCKET) {
        return -1;
    }

    /* Set TCP_NODELAY for low latency */
    {
        int option = 1;
        setsockopt(cSock, IPPROTO_TCP, TCP_NODELAY, (char*)&option, sizeof(option));
    }

    /* Set non-blocking for connect with timeout */
    set_nonblocking(cSock, 1);

    /* Initiate non-blocking connect */
    if (connect(cSock, (struct sockaddr*)&sa, sizeof(sa)) == SOCK_ERR) {
        int err = GET_SOCK_ERROR();
        if (!WOULD_BLOCK(err)) {
            close(cSock);
            return -1;
        }

        /* Wait for connect to complete with timeout */
        if (wait_writable(cSock, timeout_ms) != 0) {
            close(cSock);
            return -1;
        }

        /* Check if connect succeeded */
        {
            int sock_err = 0;
            socklen_t err_len = sizeof(sock_err);
            if (getsockopt(cSock, SOL_SOCKET, SO_ERROR, (char*)&sock_err, &err_len) != 0 ||
                sock_err != 0) {
                close(cSock);
                return -1;
            }
        }
    }

    /* Set back to blocking mode */
    set_nonblocking(cSock, 0);

    /* Set socket options */
    {
        /* Set send buffer size */
        int bufSize = 65536;
        setsockopt(cSock, SOL_SOCKET, SO_SNDBUF, (char*)&bufSize, sizeof(bufSize));

        /* Set receive buffer size */
        setsockopt(cSock, SOL_SOCKET, SO_RCVBUF, (char*)&bufSize, sizeof(bufSize));
    }

    s->fd = cSock;
    return 0;
}

int c2837x_socket_send_all(c2837x_socket_t* s,
                           const uint8_t* data,
                           uint32_t length,
                           uint32_t timeout_ms)
{
    uint32_t totalSent = 0;
    int sizeLim;
    int nSent;

    if (s == NULL || data == NULL) {
        return -1;
    }

    while (totalSent < length) {
        /* Wait for socket to be writable with timeout */
        if (wait_writable((SOCKET)s->fd, timeout_ms) != 0) {
            return -1; /* Timeout or error */
        }

        /* Ensure size is not out of range for socket API send function */
        sizeLim = (int)MIN(length - totalSent, INT_MAX);

        nSent = (int)send((SOCKET)s->fd, (send_buffer_t)(data + totalSent), (size_t)sizeLim, 0);
        if (nSent == SOCK_ERR) {
#ifdef _WIN32
            if (WSAGetLastError() == WSAEWOULDBLOCK) {
#else
            if (errno == EAGAIN || errno == EWOULDBLOCK) {
#endif
                /* Would block, try again */
                continue;
            }
            return -1;
        }

        if (nSent == 0) {
            return -1; /* Connection closed */
        }

        totalSent += (uint32_t)nSent;
    }

    return 0;
}

int c2837x_socket_recv_exact(c2837x_socket_t* s,
                             uint8_t* data,
                             uint32_t length,
                             uint32_t timeout_ms)
{
    uint32_t totalRecvd = 0;
    int sizeLim;
    int nRead;

    if (s == NULL || data == NULL) {
        return -1;
    }

    while (totalRecvd < length) {
        /* Wait for data to be available with timeout */
        if (wait_readable((SOCKET)s->fd, timeout_ms) != 0) {
            return -1; /* Timeout or error */
        }

        /* Ensure size is not out of range for socket API recv function */
        sizeLim = (int)MIN(length - totalRecvd, INT_MAX);

        nRead = (int)recv((SOCKET)s->fd, (char*)(data + totalRecvd), (size_t)sizeLim, 0);
        if (nRead == SOCK_ERR) {
#ifdef _WIN32
            if (WSAGetLastError() == WSAEWOULDBLOCK) {
#else
            if (errno == EAGAIN || errno == EWOULDBLOCK) {
#endif
                continue;
            }
            return -1;
        }

        if (nRead == 0) {
            return -1; /* Connection closed by remote */
        }

        totalRecvd += (uint32_t)nRead;
    }

    return 0;
}

void c2837x_socket_close(c2837x_socket_t* s)
{
    if (s != NULL && s->fd != INVALID_SOCKET) {
        close((SOCKET)s->fd);
        s->fd = INVALID_SOCKET;
    }
}

int c2837x_socket_is_valid(const c2837x_socket_t* s)
{
    return (s != NULL && s->fd != INVALID_SOCKET) ? 1 : 0;
}
