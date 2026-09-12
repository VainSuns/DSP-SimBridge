#ifndef _WIN32
#ifndef _POSIX_C_SOURCE
#define _POSIX_C_SOURCE 200809L
#endif
#endif

#include "axis_alpha_pc_udp.h"

#ifdef _WIN32
#include <winsock2.h>
#include <ws2tcpip.h>
typedef SOCKET test_socket_t;
#define TEST_INVALID_SOCKET INVALID_SOCKET
#define TEST_SOCKET_ERROR SOCKET_ERROR
#define TEST_CLOSE_SOCKET(s_) closesocket(s_)
#else
#include <arpa/inet.h>
#include <errno.h>
#include <poll.h>
#include <sys/socket.h>
#include <unistd.h>
typedef int test_socket_t;
#define TEST_INVALID_SOCKET (-1)
#define TEST_SOCKET_ERROR (-1)
#define TEST_CLOSE_SOCKET(s_) close(s_)
#endif

#include <stdint.h>
#include <stdio.h>
#include <string.h>

static int check(int condition, const char *message)
{
    if (!condition) {
        fprintf(stderr, "FAIL %s\n", message);
        return 0;
    }
    return 1;
}

static test_socket_t native_socket(const AxisAlphaPcUdpSocket *socket)
{
    return (test_socket_t)socket->native_handle;
}

static int create_peer(test_socket_t *peer, uint16_t *port)
{
    struct sockaddr_in address;
    test_socket_t native;
#ifdef _WIN32
    int address_length;
#else
    socklen_t address_length;
#endif

    if (peer == NULL || port == NULL) return -1;
    native = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    if (native == TEST_INVALID_SOCKET) return -1;
    memset(&address, 0, sizeof(address));
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    address.sin_port = htons(0u);
    if (bind(native, (struct sockaddr *)&address, sizeof(address)) ==
            TEST_SOCKET_ERROR) {
        (void)TEST_CLOSE_SOCKET(native);
        return -1;
    }
    address_length = (int)sizeof(address);
    if (getsockname(native, (struct sockaddr *)&address, &address_length) ==
            TEST_SOCKET_ERROR) {
        (void)TEST_CLOSE_SOCKET(native);
        return -1;
    }
    *peer = native;
    *port = ntohs(address.sin_port);
    return 0;
}

static int receive_datagram(test_socket_t peer, uint8_t *buffer,
    size_t capacity)
{
#ifdef _WIN32
    int result;
#else
    int result;
#endif
#ifdef _WIN32
    fd_set read_set;
    struct timeval timeout;
    FD_ZERO(&read_set);
    FD_SET(peer, &read_set);
    timeout.tv_sec = 1;
    timeout.tv_usec = 0;
    result = select(0, &read_set, NULL, NULL, &timeout);
#else
    struct pollfd descriptor;
    descriptor.fd = peer;
    descriptor.events = POLLIN;
    descriptor.revents = 0;
    result = poll(&descriptor, 1, 1000);
#endif
    if (result != 1) return -1;
    return (int)recv(peer, (char *)buffer, (int)capacity, 0);
}

static int has_datagram(test_socket_t peer)
{
    uint8_t byte;
#ifdef _WIN32
    int result;
    fd_set read_set;
    struct timeval timeout;
    FD_ZERO(&read_set);
    FD_SET(peer, &read_set);
    timeout.tv_sec = 0;
    timeout.tv_usec = 0;
    result = select(0, &read_set, NULL, NULL, &timeout);
#else
    int result;
    struct pollfd descriptor;
    descriptor.fd = peer;
    descriptor.events = POLLIN;
    descriptor.revents = 0;
    result = poll(&descriptor, 1, 0);
#endif
    if (result != 1) return 0;
    return recv(peer, (char *)&byte, 1, MSG_PEEK) > 0;
}

static uint16_t local_port(const AxisAlphaPcUdpSocket *socket)
{
    struct sockaddr_in address;
#ifdef _WIN32
    int address_length = (int)sizeof(address);
#else
    socklen_t address_length = (socklen_t)sizeof(address);
#endif
    memset(&address, 0, sizeof(address));
    if (getsockname(native_socket(socket), (struct sockaddr *)&address,
            &address_length) == TEST_SOCKET_ERROR) return 0u;
    return ntohs(address.sin_port);
}

int main(void)
{
    static const uint8_t frame[] = {0x01u, 0x00u, 0x04u, 0x00u,
        0xa1u, 0xb2u, 0xc3u, 0xd4u};
    uint8_t received[sizeof(frame)] = {0u};
    AxisAlphaPcUdpSocket client;
    AxisAlphaPcUdpDeadline deadline;
    AxisAlphaPcError error;
    test_socket_t peer = TEST_INVALID_SOCKET;
    uint16_t peer_port = 0u;
    int received_length;
    int status = 1;

    memset(&client, 0, sizeof(client));
    if (!check(axis_alpha_pc_udp_init(&client, &error) == 0,
            "UDP init")) goto cleanup;
    if (!check(create_peer(&peer, &peer_port) == 0 && peer_port != 0u,
            "ephemeral peer setup")) goto cleanup;
    if (!check(axis_alpha_pc_udp_connect(&client, "127.0.0.1", peer_port,
            0u, &error) == 0, "UDP endpoint connect")) goto cleanup;
    if (!check(axis_alpha_pc_udp_is_valid(&client),
            "connected UDP socket is valid")) goto cleanup;
    if (!check(local_port(&client) != 0u,
            "PC source port is OS-assigned and nonzero")) goto cleanup;
    if (!check(axis_alpha_pc_udp_send_datagram(&client, frame, sizeof(frame),
            1000u, &error) == 0, "one complete datagram send")) goto cleanup;
    if (!check(client.last_transfer_count == sizeof(frame),
            "successful send reports complete frame")) goto cleanup;
    received_length = receive_datagram(peer, received, sizeof(received));
    if (!check(received_length == (int)sizeof(frame) &&
            memcmp(received, frame, sizeof(frame)) == 0,
            "peer receives one complete datagram")) goto cleanup;
    if (!check(!has_datagram(peer),
            "one frame does not create a second datagram")) goto cleanup;

    client.native_handle = (uintptr_t)TEST_INVALID_SOCKET;
    if (!check(axis_alpha_pc_udp_send_datagram(&client, frame, sizeof(frame),
            1000u, &error) == -1 &&
            error.kind == C2837X_PC_ERROR_SOCKET,
            "explicit socket failure maps to SOCKET")) goto cleanup;
    if (!check(!axis_alpha_pc_udp_is_valid(&client),
            "socket failure closes and invalidates socket")) goto cleanup;

    if (!check(axis_alpha_pc_udp_connect(&client, "127.0.0.1", peer_port,
            1000u, &error) == 0, "UDP reconnect for deadline test")) goto cleanup;
    if (!check(axis_alpha_pc_udp_deadline_start(&client, 0u, &deadline,
            &error) == 0, "expired deadline setup")) goto cleanup;
    if (!check(axis_alpha_pc_udp_send_datagram_until(&client, frame,
            sizeof(frame), &deadline, &error) == -1 &&
            error.kind == C2837X_PC_ERROR_TIMEOUT,
            "expired deadline maps to TIMEOUT")) goto cleanup;
    if (!check(!has_datagram(peer),
            "expired deadline does not send a datagram")) goto cleanup;

    status = 0;

cleanup:
    if (peer != TEST_INVALID_SOCKET) (void)TEST_CLOSE_SOCKET(peer);
    axis_alpha_pc_udp_cleanup(&client);
    axis_alpha_pc_udp_cleanup(&client);
    if (status == 0 && !check(!axis_alpha_pc_udp_is_valid(&client),
            "cleanup invalidates UDP socket")) status = 1;
    if (status == 0) {
        printf("SUMMARY passed=8 failed=0\n");
    }
    return status;
}
