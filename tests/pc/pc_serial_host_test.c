/*
 * Focused SCI-S4-01 host test.
 *
 * The fake callbacks replace only Win32/QPC external effects.  All assertions
 * exercise the production c2837x_block_pc_serial.c implementation.
 */

#include "c2837x_block_pc_serial.h"

#include <stdio.h>
#include <string.h>

#define FAKE_MAX_CALLS 32u

typedef struct
{
    uint64_t now;
    uint64_t frequency;
    uintptr_t handle;
    int open_success;
    uint32_t open_os_error;
    char opened_path[64];
    uint32_t close_calls;
    uint32_t configured_baud;
    c2837x_pc_serial_test_dcb_t configured_dcb;
    c2837x_pc_serial_test_timeouts_t timeout_history[FAKE_MAX_CALLS];
    uint32_t timeout_count;
    int get_dcb_success;
    int set_dcb_success;
    int set_timeouts_success;
    uint32_t configure_os_error;
    uint32_t purge_calls;
    uint32_t purge_flags;
    uint8_t read_source[64];
    uint32_t read_source_length;
    uint32_t read_offset;
    uint32_t read_plan[FAKE_MAX_CALLS];
    uint32_t read_plan_count;
    uint32_t read_plan_index;
    uint32_t read_advance_ms;
    int read_success;
    uint32_t read_os_error;
    uint32_t read_requests[FAKE_MAX_CALLS];
    uint32_t read_request_count;
    uint8_t write_sink[64];
    uint32_t write_sink_length;
    uint32_t write_plan[FAKE_MAX_CALLS];
    uint32_t write_plan_count;
    uint32_t write_plan_index;
    uint32_t write_advance_ms;
    int write_success;
    uint32_t write_os_error;
    uint32_t write_requests[FAKE_MAX_CALLS];
    uint32_t write_request_count;
} fake_serial_t;

static int check(int condition, const char *message)
{
    if (!condition) {
        fprintf(stderr, "FAIL %s\n", message);
        return 0;
    }
    return 1;
}

static int fake_query_frequency(uint64_t *frequency_hz, uint32_t *os_error,
    void *user_data)
{
    fake_serial_t *fake = (fake_serial_t *)user_data;
    *frequency_hz = fake->frequency;
    *os_error = 0u;
    return 1;
}

static int fake_query_counter(uint64_t *ticks, uint32_t *os_error,
    void *user_data)
{
    fake_serial_t *fake = (fake_serial_t *)user_data;
    *ticks = fake->now;
    *os_error = 0u;
    return 1;
}

static int fake_open(const char *path, uintptr_t *native_handle,
    uint32_t *os_error, void *user_data)
{
    fake_serial_t *fake = (fake_serial_t *)user_data;
    strncpy(fake->opened_path, path, sizeof(fake->opened_path) - 1u);
    fake->opened_path[sizeof(fake->opened_path) - 1u] = '\0';
    if (!fake->open_success) {
        *os_error = fake->open_os_error;
        return 0;
    }
    *native_handle = fake->handle;
    *os_error = 0u;
    return 1;
}

static int fake_close(uintptr_t native_handle, uint32_t *os_error,
    void *user_data)
{
    fake_serial_t *fake = (fake_serial_t *)user_data;
    (void)native_handle;
    fake->close_calls++;
    *os_error = 0u;
    return 1;
}

static int fake_get_dcb(uintptr_t native_handle,
    c2837x_pc_serial_test_dcb_t *dcb, uint32_t *os_error, void *user_data)
{
    fake_serial_t *fake = (fake_serial_t *)user_data;
    (void)native_handle;
    if (!fake->get_dcb_success) {
        *os_error = fake->configure_os_error;
        return 0;
    }
    memset(dcb, 0, sizeof(*dcb));
    *os_error = 0u;
    return 1;
}

static int fake_set_dcb(uintptr_t native_handle,
    const c2837x_pc_serial_test_dcb_t *dcb, uint32_t *os_error,
    void *user_data)
{
    fake_serial_t *fake = (fake_serial_t *)user_data;
    (void)native_handle;
    if (!fake->set_dcb_success) {
        *os_error = fake->configure_os_error;
        return 0;
    }
    fake->configured_dcb = *dcb;
    fake->configured_baud = dcb->baud_rate;
    *os_error = 0u;
    return 1;
}

static int fake_set_timeouts(uintptr_t native_handle,
    const c2837x_pc_serial_test_timeouts_t *timeouts, uint32_t *os_error,
    void *user_data)
{
    fake_serial_t *fake = (fake_serial_t *)user_data;
    (void)native_handle;
    if (fake->timeout_count < FAKE_MAX_CALLS) {
        fake->timeout_history[fake->timeout_count++] = *timeouts;
    }
    if (!fake->set_timeouts_success) {
        *os_error = fake->configure_os_error;
        return 0;
    }
    *os_error = 0u;
    return 1;
}

static int fake_purge(uintptr_t native_handle, uint32_t flags,
    uint32_t *os_error, void *user_data)
{
    fake_serial_t *fake = (fake_serial_t *)user_data;
    (void)native_handle;
    fake->purge_calls++;
    fake->purge_flags = flags;
    *os_error = 0u;
    return 1;
}

static uint32_t next_piece(const uint32_t *plan, uint32_t plan_count,
    uint32_t *plan_index, uint32_t request)
{
    uint32_t piece = request;
    if (*plan_index < plan_count) {
        piece = plan[(*plan_index)++];
    }
    return piece < request ? piece : request;
}

static int fake_read(uintptr_t native_handle, uint8_t *buffer,
    uint32_t request, uint32_t *transferred, uint32_t *os_error,
    void *user_data)
{
    fake_serial_t *fake = (fake_serial_t *)user_data;
    uint32_t piece;
    (void)native_handle;
    if (fake->read_request_count < FAKE_MAX_CALLS) {
        fake->read_requests[fake->read_request_count++] = request;
    }
    if (!fake->read_success) {
        *transferred = 0u;
        *os_error = fake->read_os_error;
        return 0;
    }
    piece = next_piece(fake->read_plan, fake->read_plan_count,
        &fake->read_plan_index, request);
    if (piece > fake->read_source_length - fake->read_offset) {
        piece = fake->read_source_length - fake->read_offset;
    }
    memcpy(buffer, fake->read_source + fake->read_offset, piece);
    fake->read_offset += piece;
    fake->now += fake->read_advance_ms;
    *transferred = piece;
    *os_error = 0u;
    return 1;
}

static int fake_write(uintptr_t native_handle, const uint8_t *buffer,
    uint32_t request, uint32_t *transferred, uint32_t *os_error,
    void *user_data)
{
    fake_serial_t *fake = (fake_serial_t *)user_data;
    uint32_t piece;
    (void)native_handle;
    if (fake->write_request_count < FAKE_MAX_CALLS) {
        fake->write_requests[fake->write_request_count++] = request;
    }
    if (!fake->write_success) {
        *transferred = 0u;
        *os_error = fake->write_os_error;
        return 0;
    }
    piece = next_piece(fake->write_plan, fake->write_plan_count,
        &fake->write_plan_index, request);
    memcpy(fake->write_sink + fake->write_sink_length, buffer, piece);
    fake->write_sink_length += piece;
    fake->now += fake->write_advance_ms;
    *transferred = piece;
    *os_error = 0u;
    return 1;
}

static c2837x_pc_serial_test_hooks_t make_hooks(void)
{
    c2837x_pc_serial_test_hooks_t hooks;
    memset(&hooks, 0, sizeof(hooks));
    hooks.query_frequency = fake_query_frequency;
    hooks.query_counter = fake_query_counter;
    hooks.open = fake_open;
    hooks.close = fake_close;
    hooks.get_dcb = fake_get_dcb;
    hooks.set_dcb = fake_set_dcb;
    hooks.set_timeouts = fake_set_timeouts;
    hooks.purge = fake_purge;
    hooks.read = fake_read;
    hooks.write = fake_write;
    return hooks;
}

static int initialize_serial(fake_serial_t *fake,
    c2837x_pc_serial_t *serial, c2837x_pc_serial_error_t *error)
{
    c2837x_pc_serial_test_hooks_t hooks = make_hooks();
    return c2837x_pc_serial_init_with_test_hooks(serial, &hooks, fake, error);
}

static void initialize_fake(fake_serial_t *fake)
{
    memset(fake, 0, sizeof(*fake));
    fake->frequency = 1000u;
    fake->handle = (uintptr_t)0x55u;
    fake->open_success = 1;
    fake->get_dcb_success = 1;
    fake->set_dcb_success = 1;
    fake->set_timeouts_success = 1;
    fake->read_success = 1;
    fake->write_success = 1;
}

static int test_com_paths(void)
{
    fake_serial_t fake;
    c2837x_pc_serial_t serial;
    c2837x_pc_serial_error_t error;
    char path[32];

    initialize_fake(&fake);
    if (!check(c2837x_pc_serial_format_path(5u, path, sizeof(path)) == 0 &&
            strcmp(path, "\\\\.\\COM5") == 0, "COM5 path")) return 0;
    if (!check(c2837x_pc_serial_format_path(12u, path, sizeof(path)) == 0 &&
            strcmp(path, "\\\\.\\COM12") == 0, "COM12 path")) return 0;
    if (!check(initialize_serial(&fake, &serial, &error) == 0,
            "init for COM paths")) return 0;
    if (!check(c2837x_pc_serial_open(&serial, 5u, &error) == 0 &&
            strcmp(fake.opened_path, "\\\\.\\COM5") == 0,
            "open COM5 through production path")) return 0;
    c2837x_pc_serial_close(&serial);
    if (!check(c2837x_pc_serial_open(&serial, 12u, &error) == 0 &&
            strcmp(fake.opened_path, "\\\\.\\COM12") == 0,
            "open COM12 through production path")) return 0;
    c2837x_pc_serial_close(&serial);
    return check(fake.close_calls == 2u, "close owns both opened handles");
}

static int open_and_configure(fake_serial_t *fake,
    c2837x_pc_serial_t *serial, c2837x_pc_serial_error_t *error)
{
    if (!check(initialize_serial(fake, serial, error) == 0, "serial init")) {
        return 0;
    }
    if (!check(c2837x_pc_serial_open(serial, 12u, error) == 0,
            "serial open")) return 0;
    if (!check(c2837x_pc_serial_configure(serial, 57600u, error) == 0,
            "serial configure")) return 0;
    return 1;
}

static int test_configuration_and_purge(void)
{
    fake_serial_t fake;
    c2837x_pc_serial_t serial;
    c2837x_pc_serial_error_t error;
    c2837x_pc_serial_test_dcb_t *dcb;

    initialize_fake(&fake);
    if (!check(open_and_configure(&fake, &serial, &error),
            "configuration setup")) return 0;
    dcb = &fake.configured_dcb;
    if (!check(fake.configured_baud == 57600u && dcb->byte_size == 8u &&
            dcb->parity == 0u && dcb->stop_bits == 0u && dcb->binary == 1u,
            "requested baud and 8N1")) return 0;
    if (!check(dcb->out_x == 0u && dcb->in_x == 0u &&
            dcb->out_cts_flow == 0u && dcb->out_dsr_flow == 0u &&
            dcb->dsr_sensitivity == 0u && dcb->tx_continue_on_xoff == 1u,
            "software and hardware flow control disabled")) return 0;
    if (!check(dcb->dtr_control == 0u && dcb->rts_control == 0u,
            "DTR and RTS inactive")) return 0;
    if (!check(fake.purge_calls == 0u, "configure does not auto-purge")) return 0;
    if (!check(c2837x_pc_serial_purge(&serial,
            C2837X_PC_SERIAL_PURGE_RX | C2837X_PC_SERIAL_PURGE_TX,
            &error) == 0 && fake.purge_calls == 1u &&
            fake.purge_flags == (C2837X_PC_SERIAL_PURGE_RX |
                C2837X_PC_SERIAL_PURGE_TX), "explicit RX/TX purge")) return 0;
    c2837x_pc_serial_close(&serial);
    return 1;
}

static int test_partial_write(void)
{
    static const uint8_t source[] = {1u, 2u, 3u, 4u, 5u, 6u};
    fake_serial_t fake;
    c2837x_pc_serial_t serial;
    c2837x_pc_serial_error_t error;

    initialize_fake(&fake);
    fake.write_plan[0] = 2u;
    fake.write_plan[1] = 1u;
    fake.write_plan[2] = 3u;
    fake.write_plan_count = 3u;
    fake.write_advance_ms = 1u;
    if (!check(open_and_configure(&fake, &serial, &error),
            "partial write setup")) return 0;
    if (!check(c2837x_pc_serial_send_all(&serial, source, sizeof(source), 20u,
            &error) == 0, "partial write completes")) return 0;
    if (!check(fake.write_sink_length == sizeof(source) &&
            memcmp(fake.write_sink, source, sizeof(source)) == 0 &&
            serial.last_transfer_count == sizeof(source) &&
            c2837x_pc_serial_is_valid(&serial),
            "write-all preserves all partial progress")) return 0;
    if (!check(fake.write_request_count == 3u && fake.write_requests[0] == 6u &&
            fake.write_requests[1] == 4u && fake.write_requests[2] == 3u,
            "write requests contain only remaining bytes")) return 0;
    c2837x_pc_serial_close(&serial);
    return 1;
}

static int test_partial_read(void)
{
    static const uint8_t source[] = {9u, 8u, 7u, 6u, 5u};
    uint8_t received[sizeof(source)] = {0u};
    fake_serial_t fake;
    c2837x_pc_serial_t serial;
    c2837x_pc_serial_error_t error;

    initialize_fake(&fake);
    memcpy(fake.read_source, source, sizeof(source));
    fake.read_source_length = sizeof(source);
    fake.read_plan[0] = 1u;
    fake.read_plan[1] = 2u;
    fake.read_plan[2] = 2u;
    fake.read_plan_count = 3u;
    fake.read_advance_ms = 1u;
    if (!check(open_and_configure(&fake, &serial, &error),
            "partial read setup")) return 0;
    if (!check(c2837x_pc_serial_recv_exact(&serial, received, sizeof(received),
            20u, &error) == 0, "partial read completes")) return 0;
    if (!check(memcmp(received, source, sizeof(source)) == 0 &&
            serial.last_transfer_count == sizeof(source) &&
            c2837x_pc_serial_is_valid(&serial),
            "read-exact preserves all partial progress")) return 0;
    if (!check(fake.read_request_count == 3u && fake.read_requests[0] == 5u &&
            fake.read_requests[1] == 4u && fake.read_requests[2] == 2u,
            "read requests contain only remaining bytes")) return 0;
    c2837x_pc_serial_close(&serial);
    return 1;
}

static int test_absolute_deadline(void)
{
    static const uint8_t source[] = {0xa1u, 0xb2u, 0xc3u, 0xd4u};
    uint8_t received[sizeof(source)] = {0u};
    fake_serial_t fake;
    c2837x_pc_serial_t serial;
    c2837x_pc_serial_error_t error;
    uint32_t operation_timeout_count;
    uint32_t index;

    initialize_fake(&fake);
    memcpy(fake.read_source, source, sizeof(source));
    fake.read_source_length = sizeof(source);
    fake.read_plan[0] = 1u;
    fake.read_plan[1] = 1u;
    fake.read_plan[2] = 1u;
    fake.read_plan[3] = 1u;
    fake.read_plan_count = 4u;
    fake.read_advance_ms = 4u;
    if (!check(open_and_configure(&fake, &serial, &error),
            "deadline setup")) return 0;
    operation_timeout_count = fake.timeout_count;
    if (!check(c2837x_pc_serial_recv_exact(&serial, received, sizeof(received),
            10u, &error) == -1, "deadline expires")) return 0;
    if (!check(error.kind == C2837X_PC_SERIAL_ERROR_TIMEOUT &&
            error.transferred_bytes == 3u && serial.last_transfer_count == 3u &&
            !c2837x_pc_serial_is_valid(&serial),
            "timeout preserves partial count and closes")) return 0;
    if (!check(fake.timeout_count >= operation_timeout_count + 3u,
            "deadline installs bounded timeout for each partial call")) return 0;
    for (index = operation_timeout_count; index < fake.timeout_count; ++index) {
        if (!check(fake.timeout_history[index].read_total_timeout_constant <=
                10u, "partial read timeout never exceeds operation timeout")) {
            return 0;
        }
        if (index > operation_timeout_count && !check(
                fake.timeout_history[index].read_total_timeout_constant <=
                    fake.timeout_history[index - 1u].read_total_timeout_constant,
                "partial read timeout does not refresh")) return 0;
    }
    return 1;
}

static int test_error_propagation(void)
{
    fake_serial_t fake;
    c2837x_pc_serial_t serial;
    c2837x_pc_serial_error_t error;
    static const uint8_t byte = 0x5au;
    uint8_t received_byte = 0u;

    initialize_fake(&fake);
    fake.open_success = 0;
    fake.open_os_error = 1234u;
    if (!check(initialize_serial(&fake, &serial, &error) == 0,
            "open error setup")) return 0;
    if (!check(c2837x_pc_serial_open(&serial, 5u, &error) == -1 &&
            error.kind == C2837X_PC_SERIAL_ERROR_OS && error.os_error == 1234u &&
            serial.last_os_error == 1234u && !c2837x_pc_serial_is_valid(&serial),
            "open preserves numeric OS error")) return 0;

    initialize_fake(&fake);
    fake.set_dcb_success = 0;
    fake.configure_os_error = 2345u;
    if (!check(initialize_serial(&fake, &serial, &error) == 0 &&
            c2837x_pc_serial_open(&serial, 5u, &error) == 0 &&
            c2837x_pc_serial_configure(&serial, 57600u, &error) == -1 &&
            error.os_error == 2345u && serial.last_os_error == 2345u,
            "configure preserves numeric OS error")) return 0;

    initialize_fake(&fake);
    fake.write_success = 0;
    fake.write_os_error = 3456u;
    if (!check(initialize_serial(&fake, &serial, &error) == 0 &&
            c2837x_pc_serial_open(&serial, 5u, &error) == 0 &&
            c2837x_pc_serial_configure(&serial, 57600u, &error) == 0 &&
            c2837x_pc_serial_send_all(&serial, &byte, 1u, 20u, &error) == -1 &&
            error.os_error == 3456u && serial.last_os_error == 3456u,
            "write preserves numeric OS error")) return 0;

    initialize_fake(&fake);
    fake.read_success = 0;
    fake.read_os_error = 4567u;
    if (!check(initialize_serial(&fake, &serial, &error) == 0 &&
            c2837x_pc_serial_open(&serial, 5u, &error) == 0 &&
            c2837x_pc_serial_configure(&serial, 57600u, &error) == 0 &&
            c2837x_pc_serial_recv_exact(&serial, &received_byte, 1u, 20u,
                &error) == -1 && error.os_error == 4567u &&
            serial.last_os_error == 4567u,
            "read preserves numeric OS error")) return 0;
    return 1;
}

static int test_system_error_text(void)
{
    char buffer[128];
    int status = c2837x_pc_serial_get_system_error_text(2u, buffer,
        sizeof(buffer));
#ifdef _WIN32
    return check(status == 0 && buffer[0] != '\0',
        "Windows system error text helper");
#else
    (void)status;
    return 1;
#endif
}

int main(void)
{
    if (!test_com_paths()) return 1;
    printf("PASS com_path\n");
    if (!test_configuration_and_purge()) return 1;
    printf("PASS configuration_and_purge\n");
    if (!test_partial_write()) return 1;
    printf("PASS partial_write\n");
    if (!test_partial_read()) return 1;
    printf("PASS partial_read\n");
    if (!test_absolute_deadline()) return 1;
    printf("PASS absolute_deadline\n");
    if (!test_error_propagation()) return 1;
    printf("PASS error_propagation\n");
    if (!test_system_error_text()) return 1;
    printf("PASS system_error_text\n");
    printf("SUMMARY passed=7 failed=0\n");
    return 0;
}
