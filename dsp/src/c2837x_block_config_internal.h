#ifndef C2837X_BLOCK_CONFIG_INTERNAL_H
#define C2837X_BLOCK_CONFIG_INTERNAL_H

#include "c2837x_block_iodevice.h"

typedef struct
{
    /* reset_io clears only this instance's final input/output objects. */
    void (*reset_io)(void *context, void *input_object,
                     void *output_object);
    int16 (*on_start)(void *context);
    /* user_data_words starts after step_index; failure must not commit input. */
    int16 (*decode_input)(void *context, void *input_object,
                          const Uint16 *user_data_words,
                          Uint16 user_data_octets);
    int16 (*on_step)(void *context, const void *input_object,
                     void *output_object);
    /* Writes only user output data, never Header or step_index. */
    int16 (*encode_output)(void *context, const void *output_object,
                           Uint16 *user_data_words,
                           Uint16 user_data_capacity_octets);
    void (*on_stop)(void *context);
} C2837xBlock_AlgorithmAdapter;

typedef struct
{
    const C2837xBlock_IoDeviceOps *iodevice_ops;
    void *iodevice_channel;

    /* Frame capacities and payload lengths are wire octets. */
    Uint16 *rx_frame_words;
    Uint32 rx_frame_capacity_octets;
    Uint16 *tx_frame_words;
    Uint32 tx_frame_capacity_octets;

    void *input_object;
    void *output_object;
    const C2837xBlock_AlgorithmAdapter *algorithm;
    void *algorithm_context;

    Uint16 protocol_version;
    Uint32 interface_hash;
    Uint16 input_payload_octets;
    Uint16 output_payload_octets;
    Uint16 max_payload_octets;

    /* User communication timeouts, converted to microseconds. */
    Uint32 interaction_timeout_us;
    Uint32 transfer_timeout_us;
} C2837xBlock_Config;

#endif /* C2837X_BLOCK_CONFIG_INTERNAL_H */
