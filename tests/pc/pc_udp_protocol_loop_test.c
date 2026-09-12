#ifndef _WIN32
#ifndef _POSIX_C_SOURCE
#define _POSIX_C_SOURCE 200809L
#endif
#endif

#include "axis_alpha_protocol.h"

#ifdef _WIN32
#include <winsock2.h>
#include <ws2tcpip.h>
typedef SOCKET test_socket_t;
typedef int test_socklen_t;
#define TEST_INVALID_SOCKET INVALID_SOCKET
#define TEST_SOCKET_ERROR SOCKET_ERROR
#define TEST_CLOSE_SOCKET(s_) closesocket(s_)
#else
#include <arpa/inet.h>
#include <poll.h>
#include <sys/socket.h>
#include <unistd.h>
typedef int test_socket_t;
typedef socklen_t test_socklen_t;
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

static int wait_peer_readable(test_socket_t peer, int timeout_ms)
{
#ifdef _WIN32
    fd_set read_set;
    struct timeval timeout;
    int result;
    FD_ZERO(&read_set);
    FD_SET(peer, &read_set);
    timeout.tv_sec = (long)(timeout_ms / 1000);
    timeout.tv_usec = (long)((timeout_ms % 1000) * 1000);
    result = select(0, &read_set, NULL, NULL, &timeout);
    return result == 1 && FD_ISSET(peer, &read_set) ? 1 : 0;
#else
    struct pollfd descriptor;
    int result;
    descriptor.fd = peer;
    descriptor.events = POLLIN;
    descriptor.revents = 0;
    result = poll(&descriptor, 1, timeout_ms);
    return result == 1 && (descriptor.revents & POLLIN) != 0 ? 1 : 0;
#endif
}

static int peer_has_datagram(test_socket_t peer)
{
    uint8_t byte = 0u;
    if (!wait_peer_readable(peer, 0)) return 0;
    return recv(peer, (char *)&byte, 1, MSG_PEEK) != TEST_SOCKET_ERROR;
}

static int create_peer(test_socket_t *peer, uint16_t *port)
{
    struct sockaddr_in address;
    test_socket_t native;
    test_socklen_t address_length;

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
    address_length = (test_socklen_t)sizeof(address);
    if (getsockname(native, (struct sockaddr *)&address, &address_length) ==
            TEST_SOCKET_ERROR) {
        (void)TEST_CLOSE_SOCKET(native);
        return -1;
    }
    *peer = native;
    *port = ntohs(address.sin_port);
    return *port != 0u ? 0 : -1;
}

static int client_endpoint(const AxisAlphaPcUdpSocket *client,
    struct sockaddr_in *endpoint)
{
    test_socklen_t endpoint_length;
    if (client == NULL || endpoint == NULL ||
            !axis_alpha_pc_udp_is_valid(client)) return -1;
    endpoint_length = (test_socklen_t)sizeof(*endpoint);
    memset(endpoint, 0, sizeof(*endpoint));
    if (getsockname(native_socket(client), (struct sockaddr *)endpoint,
            &endpoint_length) == TEST_SOCKET_ERROR) return -1;
    return endpoint->sin_family == AF_INET &&
        endpoint->sin_addr.s_addr == htonl(INADDR_LOOPBACK) &&
        ntohs(endpoint->sin_port) != 0u ? 0 : -1;
}

static int receive_datagram(test_socket_t peer, uint8_t *buffer,
    size_t capacity, struct sockaddr_in *source)
{
    test_socklen_t source_length;
    if (buffer == NULL || source == NULL || capacity == 0u) return -1;
    if (!wait_peer_readable(peer, 1000)) return -1;
    source_length = (test_socklen_t)sizeof(*source);
    memset(source, 0, sizeof(*source));
    return recvfrom(peer, (char *)buffer, (int)capacity, 0,
        (struct sockaddr *)source, &source_length);
}

static int send_datagram(test_socket_t peer,
    const struct sockaddr_in *destination, const uint8_t *data, size_t length)
{
    test_socklen_t destination_length;
    int count;
    if (destination == NULL || (data == NULL && length != 0u)) return -1;
    destination_length = (test_socklen_t)sizeof(*destination);
    count = sendto(peer, (const char *)data, (int)length, 0,
        (const struct sockaddr *)destination, destination_length);
    return count == (int)length ? 0 : -1;
}

static int expect_datagram(test_socket_t peer,
    const struct sockaddr_in *client, const uint8_t *expected,
    size_t expected_length, const char *label)
{
    uint8_t received[2048];
    struct sockaddr_in source;
    int count;
    count = receive_datagram(peer, received, sizeof(received), &source);
    if (count != (int)expected_length) {
        fprintf(stderr, "FAIL %s length=%d expected=%lu\n", label, count,
            (unsigned long)expected_length);
        return 0;
    }
    if (!check(memcmp(received, expected, expected_length) == 0, label)) {
        return 0;
    }
    if (!check(source.sin_family == AF_INET &&
            source.sin_addr.s_addr == htonl(INADDR_LOOPBACK) &&
            source.sin_port == client->sin_port,
            "peer sees the OS-assigned client endpoint")) return 0;
    return check(!peer_has_datagram(peer),
        "one protocol frame produces one UDP datagram");
}

static int connect_client(AxisAlphaPcUdpSocket *client, uint16_t peer_port,
    struct sockaddr_in *endpoint, AxisAlphaPcError *error)
{
    if (!check(axis_alpha_pc_udp_connect(client, "127.0.0.1", peer_port,
            1000u, error) == 0, "localhost UDP connect")) return 0;
    if (!check(client_endpoint(client, endpoint) == 0,
            "client uses an OS-assigned ephemeral local port")) return 0;
    return 1;
}

static void print_error(const char *label, const AxisAlphaPcError *error)
{
    char formatted[512];
    (void)axis_alpha_pc_error_format(error, formatted, sizeof(formatted));
    printf("EVIDENCE %s %s\n", label, formatted);
}

static int error_has_lengths(const AxisAlphaPcError *error,
    uint16_t expected, uint16_t actual)
{
    return error != NULL &&
        (error->available & C2837X_PC_ERROR_HAS_EXPECTED_LENGTH) != 0u &&
        (error->available & C2837X_PC_ERROR_HAS_ACTUAL_LENGTH) != 0u &&
        error->expected_length == expected && error->actual_length == actual;
}

static int error_matches(const AxisAlphaPcError *error,
    AxisAlphaPcErrorKind kind, const char *stage, uint16_t expected,
    uint16_t actual)
{
    return error != NULL && error->kind == kind && error->stage != NULL &&
        strcmp(error->stage, stage) == 0 &&
        error_has_lengths(error, expected, actual);
}

static int run_normal_loop(AxisAlphaPcUdpSocket *client, test_socket_t peer,
    uint16_t peer_port, AxisAlphaPcError *error)
{
    static const uint8_t start_frame[] = {
        0x01u, 0x00u, 0x06u, 0x00u, 0x01u, 0x00u,
        0x78u, 0x56u, 0x34u, 0x12u
    };
    static const uint8_t response_frame[] = {
        0x05u, 0x00u, 0x02u, 0x00u, 0x00u, 0x00u
    };
    static const uint8_t expected_input[] = {
        0x02u, 0x00u, 0x04u, 0x00u, 0x11u, 0x22u, 0x33u, 0x44u
    };
    static const uint8_t output_frame[] = {
        0x03u, 0x00u, 0x04u, 0x00u, 0x55u, 0x66u, 0x77u, 0x88u
    };
    static const uint8_t stop_frame[] = {0x04u, 0x00u, 0x00u, 0x00u};
    uint8_t input_frame[sizeof(expected_input)] = {0u};
    uint8_t output_payload[4] = {0u};
    uint16_t output_length = 0u;
    struct sockaddr_in endpoint;

    memcpy(input_frame + 4u, expected_input + 4u, 4u);
    if (!connect_client(client, peer_port, &endpoint, error)) return 0;
    printf("EVIDENCE client_local_port=%u peer_port=%u\n",
        (unsigned int)ntohs(endpoint.sin_port), (unsigned int)peer_port);
    if (!check(axis_alpha_protocol_send_sim_start(client, 1u, 0x12345678u,
            1000u, error) == 0, "SIM_START send")) return 0;
    if (!expect_datagram(peer, &endpoint, start_frame, sizeof(start_frame),
            "SIM_START is one complete datagram")) return 0;
    printf("PASS SIM_START whole_datagram\n");

    if (!check(send_datagram(peer, &endpoint, response_frame,
            sizeof(response_frame)) == 0, "RESPONSE peer send")) return 0;
    if (!check(axis_alpha_protocol_wait_response(client, 1000u, error) == 0,
            "RESPONSE receive")) return 0;
    printf("PASS RESPONSE\n");

    if (!check(axis_alpha_protocol_send_input_data(client, input_frame, 4u,
            1000u, error) == 0, "INPUT_DATA send")) return 0;
    if (!expect_datagram(peer, &endpoint, expected_input,
            sizeof(expected_input), "INPUT_DATA is one complete datagram")) {
        return 0;
    }
    printf("PASS INPUT_DATA whole_datagram\n");

    if (!check(send_datagram(peer, &endpoint, output_frame,
            sizeof(output_frame)) == 0, "OUTPUT_DATA peer send")) return 0;
    if (!check(axis_alpha_protocol_wait_output_data(client, output_payload,
            &output_length, sizeof(output_payload), 1000u, error) == 0 &&
            output_length == 4u &&
            memcmp(output_payload, output_frame + 4u, 4u) == 0,
            "OUTPUT_DATA staged header then payload")) return 0;
    printf("PASS OUTPUT_DATA staged_header_payload one_peer_datagram\n");

    if (!check(axis_alpha_protocol_send_sim_stop(client, 1000u, error) == 0,
            "SIM_STOP send")) return 0;
    if (!expect_datagram(peer, &endpoint, stop_frame, sizeof(stop_frame),
            "SIM_STOP is one complete datagram")) return 0;
    printf("PASS SIM_STOP whole_datagram best_effort_no_response\n");
    return 1;
}

static int run_timeout(AxisAlphaPcUdpSocket *client, test_socket_t peer,
    uint16_t peer_port, AxisAlphaPcError *error)
{
    static const uint8_t start_frame[] = {
        0x01u, 0x00u, 0x06u, 0x00u, 0x01u, 0x00u,
        0x78u, 0x56u, 0x34u, 0x12u
    };
    struct sockaddr_in endpoint;
    if (!connect_client(client, peer_port, &endpoint, error)) return 0;
    if (!check(axis_alpha_protocol_send_sim_start(client, 1u, 0x12345678u,
            1000u, error) == 0, "timeout request send")) return 0;
    if (!expect_datagram(peer, &endpoint, start_frame, sizeof(start_frame),
            "timeout request is received before response is withheld")) {
        return 0;
    }
    if (!check(axis_alpha_protocol_wait_response(client, 40u, error) == -1 &&
            error_matches(error, AXIS_ALPHA_PC_ERROR_TIMEOUT, "recv_header",
                4u, 0u), "missing RESPONSE maps to TIMEOUT")) return 0;
    print_error("timeout", error);
    printf("PASS timeout no_packet_lost_category\n");
    return 1;
}

static int run_short_datagram(AxisAlphaPcUdpSocket *client,
    test_socket_t peer, uint16_t peer_port, AxisAlphaPcError *error)
{
    static const uint8_t short_datagram[] = {0x05u, 0x00u, 0x02u};
    struct sockaddr_in endpoint;
    if (!connect_client(client, peer_port, &endpoint, error)) return 0;
    if (!check(send_datagram(peer, &endpoint, short_datagram,
            sizeof(short_datagram)) == 0, "short datagram peer send")) {
        return 0;
    }
    if (!check(axis_alpha_protocol_wait_response(client, 1000u, error) == -1 &&
            error_matches(error, AXIS_ALPHA_PC_ERROR_TRUNCATED,
                "recv_header", 4u, 3u),
            "short datagram maps to TRUNCATED recv_header")) return 0;
    print_error("short_datagram", error);
    printf("PASS short_datagram\n");
    return 1;
}

static int run_declared_short_and_no_cross(AxisAlphaPcUdpSocket *client,
    test_socket_t peer, uint16_t peer_port, AxisAlphaPcError *error)
{
    static const uint8_t first[] = {
        0x05u, 0x00u, 0x02u, 0x00u, 0x00u
    };
    static const uint8_t second[] = {
        0x05u, 0x00u, 0x02u, 0x00u, 0x00u, 0x00u
    };
    struct sockaddr_in endpoint;
    if (!connect_client(client, peer_port, &endpoint, error)) return 0;
    if (!check(send_datagram(peer, &endpoint, first, sizeof(first)) == 0 &&
            send_datagram(peer, &endpoint, second, sizeof(second)) == 0,
            "short datagram followed by independent second datagram")) {
        return 0;
    }
    if (!check(axis_alpha_protocol_wait_response(client, 1000u, error) == -1 &&
            error_matches(error, AXIS_ALPHA_PC_ERROR_TRUNCATED,
                "recv_payload", 2u, 1u),
            "short payload does not consume the next datagram")) return 0;
    print_error("no_cross_datagram", error);
    printf("PASS declared_length_short\n");
    printf("PASS no_cross_datagram second_untouched\n");
    return 1;
}

static int run_declared_long(AxisAlphaPcUdpSocket *client, test_socket_t peer,
    uint16_t peer_port, AxisAlphaPcError *error)
{
    static const uint8_t datagram[] = {
        0x05u, 0x00u, 0x02u, 0x00u, 0x00u, 0x00u, 0xaau, 0xbbu
    };
    struct sockaddr_in endpoint;
    if (!connect_client(client, peer_port, &endpoint, error)) return 0;
    if (!check(send_datagram(peer, &endpoint, datagram, sizeof(datagram)) == 0,
            "long payload peer send")) return 0;
    if (!check(axis_alpha_protocol_wait_response(client, 1000u, error) == -1 &&
            error_matches(error, AXIS_ALPHA_PC_ERROR_PAYLOAD_LENGTH,
                "recv_payload", 2u, 4u),
            "long payload maps to PAYLOAD_LENGTH recv_payload")) return 0;
    print_error("declared_length_long", error);
    printf("PASS declared_length_long\n");
    return 1;
}

int main(void)
{
    AxisAlphaPcUdpSocket client;
    AxisAlphaPcError error;
    test_socket_t peer = TEST_INVALID_SOCKET;
    uint16_t peer_port = 0u;
    int status = 1;

    memset(&client, 0, sizeof(client));
    if (!check(axis_alpha_pc_udp_init(&client, &error) == 0,
            "UDP production client init")) goto cleanup;
    if (!check(create_peer(&peer, &peer_port) == 0,
            "minimal localhost UDP peer with OS-assigned port")) goto cleanup;
    printf("PASS real_os_udp peer_port=%u\n", (unsigned int)peer_port);

    if (!run_normal_loop(&client, peer, peer_port, &error)) goto cleanup;
    if (!run_timeout(&client, peer, peer_port, &error)) goto cleanup;
    if (!run_short_datagram(&client, peer, peer_port, &error)) goto cleanup;
    if (!run_declared_short_and_no_cross(&client, peer, peer_port, &error)) {
        goto cleanup;
    }
    if (!run_declared_long(&client, peer, peer_port, &error)) goto cleanup;

    status = 0;

cleanup:
    if (peer != TEST_INVALID_SOCKET) (void)TEST_CLOSE_SOCKET(peer);
    axis_alpha_pc_udp_cleanup(&client);
    if (status == 0) printf("SUMMARY passed=11 failed=0\n");
    return status;
}
