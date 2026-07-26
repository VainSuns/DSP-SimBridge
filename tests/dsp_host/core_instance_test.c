#include <assert.h>
#include "c2837x_block_internal.h"
#include "c2837x_block_protocol.h"

typedef struct
{
    Uint16 id;
    C2837xBlock_IoConnectionState state;
    Uint16 init_calls;
    Uint16 open_calls;
    Uint16 listen_calls;
    Uint16 receive_calls;
    Uint16 send_calls;
    Uint16 close_calls;
} FakeChannel;

static C2837xBlock first_instance;
static C2837xBlock second_instance;
static FakeChannel first_channel = {1u, C2837X_IODEVICE_CONNECTION_CLOSED,
                                     0u, 0u, 0u, 0u, 0u, 0u};
static FakeChannel second_channel = {2u, C2837X_IODEVICE_CONNECTION_CLOSED,
                                      0u, 0u, 0u, 0u, 0u, 0u};

static void fake_init(void *ref)
{
    FakeChannel *channel = (FakeChannel *)ref;
    channel->state = C2837X_IODEVICE_CONNECTION_CLOSED;
    channel->open_calls = 0u;
    channel->listen_calls = 0u;
    channel->receive_calls = 0u;
    channel->send_calls = 0u;
    channel->close_calls = 0u;
    channel->init_calls++;
}
static int16 fake_open(void *ref)
{
    FakeChannel *channel = (FakeChannel *)ref;
    channel->open_calls++;
    return 0;
}
static int16 fake_listen(void *ref)
{
    FakeChannel *channel = (FakeChannel *)ref;
    channel->listen_calls++;
    return 0;
}
static C2837xBlock_IoConnectionState fake_state(void *ref)
{
    return ((FakeChannel *)ref)->state;
}
static int32 fake_receive(void *ref, Uint16 *data, Uint32 capacity)
{
    FakeChannel *channel = (FakeChannel *)ref;
    (void)data;
    (void)capacity;
    channel->receive_calls++;
    return 0;
}
static int32 fake_send(void *ref, const Uint16 *data, Uint32 count)
{
    FakeChannel *channel = (FakeChannel *)ref;
    (void)data;
    channel->send_calls++;
    return (int32)count;
}
static int16 fake_close(void *ref)
{
    FakeChannel *channel = (FakeChannel *)ref;
    channel->close_calls++;
    return 1;
}

static const C2837xBlock_IoDeviceOps fake_ops = {
    fake_init, fake_open, fake_listen, fake_state,
    fake_receive, fake_send, fake_close
};

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
    C2837xBlock_Init(NULL);
    C2837xBlock_Run(NULL);
    assert(C2837xBlock_GetLastError(NULL) ==
           C2837X_BLOCK_ERROR_INVALID_ARGUMENT);

    c2837x_block_bind_iodevice(&first_instance, &fake_ops, &first_channel);
    c2837x_block_bind_iodevice(&second_instance, &fake_ops, &second_channel);
    C2837xBlock_Init(&first_instance);
    C2837xBlock_Init(&second_instance);
    C2837xBlock_Init(&first_instance);

    assert(first_instance.iodevice_channel == &first_channel);
    assert(second_instance.iodevice_channel == &second_channel);
    assert(first_channel.id == 1u && second_channel.id == 2u);
    assert(first_channel.init_calls == 2u && second_channel.init_calls == 1u);

    first_channel.state = C2837X_IODEVICE_CONNECTION_OPEN;
    C2837xBlock_Run(&first_instance);
    assert(first_channel.listen_calls == 1u);
    assert(second_channel.listen_calls == 0u);

    second_channel.state = C2837X_IODEVICE_CONNECTION_CLOSED;
    C2837xBlock_Run(&second_instance);
    assert(second_channel.open_calls == 1u);
    assert(first_channel.open_calls == 0u);

    first_channel.state = C2837X_IODEVICE_CONNECTION_CONNECTED;
    C2837xBlock_Run(&first_instance);
    assert(first_channel.receive_calls == 1u);
    assert(second_channel.receive_calls == 0u);

    first_instance.first_connected = 1u;
    first_instance.state = C2837X_STATE_SEND;
    first_instance.tx_total_bytes = 2u;
    first_instance.tx_sent_bytes = 0u;
    C2837xBlock_Run(&first_instance);
    assert(first_channel.send_calls == 1u);
    assert(first_channel.close_calls == 1u);
    assert(second_channel.send_calls == 0u && second_channel.close_calls == 0u);

    second_channel.state = C2837X_IODEVICE_CONNECTION_PEER_CLOSED;
    C2837xBlock_Run(&second_instance);
    assert(second_channel.close_calls == 1u);
    assert(C2837xBlock_GetLastError(&second_instance) ==
           C2837X_BLOCK_ERROR_DISCONNECTED);
    return 0;
}
