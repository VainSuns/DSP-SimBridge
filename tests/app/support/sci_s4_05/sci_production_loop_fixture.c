#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "axis_alpha_protocol.h"
#include "axis_alpha_sfun_config.h"

#define COM_NUMBER 7u
#define REQUESTED_BAUD 115200u
#define MAX_CALLS 32u
#define MAX_BYTES 128u

typedef struct
{
    uint64_t now;
    uint64_t frequency;
    uintptr_t handle;
    int open_success;
    int get_dcb_success;
    int set_dcb_success;
    int set_timeouts_success;
    int purge_success;
    int read_success;
    int write_success;
    uint32_t open_os_error;
    uint32_t configure_os_error;
    uint32_t read_os_error;
    uint32_t write_os_error;
    char opened_path[32];
    uint32_t open_calls;
    uint32_t close_calls;
    uint32_t purge_calls;
    uint32_t purge_flags;
    c2837x_pc_serial_test_dcb_t driver_dcb;
    c2837x_pc_serial_test_dcb_t configured_dcb;
    uint32_t configured_baud;
    c2837x_pc_serial_test_timeouts_t timeout_history[MAX_CALLS];
    uint32_t timeout_count;
    uint8_t read_source[MAX_BYTES];
    uint32_t read_source_length;
    uint32_t read_offset;
    uint32_t read_plan[MAX_CALLS];
    uint32_t read_plan_count;
    uint32_t read_plan_index;
    uint32_t read_advance_ms;
    uint32_t read_requests[MAX_CALLS];
    uint32_t read_request_count;
    uint8_t write_sink[MAX_BYTES];
    uint32_t write_sink_length;
    uint32_t write_plan[MAX_CALLS];
    uint32_t write_plan_count;
    uint32_t write_plan_index;
    uint32_t write_advance_ms;
    uint32_t write_requests[MAX_CALLS];
    uint32_t write_request_count;
} fake_peer_t;

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
    fake_peer_t *fake = (fake_peer_t *)user_data;
    *frequency_hz = fake->frequency;
    *os_error = 0u;
    return 1;
}

static int fake_query_counter(uint64_t *ticks, uint32_t *os_error,
    void *user_data)
{
    fake_peer_t *fake = (fake_peer_t *)user_data;
    *ticks = fake->now;
    *os_error = 0u;
    return 1;
}

static int fake_open(const char *path, uintptr_t *native_handle,
    uint32_t *os_error, void *user_data)
{
    fake_peer_t *fake = (fake_peer_t *)user_data;
    strncpy(fake->opened_path, path, sizeof(fake->opened_path) - 1u);
    fake->opened_path[sizeof(fake->opened_path) - 1u] = '\0';
    fake->open_calls++;
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
    fake_peer_t *fake = (fake_peer_t *)user_data;
    (void)native_handle;
    fake->close_calls++;
    *os_error = 0u;
    return 1;
}

static int fake_get_dcb(uintptr_t native_handle,
    c2837x_pc_serial_test_dcb_t *dcb, uint32_t *os_error, void *user_data)
{
    fake_peer_t *fake = (fake_peer_t *)user_data;
    (void)native_handle;
    if (!fake->get_dcb_success) {
        *os_error = fake->configure_os_error;
        return 0;
    }
    *dcb = fake->driver_dcb;
    *os_error = 0u;
    return 1;
}

static int fake_set_dcb(uintptr_t native_handle,
    const c2837x_pc_serial_test_dcb_t *dcb, uint32_t *os_error,
    void *user_data)
{
    fake_peer_t *fake = (fake_peer_t *)user_data;
    (void)native_handle;
    if (!fake->set_dcb_success) {
        *os_error = fake->configure_os_error;
        return 0;
    }
    fake->configured_dcb = *dcb;
    fake->configured_baud = dcb->BaudRate;
    *os_error = 0u;
    return 1;
}

static int fake_set_timeouts(uintptr_t native_handle,
    const c2837x_pc_serial_test_timeouts_t *timeouts, uint32_t *os_error,
    void *user_data)
{
    fake_peer_t *fake = (fake_peer_t *)user_data;
    (void)native_handle;
    if (fake->timeout_count < MAX_CALLS) {
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
    fake_peer_t *fake = (fake_peer_t *)user_data;
    (void)native_handle;
    fake->purge_calls++;
    fake->purge_flags = flags;
    if (!fake->purge_success) {
        *os_error = fake->configure_os_error;
        return 0;
    }
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
    fake_peer_t *fake = (fake_peer_t *)user_data;
    uint32_t remaining;
    uint32_t piece;
    (void)native_handle;
    if (fake->read_request_count < MAX_CALLS) {
        fake->read_requests[fake->read_request_count++] = request;
    }
    if (!fake->read_success) {
        *transferred = 0u;
        *os_error = fake->read_os_error;
        return 0;
    }
    remaining = fake->read_offset < fake->read_source_length ?
        fake->read_source_length - fake->read_offset : 0u;
    piece = next_piece(fake->read_plan, fake->read_plan_count,
        &fake->read_plan_index, request);
    if (piece > remaining) piece = remaining;
    if (piece != 0u) {
        memcpy(buffer, fake->read_source + fake->read_offset, piece);
    }
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
    fake_peer_t *fake = (fake_peer_t *)user_data;
    uint32_t piece;
    (void)native_handle;
    if (fake->write_request_count < MAX_CALLS) {
        fake->write_requests[fake->write_request_count++] = request;
    }
    if (!fake->write_success) {
        *transferred = 0u;
        *os_error = fake->write_os_error;
        return 0;
    }
    piece = next_piece(fake->write_plan, fake->write_plan_count,
        &fake->write_plan_index, request);
    if (piece > MAX_BYTES - fake->write_sink_length) {
        *transferred = 0u;
        *os_error = 0xdeadbeefu;
        return 0;
    }
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

static void initialize_fake(fake_peer_t *fake)
{
    memset(fake, 0, sizeof(*fake));
    fake->frequency = 1000u;
    fake->handle = (uintptr_t)0x55u;
    fake->open_success = 1;
    fake->get_dcb_success = 1;
    fake->set_dcb_success = 1;
    fake->set_timeouts_success = 1;
    fake->purge_success = 1;
    fake->read_success = 1;
    fake->write_success = 1;
    fake->driver_dcb.DCBlength = (uint32_t)sizeof(fake->driver_dcb);
    fake->driver_dcb.BaudRate = 38400u;
    fake->driver_dcb.XonChar = 0x11u;
    fake->driver_dcb.XoffChar = 0x13u;
}

static int initialize_serial(fake_peer_t *fake,
    c2837x_pc_serial_t *serial)
{
    c2837x_pc_serial_test_hooks_t hooks = make_hooks();
    c2837x_pc_serial_error_t error;
    if (c2837x_pc_serial_init_with_test_hooks(serial, &hooks, fake,
            &error) != 0) return 0;
    if (c2837x_pc_serial_open(serial, COM_NUMBER, &error) != 0) return 0;
    if (c2837x_pc_serial_configure(serial, REQUESTED_BAUD, &error) != 0) {
        return 0;
    }
    if (c2837x_pc_serial_purge(serial,
            C2837X_PC_SERIAL_PURGE_RX | C2837X_PC_SERIAL_PURGE_TX,
            &error) != 0) return 0;
    return 1;
}

static void reset_pc_error(c2837x_pc_error_t *error)
{
    c2837x_pc_error_reset(error, "axis_alpha", "fixture");
    c2837x_pc_error_set_com_and_baud(error, COM_NUMBER, REQUESTED_BAUD);
}

static void expected_sim_start(uint8_t *frame)
{
    uint32_t hash = AXIS_ALPHA_SFUN_INTERFACE_HASH;
    frame[0] = 0x01u;
    frame[1] = 0x00u;
    frame[2] = 0x06u;
    frame[3] = 0x00u;
    frame[4] = 0x01u;
    frame[5] = 0x00u;
    frame[6] = (uint8_t)(hash & 0xffu);
    frame[7] = (uint8_t)((hash >> 8) & 0xffu);
    frame[8] = (uint8_t)((hash >> 16) & 0xffu);
    frame[9] = (uint8_t)((hash >> 24) & 0xffu);
}

static int configuration_matches(const fake_peer_t *fake)
{
    const c2837x_pc_serial_test_dcb_t *dcb = &fake->configured_dcb;
    return strcmp(fake->opened_path, "\\\\.\\COM7") == 0 &&
        fake->configured_baud == REQUESTED_BAUD &&
        dcb->BaudRate == REQUESTED_BAUD && dcb->ByteSize == 8u &&
        dcb->Parity == 0u && dcb->StopBits == 0u && dcb->fBinary == 1u &&
        dcb->fOutX == 0u && dcb->fInX == 0u &&
        dcb->fOutxCtsFlow == 0u && dcb->fOutxDsrFlow == 0u &&
        dcb->fDsrSensitivity == 0u && dcb->fTXContinueOnXoff == 1u &&
        dcb->fParity == 0u && dcb->fErrorChar == 0u &&
        dcb->fNull == 0u && dcb->fAbortOnError == 0u &&
        dcb->fDtrControl == 0u && dcb->fRtsControl == 0u &&
        fake->purge_calls == 1u && fake->purge_flags ==
            (C2837X_PC_SERIAL_PURGE_RX | C2837X_PC_SERIAL_PURGE_TX);
}

static int test_happy_path(void)
{
    static const uint8_t response_and_output[] = {
        0x05u, 0x00u, 0x02u, 0x00u, 0x00u, 0x00u,
        0x03u, 0x00u, 0x06u, 0x00u, 0x00u, 0x00u,
        0x00u, 0x00u, 0xefu, 0xbeu};
    static const uint8_t expected_input[] = {
        0x02u, 0x00u, 0x06u, 0x00u, 0x00u, 0x00u,
        0x00u, 0x00u, 0x34u, 0x12u};
    static const uint8_t expected_output_payload[] = {
        0x00u, 0x00u, 0x00u, 0x00u, 0xefu, 0xbeu};
    fake_peer_t fake;
    c2837x_pc_serial_t serial;
    c2837x_pc_error_t error;
    uint8_t expected_start[10];
    uint8_t input_frame[10] = {0u};
    uint8_t output_payload[6] = {0u};
    uint16_t output_length = 0u;

    initialize_fake(&fake);
    memcpy(fake.read_source, response_and_output,
        sizeof(response_and_output));
    fake.read_source_length = sizeof(response_and_output);
    fake.read_plan[0] = 1u;
    fake.read_plan[1] = 1u;
    fake.read_plan[2] = 2u;
    fake.read_plan[3] = 1u;
    fake.read_plan[4] = 1u;
    fake.read_plan[5] = 1u;
    fake.read_plan[6] = 1u;
    fake.read_plan[7] = 2u;
    fake.read_plan[8] = 2u;
    fake.read_plan[9] = 2u;
    fake.read_plan[10] = 2u;
    fake.read_plan_count = 11u;
    fake.read_advance_ms = 1u;
    fake.write_plan[0] = 2u;
    fake.write_plan[1] = 3u;
    fake.write_plan[2] = 5u;
    fake.write_plan[3] = 1u;
    fake.write_plan[4] = 2u;
    fake.write_plan[5] = 7u;
    fake.write_plan_count = 6u;

    if (!check(initialize_serial(&fake, &serial),
            "happy serial initialization")) return 0;
    if (!check(configuration_matches(&fake),
            "happy COM7 115200 8N1 purge")) return 0;

    expected_sim_start(expected_start);
    reset_pc_error(&error);
    if (!check(axis_alpha_protocol_send_sim_start(&serial,
            AXIS_ALPHA_PROTOCOL_VERSION, AXIS_ALPHA_SFUN_INTERFACE_HASH,
            100u, &error) == 0, "happy SIM_START send")) return 0;
    if (!check(fake.write_sink_length == sizeof(expected_start) &&
            memcmp(fake.write_sink, expected_start, sizeof(expected_start)) == 0,
            "happy SIM_START bytes and interface hash")) return 0;
    if (!check(axis_alpha_protocol_wait_response(&serial, 100u, &error) == 0,
            "happy RESPONSE OK")) return 0;

    input_frame[4] = 0x00u;
    input_frame[5] = 0x00u;
    input_frame[6] = 0x00u;
    input_frame[7] = 0x00u;
    input_frame[8] = 0x34u;
    input_frame[9] = 0x12u;
    reset_pc_error(&error);
    if (!check(axis_alpha_protocol_send_input_data(&serial, input_frame, 6u,
            100u, &error) == 0, "happy INPUT_DATA send")) return 0;
    if (!check(fake.write_sink_length == sizeof(expected_start) +
            sizeof(expected_input) &&
            memcmp(fake.write_sink + sizeof(expected_start), expected_input,
                sizeof(expected_input)) == 0,
            "happy INPUT_DATA bytes")) return 0;
    if (!check(axis_alpha_protocol_wait_output_data(&serial, output_payload,
            &output_length, sizeof(output_payload), 100u, &error) == 0,
            "happy OUTPUT_DATA receive")) return 0;
    if (!check(output_length == sizeof(expected_output_payload) &&
            memcmp(output_payload, expected_output_payload,
                sizeof(expected_output_payload)) == 0,
            "happy OUTPUT_DATA step and uint16 sentinel")) return 0;
    if (!check(fake.open_calls == 1u && fake.write_request_count == 6u &&
            fake.read_request_count == 11u &&
            c2837x_pc_serial_is_valid(&serial),
            "happy partial write/read without resend")) return 0;

    c2837x_pc_serial_close(&serial);
    return check(fake.close_calls == 1u &&
            !c2837x_pc_serial_is_valid(&serial), "happy session cleanup");
}

static int test_deadline_timeout(void)
{
    static const uint8_t partial_response[] = {0x05u, 0x00u};
    fake_peer_t fake;
    c2837x_pc_serial_t serial;
    c2837x_pc_error_t error;
    uint32_t timeout_start;

    initialize_fake(&fake);
    memcpy(fake.read_source, partial_response, sizeof(partial_response));
    fake.read_source_length = sizeof(partial_response);
    fake.read_plan[0] = 2u;
    fake.read_plan_count = 1u;
    fake.read_advance_ms = 3u;
    if (!check(initialize_serial(&fake, &serial),
            "deadline serial initialization")) return 0;
    timeout_start = fake.timeout_count;
    reset_pc_error(&error);
    if (!check(axis_alpha_protocol_wait_response(&serial, 5u, &error) != 0,
            "deadline response fails")) return 0;
    if (!check(error.kind == C2837X_PC_ERROR_TIMEOUT &&
            strcmp(error.stage, "recv_header") == 0 &&
            error.expected_length == 4u && error.actual_length == 2u &&
            serial.last_transfer_count == 2u &&
            !c2837x_pc_serial_is_valid(&serial),
            "deadline timeout preserves partial progress")) return 0;
    if (!check(fake.close_calls == 1u && fake.open_calls == 1u &&
            fake.write_request_count == 0u && fake.timeout_count >=
                timeout_start + 2u &&
            fake.timeout_history[timeout_start + 1u].
                read_total_timeout_constant <=
                fake.timeout_history[timeout_start].
                read_total_timeout_constant,
            "deadline is absolute without retry or reopen")) return 0;
    return 1;
}

static int test_serial_error(void)
{
    const uint32_t expected_os_error = 4321u;
    fake_peer_t fake;
    c2837x_pc_serial_t serial;
    c2837x_pc_error_t error;

    initialize_fake(&fake);
    fake.write_success = 0;
    fake.write_os_error = expected_os_error;
    if (!check(initialize_serial(&fake, &serial),
            "serial error initialization")) return 0;
    reset_pc_error(&error);
    if (!check(axis_alpha_protocol_send_sim_start(&serial,
            AXIS_ALPHA_PROTOCOL_VERSION, AXIS_ALPHA_SFUN_INTERFACE_HASH,
            100u, &error) != 0, "serial error send fails")) return 0;
    if (!check(error.kind == C2837X_PC_ERROR_SERIAL &&
            strcmp(error.stage, "send_frame") == 0 &&
            error.com_number == COM_NUMBER &&
            error.requested_baud == REQUESTED_BAUD &&
            (error.available & C2837X_PC_ERROR_HAS_OS_ERROR_CODE) != 0u &&
            error.os_error_code == expected_os_error &&
            !c2837x_pc_serial_is_valid(&serial),
            "serial error category stage COM baud OS code")) return 0;
    return check(fake.open_calls == 1u && fake.close_calls == 1u &&
        fake.write_request_count == 1u, "serial error no retry or reopen");
}

static int test_protocol_error(void)
{
    static const uint8_t dsp_error_response[] = {
        0x05u, 0x00u, 0x02u, 0x00u, 0x04u, 0x00u};
    fake_peer_t fake;
    c2837x_pc_serial_t serial;
    c2837x_pc_error_t error;

    initialize_fake(&fake);
    memcpy(fake.read_source, dsp_error_response,
        sizeof(dsp_error_response));
    fake.read_source_length = sizeof(dsp_error_response);
    fake.read_plan[0] = 4u;
    fake.read_plan[1] = 2u;
    fake.read_plan_count = 2u;
    if (!check(initialize_serial(&fake, &serial),
            "protocol error initialization")) return 0;
    reset_pc_error(&error);
    if (!check(axis_alpha_protocol_send_sim_start(&serial,
            AXIS_ALPHA_PROTOCOL_VERSION, AXIS_ALPHA_SFUN_INTERFACE_HASH,
            100u, &error) == 0, "protocol error SIM_START send")) return 0;
    reset_pc_error(&error);
    if (!check(axis_alpha_protocol_wait_response(&serial, 100u, &error) != 0,
            "protocol DSP error fails")) return 0;
    if (!check(error.kind == C2837X_PC_ERROR_DSP_RESPONSE &&
            strcmp(error.stage, "wait_response") == 0 &&
            error.dsp_error == AXIS_ALPHA_ERR_STATE &&
            !c2837x_pc_serial_is_valid(&serial),
            "protocol error parser category and cleanup")) return 0;
    return check(fake.open_calls == 1u && fake.close_calls == 1u &&
        fake.write_request_count == 1u && fake.read_request_count == 2u,
        "protocol error no retry resync or resend");
}

int main(void)
{
    int passed = 0;
    int failed = 0;

    if (test_happy_path()) {
        printf("SCI_PRODUCTION_LOOP happy_path=PASS\n");
        passed++;
    } else {
        printf("SCI_PRODUCTION_LOOP happy_path=FAIL\n");
        failed++;
    }
    if (test_deadline_timeout()) {
        printf("SCI_PRODUCTION_LOOP deadline_timeout=PASS\n");
        passed++;
    } else {
        printf("SCI_PRODUCTION_LOOP deadline_timeout=FAIL\n");
        failed++;
    }
    if (test_serial_error()) {
        printf("SCI_PRODUCTION_LOOP serial_error=PASS\n");
        passed++;
    } else {
        printf("SCI_PRODUCTION_LOOP serial_error=FAIL\n");
        failed++;
    }
    if (test_protocol_error()) {
        printf("SCI_PRODUCTION_LOOP protocol_error=PASS\n");
        passed++;
    } else {
        printf("SCI_PRODUCTION_LOOP protocol_error=FAIL\n");
        failed++;
    }
    printf("SUMMARY passed=%d failed=%d\n", passed, failed);
    return failed == 0 ? 0 : 1;
}
