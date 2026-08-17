#ifndef C2837X_BLOCK_PC_SERIAL_H
#define C2837X_BLOCK_PC_SERIAL_H

/*
 * C2837xBlock Windows PC serial transport.
 *
 * The production implementation is Windows-only and exposes a raw octet
 * stream.  Protocol framing, message validation, and session lifecycle stay
 * above this layer.
 */

#include <stddef.h>
#include <stdint.h>

#include "c2837x_block_pc_error.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef enum
{
    C2837X_PC_SERIAL_ERROR_NONE = 0,
    C2837X_PC_SERIAL_ERROR_ARGUMENT = 1,
    C2837X_PC_SERIAL_ERROR_TIMEOUT = 2,
    C2837X_PC_SERIAL_ERROR_OS = 3,
    C2837X_PC_SERIAL_ERROR_INTERNAL = 4
} c2837x_pc_serial_error_kind_t;

typedef struct
{
    c2837x_pc_serial_error_kind_t kind;
    const char *operation;
    uint32_t com_number;
    uint32_t requested_baud;
    uint32_t requested_bytes;
    uint32_t transferred_bytes;
    uint32_t os_error;
} c2837x_pc_serial_error_t;

typedef struct
{
    uint64_t expires_at_ticks;
} c2837x_pc_serial_deadline_t;

#define C2837X_PC_SERIAL_PURGE_RX 0x01u
#define C2837X_PC_SERIAL_PURGE_TX 0x02u

#define C2837X_PC_SERIAL_INVALID_HANDLE ((uintptr_t)(~(uintptr_t)0u))

/*
 * Test-only syscall seam.
 *
 * Defining C2837X_PC_SERIAL_TEST_SEAM exposes this seam and does not change
 * the production path.  The callbacks replace only Win32/QPC external
 * effects; the production transport loop, deadline logic, configuration, and
 * ownership remain under test.
 */
#ifdef C2837X_PC_SERIAL_TEST_SEAM

typedef struct
{
    /* Keep the test DCB field names aligned with Win32's DCB structure. */
    uint32_t DCBlength;
    uint32_t BaudRate;
    uint32_t fBinary;
    uint32_t fParity;
    uint32_t fOutxCtsFlow;
    uint32_t fOutxDsrFlow;
    uint32_t fDtrControl;
    uint32_t fDsrSensitivity;
    uint32_t fTXContinueOnXoff;
    uint32_t fOutX;
    uint32_t fInX;
    uint32_t fErrorChar;
    uint32_t fNull;
    uint32_t fRtsControl;
    uint32_t fAbortOnError;
    uint32_t fDummy2;
    uint16_t wReserved;
    uint16_t XonLim;
    uint16_t XoffLim;
    uint8_t ByteSize;
    uint8_t Parity;
    uint8_t StopBits;
    uint8_t XonChar;
    uint8_t XoffChar;
    uint8_t ErrorChar;
    uint8_t EofChar;
    uint8_t EvtChar;
    uint16_t wReserved1;
} c2837x_pc_serial_test_dcb_t;

typedef struct
{
    uint32_t read_interval_timeout;
    uint32_t read_total_timeout_multiplier;
    uint32_t read_total_timeout_constant;
    uint32_t write_total_timeout_multiplier;
    uint32_t write_total_timeout_constant;
} c2837x_pc_serial_test_timeouts_t;

typedef struct c2837x_pc_serial_test_hooks
{
    int (*query_frequency)(uint64_t *frequency_hz, uint32_t *os_error,
        void *user_data);
    int (*query_counter)(uint64_t *ticks, uint32_t *os_error,
        void *user_data);
    int (*open)(const char *path, uintptr_t *native_handle,
        uint32_t *os_error, void *user_data);
    int (*close)(uintptr_t native_handle, uint32_t *os_error,
        void *user_data);
    int (*get_dcb)(uintptr_t native_handle, c2837x_pc_serial_test_dcb_t *dcb,
        uint32_t *os_error, void *user_data);
    int (*set_dcb)(uintptr_t native_handle,
        const c2837x_pc_serial_test_dcb_t *dcb, uint32_t *os_error,
        void *user_data);
    int (*set_timeouts)(uintptr_t native_handle,
        const c2837x_pc_serial_test_timeouts_t *timeouts,
        uint32_t *os_error, void *user_data);
    int (*purge)(uintptr_t native_handle, uint32_t flags,
        uint32_t *os_error, void *user_data);
    int (*read)(uintptr_t native_handle, uint8_t *buffer, uint32_t request,
        uint32_t *transferred, uint32_t *os_error, void *user_data);
    int (*write)(uintptr_t native_handle, const uint8_t *buffer,
        uint32_t request, uint32_t *transferred, uint32_t *os_error,
        void *user_data);
} c2837x_pc_serial_test_hooks_t;

#endif /* C2837X_PC_SERIAL_TEST_SEAM */

typedef struct
{
    uintptr_t native_handle;
    uint32_t com_number;
    uint32_t requested_baud;
    uint32_t last_transfer_count;
    uint32_t last_os_error;
    uint64_t clock_frequency_hz;
    int valid;
    int initialized;
#ifdef C2837X_PC_SERIAL_TEST_SEAM
    struct c2837x_pc_serial_test_hooks hooks;
    void *test_user_data;
    int test_hooks_installed;
#endif
} c2837x_pc_serial_t;

#ifdef C2837X_PC_SERIAL_TEST_SEAM
int c2837x_pc_serial_init_with_test_hooks(c2837x_pc_serial_t *serial,
    const c2837x_pc_serial_test_hooks_t *hooks, void *user_data,
    c2837x_pc_serial_error_t *error);
#endif

void c2837x_pc_serial_error_reset(c2837x_pc_serial_error_t *error,
    const char *operation);

/* Map one transport result into the shared PC diagnostics contract. */
void c2837x_pc_serial_error_to_pc_error(
    const c2837x_pc_serial_error_t *serial_error, const char *instance,
    const char *stage, uint32_t generated_baud, c2837x_pc_error_t *error);

/* Convert a positive logical COM number to a native Windows device path. */
int c2837x_pc_serial_format_path(uint32_t logical_com_number,
    char *path, size_t capacity);

/* Initialize the context and its monotonic clock source. */
int c2837x_pc_serial_init(c2837x_pc_serial_t *serial,
    c2837x_pc_serial_error_t *error);

/* Open one exclusive logical COM port.  This does not configure or purge. */
int c2837x_pc_serial_open(c2837x_pc_serial_t *serial,
    uint32_t logical_com_number, c2837x_pc_serial_error_t *error);

/* Configure the caller-provided Requested/Nominal Baud using fixed 8N1. */
int c2837x_pc_serial_configure(c2837x_pc_serial_t *serial,
    uint32_t requested_baud, c2837x_pc_serial_error_t *error);

/* Clear only the explicitly requested RX/TX queues. */
int c2837x_pc_serial_purge(c2837x_pc_serial_t *serial, uint32_t flags,
    c2837x_pc_serial_error_t *error);

int c2837x_pc_serial_deadline_start(const c2837x_pc_serial_t *serial,
    uint32_t timeout_ms, c2837x_pc_serial_deadline_t *deadline,
    c2837x_pc_serial_error_t *error);

int c2837x_pc_serial_deadline_remaining(
    const c2837x_pc_serial_t *serial,
    const c2837x_pc_serial_deadline_t *deadline, uint32_t *remaining_ms,
    int *expired, c2837x_pc_serial_error_t *error);

/* Raw write-all/read-exact operations with one absolute operation deadline. */
int c2837x_pc_serial_send_all(c2837x_pc_serial_t *serial,
    const uint8_t *data, uint32_t length, uint32_t timeout_ms,
    c2837x_pc_serial_error_t *error);

int c2837x_pc_serial_recv_exact(c2837x_pc_serial_t *serial, uint8_t *data,
    uint32_t length, uint32_t timeout_ms, c2837x_pc_serial_error_t *error);

/* Variants for callers that already own one fixed operation deadline. */
int c2837x_pc_serial_send_all_until(c2837x_pc_serial_t *serial,
    const uint8_t *data, uint32_t length,
    const c2837x_pc_serial_deadline_t *deadline,
    c2837x_pc_serial_error_t *error);

int c2837x_pc_serial_recv_exact_until(c2837x_pc_serial_t *serial, uint8_t *data,
    uint32_t length, const c2837x_pc_serial_deadline_t *deadline,
    c2837x_pc_serial_error_t *error);

/* Close and invalidate the owned native handle. */
void c2837x_pc_serial_close(c2837x_pc_serial_t *serial);

int c2837x_pc_serial_is_valid(const c2837x_pc_serial_t *serial);

/* Obtain text for a saved Windows numeric error code when available. */
int c2837x_pc_serial_get_system_error_text(uint32_t os_error,
    char *buffer, size_t capacity);

#ifdef __cplusplus
}
#endif

#endif /* C2837X_BLOCK_PC_SERIAL_H */
