#ifndef C2837X_W5300_HAL_H
#define C2837X_W5300_HAL_H

/*
 * W5300 hardware abstraction layer for C2837x.
 * Provides register read/write, FIFO stream I/O, and socket register helpers.
 */

#include "F28x_Project.h"
#include "c2837x_w5300_regs.h"

/* ---- Reset pin ---- */
#define C2837X_W5300_RESET_PIN 99
#define C2837X_W5300_RESET_ASSERT_US  2u
#define C2837X_W5300_RESET_SETTLE_US  10000u

/* Fixed first-version allocation for every W5300 socket. */
#define C2837X_W5300_SOCKET_MEMORY_KB     8u
#define C2837X_W5300_SOCKET_MEMORY_BYTES  \
    (C2837X_W5300_SOCKET_MEMORY_KB * 1024u)

/* Project bound for volatile 32-bit size-register snapshots. */
#define C2837X_W5300_STABLE_READ_ATTEMPTS 3u

typedef struct
{
    Uint16 mac[6];
    Uint32 ip_address;
    Uint32 gateway;
    Uint32 subnet;
} C2837xW5300ProjectConfig;

extern const C2837xW5300ProjectConfig
    c2837x_w5300_project_config;

/* ---- FIFO byte-swap flag ---- */
extern Uint16 c2837x_w5300_fifo_swap;

/* ---- Low-level init / reset ---- */
int16 c2837x_w5300_init(void);
void c2837x_w5300_reset(void);

/* ---- 16-bit register access ---- */
Uint16 c2837x_w5300_read16(Uint32 addr);
void   c2837x_w5300_write16(Uint32 addr, Uint16 data);

/* ---- 8-bit register access (inline) ---- */
static inline Uint16 c2837x_w5300_read8(Uint32 addr)
{
    return (Uint16)(c2837x_w5300_read16(addr) & 0x00FFu);
}

static inline void c2837x_w5300_write8(Uint32 addr, Uint16 data)
{
    c2837x_w5300_write16(addr, data & 0x00FFu);
}

/* ---- Bounded socket command helpers ----
 * issue: one Sn_CR write, 0 on success, negative on local error.
 * poll:  one Sn_CR read, >0 when clear, 0 while busy, negative on error.
 */
int16 c2837x_w5300_issue_sn_cr(Uint16 sn, Uint16 command);
int16 c2837x_w5300_poll_sn_cr(Uint16 sn);

/* ---- Socket register inline helpers ---- */
static inline Uint16 c2837x_w5300_is_socket_status(Uint16 status)
{
    return ((status == SOCK_CLOSED) ||
            (status == SOCK_ARP) ||
            (status == SOCK_INIT) ||
            (status == SOCK_LISTEN) ||
            (status == SOCK_SYNSENT) ||
            (status == SOCK_SYNRECV) ||
            (status == SOCK_ESTABLISHED) ||
            (status == SOCK_FIN_WAIT) ||
            (status == SOCK_CLOSING) ||
            (status == SOCK_TIME_WAIT) ||
            (status == SOCK_CLOSE_WAIT) ||
            (status == SOCK_LAST_ACK) ||
            (status == SOCK_UDP) ||
            (status == SOCK_IPRAW) ||
            (status == SOCK_MACRAW) ||
            (status == SOCK_PPPoE)) ? 1u : 0u;
}

static inline Uint16 c2837x_w5300_get_sn_ssr(Uint16 sn)
{
    return c2837x_w5300_read8(Sn_SSR(sn));
}

static inline Uint16 c2837x_w5300_get_sn_mr(Uint16 sn)
{
    return c2837x_w5300_read8(Sn_MR(sn));
}

static inline Uint16 c2837x_w5300_get_sn_ir(Uint16 sn)
{
    return c2837x_w5300_read8(Sn_IR(sn));
}

static inline void c2837x_w5300_set_sn_ir(Uint16 sn, Uint16 ir)
{
    c2837x_w5300_write8(Sn_IR(sn), ir);
}

static inline void c2837x_w5300_set_sn_tx_wrsr(Uint16 sn, Uint32 size)
{
    c2837x_w5300_write16(Sn_TX_WRSR(sn),  (Uint16)(size >> 16));
    c2837x_w5300_write16(Sn_TX_WRSR2(sn), (Uint16)size);
}

/* ---- Network register inline helpers ---- */
static inline void c2837x_w5300_set_subr(Uint32 submask)
{
    c2837x_w5300_write16(SUBR0, (Uint16)(submask >> 16));
    c2837x_w5300_write16(SUBR2, (Uint16)submask);
}

static inline void c2837x_w5300_clear_subr(void)
{
    c2837x_w5300_write16(SUBR0, 0);
    c2837x_w5300_write16(SUBR2, 0);
}

static inline void c2837x_w5300_set_gar(Uint32 gateway)
{
    c2837x_w5300_write16(GAR0, (Uint16)(gateway >> 16));
    c2837x_w5300_write16(GAR2, (Uint16)gateway);
}

static inline void c2837x_w5300_set_sipr(Uint32 ip)
{
    c2837x_w5300_write16(SIPR0, (Uint16)(ip >> 16));
    c2837x_w5300_write16(SIPR2, (Uint16)ip);
}

static inline void c2837x_w5300_set_shar(Uint16 mac01, Uint16 mac23, Uint16 mac45)
{
    c2837x_w5300_write16(SHAR0, mac01);
    c2837x_w5300_write16(SHAR2, mac23);
    c2837x_w5300_write16(SHAR4, mac45);
}

/* ---- Multi-read register helpers ---- */
int16 c2837x_w5300_get_sn_tx_fsr(Uint16 sn, Uint32 *value);
int16 c2837x_w5300_get_sn_rx_rsr(Uint16 sn, Uint32 *value);

/* ---- FIFO stream I/O ----
 *
 * Word mapping documentation:
 *   W5300 FIFO is 16-bit wide. Each FIFO word carries 2 wire bytes.
 *   When c2837x_w5300_fifo_swap == 0:
 *     FIFO word[0] low byte = wire byte 0, high byte = wire byte 1
 *     i.e. word[0] = 0x0201 for wire bytes 01 02
 *   When c2837x_w5300_fifo_swap == 1:
 *     FIFO word[0] is byte-swapped by the hardware bus
 *     i.e. word[0] = 0x0102 for wire bytes 01 02
 *
 * DSP-native char packing:
 *   Each DSP char (Uint16, lower 8 bits meaningful) maps to one wire byte.
 *   dspData[i] low byte = wire byte (2*i), dspData[i] high byte = wire byte (2*i+1)
 *   This matches the byteswap_L8exp_PIL convention.
 */
Uint32 c2837x_w5300_write_stream(Uint16 sn, const Uint16* dsp_data, Uint32 wire_byte_count);
Uint32 c2837x_w5300_read_stream(Uint16 sn, Uint16* dsp_data, Uint32 wire_byte_count);

#endif /* C2837X_W5300_HAL_H */
