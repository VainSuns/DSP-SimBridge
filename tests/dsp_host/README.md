# DSP host tests

S2-01 covers the public Core API and instance state. S2-02 adds host-stub
coverage for shared platform initialization, Timer2, W5300 memory/network
readback, failure short-circuiting, and reset timing source evidence.

Run with:

```matlab
run_all_tests('dsp_host')
```
