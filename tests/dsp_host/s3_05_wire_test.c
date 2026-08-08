#include "axis_x_config.h"
#include "axis_x_algorithm.h"
#include <stdint.h>
#include <stdio.h>
#include <string.h>

extern AxisX_InputData c2837x_block_axis_x_input_object;
extern AxisX_OutputData c2837x_block_axis_x_output_object;
extern void c2837x_block_axis_x_decode_input(
    void *, const Uint16 *);
extern void c2837x_block_axis_x_encode_output(
    const void *, Uint16 *);

static const Uint16 golden[] = {
    0xfffeu, 0x1234u,
    0xfffeu, 0xffffu, 0xcdefu, 0x89abu,
    0x5678u, 0x1234u,
    0x0000u, 0x0000u, 0x0000u, 0x8000u,
    0x0000u, 0x7f80u, 0x0000u, 0xff80u,
    0x2345u, 0x7fc1u, 0x0001u, 0x0000u,
    0x0000u, 0x0000u, 0x0000u, 0x0000u,
    0x0000u, 0x0000u, 0x0000u, 0x8000u,
    0x0000u, 0x0000u, 0x0000u, 0x7ff0u,
    0x0000u, 0x0000u, 0x0000u, 0xfff0u,
    0x2345u, 0x0001u, 0x0000u, 0x7ff8u,
    0x0001u, 0x0000u, 0x0000u, 0x0000u
};

static int copy_output(void)
{
    Uint16 i;
    AxisX_InputData *input = &c2837x_block_axis_x_input_object;
    AxisX_OutputData *output = &c2837x_block_axis_x_output_object;
    output->o_i16v = input->i_i16v;
    output->o_u16v = input->i_u16v;
    output->o_u32v = input->i_u32v;
    for (i = 0u; i < 2u; ++i) output->o_i32v[i] = input->i_i32v[i];
    for (i = 0u; i < 6u; ++i) output->o_f32v[i] = input->i_f32v[i];
    for (i = 0u; i < 6u; ++i) output->o_f64v[i] = input->i_f64v[i];
    return 0;
}

int main(void)
{
    Uint16 frame[48];
    Uint16 unchanged[48];
    unsigned index;

    memset(&c2837x_block_axis_x_input_object, 0x5a,
           sizeof(c2837x_block_axis_x_input_object));
    c2837x_block_axis_x_decode_input(
        &c2837x_block_axis_x_input_object, golden);
    copy_output();

    for (index = 0u; index < 48u; ++index) frame[index] = 0xa55au;
    memcpy(unchanged, frame, sizeof(frame));
    c2837x_block_axis_x_encode_output(
        &c2837x_block_axis_x_output_object, &frame[2]);
    if (frame[0] != unchanged[0] || frame[1] != unchanged[1] ||
        frame[46] != unchanged[46] || frame[47] != unchanged[47] ||
        memcmp(&frame[2], golden, sizeof(golden)) != 0 ||
        frame[0] != 0xa55au || frame[1] != 0xa55au ||
        frame[46] != 0xa55au || frame[47] != 0xa55au)
        return 1;

    puts("s3_05_wire=ok");
    return 0;
}
