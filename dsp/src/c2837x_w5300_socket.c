/* Bounded W5300 TCP stream operations for C2837xBlock. */

#include "c2837x_w5300_socket.h"

static int16 socket_is_valid(const C2837xW5300Socket *sk)
{
    if ((sk == 0) || (sk->sn >= C2837X_W5300_MAX_SOCK_NUM))
        return 0;
    return (((sk->pending_command == C2837X_W5300_COMMAND_NONE) &&
             (sk->command_phase == C2837X_W5300_COMMAND_PHASE_IDLE)) ||
            ((sk->pending_command != C2837X_W5300_COMMAND_NONE) &&
             (sk->command_phase != C2837X_W5300_COMMAND_PHASE_IDLE))) ? 1 : 0;
}

static void clear_socket_interrupts(Uint16 sn)
{
    c2837x_w5300_set_sn_ir(sn, 0x00FFu);
    c2837x_w5300_write16(IR, (Uint16)(1u << sn));
}

static void complete_pending(C2837xW5300Socket *sk)
{
    sk->pending_command = C2837X_W5300_COMMAND_NONE;
    sk->command_phase = C2837X_W5300_COMMAND_PHASE_IDLE;
}

static int16 advance_target_state(C2837xW5300Socket *sk)
{
    Uint16 status = c2837x_w5300_get_sn_ssr(sk->sn);

    switch (sk->pending_command)
    {
    case C2837X_W5300_COMMAND_OPEN:
        if (status == SOCK_INIT)
        {
            complete_pending(sk);
            return 1;
        }
        return ((status == SOCK_CLOSED) || (status == SOCK_ARP)) ? 0 : -1;

    case C2837X_W5300_COMMAND_LISTEN:
        if ((status == SOCK_LISTEN) || (status == SOCK_SYNRECV) ||
            (status == SOCK_ESTABLISHED) || (status == SOCK_CLOSE_WAIT))
        {
            complete_pending(sk);
            return 1;
        }
        return (status == SOCK_INIT) ? 0 : -1;

    case C2837X_W5300_COMMAND_DISCONNECT:
        if (status == SOCK_CLOSED)
        {
            complete_pending(sk);
            return 1;
        }
        return ((status == SOCK_ESTABLISHED) ||
                (status == SOCK_CLOSE_WAIT) || (status == SOCK_FIN_WAIT) ||
                (status == SOCK_CLOSING) || (status == SOCK_TIME_WAIT) ||
                (status == SOCK_LAST_ACK)) ? 0 : -1;

    case C2837X_W5300_COMMAND_CLOSE:
        if (status == SOCK_CLOSED)
        {
            complete_pending(sk);
            return 1;
        }
        return c2837x_w5300_is_socket_status(status) ? 0 : -1;

    default:
        return -1;
    }
}

static int16 advance_pending(C2837xW5300Socket *sk)
{
    int16 result;

    if (sk->command_phase == C2837X_W5300_COMMAND_PHASE_WAIT_CR_CLEAR)
    {
        result = c2837x_w5300_poll_sn_cr(sk->sn);
        if (result <= 0)
            return result;
        if ((sk->pending_command == C2837X_W5300_COMMAND_SEND) ||
            (sk->pending_command == C2837X_W5300_COMMAND_RECV))
        {
            complete_pending(sk);
            return 1;
        }
        sk->command_phase = C2837X_W5300_COMMAND_PHASE_WAIT_TARGET_STATE;
        return 0;
    }
    if (sk->command_phase == C2837X_W5300_COMMAND_PHASE_WAIT_TARGET_STATE)
        return advance_target_state(sk);
    return -1;
}

static int16 advance_for(C2837xW5300Socket *sk,
                         C2837xW5300PendingCommand requested)
{
    C2837xW5300PendingCommand pending = sk->pending_command;
    int16 result = advance_pending(sk);

    if (result < 0)
        return result;
    return ((result > 0) && (pending == requested)) ? 1 : 0;
}

static int16 issue(C2837xW5300Socket *sk, Uint16 command,
                   C2837xW5300PendingCommand pending)
{
    if (c2837x_w5300_issue_sn_cr(sk->sn, command) < 0)
        return -1;
    sk->pending_command = pending;
    sk->command_phase = C2837X_W5300_COMMAND_PHASE_WAIT_CR_CLEAR;
    return 0;
}

int16 c2837x_w5300_socket_open(C2837xW5300Socket *sk, Uint16 protocol,
                               Uint16 port, Uint16 flags)
{
    if (!socket_is_valid(sk))
        return -1;
    if (sk->pending_command != C2837X_W5300_COMMAND_NONE)
        return advance_for(sk, C2837X_W5300_COMMAND_OPEN);

    clear_socket_interrupts(sk->sn);
    c2837x_w5300_write16(Sn_MR(sk->sn), (Uint16)(protocol | flags));
    if (protocol == Sn_MR_TCP)
    {
        c2837x_w5300_write16(Sn_TTLR(sk->sn), 128u);
        c2837x_w5300_write16(Sn_TOSR(sk->sn), 0u);
        c2837x_w5300_write16(Sn_IMR(sk->sn), 0x1Fu);
        c2837x_w5300_write16(Sn_PROTOR(sk->sn), 0x100u);
    }
    c2837x_w5300_write16(Sn_PORTR(sk->sn), port);
    return issue(sk, Sn_CR_OPEN, C2837X_W5300_COMMAND_OPEN);
}

int16 c2837x_w5300_socket_listen(C2837xW5300Socket *sk)
{
    if (!socket_is_valid(sk))
        return -1;
    if (sk->pending_command != C2837X_W5300_COMMAND_NONE)
        return advance_for(sk, C2837X_W5300_COMMAND_LISTEN);
    if (c2837x_w5300_get_sn_ssr(sk->sn) != SOCK_INIT)
        return -1;
    clear_socket_interrupts(sk->sn);
    return issue(sk, Sn_CR_LISTEN, C2837X_W5300_COMMAND_LISTEN);
}

int16 c2837x_w5300_socket_disconnect(C2837xW5300Socket *sk)
{
    if (!socket_is_valid(sk))
        return -1;
    if (sk->pending_command != C2837X_W5300_COMMAND_NONE)
        return advance_for(sk, C2837X_W5300_COMMAND_DISCONNECT);
    return issue(sk, Sn_CR_DISCON, C2837X_W5300_COMMAND_DISCONNECT);
}

int16 c2837x_w5300_socket_close(C2837xW5300Socket *sk)
{
    C2837xW5300PendingCommand pending;
    int16 result;
    Uint16 status;

    if (!socket_is_valid(sk))
        return -1;
    if (sk->pending_command != C2837X_W5300_COMMAND_NONE)
    {
        pending = sk->pending_command;
        result = advance_pending(sk);
        if (result < 0)
            return result;
        return ((result > 0) &&
                ((pending == C2837X_W5300_COMMAND_CLOSE) ||
                 (pending == C2837X_W5300_COMMAND_DISCONNECT))) ? 1 : 0;
    }

    status = c2837x_w5300_get_sn_ssr(sk->sn);
    if (status == SOCK_CLOSED)
    {
        complete_pending(sk);
        return 1;
    }
    if (status == SOCK_CLOSE_WAIT)
        return issue(sk, Sn_CR_DISCON, C2837X_W5300_COMMAND_DISCONNECT);

    clear_socket_interrupts(sk->sn);
    return issue(sk, Sn_CR_CLOSE, C2837X_W5300_COMMAND_CLOSE);
}

#if __TI_COMPILER_VERSION__ >= 15009000
    #pragma CODE_SECTION(c2837x_w5300_socket_send, ".TI.ramfunc");
#else
    #pragma CODE_SECTION(c2837x_w5300_socket_send, "ramfuncs");
#endif
int32 c2837x_w5300_socket_send(C2837xW5300Socket *sk,
                               const Uint16 *data_words,
                               Uint32 wire_byte_count)
{
    Uint16 status;
    Uint16 ir;
    Uint32 free_size;
    Uint32 chunk;

    wire_byte_count &= ~1u;
    if (wire_byte_count == 0u)
        return 0;
    if (!socket_is_valid(sk) || (data_words == 0))
        return -1;
    if (sk->pending_command != C2837X_W5300_COMMAND_NONE)
        return (advance_pending(sk) < 0) ? -1 : 0;

    status = c2837x_w5300_get_sn_ssr(sk->sn);
    if ((status != SOCK_ESTABLISHED) && (status != SOCK_CLOSE_WAIT))
        return 0;
    ir = c2837x_w5300_get_sn_ir(sk->sn);
    if ((ir & Sn_IR_TIMEOUT) != 0u)
    {
        c2837x_w5300_set_sn_ir(sk->sn, Sn_IR_TIMEOUT);
        return -1;
    }
    if (c2837x_w5300_get_sn_tx_fsr(sk->sn, &free_size) < 0)
        return -1;

    chunk = wire_byte_count;
    if (chunk > free_size) chunk = free_size;
    if (chunk > sk->tx_mem_size) chunk = sk->tx_mem_size;
    chunk &= ~1u;
    if (chunk == 0u)
        return 0;

    c2837x_w5300_write_stream(sk->sn, data_words, chunk);
    c2837x_w5300_set_sn_tx_wrsr(sk->sn, chunk);
    if (issue(sk, Sn_CR_SEND, C2837X_W5300_COMMAND_SEND) < 0)
        return -1;
    /* S2-04 transition: SEND_OK completion and delayed progress are S2-05. */
    return (int32)chunk;
}

#if __TI_COMPILER_VERSION__ >= 15009000
    #pragma CODE_SECTION(c2837x_w5300_socket_recv, ".TI.ramfunc");
#else
    #pragma CODE_SECTION(c2837x_w5300_socket_recv, "ramfuncs");
#endif
int32 c2837x_w5300_socket_recv(C2837xW5300Socket *sk, Uint16 *data_words,
                               Uint32 wire_capacity_bytes)
{
    Uint16 status;
    Uint32 rx_size;
    Uint32 copy_size;

    wire_capacity_bytes &= ~1u;
    if (wire_capacity_bytes == 0u)
        return 0;
    if (!socket_is_valid(sk) || (data_words == 0))
        return -1;
    if (sk->pending_command != C2837X_W5300_COMMAND_NONE)
        return (advance_pending(sk) < 0) ? -1 : 0;

    status = c2837x_w5300_get_sn_ssr(sk->sn);
    if ((status != SOCK_ESTABLISHED) && (status != SOCK_CLOSE_WAIT))
        return 0;
    if (c2837x_w5300_get_sn_rx_rsr(sk->sn, &rx_size) < 0)
        return -1;

    copy_size = rx_size;
    if (copy_size > wire_capacity_bytes) copy_size = wire_capacity_bytes;
    if (copy_size > sk->rx_mem_size) copy_size = sk->rx_mem_size;
    copy_size &= ~1u;
    if (copy_size == 0u)
        return 0;

    c2837x_w5300_read_stream(sk->sn, data_words, copy_size);
    if (issue(sk, Sn_CR_RECV, C2837X_W5300_COMMAND_RECV) < 0)
        return -1;
    return (int32)copy_size;
}
