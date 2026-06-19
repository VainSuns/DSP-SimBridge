#ifndef C2837X_BLOCK_SFUN_H
#define C2837X_BLOCK_SFUN_H

/*
 * C2837xBlock C MEX S-Function Internal Header
 * Context structure and helper declarations.
 *
 * This module uses direct port-to-payload conversion,
 * eliminating intermediate data structures.
 */

#include <stdint.h>
#include "c2837x_block_pc_socket.h"
#include "c2837x_block_pc_config.h"

#ifdef __cplusplus
extern "C" {
#endif

/* ---- S-Function context structure ---- */

typedef struct {
    /* Socket connection to DSP */
    c2837x_socket_t sock;

    /* TX/RX buffers for protocol frames */
    uint8_t tx_buf[C2837X_BLOCK_MAX_FRAME_SIZE_BYTES];
    uint8_t rx_buf[C2837X_BLOCK_MAX_FRAME_SIZE_BYTES];

    /* Step index counter */
    uint32_t step_index;

    /* Timeout configuration (milliseconds) */
    uint32_t connect_timeout_ms;
    uint32_t step_timeout_ms;
    uint32_t terminate_timeout_ms;

    /* Connection state flags */
    int connected;
    int sim_started;

    /* Socket library initialization flag */
    int socket_lib_initialized;

    /* Last DSP error code for reporting */
    uint16_t last_dsp_error;
} C2837xBlockSfunContext;

/* ---- Helper function declarations ---- */

/*
 * Create and initialize a new context.
 * Returns NULL on failure.
 */
C2837xBlockSfunContext* c2837x_block_sfun_create_context(void);

/*
 * Destroy context and release resources.
 * Closes socket if connected.
 */
void c2837x_block_sfun_destroy_context(C2837xBlockSfunContext* ctx);

/*
 * Connect to DSP and perform SIM_START handshake.
 * - ctx: context (must be initialized)
 * Returns 0 on success, -1 on failure.
 */
int c2837x_block_sfun_connect(C2837xBlockSfunContext* ctx);

/*
 * Perform one simulation step with direct port I/O.
 * - ctx: context (must be connected and sim_started)
 * - S: Simulink S-Function pointer for port access
 * Returns 0 on success, -1 on failure.
 */
int c2837x_block_sfun_step(C2837xBlockSfunContext* ctx, void *S);

/*
 * Disconnect from DSP: send SIM_STOP, close socket.
 * - ctx: context
 * - graceful: if 1, try to send SIM_STOP; if 0, just close
 */
void c2837x_block_sfun_disconnect(C2837xBlockSfunContext* ctx, int graceful);

#ifdef __cplusplus
}
#endif

#endif /* C2837X_BLOCK_SFUN_H */
