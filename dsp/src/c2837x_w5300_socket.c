/* Bounded W5300 socket operations for C2837xBlock. */

#include "c2837x_w5300_socket.h"

static int16 socket_is_valid(const C2837xW5300Socket *sk)
{
    if ((sk == 0) || (sk->sn >= C2837X_W5300_MAX_SOCK_NUM))
        return 0;
    if (((Uint32)sk->pending_command >
         (Uint32)C2837X_W5300_COMMAND_DUMMY_SEND) ||
        ((Uint32)sk->command_phase >
         (Uint32)C2837X_W5300_COMMAND_PHASE_WAIT_TARGET_STATE))
        return 0;
    if ((sk->udp_rx_datagram_active > 1u) ||
        (sk->udp_rx_residual_valid > 1u) ||
        ((sk->udp_rx_datagram_active == 0u) &&
         ((sk->udp_rx_data_remaining != 0u) ||
          (sk->udp_rx_residual_valid != 0u))))
        return 0;
    if ((sk->udp_rx_residual_valid != 0u) &&
        (sk->udp_rx_data_remaining == 0u))
        return 0;
    return (((sk->pending_command == C2837X_W5300_COMMAND_NONE) &&
             (sk->command_phase == C2837X_W5300_COMMAND_PHASE_IDLE)) ||
            ((sk->pending_command != C2837X_W5300_COMMAND_NONE) &&
             (sk->command_phase != C2837X_W5300_COMMAND_PHASE_IDLE))) ? 1 : 0;
}

static void clear_udp_rx_datagram(C2837xW5300Socket *sk)
{
    sk->udp_rx_datagram_active = 0u;
    sk->udp_rx_data_remaining = 0u;
    sk->udp_rx_residual_byte = 0u;
    sk->udp_rx_residual_valid = 0u;
}

static Uint16 udp_packet_info_u16(Uint16 dsp_word)
{
    return (Uint16)(((dsp_word & 0x00FFu) << 8) |
                    ((dsp_word >> 8) & 0x00FFu));
}

static void clear_socket_interrupts(Uint16 sn)
{
    c2837x_w5300_set_sn_ir(sn, 0x00FFu);
    c2837x_w5300_write16(IR, (Uint16)(1u << sn));
}

static void complete_pending(C2837xW5300Socket *sk)
{
    if (sk->pending_command == C2837X_W5300_COMMAND_RECV)
        clear_udp_rx_datagram(sk);
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

    case C2837X_W5300_COMMAND_NATIVE_UDP_OPEN:
        if (status == SOCK_UDP)
        {
            complete_pending(sk);
            return 1;
        }
        return c2837x_w5300_is_socket_status(status) ? 0 : -1;

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
        if ((sk->pending_command == C2837X_W5300_COMMAND_RECV) &&
            (sk->udp_rx_datagram_active != 0u) &&
            ((sk->udp_rx_data_remaining != 0u) ||
             (sk->udp_rx_residual_valid != 0u)))
            return -1;
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
    if (protocol == Sn_MR_UDP)
    {
        if (flags != 0u)
            return -1;
        return c2837x_w5300_socket_udp_open(sk, port);
    }
    if (!socket_is_valid(sk))
        return -1;
    if (sk->pending_command != C2837X_W5300_COMMAND_NONE)
        return advance_for(sk, C2837X_W5300_COMMAND_OPEN);

    clear_udp_rx_datagram(sk);
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

int16 c2837x_w5300_socket_udp_open(C2837xW5300Socket *sk, Uint16 port)
{
    if (!socket_is_valid(sk))
        return -1;
    if (sk->pending_command != C2837X_W5300_COMMAND_NONE)
        return advance_for(sk, C2837X_W5300_COMMAND_NATIVE_UDP_OPEN);

    clear_udp_rx_datagram(sk);
    clear_socket_interrupts(sk->sn);
    c2837x_w5300_write16(Sn_MR(sk->sn), Sn_MR_UDP);
    c2837x_w5300_write16(Sn_PORTR(sk->sn), port);
    return issue(sk, Sn_CR_OPEN, C2837X_W5300_COMMAND_NATIVE_UDP_OPEN);
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

int16 c2837x_w5300_socket_take_pending(C2837xW5300Socket *sk)
{
    int16 result;

    if (!socket_is_valid(sk))
        return -1;
    if (sk->pending_command == C2837X_W5300_COMMAND_NONE)
        return 1;
    if (sk->command_phase == C2837X_W5300_COMMAND_PHASE_WAIT_CR_CLEAR)
    {
        result = c2837x_w5300_poll_sn_cr(sk->sn);
        if (result <= 0)
            return result;
    }
    else if (sk->command_phase !=
             C2837X_W5300_COMMAND_PHASE_WAIT_TARGET_STATE)
        return -1;
    complete_pending(sk);
    return 1;
}

int16 c2837x_w5300_socket_check_close_erratum(
    C2837xW5300Socket *sk, Uint16 *needed)
{
    Uint16 mode;
    Uint32 free_octets;

    if (!socket_is_valid(sk) || (needed == 0) ||
        (sk->pending_command != C2837X_W5300_COMMAND_NONE) ||
        (sk->tx_mem_size == 0u))
        return -1;
    mode = c2837x_w5300_get_sn_mr(sk->sn);
    if (c2837x_w5300_get_sn_tx_fsr(sk->sn, &free_octets) < 0)
        return 0;
    *needed = ((((mode & C2837X_W5300_SN_MR_PROTOCOL_MASK) == Sn_MR_TCP) &&
                (free_octets != sk->tx_mem_size)) ? 1u : 0u);
    return 1;
}

int16 c2837x_w5300_socket_dummy_tx_ready(C2837xW5300Socket *sk)
{
    Uint32 free_octets;

    if (!socket_is_valid(sk) ||
        (sk->pending_command != C2837X_W5300_COMMAND_NONE))
        return -1;
    if (c2837x_w5300_get_sn_tx_fsr(sk->sn, &free_octets) < 0)
        return 0;
    return (free_octets >= 1u) ? 1 : 0;
}

int16 c2837x_w5300_socket_issue_udp_open(C2837xW5300Socket *sk, Uint16 port)
{
    if (!socket_is_valid(sk) ||
        (sk->pending_command != C2837X_W5300_COMMAND_NONE))
        return -1;
    clear_socket_interrupts(sk->sn);
    c2837x_w5300_write16(Sn_MR(sk->sn), Sn_MR_UDP);
    c2837x_w5300_write16(Sn_PORTR(sk->sn), port);
    return issue(sk, Sn_CR_OPEN, C2837X_W5300_COMMAND_UDP_OPEN);
}

int16 c2837x_w5300_socket_issue_dummy_send(C2837xW5300Socket *sk,
                                           Uint32 ip, Uint16 port)
{
    static const Uint16 dummy_word = 0u;

    if (!socket_is_valid(sk) ||
        (sk->pending_command != C2837X_W5300_COMMAND_NONE))
        return -1;
    c2837x_w5300_write16(Sn_DIPR(sk->sn), (Uint16)(ip >> 16));
    c2837x_w5300_write16(Sn_DIPR2(sk->sn), (Uint16)ip);
    c2837x_w5300_write16(Sn_DPORTR(sk->sn), port);
    c2837x_w5300_set_sn_ir(sk->sn, Sn_IR_SENDOK | Sn_IR_TIMEOUT);
    c2837x_w5300_write_stream(sk->sn, &dummy_word, 1u);
    c2837x_w5300_set_sn_tx_wrsr(sk->sn, 1u);
    return issue(sk, Sn_CR_SEND, C2837X_W5300_COMMAND_DUMMY_SEND);
}

int16 c2837x_w5300_socket_issue_close(C2837xW5300Socket *sk)
{
    if (!socket_is_valid(sk) ||
        (sk->pending_command != C2837X_W5300_COMMAND_NONE))
        return -1;

    clear_udp_rx_datagram(sk);
    clear_socket_interrupts(sk->sn);
    return issue(sk, Sn_CR_CLOSE, C2837X_W5300_COMMAND_CLOSE);
}

int16 c2837x_w5300_socket_poll_close_command(
    C2837xW5300Socket *sk, C2837xW5300PendingCommand expected)
{
    int16 result;

    if (!socket_is_valid(sk) || (sk->pending_command != expected) ||
        (sk->command_phase != C2837X_W5300_COMMAND_PHASE_WAIT_CR_CLEAR))
        return -1;
    result = c2837x_w5300_poll_sn_cr(sk->sn);
    if (result > 0)
        sk->command_phase = C2837X_W5300_COMMAND_PHASE_WAIT_TARGET_STATE;
    return result;
}

int16 c2837x_w5300_socket_complete_close_command(
    C2837xW5300Socket *sk, C2837xW5300PendingCommand expected)
{
    if (!socket_is_valid(sk) || (sk->pending_command != expected) ||
        (sk->command_phase != C2837X_W5300_COMMAND_PHASE_WAIT_TARGET_STATE))
        return -1;
    complete_pending(sk);
    return 1;
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
    Uint32 free_size;
    Uint32 chunk;

    wire_byte_count &= ~1u;
    if (wire_byte_count == 0u)
        return 0;
    if ((sk == 0) || (data_words == 0))
        return -1;
    if (sk->pending_command == C2837X_W5300_COMMAND_NONE)
    {
        if (sk->command_phase != C2837X_W5300_COMMAND_PHASE_IDLE)
            return -1;
    }
    else
    {
        if (sk->command_phase == C2837X_W5300_COMMAND_PHASE_IDLE)
            return -1;
        return 0;
    }

    status = c2837x_w5300_get_sn_ssr(sk->sn);
    if ((status != SOCK_ESTABLISHED) && (status != SOCK_CLOSE_WAIT))
        return 0;
    if (c2837x_w5300_get_sn_tx_fsr(sk->sn, &free_size) < 0)
        return -1;

    chunk = wire_byte_count;
    if (chunk > free_size) chunk = free_size;
    if (chunk > sk->tx_mem_size) chunk = sk->tx_mem_size;
    chunk &= ~1u;
    if (chunk == 0u)
        return 0;

    c2837x_w5300_set_sn_ir(sk->sn, Sn_IR_SENDOK | Sn_IR_TIMEOUT);
    c2837x_w5300_write_stream(sk->sn, data_words, chunk);
    c2837x_w5300_set_sn_tx_wrsr(sk->sn, chunk);
    if (issue(sk, Sn_CR_SEND, C2837X_W5300_COMMAND_SEND) < 0)
        return -1;
    return (int32)chunk;
}

#if __TI_COMPILER_VERSION__ >= 15009000
    #pragma CODE_SECTION(c2837x_w5300_socket_udp_send, ".TI.ramfunc");
#else
    #pragma CODE_SECTION(c2837x_w5300_socket_udp_send, "ramfuncs");
#endif
int32 c2837x_w5300_socket_udp_send(C2837xW5300Socket *sk,
                                   Uint32 destination_ip,
                                   Uint16 destination_port,
                                   const Uint16 *data_words,
                                   Uint32 wire_byte_count)
{
    Uint16 status;
    Uint32 free_size;

    if ((sk == 0) || !socket_is_valid(sk))
        return -1;

    /* A pending UDP SEND is progressed once; its arguments are ignored. */
    if (sk->pending_command != C2837X_W5300_COMMAND_NONE)
    {
        if (sk->command_phase == C2837X_W5300_COMMAND_PHASE_IDLE)
            return -1;
        if (sk->pending_command == C2837X_W5300_COMMAND_SEND)
        {
            if (c2837x_w5300_socket_advance_send_command(sk) < 0)
                return -1;
        }
        return 0;
    }
    if (sk->command_phase != C2837X_W5300_COMMAND_PHASE_IDLE)
        return -1;
    if (wire_byte_count == 0u)
        return 0;
    if ((wire_byte_count & 1u) != 0u)
        return -1;
    if (data_words == 0)
        return -1;

    status = c2837x_w5300_get_sn_ssr(sk->sn);
    if (status != SOCK_UDP)
        return 0;
    if (c2837x_w5300_get_sn_tx_fsr(sk->sn, &free_size) < 0)
        return -1;
    if ((free_size < wire_byte_count) ||
        (sk->tx_mem_size < wire_byte_count))
        return 0;

    c2837x_w5300_write16(Sn_DIPR(sk->sn),
                         (Uint16)(destination_ip >> 16));
    c2837x_w5300_write16(Sn_DIPR2(sk->sn), (Uint16)destination_ip);
    c2837x_w5300_write16(Sn_DPORTR(sk->sn), destination_port);
    c2837x_w5300_set_sn_ir(sk->sn, Sn_IR_SENDOK | Sn_IR_TIMEOUT);
    c2837x_w5300_write_stream(sk->sn, data_words, wire_byte_count);
    c2837x_w5300_set_sn_tx_wrsr(sk->sn, wire_byte_count);
    if (issue(sk, Sn_CR_SEND, C2837X_W5300_COMMAND_SEND) < 0)
        return -1;
    return (int32)wire_byte_count;
}

int16 c2837x_w5300_socket_advance_send_command(C2837xW5300Socket *sk)
{
    if (sk == 0)
        return -1;
    if (sk->pending_command == C2837X_W5300_COMMAND_NONE)
        return (sk->command_phase == C2837X_W5300_COMMAND_PHASE_IDLE) ?
            1 : -1;
    if ((sk->pending_command != C2837X_W5300_COMMAND_SEND) ||
        (sk->command_phase != C2837X_W5300_COMMAND_PHASE_WAIT_CR_CLEAR))
        return -1;
    return advance_pending(sk);
}

int16 c2837x_w5300_socket_advance_recv_command(C2837xW5300Socket *sk)
{
    if (sk == 0)
        return -1;
    if (sk->pending_command == C2837X_W5300_COMMAND_NONE)
        return (sk->command_phase == C2837X_W5300_COMMAND_PHASE_IDLE) ?
            1 : -1;
    if ((sk->pending_command != C2837X_W5300_COMMAND_RECV) ||
        (sk->command_phase != C2837X_W5300_COMMAND_PHASE_WAIT_CR_CLEAR))
        return -1;
    return advance_pending(sk);
}

int16 c2837x_w5300_socket_udp_rx_available(C2837xW5300Socket *sk)
{
    Uint16 status;
    Uint32 rx_size;

    if (!socket_is_valid(sk))
        return -1;
    if (sk->pending_command != C2837X_W5300_COMMAND_NONE)
        return 0;

    status = c2837x_w5300_get_sn_ssr(sk->sn);
    if (status != SOCK_UDP)
        return 0;
    if (sk->udp_rx_datagram_active != 0u)
        return 1;
    if (c2837x_w5300_get_sn_rx_rsr(sk->sn, &rx_size) < 0)
        return -1;
    return (rx_size != 0u) ? 1 : 0;
}

int16 c2837x_w5300_socket_udp_read_packet_info(
    C2837xW5300Socket *sk, C2837xW5300UdpPacketInfo *packet_info)
{
    Uint16 packet_info_words[4];
    Uint16 status;
    Uint32 rx_size;

    if (!socket_is_valid(sk) || (packet_info == 0))
        return -1;
    if (sk->pending_command != C2837X_W5300_COMMAND_NONE)
        return 0;
    if (sk->udp_rx_datagram_active != 0u)
        return -1;

    status = c2837x_w5300_get_sn_ssr(sk->sn);
    if (status != SOCK_UDP)
        return 0;
    if (c2837x_w5300_get_sn_rx_rsr(sk->sn, &rx_size) < 0)
        return -1;
    if (rx_size < C2837X_W5300_UDP_PACKET_INFO_BYTES)
        return 0;

    c2837x_w5300_read_stream(sk->sn, packet_info_words,
                             C2837X_W5300_UDP_PACKET_INFO_BYTES);

    /* HAL returns low-byte-first DSP words; PACKET-INFO fields are network order. */
    packet_info->source_ip = ((Uint32)udp_packet_info_u16(packet_info_words[0])
                              << 16) |
                             (Uint32)udp_packet_info_u16(packet_info_words[1]);
    packet_info->source_port = udp_packet_info_u16(packet_info_words[2]);
    packet_info->data_size = udp_packet_info_u16(packet_info_words[3]);
    sk->udp_rx_datagram_active = 1u;
    sk->udp_rx_data_remaining = (Uint32)packet_info->data_size;
    return 1;
}

int32 c2837x_w5300_socket_udp_read_data(C2837xW5300Socket *sk,
                                        Uint16 *data_words,
                                        Uint32 wire_capacity_bytes)
{
    Uint16 status;
    Uint16 fifo_word;
    Uint16 fifo_byte;
    Uint32 remaining_before;
    Uint32 copy_size;
    Uint32 fifo_byte_count;
    Uint32 fifo_word_count;
    Uint32 word_index;
    Uint32 byte_index;
    Uint32 output_index;

    if (wire_capacity_bytes == 0u)
        return 0;
    if ((sk == 0) || (data_words == 0))
        return -1;
    if (!socket_is_valid(sk))
        return -1;
    if (sk->pending_command != C2837X_W5300_COMMAND_NONE)
        return 0;
    if ((sk->udp_rx_datagram_active == 0u) ||
        (sk->udp_rx_data_remaining == 0u))
        return 0;

    status = c2837x_w5300_get_sn_ssr(sk->sn);
    if (status != SOCK_UDP)
        return 0;

    remaining_before = sk->udp_rx_data_remaining;
    copy_size = wire_capacity_bytes;
    if (copy_size > remaining_before)
        copy_size = remaining_before;

    /*
     * A residual byte is already the first byte of this read. Keep the
     * caller's DSP-native byte packing while filling the rest from complete
     * FIFO words. The word read below deliberately uses the HAL stream helper
     * so both FIFO-swap modes retain their existing mapping.
     */
    output_index = 0u;
    if (sk->udp_rx_residual_valid != 0u)
    {
        data_words[0] = (Uint16)(sk->udp_rx_residual_byte & 0x00FFu);
        sk->udp_rx_residual_byte = 0u;
        sk->udp_rx_residual_valid = 0u;
        output_index = 1u;
    }

    fifo_byte_count = copy_size - output_index;
    fifo_word_count = (fifo_byte_count + 1u) >> 1;
    for (word_index = 0u; word_index < fifo_word_count; word_index++)
    {
        fifo_word = 0u;
        c2837x_w5300_read_stream(sk->sn, &fifo_word, 2u);
        for (byte_index = 0u; byte_index < 2u; byte_index++)
        {
            fifo_byte = (byte_index == 0u) ?
                (Uint16)(fifo_word & 0x00FFu) :
                (Uint16)((fifo_word >> 8) & 0x00FFu);
            if (fifo_byte_count != 0u)
            {
                if ((output_index & 1u) == 0u)
                    data_words[output_index >> 1] = fifo_byte;
                else
                    data_words[output_index >> 1] =
                        (Uint16)(data_words[output_index >> 1] |
                                 (Uint16)(fifo_byte << 8));
                output_index++;
                fifo_byte_count--;
            }
            else if ((copy_size < remaining_before) &&
                     (sk->udp_rx_residual_valid == 0u))
            {
                /* The extra byte is still current-Datagram DATA, not padding. */
                sk->udp_rx_residual_byte = fifo_byte;
                sk->udp_rx_residual_valid = 1u;
            }
        }
    }

    sk->udp_rx_data_remaining -= copy_size;
    return (int32)copy_size;
}

int32 c2837x_w5300_socket_udp_drop_data(C2837xW5300Socket *sk)
{
    Uint16 status;
    Uint16 discard_word;
    Uint32 dropped_size;
    Uint32 physical_size;
    Uint32 word_index;
    Uint32 word_count;

    if (!socket_is_valid(sk))
        return -1;
    if (sk->pending_command != C2837X_W5300_COMMAND_NONE)
        return 0;
    if (sk->udp_rx_datagram_active == 0u)
        return 0;

    status = c2837x_w5300_get_sn_ssr(sk->sn);
    if (status != SOCK_UDP)
        return 0;

    dropped_size = sk->udp_rx_data_remaining;
    physical_size = dropped_size;
    if (sk->udp_rx_residual_valid != 0u)
    {
        /* This byte was already read from the FIFO and is part of this DATA. */
        physical_size--;
        sk->udp_rx_residual_byte = 0u;
        sk->udp_rx_residual_valid = 0u;
    }
    word_count = (physical_size + 1u) >> 1;
    for (word_index = 0u; word_index < word_count; word_index++)
    {
        /* The count is known; each read consumes one current-Datagram word. */
        discard_word = 0u;
        c2837x_w5300_read_stream(sk->sn, &discard_word, 2u);
    }
    sk->udp_rx_data_remaining = 0u;
    return (int32)dropped_size;
}

int16 c2837x_w5300_socket_udp_commit_recv(C2837xW5300Socket *sk)
{
    Uint16 status;

    if (!socket_is_valid(sk) ||
        (sk->udp_rx_datagram_active == 0u) ||
        (sk->udp_rx_data_remaining != 0u) ||
        (sk->udp_rx_residual_valid != 0u))
        return -1;
    if (sk->pending_command == C2837X_W5300_COMMAND_RECV)
        return c2837x_w5300_socket_advance_recv_command(sk);
    if (sk->pending_command != C2837X_W5300_COMMAND_NONE)
        return -1;

    status = c2837x_w5300_get_sn_ssr(sk->sn);
    if (status != SOCK_UDP)
        return -1;
    return issue(sk, Sn_CR_RECV, C2837X_W5300_COMMAND_RECV);
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
    if ((sk == 0) || (data_words == 0))
        return -1;
    if (sk->pending_command == C2837X_W5300_COMMAND_NONE)
    {
        if (sk->command_phase != C2837X_W5300_COMMAND_PHASE_IDLE)
            return -1;
    }
    else
    {
        if (sk->command_phase == C2837X_W5300_COMMAND_PHASE_IDLE)
            return -1;
        return (advance_pending(sk) < 0) ? -1 : 0;
    }

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
