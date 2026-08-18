#include "simstruc.h"
#include "c2837x_block_pc_serial.h"
#include "sci_sfun_host_serial_test.h"

#include <stdio.h>
#include <string.h>

#include "axis_alpha_sfun.c"
#include "axis_alpha_sfun_io.c"
#include "axis_alpha_protocol.c"

static int passed;
static int failed;

static void check(int condition, const char *name)
{
    if (condition) {
        ++passed;
        printf("PASS %s\n", name);
    } else {
        ++failed;
        printf("FAIL %s\n", name);
    }
}

static int has_text(const char *text, const char *part)
{
    return text != NULL && part != NULL && strstr(text, part) != NULL;
}

static int ordered(const char *text, const char *first, const char *second)
{
    const char *first_position = strstr(text, first);
    const char *second_position = strstr(text, second);
    return first_position != NULL && second_position != NULL &&
        first_position < second_position;
}

static int count_text(const char *text, const char *part)
{
    int count = 0;
    size_t part_length = strlen(part);
    while (text != NULL && part_length > 0u &&
            (text = strstr(text, part)) != NULL) {
        ++count;
        text += part_length;
    }
    return count;
}

static void prepare_sim(SimStruct *S, mxArray *parameter,
    const uint16_t *input, uint16_t *output)
{
    memset(S, 0, sizeof(*S));
    memset(parameter, 0, sizeof(*parameter));
    parameter->value = 7.0;
    parameter->elements = 1u;
    parameter->numeric = 1;
    S->params[0] = parameter;
    S->params_count = 1;
    S->inputs[0] = input;
    S->outputs[0] = output;
}

static int initialize_and_start(SimStruct *S, mxArray *parameter,
    const uint16_t *input, uint16_t *output)
{
    prepare_sim(S, parameter, input, output);
    mdlInitializeSizes(S);
    mdlCheckParameters(S);
    mdlInitializeSampleTimes(S);
    if (S->error_status != NULL) return -1;
    mdlStart(S);
    return S->error_status == NULL && S->pwork != NULL ? 0 : -1;
}

static void verify_error_text(const char *name, const SimStruct *S,
    const char *expected_stage, const char *expected_category,
    const char *extra)
{
    const char *text = S->error_status;
    char label[128];
    (void)snprintf(label, sizeof(label), "%s_has_instance_com_baud", name);
    check(has_text(text, "instance=axis_alpha COM=7 baud=115200"), label);
    (void)snprintf(label, sizeof(label), "%s_has_stage_category", name);
    check(has_text(text, expected_stage) && has_text(text, expected_category),
        label);
    if (extra != NULL) {
        (void)snprintf(label, sizeof(label), "%s_has_transient_details", name);
        check(has_text(text, extra), label);
    }
    printf("ERROR_TEXT %s %s\n", name, text != NULL ? text : "<null>");
}

static void run_success_lifecycle(void)
{
    SimStruct S;
    mxArray parameter;
    uint16_t input = 0x1234u;
    uint16_t output = 0xaaaau;
    AxisAlphaSfunContext *context;

    sci_host_mock_reset(SCI_HOST_MOCK_NORMAL);
    check(initialize_and_start(&S, &parameter, &input, &output) == 0,
        "start_success");
    context = (AxisAlphaSfunContext *)S.pwork;
    check(context != NULL && context->step_index == 0u &&
            context->session_started != 0, "start_session_step_zero");
    check(sci_host_mock_open_com_number() == 7u &&
            sci_host_mock_configured_baud() == 115200u &&
            sci_host_mock_purge_flags() ==
                (C2837X_PC_SERIAL_PURGE_RX | C2837X_PC_SERIAL_PURGE_TX),
        "start_requested_baud_and_purge");
    check(count_text(sci_host_mock_log(), "purge(") == 1 &&
            ordered(sci_host_mock_log(), "init;", "open(7);") &&
            ordered(sci_host_mock_log(), "open(7);", "configure(115200);") &&
            ordered(sci_host_mock_log(), "configure(115200);", "purge(3);") &&
            ordered(sci_host_mock_log(), "purge(3);", "sim_start_send(100);") &&
            ordered(sci_host_mock_log(), "sim_start_send(100);", "response_header;") &&
            ordered(sci_host_mock_log(), "response_header;", "response_payload;"),
        "start_call_order");

    mdlOutputs(&S, 0);
    context = (AxisAlphaSfunContext *)S.pwork;
    check(S.error_status == NULL && output == 0xbeefu && context != NULL &&
            context->step_index == 1u && context->session_started != 0,
        "step_success_commit_and_increment");
    check(ordered(sci_host_mock_log(), "input_send(100);", "output_header;") &&
            ordered(sci_host_mock_log(), "output_header;", "output_payload;") &&
            sci_host_mock_same_receive_deadline() != 0 &&
            sci_host_mock_same_send_deadline() != 0,
        "step_call_order_and_deadlines");

    mdlTerminate(&S);
    check(S.pwork == NULL && S.error_status == NULL &&
            sci_host_mock_sim_stop_timeout() == TERMINATE_TIMEOUT_MS &&
            ordered(sci_host_mock_log(), "sim_stop_send(50);", "close;"),
        "terminate_best_effort_and_cleanup");
}

static void run_start_failure(sci_host_mock_mode_t mode, const char *name,
    const char *stage, const char *category, const char *extra)
{
    SimStruct S;
    mxArray parameter;
    uint16_t input = 0x1234u;
    uint16_t output = 0xaaaau;

    sci_host_mock_reset(mode);
    prepare_sim(&S, &parameter, &input, &output);
    mdlInitializeSizes(&S);
    mdlCheckParameters(&S);
    mdlStart(&S);
    check(S.pwork == NULL, name);
    verify_error_text(name, &S, stage, category, extra);
    mdlTerminate(&S);
}

static void run_step_failure(sci_host_mock_mode_t mode, const char *name,
    const char *stage, const char *category, const char *extra,
    int null_output)
{
    SimStruct S;
    mxArray parameter;
    uint16_t input = 0x1234u;
    uint16_t output = 0xaaaau;
    AxisAlphaSfunContext *context;

    sci_host_mock_reset(mode);
    check(initialize_and_start(&S, &parameter, &input, &output) == 0,
        name);
    if (null_output != 0) S.outputs[0] = NULL;
    mdlOutputs(&S, 0);
    context = (AxisAlphaSfunContext *)S.pwork;
    check((null_output != 0 && output == 0xaaaau) ||
            (null_output == 0 && output == 0xaaaau),
        "step_failure_no_partial_commit");
    check(context != NULL && context->step_index == 0u &&
            context->session_started == 0 &&
            c2837x_pc_serial_is_valid(&context->serial) == 0,
        "step_failure_closes_and_preserves_step");
    verify_error_text(name, &S, stage, category, extra);
    mdlTerminate(&S);
}

int main(void)
{
    run_success_lifecycle();
    run_start_failure(SCI_HOST_MOCK_SERIAL_OPEN_OS, "serial_os_error",
        "stage=serial_open", "category=serial", "os_error=5");
    run_step_failure(SCI_HOST_MOCK_STEP_TIMEOUT, "partial_timeout",
        "stage=recv_payload", "category=timeout", "actual_length=1", 0);
    run_start_failure(SCI_HOST_MOCK_START_DSP, "protocol_dsp_error",
        "stage=wait_response", "category=dsp_response", "dsp_error=4");
    run_start_failure(SCI_HOST_MOCK_START_MESSAGE, "protocol_message_type",
        "stage=wait_response", "category=message_type", "actual_type=3");
    run_start_failure(SCI_HOST_MOCK_START_LENGTH, "protocol_payload_length",
        "stage=wait_response", "category=payload_length", "actual_length=4");
    run_step_failure(SCI_HOST_MOCK_STEP_DECODE, "decode_step_error",
        "stage=decode_output", "category=step_index", "actual_step=7", 0);
    run_step_failure(SCI_HOST_MOCK_STEP_COMMIT, "commit_port_error",
        "stage=commit_output", "category=port_access", "expected_type=3", 1);
    printf("SUMMARY passed=%d failed=%d\n", passed, failed);
    return failed == 0 ? 0 : 1;
}
