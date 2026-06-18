/*
 * Protocol frame building and parsing for C2837xBlock.
 * Wire format: little-endian uint16 type, uint16 length, then payload.
 */

#include "c2837x_block_protocol.h"

Uint32 c2837x_block_build_frame(Uint16* tx_frame_words,
                                 Uint16 msg_type,
                                 Uint16 payload_wire_bytes,
                                 const Uint16* payload_words)
{
    Uint32 offset = 0;
    Uint32 payload_word_count;
    Uint32 i;

    /* Header: type (uint16 LE) + length (uint16 LE) */
    tx_frame_words[offset++] = msg_type;
    tx_frame_words[offset++] = payload_wire_bytes;

    /* Payload: copy as word buffer */
    payload_word_count = ((Uint32)payload_wire_bytes + 1U) >> 1;
    for (i = 0; i < payload_word_count; i++)
    {
        tx_frame_words[offset++] = payload_words[i];
    }

    return (Uint32)C2837X_BLOCK_HEADER_SIZE_BYTES + (Uint32)payload_wire_bytes;
}

int16 c2837x_block_parse_header(const Uint16* header_words,
                                 Uint16* msg_type,
                                 Uint16* payload_length)
{
    Uint16 type = header_words[0];
    Uint16 length = header_words[1];

    /* Check for odd length */
    if (length & 0x0001u)
    {
        return -1;
    }

    *msg_type = type;
    *payload_length = length;
    return 0;
}

Uint32 c2837x_block_build_response(Uint16* tx_frame_words,
                                    Uint16 error_code)
{
    Uint32 offset = 0;

    /* Header */
    tx_frame_words[offset++] = C2837X_MSG_RESPONSE;
    tx_frame_words[offset++] = 2u;  /* payload: 2 wire bytes */

    /* Payload: error_code */
    tx_frame_words[offset++] = error_code;

    return (Uint32)C2837X_BLOCK_HEADER_SIZE_BYTES + 2u;
}
