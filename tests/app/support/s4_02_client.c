#ifndef _WIN32
#ifndef _POSIX_C_SOURCE
#define _POSIX_C_SOURCE 200809L
#endif
#endif

#include "axis_alpha_protocol.h"

#ifdef _WIN32
#include <winsock2.h>
#include <windows.h>
#else
#include <sys/socket.h>
#include <time.h>
#endif
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static uint64_t test_now_ms(void)
{
#ifdef _WIN32
    LARGE_INTEGER counter;
    LARGE_INTEGER frequency;
    if (!QueryPerformanceCounter(&counter) ||
            !QueryPerformanceFrequency(&frequency)) return 0u;
    return (uint64_t)(counter.QuadPart / frequency.QuadPart) * 1000u +
        (uint64_t)(counter.QuadPart % frequency.QuadPart) * 1000u /
            (uint64_t)frequency.QuadPart;
#else
    struct timespec value;
    if (clock_gettime(CLOCK_MONOTONIC, &value) != 0) return 0u;
    return (uint64_t)value.tv_sec * 1000u +
        (uint64_t)value.tv_nsec / 1000000u;
#endif
}

static int constrain_send_buffer(AxisAlphaPcSocket *socket)
{
    int size = 4096;
#ifdef _WIN32
    return setsockopt((SOCKET)socket->native_handle, SOL_SOCKET, SO_SNDBUF,
        (const char *)&size, (int)sizeof(size));
#else
    return setsockopt((int)socket->native_handle, SOL_SOCKET, SO_SNDBUF,
        &size, (socklen_t)sizeof(size));
#endif
}

static void print_result(int status, AxisAlphaPcSocket *socket,
    AxisAlphaPcError *error)
{
    char text[512];
    (void)axis_alpha_pc_error_format(error, text, sizeof(text));
    printf("status=%d valid=%d kind=%d dsp=%u transferred=%lu error=%s\n",
        status, axis_alpha_pc_socket_is_valid(socket), (int)error->kind,
        (unsigned int)error->dsp_error,
        (unsigned long)socket->last_transfer_count, text);
}

int main(int argc, char **argv)
{
    AxisAlphaPcSocket socket;
    AxisAlphaPcError error;
    uint16_t port;
    int status;
    if (argc != 4) return 2;
    port = (uint16_t)strtoul(argv[2], NULL, 10);
    if (axis_alpha_pc_socket_init(&socket, &error) != 0) return 3;
    status = axis_alpha_pc_socket_connect(&socket, argv[1], port,
        strcmp(argv[3], "connect_zero_timeout") == 0 ? 0u : 500u, &error);
    if (status != 0) {
        print_result(status, &socket, &error);
        axis_alpha_pc_socket_cleanup(&socket);
        return strcmp(argv[3], "connect_fail") == 0 ||
            strcmp(argv[3], "connect_zero_timeout") == 0 ? 0 : 4;
    }
    if (strcmp(argv[3], "golden") == 0) {
        uint8_t input_frame[AXIS_ALPHA_HEADER_SIZE + 2u];
        input_frame[AXIS_ALPHA_HEADER_SIZE] = 0xaau;
        input_frame[AXIS_ALPHA_HEADER_SIZE + 1u] = 0xbbu;
        status = axis_alpha_protocol_send_sim_start(&socket, 1u,
            0x12345678u, 500u, &error);
        if (status == 0) status = axis_alpha_protocol_send_sim_stop(
            &socket, 500u, &error);
        if (status == 0) status = axis_alpha_protocol_send_input_data(
            &socket, input_frame, 2u, 500u, &error);
    } else if (strcmp(argv[3], "response") == 0) {
        status = axis_alpha_protocol_wait_response(&socket, 500u, &error);
    } else if (strcmp(argv[3], "response_short_timeout") == 0) {
        uint64_t started = test_now_ms();
        status = axis_alpha_protocol_wait_response(&socket, 250u, &error);
        printf("client_elapsed_ms=%lu ", (unsigned long)
            (test_now_ms() - started));
    } else if (strcmp(argv[3], "response_retry") == 0) {
        status = axis_alpha_protocol_wait_response(&socket, 500u, &error);
        if (status != 0) {
            AxisAlphaPcError first = error;
            char first_text[512];
            int first_status = status;
            (void)axis_alpha_pc_error_format(&first, first_text,
                sizeof(first_text));
            status = axis_alpha_protocol_wait_response(&socket, 100u, &error);
            printf("first_status=%d first_kind=%d first_dsp=%u first_error=%s retry_status=%d ",
                first_status, (int)first.kind, (unsigned int)first.dsp_error,
                first_text, status);
        }
    } else if (strcmp(argv[3], "output") == 0) {
        uint8_t payload[16];
        uint16_t length = 0u;
        status = axis_alpha_protocol_wait_output_data(&socket, payload,
            &length, sizeof(payload), 500u, &error);
        if (status == 0) printf("length=%u payload=%02x%02x ",
            (unsigned int)length, payload[0], payload[1]);
    } else if (strcmp(argv[3], "send_large") == 0) {
        uint32_t length = 8u * 1024u * 1024u;
        uint8_t *data = (uint8_t *)malloc(length);
        if (data == NULL) return 5;
        memset(data, 0x5a, length);
        status = axis_alpha_pc_socket_send_all(&socket, data, length,
            5000u, &error);
        free(data);
    } else if (strcmp(argv[3], "recv_ready_timeout") == 0) {
        uint32_t length = 128u * 1024u * 1024u;
        uint8_t *data = (uint8_t *)malloc(length);
        uint64_t started = test_now_ms();
        if (data == NULL) return 5;
        status = axis_alpha_pc_socket_recv_exact(&socket, data, length,
            10u, &error);
        printf("requested=%lu client_elapsed_ms=%lu ", (unsigned long)length,
            (unsigned long)(test_now_ms() - started));
        free(data);
    } else if (strcmp(argv[3], "send_timeout") == 0 ||
            strcmp(argv[3], "send_disconnect") == 0) {
        uint32_t length = 64u * 1024u * 1024u;
        uint8_t *data = (uint8_t *)malloc(length);
        uint64_t started = test_now_ms();
        if (data == NULL) return 5;
        if (constrain_send_buffer(&socket) != 0) return 7;
        memset(data, 0x5a, length);
        status = axis_alpha_pc_socket_send_all(&socket, data, length,
            strcmp(argv[3], "send_timeout") == 0 ? 10u : 1000u, &error);
        printf("requested=%lu client_elapsed_ms=%lu ", (unsigned long)length,
            (unsigned long)(test_now_ms() - started));
        free(data);
    } else if (strcmp(argv[3], "recv_zero_timeout") == 0) {
        uint8_t byte = 0u;
        status = axis_alpha_pc_socket_recv_exact(&socket, &byte, 1u, 0u,
            &error);
    } else if (strcmp(argv[3], "zero") == 0) {
        status = axis_alpha_pc_socket_send_all(&socket, NULL, 0u, 0u, &error);
        if (status == 0) status = axis_alpha_pc_socket_recv_exact(
            &socket, NULL, 0u, 0u, &error);
    } else {
        return 6;
    }
    print_result(status, &socket, &error);
    axis_alpha_pc_socket_cleanup(&socket);
    return 0;
}
