#ifndef _WIN32
#ifndef _POSIX_C_SOURCE
#define _POSIX_C_SOURCE 200809L
#endif
#endif

#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "axis_alpha_protocol.h"

static const char *test_mode;
static int injected_send_sim_start(AxisAlphaPcSocket *socket,
    uint16_t protocol_version, uint32_t interface_hash, uint32_t timeout_ms,
    AxisAlphaPcError *error);
#define axis_alpha_protocol_send_sim_start injected_send_sim_start
#include "axis_alpha_sfun.c"
#undef axis_alpha_protocol_send_sim_start

static int injected_send_sim_start(AxisAlphaPcSocket *socket,
    uint16_t protocol_version, uint32_t interface_hash, uint32_t timeout_ms,
    AxisAlphaPcError *error)
{
    if (strcmp(test_mode, "start_send_failure") != 0) {
        return axis_alpha_protocol_send_sim_start(socket, protocol_version,
            interface_hash, timeout_ms, error);
    }
    axis_alpha_pc_error_reset(error, "send_frame");
    error->kind = AXIS_ALPHA_PC_ERROR_DISCONNECT;
    axis_alpha_pc_socket_close(socket);
    return -1;
}

#ifdef _WIN32
#include <windows.h>
static uint64_t now_ms(void) { return (uint64_t)GetTickCount(); }
static void pause_ms(unsigned int value) { Sleep(value); }
#else
#include <time.h>
static uint64_t now_ms(void)
{
    struct timespec value;
    (void)clock_gettime(CLOCK_MONOTONIC, &value);
    return (uint64_t)value.tv_sec * 1000u + (uint64_t)value.tv_nsec / 1000000u;
}
static void pause_ms(unsigned int value)
{
    struct timespec delay = {(time_t)(value / 1000u), (long)(value % 1000u) * 1000000L};
    (void)nanosleep(&delay, NULL);
}
#endif

static int contains(const char *text, const char *token)
{
    return text != NULL && strstr(text, token) != NULL;
}

int main(int argc, char **argv)
{
    SimStruct sim = {0};
    AxisAlphaSfunContext *context;
    const char *before;
    uint64_t started;
    if (argc != 2) return 2;
    test_mode = argv[1];
    (void)&mdlInitializeSampleTimes;
    (void)&mdlOutputs;
    mdlInitializeSizes(&sim);
    if (sim.dwork_width != AXIS_ALPHA_SFUN_ERROR_TEXT_CAPACITY ||
            (sim.options & SS_OPTION_CALL_TERMINATE_ON_EXIT) == 0u) return 3;
    mdlStart(&sim);
    context = (AxisAlphaSfunContext *)sim.pwork;
    if (strcmp(argv[1], "success") == 0) {
        if (context == NULL || !axis_alpha_pc_socket_is_valid(&context->socket) ||
                context->session_started != 1 || context->step_index != 0u ||
                sim.error_status != NULL) return 4;
        started = now_ms();
        mdlTerminate(&sim);
        if (sim.pwork != NULL || now_ms() - started > 150u) return 5;
    } else if (strcmp(argv[1], "version_error") == 0 ||
            strcmp(argv[1], "hash_error") == 0) {
        const char *code = strcmp(argv[1], "version_error") == 0 ?
            "dsp_error=6" : "dsp_error=3";
        if (context != NULL || !contains(sim.error_status, "instance=axis_alpha") ||
                !contains(sim.error_status, "stage=wait_response") ||
                !contains(sim.error_status, code) || sim.error_status != sim.dwork) return 6;
        mdlTerminate(&sim);
    } else if (strcmp(argv[1], "connect_timeout") == 0) {
        if (context != NULL || !contains(sim.error_status, "category=timeout") ||
                sim.error_status != sim.dwork) return 7;
        mdlTerminate(&sim);
    } else if (strcmp(argv[1], "start_send_failure") == 0) {
        if (context != NULL || sim.error_status != sim.dwork ||
                !contains(sim.error_status, "stage=send_frame")) return 8;
        mdlTerminate(&sim);
    } else if (strcmp(argv[1], "response_timeout") == 0) {
        if (context != NULL || !contains(sim.error_status, "category=timeout") ||
                sim.error_status != sim.dwork) return 9;
        mdlTerminate(&sim);
    } else if (strcmp(argv[1], "stop_failure") == 0) {
        if (context == NULL || sim.error_status != NULL) return 10;
        pause_ms(100u);
        before = sim.error_status;
        mdlTerminate(&sim);
        if (sim.pwork != NULL || sim.error_status != before) return 11;
    } else if (strcmp(argv[1], "invalid_terminate") == 0) {
        if (context == NULL) return 12;
        axis_alpha_pc_socket_close(&context->socket);
        mdlTerminate(&sim);
        if (sim.pwork != NULL) return 13;
    } else {
        return 14;
    }
    printf("PASS %s\n", argv[1]);
    return 0;
}
