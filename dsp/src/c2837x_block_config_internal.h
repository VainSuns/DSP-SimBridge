#ifndef C2837X_BLOCK_CONFIG_INTERNAL_H
#define C2837X_BLOCK_CONFIG_INTERNAL_H

#include "c2837x_block_iodevice.h"

typedef struct
{
    /* reset_io clears only this instance's final input/output objects. */
    void (*reset_io)(void *context, void *input_object,
                     void *output_object);
    int16 (*on_start)(void *context);
    /* Core validates the frame, fixed length, state, and step_index first.
     * The decoder fully covers the final input object and cannot fail. */
    void (*decode_input)(void *input_object,
                         const Uint16 *user_data_words);
    int16 (*on_step)(void *context, const void *input_object,
                     void *output_object);
    /* Encodes only user output data, never Header or step_index. OnStep has
     * already succeeded when this callback is called. */
    void (*encode_output)(const void *output_object,
                          Uint16 *user_data_words);
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

    /* Shared monotonic clock; timeout state remains per instance. */
    Uint32 (*time_us)(void);
    /* User communication timeouts, converted to microseconds. */
    Uint32 interaction_timeout_us;
    Uint32 transfer_timeout_us;
} C2837xBlock_Config;

#endif /* C2837X_BLOCK_CONFIG_INTERNAL_H */
