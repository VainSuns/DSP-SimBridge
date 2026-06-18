
/*
* Socket.c
*
* Created on: 2026.5.25
* Author: Sun
*/


#include "W5300_Socket.h"
#include "W5300_C2837x.h"


int16 OpenSocket(W5300_Socket* sk, Uint16 protocol, Uint16 port, Uint16 flag)
{
    int16 result;
    // set Sn_MR with protocol & flag
    W5300_Write16(Sn_MR(sk->sn), (Uint16)(protocol | flag));
    if(protocol == Sn_MR_TCP)
    {
        W5300_Write16(Sn_TTLR(sk->sn), 128);
        W5300_Write16(Sn_TOSR(sk->sn), 0);
        W5300_Write16(Sn_IMR(sk->sn), 0x1F);
        W5300_Write16(Sn_PROTOR(sk->sn), 0x100);
        W5300_Write16(IMR, 0x0ff);
    }

    W5300_Write16(Sn_PORTR(sk->sn), port);

    result = SetSn_CR(sk->sn, Sn_CR_OPEN);
    if (result < 0)
    {
        return result;
    }

    sk->recv_pending_valid = 0;
    sk->recv_pending_remain = 0U;
    sk->send_connected = 0;

    return 0;
}

int16 CloseSocket(W5300_Socket* sk)
{
    Uint16 loop_cnt = 0;
    Uint32 destip = 0x00000001; // 0.0.0.1
    if( (GetSn_MR(sk->sn) == Sn_MR_TCP) && (GetSn_TX_FSR(sk->sn) != sk->tx_mem_size) )
    {
        while(GetSn_TX_FSR(sk->sn) != sk->tx_mem_size)
        {
            if(loop_cnt++ > 10)
            {
                OpenSocket(sk, Sn_MR_UDP, 0x3000, 0);
                // send the dummy data to an unknown destination(0.0.0.1).
                SendToSocket(sk, (Uint16*)"x", 1, destip, 0x3000, 0);
                break;
            }
            DELAY_US(10000);
        }
    };

    SetSn_IR(sk->sn, 0x00FF);  // Clear the remained interrupt bits.
    sk->recv_pending_valid = 0;
    sk->recv_pending_remain = 0U;
    sk->send_connected = 0;
    return SetSn_CR(sk->sn, Sn_CR_CLOSE);  // Close s-th SOCKET
}

int16 ListenSocket(W5300_Socket* sk)
{
    if (GetSn_SSR(sk->sn) != SOCK_INIT)
    {
        return -1;
    }

    return SetSn_CR(sk->sn,Sn_CR_LISTEN);
}

#if __TI_COMPILER_VERSION__ >= 15009000
    #pragma CODE_SECTION(SendStream, ".TI.ramfunc");
#else
    #pragma CODE_SECTION(SendStream, "ramfuncs");
#endif
int32 SendStream(W5300_Socket* sk, const Uint16* dspData, Uint32 wireByteCount)
{
    if (wireByteCount == 0U) return 0;

    if (!sk->send_connected)
    {
        Uint16 status = GetSn_SSR(sk->sn);
        if ((status != SOCK_ESTABLISHED) && (status != SOCK_CLOSE_WAIT))
            return 0;
        sk->send_connected = 1;
    }

    {
        Uint16 ir = GetSn_IR(sk->sn);
        if (ir & Sn_IR_TIMEOUT)
        {
            SetSn_IR(sk->sn, Sn_IR_TIMEOUT);
            sk->send_connected = 0;
            return 0;
        }
    }

    {
        Uint32 freesize = GetSn_TX_FSR(sk->sn);
        if (freesize == 0U) return 0;

        Uint32 chunk = wireByteCount;
        if (chunk > freesize) chunk = freesize;
        if (chunk > sk->tx_mem_size) chunk = sk->tx_mem_size;

        W5300_WriteStream(sk->sn, dspData, chunk);
        SetSn_TX_WRSR(sk->sn, chunk);
        if (SetSn_CR(sk->sn, Sn_CR_SEND) < 0) return -1;

        return (int32)chunk;
    }
}

#if __TI_COMPILER_VERSION__ >= 15009000
    #pragma CODE_SECTION(RecvStream, ".TI.ramfunc");
#else
    #pragma CODE_SECTION(RecvStream, "ramfuncs");
#endif
int32 RecvStream(W5300_Socket* sk, Uint16* dspData, Uint32 wireCapacity)
{
    Uint16 status;
    Uint32 pack_size;
    Uint32 copySize;
    Uint32 rxsize;

    if (wireCapacity == 0U) return 0;

    status = GetSn_SSR(sk->sn);
    if (status == SOCK_CLOSED)
    {
        sk->recv_pending_valid = 0;
        sk->recv_pending_remain = 0U;
        return 0;
    }

    rxsize = GetSn_RX_RSR(sk->sn);
    if (rxsize == 0U) return 0;

    if (sk->recv_pending_valid)
    {
        pack_size = sk->recv_pending_remain;
        if (pack_size == 0U)
        {
            sk->recv_pending_valid = 0;
            if (SetSn_CR(sk->sn, Sn_CR_RECV) < 0) return -1;
            return 0;
        }
    }
    else if (W5300_Read16(Sn_MR(sk->sn)) & Sn_MR_ALIGN)
    {
        pack_size = rxsize;
        sk->recv_pending_valid = 1;
        sk->recv_pending_remain = pack_size;
    }
    else
    {
        Uint16 raw;

        if (rxsize < 2U) return 0;

        raw = W5300_Read16(Sn_RX_FIFOR(sk->sn));
        if (g_w5300_fifo_swap) raw = (Uint16)((raw << 8) | (raw >> 8));
        pack_size = raw;
        if (pack_size == 0U)
        {
            if (SetSn_CR(sk->sn, Sn_CR_RECV) < 0) return -1;
            return 0;
        }

        sk->recv_pending_valid = 1;
        sk->recv_pending_remain = pack_size;
        rxsize = GetSn_RX_RSR(sk->sn);
        if (rxsize == 0U) return 0;
    }

    copySize = sk->recv_pending_remain;
    if (copySize > wireCapacity) copySize = wireCapacity;
    if (copySize > rxsize) copySize = rxsize;

    if (copySize == 0U) return 0;

    W5300_ReadStream(sk->sn, dspData, copySize);
    sk->recv_pending_remain -= copySize;

    if (sk->recv_pending_remain == 0U)
    {
        sk->recv_pending_valid = 0;
        if (SetSn_CR(sk->sn, Sn_CR_RECV) < 0) return -1;
    }

    return (int32)copySize;
}

int32 SendToSocket(W5300_Socket* sk, Uint16* buf, Uint32 len, Uint32 addr, Uint16 port, Uint32 subnet_mask)
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
    Set_SIPR(addr);

    // set destination port number
    W5300_Write16(Sn_DPORTR(sk->sn), port);

    W5300_WriteStream(sk->sn, buf, ret);
    // send
    SetSn_TX_WRSR(sk->sn, ret);
    Set_SUBR(subnet_mask);
    SetSn_CR(sk->sn, Sn_CR_SEND);

    while (!((isr = GetSn_IR(sk->sn)) & Sn_IR_SENDOK)) // wait SEND command completion
    {
        status = GetSn_SSR(sk->sn);
        if ((status == SOCK_CLOSED) || (isr & Sn_IR_TIMEOUT)) // Sn_IR_TIMEOUT causes the decrement of Sn_TX_FSR
        {
            SetSn_IR(sk->sn, Sn_IR_TIMEOUT);
            return 0;
        }
    }

    SetSn_IR(sk->sn, Sn_IR_SENDOK); // Clear Sn_IR_SENDOK
    Clear_SUBR();

    return ret;
}

//
// End of file
//
