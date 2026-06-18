#ifndef C2837X_BLOCK_PROTOCOL_H
#define C2837X_BLOCK_PROTOCOL_H

/*
 * Protocol types, error codes, and frame helper declarations
 * for the C2837xBlock communication module.
 */

#include "F28x_Project.h"

/* ---- Message types ---- */
#define C2837X_MSG_SIM_START    0x0001u
#define C2837X_MSG_INPUT_DATA   0x0002u
#define C2837X_MSG_OUTPUT_DATA  0x0003u
#define C2837X_MSG_SIM_STOP     0x0004u
#define C2837X_MSG_RESPONSE     0x0005u

/* ---- Error codes ---- */
#define C2837X_ERR_OK                    0u
#define C2837X_ERR_UNKNOWN_TYPE          1u
#define C2837X_ERR_LENGTH                2u
#define C2837X_ERR_CONFIG_MISMATCH       3u
#define C2837X_ERR_STATE                 4u
#define C2837X_ERR_INTERNAL              5u
#define C2837X_ERR_PROTOCOL_VERSION      6u
#define C2837X_ERR_STEP_INDEX            7u
#define C2837X_ERR_UNSUPPORTED_TYPE      8u

/* ---- Frame size constants ---- */
#define C2837X_BLOCK_HEADER_SIZE_BYTES   4u

/* ---- Frame helper functions ---- */

/*
 * Build a frame into tx_frame_words[].
 * Returns total wire bytes (header + payload).
 * tx_frame_words must have enough capacity.
 * payload_words can be NULL if payload_wire_bytes == 0.
 */
Uint32 c2837x_block_build_frame(Uint16* tx_frame_words,
                                 Uint16 msg_type,
                                 Uint16 payload_wire_bytes,
                                 const Uint16* payload_words);

/*
 * Parse a 4-byte header (already received as 2 Uint16 words).
 * Extracts type and length in host byte order.
 * Returns 0 on success, -1 on error (e.g. odd length).
 */
int16 c2837x_block_parse_header(const Uint16* header_words,
                                 Uint16* msg_type,
                                 Uint16* payload_length);

/*
 * Build a RESPONSE frame with the given error code.
 * Returns total wire bytes.
 */
Uint32 c2837x_block_build_response(Uint16* tx_frame_words,
                                    Uint16 error_code);

#endif /* C2837X_BLOCK_PROTOCOL_H */
