#include <assert.h>
#include "c2837x_block_internal.h"
#include "c2837x_block_protocol.h"
#include "c2837x_w5300_hal.h"

static C2837xBlock first_instance;
static C2837xBlock second_instance;
static Uint16 socket_status = SOCK_ESTABLISHED;
static int16 memory_result;

Uint16 c2837x_w5300_fifo_swap;

void c2837x_w5300_init(void) {}
void c2837x_w5300_write16(Uint32 address, Uint16 data) {(void)address; (void)data;}
Uint16 c2837x_w5300_read16(Uint32 address) {(void)address; return socket_status;}
int16 c2837x_w5300_configure_socket_memory(Uint16 sn, Uint16 tx_kb,
    Uint16 rx_kb, Uint32* tx_bytes, Uint32* rx_bytes)
{
    (void)sn;
    *tx_bytes = (Uint32)tx_kb * 1024u;
    *rx_bytes = (Uint32)rx_kb * 1024u;
    return memory_result;
}

int16 c2837x_w5300_socket_open(C2837xW5300Socket* socket, Uint16 protocol,
    Uint16 port, Uint16 flags)
{
    (void)socket; (void)protocol; (void)port; (void)flags; return 0;
}
int16 c2837x_w5300_socket_close(C2837xW5300Socket* socket) {(void)socket; return 0;}
int16 c2837x_w5300_socket_listen(C2837xW5300Socket* socket) {(void)socket; return 0;}
int32 c2837x_w5300_socket_send(C2837xW5300Socket* socket,
    const Uint16* data, Uint32 count)
{
    (void)socket; (void)data; (void)count; return 0;
}
void c2837x_w5300_socket_disconnect(C2837xW5300Socket* socket) {(void)socket;}
int32 c2837x_w5300_socket_recv(C2837xW5300Socket* socket,
    Uint16* data, Uint32 count)
{
    (void)socket; (void)data; (void)count; return 0;
}

int16 c2837x_block_parse_header(const Uint16* words, Uint16* type, Uint16* length)
{
    (void)words; *type = 0; *length = 0; return 0;
}
Uint32 c2837x_block_build_response(Uint16* words, Uint16 error)
{
    (void)words; (void)error; return 0;
}
Uint32 c2837x_block_build_frame(Uint16* frame, Uint16 type,
    Uint16 length, const Uint16* payload)
{
    (void)frame; (void)type; (void)length; (void)payload; return 0;
}
void c2837x_block_unpack_input_payload(const uint16_t* words, uint32_t* step)
{
    (void)words; *step = 0;
}
void c2837x_block_pack_output_payload(uint16_t* words, uint32_t step)
{
    (void)words; (void)step;
}
int C2837xBlock_OnSimStart(void) {return 0;}
int C2837xBlock_OnStep(void) {return 0;}
void C2837xBlock_OnSimStop(void) {}

int main(void)
{
    assert(C2837xBlock_PlatformInit() == C2837X_BLOCK_PLATFORM_OK);
    memory_result = -1;
    assert(C2837xBlock_PlatformInit() ==
           C2837X_BLOCK_PLATFORM_ERROR_W5300_MEMORY);

    C2837xBlock_Init(NULL);
    C2837xBlock_Run(NULL);
    assert(C2837xBlock_GetLastError(NULL) ==
           C2837X_BLOCK_ERROR_INVALID_ARGUMENT);

    C2837xBlock_Init(&first_instance);
    C2837xBlock_Init(&second_instance);
    assert(C2837xBlock_GetLastError(&first_instance) == C2837X_BLOCK_ERROR_NONE);
    assert(C2837xBlock_GetLastError(&second_instance) == C2837X_BLOCK_ERROR_NONE);

    first_instance.expected_step_index = 7u;
    first_instance.last_error = C2837X_BLOCK_ERROR_PROTOCOL;
    assert(second_instance.expected_step_index == 0u);
    assert(C2837xBlock_GetLastError(&second_instance) == C2837X_BLOCK_ERROR_NONE);

    C2837xBlock_Run(&first_instance);
    assert(first_instance.first_connected == 1u);
    assert(first_instance.tick_counter == 1u);
    assert(second_instance.first_connected == 0u);
    assert(second_instance.tick_counter == 0u);
    return 0;
}
