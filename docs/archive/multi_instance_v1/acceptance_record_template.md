# Acceptance Record

> **Historical notice — V1.0 multi-instance/W5300 artifact.**
>
> This file belongs to the completed historical 267-FR cycle. It is not current SCI implementation authority.
>
> Current SCI authority: `requirements/requirements_sci_iodevice_v1.0_frozen.md` and `plan.md`.
> Current SCI traceability: `docs/requirements_traceability.md`.
> Linked current guides may have evolved after this historical artifact.

> 本模板记录一次真实 DSP-SimBridge 验收活动。复制后填写，不要直接把模板当作结果。空白不等于通过；定稿前每个计划内 Test ID 都必须填写 `PASS`、`FAIL`、`NOT_EXECUTED`、`BLOCKED` 或 `USER_VALIDATION_PENDING`。环境能力缺失写 `NOT_EXECUTED / CAPABILITY`。只有实际执行且证据齐全才能写 `PASS`；总体可用 `PARTIAL` 表示部分完成。测试步骤和预期结果见 [测试方案](test_plan.md)。

## 1. Baseline

| Field | Actual value |
| --- | --- |
| Acceptance record ID |  |
| Repository |  |
| Branch |  |
| Commit SHA |  |
| Working tree state |  |
| App/DSP-SimBridge version |  |
| Project file / `.mat` |  |
| Project format version |  |
| DSP output root |  |
| S-Function output root |  |
| Generation date/time/timezone |  |
| Test start date/time/timezone |  |
| Test end date/time/timezone |  |
| Generated file manifest |  |

## 2. PC Environment

| Field | Actual value |
| --- | --- |
| MATLAB version |  |
| Simulink version |  |
| OS/version/architecture |  |
| `mexext` |  |
| MEX compiler name |  |
| MEX compiler version |  |
| Simulation mode |  |
| Model file / `.slx` |  |
| Python version, if used |  |
| Firewall/network notes |  |

不适用项填写 `N/A`。

## 3. DSP Environment

| Field | Actual value |
| --- | --- |
| DSP model |  |
| Board/hardware revision |  |
| CCS version |  |
| C2000 compiler version |  |
| ABI |  |
| Build configuration |  |
| Linker/startup configuration |  |
| W5300 hardware/module revision |  |
| DSP download/reset method |  |
| CPU Timer 2 ownership confirmed |  |
| Complete CCS build log |  |

不适用项填写 `N/A`。未经实际 CCS build/download 不得填写 `PASS`，应在第 6 节列为 `NOT_EXECUTED`、`BLOCKED` 或 `USER_VALIDATION_PENDING`。

## 4. Project Configuration

### 4.1 Common network

| Field | Actual value |
| --- | --- |
| Protocol version |  |
| DSP model in project |  |
| ABI selected in App |  |
| MAC |  |
| PC IP |  |
| DSP IP |  |
| Gateway |  |
| Subnet |  |
| Network topology |  |

### 4.2 Instances

| display_name | internal_name | Socket | TCP port | sample_time_sec | Interface Hash | input data octets | output data octets | input payload octets | output payload octets | max payload | RX generated capacity | TX generated capacity |
| --- | --- | ---: | ---: | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
|  |  |  |  |  |  |  |  |  |  |  |  |  |

### 4.3 Timeouts

| internal_name | PC `CONNECT_TIMEOUT_MS` | PC `STEP_TIMEOUT_MS` | PC `TERMINATE_TIMEOUT_MS` | DSP `INTERACTION_TIMEOUT` ms | DSP `TRANSFER_TIMEOUT` ms |
| --- | ---: | ---: | ---: | ---: | ---: |
|  |  |  |  |  |  |

PC 和 DSP timeout 相互独立、不协商。记录实际 wall-clock 和最终触发侧，不预先假定哪侧先触发。

### 4.4 Representative I/O coverage

| internal_name | Direction | Signal | Type | Dim | Test values / bit patterns | Scalar/Array | Evidence |
| --- | --- | --- | --- | ---: | --- | --- | --- |
|  | `<PC→DSP/DSP→PC>` |  | `<int16/uint16/int32/uint32/single/double>` |  |  |  |  |

六种类型、scalar 和 array 的覆盖缺口必须在第 6 节显式列出。浮点至少记录 normal finite、`+0`、`-0`；Inf/NaN/subnormal 如未执行，写明证据来自 Host/golden 或未执行。

## 5. Test Results

> `Actual result`、`Status`、`Evidence` 和 `Issue` 留给实际执行者填写。Evidence 写文件名/路径和关键位置；不得只写“见日志”。软件 runner count 记录本次真实数值，不复用历史 count。

### 5.1 Delivery-side software regression

| Test ID | Related FR | Actual result | Status | Evidence | Issue | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| SW-APP | FR-233, FR-237, FR-251 |  |  |  |  |  |
| SW-GEN | FR-233, FR-236 |  |  |  |  |  |
| SW-HASH | FR-233, FR-236 |  |  |  |  |  |
| SW-FILE | FR-233, FR-236, FR-237 |  |  |  |  |  |
| SW-PC-PROTOCOL | FR-146–FR-172, FR-233 |  |  |  |  |  |
| SW-PC-ATOMIC | FR-161, FR-171, FR-239 |  |  |  |  |  |
| SW-PC-MEX | FR-153–FR-172, FR-232–FR-234, FR-243 |  |  |  |  |  |
| SW-PC-NORMAL | FR-153–FR-172, FR-232–FR-234 |  |  |  |  |  |
| SW-DSP-HOST | FR-093–FR-152, FR-233, FR-238, FR-263–FR-266 |  |  |  |  |  |

Software runner record:

| Runner/category | Command/entry | Total | Passed | Failed | Incomplete | Log/evidence |
| --- | --- | ---: | ---: | ---: | ---: | --- |
|  |  |  |  |  |  |  |

### 5.2 DSP build and data types

| Test ID | Related FR | Actual result | Status | Evidence | Issue | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| DSP-BUILD-EABI | FR-228–FR-231, FR-234, FR-238, FR-251 |  |  |  |  |  |
| DSP-BUILD-COFF | FR-228–FR-231, FR-234, FR-238, FR-251 |  |  |  |  |  |
| TYPE-ROUNDTRIP-01 | FR-158–FR-161, FR-233, FR-234, FR-238 |  |  |  |  |  |

### 5.3 Single-instance and multiple sessions

| Test ID | Related FR | Actual result | Status | Evidence | Issue | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| SI-NORMAL-01 | FR-101, FR-112, FR-134–FR-143, FR-160–FR-171, FR-238 |  |  |  |  |  |
| SI-SESSION-02 | FR-112, FR-134, FR-140–FR-143, FR-163, FR-171, FR-234, FR-238 |  |  |  |  |  |
| SI-MULTISESSION | FR-112, FR-134, FR-140–FR-143, FR-234, FR-238 |  |  |  |  | `session_count=` |

Callback/session record:

| Session | internal_name | Connection identifier | OnStart count | Legal steps / OnStep count | OnStop count | First step | Last step | Close result | New listen observed |
| ---: | --- | --- | ---: | --- | ---: | ---: | ---: | --- | --- |
|  |  |  |  |  |  |  |  |  |  |

### 5.4 Dual-instance and isolation

| Test ID | Related FR | Actual result | Status | Evidence | Issue | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| DI-NORMAL-01 | FR-101, FR-103–FR-105, FR-133, FR-153–FR-160, FR-234, FR-238 |  |  |  |  |  |
| DI-ISOLATION-02 | FR-103, FR-116, FR-133–FR-136, FR-234, FR-238, FR-266 |  |  |  |  |  |

Isolation step record:

| Timestamp/event | Instance A step/state | Instance B step/state | Injected fault | A continued evidence | B cleanup/close | Other Socket/global reset evidence |
| --- | --- | --- | --- | --- | --- | --- |
|  |  |  |  |  |  |  |

### 5.5 Protocol errors

| Test ID | Related FR | Actual result | Status | Evidence | Issue | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| PROTO-VERSION | FR-134–FR-151, FR-234, FR-238 |  |  |  |  |  |
| PROTO-HASH | FR-134–FR-151, FR-232, FR-234, FR-238 |  |  |  |  |  |
| PROTO-LENGTH | FR-134–FR-150, FR-234, FR-238 |  |  |  |  |  |
| PROTO-TYPE | FR-134–FR-150, FR-234, FR-238 |  |  |  |  |  |
| PROTO-STATE | FR-129, FR-134–FR-150, FR-234, FR-238 |  |  |  |  |  |
| PROTO-STEP | FR-138–FR-150, FR-160–FR-171, FR-234, FR-238 |  |  |  |  | `duplicate/skipped/mismatched:` |

Protocol detail record:

| Test ID/variant | Phase | Expected/actual type | Expected/actual length | Expected/actual step/version/hash | Wire response | GetLastError | OnStep/OnStop | Close result/new session |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
|  |  |  |  |  |  |  |  |  |

### 5.6 Timeout, disconnect and IoDevice failures

| Test ID | Related FR | Actual result | Status | Evidence | Issue | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| TIMEOUT-FIRST-FRAME | FR-121–FR-136, FR-148, FR-234, FR-238 |  |  |  |  |  |
| TIMEOUT-INTERACTION | FR-126, FR-134–FR-136, FR-148, FR-234, FR-238 |  |  |  |  |  |
| TIMEOUT-TRANSFER-RX | FR-114–FR-126, FR-134–FR-136, FR-238 |  |  |  |  |  |
| TIMEOUT-TRANSFER-TX | FR-114–FR-126, FR-134–FR-149, FR-238, FR-265 |  |  |  |  |  |
| DISCONNECT-START | FR-134–FR-148, FR-162, FR-171, FR-234, FR-238 |  |  |  |  |  |
| DISCONNECT-RUN | FR-134–FR-148, FR-171, FR-234, FR-238 |  |  |  |  |  |
| DISCONNECT-PARTIAL | FR-134–FR-148, FR-161, FR-171, FR-234, FR-238 |  |  |  |  |  |
| IODEV-RX-FAIL | FR-114, FR-134–FR-150, FR-234, FR-238 |  |  |  |  |  |
| IODEV-TX-FAIL | FR-114, FR-134–FR-150, FR-234, FR-238, FR-265 |  |  |  |  |  |

Timing/transfer detail:

| Test ID | PC timeout config | DSP timeout config | Actual wall-clock | Triggering side/stage | Bytes transferred/pending | Socket state | GetLastError | Other-instance progress |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
|  |  |  |  |  |  |  |  |  |

### 5.7 Near-max payload and PC output atomicity

| Test ID | Related FR | Actual result | Status | Evidence | Issue | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| PAYLOAD-NEAR-MAX | FR-109, FR-123, FR-233, FR-237, FR-238 |  |  |  |  |  |
| SW-PC-ATOMIC | FR-161, FR-171, FR-239 |  |  |  |  | `可引用 5.1 的相同执行，勿伪造重复结果` |

Near-max detail:

| internal_name | Input data | Output data | Input payload | Output payload | Max payload | RX capacity | TX capacity | Tail sentinel/result |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
|  |  |  |  |  |  |  |  |  |

Atomic-output detail:

| Scenario | Last-known-good outputs | Outputs after error | Partial update observed | Error stage/text | Evidence source |
| --- | --- | --- | --- | --- | --- |
| RESPONSE(error) |  |  |  |  |  |
| Wrong type |  |  |  |  |  |
| Wrong length |  |  |  |  |  |
| Wrong step |  |  |  |  |  |
| Truncated header/payload |  |  |  |  |  |
| Timeout |  |  |  |  |  |
| Disconnect |  |  |  |  |  |
| Decode failure |  |  |  |  |  |

### 5.8 W5300 Erratum 1

| Test ID | Related FR | Actual result | Status | Evidence | Issue | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| ERRATUM-SENDOK | FR-116, FR-240, FR-263–FR-266 |  |  |  |  | `<Host/Hardware>` |
| ERRATUM-TIMEOUT | FR-116, FR-240, FR-263–FR-266 |  |  |  |  | `<Host/Hardware>` |
| ERRATUM-CLOSE-ERROR | FR-116, FR-131, FR-240, FR-263–FR-266 |  |  |  |  | `<Host/Hardware>` |

Erratum stage record:

| Test ID/time | Socket | `Sn_MR` | `Sn_TX_FSR` | TX capacity | Workaround needed | UDP OPEN/`SOCK_UDP` | Dummy SEND event | CLOSE/`SOCK_CLOSED` | Close result | faulted | Other Socket |
| --- | ---: | --- | ---: | ---: | --- | --- | --- | --- | --- | --- | --- |
|  |  |  |  |  |  |  | `<SEND_OK/TIMEOUT/N/A>` |  |  |  |  |

Fault recovery record:

| Event | Current Socket open/listen access | faulted | PlatformInit result/generation | DSP reset | Other instance result | Evidence |
| --- | --- | --- | --- | --- | --- | --- |
| Ordinary PC simulation restart |  |  |  | `No` |  |  |
| Failed PlatformInit, if safely testable |  |  |  |  |  |  |
| Successful PlatformInit or DSP reset |  |  |  |  |  |  |

## 6. Unexecuted / Blocked Items

列出所有 `NOT_EXECUTED`、`BLOCKED`、`USER_VALIDATION_PENDING` 和 `NOT_EXECUTED / CAPABILITY`；不得依靠第 5 节空白隐含未执行。

| Test ID / scope | Status | Reason | Missing capability/blocker | Impact | Owner | Required action/evidence | Target date |
| --- | --- | --- | --- | --- | --- | --- | --- |
|  |  |  |  |  |  |  |  |

## 7. Open Issues

问题材料应使用 [问题反馈模板](problem_feedback_template.md)。

| Issue ID | Severity | Description | Impact | Workaround | Retest required | Retest Test ID | Owner | Status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
|  |  |  |  |  |  |  |  |  |

## 8. Acceptance Summary

> 每项填写实际状态和证据摘要。软件证据不能替代 CCS/硬件证据；Host Erratum test 不能自动变成 W5300 hardware PASS。

| Scope | Result/status | Evidence summary | Remaining gap |
| --- | --- | --- | --- |
| Software-side result |  |  |  |
| DSP EABI compile result |  |  |  |
| DSP COFF compile result |  |  |  |
| DSP download result |  |  |  |
| Hardware result |  |  |  |
| Six data types result |  |  |  |
| Single-instance result |  |  |  |
| New/multiple sessions result |  |  |  |
| Dual-instance result |  |  |  |
| Local-fault isolation result |  |  |  |
| Protocol/error-path result |  |  |  |
| Timeout/disconnect result |  |  |  |
| Near-max payload result |  |  |  |
| PC atomic-output result |  |  |  |
| Erratum SENDOK result |  |  |  |
| Erratum TIMEOUT result |  |  |  |
| Erratum faulted/recovery result |  |  |  |

Final overall status: `<PASS / FAIL / PARTIAL / BLOCKED>`

Acceptance decision and rationale:

`<说明通过、拒绝或部分验收的事实依据；逐项引用证据和未执行范围>`

Restrictions/conditions of acceptance:

`<填写或 N/A>`

## 9. Reviewer / Tester

| Role | Name | Organization/team | Date/time/timezone | Signature/approval reference |
| --- | --- | --- | --- | --- |
| Tester |  |  |  |  |
| DSP/CCS tester |  |  |  |  |
| Hardware tester |  |  |  |  |
| Reviewer |  |  |  |  |
| Acceptance owner |  |  |  |  |

## 10. Evidence Index

| # | Test ID / issue | File name/path | Evidence type | Captured date/time | Description |
| ---: | --- | --- | --- | --- | --- |
| 1 |  |  | `<build log/MATLAB log/Simulink transcript/CCS console/screen capture/scope/logic analyzer/PCAP/register snapshot/watch/generated file>` |  |  |
| 2 |  |  |  |  |  |

## 11. Completion Checklist

- [ ] Baseline、PC、DSP、hardware、network 和每实例配置均已填写；不适用项为 `N/A`。
- [ ] 每个计划内 Test ID 都有明确状态，未执行项全部出现在第 6 节。
- [ ] 所有 `PASS` 都有可追溯 Evidence；没有以推断、Host 或 Mock 替代未执行硬件。
- [ ] 所有 `FAIL` 都有关联 Issue 和复现材料。
- [ ] EABI 与 COFF 分开记录；能力缺失未被填写为通过。
- [ ] 六种类型、scalar/array 和浮点 bit-preservation 的实际覆盖已列明。
- [ ] 新用户 session 与 PC 自动 reconnect 已明确区分。
- [ ] 普通 close `DONE` 后恢复与 close `ERROR`/faulted 恢复门禁已明确区分。
- [ ] 双实例隔离包含两个实例各自的 step/log 证据。
- [ ] Erratum 的证据来源已标为 Host 或 Hardware。
- [ ] Final overall status 与全部未执行、阻塞和 open issue 一致。
