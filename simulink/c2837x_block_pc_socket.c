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

    /* Connect */
    if (connect(cSock, (struct sockaddr*)&sa, sizeof(sa)) == SOCK_ERR) {
        close(cSock);
        return -1;
    }

    /* Set socket options */
    {
        /* Set send buffer size */
        int bufSize = 65536;
        setsockopt(cSock, SOL_SOCKET, SO_SNDBUF, (char*)&bufSize, sizeof(bufSize));

        /* Set receive buffer size */
        setsockopt(cSock, SOL_SOCKET, SO_RCVBUF, (char*)&bufSize, sizeof(bufSize));
    }

    s->fd = cSock;
    (void)timeout_ms; /* timeout not used for blocking connect */
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

    (void)timeout_ms; /* Blocking send, timeout not implemented */
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
        /* Check for data pending using select/poll */
#ifdef _WIN32
        {
            fd_set ReadFds;
            struct timeval tval;
            int pending;

            FD_ZERO(&ReadFds);
            FD_SET((SOCKET)s->fd, &ReadFds);

            tval.tv_sec = timeout_ms / 1000;
            tval.tv_usec = (timeout_ms % 1000) * 1000;

            pending = select((int)((SOCKET)s->fd + 1), &ReadFds, NULL, NULL, &tval);
            if (pending == SOCKET_ERROR || pending == 0) {
                return -1; /* Error or timeout */
            }
        }
#else
        {
            struct pollfd pfd;
            int pending;

            pfd.fd = (int)s->fd;
            pfd.events = POLLIN;
            pfd.revents = 0;

            pending = poll(&pfd, 1, (int)timeout_ms);
            if (pending <= 0 || (pfd.revents & POLLERR)) {
                return -1; /* Error or timeout */
            }
        }
#endif

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
