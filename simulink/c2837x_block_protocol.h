#ifndef C2837X_BLOCK_PROTOCOL_H
#define C2837X_BLOCK_PROTOCOL_H

/*
 * C2837xBlock Protocol Layer
 * Frame packing/unpacking for PC-side C S-Function.
 *
 * Wire format: little-endian, 4-byte header (type + length) + payload.
 * Length field represents TCP wire bytes (8-bit), always even.
 */

#include <stdint.h>
#include "c2837x_block_pc_socket.h"

#ifdef __cplusplus
extern "C" {
#endif

/* ---- Protocol constants ---- */

/* Message types (uint16_t, little-endian on wire) */
#define C2837X_BLOCK_TYPE_SIM_START    0x0001u
#define C2837X_BLOCK_TYPE_INPUT_DATA   0x0002u
#define C2837X_BLOCK_TYPE_OUTPUT_DATA  0x0003u
#define C2837X_BLOCK_TYPE_SIM_STOP     0x0004u
#define C2837X_BLOCK_TYPE_RESPONSE     0x0005u

/* Response error codes (uint16_t, in RESPONSE payload) */
/* Must match DSP error codes in dsp/inc/c2837x_block_protocol.h */
#define C2837X_BLOCK_ERR_NONE                0u  /* Success */
#define C2837X_BLOCK_ERR_UNKNOWN_TYPE        1u  /* Unknown message type */
#define C2837X_BLOCK_ERR_LENGTH              2u  /* Invalid payload length */
#define C2837X_BLOCK_ERR_CONFIG_HASH         3u  /* Config hash mismatch */
#define C2837X_BLOCK_ERR_STATE               4u  /* Invalid state for message */
#define C2837X_BLOCK_ERR_INTERNAL            5u  /* Internal DSP error */
#define C2837X_BLOCK_ERR_PROTOCOL_VERSION    6u  /* Protocol version mismatch */
#define C2837X_BLOCK_ERR_STEP_INDEX          7u  /* Step index mismatch */
#define C2837X_BLOCK_ERR_UNSUPPORTED_TYPE    8u  /* Unsupported data type or ABI */

/* SIM_START payload: protocol_version (uint16) + config_hash (uint32) = 6 bytes */
#define C2837X_BLOCK_SIM_START_PAYLOAD_SIZE  6u

/* RESPONSE payload: error_code (uint16) = 2 bytes */
#define C2837X_BLOCK_RESPONSE_PAYLOAD_SIZE   2u

/* Header size: type (uint16) + length (uint16) = 4 bytes */
#define C2837X_BLOCK_HEADER_SIZE             4u

/* ---- Protocol frame API (implemented in c2837x_block_protocol.c) ---- */

/*
 * Send a protocol frame: header (type + length) + payload.
 * - type: message type (C2837X_BLOCK_TYPE_*)
 * - length: payload wire bytes (must be even)
 * - payload: payload data (can be NULL if length == 0)
 * - timeout_ms: send timeout
 *
 * Returns 0 on success, -1 on error.
 */
int c2837x_protocol_send_frame(c2837x_socket_t* s,
                               uint16_t type,
                               uint16_t length,
                               const uint8_t* payload,
                               uint32_t timeout_ms);

/*
 * Receive a protocol frame: header + payload.
 * - type: received message type (output)
 * - length: received payload length (output)
 * - payload: buffer for payload data
 * - payload_capacity: buffer capacity in bytes
 * - timeout_ms: receive timeout
 *
 * Returns 0 on success, -1 on error.
 * If payload_capacity < received length, returns -1 (payload too large).
 */
int c2837x_protocol_recv_frame(c2837x_socket_t* s,
                               uint16_t* type,
                               uint16_t* length,
                               uint8_t* payload,
                               uint32_t payload_capacity,
                               uint32_t timeout_ms);

/*
 * Helper: Send SIM_START frame.
 * - protocol_version: protocol version (should be C2837X_BLOCK_PROTOCOL_VERSION)
 * - config_hash: configuration hash
 * - timeout_ms: send timeout
 *
 * Returns 0 on success, -1 on error.
 */
int c2837x_protocol_send_sim_start(c2837x_socket_t* s,
                                   uint16_t protocol_version,
                                   uint32_t config_hash,
                                   uint32_t timeout_ms);

/*
 * Helper: Send SIM_STOP frame.
 * Returns 0 on success, -1 on error.
 */
int c2837x_protocol_send_sim_stop(c2837x_socket_t* s,
                                  uint32_t timeout_ms);

/*
 * Helper: Send INPUT_DATA frame.
 * - payload: serialized input payload (step_index + input data)
 * - length: payload length in bytes
 * - timeout_ms: send timeout
 *
 * Returns 0 on success, -1 on error.
 */
int c2837x_protocol_send_input_data(c2837x_socket_t* s,
                                    const uint8_t* payload,
                                    uint16_t length,
                                    uint32_t timeout_ms);

/*
 * Helper: Wait for RESPONSE frame and check error code.
 * - expected_error: expected error code (0 for success)
 * - timeout_ms: receive timeout
 *
 * Returns 0 if RESPONSE received with expected error code, -1 otherwise.
 */
int c2837x_protocol_wait_response(c2837x_socket_t* s,
                                  uint16_t expected_error,
                                  uint32_t timeout_ms);

/*
 * Helper: Wait for OUTPUT_DATA frame.
 * - payload: buffer for payload data (output)
 * - length: received payload length (output)
 * - payload_capacity: buffer capacity
 * - timeout_ms: receive timeout
 * - error_code: if not NULL and DSP returns RESPONSE, stores the error code (output)
 *
 * Returns 0 on success, -1 on error.
 * If DSP returns RESPONSE instead of OUTPUT_DATA, returns -1 and sets error_code.
 */
int c2837x_protocol_wait_output_data(c2837x_socket_t* s,
                                     uint8_t* payload,
                                     uint16_t* length,
                                     uint32_t payload_capacity,
                                     uint32_t timeout_ms,
                                     uint16_t* error_code);

#ifdef __cplusplus
}
#endif

#endif /* C2837X_BLOCK_PROTOCOL_H */
