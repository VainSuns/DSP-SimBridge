#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "axis_alpha_sfun.h"
#include "axis_beta_sfun.h"

#ifdef INJECT_DECODE_FAILURE
static int injected_decode_failure(const uint8_t *payload,
    uint16_t payload_length, uint32_t expected_step,
    AxisAlphaSfunOutputTemp *temporary, AxisAlphaPcError *error);
#define axis_alpha_sfun_decode_output_payload injected_decode_failure
#endif
#include "axis_alpha_sfun.c"
#ifdef INJECT_DECODE_FAILURE
#undef axis_alpha_sfun_decode_output_payload
static int injected_decode_failure(const uint8_t *payload,
    uint16_t payload_length, uint32_t expected_step,
    AxisAlphaSfunOutputTemp *temporary, AxisAlphaPcError *error)
{
    if (axis_alpha_sfun_decode_output_payload(payload, payload_length,
            expected_step, temporary, error) != 0) return -1;
    axis_alpha_pc_error_reset(error, "decode_output");
    error->kind = AXIS_ALPHA_PC_ERROR_FIELD_DECODE;
    return -1;
}
#endif

typedef struct
{
    int16_t i16[2];
    uint16_t u16[1];
    int32_t i32[1];
    uint32_t u32[1];
    float f32[1];
    double f64[2];
} Inputs;

typedef struct
{
    int16_t i16[1];
    uint16_t u16[1];
    int32_t i32[1];
    uint32_t u32[1];
    float f32[2];
    double f64[1];
} Outputs;

static int contains(const char *text, const char *token)
{
    return text != NULL && strstr(text, token) != NULL;
}

static void initialize_inputs(Inputs *values)
{
    const uint32_t negative_zero = UINT32_C(0x80000000);
    const uint64_t nan_bits = UINT64_C(0x7ff80000000000a5);
    const uint64_t one_bits = UINT64_C(0x3ff0000000000000);
    values->i16[0] = -2;
    values->i16[1] = 0x1234;
    values->u16[0] = UINT16_C(0xfedc);
    values->i32[0] = -123456789;
    values->u32[0] = UINT32_C(0x89abcdef);
    memcpy(&values->f32[0], &negative_zero, sizeof(negative_zero));
    memcpy(&values->f64[0], &nan_bits, sizeof(nan_bits));
    memcpy(&values->f64[1], &one_bits, sizeof(one_bits));
}

static void connect_ports(SimStruct *sim, Inputs *inputs, Outputs *outputs)
{
    sim->inputs[0] = inputs->i16;
    sim->inputs[1] = inputs->u16;
    sim->inputs[2] = inputs->i32;
    sim->inputs[3] = inputs->u32;
    sim->inputs[4] = inputs->f32;
    sim->inputs[5] = inputs->f64;
    sim->outputs[0] = outputs->i16;
    sim->outputs[1] = outputs->u16;
    sim->outputs[2] = outputs->i32;
    sim->outputs[3] = outputs->u32;
    sim->outputs[4] = outputs->f32;
    sim->outputs[5] = outputs->f64;
}

static int outputs_match(const Outputs *values)
{
    uint32_t f0;
    uint32_t f1;
    uint64_t d0;
    memcpy(&f0, &values->f32[0], sizeof(f0));
    memcpy(&f1, &values->f32[1], sizeof(f1));
    memcpy(&d0, &values->f64[0], sizeof(d0));
    return values->i16[0] == -32767 && values->u16[0] == UINT16_C(0xabcd) &&
        values->i32[0] == -2 && values->u32[0] == UINT32_C(0xfedcba98) &&
        f0 == UINT32_C(0x80000000) && f1 == UINT32_C(1) &&
        d0 == UINT64_C(0x7ff80000000000a5);
}

int main(int argc, char **argv)
{
    SimStruct sim = {0};
    Inputs inputs;
    Outputs outputs;
    Outputs sentinels;
    Outputs beta_outputs;
    Outputs beta_snapshot;
    AxisBetaSfunOutputTemp beta_temporary;
    AxisBetaSfunContext beta_context = {0};
    AxisBetaSfunContext beta_context_snapshot;
    AxisBetaPcError beta_error;
    SimStruct beta_sim = {0};
    AxisAlphaSfunContext *context;
    uint32_t initial_step = 0u;
    int success;
    if (argc != 2) return 2;
    initialize_inputs(&inputs);
    memset(&outputs, 0xa5, sizeof(outputs));
    sentinels = outputs;
    connect_ports(&sim, &inputs, &outputs);
    memset(&beta_outputs, 0x5a, sizeof(beta_outputs));
    memset(&beta_temporary, 0x3c, sizeof(beta_temporary));
    connect_ports(&beta_sim, &inputs, &beta_outputs);
    beta_context.step_index = 77u;
    beta_context.session_started = 1;
    if (axis_beta_sfun_commit_output_ports(&beta_sim, &beta_temporary,
            &beta_error) != 0) return 3;
    beta_snapshot = beta_outputs;
    beta_context_snapshot = beta_context;
    mdlInitializeSizes(&sim);
    mdlStart(&sim);
    context = (AxisAlphaSfunContext *)sim.pwork;
    if (context == NULL || sim.error_status != NULL) return 3;
    if (strcmp(argv[1], "wrap") == 0) {
        context->step_index = UINT32_MAX;
        initial_step = UINT32_MAX;
    }
    if (strcmp(argv[1], "port_failure") == 0) sim.outputs[1] = NULL;
    mdlOutputs(&sim, 0);
    if (memcmp(&beta_outputs, &beta_snapshot, sizeof(beta_outputs)) != 0 ||
            memcmp(&beta_context, &beta_context_snapshot,
                sizeof(beta_context)) != 0) return 14;
    success = strcmp(argv[1], "success") == 0 || strcmp(argv[1], "wrap") == 0;
    if (success) {
        uint32_t expected_step = strcmp(argv[1], "success") == 0 ? 1u : 0u;
        if (sim.error_status != NULL || !outputs_match(&outputs) ||
                context->step_index != expected_step ||
                context->session_started != 1 ||
                !axis_alpha_pc_socket_is_valid(&context->socket)) return 4;
        if (strcmp(argv[1], "success") == 0) {
            memset(&outputs, 0xa5, sizeof(outputs));
            mdlOutputs(&sim, 0);
            if (sim.error_status != NULL || !outputs_match(&outputs) ||
                    context->step_index != 2u) return 5;
        }
    } else {
        if (memcmp(&outputs, &sentinels, sizeof(outputs)) != 0 ||
                context->step_index != initial_step || context->session_started != 0 ||
                axis_alpha_pc_socket_is_valid(&context->socket) ||
                sim.error_status != sim.dwork ||
                !contains(sim.error_status, "instance=axis_alpha") ||
                !contains(sim.error_status, "step_index=0")) return 6;
        if (strcmp(argv[1], "response_error") == 0 &&
                !contains(sim.error_status, "dsp_error=7")) return 7;
        if (strcmp(argv[1], "response_zero") == 0 &&
                !contains(sim.error_status, "category=message_type")) return 8;
        if (strcmp(argv[1], "wrong_step") == 0 &&
                (!contains(sim.error_status, "expected_step=0") ||
                 !contains(sim.error_status, "actual_step=1"))) return 9;
        if ((strcmp(argv[1], "short") == 0 || strcmp(argv[1], "long") == 0 ||
                strcmp(argv[1], "odd") == 0) &&
                (!contains(sim.error_status, "category=payload_length") ||
                 !contains(sim.error_status, "expected_length=32"))) return 10;
        if (strcmp(argv[1], "decode_failure") == 0 &&
                !contains(sim.error_status, "category=field_decode")) return 11;
        if (strcmp(argv[1], "port_failure") == 0 &&
                !contains(sim.error_status, "category=port_access")) return 12;
    }
    mdlTerminate(&sim);
    if (sim.pwork != NULL) return 13;
    printf("PASS %s\n", argv[1]);
    return 0;
}
