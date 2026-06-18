#ifndef W5300_SOCKET_H_
#define W5300_SOCKET_H_

#include "F28x_Project.h"


typedef struct {
    Uint16 sn;                    /* socket number (0-7) */
    Uint16 recv_pending_valid;
    Uint32 recv_pending_remain;
    Uint16 send_connected;
    Uint32 tx_mem_size;           /* TX buffer size in bytes */
    Uint32 rx_mem_size;           /* RX buffer size in bytes */
} W5300_Socket;


/**********************************
* define function of SOCKET APIs *
**********************************/

/**
* Open a SOCKET.
*/
int16 OpenSocket(W5300_Socket* sk, Uint16 protocol, Uint16 port, Uint16 flag);

/**
* Close a SOCKET.
*/
int16 CloseSocket(W5300_Socket* sk);

/**
* It is listening to a connect-request from a client.
*/
int16 ListenSocket(W5300_Socket* sk);

/**
* Send TCP data from DSP-native char array directly to W5300 TX FIFO.
* Each DSP char packs to one FIFO word (2 wire bytes). No intermediate buffer.
* @param wireByteCount Number of wire bytes to send (= 2 * DSP chars in dspData).
* @return Wire bytes sent, 0 if blocked, -1 on error.
*/
int32 SendStream(W5300_Socket* sk, const Uint16* dspData, Uint32 wireByteCount);

/**
* Receive TCP data into DSP-native char array directly from W5300 RX FIFO.
* Each FIFO word unpacks to one DSP char. No intermediate buffer.
* @param wireCapacity Max wire bytes to receive (= 2 * DSP char buffer capacity).
* @return Wire bytes received, 0 if none, -1 on error.
*/
int32 RecvStream(W5300_Socket* sk, Uint16* dspData, Uint32 wireCapacity);

/**
* It sends UDP, IPRAW, or MACRAW data
*/
int32 SendToSocket(W5300_Socket* sk, Uint16* buf, Uint32 len, Uint32 addr, Uint16 port, Uint32 subnet_mask);

#endif /* W5300_SOCKET_H_ */

//
// End of file
//
