/* Hand-written phase-1 sample adapter and static instance binding. */

#define C2837X_BLOCK_EXPECTED_CORE_API_VERSION 1u
#include "c2837x_block_internal.h"
#include "c2837x_block_algorithm.h"
#include "c2837x_block_config.h"
#include "c2837x_block_platform.h"
#include "c2837x_w5300_channel.h"
#include <limits.h>
#include <string.h>

#define SAMPLE_MAX_INBOUND_PAYLOAD_OCTETS \
    ((C2837X_BLOCK_INPUT_PAYLOAD_SIZE_BYTES > \
      C2837X_BLOCK_SIM_START_PAYLOAD_SIZE_BYTES) ? \
      C2837X_BLOCK_INPUT_PAYLOAD_SIZE_BYTES : \
      C2837X_BLOCK_SIM_START_PAYLOAD_SIZE_BYTES)
#define SAMPLE_RX_FRAME_WORDS \
    ((C2837X_BLOCK_HEADER_SIZE_BYTES + \
      SAMPLE_MAX_INBOUND_PAYLOAD_OCTETS) / 2u)
#define SAMPLE_TX_FRAME_WORDS \
    ((C2837X_BLOCK_HEADER_SIZE_BYTES + \
      C2837X_BLOCK_OUTPUT_PAYLOAD_SIZE_BYTES) / 2u)
#define C2837X_BLOCK_TIMEOUT_MS_TO_US(value_) ((Uint32)(value_) * 1000u)

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
C2837X_STATIC_ASSERT(
    SAMPLE_RX_FRAME_WORDS ==
        ((C2837X_BLOCK_HEADER_SIZE_BYTES +
          SAMPLE_MAX_INBOUND_PAYLOAD_OCTETS) / 2u),
    sample_rx_frame_size_mismatch);
C2837X_STATIC_ASSERT(SAMPLE_RX_FRAME_WORDS == 7u,
                     sample_rx_frame_must_be_seven_words);
C2837X_STATIC_ASSERT(INTERACTION_TIMEOUT > 0u,
                     interaction_timeout_must_be_positive);
C2837X_STATIC_ASSERT(TRANSFER_TIMEOUT > 0u,
                     transfer_timeout_must_be_positive);
C2837X_STATIC_ASSERT(INTERACTION_TIMEOUT <= 2147483u,
                     interaction_timeout_must_fit_unsigned_delta);
C2837X_STATIC_ASSERT(TRANSFER_TIMEOUT <= 2147483u,
                     transfer_timeout_must_fit_unsigned_delta);

static C2837xBlock_InputData sample_input;
static C2837xBlock_OutputData sample_output;
static Uint16 sample_rx_frame[SAMPLE_RX_FRAME_WORDS];
static Uint16 sample_tx_frame[SAMPLE_TX_FRAME_WORDS];
static C2837xW5300Channel sample_channel =
    C2837X_W5300_CHANNEL_INITIALIZER(
        C2837X_BLOCK_SOCKET_NUM, 8192u, 8192u, C2837X_BLOCK_TCP_PORT,
        c2837x_block_time_us,
        C2837X_BLOCK_TIMEOUT_MS_TO_US(TRANSFER_TIMEOUT));

static void sample_reset_io(void *context, void *input, void *output)
{
    (void)context;
    memset(input, 0, sizeof(C2837xBlock_InputData));
    memset(output, 0, sizeof(C2837xBlock_OutputData));
}

static int16 sample_on_start(void *context)
{
    (void)context;
    return C2837xBlock_OnSimStart();
}

static void sample_decode_input(void *input, const Uint16 *words)
{
    C2837xBlock_InputData *typed_input = (C2837xBlock_InputData *)input;
    typed_input->a = (int16_t)words[0];
    typed_input->b = (int16_t)words[1];
    typed_input->c = (int16_t)words[2];
}

static int16 sample_on_step(void *context, const void *input, void *output)
{
    (void)context;
    return C2837xBlock_OnStep((const C2837xBlock_InputData *)input,
                              (C2837xBlock_OutputData *)output);
}

static void sample_encode_output(const void *output, Uint16 *words)
{
    const C2837xBlock_OutputData *typed_output =
        (const C2837xBlock_OutputData *)output;
    words[0] = (Uint16)typed_output->sum;
}

static void sample_on_stop(void *context)
{
    (void)context;
    C2837xBlock_OnSimStop();
}

static const C2837xBlock_AlgorithmAdapter sample_algorithm = {
    sample_reset_io,
    sample_on_start,
    sample_decode_input,
    sample_on_step,
    sample_encode_output,
    sample_on_stop
};

static const C2837xBlock_Config sample_config = {
    &c2837x_w5300_iodevice_ops,
    &sample_channel,
    sample_rx_frame,
    SAMPLE_RX_FRAME_WORDS * 2u,
    sample_tx_frame,
    SAMPLE_TX_FRAME_WORDS * 2u,
    &sample_input,
    &sample_output,
    &sample_algorithm,
    NULL,
    C2837X_BLOCK_PROTOCOL_VERSION,
    C2837X_BLOCK_CONFIG_HASH,
    C2837X_BLOCK_INPUT_PAYLOAD_SIZE_BYTES,
    C2837X_BLOCK_OUTPUT_PAYLOAD_SIZE_BYTES,
    C2837X_BLOCK_MAX_PAYLOAD_SIZE_BYTES,
    c2837x_block_time_us,
    C2837X_BLOCK_TIMEOUT_MS_TO_US(INTERACTION_TIMEOUT),
    C2837X_BLOCK_TIMEOUT_MS_TO_US(TRANSFER_TIMEOUT)
};

C2837xBlock c2837x_block_instance =
    C2837X_BLOCK_INSTANCE_INITIALIZER(&sample_config);
