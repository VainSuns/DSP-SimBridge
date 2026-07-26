#ifndef C2837X_BLOCK_IODEVICE_H
#define C2837X_BLOCK_IODEVICE_H

#include "F28x_Project.h"

typedef enum
{
    C2837X_IODEVICE_CONNECTION_CLOSED = 0,
    C2837X_IODEVICE_CONNECTION_OPEN,
    C2837X_IODEVICE_CONNECTION_LISTENING,
    C2837X_IODEVICE_CONNECTION_CONNECTED,
    C2837X_IODEVICE_CONNECTION_PEER_CLOSED,
    C2837X_IODEVICE_CONNECTION_ERROR
} C2837xBlock_IoConnectionState;

typedef struct
{
    void (*channel_init)(void *channel);
    int16 (*open)(void *channel);
    int16 (*listen)(void *channel);
    C2837xBlock_IoConnectionState (*get_connection_state)(void *channel);
    /* >0: submitted receive progress; 0: none; <0: failure. */
    int32 (*receive)(void *channel, Uint16 *data_words,
                     Uint32 capacity_octets);
    /* >0: confirmed send completion; 0: none; <0: failure. */
    int32 (*send)(void *channel, const Uint16 *data_words,
                  Uint32 count_octets);
    /* Every valid positive receive/send result is an even wire-octet count. */
    /* >0: DONE, 0: BUSY, <0: ERROR. */
    int16 (*close)(void *channel);
} C2837xBlock_IoDeviceOps;

#endif /* C2837X_BLOCK_IODEVICE_H */
