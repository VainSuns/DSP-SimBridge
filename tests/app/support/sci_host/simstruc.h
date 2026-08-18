#ifndef SCI_SFUN_HOST_SIMSTRUC_H
#define SCI_SFUN_HOST_SIMSTRUC_H

#include <math.h>
#include <stddef.h>
#include <stdint.h>

typedef int int_T;

typedef struct
{
    double value;
    size_t elements;
    int numeric;
    int complex_value;
} mxArray;

static int mxIsNumeric(const mxArray *value)
{
    return value != NULL && value->numeric != 0;
}

static int mxIsComplex(const mxArray *value)
{
    return value != NULL && value->complex_value != 0;
}

static size_t mxGetNumberOfElements(const mxArray *value)
{
    return value == NULL ? 0u : value->elements;
}

static double mxGetScalar(const mxArray *value)
{
    return value == NULL ? 0.0 : value->value;
}

static int mxIsFinite(double value)
{
    return isfinite(value) != 0;
}

typedef struct
{
    void *pwork;
    uint8_t dwork[512];
    const char *error_status;
    int num_params;
    int params_count;
    const mxArray *params[1];
    int param_tunable[1];
    int input_port_count;
    int output_port_count;
    const void *inputs[8];
    void *outputs[8];
    uint32_t options;
    size_t dwork_width;
} SimStruct;

#define SS_INT16 1
#define SS_UINT16 2
#define SS_INT32 3
#define SS_UINT32 4
#define SS_SINGLE 5
#define SS_DOUBLE 6
#define SS_UINT8 7

#define SS_OPTION_EXCEPTION_FREE_CODE 1u
#define SS_OPTION_CALL_TERMINATE_ON_EXIT 2u

#define ssSetNumSFcnParams(S_, N_) ((S_)->num_params = (N_))
#define ssGetNumSFcnParams(S_) ((S_)->num_params)
#define ssGetSFcnParamsCount(S_) ((S_)->params_count)
#define ssGetSFcnParam(S_, I_) ((S_)->params[(I_)])
#define ssSetSFcnParamTunable(S_, I_, V_) ((S_)->param_tunable[(I_)] = (V_))

#define ssSetNumInputPorts(S_, N_) ((S_)->input_port_count = (N_), 1)
#define ssSetNumOutputPorts(S_, N_) ((S_)->output_port_count = (N_), 1)
#define ssSetInputPortWidth(S_, P_, W_) ((void)(S_), (void)(P_), (void)(W_))
#define ssSetOutputPortWidth(S_, P_, W_) ((void)(S_), (void)(P_), (void)(W_))
#define ssSetInputPortDataType(S_, P_, T_) ((void)(S_), (void)(P_), (void)(T_))
#define ssSetOutputPortDataType(S_, P_, T_) ((void)(S_), (void)(P_), (void)(T_))
#define ssSetInputPortDirectFeedThrough(S_, P_, V_) ((void)(S_), (void)(P_), (void)(V_))
#define ssSetInputPortRequiredContiguous(S_, P_, V_) ((void)(S_), (void)(P_), (void)(V_))

#define ssSetNumSampleTimes(S_, N_) ((void)(S_), (void)(N_))
#define ssSetSampleTime(S_, I_, T_) ((void)(S_), (void)(I_), (void)(T_))
#define ssSetOffsetTime(S_, I_, T_) ((void)(S_), (void)(I_), (void)(T_))
#define ssSetNumPWork(S_, N_) ((void)(S_), (void)(N_))
#define ssSetNumDWork(S_, N_) ((void)(S_), (void)(N_), 1)
#define ssSetDWorkWidth(S_, I_, W_) ((void)(I_), (S_)->dwork_width = (W_))
#define ssSetDWorkDataType(S_, I_, T_) ((void)(S_), (void)(I_), (void)(T_))
#define ssSetDWorkUsedAsDState(S_, I_, V_) ((void)(S_), (void)(I_), (void)(V_))

#define ssSetOptions(S_, O_) ((S_)->options = (O_))
#define ssSetErrorStatus(S_, M_) ((S_)->error_status = (M_))
#define ssSetPWorkValue(S_, I_, V_) ((void)(I_), (S_)->pwork = (V_))
#define ssGetPWork(S_) ((S_)->pwork == NULL ? NULL : &(S_)->pwork)
#define ssGetPWorkValue(S_, I_) ((void)(I_), (S_)->pwork)
#define ssGetDWork(S_, I_) ((void)(I_), (void *)(S_)->dwork)
#define ssGetInputPortSignal(S_, P_) ((S_)->inputs[(P_)])
#define ssGetOutputPortSignal(S_, P_) ((S_)->outputs[(P_)])

#endif
