#ifndef SCI_SFUN_HOST_SERIAL_TEST_H
#define SCI_SFUN_HOST_SERIAL_TEST_H

#include <stdint.h>

typedef enum
{
    SCI_HOST_MOCK_NORMAL = 0,
    SCI_HOST_MOCK_SERIAL_OPEN_OS = 1,
    SCI_HOST_MOCK_STEP_TIMEOUT = 2,
    SCI_HOST_MOCK_START_DSP = 3,
    SCI_HOST_MOCK_START_MESSAGE = 4,
    SCI_HOST_MOCK_START_LENGTH = 5,
    SCI_HOST_MOCK_STEP_DECODE = 6,
    SCI_HOST_MOCK_STEP_COMMIT = 7
} sci_host_mock_mode_t;

void sci_host_mock_reset(sci_host_mock_mode_t mode);
const char *sci_host_mock_log(void);
uint32_t sci_host_mock_configured_baud(void);
uint32_t sci_host_mock_open_com_number(void);
uint32_t sci_host_mock_purge_flags(void);
uint32_t sci_host_mock_sim_stop_timeout(void);
int sci_host_mock_same_send_deadline(void);
int sci_host_mock_same_receive_deadline(void);

#endif /* SCI_SFUN_HOST_SERIAL_TEST_H */
