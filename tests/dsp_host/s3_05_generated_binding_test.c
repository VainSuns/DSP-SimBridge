#include "c2837x_block_internal.h"
#include "c2837x_block_protocol.h"
#include "c2837x_block_project.h"
#include "axis_a_config.h"
#include "axis_a_algorithm.h"
#include "axis_b_config.h"
#include "axis_b_algorithm.h"
#include "test_provider_channel.h"
#include <stdio.h>

extern TestProviderChannel c2837x_block_axis_a_iodevice_channel;
extern TestProviderChannel c2837x_block_axis_b_iodevice_channel;
extern AxisA_InputData c2837x_block_axis_a_input_object;
extern AxisB_InputData c2837x_block_axis_b_input_object;

static Uint32 now_us;
Uint32 c2837x_block_time_us(void) { return now_us++; }

static void channel_init(void *context)
{
    TestProviderChannel *channel = (TestProviderChannel *)context;
    channel->state = C2837X_IODEVICE_CONNECTION_CONNECTED;
}
static int16 progress(void *context) { (void)context; return 1; }
static C2837xBlock_IoConnectionState state(void *context)
{
    return ((TestProviderChannel *)context)->state;
}
static int32 receive_words(void *context, Uint16 *data, Uint32 capacity)
{
    TestProviderChannel *channel = (TestProviderChannel *)context;
    Uint32 remaining = channel->rx_octets - channel->rx_offset;
    Uint32 count = remaining < capacity ? remaining : capacity;
    Uint32 index;
    for (index = 0u; index < count / 2u; ++index)
        data[index] = channel->rx[channel->rx_offset / 2u + index];
    channel->rx_offset += count;
    return (int32)count;
}
static int32 send_words(void *context, const Uint16 *data, Uint32 count)
{
    TestProviderChannel *channel = (TestProviderChannel *)context;
    Uint32 index;
    for (index = 0u; index < count / 2u; ++index)
        channel->tx[channel->tx_octets / 2u + index] = data[index];
    channel->tx_octets += count;
    return (int32)count;
}
static int16 close_channel(void *context)
{
    ((TestProviderChannel *)context)->state =
        C2837X_IODEVICE_CONNECTION_CONNECTED;
    return 1;
}
const C2837xBlock_IoDeviceOps test_provider_iodevice_ops = {
    channel_init, progress, progress, state,
    receive_words, send_words, close_channel
};

static void load_start(TestProviderChannel *channel, Uint32 hash)
{
    channel->rx[0] = C2837X_MSG_SIM_START;
    channel->rx[1] = 6u;
    channel->rx[2] = 1u;
    channel->rx[3] = (Uint16)(hash & 0xffffu);
    channel->rx[4] = (Uint16)(hash >> 16);
    channel->rx_octets = 10u;
    channel->rx_offset = 0u;
    channel->tx_octets = 0u;
}

static void load_input(TestProviderChannel *channel, Uint32 step, Uint16 value)
{
    channel->rx[0] = C2837X_MSG_INPUT_DATA;
    channel->rx[1] = 6u;
    channel->rx[2] = (Uint16)(step & 0xffffu);
    channel->rx[3] = (Uint16)(step >> 16);
    channel->rx[4] = value;
    channel->rx_octets = 10u;
    channel->rx_offset = 0u;
    channel->tx_octets = 0u;
}

static void run(C2837xBlock *instance, unsigned count)
{
    unsigned index;
    for (index = 0u; index < count; ++index) C2837xBlock_Run(instance);
}

int main(void)
{
    C2837xBlock_Init(&g_axis_a);
    C2837xBlock_Init(&g_axis_b);
    if (C2837xBlock_GetLastError(&g_axis_a) != C2837X_BLOCK_ERROR_NONE ||
        C2837xBlock_GetLastError(&g_axis_b) != C2837X_BLOCK_ERROR_NONE)
        return 1;

    load_start(&c2837x_block_axis_a_iodevice_channel, AXIS_A_INTERFACE_HASH);
    load_start(&c2837x_block_axis_b_iodevice_channel, AXIS_B_INTERFACE_HASH);
    run(&g_axis_a, 5u);
    run(&g_axis_b, 5u);

    load_input(&c2837x_block_axis_a_iodevice_channel, 0u, 0x1111u);
    run(&g_axis_a, 4u);
    if (c2837x_block_axis_a_input_object.a_in != 0x1111u ||
        c2837x_block_axis_b_input_object.b_in != 0u ||
        g_axis_a.runtime.expected_step_index != 1u ||
        g_axis_b.runtime.expected_step_index != 0u ||
        c2837x_block_axis_a_iodevice_channel.tx[0] != C2837X_MSG_OUTPUT_DATA ||
        c2837x_block_axis_a_iodevice_channel.tx[2] != 0u)
        return 2;

    load_input(&c2837x_block_axis_b_iodevice_channel, 0u, 0x2222u);
    run(&g_axis_b, 4u);
    if (c2837x_block_axis_b_input_object.b_in != 0x2222u ||
        c2837x_block_axis_a_input_object.a_in != 0x1111u ||
        g_axis_b.runtime.expected_step_index != 1u)
        return 3;

    load_input(&c2837x_block_axis_a_iodevice_channel, 7u, 0x9999u);
    run(&g_axis_a, 3u);
    if (c2837x_block_axis_a_input_object.a_in != 0x1111u ||
        C2837xBlock_GetLastError(&g_axis_a) != C2837X_BLOCK_ERROR_PROTOCOL ||
        C2837xBlock_GetLastError(&g_axis_b) != C2837X_BLOCK_ERROR_NONE)
        return 4;

    puts("s3_05_generated_binding=ok");
    return 0;
}
