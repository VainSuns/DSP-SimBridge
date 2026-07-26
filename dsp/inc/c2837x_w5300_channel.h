#ifndef C2837X_W5300_CHANNEL_H
#define C2837X_W5300_CHANNEL_H

#include "c2837x_block_iodevice.h"
#include "c2837x_w5300_socket.h"

typedef enum
{
    C2837X_W5300_SEND_IDLE = 0,
    C2837X_W5300_SEND_PENDING
} C2837xW5300SendState;

typedef enum
{
    C2837X_W5300_CLOSE_IDLE = 0,
    C2837X_W5300_CLOSE_WAIT_EXISTING_CR,
    C2837X_W5300_CLOSE_CHECK_ERRATUM,
    C2837X_W5300_CLOSE_UDP_OPEN_ISSUE,
    C2837X_W5300_CLOSE_UDP_OPEN_WAIT_CR,
    C2837X_W5300_CLOSE_UDP_OPEN_WAIT_STATE,
    C2837X_W5300_CLOSE_DUMMY_WAIT_TX_SPACE,
    C2837X_W5300_CLOSE_DUMMY_SEND_ISSUE,
    C2837X_W5300_CLOSE_DUMMY_SEND_WAIT_CR,
    C2837X_W5300_CLOSE_DUMMY_SEND_WAIT_RESULT,
    C2837X_W5300_CLOSE_CLOSE_ISSUE,
    C2837X_W5300_CLOSE_CLOSE_WAIT_CR,
    C2837X_W5300_CLOSE_CLOSE_WAIT_STATE,
    C2837X_W5300_CLOSE_FAULTED
} C2837xW5300CloseState;

typedef Uint32 (*C2837xW5300TimeUs)(void);

typedef struct
{
    C2837xW5300Socket socket;
    Uint16 tcp_port;
    C2837xW5300TimeUs time_us;
    Uint32 close_timeout_us;
    Uint16 connected;
    C2837xW5300SendState send_state; /* one segment awaiting SEND_OK */
    Uint32 pending_octets;           /* submitted, not Core-committed */
    Uint16 faulted;
    C2837xW5300CloseState close_state;
    Uint32 close_start_us;
    Uint32 observed_platform_generation;
} C2837xW5300Channel;

#define C2837X_W5300_CHANNEL_INITIALIZER(sn_, tx_, rx_, port_, time_, timeout_) \
    { C2837X_W5300_SOCKET_INITIALIZER((sn_), (tx_), (rx_)), (port_), (time_), \
      (timeout_), 0u, C2837X_W5300_SEND_IDLE, 0u, 0u, \
      C2837X_W5300_CLOSE_IDLE, 0u, 0u }

extern const C2837xBlock_IoDeviceOps c2837x_w5300_iodevice_ops;

#endif /* C2837X_W5300_CHANNEL_H */
