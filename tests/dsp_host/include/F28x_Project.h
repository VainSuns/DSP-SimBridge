#ifndef F28X_PROJECT_H
#define F28X_PROJECT_H

#include <stdint.h>

typedef uint16_t Uint16;
typedef uint32_t Uint32;
typedef int16_t int16;
typedef int32_t int32;

typedef union {
    Uint32 all;
} CPUTIMER_REG32;

typedef union {
    Uint16 all;
    struct {
        Uint16 TDDR : 8;
        Uint16 PSC : 8;
    } bit;
} CPUTIMER_TPR_REG;

typedef union {
    Uint16 all;
    struct {
        Uint16 TDDRH : 8;
        Uint16 PSCH : 8;
    } bit;
} CPUTIMER_TPRH_REG;

typedef union {
    Uint16 all;
    struct {
        Uint16 reserved0 : 4;
        Uint16 TSS : 1;
        Uint16 TRB : 1;
        Uint16 reserved1 : 4;
        Uint16 SOFT : 1;
        Uint16 FREE : 1;
        Uint16 reserved2 : 2;
        Uint16 TIE : 1;
        Uint16 TIF : 1;
    } bit;
} CPUTIMER_TCR_REG;

struct CPUTIMER_REGS {
    CPUTIMER_REG32 TIM;
    CPUTIMER_REG32 PRD;
    CPUTIMER_TCR_REG TCR;
    CPUTIMER_TPR_REG TPR;
    CPUTIMER_TPRH_REG TPRH;
};

extern volatile struct CPUTIMER_REGS CpuTimer2Regs;

#endif /* F28X_PROJECT_H */
