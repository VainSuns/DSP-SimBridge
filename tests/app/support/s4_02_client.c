#include "axis_alpha_protocol.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

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
    status = axis_alpha_pc_socket_connect(&socket, argv[1], port, 500u, &error);
    if (status != 0) {
        print_result(status, &socket, &error);
        axis_alpha_pc_socket_cleanup(&socket);
        return strcmp(argv[3], "connect_fail") == 0 ? 0 : 4;
    }
    if (strcmp(argv[3], "golden") == 0) {
        const uint8_t input[] = {0xaau, 0xbbu};
        status = axis_alpha_protocol_send_sim_start(&socket, 1u,
            0x12345678u, 500u, &error);
        if (status == 0) status = axis_alpha_protocol_send_sim_stop(
            &socket, 500u, &error);
        if (status == 0) status = axis_alpha_protocol_send_input_data(
            &socket, input, sizeof(input), 500u, &error);
    } else if (strcmp(argv[3], "response") == 0) {
        status = axis_alpha_protocol_wait_response(&socket, 500u, &error);
    } else if (strcmp(argv[3], "response_short_timeout") == 0) {
        uint64_t started = axis_alpha_pc_socket_monotonic_ms();
        status = axis_alpha_protocol_wait_response(&socket, 250u, &error);
        printf("client_elapsed_ms=%lu ", (unsigned long)
            (axis_alpha_pc_socket_monotonic_ms() - started));
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
