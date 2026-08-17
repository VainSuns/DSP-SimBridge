# PC tests

Run the deterministic standard-library mock matrix with:

```text
python tests/pc/run_sfun_pc_matrix.py
```

`sfun_mock_endpoint.py --help` documents the standalone endpoint CLI.

The SCI-S4-01 raw serial core test uses the production source with its
compile-time syscall/clock seam:

```text
gcc -std=c11 -Wall -Wextra -Werror -DC2837X_PC_SERIAL_TEST_SEAM -Isimulink tests/pc/pc_serial_host_test.c simulink/c2837x_block_pc_serial.c -o "$env:TEMP\pc_serial_host_test.exe"
& "$env:TEMP\pc_serial_host_test.exe"
```
