# DSP-SimBridge tests

Run all currently implemented MATLAB tests from any working directory:

```matlab
repo = '<repo>';
addpath(fullfile(repo, 'tests'));
result = run_all_tests();
```

Run one category:

```matlab
result = run_all_tests('protocol');
```

Categories:

- `protocol`: immutable V1 protocol baseline, golden frames, and stage0 repository checks.
- `app`: stage1 project/model/generation transaction tests. Not implemented in stage0.
- `dsp_host`: stage2 host-side Core/W5300 tests. Not implemented in stage0.
- `pc`: stage4 PC/S-Function tests. Not implemented in stage0.

An empty category is reported as `NOT_IMPLEMENTED`; it is not treated as passing.
Record gate evidence using `test_result_schema.json` and actual command/environment data.
