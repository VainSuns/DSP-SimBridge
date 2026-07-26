#ifndef C2837X_BLOCK_INTERNAL_H
#define C2837X_BLOCK_INTERNAL_H

#include "c2837x_block.h"
#include "c2837x_block_config_internal.h"
#include "c2837x_block_protocol.h"

typedef enum
{
    C2837X_BLOCK_STATE_WAIT_CONNECTION = 0,
    C2837X_BLOCK_STATE_RECEIVING,
    C2837X_BLOCK_STATE_FRAME_READY,
    C2837X_BLOCK_STATE_SENDING
} C2837xBlock_State;

typedef enum
{
    C2837X_BLOCK_PROTOCOL_WAIT_SIM_START = 0,
    C2837X_BLOCK_PROTOCOL_SIM_RUNNING
} C2837xBlock_ProtocolPhase;

typedef enum
{
    C2837X_BLOCK_RX_HEADER = 0,
    C2837X_BLOCK_RX_PAYLOAD
} C2837xBlock_RxPhase;

typedef enum
{
    C2837X_BLOCK_TX_DONE_CLOSE = 0,
    C2837X_BLOCK_TX_DONE_ENTER_SIM_RUNNING,
    C2837X_BLOCK_TX_DONE_RECEIVE_NEXT,
    C2837X_BLOCK_TX_DONE_ADVANCE_STEP
} C2837xBlock_TxDoneAction;

#define C2837X_BLOCK_SIM_START_PAYLOAD_SIZE_BYTES  6u
#define C2837X_BLOCK_RESPONSE_PAYLOAD_SIZE_BYTES   2u

typedef struct
{
    C2837xBlock_State state;
    C2837xBlock_ProtocolPhase protocol_phase;
    C2837xBlock_RxPhase rx_phase;
    Uint32 rx_header_received_octets;
    Uint16 rx_msg_type;
    Uint16 rx_payload_length_octets;
    Uint32 rx_payload_received_octets;
    Uint32 tx_total_octets;
    Uint32 tx_sent_octets;
    Uint32 expected_step_index;
    Uint16 algorithm_started;
    Uint16 close_pending;
    C2837xBlock_TxDoneAction tx_done_action;
    Uint16 response_error;
    C2837xBlock_Error last_error;
} C2837xBlock_Runtime;

struct C2837xBlock
{
    const C2837xBlock_Config *config;
    C2837xBlock_Runtime runtime;
};

#define C2837X_BLOCK_INSTANCE_INITIALIZER(config_ptr) \
    { (config_ptr), { 0 } }

#endif /* C2837X_BLOCK_INTERNAL_H */
