#ifndef _W5300_C2837X_H_
#define _W5300_C2837X_H_


#include "F28x_Project.h"
#include "W5300_define.h"

#define W5300_RESET_PIN 99

void Init_W5300(void);
void Reset_W5300(void);

/** @brief Reads a 16-bit value from the W5300 memory.
 * @param addr The memory address to read from.
 * @return The 16-bit value read from the specified address.
 */
Uint16 W5300_Read16(Uint32 addr);

/** @brief Writes a 16-bit value to the W5300 memory.
 * @param addr The memory address to write to.
 * @param data The 16-bit value to write.
 */
void W5300_Write16(Uint32 addr, Uint16 data);

/** @brief Writes an 8-bit value to the W5300 memory.
 * @param addr The memory address to write to.
 * @param data The 8-bit value to write.
 */
static inline Uint16 W5300_Read8(Uint32 addr)
{
    return (Uint16)(W5300_Read16(addr) & 0x00FF);
}

/** @brief Writes an 8-bit value to the W5300 memory.
 * @param addr The memory address to write to.
 * @param data The 8-bit value to write.
 */
static inline void W5300_Write8(Uint32 addr, Uint16 data)
{
    W5300_Write16(addr, data & 0x00FF);
}

/** @brief Sets the command register of a specified socket.
 * @param sn The socket number (0 to 7).
 * @param data The command value to write to the command register.
 * @return Returns 0 if the command was successfully set, or -1 if there was an error (e.g., invalid socket number).
 */
int16 SetSn_CR(Uint16 sn, Uint16 data);

/** @brief Retrieves the status register value of a specified socket.
 * @param sn The socket number (0 to 7).
 * @return The value of the status register for the specified socket
 */
static inline Uint16 GetSn_SSR(Uint16 sn)
{
    return W5300_Read8(Sn_SSR(sn));
}

/** @brief Sets the status register of a specified socket.
 * @param sn The socket number (0 to 7).
 * @param data The status value to write to the status register.
 * @return Returns 0 if the status was successfully set, or -1 if there was an error (e.g., invalid socket number).
 */
static inline Uint16 GetSn_MR(Uint16 sn)
{
   return W5300_Read8(Sn_MR(sn));
}

/** @brief Retrieves the free size of the transmit buffer for a specified socket.
 * @param sn The socket number (0 to 7).
 * @return The free size of the transmit buffer for the specified socket.
 */
Uint32 GetSn_TX_FSR(Uint16 sn);

/** @brief Retrieves the received size of the receive buffer for a specified socket.
 * @param sn The socket number (0 to 7).
 * @return The received size of the receive buffer for the specified socket.
 */
Uint32 GetSn_RX_RSR(Uint16 sn);

/** @brief Retrieves the interrupt register value of a specified socket.
 * @param sn The socket number (0 to 7).
 * @return The value of the interrupt register for the specified socket.
 */
static inline Uint16 GetSn_IR(Uint16 sn)
{
   return W5300_Read8(Sn_IR(sn));
}

/** @brief Sets the interrupt register of a specified socket.
 * @param s The socket number (0 to 7).
 * @param ir The interrupt value to write to the interrupt register.
 */
static inline void SetSn_IR(Uint16 s, Uint16 ir)
{
    W5300_Write8(Sn_IR(s), ir);
}

/** @brief Sets the transmit write size for a specified socket.
 * @param sn The socket number (0 to 7).
 * @param size The transmit write size to set for the specified socket.
 */
static inline void SetSn_TX_WRSR(Uint16 sn, Uint32 size)
{
   W5300_Write16(Sn_TX_WRSR(sn), (Uint16)(size >> 16));
   W5300_Write16(Sn_TX_WRSR2(sn), (Uint16)size);
}

static inline void Set_SUBR(Uint32 submask)
{
    W5300_Write16(SUBR0, (Uint16)(submask >> 16));
    W5300_Write16(SUBR2, (Uint16)submask);
}

static inline void Clear_SUBR()
{
    W5300_Write16(SUBR0, 0);
    W5300_Write16(SUBR2, 0);
}

static inline void Set_GAR(Uint32 gateway)
{
    W5300_Write16(GAR0, (Uint16)(gateway >> 16));
    W5300_Write16(GAR2, (Uint16)gateway);
}

static inline void Set_SIPR(Uint32 ip)
{
    W5300_Write16(SIPR0, (Uint16)(ip >> 16));
    W5300_Write16(SIPR2, (Uint16)ip);
}

static inline void Set_SHAR(Uint16 mac01, Uint16 mac23, Uint16 mac45)
{
    W5300_Write16(SHAR0, mac01);
    W5300_Write16(SHAR2, mac23);
    W5300_Write16(SHAR4, mac45);
}

extern Uint16 g_w5300_fifo_swap;

/** @brief Write DSP-native char stream directly to W5300 TX FIFO.
 *  Each DSP char (16-bit, lower 8 bits meaningful) packs into one FIFO word (2 wire bytes).
 *  Wire format matches byteswap_L8exp_PIL: low byte first, then high byte.
 * @param s Socket number (0-7).
 * @param dspData Pointer to DSP char array.
 * @param wireByteCount Number of wire bytes to write (= 2 * DSP chars).
 * @return wireByteCount.
 */
Uint32 W5300_WriteStream(Uint16 s, const Uint16* dspData, Uint32 wireByteCount);

/** @brief Read from W5300 RX FIFO and unpack directly into DSP-native chars.
 *  Each FIFO word (2 wire bytes) unpacks to one DSP char.
 *  Unpack matches byteswap_L8cmp_PIL.
 * @param s Socket number (0-7).
 * @param dspData Destination DSP char array.
 * @param wireByteCount Number of wire bytes to read.
 * @return wireByteCount.
 */
Uint32 W5300_ReadStream(Uint16 s, Uint16* dspData, Uint32 wireByteCount);

#endif

//
// End of file
//
