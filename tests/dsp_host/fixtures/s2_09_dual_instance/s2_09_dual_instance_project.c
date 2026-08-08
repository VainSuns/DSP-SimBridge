/* Hand-written S2-09 fixture; this is not generated project output. */

#define C2837X_BLOCK_EXPECTED_CORE_API_VERSION 1u
#include "c2837x_block_internal.h"
#include "c2837x_block_platform.h"
#include "c2837x_w5300_channel.h"
#include "s2_09_dual_instance_project.h"
#include <string.h>

const C2837xW5300ProjectConfig c2837x_w5300_project_config =
{
    {0x00u, 0x08u, 0xDCu, 0x01u, 0x02u, 0x03u},
    (Uint32)0xC0A80164UL,
    (Uint32)0xC0A80101UL,
    (Uint32)0xFFFFFF00UL
};

typedef struct
{
    Uint16 values[2];
} S2_09_Data;

typedef struct
{
    Uint16 data_octets;
    Uint16 bias;
} S2_09_AlgorithmContext;

static S2_09_Data current_loop_input;
static S2_09_Data current_loop_output;
static Uint16 current_loop_rx_words[5];
static Uint16 current_loop_tx_words[5];
static S2_09_AlgorithmContext current_loop_algorithm_context = { 2u, 10u };

static S2_09_Data voltage_loop_input;
static S2_09_Data voltage_loop_output;
static Uint16 voltage_loop_rx_words[6];
static Uint16 voltage_loop_tx_words[6];
static S2_09_AlgorithmContext voltage_loop_algorithm_context = { 4u, 20u };

static C2837xW5300Channel current_loop_channel =
    C2837X_W5300_CHANNEL_INITIALIZER(
        1u, 8192u, 8192u, 5101u, c2837x_block_time_us, 1000000u);
static C2837xW5300Channel voltage_loop_channel =
    C2837X_W5300_CHANNEL_INITIALIZER(
        6u, 8192u, 8192u, 5102u, c2837x_block_time_us, 2000000u);

static void s2_09_reset_io(void *context, void *input, void *output)
{
    (void)context;
    memset(input, 0, sizeof(S2_09_Data));
    memset(output, 0, sizeof(S2_09_Data));
}

static int16 s2_09_on_start(void *context)
{
    (void)context;
    return 0;
}

static void s2_09_decode_current(void *input, const Uint16 *words)
{
    ((S2_09_Data *)input)->values[0] = words[0];
}

static void s2_09_decode_voltage(void *input, const Uint16 *words)
{
    S2_09_Data *typed_input = (S2_09_Data *)input;
    typed_input->values[0] = words[0];
    typed_input->values[1] = words[1];
}

static int16 s2_09_on_step(void *context, const void *input, void *output)
{
    const S2_09_AlgorithmContext *algorithm =
        (const S2_09_AlgorithmContext *)context;
    const S2_09_Data *source = (const S2_09_Data *)input;
    S2_09_Data *destination = (S2_09_Data *)output;

    destination->values[0] = source->values[0] + algorithm->bias;
    destination->values[1] = source->values[1] + algorithm->bias;
    return 0;
}

static void s2_09_encode_current(const void *output, Uint16 *words)
{
    const S2_09_Data *data = (const S2_09_Data *)output;

    words[0] = data->values[0];
}

static void s2_09_encode_voltage(const void *output, Uint16 *words)
{
    const S2_09_Data *data = (const S2_09_Data *)output;

    words[0] = data->values[0];
    words[1] = data->values[1];
}

static void s2_09_on_stop(void *context)
{
    (void)context;
}

static const C2837xBlock_AlgorithmAdapter current_loop_algorithm_adapter = {
    s2_09_reset_io, s2_09_on_start, s2_09_decode_current,
    s2_09_on_step, s2_09_encode_current, s2_09_on_stop
};
static const C2837xBlock_AlgorithmAdapter voltage_loop_algorithm_adapter = {
    s2_09_reset_io, s2_09_on_start, s2_09_decode_voltage,
    s2_09_on_step, s2_09_encode_voltage, s2_09_on_stop
};

static const C2837xBlock_Config current_loop_config = {
    &c2837x_w5300_iodevice_ops, &current_loop_channel,
    current_loop_rx_words, 10u,
    current_loop_tx_words, 10u,
    &current_loop_input, &current_loop_output,
    &current_loop_algorithm_adapter, &current_loop_algorithm_context,
    0x0001u, 0x11112222u, 6u, 6u, 6u,
    c2837x_block_time_us, 5000000u, 1000000u
};
static const C2837xBlock_Config voltage_loop_config = {
    &c2837x_w5300_iodevice_ops, &voltage_loop_channel,
    voltage_loop_rx_words, 12u,
    voltage_loop_tx_words, 12u,
    &voltage_loop_input, &voltage_loop_output,
    &voltage_loop_algorithm_adapter, &voltage_loop_algorithm_context,
    0x0001u, 0x33334444u, 8u, 8u, 8u,
    c2837x_block_time_us, 7000000u, 2000000u
};

C2837xBlock g_s2_09_current_loop =
    C2837X_BLOCK_INSTANCE_INITIALIZER(&current_loop_config);
C2837xBlock g_s2_09_voltage_loop =
    C2837X_BLOCK_INSTANCE_INITIALIZER(&voltage_loop_config);
