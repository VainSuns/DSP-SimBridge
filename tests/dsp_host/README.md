# DSP host tests

S2-01 covers the public Core API and instance state. S2-02 adds host-stub
coverage for shared platform initialization, Timer2, W5300 memory/network
readback, failure short-circuiting, and reset timing source evidence. S2-03
adds the generic IoDevice boundary, Fake IoDevice Core linking, and independent
W5300 channel coverage. S2-03A adds the internal const Config and algorithm
adapter contract, static two-instance binding, routing/isolation, and invalid
configuration boundary coverage.

Run with:

```matlab
run_all_tests('dsp_host')
```
