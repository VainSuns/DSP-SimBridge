/*
 * W5300 socket implementation for C2837xBlock project.
 * TCP stream send/recv — no PIL packet-length prefix.
 */

#include "c2837x_w5300_socket.h"
#include "c2837x_w5300_hal.h"


int32 c2837x_w5300_socket_send_to(C2837xW5300Socket* sk, const Uint16* buf, Uint32 len, Uint32 addr, Uint16 port, Uint32 subnet_mask);


int16 c2837x_w5300_socket_open(C2837xW5300Socket* sk,
                                Uint16 protocol,
                                Uint16 port,
                                Uint16 flags)
{
    int16 result;

    c2837x_w5300_set_sn_ir(sk->sn, 0x00FF);

    if (protocol == Sn_MR_TCP)
        flags = (Uint16)(flags | Sn_MR_ALIGN);

    c2837x_w5300_write16(Sn_MR(sk->sn), (Uint16)(protocol | flags));

    if (protocol == Sn_MR_TCP)
    {
        c2837x_w5300_write16(Sn_TTLR(sk->sn), 128);
        c2837x_w5300_write16(Sn_TOSR(sk->sn), 0);
        c2837x_w5300_write16(Sn_IMR(sk->sn), 0x1F);
        c2837x_w5300_write16(Sn_PROTOR(sk->sn), 0x100);
        c2837x_w5300_write16(IMR, 0x0FF);
    }

    c2837x_w5300_write16(Sn_PORTR(sk->sn), port);

    result = c2837x_w5300_set_sn_cr(sk->sn, Sn_CR_OPEN);
    if (result < 0)
    {
        return result;
    }

    return 0;
}

int16 c2837x_w5300_socket_close(C2837xW5300Socket* sk)
{
    // M_08082008 : It is fixed the problem that Sn_SSR cannot be changed a undefined value to the defined value.
    //              Refer to Errata of W5300
    //Check if the transmit data is remained or not.
    Uint16 loop_cnt = 0;
    Uint32 destip = 0x00000001; // 0.0.0.1
    if( (c2837x_w5300_get_sn_mr(sk->sn) == Sn_MR_TCP) && (c2837x_w5300_get_sn_tx_fsr(sk->sn) != sk->tx_mem_size) )
    {
        while(c2837x_w5300_get_sn_tx_fsr(sk->sn) != sk->tx_mem_size)
        {
            if(loop_cnt++ > 10)
            {
                c2837x_w5300_socket_open(sk, Sn_MR_UDP, 0x3000, 0);
                // send the dummy data to an unknown destination(0.0.0.1).
                c2837x_w5300_socket_send_to(sk, (Uint16*)"x", 1, destip, 0x3000, 0);
                break;
            }
            DELAY_US(10000);
        }
    };

    /* Non-blocking close: clear interrupts and issue CLOSE command
     * without waiting for TX buffer to drain. */
    c2837x_w5300_set_sn_ir(sk->sn, 0x00FF);
    return c2837x_w5300_set_sn_cr(sk->sn, Sn_CR_CLOSE);
}

int16 c2837x_w5300_socket_listen(C2837xW5300Socket* sk)
{
    if (c2837x_w5300_get_sn_ssr(sk->sn) != SOCK_INIT)
    {
        return -1;
    }
    c2837x_w5300_set_sn_ir(sk->sn, 0x00FF);
    return c2837x_w5300_set_sn_cr(sk->sn, Sn_CR_LISTEN);
}

#if __TI_COMPILER_VERSION__ >= 15009000
    #pragma CODE_SECTION(c2837x_w5300_socket_send, ".TI.ramfunc");
#else
    #pragma CODE_SECTION(c2837x_w5300_socket_send, "ramfuncs");
#endif
int32 c2837x_w5300_socket_send(C2837xW5300Socket* sk,
                                const Uint16* data_words,
                                Uint32 wire_byte_count)
{
    Uint16 status;
    Uint32 freesize;
    Uint32 chunk;

    if (wire_byte_count == 0U) return 0;

    /* Check connection state */
    status = c2837x_w5300_get_sn_ssr(sk->sn);
    if (status != SOCK_ESTABLISHED)
        return 0;

    /* Check for timeout error */
    {
        Uint16 ir = c2837x_w5300_get_sn_ir(sk->sn);
        if (ir & Sn_IR_TIMEOUT)
        {
            c2837x_w5300_set_sn_ir(sk->sn, Sn_IR_TIMEOUT);
            return -1;
        }
    }

    /* Get TX free size and send only what fits */
    freesize = c2837x_w5300_get_sn_tx_fsr(sk->sn);
    if (freesize == 0U) return 0;

    chunk = wire_byte_count;
    if (chunk > freesize) chunk = freesize;
    if (chunk > sk->tx_mem_size) chunk = sk->tx_mem_size;
    if (((chunk & 1U) != 0U) && (chunk < wire_byte_count))
        chunk--;
    if (chunk == 0U) return 0;

    c2837x_w5300_write_stream(sk->sn, data_words, chunk);
    c2837x_w5300_set_sn_tx_wrsr(sk->sn, chunk);
    if (c2837x_w5300_set_sn_cr(sk->sn, Sn_CR_SEND) < 0) return -1;

    return (int32)chunk;
}

#if __TI_COMPILER_VERSION__ >= 15009000
    #pragma CODE_SECTION(c2837x_w5300_socket_recv, ".TI.ramfunc");
#else
    #pragma CODE_SECTION(c2837x_w5300_socket_recv, "ramfuncs");
#endif
int32 c2837x_w5300_socket_recv(C2837xW5300Socket* sk,
                                Uint16* data_words,
                                Uint32 wire_capacity_bytes)
{
    Uint16 status;
    Uint32 rxsize;
    Uint32 copy_size;

    if (wire_capacity_bytes == 0U) return 0;

    status = c2837x_w5300_get_sn_ssr(sk->sn);
    if (status != SOCK_ESTABLISHED)
    {
        return 0;
    }

    /* Read available bytes from RX FIFO — pure TCP stream, no pack_size prefix */
    rxsize = c2837x_w5300_get_sn_rx_rsr(sk->sn);
    if (rxsize == 0U) return 0;

    copy_size = rxsize;
    if (copy_size > wire_capacity_bytes) copy_size = wire_capacity_bytes;
    if (((copy_size & 1U) != 0U) && (copy_size < wire_capacity_bytes))
        copy_size--;
    if (copy_size == 0U) return 0;

    c2837x_w5300_read_stream(sk->sn, data_words, copy_size);

    /* Update RX read pointer */
    if (c2837x_w5300_set_sn_cr(sk->sn, Sn_CR_RECV) < 0) return -1;

    return (int32)copy_size;
}

Uint32 c2837x_w5300_socket_get_tx_free(const C2837xW5300Socket* sk)
{
    return c2837x_w5300_get_sn_tx_fsr(sk->sn);
}

Uint32 c2837x_w5300_socket_get_rx_size(const C2837xW5300Socket* sk)
{
    return c2837x_w5300_get_sn_rx_rsr(sk->sn);
}

int32 c2837x_w5300_socket_send_to(C2837xW5300Socket* sk, const Uint16* buf, Uint32 len, Uint32 addr, Uint16 port, Uint32 subnet_mask)
{
    Uint16 status = 0;
    Uint16 isr = 0;
    Uint32 ret = 0;

    if (len > sk->tx_mem_size)
    {
        ret = sk->tx_mem_size; // check size not to exceed MAX size.
    }
    else
    {
        ret = len;
    }

    // set destination IP address
    c2837x_w5300_set_sipr(addr);

    // set destination port number
    c2837x_w5300_write16(Sn_DPORTR(sk->sn), port);

    c2837x_w5300_write_stream(sk->sn, buf, ret);
    // send
    c2837x_w5300_set_sn_tx_wrsr(sk->sn, ret);
    c2837x_w5300_set_subr(subnet_mask);
    c2837x_w5300_set_sn_cr(sk->sn, Sn_CR_SEND);

    while (!((isr = c2837x_w5300_get_sn_ir(sk->sn)) & Sn_IR_SENDOK)) // wait SEND command completion
    {
        status = c2837x_w5300_get_sn_ssr(sk->sn);
        if ((status == SOCK_CLOSED) || (isr & Sn_IR_TIMEOUT)) // Sn_IR_TIMEOUT causes the decrement of Sn_TX_FSR
        {
            c2837x_w5300_set_sn_ir(sk->sn, Sn_IR_TIMEOUT);
            return 0;
        }
    }

    c2837x_w5300_set_sn_ir(sk->sn, Sn_IR_SENDOK); // Clear Sn_IR_SENDOK
    c2837x_w5300_clear_subr();

    return ret;
}
