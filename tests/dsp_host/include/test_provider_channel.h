#ifndef TEST_PROVIDER_CHANNEL_H
#define TEST_PROVIDER_CHANNEL_H

#include "c2837x_block_iodevice.h"

typedef struct
{
    Uint16 instance_id;
    C2837xBlock_IoConnectionState state;
    Uint16 rx[128];
    Uint16 tx[128];
    Uint32 rx_octets;
    Uint32 rx_offset;
    Uint32 tx_octets;
} TestProviderChannel;

extern const C2837xBlock_IoDeviceOps test_provider_iodevice_ops;

#endif /* TEST_PROVIDER_CHANNEL_H */
