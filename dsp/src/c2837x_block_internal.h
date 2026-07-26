#ifndef C2837X_BLOCK_INTERNAL_H
#define C2837X_BLOCK_INTERNAL_H

#include "c2837x_block.h"
#include "c2837x_block_config.h"
#include "c2837x_block_protocol.h"
#include "c2837x_w5300_socket.h"

typedef enum {
    C2837X_STATE_RECV = 0,
    C2837X_STATE_SEND
} C2837xBlock_State;

typedef enum {
    C2837X_RX_WAIT_HEADER = 0,
    C2837X_RX_WAIT_PAYLOAD,
    C2837X_RX_PROCESSING
} C2837xBlock_RxState;

typedef enum {
    C2837X_TX_DONE_DISCONNECT = 0,
    C2837X_TX_DONE_START_RX,
    C2837X_TX_DONE_ADVANCE_STEP
} C2837xBlock_TxDoneAction;

#define C2837X_BLOCK_SIM_START_PAYLOAD_SIZE_BYTES  6u
#define C2837X_BLOCK_RESPONSE_PAYLOAD_SIZE_BYTES   2u
#define C2837X_BLOCK_RX_PAYLOAD_SIZE_BYTES         \
    ((C2837X_BLOCK_INPUT_PAYLOAD_SIZE_BYTES >      \
      C2837X_BLOCK_SIM_START_PAYLOAD_SIZE_BYTES) ? \
      C2837X_BLOCK_INPUT_PAYLOAD_SIZE_BYTES :      \
      C2837X_BLOCK_SIM_START_PAYLOAD_SIZE_BYTES)
#define C2837X_BLOCK_TX_PAYLOAD_SIZE_BYTES         \
    ((C2837X_BLOCK_OUTPUT_PAYLOAD_SIZE_BYTES >     \
      C2837X_BLOCK_RESPONSE_PAYLOAD_SIZE_BYTES) ?  \
      C2837X_BLOCK_OUTPUT_PAYLOAD_SIZE_BYTES :     \
      C2837X_BLOCK_RESPONSE_PAYLOAD_SIZE_BYTES)
#define C2837X_BLOCK_PAYLOAD_WORK_SIZE_BYTES       \
    ((C2837X_BLOCK_RX_PAYLOAD_SIZE_BYTES >         \
      C2837X_BLOCK_OUTPUT_PAYLOAD_SIZE_BYTES) ?    \
      C2837X_BLOCK_RX_PAYLOAD_SIZE_BYTES :         \
      C2837X_BLOCK_OUTPUT_PAYLOAD_SIZE_BYTES)
#define C2837X_BLOCK_PAYLOAD_WORK_SIZE_WORDS       \
    ((C2837X_BLOCK_PAYLOAD_WORK_SIZE_BYTES + 1u) / 2u)
#define C2837X_BLOCK_TX_FRAME_SIZE_BYTES           \
    (C2837X_BLOCK_HEADER_SIZE_BYTES + C2837X_BLOCK_TX_PAYLOAD_SIZE_BYTES)
#define C2837X_BLOCK_TX_FRAME_SIZE_WORDS           \
    ((C2837X_BLOCK_TX_FRAME_SIZE_BYTES + 1u) / 2u)

struct C2837xBlock {
    C2837xBlock_State state;
    C2837xBlock_RxState rx_state;
    C2837xW5300Socket socket;

    Uint16 rx_header_words[2];
    Uint32 rx_header_received_bytes;
    Uint16 rx_payload_words[C2837X_BLOCK_PAYLOAD_WORK_SIZE_WORDS];
    Uint16 rx_msg_type;
    Uint16 rx_payload_length_bytes;
    Uint32 rx_payload_received_bytes;

    Uint16 tx_frame_words[C2837X_BLOCK_TX_FRAME_SIZE_WORDS];
    Uint32 tx_total_bytes;
    Uint32 tx_sent_bytes;

    Uint32 expected_step_index;
    Uint16 sim_started;
    C2837xBlock_TxDoneAction tx_done_action;
    Uint32 frame_start_tick;
    Uint32 tick_counter;
    Uint16 first_connected;
    Uint16 response_error;
    C2837xBlock_Error last_error;
};

#endif /* C2837X_BLOCK_INTERNAL_H */
