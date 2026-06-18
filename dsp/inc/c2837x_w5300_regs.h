#ifndef C2837X_W5300_REGS_H
#define C2837X_W5300_REGS_H

/*
 * W5300 register and bit definitions for C2837xBlock project.
 * Register names follow the W5300 datasheet convention (Sn_MR, Sn_CR, etc.).
 * Project macros use C2837X_W5300_* prefix.
 */

#define C2837X_W5300_MAX_SOCK_NUM 8

#define C2837X_W5300_DIRECT_MODE   1
#define C2837X_W5300_INDIRECT_MODE 2

#define C2837X_W5300_ADDRESS_MODE C2837X_W5300_DIRECT_MODE

/*
 * Base address of W5300 on the target host system.
 */
#define C2837X_W5300_MAP_BASE 0x380000u

#if (C2837X_W5300_ADDRESS_MODE == C2837X_W5300_DIRECT_MODE)
#define COMMON_REG_BASE  C2837X_W5300_MAP_BASE
#define SOCKET_REG_BASE  (C2837X_W5300_MAP_BASE + 0x0200u)
#else
#define COMMON_REG_BASE  0u
#define SOCKET_REG_BASE  0x0200u
#endif

#define SOCKET_REG_SIZE 0x40u

/* ---- Mode register ---- */
#define MR   (C2837X_W5300_MAP_BASE)
#define MR0  MR
#define MR1  (MR + 1u)

/* ---- Indirect mode address register ---- */
#define IDM_AR  (C2837X_W5300_MAP_BASE + 0x02u)
#define IDM_AR0 IDM_AR
#define IDM_AR1 (IDM_AR + 1u)

/* ---- Indirect mode data register ---- */
#define IDM_DR  (C2837X_W5300_MAP_BASE + 0x04u)
#define IDM_DR0 IDM_DR
#define IDM_DR1 (IDM_DR + 1u)

/* ---- Interrupt register ---- */
#define IR  (COMMON_REG_BASE + 0x02u)
#define IR0 IR
#define IR1 (IR + 1u)

/* ---- Interrupt mask register ---- */
#define IMR  (COMMON_REG_BASE + 0x04u)
#define IMR0 IMR
#define IMR1 (IMR + 1u)

/* ---- Source hardware address register ---- */
#define SHAR  (COMMON_REG_BASE + 0x08u)
#define SHAR0 SHAR
#define SHAR1 (SHAR + 1u)
#define SHAR2 (SHAR + 2u)
#define SHAR3 (SHAR + 3u)
#define SHAR4 (SHAR + 4u)
#define SHAR5 (SHAR + 5u)

/* ---- Gateway IP address register ---- */
#define GAR  (COMMON_REG_BASE + 0x10u)
#define GAR0 GAR
#define GAR1 (GAR + 1u)
#define GAR2 (GAR + 2u)
#define GAR3 (GAR + 3u)

/* ---- Subnet mask register ---- */
#define SUBR  (COMMON_REG_BASE + 0x14u)
#define SUBR0 SUBR
#define SUBR1 (SUBR + 1u)
#define SUBR2 (SUBR + 2u)
#define SUBR3 (SUBR + 3u)

/* ---- Source IP address register ---- */
#define SIPR  (COMMON_REG_BASE + 0x18u)
#define SIPR0 SIPR
#define SIPR1 (SIPR + 1u)
#define SIPR2 (SIPR + 2u)
#define SIPR3 (SIPR + 3u)

/* ---- Retransmission timeout register ---- */
#define RTR  (COMMON_REG_BASE + 0x1Cu)
#define RTR0 RTR
#define RTR1 (RTR + 1u)

/* ---- Retransmission retry count register ---- */
#define RCR  (COMMON_REG_BASE + 0x1Eu)
#define RCR0 RCR
#define RCR1 (RCR + 1u)

/* ---- TX memory size registers ---- */
#define TMS01R (COMMON_REG_BASE + 0x20u)
#define TMS23R (TMS01R + 2u)
#define TMS45R (TMS01R + 4u)
#define TMS67R (TMS01R + 6u)

#define TMSR0 TMS01R
#define TMSR1 (TMSR0 + 1u)
#define TMSR2 (TMSR0 + 2u)
#define TMSR3 (TMSR0 + 3u)
#define TMSR4 (TMSR0 + 4u)
#define TMSR5 (TMSR0 + 5u)
#define TMSR6 (TMSR0 + 6u)
#define TMSR7 (TMSR0 + 7u)

/* ---- RX memory size registers ---- */
#define RMS01R (COMMON_REG_BASE + 0x28u)
#define RMS23R (RMS01R + 2u)
#define RMS45R (RMS01R + 4u)
#define RMS67R (RMS01R + 6u)

#define RMSR0 RMS01R
#define RMSR1 (RMSR0 + 1u)
#define RMSR2 (RMSR0 + 2u)
#define RMSR3 (RMSR0 + 3u)
#define RMSR4 (RMSR0 + 4u)
#define RMSR5 (RMSR0 + 5u)
#define RMSR6 (RMSR0 + 6u)
#define RMSR7 (RMSR0 + 7u)

/* ---- Memory type register ---- */
#define MTYPER  (COMMON_REG_BASE + 0x30u)
#define MTYPER0 MTYPER
#define MTYPER1 (MTYPER + 1u)

/* ---- Authentication type register ---- */
#define PATR  (COMMON_REG_BASE + 0x32u)
#define PATR0 PATR
#define PATR1 (PATR + 1u)

/* ---- PPP link control protocol request timer ---- */
#define PTIMER  (COMMON_REG_BASE + 0x36u)
#define PTIMER0 PTIMER
#define PTIMER1 (PTIMER + 1u)

/* ---- PPP LCP magic number register ---- */
#define PMAGICR  (COMMON_REG_BASE + 0x38u)
#define PMAGICR0 PMAGICR
#define PMAGICR1 (PMAGICR + 1u)

/* ---- PPPoE session ID register ---- */
#define PSIDR  (COMMON_REG_BASE + 0x3Cu)
#define PSIDR0 PSIDR
#define PSIDR1 (PSIDR + 1u)

/* ---- PPPoE destination hardware address register ---- */
#define PDHAR  (COMMON_REG_BASE + 0x40u)
#define PDHAR0 PDHAR
#define PDHAR1 (PDHAR + 1u)
#define PDHAR2 (PDHAR + 2u)
#define PDHAR3 (PDHAR + 3u)
#define PDHAR4 (PDHAR + 4u)
#define PDHAR5 (PDHAR + 5u)

/* ---- Unreachable IP address register ---- */
#define UIPR  (COMMON_REG_BASE + 0x48u)
#define UIPR0 UIPR
#define UIPR1 (UIPR + 1u)
#define UIPR2 (UIPR + 2u)
#define UIPR3 (UIPR + 3u)

/* ---- Unreachable port number register ---- */
#define UPORTR  (COMMON_REG_BASE + 0x4Cu)
#define UPORTR0 UPORTR
#define UPORTR1 (UPORTR + 1u)

/* ---- Fragment MTU register ---- */
#define FMTUR  (COMMON_REG_BASE + 0x4Eu)
#define FMTUR0 FMTUR
#define FMTUR1 (FMTUR + 1u)

/* ---- PIN BRDYn configure register ---- */
#define Pn_BRDYR(n)   (COMMON_REG_BASE + 0x60u + (n) * 4u)
#define Pn_BRDYR0(n)  Pn_BRDYR(n)
#define Pn_BRDYR1(n)  (Pn_BRDYR(n) + 1u)

/* ---- PIN BRDYn buffer depth register ---- */
#define Pn_BDPTHR(n)  (COMMON_REG_BASE + 0x60u + (n) * 4u + 2u)
#define Pn_BDPTHR0(n) Pn_BDPTHR(n)
#define Pn_BDPTHR1(n) (Pn_BDPTHR(n) + 1u)

/* ---- W5300 identification register ---- */
#define IDR  (COMMON_REG_BASE + 0xFEu)
#define IDR1 (IDR + 1u)

/* ---- SOCKETn mode register ---- */
#define Sn_MR(n)   (SOCKET_REG_BASE + (n) * SOCKET_REG_SIZE + 0x00u)
#define Sn_MR0(n)  Sn_MR(n)
#define Sn_MR1(n)  (Sn_MR(n) + 1u)

/* ---- SOCKETn command register ---- */
#define Sn_CR(n)   (SOCKET_REG_BASE + (n) * SOCKET_REG_SIZE + 0x02u)
#define Sn_CR0(n)  Sn_CR(n)
#define Sn_CR1(n)  (Sn_CR(n) + 1u)

/* ---- SOCKETn interrupt mask register ---- */
#define Sn_IMR(n)  (SOCKET_REG_BASE + (n) * SOCKET_REG_SIZE + 0x04u)
#define Sn_IMR0(n) Sn_IMR(n)
#define Sn_IMR1(n) (Sn_IMR(n) + 1u)

/* ---- SOCKETn interrupt register ---- */
#define Sn_IR(n)   (SOCKET_REG_BASE + (n) * SOCKET_REG_SIZE + 0x06u)
#define Sn_IR0(n)  Sn_IR(n)
#define Sn_IR1(n)  (Sn_IR(n) + 1u)

/* ---- SOCKETn status register ---- */
#define Sn_SSR(n)  (SOCKET_REG_BASE + (n) * SOCKET_REG_SIZE + 0x08u)
#define Sn_SSR0(n) Sn_SSR(n)
#define Sn_SSR1(n) (Sn_SSR(n) + 1u)

/* ---- SOCKETn source port register ---- */
#define Sn_PORTR(n)  (SOCKET_REG_BASE + (n) * SOCKET_REG_SIZE + 0x0Au)
#define Sn_PORTR0(n) Sn_PORTR(n)
#define Sn_PORTR1(n) (Sn_PORTR(n) + 1u)

/* ---- SOCKETn destination hardware address register ---- */
#define Sn_DHAR(n)  (SOCKET_REG_BASE + (n) * SOCKET_REG_SIZE + 0x0Cu)
#define Sn_DHAR0(n) Sn_DHAR(n)
#define Sn_DHAR1(n) (Sn_DHAR(n) + 1u)
#define Sn_DHAR2(n) (Sn_DHAR(n) + 2u)
#define Sn_DHAR3(n) (Sn_DHAR(n) + 3u)
#define Sn_DHAR4(n) (Sn_DHAR(n) + 4u)
#define Sn_DHAR5(n) (Sn_DHAR(n) + 5u)

/* ---- SOCKETn destination port register ---- */
#define Sn_DPORTR(n)  (SOCKET_REG_BASE + (n) * SOCKET_REG_SIZE + 0x12u)
#define Sn_DPORTR0(n) Sn_DPORTR(n)
#define Sn_DPORTR1(n) (Sn_DPORTR(n) + 1u)

/* ---- SOCKETn destination IP address register ---- */
#define Sn_DIPR(n)  (SOCKET_REG_BASE + (n) * SOCKET_REG_SIZE + 0x14u)
#define Sn_DIPR0(n) Sn_DIPR(n)
#define Sn_DIPR1(n) (Sn_DIPR(n) + 1u)
#define Sn_DIPR2(n) (Sn_DIPR(n) + 2u)
#define Sn_DIPR3(n) (Sn_DIPR(n) + 3u)

/* ---- SOCKETn maximum segment size register ---- */
#define Sn_MSSR(n)  (SOCKET_REG_BASE + (n) * SOCKET_REG_SIZE + 0x18u)
#define Sn_MSSR0(n) Sn_MSSR(n)
#define Sn_MSSR1(n) (Sn_MSSR(n) + 1u)

/* ---- SOCKETn protocol of IP header field register ---- */
#define Sn_PROTOR(n)   (SOCKET_REG_BASE + (n) * SOCKET_REG_SIZE + 0x1Au)
#define Sn_KPALVTR(n)  Sn_PROTOR(n)
#define Sn_PROTOR1(n)  (Sn_PROTOR(n) + 1u)

/* ---- SOCKETn IP type of service register ---- */
#define Sn_TOSR(n)  (SOCKET_REG_BASE + (n) * SOCKET_REG_SIZE + 0x1Cu)
#define Sn_TOSR0(n) Sn_TOSR(n)
#define Sn_TOSR1(n) (Sn_TOSR(n) + 1u)

/* ---- SOCKETn IP time to live register ---- */
#define Sn_TTLR(n)  (SOCKET_REG_BASE + (n) * SOCKET_REG_SIZE + 0x1Eu)
#define Sn_TTLR0(n) Sn_TTLR(n)
#define Sn_TTLR1(n) (Sn_TTLR(n) + 1u)

/* ---- SOCKETn TX write size register ---- */
#define Sn_TX_WRSR(n)  (SOCKET_REG_BASE + (n) * SOCKET_REG_SIZE + 0x20u)
#define Sn_TX_WRSR0(n) Sn_TX_WRSR(n)
#define Sn_TX_WRSR1(n) (Sn_TX_WRSR(n) + 1u)
#define Sn_TX_WRSR2(n) (Sn_TX_WRSR(n) + 2u)
#define Sn_TX_WRSR3(n) (Sn_TX_WRSR(n) + 3u)

/* ---- SOCKETn TX free size register ---- */
#define Sn_TX_FSR(n)  (SOCKET_REG_BASE + (n) * SOCKET_REG_SIZE + 0x24u)
#define Sn_TX_FSR0(n) Sn_TX_FSR(n)
#define Sn_TX_FSR1(n) (Sn_TX_FSR(n) + 1u)
#define Sn_TX_FSR2(n) (Sn_TX_FSR(n) + 2u)
#define Sn_TX_FSR3(n) (Sn_TX_FSR(n) + 3u)

/* ---- SOCKETn RX received size register ---- */
#define Sn_RX_RSR(n)  (SOCKET_REG_BASE + (n) * SOCKET_REG_SIZE + 0x28u)
#define Sn_RX_RSR0(n) Sn_RX_RSR(n)
#define Sn_RX_RSR1(n) (Sn_RX_RSR(n) + 1u)
#define Sn_RX_RSR2(n) (Sn_RX_RSR(n) + 2u)
#define Sn_RX_RSR3(n) (Sn_RX_RSR(n) + 3u)

/* ---- SOCKETn fragment register ---- */
#define Sn_FRAGR(n)  (SOCKET_REG_BASE + (n) * SOCKET_REG_SIZE + 0x2Cu)
#define Sn_FRAGR0(n) Sn_FRAGR(n)
#define Sn_FRAGR1(n) (Sn_FRAGR(n) + 1u)

/* ---- SOCKETn TX FIFO register ---- */
#define Sn_TX_FIFOR(n)  (SOCKET_REG_BASE + (n) * SOCKET_REG_SIZE + 0x2Eu)
#define Sn_TX_FIFOR0(n) Sn_TX_FIFOR(n)
#define Sn_TX_FIFOR1(n) (Sn_TX_FIFOR(n) + 1u)

/* ---- SOCKETn RX FIFO register ---- */
#define Sn_RX_FIFOR(n)  (SOCKET_REG_BASE + (n) * SOCKET_REG_SIZE + 0x30u)
#define Sn_RX_FIFOR0(n) Sn_RX_FIFOR(n)
#define Sn_RX_FIFOR1(n) (Sn_RX_FIFOR(n) + 1u)

/* ---- MR register bits ---- */
#define MR_DBW    (1u << 15)
#define MR_MPF    (1u << 14)
#define MR_WDF(X) (((X) & 0x07u) << 11)
#define MR_RDH    (1u << 10)
#define MR_FS     (1u << 8)
#define MR_RST    (1u << 7)
#define MR_MT     (1u << 5)
#define MR_PB     (1u << 4)
#define MR_PPPoE  (1u << 3)
#define MR_DBS    (1u << 2)
#define MR_IND    (1u << 0)

/* ---- IR register bits ---- */
#define IR_IPCF     (1u << 7)
#define IR_DPUR     (1u << 6)
#define IR_PPPT     (1u << 5)
#define IR_FMTU     (1u << 4)
#define IR_SnINT(n) (0x01u << (n))

/* ---- Pn_BRDYR register bits ---- */
#define Pn_PEN      (1u << 7)
#define Pn_MT       (1u << 6)
#define Pn_PPL      (1u << 5)
#define Pn_SN(n)    ((n) & 0x07u)

/* ---- Sn_MR register bits ---- */
#define Sn_MR_ALIGN  (1u << 8)
#define Sn_MR_MULTI  (1u << 7)
#define Sn_MR_MF     (1u << 6)
#define Sn_MR_IGMPv  (1u << 5)
#define Sn_MR_ND     (1u << 5)
#define Sn_MR_CLOSE  0x00u
#define Sn_MR_TCP    0x01u
#define Sn_MR_UDP    0x02u
#define Sn_MR_IPRAW  0x03u
#define Sn_MR_MACRAW 0x04u
#define Sn_MR_PPPoE  0x05u

/* ---- Sn_CR command values ---- */
#define Sn_CR_OPEN      0x01u
#define Sn_CR_LISTEN    0x02u
#define Sn_CR_CONNECT   0x04u
#define Sn_CR_DISCON    0x08u
#define Sn_CR_CLOSE     0x10u
#define Sn_CR_SEND      0x20u
#define Sn_CR_SEND_MAC  0x21u
#define Sn_CR_SEND_KEEP 0x22u
#define Sn_CR_RECV      0x40u
#define Sn_CR_PCON      0x23u
#define Sn_CR_PDISCON   0x24u
#define Sn_CR_PCR       0x25u
#define Sn_CR_PCN       0x26u
#define Sn_CR_PCJ       0x27u

/* ---- Sn_IR register bits ---- */
#define Sn_IR_PRECV   0x80u
#define Sn_IR_PFAIL   0x40u
#define Sn_IR_PNEXT   0x20u
#define Sn_IR_SENDOK  0x10u
#define Sn_IR_TIMEOUT 0x08u
#define Sn_IR_RECV    0x04u
#define Sn_IR_DISCON  0x02u
#define Sn_IR_CON     0x01u

/* ---- Sn_SSR socket status values ---- */
#define SOCK_CLOSED      0x00u
#define SOCK_ARP         0x01u
#define SOCK_INIT        0x13u
#define SOCK_LISTEN      0x14u
#define SOCK_SYNSENT     0x15u
#define SOCK_SYNRECV     0x16u
#define SOCK_ESTABLISHED 0x17u
#define SOCK_FIN_WAIT    0x18u
#define SOCK_CLOSING     0x1Au
#define SOCK_TIME_WAIT   0x1Bu
#define SOCK_CLOSE_WAIT  0x1Cu
#define SOCK_LAST_ACK    0x1Du
#define SOCK_UDP         0x22u
#define SOCK_IPRAW       0x32u
#define SOCK_MACRAW      0x42u
#define SOCK_PPPoE       0x5Fu

#endif /* C2837X_W5300_REGS_H */
