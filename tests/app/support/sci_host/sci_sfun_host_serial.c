#include "c2837x_block_pc_serial.h"
#include "sci_sfun_host_serial_test.h"

#include <stdarg.h>
#include <stdio.h>
#include <string.h>

static sci_host_mock_mode_t mock_mode;
static char mock_log[4096];
static size_t mock_log_used;
static uint32_t mock_configured_baud;
static uint32_t mock_open_com_number;
static uint32_t mock_purge_flags;
static uint32_t mock_sim_stop_timeout;
static uint32_t mock_deadline_timeout_ms;
static const c2837x_pc_serial_deadline_t *first_receive_deadline;
static int same_receive_deadline;
static int same_send_deadline;
static int active_frame;

static void append_log(const char *format, ...)
{
    va_list args;
    int written;
    if (mock_log_used >= sizeof(mock_log)) return;
    va_start(args, format);
    written = vsnprintf(mock_log + mock_log_used,
        sizeof(mock_log) - mock_log_used, format, args);
    va_end(args);
    if (written > 0) {
        size_t count = (size_t)written;
        if (count >= sizeof(mock_log) - mock_log_used) {
            mock_log_used = sizeof(mock_log) - 1u;
        } else {
            mock_log_used += count;
        }
    }
}

static void set_serial_error(c2837x_pc_serial_t *serial,
    c2837x_pc_serial_error_t *error, c2837x_pc_serial_error_kind_t kind,
    const char *operation, uint32_t requested, uint32_t transferred,
    uint32_t os_error)
{
    c2837x_pc_serial_error_reset(error, operation);
    if (error != NULL) {
        error->kind = kind;
        error->com_number = serial != NULL ? serial->com_number : 0u;
        error->requested_baud = serial != NULL ? serial->requested_baud : 0u;
        error->requested_bytes = requested;
        error->transferred_bytes = transferred;
        error->os_error = os_error;
    }
}

static c2837x_pc_error_kind_t pc_error_kind_for_serial(
    c2837x_pc_serial_error_kind_t kind)
{
    switch (kind) {
    case C2837X_PC_SERIAL_ERROR_NONE:
        return C2837X_PC_ERROR_NONE;
    case C2837X_PC_SERIAL_ERROR_ARGUMENT:
        return C2837X_PC_ERROR_ARGUMENT;
    case C2837X_PC_SERIAL_ERROR_TIMEOUT:
        return C2837X_PC_ERROR_TIMEOUT;
    case C2837X_PC_SERIAL_ERROR_OS:
        return C2837X_PC_ERROR_SERIAL;
    case C2837X_PC_SERIAL_ERROR_INTERNAL:
        return C2837X_PC_ERROR_INTERNAL;
    default:
        return C2837X_PC_ERROR_INTERNAL;
    }
}

void sci_host_mock_reset(sci_host_mock_mode_t mode)
{
    mock_mode = mode;
    mock_log[0] = '\0';
    mock_log_used = 0u;
    mock_configured_baud = 0u;
    mock_open_com_number = 0u;
    mock_purge_flags = 0u;
    mock_sim_stop_timeout = 0u;
    mock_deadline_timeout_ms = 0u;
    first_receive_deadline = NULL;
    same_receive_deadline = 1;
    same_send_deadline = 1;
    active_frame = 0;
}

const char *sci_host_mock_log(void)
{
    return mock_log;
}

uint32_t sci_host_mock_configured_baud(void)
{
    return mock_configured_baud;
}

uint32_t sci_host_mock_open_com_number(void)
{
    return mock_open_com_number;
}

uint32_t sci_host_mock_purge_flags(void)
{
    return mock_purge_flags;
}

uint32_t sci_host_mock_sim_stop_timeout(void)
{
    return mock_sim_stop_timeout;
}

int sci_host_mock_same_send_deadline(void)
{
    return same_send_deadline;
}

int sci_host_mock_same_receive_deadline(void)
{
    return same_receive_deadline;
}

void c2837x_pc_serial_error_reset(c2837x_pc_serial_error_t *error,
    const char *operation)
{
    if (error != NULL) {
        memset(error, 0, sizeof(*error));
        error->operation = operation;
    }
}

void c2837x_pc_serial_error_to_pc_error(
    const c2837x_pc_serial_error_t *serial_error, const char *instance,
    const char *stage, uint32_t generated_baud, c2837x_pc_error_t *error)
{
    const char *resolved_stage = stage;
    uint32_t baud = generated_baud;
    if (resolved_stage == NULL || resolved_stage[0] == '\0') {
        resolved_stage = serial_error != NULL &&
                serial_error->operation != NULL ?
            serial_error->operation : "serial";
    }
    if (serial_error != NULL && baud == 0u) {
        baud = serial_error->requested_baud;
    }
    c2837x_pc_error_reset(error, instance, resolved_stage);
    if (error == NULL) return;
    error->kind = serial_error == NULL ? C2837X_PC_ERROR_ARGUMENT :
        pc_error_kind_for_serial(serial_error->kind);
    c2837x_pc_error_set_com_and_baud(error,
        serial_error != NULL ? serial_error->com_number : 0u, baud);
    if (serial_error == NULL) return;
    if (serial_error->requested_bytes != 0u ||
            serial_error->transferred_bytes != 0u) {
        c2837x_pc_error_set_lengths(error, serial_error->requested_bytes,
            serial_error->transferred_bytes);
    }
    if (serial_error->kind == C2837X_PC_SERIAL_ERROR_OS) {
        error->available |= C2837X_PC_ERROR_HAS_OS_ERROR |
            C2837X_PC_ERROR_HAS_OS_ERROR_CODE;
        error->os_error = (int)serial_error->os_error;
        error->os_error_code = serial_error->os_error;
        c2837x_pc_error_set_system_error_text(error, "mock_os_error");
    }
}

int c2837x_pc_serial_init(c2837x_pc_serial_t *serial,
    c2837x_pc_serial_error_t *error)
{
    if (serial == NULL) {
        set_serial_error(serial, error, C2837X_PC_SERIAL_ERROR_ARGUMENT,
            "serial_init", 0u, 0u, 0u);
        return -1;
    }
    memset(serial, 0, sizeof(*serial));
    serial->initialized = 1;
    c2837x_pc_serial_error_reset(error, "serial_init");
    append_log("init;");
    return 0;
}

int c2837x_pc_serial_open(c2837x_pc_serial_t *serial,
    uint32_t logical_com_number, c2837x_pc_serial_error_t *error)
{
    if (serial == NULL || !serial->initialized || logical_com_number == 0u) {
        set_serial_error(serial, error, C2837X_PC_SERIAL_ERROR_ARGUMENT,
            "open", 0u, 0u, 0u);
        return -1;
    }
    serial->com_number = logical_com_number;
    mock_open_com_number = logical_com_number;
    append_log("open(%lu);", (unsigned long)logical_com_number);
    if (mock_mode == SCI_HOST_MOCK_SERIAL_OPEN_OS) {
        set_serial_error(serial, error, C2837X_PC_SERIAL_ERROR_OS, "open",
            0u, 0u, 5u);
        return -1;
    }
    serial->native_handle = (uintptr_t)1u;
    serial->valid = 1;
    c2837x_pc_serial_error_reset(error, "open");
    return 0;
}

int c2837x_pc_serial_configure(c2837x_pc_serial_t *serial,
    uint32_t requested_baud, c2837x_pc_serial_error_t *error)
{
    if (serial == NULL || !serial->valid || requested_baud == 0u) {
        set_serial_error(serial, error, C2837X_PC_SERIAL_ERROR_ARGUMENT,
            "configure", 0u, 0u, 0u);
        return -1;
    }
    serial->requested_baud = requested_baud;
    mock_configured_baud = requested_baud;
    append_log("configure(%lu);", (unsigned long)requested_baud);
    c2837x_pc_serial_error_reset(error, "configure");
    return 0;
}

int c2837x_pc_serial_purge(c2837x_pc_serial_t *serial, uint32_t flags,
    c2837x_pc_serial_error_t *error)
{
    if (serial == NULL || !serial->valid) {
        set_serial_error(serial, error, C2837X_PC_SERIAL_ERROR_ARGUMENT,
            "purge", 0u, 0u, 0u);
        return -1;
    }
    mock_purge_flags = flags;
    append_log("purge(%lu);", (unsigned long)flags);
    c2837x_pc_serial_error_reset(error, "purge");
    return 0;
}

int c2837x_pc_serial_deadline_start(const c2837x_pc_serial_t *serial,
    uint32_t timeout_ms, c2837x_pc_serial_deadline_t *deadline,
    c2837x_pc_serial_error_t *error)
{
    if (serial == NULL || !serial->valid || deadline == NULL) {
        set_serial_error((c2837x_pc_serial_t *)(uintptr_t)serial, error,
            C2837X_PC_SERIAL_ERROR_ARGUMENT, "serial_deadline_start",
            0u, 0u, 0u);
        return -1;
    }
    (void)deadline;
    mock_deadline_timeout_ms = timeout_ms;
    c2837x_pc_serial_error_reset(error, "serial_deadline_start");
    return 0;
}

int c2837x_pc_serial_deadline_remaining(
    const c2837x_pc_serial_t *serial,
    const c2837x_pc_serial_deadline_t *deadline, uint32_t *remaining_ms,
    int *expired, c2837x_pc_serial_error_t *error)
{
    if (serial == NULL || !serial->valid || deadline == NULL ||
            remaining_ms == NULL || expired == NULL) {
        set_serial_error((c2837x_pc_serial_t *)(uintptr_t)serial, error,
            C2837X_PC_SERIAL_ERROR_ARGUMENT, "serial_deadline_remaining",
            0u, 0u, 0u);
        return -1;
    }
    *remaining_ms = mock_deadline_timeout_ms;
    *expired = 0;
    c2837x_pc_serial_error_reset(error, "serial_deadline_remaining");
    return 0;
}

static uint16_t read_le16(const uint8_t *data)
{
    return (uint16_t)((uint16_t)data[0] | ((uint16_t)data[1] << 8));
}

static void write_le16(uint8_t *data, uint16_t value)
{
    data[0] = (uint8_t)(value & 0xffu);
    data[1] = (uint8_t)((value >> 8) & 0xffu);
}

static void write_le32(uint8_t *data, uint32_t value)
{
    data[0] = (uint8_t)(value & 0xffu);
    data[1] = (uint8_t)((value >> 8) & 0xffu);
    data[2] = (uint8_t)((value >> 16) & 0xffu);
    data[3] = (uint8_t)((value >> 24) & 0xffu);
}

int c2837x_pc_serial_send_all_until(c2837x_pc_serial_t *serial,
    const uint8_t *data, uint32_t length,
    const c2837x_pc_serial_deadline_t *deadline,
    c2837x_pc_serial_error_t *error)
{
    uint16_t type;
    if (serial == NULL || !serial->valid || data == NULL || deadline == NULL ||
            length < 4u) {
        set_serial_error(serial, error, C2837X_PC_SERIAL_ERROR_ARGUMENT,
            "serial_write", length, 0u, 0u);
        return -1;
    }
    type = read_le16(data);
    serial->last_transfer_count = length;
    same_send_deadline = deadline != NULL ? 1 : 0;
    if (type == 1u) {
        active_frame = 1;
        append_log("sim_start_send(%lu);", (unsigned long)mock_deadline_timeout_ms);
    } else if (type == 2u) {
        active_frame = 2;
        append_log("input_send(%lu);", (unsigned long)mock_deadline_timeout_ms);
    } else if (type == 4u) {
        mock_sim_stop_timeout = mock_deadline_timeout_ms;
        append_log("sim_stop_send(%lu);", (unsigned long)mock_deadline_timeout_ms);
    } else {
        append_log("send(%u,%lu);", (unsigned int)type,
            (unsigned long)mock_deadline_timeout_ms);
    }
    c2837x_pc_serial_error_reset(error, "serial_write");
    return 0;
}

int c2837x_pc_serial_recv_exact_until(c2837x_pc_serial_t *serial,
    uint8_t *data, uint32_t length,
    const c2837x_pc_serial_deadline_t *deadline,
    c2837x_pc_serial_error_t *error)
{
    if (serial == NULL || !serial->valid || data == NULL || deadline == NULL ||
            length == 0u) {
        set_serial_error(serial, error, C2837X_PC_SERIAL_ERROR_ARGUMENT,
            "serial_read", length, 0u, 0u);
        return -1;
    }
    if (length == 4u) {
        if (active_frame == 1) {
            if (mock_mode == SCI_HOST_MOCK_START_MESSAGE) {
                write_le16(data, 3u);
                write_le16(data + 2u, 6u);
            } else if (mock_mode == SCI_HOST_MOCK_START_LENGTH) {
                write_le16(data, 5u);
                write_le16(data + 2u, 4u);
            } else {
                write_le16(data, 5u);
                write_le16(data + 2u, 2u);
            }
            append_log("response_header;");
        } else {
            write_le16(data, 3u);
            write_le16(data + 2u, 6u);
            append_log("output_header;");
        }
        first_receive_deadline = deadline;
    } else {
        if (first_receive_deadline != deadline) same_receive_deadline = 0;
        if (active_frame == 1) {
            write_le16(data, mock_mode == SCI_HOST_MOCK_START_DSP ? 4u : 0u);
            append_log("response_payload;");
        } else {
            if (mock_mode == SCI_HOST_MOCK_STEP_TIMEOUT) {
                data[0] = 0u;
                serial->last_transfer_count = 1u;
                set_serial_error(serial, error, C2837X_PC_SERIAL_ERROR_TIMEOUT,
                    "serial_read", length, 1u, 0u);
                return -1;
            }
            write_le32(data, mock_mode == SCI_HOST_MOCK_STEP_DECODE ? 7u : 0u);
            write_le16(data + 4u, 0xbeefu);
            serial->last_transfer_count = length;
            append_log("output_payload;");
        }
    }
    serial->last_transfer_count = length;
    c2837x_pc_serial_error_reset(error, "serial_read");
    return 0;
}

int c2837x_pc_serial_send_all(c2837x_pc_serial_t *serial,
    const uint8_t *data, uint32_t length, uint32_t timeout_ms,
    c2837x_pc_serial_error_t *error)
{
    c2837x_pc_serial_deadline_t deadline;
    if (c2837x_pc_serial_deadline_start(serial, timeout_ms, &deadline, error) != 0) {
        return -1;
    }
    return c2837x_pc_serial_send_all_until(serial, data, length, &deadline,
        error);
}

int c2837x_pc_serial_recv_exact(c2837x_pc_serial_t *serial, uint8_t *data,
    uint32_t length, uint32_t timeout_ms, c2837x_pc_serial_error_t *error)
{
    c2837x_pc_serial_deadline_t deadline;
    if (c2837x_pc_serial_deadline_start(serial, timeout_ms, &deadline, error) != 0) {
        return -1;
    }
    return c2837x_pc_serial_recv_exact_until(serial, data, length, &deadline,
        error);
}

void c2837x_pc_serial_close(c2837x_pc_serial_t *serial)
{
    if (serial != NULL && serial->valid) {
        append_log("close;");
        serial->valid = 0;
        serial->native_handle = 0u;
    }
}

int c2837x_pc_serial_is_valid(const c2837x_pc_serial_t *serial)
{
    return serial != NULL && serial->valid != 0;
}

int c2837x_pc_serial_get_system_error_text(uint32_t os_error,
    char *buffer, size_t capacity)
{
    int written;
    if (buffer == NULL || capacity == 0u) return -1;
    written = snprintf(buffer, capacity, "mock_os_error_%lu",
        (unsigned long)os_error);
    return written >= 0 && (size_t)written < capacity ? 0 : -1;
}
