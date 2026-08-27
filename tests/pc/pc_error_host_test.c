/*
 * Focused SCI-S4-02 diagnostics test.
 *
 * This test exercises the shared PcError formatter and the production serial
 * error adapter without requiring a real COM port.
 */

#include "c2837x_block_pc_serial.h"

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

static int contains(const char *text, const char *token)
{
    return text != NULL && token != NULL && strstr(text, token) != NULL;
}

static int test_kind_numbers(void)
{
    return check(C2837X_PC_ERROR_NONE == 0 &&
            C2837X_PC_ERROR_ARGUMENT == 1 &&
            C2837X_PC_ERROR_TIMEOUT == 2 &&
            C2837X_PC_ERROR_DISCONNECT == 3 &&
            C2837X_PC_ERROR_SOCKET == 4 &&
            C2837X_PC_ERROR_TRUNCATED == 5 &&
            C2837X_PC_ERROR_MESSAGE_TYPE == 6 &&
            C2837X_PC_ERROR_PAYLOAD_LENGTH == 7 &&
            C2837X_PC_ERROR_PAYLOAD_CAPACITY == 8 &&
            C2837X_PC_ERROR_DSP_RESPONSE == 9 &&
            C2837X_PC_ERROR_INTERNAL == 10 &&
            C2837X_PC_ERROR_STEP_INDEX == 11 &&
            C2837X_PC_ERROR_FIELD_DECODE == 12 &&
            C2837X_PC_ERROR_PORT_ACCESS == 13 &&
            C2837X_PC_ERROR_SERIAL == 14,
        "PcError kind numbers preserve 0-13 and append SERIAL");
}

static int test_serial_mapping(void)
{
    c2837x_pc_serial_error_t serial_error;
    c2837x_pc_error_t error;
    char formatted[512];
    memset(&serial_error, 0, sizeof(serial_error));
    serial_error.kind = C2837X_PC_SERIAL_ERROR_OS;
    serial_error.operation = "serial_read";
    serial_error.com_number = 12u;
    serial_error.requested_bytes = 4u;
    serial_error.os_error = 995u;
    c2837x_pc_serial_error_to_pc_error(&serial_error, "axis_alpha",
        C2837X_PC_ERROR_STAGE_RECV_HEADER, 57600u, &error);
    if (!check(error.kind == C2837X_PC_ERROR_SERIAL,
            "Win32 serial failure maps to SERIAL")) return 0;
    if (!check(strcmp(error.stage, C2837X_PC_ERROR_STAGE_RECV_HEADER) == 0,
            "serial adapter preserves protocol stage")) return 0;
    if (!check((error.available & C2837X_PC_ERROR_HAS_COM_NUMBER) != 0u &&
            error.com_number == 12u &&
            (error.available & C2837X_PC_ERROR_HAS_REQUESTED_BAUD) != 0u &&
            error.requested_baud == 57600u,
            "serial context preserves COM and generated baud")) return 0;
    c2837x_pc_error_set_com_and_actual_baud(&error, 12u, 57600u,
        57339.449541284404);
    if (!check((error.available & C2837X_PC_ERROR_HAS_ACTUAL_BAUD) != 0u &&
            error.actual_baud == 57339.449541284404,
            "serial context preserves actual generated baud")) return 0;
    if (!check((error.available & C2837X_PC_ERROR_HAS_OS_ERROR) != 0u &&
            (error.available & C2837X_PC_ERROR_HAS_OS_ERROR_CODE) != 0u &&
            error.os_error == 995 && error.os_error_code == 995u,
            "serial context preserves numeric OS error")) return 0;
    if (!check(c2837x_pc_error_format(&error, formatted, sizeof(formatted)) == 0,
            "serial error formats")) return 0;
    if (!check(contains(formatted, "instance=axis_alpha COM=12 baud=57600") &&
            contains(formatted, "stage=recv_header category=serial") &&
            contains(formatted, "actual_baud=57339.449541284404") &&
            contains(formatted, "os_error=995") &&
            !contains(formatted, "category=disconnect") &&
            !contains(formatted, "category=socket"),
            "serial formatted fields are stable")) return 0;
    if ((error.available & C2837X_PC_ERROR_HAS_SYSTEM_ERROR_TEXT) != 0u) {
        if (!check(contains(formatted, "system_error=\""),
                "available Windows system text is formatted")) return 0;
        printf("SYSTEM_ERROR_TEXT=AVAILABLE\n");
    } else {
        printf("SYSTEM_ERROR_TEXT=NOT_AVAILABLE\n");
    }
    return 1;
}

static int test_partial_timeout_mapping(void)
{
    c2837x_pc_serial_error_t serial_error;
    c2837x_pc_error_t error;
    char formatted[512];
    memset(&serial_error, 0, sizeof(serial_error));
    serial_error.kind = C2837X_PC_SERIAL_ERROR_TIMEOUT;
    serial_error.operation = "serial_read";
    serial_error.com_number = 12u;
    serial_error.requested_baud = 57600u;
    serial_error.requested_bytes = 4u;
    serial_error.transferred_bytes = 2u;
    c2837x_pc_serial_error_to_pc_error(&serial_error, "axis_alpha",
        C2837X_PC_ERROR_STAGE_RECV_HEADER, 57600u, &error);
    if (!check(error.kind == C2837X_PC_ERROR_TIMEOUT,
            "partial deadline remains TIMEOUT")) return 0;
    if (!check((error.available & C2837X_PC_ERROR_HAS_EXPECTED_LENGTH) != 0u &&
            (error.available & C2837X_PC_ERROR_HAS_ACTUAL_LENGTH) != 0u &&
            error.expected_length == 4u && error.actual_length == 2u,
            "partial deadline preserves expected and actual length")) return 0;
    if (!check(c2837x_pc_error_format(&error, formatted, sizeof(formatted)) == 0 &&
            contains(formatted, "stage=recv_header category=timeout") &&
            contains(formatted, "expected_length=4 actual_length=2") &&
            !contains(formatted, "category=serial") &&
            !contains(formatted, "category=disconnect") &&
            !contains(formatted, "category=truncated"),
            "partial timeout formatting is orthogonal to serial")) return 0;
    return 1;
}

static int test_existing_protocol_diagnostic(void)
{
    c2837x_pc_error_t error;
    char formatted[512];
    c2837x_pc_error_reset(&error, "axis_alpha",
        C2837X_PC_ERROR_STAGE_WAIT_RESPONSE);
    error.kind = C2837X_PC_ERROR_PAYLOAD_LENGTH;
    c2837x_pc_error_set_lengths(&error, 2u, 4u);
    if (!check(c2837x_pc_error_format(&error, formatted, sizeof(formatted)) == 0 &&
            contains(formatted, "stage=wait_response category=payload_length") &&
            contains(formatted, "expected_length=2 actual_length=4"),
            "existing protocol payload diagnostic remains stable")) return 0;
    return 1;
}

static int test_serial_operation_stages(void)
{
    static const char *operations[] = {"open", "configure", "purge"};
    static const char *expected[] = {
        C2837X_PC_ERROR_STAGE_SERIAL_OPEN,
        C2837X_PC_ERROR_STAGE_SERIAL_CONFIGURE,
        C2837X_PC_ERROR_STAGE_SERIAL_PURGE};
    c2837x_pc_serial_error_t serial_error;
    c2837x_pc_error_t error;
    size_t index;
    memset(&serial_error, 0, sizeof(serial_error));
    serial_error.kind = C2837X_PC_SERIAL_ERROR_ARGUMENT;
    for (index = 0u; index < sizeof(operations) / sizeof(operations[0]);
            ++index) {
        serial_error.operation = operations[index];
        c2837x_pc_serial_error_to_pc_error(&serial_error, "axis_alpha", NULL,
            57600u, &error);
        if (!check(strcmp(error.stage, expected[index]) == 0,
                "serial-specific operation stage is stable")) return 0;
    }
    return 1;
}

static int test_serial_mapping_kinds(void)
{
    static const c2837x_pc_serial_error_kind_t serial_kinds[] = {
        C2837X_PC_SERIAL_ERROR_ARGUMENT,
        C2837X_PC_SERIAL_ERROR_TIMEOUT,
        C2837X_PC_SERIAL_ERROR_OS,
        C2837X_PC_SERIAL_ERROR_INTERNAL};
    static const c2837x_pc_error_kind_t pc_kinds[] = {
        C2837X_PC_ERROR_ARGUMENT,
        C2837X_PC_ERROR_TIMEOUT,
        C2837X_PC_ERROR_SERIAL,
        C2837X_PC_ERROR_INTERNAL};
    c2837x_pc_serial_error_t serial_error;
    c2837x_pc_error_t error;
    size_t index;
    memset(&serial_error, 0, sizeof(serial_error));
    serial_error.operation = "serial_transfer";
    for (index = 0u; index < sizeof(serial_kinds) / sizeof(serial_kinds[0]);
            ++index) {
        serial_error.kind = serial_kinds[index];
        c2837x_pc_serial_error_to_pc_error(&serial_error, "axis_alpha",
            C2837X_PC_ERROR_STAGE_SEND_FRAME, 57600u, &error);
        if (!check(error.kind == pc_kinds[index],
                "serial error kind mapping is stable")) return 0;
    }
    return 1;
}

int main(void)
{
    int passed = 0;
    int failed = 0;
    if (test_kind_numbers()) {
        ++passed;
        printf("PASS kind_numbers\n");
    } else {
        ++failed;
    }
    if (test_serial_mapping()) {
        ++passed;
        printf("PASS serial_mapping\n");
    } else {
        ++failed;
    }
    if (test_partial_timeout_mapping()) {
        ++passed;
        printf("PASS partial_timeout_mapping\n");
    } else {
        ++failed;
    }
    if (test_existing_protocol_diagnostic()) {
        ++passed;
        printf("PASS existing_protocol_diagnostic\n");
    } else {
        ++failed;
    }
    if (test_serial_operation_stages()) {
        ++passed;
        printf("PASS serial_operation_stages\n");
    } else {
        ++failed;
    }
    if (test_serial_mapping_kinds()) {
        ++passed;
        printf("PASS serial_mapping_kinds\n");
    } else {
        ++failed;
    }
    printf("SUMMARY passed=%d failed=%d\n", passed, failed);
    return failed == 0 ? 0 : 1;
}
