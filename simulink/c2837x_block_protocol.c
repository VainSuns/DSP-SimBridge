/*
 * C2837xBlock Protocol Layer Implementation
 * Frame packing/unpacking for PC-side C S-Function.
 *
 * Wire format: little-endian, 4-byte header (type + length) + payload.
 */

#include "c2837x_block_protocol.h"
#include "c2837x_block_pc_socket.h"
#include <string.h>

/* ---- Little-endian serialization helpers ---- */

static inline void write_le16(uint8_t* buf, uint16_t val)
{
    buf[0] = (uint8_t)(val & 0xFFu);
    buf[1] = (uint8_t)((val >> 8) & 0xFFu);
}

static inline uint16_t read_le16(const uint8_t* buf)
{
    return (uint16_t)((uint16_t)buf[0] | ((uint16_t)buf[1] << 8));
}

static inline void write_le32(uint8_t* buf, uint32_t val)
{
    buf[0] = (uint8_t)(val & 0xFFu);
    buf[1] = (uint8_t)((val >> 8) & 0xFFu);
    buf[2] = (uint8_t)((val >> 16) & 0xFFu);
    buf[3] = (uint8_t)((val >> 24) & 0xFFu);
}

/* ---- Protocol frame API ---- */

int c2837x_protocol_send_frame(c2837x_socket_t* s,
                               uint16_t type,
                               uint16_t length,
                               const uint8_t* payload,
                               uint32_t timeout_ms)
{
    uint8_t header[C2837X_BLOCK_HEADER_SIZE];

    if (s == NULL) {
        return -1;
    }

    /* Validate: length must be even */
    if (length & 1u) {
        return -1;
    }

    /* Build header: type (LE) + length (LE) */
    write_le16(&header[0], type);
    write_le16(&header[2], length);

    /* Send header */
    if (c2837x_socket_send_all(s, header, C2837X_BLOCK_HEADER_SIZE, timeout_ms) != 0) {
        return -1;
    }

    /* Send payload if present */
    if (length > 0 && payload != NULL) {
        if (c2837x_socket_send_all(s, payload, (uint32_t)length, timeout_ms) != 0) {
            return -1;
        }
    }

    return 0;
}

int c2837x_protocol_recv_frame(c2837x_socket_t* s,
                               uint16_t* type,
                               uint16_t* length,
                               uint8_t* payload,
                               uint32_t payload_capacity,
                               uint32_t timeout_ms)
{
    uint8_t header[C2837X_BLOCK_HEADER_SIZE];
    uint16_t recv_type;
    uint16_t recv_length;

    if (s == NULL || type == NULL || length == NULL) {
        return -1;
    }

    /* Receive header */
    if (c2837x_socket_recv_exact(s, header, C2837X_BLOCK_HEADER_SIZE, timeout_ms) != 0) {
        return -1;
    }

    /* Parse header */
    recv_type = read_le16(&header[0]);
    recv_length = read_le16(&header[2]);

    /* Validate: length must be even */
    if (recv_length & 1u) {
        return -1;
    }

    /* Check payload capacity */
    if (recv_length > payload_capacity) {
        return -1;
    }

    /* Receive payload if present */
    if (recv_length > 0) {
        if (payload == NULL) {
            return -1;
        }
        if (c2837x_socket_recv_exact(s, payload, (uint32_t)recv_length, timeout_ms) != 0) {
            return -1;
        }
    }

    *type = recv_type;
    *length = recv_length;
    return 0;
}

/* ---- Helper functions ---- */

int c2837x_protocol_send_sim_start(c2837x_socket_t* s,
                                   uint16_t protocol_version,
                                   uint32_t config_hash,
                                   uint32_t timeout_ms)
{
    uint8_t payload[C2837X_BLOCK_SIM_START_PAYLOAD_SIZE];

    if (s == NULL) {
        return -1;
    }

    /* Build payload: protocol_version (LE16) + config_hash (LE32) */
    write_le16(&payload[0], protocol_version);
    write_le32(&payload[2], config_hash);

    return c2837x_protocol_send_frame(s,
                                      C2837X_BLOCK_TYPE_SIM_START,
                                      C2837X_BLOCK_SIM_START_PAYLOAD_SIZE,
                                      payload,
                                      timeout_ms);
}

int c2837x_protocol_send_sim_stop(c2837x_socket_t* s,
                                  uint32_t timeout_ms)
{
    if (s == NULL) {
        return -1;
    }

    return c2837x_protocol_send_frame(s,
                                      C2837X_BLOCK_TYPE_SIM_STOP,
                                      0,
                                      NULL,
                                      timeout_ms);
}

int c2837x_protocol_send_input_data(c2837x_socket_t* s,
                                    const uint8_t* payload,
                                    uint16_t length,
                                    uint32_t timeout_ms)
{
    if (s == NULL || payload == NULL) {
        return -1;
    }

    /* Validate: length must be even */
    if (length & 1u) {
        return -1;
    }

    return c2837x_protocol_send_frame(s,
                                      C2837X_BLOCK_TYPE_INPUT_DATA,
                                      length,
                                      payload,
                                      timeout_ms);
}

int c2837x_protocol_wait_response(c2837x_socket_t* s,
                                  uint16_t expected_error,
                                  uint32_t timeout_ms)
{
    uint16_t type;
    uint16_t length;
    uint8_t payload[C2837X_BLOCK_RESPONSE_PAYLOAD_SIZE];
    uint16_t error_code;

    if (s == NULL) {
        return -1;
    }

    /* Receive frame */
    if (c2837x_protocol_recv_frame(s, &type, &length, payload,
                                   sizeof(payload), timeout_ms) != 0) {
        return -1;
    }

    /* Validate: must be RESPONSE type */
    if (type != C2837X_BLOCK_TYPE_RESPONSE) {
        return -1;
    }

    /* Validate: length must be 2 */
    if (length != C2837X_BLOCK_RESPONSE_PAYLOAD_SIZE) {
        return -1;
    }

    /* Parse error code */
    error_code = read_le16(&payload[0]);

    /* Check error code */
    if (error_code != expected_error) {
        return -1;
    }

    return 0;
}

int c2837x_protocol_wait_output_data(c2837x_socket_t* s,
                                     uint8_t* payload,
                                     uint16_t* length,
                                     uint32_t payload_capacity,
                                     uint32_t timeout_ms,
                                     uint16_t* error_code)
{
    uint16_t type;
    uint16_t recv_length;

    if (s == NULL || payload == NULL || length == NULL) {
        return -1;
    }

    /* Initialize error code to none */
    if (error_code != NULL) {
        *error_code = C2837X_BLOCK_ERR_NONE;
    }

    /* Receive frame */
    if (c2837x_protocol_recv_frame(s, &type, &recv_length, payload,
                                   payload_capacity, timeout_ms) != 0) {
        return -1;
    }

    /* Validate: must be OUTPUT_DATA type */
    if (type != C2837X_BLOCK_TYPE_OUTPUT_DATA) {
        /* If we got RESPONSE instead, it's an error from DSP */
        if (type == C2837X_BLOCK_TYPE_RESPONSE) {
            /* Parse error code and return to caller */
            if (recv_length >= C2837X_BLOCK_RESPONSE_PAYLOAD_SIZE) {
                if (error_code != NULL) {
                    *error_code = read_le16(&payload[0]);
                }
            }
        }
        return -1;
    }

    *length = recv_length;
    return 0;
}
