#ifndef C2837X_BLOCK_CONFIG_H
#define C2837X_BLOCK_CONFIG_H

/*
 * DSP-side configuration for C2837xBlock.
 * Phase 1: 3x int16 input, 1x int16 output.
 *
 * config_hash = 0x12345678 (placeholder for manual testing)
 */

#include <stdint.h>
#include "F28x_Project.h"

/* ---- Static assert compatibility macro ---- */
#if defined(__STDC_VERSION__) && (__STDC_VERSION__ >= 201112L)
#define C2837X_STATIC_ASSERT(cond, name) _Static_assert((cond), #name)
#else
#define C2837X_STATIC_ASSERT_JOIN_(a, b) a##b
#define C2837X_STATIC_ASSERT_JOIN(a, b)  C2837X_STATIC_ASSERT_JOIN_(a, b)
#define C2837X_STATIC_ASSERT(cond, name) \
    typedef char C2837X_STATIC_ASSERT_JOIN(static_assertion_, __LINE__)[(cond) ? 1 : -1]
#endif

/* ---- Protocol configuration ---- */
#define C2837X_BLOCK_PROTOCOL_VERSION  0x0001u
#define C2837X_BLOCK_CONFIG_HASH       0x12345678u  /* placeholder */
#define C2837X_BLOCK_SAMPLE_TIME_SEC   1.0e-4

/* ---- Network configuration ---- */
#define C2837X_BLOCK_IP_ADDR           0xC0A80164u   /* 192.168.1.100 */
#define C2837X_BLOCK_GATEWAY           0xC0A80101u   /* 192.168.1.1   */
#define C2837X_BLOCK_SUBNET            0xFFFFFF00u   /* 255.255.255.0 */
#define C2837X_BLOCK_TCP_PORT          5000u
#define C2837X_BLOCK_SOCKET_NUM        0u
#define C2837X_BLOCK_ENABLE_DOUBLE     0u

/* ---- MAC address (6 bytes) ---- */
#define C2837X_BLOCK_MAC0   0x00u
#define C2837X_BLOCK_MAC1   0x08u
#define C2837X_BLOCK_MAC2   0xDCu
#define C2837X_BLOCK_MAC3   0x01u
#define C2837X_BLOCK_MAC4   0x02u
#define C2837X_BLOCK_MAC5   0x03u

#define C2837X_BLOCK_MAX_PAYLOAD_SIZE_BYTES       1024u
#define C2837X_BLOCK_MAX_FRAME_SIZE_BYTES         (4u + C2837X_BLOCK_MAX_PAYLOAD_SIZE_BYTES)

/* ---- W5300 socket memory allocation (in KB) ----
 * Total W5300 buffer: 128 KB.
 * Socket 0: 64 KB TX + 64 KB RX.
 * Other sockets: 0 KB (unused).
 * TX sum must be multiple of 8. TX + RX <= 128.
 */
#define C2837X_BLOCK_SOCKET0_TX_KB   64u
#define C2837X_BLOCK_SOCKET0_RX_KB   64u

/* ---- Data counts ---- */
#define C2837X_BLOCK_INPUT_COUNT       3u
#define C2837X_BLOCK_OUTPUT_COUNT      1u

/* ---- Wire byte sizes ---- */
#define C2837X_BLOCK_INPUT_DATA_SIZE_BYTES      6u   /* 3 x int16 */
#define C2837X_BLOCK_OUTPUT_DATA_SIZE_BYTES     2u   /* 1 x int16 */
#define C2837X_BLOCK_INPUT_PAYLOAD_SIZE_BYTES   (4u + C2837X_BLOCK_INPUT_DATA_SIZE_BYTES)
#define C2837X_BLOCK_OUTPUT_PAYLOAD_SIZE_BYTES  (4u + C2837X_BLOCK_OUTPUT_DATA_SIZE_BYTES)

/* ---- DSP word sizes ---- */
#define C2837X_BLOCK_INPUT_DATA_SIZE_WORDS      (C2837X_BLOCK_INPUT_DATA_SIZE_BYTES / 2u)
#define C2837X_BLOCK_OUTPUT_DATA_SIZE_WORDS     (C2837X_BLOCK_OUTPUT_DATA_SIZE_BYTES / 2u)
#define C2837X_BLOCK_INPUT_PAYLOAD_SIZE_WORDS   (C2837X_BLOCK_INPUT_PAYLOAD_SIZE_BYTES / 2u)
#define C2837X_BLOCK_OUTPUT_PAYLOAD_SIZE_WORDS  (C2837X_BLOCK_OUTPUT_PAYLOAD_SIZE_BYTES / 2u)
#define C2837X_BLOCK_MAX_PAYLOAD_SIZE_WORDS     (C2837X_BLOCK_MAX_PAYLOAD_SIZE_BYTES / 2u)

/* ---- Payload pack/unpack functions ---- */
void c2837x_block_unpack_input_payload(const uint16_t* payload_words,
                                       uint32_t* step_index);
void c2837x_block_pack_output_payload(uint16_t* payload_words,
                                      uint32_t step_index);

#endif /* C2837X_BLOCK_CONFIG_H */
