# DSP-SimBridge Problem Feedback

> 复制本模板后填写并提交。所有字段都应填写；不适用时写 `N/A`。请附文件名或附件路径，不要把巨大二进制文件直接粘贴进 Markdown。不要截断第一条错误、CCS build log 的相关完整上下文或 Simulink error status。（FR-241）

## 1. Issue Summary

| Field | Value |
| --- | --- |
| Issue ID | `<填写或 N/A>` |
| Title | `<一句话描述>` |
| Reporter | `<姓名/团队/联系方式>` |
| Report date/time/timezone | `<填写>` |
| Severity | `<Blocker/Critical/Major/Minor>` |
| Affected area | `<App/Generate/DSP build/DSP runtime/MEX/Simulink/Protocol/W5300/Erratum/Documentation>` |
| Frequency/repeatability | `<Always/Intermittent/Once；成功次数/尝试次数>` |
| First observed version/commit | `<填写>` |
| Regression from known-good | `<Yes/No/Unknown；若 Yes 填 known-good commit>` |
| Current status | `<OPEN/NEEDS_INFO/RETEST/CLOSED>` |

## 2. Repository and Product Baseline

| Field | Value |
| --- | --- |
| App/DSP-SimBridge version | `<界面版本、版本标签或 commit；未知写 Unknown>` |
| Repository | `<URL/名称>` |
| Branch | `<填写>` |
| Repository commit SHA | `<完整 SHA>` |
| Commit used when Generate ran | `<完整 SHA>` |
| Local changes at Generate/build time | `<None；或附 git status/diff 摘要>` |
| Project file / `.mat` | `<文件名和附件路径>` |
| Project format version | `<project.format_version>` |
| Generation date/time/timezone | `<填写>` |

## 3. Project Configuration and Generated Files

### 3.1 Output roots

| Field | Value |
| --- | --- |
| Generated DSP root | `<绝对路径>` |
| Generated S-Function root | `<绝对路径>` |
| Generation result/status | `<success/partial_failure/其他实际值>` |
| Preview/Generate warnings | `<完整文本或附件>` |

### 3.2 Common project configuration

| Field | Value |
| --- | --- |
| DSP model | `<填写>` |
| Protocol version | `<填写>` |
| ABI selected in App | `<eabi/coffabi/实际值>` |
| MAC | `<填写>` |
| DSP IP | `<填写>` |
| Gateway | `<填写或 N/A>` |
| Subnet | `<填写>` |
| PC IP | `<填写>` |
| Network topology | `<直连/交换机/路由；关键设备>` |

### 3.3 Affected instance

| Field | Value |
| --- | --- |
| Display name | `<填写>` |
| Internal name | `<填写>` |
| IoDevice | `<填写；当前通常为 w5300_tcp>` |
| Socket number | `<0..7>` |
| TCP port | `<填写>` |
| `sample_time_sec` | `<填写>` |
| Interface Hash | `<0x........>` |
| Input data octets | `<填写>` |
| Output data octets | `<填写>` |
| Input payload octets | `<填写>` |
| Output payload octets | `<填写>` |
| `max_payload_size_bytes` | `<填写>` |
| Algorithm mode/source | `<generated_example/external_copy/external_reference；源文件名>` |

如有多个受影响实例，复制本节，并注明哪个实例是 last-known-good/first-bad。

### 3.4 Generated file list

附 Generate 时的完整文件列表。可使用文件浏览器导出、`tree`、PowerShell、shell 或其他等价方式；不能把某个 OS 专用命令作为唯一方式。

```text
<粘贴可读的相对文件列表，或写附件文件名/路径>
```

Generated file-list attachment: `<文件名/路径>`

## 4. PC Environment

| Field | Value |
| --- | --- |
| MATLAB version | `<填写>` |
| Simulink version | `<填写>` |
| OS/version/architecture | `<填写>` |
| `mexext` | `<填写>` |
| MEX compiler name | `<填写>` |
| MEX compiler version | `<填写>` |
| Instance build script | `<build_<internal_name>_sfun.m 路径>` |
| MEX file/path/time/size | `<填写>` |
| `which <internal_name>_sfun -all` output | `<粘贴或附件>` |
| Simulation mode | `<Normal/其他>` |
| PC `CONNECT_TIMEOUT_MS` | `<填写>` |
| PC `STEP_TIMEOUT_MS` | `<填写>` |
| PC `TERMINATE_TIMEOUT_MS` | `<填写>` |

## 5. DSP and Hardware Environment

| Field | Value |
| --- | --- |
| CCS version | `<填写>` |
| C2000 compiler version | `<填写>` |
| ABI actually built | `<EABI/COFF/填写>` |
| DSP model | `<填写>` |
| Board/hardware revision | `<填写>` |
| W5300 hardware/module revision | `<填写>` |
| Linker/startup configuration | `<名称/附件>` |
| Build configuration | `<Debug/Release/自定义>` |
| DSP `INTERACTION_TIMEOUT` | `<填写 ms>` |
| DSP `TRANSFER_TIMEOUT` | `<填写 ms>` |
| DSP image/program timestamp | `<填写>` |
| Download/reset method | `<填写>` |

## 6. CCS Integration and `main.c`

| Field | Value |
| --- | --- |
| Bottom-level/device initialization location | `<函数/文件/行或附件>` |
| `C2837xBlock_PlatformInit()` call location | `<函数/文件/行>` |
| `C2837xBlock_PlatformInit()` result | `<数值和符号；未观察写 Unknown>` |
| Per-instance `C2837xBlock_Init()` calls | `<按顺序列出>` |
| Main `while`/`for` loop location | `<函数/文件/行>` |
| Per-instance `C2837xBlock_Run()` polling order | `<按实际顺序列出>` |
| CPU Timer 2 ownership/configuration | `<填写>` |
| `<dsp_root>/inc` include path | `<实际值>` |
| Compiled `.c` manifest | `<附件；确认每个只编译一次>` |
| Old generated files removed | `<Yes/No/Unknown；说明>` |

优先附 `main.c`。若不能附完整文件，请粘贴 PlatformInit、每实例 Init、主循环 Run 顺序和底层初始化的最小相关代码。无需提供与问题无关的 proprietary algorithm source。

```c
/* Minimum relevant main.c excerpt, or write: See attachment <file>. */
```

## 7. Reproduction Steps

> 从干净启动状态写出最小、确定的复现。注明在哪一步首次出现问题，以及是否每次可复现。

1. `<填写>`
2. `<填写>`
3. `<填写>`

Additional attempts/variations:

1. `<填写或 N/A>`
2. `<填写或 N/A>`

## 8. Expected Result

`<说明按哪个 Test ID、FR 或用户文档应发生什么>`

Related Test ID / FR / task: `<例如 PROTO-STEP / FR-144 / S5-04>`

## 9. Actual Result

`<准确描述实际行为、首次失败点以及后续状态>`

| Field | Value |
| --- | --- |
| Last known good `step_index` | `<填写或 N/A>` |
| First bad `step_index` | `<填写或 N/A>` |
| Expected/actual message type | `<填写或 N/A>` |
| Expected/actual payload length | `<填写或 N/A>` |
| Expected/actual step | `<填写或 N/A>` |
| DSP wire RESPONSE/error | `<符号、数值、raw bytes；或 N/A>` |
| `C2837xBlock_GetLastError()` | `<符号和值；或 Unknown>` |
| Other instance impact | `<None/说明/Not tested>` |
| Recovery attempted | `<新用户 session/PlatformInit/DSP reset/其他>` |
| Recovery result | `<填写；未执行写 NOT_EXECUTED>` |

## 10. Full Error Text

不要只贴最后一行，也不要截断第一条错误。

### 10.1 App / MATLAB error and warnings

```text
<完整文本，或写附件文件名/路径；无则 N/A>
```

### 10.2 CCS errors and warnings

附完整 build log；若文件很大，在此提供附件名并粘贴第一条错误及其完整相关上下文。

```text
<完整相关上下文，或 N/A>
```

Complete CCS build log: `<文件名/路径或 N/A>`

### 10.3 Simulink error status

复制完整 error status，包括 instance、stage、category、step_index 和可获得的 expected/actual、DSP/OS error 字段。

```text
<完整 Simulink error status，或 N/A>
```

### 10.4 DSP console/assert/watch text

```text
<完整相关文本，或 N/A>
```

## 11. Socket, Protocol, Breakpoint and Packet Evidence

仅在相关时填写；不要求每个问题提供所有寄存器。记录采样时刻、Socket、协议阶段、当前/前一步操作，避免孤立的数值快照。

| Evidence | Value |
| --- | --- |
| Sample time/event | `<填写>` |
| Instance / Socket | `<填写>` |
| Protocol phase | `<WAIT_SIM_START/SIM_RUNNING/Unknown>` |
| Core operation/stage | `<connect/receive/send/close/Unknown>` |
| `Sn_MR` | `<值或 N/A>` |
| `Sn_CR` | `<值或 N/A>` |
| `Sn_SSR` | `<值或 N/A>` |
| `Sn_IR` | `<值或 N/A>` |
| `Sn_TX_FSR` | `<值或 N/A>` |
| `Sn_RX_RSR` | `<值或 N/A>` |
| Breakpoint/watch location | `<文件/函数/行或 N/A>` |
| Packet capture frame/time | `<文件和 filter/frame number 或 N/A>` |

### 11.1 Erratum/close evidence, if relevant

| Field | Value |
| --- | --- |
| Socket TX total capacity | `<填写>` |
| `Sn_TX_FSR != tx_mem_size` | `<True/False/Unknown>` |
| Close stage | `<C2837X_W5300_CLOSE_* 或等价观察>` |
| Pending command | `<C2837X_W5300_COMMAND_* 或 N/A>` |
| UDP OPEN / `SOCK_UDP` observed | `<Yes/No/Unknown>` |
| Dummy SEND issued | `<Yes/No/Unknown>` |
| `SEND_OK` observed | `<Yes/No/Unknown>` |
| `TIMEOUT` observed | `<Yes/No/Unknown>` |
| CLOSE / `SOCK_CLOSED` observed | `<Yes/No/Unknown>` |
| Close result | `<BUSY/DONE/ERROR/Unknown>` |
| Channel `faulted` state | `<0/1/Unknown>` |
| Other Socket state before/after | `<填写>` |
| Successful PlatformInit generation or DSP reset after fault | `<填写或 NOT_EXECUTED>` |

## 12. Attachments and Evidence List

| # | File name/path | Type | Captured date/time | Description / related step |
| ---: | --- | --- | --- | --- |
| 1 |  | `<.mat/build log/main.c/JSON/PCAP/screenshot/register dump/etc.>` |  |  |
| 2 |  |  |  |  |

建议按问题需要提供：project `.mat`、generated file list、完整 CCS build log、最小 `main.c`、Simulink transcript、MEX resolution、PC/DSP logs、packet capture、W5300 register snapshot、breakpoint/watch record。不要把巨大二进制内容内嵌到本 Markdown；提供附件路径/文件名和校验信息（如适用）。

## 13. Workaround and Additional Notes

Known workaround: `<填写或 None>`

Workaround impact/limitations: `<填写或 N/A>`

Additional notes: `<填写或 N/A>`

## 14. Retest Request

| Field | Value |
| --- | --- |
| Fix commit/build | `<填写或 N/A>` |
| Retest Test ID(s) | `<填写>` |
| Required environment | `<填写>` |
| Required evidence | `<填写>` |
| Retest owner | `<填写>` |
| Retest status | `<NOT_EXECUTED/USER_VALIDATION_PENDING/PASS/FAIL/BLOCKED>` |
