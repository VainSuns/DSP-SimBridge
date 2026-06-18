/*
 * DSP-side payload serialization for C2837xBlock.
 * Phase 1: 3x int16 input, 1x int16 output.
 *
 * All serialization uses uint16_t word buffer.
 * Wire format: little-endian, low word first.
 */

#include "c2837x_block_config.h"
#include "c2837x_block_algorithm.h"
#include <limits.h>
#include <string.h>

/* ---- Static asserts ---- */
C2837X_STATIC_ASSERT((sizeof(uint16_t) * CHAR_BIT) == 16u,
                     uint16_bit_size_mismatch);
C2837X_STATIC_ASSERT((sizeof(uint32_t) * CHAR_BIT) == 32u,
                     uint32_bit_size_mismatch);
C2837X_STATIC_ASSERT((sizeof(float) * CHAR_BIT) == 32u,
                     single_bit_size_mismatch);
C2837X_STATIC_ASSERT((C2837X_BLOCK_INPUT_DATA_SIZE_BYTES % 2u) == 0u,
                     input_data_size_must_be_even);
C2837X_STATIC_ASSERT((C2837X_BLOCK_OUTPUT_DATA_SIZE_BYTES % 2u) == 0u,
                     output_data_size_must_be_even);

/* ---- Serialization helpers ---- */

static inline uint16_t read_uint16(const uint16_t* buf, uint32_t* offset)
{
    return buf[(*offset)++];
}

static inline void write_uint16(uint16_t* buf, uint32_t* offset, uint16_t val)
{
    buf[(*offset)++] = val;
}

static inline int16_t read_int16(const uint16_t* buf, uint32_t* offset)
{
    return (int16_t)buf[(*offset)++];
}

static inline void write_int16(uint16_t* buf, uint32_t* offset, int16_t val)
{
    buf[(*offset)++] = (uint16_t)val;
}

static inline uint32_t read_uint32(const uint16_t* buf, uint32_t* offset)
{
    uint32_t lo = (uint32_t)buf[(*offset)++];
    uint32_t hi = (uint32_t)buf[(*offset)++];
    return lo | (hi << 16);
}

static inline void write_uint32(uint16_t* buf, uint32_t* offset, uint32_t val)
{
    buf[(*offset)++] = (uint16_t)(val & 0xFFFFu);
    buf[(*offset)++] = (uint16_t)((val >> 16) & 0xFFFFu);
}

/* ---- Unpack INPUT_DATA payload ----
 * Payload layout (words):
 *   [0..1] step_index (uint32)
 *   [2]    a (int16)
 *   [3]    b (int16)
 *   [4]    c (int16)
 */
void c2837x_block_unpack_input_payload(const uint16_t* payload_words,
                                       uint32_t* step_index)
{
    uint32_t offset = 0;

    *step_index = read_uint32(payload_words, &offset);

    c2837x_block_input.a = read_int16(payload_words, &offset);
    c2837x_block_input.b = read_int16(payload_words, &offset);
    c2837x_block_input.c = read_int16(payload_words, &offset);
}

/* ---- Pack OUTPUT_DATA payload ----
 * Payload layout (words):
 *   [0..1] step_index (uint32)
 *   [2]    sum (int16)
 */
void c2837x_block_pack_output_payload(uint16_t* payload_words,
                                      uint32_t step_index)
{
    uint32_t offset = 0;

    write_uint32(payload_words, &offset, step_index);

    write_int16(payload_words, &offset, c2837x_block_output.sum);
}
