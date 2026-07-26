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

typedef union {
    Uint32 all;
} TEST_REGISTER32;

struct TEST_CPU_SYS_REGS {
    struct {
        struct {
            Uint16 EMIF1;
        } bit;
    } PCLKCR1;
};

struct TEST_DEVICE_CONFIG_REGS {
    TEST_REGISTER32 SOFTPRES1;
};

struct TEST_CLOCK_CONFIG_REGS {
    struct {
        struct {
            Uint16 EMIF1CLKDIV;
        } bit;
    } PERCLKDIVSEL;
};

struct TEST_EMIF_CONFIG_REGS {
    TEST_REGISTER32 EMIF1ACCPROT0;
    TEST_REGISTER32 EMIF1COMMIT;
    TEST_REGISTER32 EMIF1LOCK;
};

struct TEST_EMIF_REGS {
    struct {
        struct {
            Uint16 ASIZE;
            Uint16 TA;
            Uint16 R_HOLD;
            Uint16 R_STROBE;
            Uint16 R_SETUP;
            Uint16 W_HOLD;
            Uint16 W_STROBE;
            Uint16 W_SETUP;
            Uint16 EW;
            Uint16 SS;
        } bit;
    } ASYNC_CS4_CR;
};

extern volatile struct TEST_CPU_SYS_REGS CpuSysRegs;
extern volatile struct TEST_DEVICE_CONFIG_REGS DevCfgRegs;
extern volatile struct TEST_CLOCK_CONFIG_REGS ClkCfgRegs;
extern volatile struct TEST_EMIF_REGS Emif1Regs;
volatile struct TEST_EMIF_CONFIG_REGS* test_emif_config_regs(void);

#define Emif1ConfigRegs  (*test_emif_config_regs())
#define CPU1             1
#define GPIO_MUX_CPU1    1u
#define GPIO_OUTPUT      1u
#define GPIO_PUSHPULL    1u
#define EALLOW           ((void)0)
#define EDIS             ((void)0)
#define DELAY_US(value)  test_delay_us((Uint32)(value))

void GPIO_SetupPinMux(Uint16 pin, Uint16 cpu, Uint16 mux);
void GPIO_SetupPinOptions(Uint16 pin, Uint16 output, Uint16 options);
void GPIO_WritePin(Uint16 pin, Uint16 value);
void test_delay_us(Uint32 value);

#endif /* F28X_PROJECT_H */
