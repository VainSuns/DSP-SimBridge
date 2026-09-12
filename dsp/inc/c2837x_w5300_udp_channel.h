#ifndef C2837X_W5300_UDP_CHANNEL_H
#define C2837X_W5300_UDP_CHANNEL_H

#include "c2837x_block_iodevice.h"
#include "c2837x_w5300_socket.h"

typedef Uint32 (*C2837xW5300UdpTimeUs)(void);

typedef enum
{
    C2837X_W5300_UDP_SEND_IDLE = 0,
    C2837X_W5300_UDP_SEND_PENDING
} C2837xW5300UdpSendState;

/* Native UDP close is only the generic W5300 CLOSE progression. */
typedef enum
{
    C2837X_W5300_UDP_CLOSE_IDLE = 0,
    C2837X_W5300_UDP_CLOSE_WAIT_EXISTING_CR,
    C2837X_W5300_UDP_CLOSE_ISSUE,
    C2837X_W5300_UDP_CLOSE_WAIT_CR,
    C2837X_W5300_UDP_CLOSE_WAIT_STATE,
    C2837X_W5300_UDP_CLOSE_FAULTED
} C2837xW5300UdpCloseState;

typedef struct
{
    C2837xW5300Socket socket;
    Uint16 udp_port;
    C2837xW5300UdpTimeUs time_us;
    Uint32 close_timeout_us;

    /* One endpoint storage is provisional until a later Core promotion. */
    Uint32 candidate_ip;
    Uint16 candidate_port;
    Uint16 candidate_valid;

    /* Current W5300 UDP DATA remains owned/staged by the socket. */
    Uint16 datagram_active;
    Uint32 datagram_data_size;
    Uint32 datagram_consumed;

    /* Placeholder bookkeeping for the later Channel TX implementation. */
    C2837xW5300UdpSendState send_state;
    Uint32 pending_octets;

    C2837xW5300UdpCloseState close_state;
    Uint32 close_start_us;
    Uint16 faulted;
    Uint32 observed_platform_generation;
} C2837xW5300UdpChannel;

#define C2837X_W5300_UDP_CHANNEL_INITIALIZER( \
    sn_, tx_, rx_, port_, time_, timeout_) \
    { C2837X_W5300_SOCKET_INITIALIZER((sn_), (tx_), (rx_)), \
      (port_), (time_), (timeout_), \
      0u, 0u, 0u, 0u, 0u, 0u, \
      C2837X_W5300_UDP_SEND_IDLE, 0u, \
      C2837X_W5300_UDP_CLOSE_IDLE, 0u, 0u, 0u }

extern const C2837xBlock_IoDeviceOps c2837x_w5300_udp_iodevice_ops;

#endif /* C2837X_W5300_UDP_CHANNEL_H */
