#ifndef C2837X_W5300_CHANNEL_H
#define C2837X_W5300_CHANNEL_H

#include "c2837x_block_iodevice.h"
#include "c2837x_w5300_socket.h"

typedef enum
{
    C2837X_W5300_SEND_IDLE = 0,
    C2837X_W5300_SEND_PENDING
} C2837xW5300SendState;

typedef struct
{
    C2837xW5300Socket socket;
    Uint16 tcp_port;
    Uint16 connected;
    C2837xW5300SendState send_state; /* one segment awaiting SEND_OK */
    Uint32 pending_octets;           /* submitted, not Core-committed */
    Uint16 closing;
    Uint16 faulted;
} C2837xW5300Channel;

extern const C2837xBlock_IoDeviceOps c2837x_w5300_iodevice_ops;

#endif /* C2837X_W5300_CHANNEL_H */
