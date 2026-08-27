#ifndef C2837X_BLOCK_PC_ERROR_H
#define C2837X_BLOCK_PC_ERROR_H

/*
 * Transport-neutral PC diagnostics shared by the generated W5300 protocol
 * runtime and the Windows serial adapter.
 *
 * The functions are header-only on purpose.  A SCI-only MEX can therefore
 * use the same PcError contract without linking the TCP socket transport.
 */

#include <stdarg.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum
{
    C2837X_PC_ERROR_NONE = 0,
    C2837X_PC_ERROR_ARGUMENT = 1,
    C2837X_PC_ERROR_TIMEOUT = 2,
    C2837X_PC_ERROR_DISCONNECT = 3,
    C2837X_PC_ERROR_SOCKET = 4,
    C2837X_PC_ERROR_TRUNCATED = 5,
    C2837X_PC_ERROR_MESSAGE_TYPE = 6,
    C2837X_PC_ERROR_PAYLOAD_LENGTH = 7,
    C2837X_PC_ERROR_PAYLOAD_CAPACITY = 8,
    C2837X_PC_ERROR_DSP_RESPONSE = 9,
    C2837X_PC_ERROR_INTERNAL = 10,
    C2837X_PC_ERROR_STEP_INDEX = 11,
    C2837X_PC_ERROR_FIELD_DECODE = 12,
    C2837X_PC_ERROR_PORT_ACCESS = 13,
    C2837X_PC_ERROR_SERIAL = 14
} c2837x_pc_error_kind_t;

enum
{
    C2837X_PC_ERROR_HAS_STEP_INDEX = 1u << 0,
    C2837X_PC_ERROR_HAS_EXPECTED_TYPE = 1u << 1,
    C2837X_PC_ERROR_HAS_ACTUAL_TYPE = 1u << 2,
    C2837X_PC_ERROR_HAS_EXPECTED_LENGTH = 1u << 3,
    C2837X_PC_ERROR_HAS_ACTUAL_LENGTH = 1u << 4,
    C2837X_PC_ERROR_HAS_EXPECTED_STEP = 1u << 5,
    C2837X_PC_ERROR_HAS_ACTUAL_STEP = 1u << 6,
    C2837X_PC_ERROR_HAS_DSP_ERROR = 1u << 7,
    C2837X_PC_ERROR_HAS_OS_ERROR = 1u << 8,
    C2837X_PC_ERROR_HAS_COM_NUMBER = 1u << 9,
    C2837X_PC_ERROR_HAS_REQUESTED_BAUD = 1u << 10,
    C2837X_PC_ERROR_HAS_SYSTEM_ERROR_TEXT = 1u << 11,
    C2837X_PC_ERROR_HAS_OS_ERROR_CODE = 1u << 12,
    C2837X_PC_ERROR_HAS_ACTUAL_BAUD = 1u << 13
};

#define C2837X_PC_ERROR_SYSTEM_TEXT_CAPACITY 128u

#define C2837X_PC_ERROR_STAGE_SERIAL_OPEN "serial_open"
#define C2837X_PC_ERROR_STAGE_SERIAL_CONFIGURE "serial_configure"
#define C2837X_PC_ERROR_STAGE_SERIAL_PURGE "serial_purge"
#define C2837X_PC_ERROR_STAGE_SEND_FRAME "send_frame"
#define C2837X_PC_ERROR_STAGE_RECV_HEADER "recv_header"
#define C2837X_PC_ERROR_STAGE_RECV_PAYLOAD "recv_payload"
#define C2837X_PC_ERROR_STAGE_WAIT_RESPONSE "wait_response"
#define C2837X_PC_ERROR_STAGE_WAIT_OUTPUT_DATA "wait_output_data"

typedef struct
{
    const char *instance;
    c2837x_pc_error_kind_t kind;
    const char *stage;
    uint32_t available;
    uint32_t com_number;
    uint32_t requested_baud;
    double actual_baud;
    uint32_t step_index;
    uint32_t expected_step;
    uint32_t actual_step;
    uint16_t expected_type;
    uint16_t actual_type;
    uint16_t expected_length;
    uint16_t actual_length;
    uint16_t dsp_error;
    int os_error;
    uint32_t os_error_code;
    char system_error_text[C2837X_PC_ERROR_SYSTEM_TEXT_CAPACITY];
} c2837x_pc_error_t;

static inline void c2837x_pc_error_reset(c2837x_pc_error_t *error,
    const char *instance, const char *stage)
{
    if (error != NULL) {
        memset(error, 0, sizeof(*error));
        error->instance = instance;
        error->stage = stage;
    }
}

static inline void c2837x_pc_error_set_com_and_baud(
    c2837x_pc_error_t *error, uint32_t com_number, uint32_t requested_baud)
{
    if (error != NULL) {
        error->available |= C2837X_PC_ERROR_HAS_COM_NUMBER |
            C2837X_PC_ERROR_HAS_REQUESTED_BAUD;
        error->com_number = com_number;
        error->requested_baud = requested_baud;
    }
}

static inline void c2837x_pc_error_set_com_and_actual_baud(
    c2837x_pc_error_t *error, uint32_t com_number, uint32_t requested_baud,
    double actual_baud)
{
    c2837x_pc_error_set_com_and_baud(error, com_number, requested_baud);
    if (error != NULL) {
        error->available |= C2837X_PC_ERROR_HAS_ACTUAL_BAUD;
        error->actual_baud = actual_baud;
    }
}

static inline uint16_t c2837x_pc_error_length_value(uint32_t value)
{
    return value > UINT16_MAX ? UINT16_MAX : (uint16_t)value;
}

static inline void c2837x_pc_error_set_lengths(c2837x_pc_error_t *error,
    uint32_t expected_length, uint32_t actual_length)
{
    if (error != NULL) {
        error->available |= C2837X_PC_ERROR_HAS_EXPECTED_LENGTH |
            C2837X_PC_ERROR_HAS_ACTUAL_LENGTH;
        error->expected_length = c2837x_pc_error_length_value(expected_length);
        error->actual_length = c2837x_pc_error_length_value(actual_length);
    }
}

static inline void c2837x_pc_error_set_system_error_text(
    c2837x_pc_error_t *error, const char *text)
{
    if (error == NULL) return;
    error->available &= ~C2837X_PC_ERROR_HAS_SYSTEM_ERROR_TEXT;
    error->system_error_text[0] = '\0';
    if (text == NULL || text[0] == '\0') return;
    strncpy(error->system_error_text, text,
        C2837X_PC_ERROR_SYSTEM_TEXT_CAPACITY - 1u);
    error->system_error_text[C2837X_PC_ERROR_SYSTEM_TEXT_CAPACITY - 1u] = '\0';
    if (error->system_error_text[0] != '\0') {
        error->available |= C2837X_PC_ERROR_HAS_SYSTEM_ERROR_TEXT;
    }
}

static inline const char *c2837x_pc_error_kind_name(
    c2837x_pc_error_kind_t kind)
{
    switch (kind) {
    case C2837X_PC_ERROR_NONE: return "none";
    case C2837X_PC_ERROR_ARGUMENT: return "argument";
    case C2837X_PC_ERROR_TIMEOUT: return "timeout";
    case C2837X_PC_ERROR_DISCONNECT: return "disconnect";
    case C2837X_PC_ERROR_SOCKET: return "socket";
    case C2837X_PC_ERROR_TRUNCATED: return "truncated";
    case C2837X_PC_ERROR_MESSAGE_TYPE: return "message_type";
    case C2837X_PC_ERROR_PAYLOAD_LENGTH: return "payload_length";
    case C2837X_PC_ERROR_PAYLOAD_CAPACITY: return "payload_capacity";
    case C2837X_PC_ERROR_DSP_RESPONSE: return "dsp_response";
    case C2837X_PC_ERROR_INTERNAL: return "internal";
    case C2837X_PC_ERROR_STEP_INDEX: return "step_index";
    case C2837X_PC_ERROR_FIELD_DECODE: return "field_decode";
    case C2837X_PC_ERROR_PORT_ACCESS: return "port_access";
    case C2837X_PC_ERROR_SERIAL: return "serial";
    default: return "unknown";
    }
}

static inline int c2837x_pc_error_append(char *buffer, size_t capacity,
    size_t *used, const char *format, ...)
{
    int count;
    va_list args;
    if (*used >= capacity) return -1;
    va_start(args, format);
    count = vsnprintf(buffer + *used, capacity - *used, format, args);
    va_end(args);
    if (count < 0 || (size_t)count >= capacity - *used) {
        buffer[capacity - 1u] = '\0';
        return -1;
    }
    *used += (size_t)count;
    return 0;
}

static inline int c2837x_pc_error_format(const c2837x_pc_error_t *error,
    char *buffer, size_t capacity)
{
    size_t used = 0u;
    int status = 0;
    if (error == NULL || buffer == NULL || capacity == 0u) return -1;
    buffer[0] = '\0';
    status |= c2837x_pc_error_append(buffer, capacity, &used,
        "instance=%s", error->instance != NULL ? error->instance : "unknown");
    if ((error->available & C2837X_PC_ERROR_HAS_COM_NUMBER) != 0u) {
        status |= c2837x_pc_error_append(buffer, capacity, &used,
            " COM=%lu", (unsigned long)error->com_number);
    }
    if ((error->available & C2837X_PC_ERROR_HAS_REQUESTED_BAUD) != 0u) {
        status |= c2837x_pc_error_append(buffer, capacity, &used,
            " baud=%lu", (unsigned long)error->requested_baud);
    }
    status |= c2837x_pc_error_append(buffer, capacity, &used,
        " stage=%s category=%s",
        error->stage != NULL ? error->stage : "unknown",
        c2837x_pc_error_kind_name(error->kind));
    if ((error->available & C2837X_PC_ERROR_HAS_ACTUAL_BAUD) != 0u) {
        status |= c2837x_pc_error_append(buffer, capacity, &used,
            " actual_baud=%.17g", error->actual_baud);
    }
#define C2837X_PC_ERROR_APPEND_IF(flag_, ...) \
    do { if ((error->available & (flag_)) != 0u) { \
        status |= c2837x_pc_error_append(buffer, capacity, &used, __VA_ARGS__); \
    } } while (0)
    C2837X_PC_ERROR_APPEND_IF(C2837X_PC_ERROR_HAS_STEP_INDEX,
        " step_index=%lu", (unsigned long)error->step_index);
    C2837X_PC_ERROR_APPEND_IF(C2837X_PC_ERROR_HAS_EXPECTED_TYPE,
        " expected_type=%u", (unsigned int)error->expected_type);
    C2837X_PC_ERROR_APPEND_IF(C2837X_PC_ERROR_HAS_ACTUAL_TYPE,
        " actual_type=%u", (unsigned int)error->actual_type);
    C2837X_PC_ERROR_APPEND_IF(C2837X_PC_ERROR_HAS_EXPECTED_LENGTH,
        " expected_length=%u", (unsigned int)error->expected_length);
    C2837X_PC_ERROR_APPEND_IF(C2837X_PC_ERROR_HAS_ACTUAL_LENGTH,
        " actual_length=%u", (unsigned int)error->actual_length);
    C2837X_PC_ERROR_APPEND_IF(C2837X_PC_ERROR_HAS_EXPECTED_STEP,
        " expected_step=%lu", (unsigned long)error->expected_step);
    C2837X_PC_ERROR_APPEND_IF(C2837X_PC_ERROR_HAS_ACTUAL_STEP,
        " actual_step=%lu", (unsigned long)error->actual_step);
    C2837X_PC_ERROR_APPEND_IF(C2837X_PC_ERROR_HAS_DSP_ERROR,
        " dsp_error=%u", (unsigned int)error->dsp_error);
    if ((error->available & C2837X_PC_ERROR_HAS_OS_ERROR_CODE) != 0u) {
        status |= c2837x_pc_error_append(buffer, capacity, &used,
            " os_error=%lu", (unsigned long)error->os_error_code);
    } else {
        C2837X_PC_ERROR_APPEND_IF(C2837X_PC_ERROR_HAS_OS_ERROR,
            " os_error=%d", error->os_error);
    }
    C2837X_PC_ERROR_APPEND_IF(C2837X_PC_ERROR_HAS_SYSTEM_ERROR_TEXT,
        " system_error=\"%s\"", error->system_error_text);
#undef C2837X_PC_ERROR_APPEND_IF
    return status == 0 ? 0 : -1;
}

#ifdef __cplusplus
}
#endif

#endif /* C2837X_BLOCK_PC_ERROR_H */
