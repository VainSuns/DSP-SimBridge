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

static int send_datagram(test_socket_t peer, uint16_t port,
    const uint8_t *data, size_t length)
{
    struct sockaddr_in address;
    int count;
    if (data == NULL && length != 0u) return -1;
    memset(&address, 0, sizeof(address));
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    address.sin_port = htons(port);
    count = (int)sendto(peer, (const char *)data, (int)length, 0,
        (struct sockaddr *)&address, (int)sizeof(address));
    return count == (int)length ? 0 : -1;
}

static int connect_receiver(AxisAlphaPcUdpSocket *client,
    test_socket_t peer, uint16_t peer_port, AxisAlphaPcError *error)
{
    (void)peer;
    if (axis_alpha_pc_udp_connect(client, "127.0.0.1", peer_port,
            1000u, error) != 0) return -1;
    return local_port(client) != 0u ? 0 : -1;
}

static int error_has_lengths(const AxisAlphaPcError *error,
    const char *stage, uint16_t expected, uint16_t actual)
{
    return error != NULL && error->stage != NULL && stage != NULL &&
        strcmp(error->stage, stage) == 0 &&
        (error->available & C2837X_PC_ERROR_HAS_EXPECTED_LENGTH) != 0u &&
        (error->available & C2837X_PC_ERROR_HAS_ACTUAL_LENGTH) != 0u &&
        error->expected_length == expected && error->actual_length == actual;
}

static int test_zero_payload(AxisAlphaPcUdpSocket *client,
    test_socket_t peer, uint16_t peer_port, AxisAlphaPcError *error)
{
    static const uint8_t frame[] = {0x34u, 0x12u, 0x00u, 0x00u};
    uint8_t header[sizeof(frame)] = {0u};
    if (!check(connect_receiver(client, peer, peer_port, error) == 0,
            "zero-payload receiver setup")) return 0;
    if (!check(send_datagram(peer, local_port(client), frame, sizeof(frame)) ==
            0, "zero-payload datagram send")) return 0;
    if (!check(axis_alpha_pc_udp_recv_exact(client, header, sizeof(header),
            1000u, error) == 0 && memcmp(header, frame, sizeof(frame)) == 0,
            "exact four-byte zero-payload header")) return 0;
    return check(client->last_transfer_count == sizeof(frame) &&
            !client->datagram_staged && client->datagram_length == 0u,
        "zero-payload header clears staging without second receive");
}

static int test_zero_payload_with_extra_bytes(AxisAlphaPcUdpSocket *client,
    test_socket_t peer, uint16_t peer_port, AxisAlphaPcError *error)
{
    static const uint8_t datagram[] = {0x34u, 0x12u, 0x00u, 0x00u,
        0xa1u};
    uint8_t header[4] = {0u};
    if (!check(connect_receiver(client, peer, peer_port, error) == 0,
            "zero-payload-extra receiver setup")) return 0;
    if (!check(send_datagram(peer, local_port(client), datagram,
            sizeof(datagram)) == 0,
            "zero-payload-extra datagram send")) return 0;
    if (!check(axis_alpha_pc_udp_recv_exact(client, header, sizeof(header),
            1000u, error) == -1 &&
            error->kind == C2837X_PC_ERROR_PAYLOAD_LENGTH &&
            error_has_lengths(error, "recv_payload", 0u, 1u),
            "extra bytes on zero-payload datagram map to payload_length")) {
        return 0;
    }
    return check(!client->datagram_staged &&
            !axis_alpha_pc_udp_is_valid(client),
        "zero-payload-extra error clears staging and closes socket");
}

static int test_max_legal_datagram(AxisAlphaPcUdpSocket *client,
    test_socket_t peer, uint16_t peer_port, AxisAlphaPcError *error)
{
    uint8_t frame[AXIS_ALPHA_PC_UDP_MAX_DATAGRAM_SIZE];
    uint8_t header[4] = {0u};
    uint8_t payload[1468u] = {0u};
    size_t index;
    frame[0] = 0x99u;
    frame[1] = 0x88u;
    frame[2] = 0xbcu;
    frame[3] = 0x05u;
    for (index = 4u; index < sizeof(frame); ++index) {
        frame[index] = (uint8_t)(index * 3u + 1u);
    }
    if (!check(connect_receiver(client, peer, peer_port, error) == 0,
            "maximum legal receiver setup")) return 0;
    if (!check(send_datagram(peer, local_port(client), frame, sizeof(frame)) ==
            0, "maximum legal datagram send")) return 0;
    if (!check(axis_alpha_pc_udp_recv_exact(client, header, sizeof(header),
            1000u, error) == 0 && memcmp(header, frame, sizeof(header)) == 0 &&
            client->datagram_staged && client->datagram_length ==
                AXIS_ALPHA_PC_UDP_MAX_DATAGRAM_SIZE,
            "1472-byte datagram is staged as legal")) return 0;
    if (!check(axis_alpha_pc_udp_recv_exact(client, payload, sizeof(payload),
            1000u, error) == 0 && memcmp(payload, frame + 4u,
                sizeof(payload)) == 0, "maximum legal payload delivery")) {
        return 0;
    }
    return check(!client->datagram_staged &&
            client->last_transfer_count == sizeof(payload),
        "maximum legal datagram clears after payload");
}

static int test_normal_staging(AxisAlphaPcUdpSocket *client,
    test_socket_t peer, uint16_t peer_port, AxisAlphaPcError *error)
{
    static const uint8_t frame[] = {0x9au, 0x88u, 0x04u, 0x00u,
        0xa1u, 0xb2u, 0xc3u, 0xd4u};
    uint8_t header[4] = {0u};
    uint8_t payload[4] = {0u};
    if (!check(connect_receiver(client, peer, peer_port, error) == 0,
            "normal receiver setup")) return 0;
    if (!check(send_datagram(peer, local_port(client), frame, sizeof(frame)) ==
            0, "normal datagram send")) return 0;
    if (!check(axis_alpha_pc_udp_recv_exact(client, header, sizeof(header),
            1000u, error) == 0 && memcmp(header, frame, sizeof(header)) == 0 &&
            client->datagram_staged && client->datagram_offset == 4u &&
            client->datagram_payload_length == sizeof(payload),
            "header returns only four staged octets")) return 0;
    if (!check(axis_alpha_pc_udp_recv_exact(client, payload, sizeof(payload),
            1000u, error) == 0 && memcmp(payload, frame + 4u,
                sizeof(payload)) == 0, "payload returns from same datagram")) {
        return 0;
    }
    return check(!client->datagram_staged &&
            client->last_transfer_count == sizeof(payload),
        "normal payload clears staging");
}

static int test_short_header(AxisAlphaPcUdpSocket *client,
    test_socket_t peer, uint16_t peer_port, AxisAlphaPcError *error)
{
    static const uint8_t datagram[] = {0x01u, 0x02u, 0x03u};
    uint8_t header[4] = {0u};
    if (!check(connect_receiver(client, peer, peer_port, error) == 0,
            "short-header receiver setup")) return 0;
    if (!check(send_datagram(peer, local_port(client), datagram,
            sizeof(datagram)) == 0, "short-header datagram send")) return 0;
    if (!check(axis_alpha_pc_udp_recv_exact(client, header, sizeof(header),
            1000u, error) == -1 &&
            error->kind == C2837X_PC_ERROR_TRUNCATED &&
            error_has_lengths(error, "recv_header", 4u, 3u),
            "short header maps to truncated recv_header")) return 0;
    return check(!client->datagram_staged &&
            !axis_alpha_pc_udp_is_valid(client),
        "short header clears staging and closes socket");
}

static int test_short_declared_payload(AxisAlphaPcUdpSocket *client,
    test_socket_t peer, uint16_t peer_port, AxisAlphaPcError *error)
{
    static const uint8_t datagram[] = {0x01u, 0x00u, 0x04u, 0x00u,
        0xa1u, 0xb2u};
    uint8_t header[4] = {0u};
    uint8_t payload[4] = {0u};
    if (!check(connect_receiver(client, peer, peer_port, error) == 0,
            "short-payload receiver setup")) return 0;
    if (!check(send_datagram(peer, local_port(client), datagram,
            sizeof(datagram)) == 0, "short-payload datagram send")) return 0;
    if (!check(axis_alpha_pc_udp_recv_exact(client, header, sizeof(header),
            1000u, error) == 0, "short-payload header delivery")) return 0;
    if (!check(axis_alpha_pc_udp_recv_exact(client, payload, sizeof(payload),
            1000u, error) == -1 &&
            error->kind == C2837X_PC_ERROR_TRUNCATED &&
            error_has_lengths(error, "recv_payload", 4u, 2u),
            "short physical payload maps to truncated recv_payload")) return 0;
    return check(!client->datagram_staged &&
            !axis_alpha_pc_udp_is_valid(client),
        "short payload clears staging and closes socket");
}

static int test_long_declared_payload(AxisAlphaPcUdpSocket *client,
    test_socket_t peer, uint16_t peer_port, AxisAlphaPcError *error)
{
    static const uint8_t datagram[] = {0x01u, 0x00u, 0x02u, 0x00u,
        0xa1u, 0xb2u, 0xc3u, 0xd4u};
    uint8_t header[4] = {0u};
    uint8_t payload[2] = {0u};
    if (!check(connect_receiver(client, peer, peer_port, error) == 0,
            "long-payload receiver setup")) return 0;
    if (!check(send_datagram(peer, local_port(client), datagram,
            sizeof(datagram)) == 0, "long-payload datagram send")) return 0;
    if (!check(axis_alpha_pc_udp_recv_exact(client, header, sizeof(header),
            1000u, error) == 0, "long-payload header delivery")) return 0;
    if (!check(axis_alpha_pc_udp_recv_exact(client, payload, sizeof(payload),
            1000u, error) == -1 &&
            error->kind == C2837X_PC_ERROR_PAYLOAD_LENGTH &&
            error_has_lengths(error, "recv_payload", 2u, 4u),
            "long physical payload maps to payload_length recv_payload")) {
        return 0;
    }
    return check(!client->datagram_staged &&
            !axis_alpha_pc_udp_is_valid(client),
        "long payload clears staging and closes socket");
}

static int test_oversize_datagram(AxisAlphaPcUdpSocket *client,
    test_socket_t peer, uint16_t peer_port, AxisAlphaPcError *error)
{
    static uint8_t datagram[AXIS_ALPHA_PC_UDP_STAGING_CAPACITY + 1u];
    uint8_t header[4] = {0u};
    size_t index;
    for (index = 0u; index < sizeof(datagram); ++index) {
        datagram[index] = 0x5au;
    }
    datagram[0] = 0x01u;
    datagram[1] = 0x00u;
    datagram[2] = 0x00u;
    datagram[3] = 0x00u;
    if (!check(connect_receiver(client, peer, peer_port, error) == 0,
            "oversize receiver setup")) return 0;
    if (!check(send_datagram(peer, local_port(client), datagram,
            sizeof(datagram)) == 0, "oversize datagram send")) return 0;
    if (!check(axis_alpha_pc_udp_recv_exact(client, header, sizeof(header),
            1000u, error) == -1 &&
            error->kind == C2837X_PC_ERROR_PAYLOAD_LENGTH &&
            error_has_lengths(error, "recv_header",
                AXIS_ALPHA_PC_UDP_MAX_DATAGRAM_SIZE,
                AXIS_ALPHA_PC_UDP_STAGING_CAPACITY),
            "oversize datagram maps to existing framing error")) return 0;
    return check(!client->datagram_staged &&
            !axis_alpha_pc_udp_is_valid(client),
        "oversize datagram clears staging and closes socket");
}

static int test_no_cross_datagram(AxisAlphaPcUdpSocket *client,
    test_socket_t peer, uint16_t peer_port, AxisAlphaPcError *error)
{
    static const uint8_t first[] = {0x01u, 0x00u, 0x04u, 0x00u,
        0xa1u, 0xb2u};
    static const uint8_t second[] = {0xc3u, 0xd4u, 0xe5u, 0xf6u};
    uint8_t header[4] = {0u};
    uint8_t payload[4] = {0u};
    uint16_t port;
    if (!check(connect_receiver(client, peer, peer_port, error) == 0,
            "no-cross receiver setup")) return 0;
    port = local_port(client);
    if (!check(send_datagram(peer, port, first, sizeof(first)) == 0 &&
            send_datagram(peer, port, second, sizeof(second)) == 0,
            "queue short datagram followed by second datagram")) return 0;
    if (!check(axis_alpha_pc_udp_recv_exact(client, header, sizeof(header),
            1000u, error) == 0, "no-cross first header delivery")) return 0;
    if (!check(axis_alpha_pc_udp_recv_exact(client, payload, sizeof(payload),
            1000u, error) == -1 &&
            error->kind == C2837X_PC_ERROR_TRUNCATED &&
            error_has_lengths(error, "recv_payload", 4u, 2u),
            "short first datagram is not completed from next datagram")) {
        return 0;
    }
    return check(!client->datagram_staged &&
            !axis_alpha_pc_udp_is_valid(client),
        "no-cross error clears first datagram staging");
}

static int test_absolute_deadline_continuity(AxisAlphaPcUdpSocket *client,
    test_socket_t peer, uint16_t peer_port, AxisAlphaPcError *error)
{
    static const uint8_t datagram[] = {0x01u, 0x00u, 0x02u, 0x00u,
        0xa1u, 0xb2u};
    uint8_t header[4] = {0u};
    uint8_t payload[2] = {0u};
    AxisAlphaPcUdpDeadline deadline;
    if (!check(connect_receiver(client, peer, peer_port, error) == 0,
            "deadline-continuity receiver setup")) return 0;
    if (!check(send_datagram(peer, local_port(client), datagram,
            sizeof(datagram)) == 0, "deadline-continuity datagram send")) {
        return 0;
    }
    if (!check(axis_alpha_pc_udp_deadline_start(client, 1000u, &deadline,
            error) == 0, "one receive operation deadline setup")) return 0;
    if (!check(axis_alpha_pc_udp_recv_exact_until(client, header, sizeof(header),
            &deadline, error) == 0, "header uses operation deadline")) {
        return 0;
    }
    deadline.expires_at_ms = 0u;
    if (!check(axis_alpha_pc_udp_recv_exact_until(client, payload, sizeof(payload),
            &deadline, error) == -1 &&
            error->kind == C2837X_PC_ERROR_TIMEOUT &&
            strcmp(error->stage, "recv_payload") == 0,
            "payload honors the same expired absolute deadline")) return 0;
    return check(!client->datagram_staged &&
            !axis_alpha_pc_udp_is_valid(client),
        "deadline failure clears staging and closes socket");
}

static int test_readable_timeout(AxisAlphaPcUdpSocket *client,
    test_socket_t peer, uint16_t peer_port, AxisAlphaPcError *error)
{
    uint8_t header[4] = {0u};
    if (!check(connect_receiver(client, peer, peer_port, error) == 0,
            "readable-timeout receiver setup")) return 0;
    if (!check(axis_alpha_pc_udp_recv_exact(client, header, sizeof(header),
            20u, error) == -1 && error->kind == C2837X_PC_ERROR_TIMEOUT &&
            strcmp(error->stage, "recv_header") == 0,
            "readable wait timeout maps to recv_header TIMEOUT")) return 0;
    return check(!client->datagram_staged &&
            !axis_alpha_pc_udp_is_valid(client),
        "readable timeout clears staging and closes socket");
}

static int test_receive_socket_failure(AxisAlphaPcUdpSocket *client,
    test_socket_t peer, uint16_t peer_port, AxisAlphaPcError *error)
{
    uint8_t header[4] = {0u};
    if (!check(connect_receiver(client, peer, peer_port, error) == 0,
            "receive-error receiver setup")) return 0;
    client->native_handle = (uintptr_t)TEST_INVALID_SOCKET;
    if (!check(axis_alpha_pc_udp_recv_exact(client, header, sizeof(header),
            1000u, error) == -1 &&
            error->kind == C2837X_PC_ERROR_SOCKET,
            "explicit receive socket failure maps to SOCKET")) return 0;
    return check(!client->datagram_staged &&
            !axis_alpha_pc_udp_is_valid(client),
        "receive socket failure clears staging and closes socket");
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

    if (!test_zero_payload(&client, peer, peer_port, &error)) goto cleanup;
    printf("PASS zero_payload\n");
    if (!test_zero_payload_with_extra_bytes(&client, peer, peer_port,
            &error)) goto cleanup;
    printf("PASS zero_payload_with_extra_bytes\n");
    if (!test_max_legal_datagram(&client, peer, peer_port, &error)) {
        goto cleanup;
    }
    printf("PASS max_legal_datagram\n");
    if (!test_normal_staging(&client, peer, peer_port, &error)) goto cleanup;
    printf("PASS normal_staging\n");
    if (!test_short_header(&client, peer, peer_port, &error)) goto cleanup;
    printf("PASS short_header\n");
    if (!test_short_declared_payload(&client, peer, peer_port, &error)) {
        goto cleanup;
    }
    printf("PASS short_declared_payload\n");
    if (!test_long_declared_payload(&client, peer, peer_port, &error)) {
        goto cleanup;
    }
    printf("PASS long_declared_payload\n");
    if (!test_oversize_datagram(&client, peer, peer_port, &error)) {
        goto cleanup;
    }
    printf("PASS oversize_datagram\n");
    if (!test_no_cross_datagram(&client, peer, peer_port, &error)) {
        goto cleanup;
    }
    printf("PASS no_cross_datagram\n");
    if (!test_absolute_deadline_continuity(&client, peer, peer_port, &error)) {
        goto cleanup;
    }
    printf("PASS absolute_deadline_continuity\n");
    if (!test_readable_timeout(&client, peer, peer_port, &error)) {
        goto cleanup;
    }
    printf("PASS readable_timeout\n");
    if (!test_receive_socket_failure(&client, peer, peer_port, &error)) {
        goto cleanup;
    }
    printf("PASS receive_socket_failure\n");

    status = 0;

cleanup:
    if (peer != TEST_INVALID_SOCKET) (void)TEST_CLOSE_SOCKET(peer);
    axis_alpha_pc_udp_cleanup(&client);
    axis_alpha_pc_udp_cleanup(&client);
    if (status == 0 && !check(!axis_alpha_pc_udp_is_valid(&client),
            "cleanup invalidates UDP socket")) status = 1;
    if (status == 0) {
        printf("SUMMARY passed=19 failed=0\n");
    }
    return status;
}
