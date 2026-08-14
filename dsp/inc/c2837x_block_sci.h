#ifndef C2837X_BLOCK_SCI_H
#define C2837X_BLOCK_SCI_H

#include "F28x_Project.h"

/*
 * SCI-S2-03 descriptor contract.
 *
 * The descriptor contains only immutable hardware facts.  It deliberately
 * does not contain a generated instance name, a baud-rate request, or any
 * mutable transport state.  RX and TX are independent endpoints.
 */
typedef enum
{
    C2837X_BLOCK_SCI_MODULE_A = 0,
    C2837X_BLOCK_SCI_MODULE_B,
    C2837X_BLOCK_SCI_MODULE_C,
    C2837X_BLOCK_SCI_MODULE_D
} C2837xBlock_SciModule;

typedef enum
{
    C2837X_BLOCK_SCI_PIN_STANDARD = 0,
    C2837X_BLOCK_SCI_PIN_PULLUP
} C2837xBlock_SciPinType;

typedef enum
{
    C2837X_BLOCK_SCI_QUALIFICATION_SYNC = 0,
    C2837X_BLOCK_SCI_QUALIFICATION_ASYNC
} C2837xBlock_SciQualification;

typedef enum
{
    C2837X_BLOCK_SCI_CTRL_TX_ACTIVE_LOW = 0,
    C2837X_BLOCK_SCI_CTRL_TX_ACTIVE_HIGH
} C2837xBlock_SciCtrlTxActiveLevel;

typedef struct
{
    Uint16 gpio;
    Uint16 mux;
} C2837xBlock_SciPinMuxDescriptor;

typedef struct
{
    C2837xBlock_SciPinMuxDescriptor pin;
    C2837xBlock_SciPinType pin_type;
    C2837xBlock_SciQualification qualification;
} C2837xBlock_SciRxEndpoint;

typedef struct
{
    C2837xBlock_SciPinMuxDescriptor pin;
    C2837xBlock_SciPinType pin_type;
} C2837xBlock_SciTxEndpoint;

/* C2837X_BLOCK_SCI_NO_CTRL_GPIO means that no CTRL GPIO is touched. */
#define C2837X_BLOCK_SCI_NO_CTRL_GPIO  0xFFFFu
#define C2837X_BLOCK_SCI_BRR_MIN       1u
#define C2837X_BLOCK_SCI_BRR_MAX       0xFFFFu

typedef struct
{
    Uint16 gpio;
    C2837xBlock_SciPinType pin_type;
    C2837xBlock_SciCtrlTxActiveLevel tx_active_level;
} C2837xBlock_SciCtrlEndpoint;

typedef struct C2837xBlock_SciDescriptor
{
    C2837xBlock_SciModule module;
    Uint16 brr;
    C2837xBlock_SciRxEndpoint rx;
    C2837xBlock_SciTxEndpoint tx;
    C2837xBlock_SciCtrlEndpoint ctrl;
} C2837xBlock_SciDescriptor;

typedef struct
{
    const C2837xBlock_SciDescriptor *items;
    Uint16 count;
} C2837xBlock_SciDescriptorCollection;

/* F2837xD GPIO numbering is GPIO0 through GPIO168. */
#define C2837X_BLOCK_SCI_MAX_GPIO  168u

/*
 * S2-03 runtime foundation only.  These fields are software bookkeeping;
 * no SCI peripheral state is cached here and no later-stage state machine is
 * implied by their presence.
 */
typedef struct
{
    Uint16 rx_staging_octet;
    Uint16 rx_staging_valid;
    Uint16 software_pending;
    Uint16 ctrl_tx_active;
} C2837xBlock_SciChannelRuntime;

typedef struct
{
    const C2837xBlock_SciDescriptor *hardware_config;
    C2837xBlock_SciChannelRuntime runtime;
} C2837xBlock_SciChannel;

#define C2837X_BLOCK_SCI_CHANNEL_INITIALIZER(config_ptr_) \
    { (config_ptr_), { 0u, 0u, 0u, 0u } }

/* Resets only this channel's software runtime and CTRL direction latch. */
void c2837x_block_sci_channel_init(C2837xBlock_SciChannel *channel);

#endif /* C2837X_BLOCK_SCI_H */
