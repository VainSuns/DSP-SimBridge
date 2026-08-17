/*
 * C2837xBlock Windows PC serial transport.
 *
 * This file deliberately contains only native serial I/O.  It does not know
 * about V1 message types, headers, payloads, or framing.
 */

#include "c2837x_block_pc_serial.h"

#if !defined(_WIN32) && !defined(C2837X_PC_SERIAL_TEST_SEAM)
#error "c2837x_block_pc_serial is a Windows-only production transport"
#endif

#ifdef _WIN32
#include <windows.h>
#endif

#include <stdio.h>
#include <string.h>

#ifdef C2837X_PC_SERIAL_TEST_SEAM
typedef c2837x_pc_serial_test_dcb_t c2837x_pc_serial_dcb_t;
typedef c2837x_pc_serial_test_timeouts_t c2837x_pc_serial_timeouts_t;
#else
#ifdef _WIN32
typedef DCB c2837x_pc_serial_dcb_t;
#endif
typedef struct
{
    uint32_t read_interval_timeout;
    uint32_t read_total_timeout_multiplier;
    uint32_t read_total_timeout_constant;
    uint32_t write_total_timeout_multiplier;
    uint32_t write_total_timeout_constant;
} c2837x_pc_serial_timeouts_t;
#endif

#ifndef C2837X_PC_SERIAL_TEST_SEAM
typedef void c2837x_pc_serial_test_hooks_t;
#endif

#define C2837X_PC_SERIAL_MISSING_HOOK_ERROR 12001u

#ifdef _WIN32
#define C2837X_PC_SERIAL_NOPARITY ((uint32_t)NOPARITY)
#define C2837X_PC_SERIAL_ONESTOPBIT ((uint32_t)ONESTOPBIT)
#define C2837X_PC_SERIAL_DTR_DISABLED ((uint32_t)DTR_CONTROL_DISABLE)
#define C2837X_PC_SERIAL_RTS_DISABLED ((uint32_t)RTS_CONTROL_DISABLE)
#else
#define C2837X_PC_SERIAL_NOPARITY 0u
#define C2837X_PC_SERIAL_ONESTOPBIT 0u
#define C2837X_PC_SERIAL_DTR_DISABLED 0u
#define C2837X_PC_SERIAL_RTS_DISABLED 0u
#endif

static void set_error_context(const c2837x_pc_serial_t *serial,
    c2837x_pc_serial_error_t *error, c2837x_pc_serial_error_kind_t kind,
    uint32_t os_error, uint32_t requested_bytes, uint32_t transferred_bytes)
{
    if (error != NULL) {
        error->kind = kind;
        error->com_number = serial != NULL ? serial->com_number : 0u;
        error->requested_baud = serial != NULL ? serial->requested_baud : 0u;
        error->requested_bytes = requested_bytes;
        error->transferred_bytes = transferred_bytes;
        error->os_error = os_error;
    }
}

static int fail(c2837x_pc_serial_t *serial,
    c2837x_pc_serial_error_t *error, c2837x_pc_serial_error_kind_t kind,
    uint32_t os_error, uint32_t requested_bytes, uint32_t transferred_bytes)
{
    if (serial != NULL) {
        serial->last_transfer_count = transferred_bytes;
        serial->last_os_error = os_error;
    }
    set_error_context(serial, error, kind, os_error, requested_bytes,
        transferred_bytes);
    if (serial != NULL && serial->valid) {
        c2837x_pc_serial_close(serial);
    }
    return -1;
}

#if !defined(_WIN32) || defined(C2837X_PC_SERIAL_TEST_SEAM)
static int missing_hook(uint32_t *os_error)
{
    if (os_error != NULL) {
        *os_error = C2837X_PC_SERIAL_MISSING_HOOK_ERROR;
    }
    return 0;
}
#endif

#ifdef _WIN32
static int native_query_frequency(uint64_t *frequency_hz,
    uint32_t *os_error)
{
    LARGE_INTEGER value;
    if (!QueryPerformanceFrequency(&value) || value.QuadPart <= 0) {
        DWORD last_error = GetLastError();
        if (last_error == 0u) last_error = ERROR_FUNCTION_FAILED;
        if (os_error != NULL) *os_error = (uint32_t)last_error;
        return 0;
    }
    *frequency_hz = (uint64_t)value.QuadPart;
    if (os_error != NULL) *os_error = 0u;
    return 1;
}

static int native_query_counter(uint64_t *ticks, uint32_t *os_error)
{
    LARGE_INTEGER value;
    if (!QueryPerformanceCounter(&value) || value.QuadPart < 0) {
        DWORD last_error = GetLastError();
        if (last_error == 0u) last_error = ERROR_FUNCTION_FAILED;
        if (os_error != NULL) *os_error = (uint32_t)last_error;
        return 0;
    }
    *ticks = (uint64_t)value.QuadPart;
    if (os_error != NULL) *os_error = 0u;
    return 1;
}

static int native_open(const char *path, uintptr_t *native_handle,
    uint32_t *os_error)
{
    HANDLE handle = CreateFileA(path, GENERIC_READ | GENERIC_WRITE, 0, NULL,
        OPEN_EXISTING, 0, NULL);
    if (handle == INVALID_HANDLE_VALUE) {
        if (os_error != NULL) *os_error = (uint32_t)GetLastError();
        return 0;
    }
    *native_handle = (uintptr_t)handle;
    if (os_error != NULL) *os_error = 0u;
    return 1;
}

static int native_close(uintptr_t native_handle, uint32_t *os_error)
{
    if (CloseHandle((HANDLE)native_handle)) {
        if (os_error != NULL) *os_error = 0u;
        return 1;
    }
    if (os_error != NULL) *os_error = (uint32_t)GetLastError();
    return 0;
}

#if !defined(C2837X_PC_SERIAL_TEST_SEAM)
static int native_get_dcb(uintptr_t native_handle,
    c2837x_pc_serial_dcb_t *config, uint32_t *os_error)
{
    config->DCBlength = sizeof(*config);
    if (!GetCommState((HANDLE)native_handle, config)) {
        if (os_error != NULL) *os_error = (uint32_t)GetLastError();
        return 0;
    }
    if (os_error != NULL) *os_error = 0u;
    return 1;
}

static int native_set_dcb(uintptr_t native_handle,
    const c2837x_pc_serial_dcb_t *config, uint32_t *os_error)
{
    DCB dcb = *config;
    if (!SetCommState((HANDLE)native_handle, &dcb)) {
        if (os_error != NULL) *os_error = (uint32_t)GetLastError();
        return 0;
    }
    if (os_error != NULL) *os_error = 0u;
    return 1;
}
#endif

static int native_set_timeouts(uintptr_t native_handle,
    const c2837x_pc_serial_timeouts_t *timeouts, uint32_t *os_error)
{
    COMMTIMEOUTS value;
    value.ReadIntervalTimeout = timeouts->read_interval_timeout;
    value.ReadTotalTimeoutMultiplier = timeouts->read_total_timeout_multiplier;
    value.ReadTotalTimeoutConstant = timeouts->read_total_timeout_constant;
    value.WriteTotalTimeoutMultiplier = timeouts->write_total_timeout_multiplier;
    value.WriteTotalTimeoutConstant = timeouts->write_total_timeout_constant;
    if (!SetCommTimeouts((HANDLE)native_handle, &value)) {
        if (os_error != NULL) *os_error = (uint32_t)GetLastError();
        return 0;
    }
    if (os_error != NULL) *os_error = 0u;
    return 1;
}

static int native_purge(uintptr_t native_handle, uint32_t flags,
    uint32_t *os_error)
{
    DWORD native_flags = 0u;
    if ((flags & C2837X_PC_SERIAL_PURGE_RX) != 0u) {
        native_flags |= PURGE_RXCLEAR;
    }
    if ((flags & C2837X_PC_SERIAL_PURGE_TX) != 0u) {
        native_flags |= PURGE_TXCLEAR;
    }
    if (!PurgeComm((HANDLE)native_handle, native_flags)) {
        if (os_error != NULL) *os_error = (uint32_t)GetLastError();
        return 0;
    }
    if (os_error != NULL) *os_error = 0u;
    return 1;
}

static int native_read(uintptr_t native_handle, uint8_t *buffer,
    uint32_t request, uint32_t *transferred, uint32_t *os_error)
{
    DWORD count = 0u;
    BOOL result = ReadFile((HANDLE)native_handle, buffer, (DWORD)request,
        &count, NULL);
    if (transferred != NULL) *transferred = (uint32_t)count;
    if (!result) {
        if (os_error != NULL) *os_error = (uint32_t)GetLastError();
        return 0;
    }
    if (os_error != NULL) *os_error = 0u;
    return 1;
}

static int native_write(uintptr_t native_handle, const uint8_t *buffer,
    uint32_t request, uint32_t *transferred, uint32_t *os_error)
{
    DWORD count = 0u;
    BOOL result = WriteFile((HANDLE)native_handle, buffer, (DWORD)request,
        &count, NULL);
    if (transferred != NULL) *transferred = (uint32_t)count;
    if (!result) {
        if (os_error != NULL) *os_error = (uint32_t)GetLastError();
        return 0;
    }
    if (os_error != NULL) *os_error = 0u;
    return 1;
}
#endif /* _WIN32 */

static int call_query_frequency(c2837x_pc_serial_t *serial,
    uint64_t *frequency_hz, uint32_t *os_error)
{
    (void)serial;
#ifdef C2837X_PC_SERIAL_TEST_SEAM
    if (serial->test_hooks_installed &&
            serial->hooks.query_frequency != NULL) {
        return serial->hooks.query_frequency(frequency_hz, os_error,
            serial->test_user_data);
    }
#endif
#ifdef _WIN32
    return native_query_frequency(frequency_hz, os_error);
#else
    return missing_hook(os_error);
#endif
}

static int call_query_counter(c2837x_pc_serial_t *serial,
    uint64_t *ticks, uint32_t *os_error)
{
    (void)serial;
#ifdef C2837X_PC_SERIAL_TEST_SEAM
    if (serial->test_hooks_installed && serial->hooks.query_counter != NULL) {
        return serial->hooks.query_counter(ticks, os_error,
            serial->test_user_data);
    }
#endif
#ifdef _WIN32
    return native_query_counter(ticks, os_error);
#else
    return missing_hook(os_error);
#endif
}

static int call_open(c2837x_pc_serial_t *serial, const char *path,
    uintptr_t *native_handle, uint32_t *os_error)
{
    (void)serial;
#ifdef C2837X_PC_SERIAL_TEST_SEAM
    if (serial->test_hooks_installed && serial->hooks.open != NULL) {
        return serial->hooks.open(path, native_handle, os_error,
            serial->test_user_data);
    }
#endif
#ifdef _WIN32
    return native_open(path, native_handle, os_error);
#else
    return missing_hook(os_error);
#endif
}

static int call_close(c2837x_pc_serial_t *serial, uintptr_t native_handle,
    uint32_t *os_error)
{
    (void)serial;
#ifdef C2837X_PC_SERIAL_TEST_SEAM
    if (serial->test_hooks_installed && serial->hooks.close != NULL) {
        return serial->hooks.close(native_handle, os_error,
            serial->test_user_data);
    }
#endif
#ifdef _WIN32
    return native_close(native_handle, os_error);
#else
    return missing_hook(os_error);
#endif
}

static int call_get_dcb(c2837x_pc_serial_t *serial,
    c2837x_pc_serial_dcb_t *config, uint32_t *os_error)
{
#ifdef C2837X_PC_SERIAL_TEST_SEAM
    if (serial->test_hooks_installed && serial->hooks.get_dcb != NULL) {
        return serial->hooks.get_dcb(serial->native_handle, config, os_error,
            serial->test_user_data);
    }
#endif
#if defined(_WIN32) && !defined(C2837X_PC_SERIAL_TEST_SEAM)
    return native_get_dcb(serial->native_handle, config, os_error);
#else
    return missing_hook(os_error);
#endif
}

static int call_set_dcb(c2837x_pc_serial_t *serial,
    const c2837x_pc_serial_dcb_t *config, uint32_t *os_error)
{
#ifdef C2837X_PC_SERIAL_TEST_SEAM
    if (serial->test_hooks_installed && serial->hooks.set_dcb != NULL) {
        return serial->hooks.set_dcb(serial->native_handle, config, os_error,
            serial->test_user_data);
    }
#endif
#if defined(_WIN32) && !defined(C2837X_PC_SERIAL_TEST_SEAM)
    return native_set_dcb(serial->native_handle, config, os_error);
#else
    return missing_hook(os_error);
#endif
}

static void apply_owned_dcb_settings(c2837x_pc_serial_dcb_t *config,
    uint32_t requested_baud)
{
    config->BaudRate = requested_baud;
    config->ByteSize = 8u;
    config->Parity = (uint8_t)C2837X_PC_SERIAL_NOPARITY;
    config->StopBits = (uint8_t)C2837X_PC_SERIAL_ONESTOPBIT;
    config->fBinary = 1u;
    config->fParity = 0u;
    config->fOutxCtsFlow = 0u;
    config->fOutxDsrFlow = 0u;
    config->fDtrControl = C2837X_PC_SERIAL_DTR_DISABLED;
    config->fDsrSensitivity = 0u;
    config->fTXContinueOnXoff = 1u;
    config->fOutX = 0u;
    config->fInX = 0u;
    config->fErrorChar = 0u;
    config->fNull = 0u;
    config->fRtsControl = C2837X_PC_SERIAL_RTS_DISABLED;
    config->fAbortOnError = 0u;
}

static int call_set_timeouts(c2837x_pc_serial_t *serial,
    const c2837x_pc_serial_timeouts_t *timeouts, uint32_t *os_error)
{
#ifdef C2837X_PC_SERIAL_TEST_SEAM
    if (serial->test_hooks_installed && serial->hooks.set_timeouts != NULL) {
        return serial->hooks.set_timeouts(serial->native_handle, timeouts,
            os_error, serial->test_user_data);
    }
#endif
#ifdef _WIN32
    return native_set_timeouts(serial->native_handle, timeouts, os_error);
#else
    return missing_hook(os_error);
#endif
}

static int call_purge(c2837x_pc_serial_t *serial, uint32_t flags,
    uint32_t *os_error)
{
#ifdef C2837X_PC_SERIAL_TEST_SEAM
    if (serial->test_hooks_installed && serial->hooks.purge != NULL) {
        return serial->hooks.purge(serial->native_handle, flags, os_error,
            serial->test_user_data);
    }
#endif
#ifdef _WIN32
    return native_purge(serial->native_handle, flags, os_error);
#else
    return missing_hook(os_error);
#endif
}

static int call_read(c2837x_pc_serial_t *serial, uint8_t *buffer,
    uint32_t request, uint32_t *transferred, uint32_t *os_error)
{
#ifdef C2837X_PC_SERIAL_TEST_SEAM
    if (serial->test_hooks_installed && serial->hooks.read != NULL) {
        return serial->hooks.read(serial->native_handle, buffer, request,
            transferred, os_error, serial->test_user_data);
    }
#endif
#ifdef _WIN32
    return native_read(serial->native_handle, buffer, request, transferred,
        os_error);
#else
    return missing_hook(os_error);
#endif
}

static int call_write(c2837x_pc_serial_t *serial, const uint8_t *buffer,
    uint32_t request, uint32_t *transferred, uint32_t *os_error)
{
#ifdef C2837X_PC_SERIAL_TEST_SEAM
    if (serial->test_hooks_installed && serial->hooks.write != NULL) {
        return serial->hooks.write(serial->native_handle, buffer, request,
            transferred, os_error, serial->test_user_data);
    }
#endif
#ifdef _WIN32
    return native_write(serial->native_handle, buffer, request, transferred,
        os_error);
#else
    return missing_hook(os_error);
#endif
}

static int require_initialized(const c2837x_pc_serial_t *serial,
    c2837x_pc_serial_error_t *error)
{
    if (serial == NULL || !serial->initialized ||
            serial->clock_frequency_hz == 0u) {
        if (error != NULL) error->kind = C2837X_PC_SERIAL_ERROR_ARGUMENT;
        return -1;
    }
    return 0;
}

static int require_valid(c2837x_pc_serial_t *serial,
    c2837x_pc_serial_error_t *error)
{
    if (require_initialized(serial, error) != 0 || !serial->valid) {
        if (error != NULL) error->kind = C2837X_PC_SERIAL_ERROR_ARGUMENT;
        return -1;
    }
    return 0;
}

static uint64_t saturating_add_u64(uint64_t left, uint64_t right)
{
    return right > UINT64_MAX - left ? UINT64_MAX : left + right;
}

static uint64_t timeout_to_ticks(uint32_t timeout_ms, uint64_t frequency_hz)
{
    uint64_t seconds = (uint64_t)timeout_ms / 1000u;
    uint64_t milliseconds = (uint64_t)timeout_ms % 1000u;
    uint64_t ticks;
    uint64_t fraction;

    if (seconds > UINT64_MAX / frequency_hz) {
        return UINT64_MAX;
    }
    ticks = seconds * frequency_hz;
    if (milliseconds > UINT64_MAX / frequency_hz) {
        return UINT64_MAX;
    }
    fraction = milliseconds * frequency_hz;
    fraction = fraction > UINT64_MAX - 999u ? UINT64_MAX : fraction + 999u;
    fraction /= 1000u;
    return saturating_add_u64(ticks, fraction);
}

static uint32_t ticks_to_ceil_ms(uint64_t ticks, uint64_t frequency_hz)
{
    uint64_t seconds = ticks / frequency_hz;
    uint64_t remainder = ticks % frequency_hz;
    uint64_t milliseconds;
    uint64_t fraction;

    if (seconds > UINT64_MAX / 1000u) {
        return UINT32_MAX;
    }
    milliseconds = seconds * 1000u;
    if (remainder > UINT64_MAX / 1000u) {
        return UINT32_MAX;
    }
    fraction = remainder * 1000u;
    fraction = fraction > UINT64_MAX - (frequency_hz - 1u) ?
        UINT64_MAX : fraction + (frequency_hz - 1u);
    fraction /= frequency_hz;
    if (milliseconds > UINT64_MAX - fraction) {
        return UINT32_MAX;
    }
    milliseconds += fraction;
    return milliseconds > UINT32_MAX ? UINT32_MAX : (uint32_t)milliseconds;
}

static int start_deadline(const c2837x_pc_serial_t *serial,
    uint32_t timeout_ms, c2837x_pc_serial_deadline_t *deadline,
    uint32_t *os_error)
{
    uint64_t now;
    c2837x_pc_serial_t *mutable_serial = (c2837x_pc_serial_t *)(uintptr_t)serial;
    if (serial == NULL || deadline == NULL || serial->clock_frequency_hz == 0u) {
        if (os_error != NULL) *os_error = 0u;
        return 0;
    }
    if (!call_query_counter(mutable_serial, &now, os_error)) {
        return 0;
    }
    deadline->expires_at_ticks = saturating_add_u64(now,
        timeout_to_ticks(timeout_ms, serial->clock_frequency_hz));
    return 1;
}

static int remaining_deadline(const c2837x_pc_serial_t *serial,
    const c2837x_pc_serial_deadline_t *deadline, uint32_t *remaining_ms,
    int *expired, uint32_t *os_error)
{
    uint64_t now;
    c2837x_pc_serial_t *mutable_serial = (c2837x_pc_serial_t *)(uintptr_t)serial;
    if (serial == NULL || deadline == NULL || remaining_ms == NULL ||
            expired == NULL || serial->clock_frequency_hz == 0u) {
        if (os_error != NULL) *os_error = 0u;
        return 0;
    }
    if (!call_query_counter(mutable_serial, &now, os_error)) {
        return 0;
    }
    if (now >= deadline->expires_at_ticks) {
        *expired = 1;
        *remaining_ms = 0u;
    } else {
        *expired = 0;
        *remaining_ms = ticks_to_ceil_ms(deadline->expires_at_ticks - now,
            serial->clock_frequency_hz);
    }
    return 1;
}

static int start_error(c2837x_pc_serial_error_t *error,
    const c2837x_pc_serial_t *serial)
{
    if (serial == NULL || !serial->initialized) {
        if (error != NULL) error->kind = C2837X_PC_SERIAL_ERROR_ARGUMENT;
        return -1;
    }
    return 0;
}

void c2837x_pc_serial_error_reset(c2837x_pc_serial_error_t *error,
    const char *operation)
{
    if (error != NULL) {
        memset(error, 0, sizeof(*error));
        error->operation = operation;
    }
}

int c2837x_pc_serial_format_path(uint32_t logical_com_number,
    char *path, size_t capacity)
{
    int count;
    if (logical_com_number == 0u || path == NULL || capacity == 0u) {
        return -1;
    }
    count = snprintf(path, capacity, "\\\\.\\COM%u",
        (unsigned int)logical_com_number);
    if (count < 0 || (size_t)count >= capacity) {
        if (capacity != 0u) path[capacity - 1u] = '\0';
        return -1;
    }
    return 0;
}

static int init_impl(c2837x_pc_serial_t *serial,
    const c2837x_pc_serial_test_hooks_t *hooks, void *user_data,
    c2837x_pc_serial_error_t *error)
{
    uint32_t os_error = 0u;

    if (serial == NULL) {
        c2837x_pc_serial_error_reset(error, "init");
        if (error != NULL) error->kind = C2837X_PC_SERIAL_ERROR_ARGUMENT;
        return -1;
    }
    memset(serial, 0, sizeof(*serial));
    serial->native_handle = C2837X_PC_SERIAL_INVALID_HANDLE;
#ifdef C2837X_PC_SERIAL_TEST_SEAM
    if (hooks != NULL) {
        serial->hooks = *hooks;
        serial->test_user_data = user_data;
        serial->test_hooks_installed = 1;
    }
#else
    (void)hooks;
    (void)user_data;
#endif
    c2837x_pc_serial_error_reset(error, "init");
    if (!call_query_frequency(serial, &serial->clock_frequency_hz, &os_error) ||
            serial->clock_frequency_hz == 0u) {
        return fail(serial, error, C2837X_PC_SERIAL_ERROR_OS, os_error, 0u, 0u);
    }
    serial->initialized = 1;
    return 0;
}

int c2837x_pc_serial_init(c2837x_pc_serial_t *serial,
    c2837x_pc_serial_error_t *error)
{
    return init_impl(serial, NULL, NULL, error);
}

#ifdef C2837X_PC_SERIAL_TEST_SEAM
int c2837x_pc_serial_init_with_test_hooks(c2837x_pc_serial_t *serial,
    const c2837x_pc_serial_test_hooks_t *hooks, void *user_data,
    c2837x_pc_serial_error_t *error)
{
    if (hooks == NULL) {
        c2837x_pc_serial_error_reset(error, "init");
        if (error != NULL) error->kind = C2837X_PC_SERIAL_ERROR_ARGUMENT;
        return -1;
    }
    return init_impl(serial, hooks, user_data, error);
}
#endif

int c2837x_pc_serial_open(c2837x_pc_serial_t *serial,
    uint32_t logical_com_number, c2837x_pc_serial_error_t *error)
{
    char path[32];
    uintptr_t native_handle = C2837X_PC_SERIAL_INVALID_HANDLE;
    uint32_t os_error = 0u;

    c2837x_pc_serial_error_reset(error, "open");
    if (serial == NULL || !serial->initialized || serial->valid ||
            logical_com_number == 0u) {
        if (error != NULL) error->kind = C2837X_PC_SERIAL_ERROR_ARGUMENT;
        return -1;
    }
    serial->com_number = logical_com_number;
    serial->requested_baud = 0u;
    if (c2837x_pc_serial_format_path(logical_com_number, path,
            sizeof(path)) != 0) {
        return fail(serial, error, C2837X_PC_SERIAL_ERROR_ARGUMENT, 0u, 0u,
            0u);
    }
    if (!call_open(serial, path, &native_handle, &os_error) ||
            native_handle == C2837X_PC_SERIAL_INVALID_HANDLE) {
        return fail(serial, error, C2837X_PC_SERIAL_ERROR_OS, os_error, 0u, 0u);
    }
    serial->native_handle = native_handle;
    serial->valid = 1;
    serial->last_transfer_count = 0u;
    serial->last_os_error = 0u;
    return 0;
}

int c2837x_pc_serial_configure(c2837x_pc_serial_t *serial,
    uint32_t requested_baud, c2837x_pc_serial_error_t *error)
{
    c2837x_pc_serial_dcb_t config;
    c2837x_pc_serial_timeouts_t timeouts;
    uint32_t os_error = 0u;

    c2837x_pc_serial_error_reset(error, "configure");
    if (require_valid(serial, error) != 0 || requested_baud == 0u) {
        if (error != NULL) error->kind = C2837X_PC_SERIAL_ERROR_ARGUMENT;
        return -1;
    }
    serial->requested_baud = requested_baud;
    if (error != NULL) error->requested_baud = requested_baud;
    if (!call_get_dcb(serial, &config, &os_error)) {
        return fail(serial, error, C2837X_PC_SERIAL_ERROR_OS, os_error, 0u, 0u);
    }

    apply_owned_dcb_settings(&config, requested_baud);

    if (!call_set_dcb(serial, &config, &os_error)) {
        return fail(serial, error, C2837X_PC_SERIAL_ERROR_OS, os_error, 0u, 0u);
    }

    /* Start in an immediate-read state; transfer calls install their own
     * remaining absolute-deadline timeout before each ReadFile/WriteFile. */
    memset(&timeouts, 0, sizeof(timeouts));
    timeouts.read_interval_timeout = UINT32_MAX;
    if (!call_set_timeouts(serial, &timeouts, &os_error)) {
        return fail(serial, error, C2837X_PC_SERIAL_ERROR_OS, os_error, 0u, 0u);
    }
    serial->last_os_error = 0u;
    return 0;
}

int c2837x_pc_serial_purge(c2837x_pc_serial_t *serial, uint32_t flags,
    c2837x_pc_serial_error_t *error)
{
    uint32_t os_error = 0u;
    c2837x_pc_serial_error_reset(error, "purge");
    if (require_valid(serial, error) != 0 || flags == 0u ||
            (flags & ~(C2837X_PC_SERIAL_PURGE_RX |
                C2837X_PC_SERIAL_PURGE_TX)) != 0u) {
        if (error != NULL) error->kind = C2837X_PC_SERIAL_ERROR_ARGUMENT;
        return -1;
    }
    if (!call_purge(serial, flags, &os_error)) {
        return fail(serial, error, C2837X_PC_SERIAL_ERROR_OS, os_error, 0u, 0u);
    }
    serial->last_os_error = 0u;
    return 0;
}

int c2837x_pc_serial_deadline_start(const c2837x_pc_serial_t *serial,
    uint32_t timeout_ms, c2837x_pc_serial_deadline_t *deadline,
    c2837x_pc_serial_error_t *error)
{
    uint32_t os_error = 0u;
    c2837x_pc_serial_error_reset(error, "deadline_start");
    if (start_error(error, serial) != 0 || deadline == NULL) {
        if (error != NULL) error->kind = C2837X_PC_SERIAL_ERROR_ARGUMENT;
        return -1;
    }
    if (!start_deadline(serial, timeout_ms, deadline, &os_error)) {
        return fail((c2837x_pc_serial_t *)(uintptr_t)serial, error,
            C2837X_PC_SERIAL_ERROR_OS, os_error, 0u, 0u);
    }
    return 0;
}

int c2837x_pc_serial_deadline_remaining(
    const c2837x_pc_serial_t *serial,
    const c2837x_pc_serial_deadline_t *deadline, uint32_t *remaining_ms,
    int *expired, c2837x_pc_serial_error_t *error)
{
    uint32_t os_error = 0u;
    c2837x_pc_serial_error_reset(error, "deadline_remaining");
    if (start_error(error, serial) != 0 || deadline == NULL ||
            remaining_ms == NULL || expired == NULL) {
        if (error != NULL) error->kind = C2837X_PC_SERIAL_ERROR_ARGUMENT;
        return -1;
    }
    if (!remaining_deadline(serial, deadline, remaining_ms, expired,
            &os_error)) {
        return fail((c2837x_pc_serial_t *)(uintptr_t)serial, error,
            C2837X_PC_SERIAL_ERROR_OS, os_error, 0u, 0u);
    }
    return 0;
}

static int transfer_until(c2837x_pc_serial_t *serial, uint8_t *data,
    uint32_t length, const c2837x_pc_serial_deadline_t *deadline,
    c2837x_pc_serial_error_t *error, int writing)
{
    uint32_t done = 0u;

    if (require_valid(serial, error) != 0 ||
            (length != 0u && (data == NULL || deadline == NULL))) {
        if (error != NULL) error->kind = C2837X_PC_SERIAL_ERROR_ARGUMENT;
        return -1;
    }
    serial->last_transfer_count = 0u;
    if (error != NULL) {
        error->com_number = serial->com_number;
        error->requested_baud = serial->requested_baud;
        error->requested_bytes = length;
        error->transferred_bytes = 0u;
    }
    if (length == 0u) {
        return 0;
    }

    while (done < length) {
        c2837x_pc_serial_timeouts_t timeouts;
        uint32_t remaining_ms;
        uint32_t os_error = 0u;
        uint32_t transferred = 0u;
        int expired;

        if (!remaining_deadline(serial, deadline, &remaining_ms, &expired,
                &os_error)) {
            return fail(serial, error, C2837X_PC_SERIAL_ERROR_OS, os_error,
                length, done);
        }
        if (expired) {
            return fail(serial, error, C2837X_PC_SERIAL_ERROR_TIMEOUT, 0u,
                length, done);
        }

        memset(&timeouts, 0, sizeof(timeouts));
        timeouts.read_total_timeout_constant = remaining_ms;
        timeouts.write_total_timeout_constant = remaining_ms;
        if (!call_set_timeouts(serial, &timeouts, &os_error)) {
            return fail(serial, error, C2837X_PC_SERIAL_ERROR_OS, os_error,
                length, done);
        }

        if (writing) {
            if (!call_write(serial, data + done, length - done, &transferred,
                    &os_error)) {
                return fail(serial, error, C2837X_PC_SERIAL_ERROR_OS, os_error,
                    length, done);
            }
        } else {
            if (!call_read(serial, data + done, length - done, &transferred,
                    &os_error)) {
                return fail(serial, error, C2837X_PC_SERIAL_ERROR_OS, os_error,
                    length, done);
            }
        }
        if (transferred > length - done) {
            return fail(serial, error, C2837X_PC_SERIAL_ERROR_INTERNAL, 0u,
                length, done);
        }
        done += transferred;
        serial->last_transfer_count = done;
        if (error != NULL) error->transferred_bytes = done;
    }
    serial->last_os_error = 0u;
    return 0;
}

int c2837x_pc_serial_send_all_until(c2837x_pc_serial_t *serial,
    const uint8_t *data, uint32_t length,
    const c2837x_pc_serial_deadline_t *deadline,
    c2837x_pc_serial_error_t *error)
{
    return transfer_until(serial, (uint8_t *)(uintptr_t)data, length, deadline,
        error, 1);
}

int c2837x_pc_serial_recv_exact_until(c2837x_pc_serial_t *serial, uint8_t *data,
    uint32_t length, const c2837x_pc_serial_deadline_t *deadline,
    c2837x_pc_serial_error_t *error)
{
    return transfer_until(serial, data, length, deadline, error, 0);
}

int c2837x_pc_serial_send_all(c2837x_pc_serial_t *serial,
    const uint8_t *data, uint32_t length, uint32_t timeout_ms,
    c2837x_pc_serial_error_t *error)
{
    c2837x_pc_serial_deadline_t deadline;
    uint32_t os_error = 0u;

    c2837x_pc_serial_error_reset(error, "write");
    if (require_valid(serial, error) != 0 ||
            (length != 0u && data == NULL)) {
        if (error != NULL) error->kind = C2837X_PC_SERIAL_ERROR_ARGUMENT;
        return -1;
    }
    if (length == 0u) return 0;
    if (!start_deadline(serial, timeout_ms, &deadline, &os_error)) {
        return fail(serial, error, C2837X_PC_SERIAL_ERROR_OS, os_error,
            length, 0u);
    }
    return c2837x_pc_serial_send_all_until(serial, data, length, &deadline,
        error);
}

int c2837x_pc_serial_recv_exact(c2837x_pc_serial_t *serial, uint8_t *data,
    uint32_t length, uint32_t timeout_ms, c2837x_pc_serial_error_t *error)
{
    c2837x_pc_serial_deadline_t deadline;
    uint32_t os_error = 0u;

    c2837x_pc_serial_error_reset(error, "read");
    if (require_valid(serial, error) != 0 ||
            (length != 0u && data == NULL)) {
        if (error != NULL) error->kind = C2837X_PC_SERIAL_ERROR_ARGUMENT;
        return -1;
    }
    if (length == 0u) return 0;
    if (!start_deadline(serial, timeout_ms, &deadline, &os_error)) {
        return fail(serial, error, C2837X_PC_SERIAL_ERROR_OS, os_error,
            length, 0u);
    }
    return c2837x_pc_serial_recv_exact_until(serial, data, length, &deadline,
        error);
}

void c2837x_pc_serial_close(c2837x_pc_serial_t *serial)
{
    uint32_t os_error = 0u;
    uintptr_t native_handle;
    if (serial == NULL || !serial->valid) return;
    native_handle = serial->native_handle;
    (void)call_close(serial, native_handle, &os_error);
    if (os_error != 0u && serial->last_os_error == 0u) {
        serial->last_os_error = os_error;
    }
    serial->native_handle = C2837X_PC_SERIAL_INVALID_HANDLE;
    serial->valid = 0;
}

int c2837x_pc_serial_is_valid(const c2837x_pc_serial_t *serial)
{
    return serial != NULL && serial->initialized && serial->valid;
}

int c2837x_pc_serial_get_system_error_text(uint32_t os_error,
    char *buffer, size_t capacity)
{
#ifdef _WIN32
    DWORD count;
    DWORD buffer_size;
    if (buffer == NULL || capacity == 0u) return -1;
    buffer[0] = '\0';
    buffer_size = capacity > (size_t)UINT32_MAX ? UINT32_MAX :
        (DWORD)capacity;
    count = FormatMessageA(FORMAT_MESSAGE_FROM_SYSTEM |
        FORMAT_MESSAGE_IGNORE_INSERTS | FORMAT_MESSAGE_MAX_WIDTH_MASK,
        NULL, (DWORD)os_error, 0u, buffer, buffer_size, NULL);
    if (count == 0u) return -1;
    if (buffer_size != 0u) buffer[buffer_size - 1u] = '\0';
    while (count != 0u &&
            (buffer[count - 1u] == '\r' || buffer[count - 1u] == '\n' ||
             buffer[count - 1u] == ' ' || buffer[count - 1u] == '\t')) {
        buffer[--count] = '\0';
    }
    return 0;
#else
    (void)os_error;
    (void)buffer;
    (void)capacity;
    return -1;
#endif
}
