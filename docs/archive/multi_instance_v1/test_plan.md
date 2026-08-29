# DSP-SimBridge 测试方案

> **Historical notice — V1.0 multi-instance/W5300 artifact.**
>
> This file belongs to the completed historical 267-FR cycle. It is not current SCI implementation authority.
>
> Current SCI authority: `requirements/requirements_sci_iodevice_v1.0_frozen.md` and `plan.md`.
> Current SCI traceability: `docs/requirements_traceability.md`.
> Linked current guides may have evolved after this historical artifact.

## 1. 目的、范围和状态规则

本文是 Stage 5 / S5-04 的长期测试方案，定义 DSP-SimBridge V1 多实例交付的软件回归、用户 CCS 编译和 DSP/W5300 实机验收。使用说明见 [App 项目与迁移指南](../../app_project_and_migration_guide.md)、[CCS 集成和双实例 main 指南](../../ccs_integration_and_dual_instance_main.md)以及 [Simulink 与 MEX 使用指南](../../simulink_mex_user_guide.md)；这些文档说明“如何使用”，本文说明“如何验证”。

本文不记录某一次历史测试数量或结果，不执行 S5-05 或 G5，也不以 Host、Mock 或文档检查替代用户 CCS、TMS320F28377D、W5300 和真实联机证据。（FR-233～FR-245、FR-251）

正式用例只使用以下状态：

| 状态 | 含义 |
| --- | --- |
| `PASS` | 已按本方案实际执行，预期结果全部满足，且所需证据可追溯 |
| `FAIL` | 已执行，但至少一个预期结果不满足 |
| `NOT_EXECUTED` | 尚未执行；不得据此推断结果 |
| `BLOCKED` | 已尝试执行，但存在明确阻塞条件 |
| `USER_VALIDATION_PENDING` | 实现或交付方证据已存在，仍需用户 CCS、DSP 或硬件验证 |

环境能力缺失时填写 `NOT_EXECUTED / CAPABILITY`，并记录缺失的工具、硬件或权限。验收汇总可使用 `PARTIAL` 表示部分完成，但单个用例不得用 `PARTIAL` 替代上述状态。不得使用 `OK`、“大概通过”、“应该可以”或“默认通过”。未经实际执行和证据不得写 `PASS`；尤其不得预判 DSP CCS compile、download、W5300 hardware、真实 Simulink/DSP 联机、Erratum hardware、EABI 或 COFF。（FR-235、FR-245）

本文各用例的 `Actual result=<执行后填写>`、`Status=NOT_EXECUTED` 是计划初始值，不是测试结论。执行者应把实际结果写入 [验收记录模板](acceptance_record_template.md)，并以真实状态替换初始值。

## 2. 测试责任边界

### 2.1 交付方责任

交付方负责 App 功能和配置校验、确定性生成、Interface Hash/CRC32 golden、candidate/user-file 保护、PC 源码生成、每实例 MEX build script、可执行的 PC 协议/错误路径测试、DSP 集成与测试方案，以及根据用户日志修正生成器、Core、协议和驱动实现缺陷。（FR-233）

交付方必须交付 App、DSP Core/生成模板、每实例 S-Function 源码模板和构建脚本、集成/迁移/使用/测试/反馈文档的源码；不能只交付 MEX 或其他二进制，也不要求 installer、`.mltbx` 或正式发布包。（FR-242～FR-244）

### 2.2 用户责任

用户负责 CCS 工程集成、EABI/COFF 编译、底层初始化、linker/startup、DSP download、TMS320F28377D、W5300 实机、单实例/双实例联机、协议错误、超时、断线、重新建立新会话，以及提交完整日志和验收记录。CCS 和 C2000 compiler 版本不冻结，以实际环境和证据为准。（FR-234）

用户责任项在执行前保持 `NOT_EXECUTED` 或 `USER_VALIDATION_PENDING`，不得因软件侧测试通过而改写为硬件 `PASS`。

## 3. 自动化边界和可用方法

第一版允许 MATLAB script、Mock endpoint、Host C test、手工 Simulink model、CCS build/console log、断点/watch、寄存器快照、逻辑分析或 packet capture。第一版不要求 CI 自动烧录 DSP、自动操作 CCS GUI、自动操作 Simulink GUI或无人值守 W5300 硬件矩阵。（FR-240）

协议/错误注入按以下顺序选择：

1. 当前仓库已有 protocol、Host fixture 或 Mock endpoint；
2. 临时、独立的测试 client；
3. 受控 mismatch configuration；
4. 抓包或其他测试工具。

不得为制造错误永久修改 generated production files；临时修改必须隔离于正式输出，并在测试后重新 Generate/Build 正式基线。本文不虚构硬件自动化脚本。

## 4. 环境和基线记录

每次执行必须在验收记录中填写下列字段；不适用时填 `N/A`，不得留给解释者猜测。

### 4.1 仓库和项目

| 字段 | 实际值 |
| --- | --- |
| Repository | `<填写>` |
| Branch | `<填写>` |
| Commit SHA | `<填写完整 SHA>` |
| Project file / `.mat` | `<填写>` |
| Project format version | `<填写；当前实现为 V2/format_version=2，但以文件为准>` |
| Generation date/time | `<填写时区>` |
| DSP output root | `<绝对路径>` |
| S-Function output root | `<绝对路径>` |
| Generated file manifest | `<附件/文件名>` |

### 4.2 PC 环境

| 字段 | 实际值 |
| --- | --- |
| MATLAB version | `<填写>` |
| Simulink version | `<填写>` |
| OS | `<填写>` |
| `mexext` | `<填写>` |
| MEX compiler name/version | `<填写>` |

### 4.3 DSP 和网络环境

| 字段 | 实际值 |
| --- | --- |
| CCS version | `<填写>` |
| C2000 compiler version | `<填写>` |
| ABI | `eabi` / `coffabi` / `<实际值>` |
| DSP model | `<填写>` |
| Board/hardware revision | `<填写>` |
| W5300 hardware/module revision | `<填写>` |
| Network topology | `<直连/交换机/路由及关键设备>` |
| PC IP | `<填写>` |
| DSP IP | `<填写>` |
| MAC | `<填写>` |
| Gateway | `<填写或 N/A>` |
| Subnet | `<填写>` |

### 4.4 每实例配置

| display_name | internal_name | Socket | TCP port | sample_time_sec | Interface Hash | input data octets | output data octets | input payload octets | output payload octets | max payload |
| --- | --- | ---: | ---: | ---: | --- | ---: | ---: | ---: | ---: | ---: |
| `<填写>` | `<填写>` |  |  |  | `0x........` |  |  |  |  |  |

同时记录每实例 PC 配置头中的 `CONNECT_TIMEOUT_MS`、`STEP_TIMEOUT_MS`、`TERMINATE_TIMEOUT_MS`，以及 DSP `inc/<internal_name>_user_config.h` 中的 `INTERACTION_TIMEOUT` 和 `TRANSFER_TIMEOUT`。PC 与 DSP timeout 相互独立、不协商；哪个先触发取决于配置和实际 wall-clock，不得预先断言。（FR-121～FR-126、FR-166～FR-170）

## 5. 通用准备、证据和判定

### 5.1 测试准备

1. 记录第 4 节全部环境字段，并保存 `.mat`、Interface Hash、生成结果和文件清单。
2. 从同一次有效 Preview/Generate 获得 `<dsp_root>/inc`、`<dsp_root>/src` 和 `<sfun_root>/<internal_name>/`；清除 CCS 工程和 MATLAB Path 中的旧单实例/旧 MEX 混用风险。（FR-228～FR-232）
3. 建立 representative project。至少包含一个可执行单实例和两个独立实例；双实例建议使用 `axis_alpha`、`axis_beta`，但名称不是冻结要求。
4. representative project 的 PC→DSP 输入和 DSP→PC 输出合计覆盖 `int16`、`uint16`、`int32`、`uint32`、`single`、`double`，同时包含 scalar 和 array。
5. 为浮点 round-trip 至少准备 normal finite、`+0`、`-0` 的 wire bit preservation 样本。`+Inf`、`-Inf`、NaN、subnormal 可由 Host/golden test 覆盖；若执行硬件验收，记录实际结果。不得要求算法对 NaN 做数值运算。
6. 为算法回调准备可观测的 `OnStart`、`OnStep`、`OnStop` count、step_index 和输入/输出记录。不得因插桩改变 wire layout 或 Interface Hash 而不重新 Generate。
7. DSP main 只按用户 `main.c` 的实际顺序轮询实例，不宣称两实例在并行线程执行。

当前基线的 public API 名称必须逐项核对，不得写回旧无参数 API：

```c
int16 C2837xBlock_PlatformInit(void);
void C2837xBlock_Init(C2837xBlock *instance);
void C2837xBlock_Run(C2837xBlock *instance);
C2837xBlock_Error C2837xBlock_GetLastError(const C2837xBlock *instance);
```

### 5.2 所需证据

证据可以是 build log、MATLAB test log、Simulink transcript、CCS console、screen capture、scope waveform、logic analyzer、Wireshark/packet capture、W5300 register snapshot、breakpoint/watch record、generated file 或 issue ID。每项证据必须记录文件名/路径、时间和对应 Test ID；不要把巨大二进制直接粘贴进 Markdown。

软件 runner 的 count 随维护变化，必须记录本次真实 total/passed/failed/incomplete，不把固定 count 写成规范。硬件用例至少同时保留 PC 和 DSP 两侧证据；双实例隔离用例必须保留两个实例各自日志或 step 证据。

### 5.3 判定规则

- `PASS`：所有 Procedure 已执行，全部 Expected result 满足，Required evidence 齐全且能对应当前 commit/config。
- `FAIL`：任何预期不满足；创建问题反馈并填写 Issue reference。
- `BLOCKED`：已尝试但无法继续；记录阻塞步骤、原因和解除条件。
- `NOT_EXECUTED`：未尝试，或 `NOT_EXECUTED / CAPABILITY`。
- `USER_VALIDATION_PENDING`：仅表示待用户验证，不表示已通过。
- 普通 protocol/timeout/disconnect/IoDevice 会话错误若 channel close 最终 `DONE`，用户可以启动新的 simulation/session；第一版 PC S-Function 不自动 reconnect。
- W5300 close `ERROR` 是不同语义：当前 Socket 进入私有 `faulted`，在下一次成功 `C2837xBlock_PlatformInit()` 或 DSP reset 前不得 `open/listen`；普通“重新启动 PC simulation”不能恢复该 Socket。（FR-116、FR-131、FR-266）

## 6. 当前仓库软件回归

下列用例记录交付方软件测试类别，不预置永久 count 或 PASS。统一前置是当前仓库 commit 已记录且测试工具可用；统一配置是使用当前测试自身 fixture；实际命令、日志和 count 以执行时仓库为准。

### SW-APP — App validation

- **Related FR:** FR-233、FR-237、FR-251
- **Purpose:** 验证项目结构、名称、网络、Socket/port、I/O、payload、输出路径和外部算法配置在写盘前被校验。
- **Prerequisites/Configuration:** MATLAB 可运行当前 App tests。
- **Procedure:** 运行当前仓库 App category；保存 runner、环境和真实 count；核对错误配置未进入写盘提交。
- **Expected result:** 所有已实现 App validation test 完成且无 failed/incomplete；非法配置在写入前拒绝。
- **Required evidence:** MATLAB test log、category result、代表性 validation identifier。
- **Execution record:** Actual result=`<执行后填写>`；Status=`NOT_EXECUTED`；Issue reference=`N/A`；Notes=`<填写>`。

### SW-GEN — Deterministic generation

- **Related FR:** FR-233、FR-236
- **Purpose:** 验证同配置、模板和外部文件下重复 Preview/Generate 内容确定。
- **Prerequisites/Configuration:** 一个有效项目和隔离输出目录。
- **Procedure:** 对同一项目连续构建候选/生成；比较所有自动生成文件字节和 Interface Hash；记录实际文件集合。
- **Expected result:** 自动生成文件和 Hash 相同，无动态时间戳差异；用户文件默认保留。
- **Required evidence:** 两轮 manifest/hash、字节比较或测试日志。
- **Execution record:** Actual result=`<执行后填写>`；Status=`NOT_EXECUTED`；Issue reference=`N/A`；Notes=`<填写>`。

### SW-HASH — Interface Hash / CRC32 golden

- **Related FR:** FR-233、FR-236
- **Purpose:** 验证 canonical text、CRC32 golden 和配置敏感/非敏感字段边界。
- **Prerequisites/Configuration:** 当前 protocol/App hash tests。
- **Procedure:** 运行当前 Hash/CRC32 tests；保存 canonical text、golden value 和实际 value。
- **Expected result:** golden 匹配；协议、I/O 顺序/名称/类型/维度和 max payload 的变化按规范影响 Hash。
- **Required evidence:** MATLAB log、canonical text、expected/actual hash。
- **Execution record:** Actual result=`<执行后填写>`；Status=`NOT_EXECUTED`；Issue reference=`N/A`；Notes=`<填写>`。

### SW-FILE — Candidate/user-file protection

- **Related FR:** FR-233、FR-236、FR-237
- **Purpose:** 验证 candidate classification、Preview snapshot、默认 Keep 和写入保护。
- **Prerequisites/Configuration:** 隔离输出目录，准备 missing/same/different user/core/auto-generated 文件。
- **Procedure:** 执行 Preview/commit tests；分别验证 create/skip/replace/keep 和 stale snapshot；保存文件前后摘要。
- **Expected result:** 不同 user 文件默认 Keep；强制替换需明确允许；过期 Preview 或路径冲突在写入前拒绝。
- **Required evidence:** action matrix、before/after manifest、test log。
- **Execution record:** Actual result=`<执行后填写>`；Status=`NOT_EXECUTED`；Issue reference=`N/A`；Notes=`<填写>`。

### SW-PC-PROTOCOL — PC protocol golden/error path

- **Related FR:** FR-146～FR-172、FR-233
- **Purpose:** 验证 V1 golden、PC frame/error 分支、结构化错误和 deterministic Mock endpoint。
- **Prerequisites/Configuration:** 当前 protocol 和 PC tests；所需 MATLAB/Python 可用。
- **Procedure:** 运行当前 protocol/PC category 和现有 Mock matrix；记录真实 scenario、repeat 和 runner count。
- **Expected result:** 当前实现的 success/error scenarios 可重复；错误文本含可获得的 instance/stage/step/expected/actual/DSP/OS 信息。
- **Required evidence:** protocol/PC logs、Mock transcript、环境记录。
- **Execution record:** Actual result=`<执行后填写>`；Status=`NOT_EXECUTED`；Issue reference=`N/A`；Notes=`<填写>`。

### SW-PC-ATOMIC — OUTPUT_DATA atomic output behavior

- **Related FR:** FR-161、FR-171、FR-239
- **Purpose:** 验证 `RESPONSE(error)`、wrong type/length/step、truncated header/payload、timeout、disconnect 和 decode failure 均不部分更新当前 step 的任何 Simulink output。
- **Prerequisites/Configuration:** 当前 PC fixture；为各 output 设置可识别的 last-known-good 值。
- **Procedure:** 对每个错误 scenario 保存错误前后全部 outputs；记录证据来源是 automated fixture 还是用户模型。
- **Expected result:** 错误 step 的全部 outputs 保持 last-known-good；连接关闭并设置 Simulink error status；无自动 reconnect。
- **Required evidence:** 每 scenario 的 before/after outputs、完整错误文本和测试日志。
- **Execution record:** Actual result=`<执行后填写>`；Status=`NOT_EXECUTED`；Issue reference=`N/A`；Notes=`<填写证据来源>`。

### SW-PC-MEX — MEX build

- **Related FR:** FR-153～FR-172、FR-232～FR-234、FR-243
- **Purpose:** 验证每实例自包含 build script、真实 MEX compiler 构建和失败保护。
- **Prerequisites/Configuration:** MATLAB/Simulink、已选择受支持 C MEX compiler、生成实例目录。
- **Procedure:** 从非实例 cwd 运行每实例 `build_<internal_name>_sfun.m`；记录 `mexext`、compiler 和完整 build log；检查目标路径和 foreign/locked/failure 行为。
- **Expected result:** 构建出的 `<internal_name>_sfun.<mexext>` 位于当前实例目录；不同实例不混编；失败语义与用户指南一致。
- **Required evidence:** build log、MEX path/size、`which <internal_name>_sfun -all`。
- **Execution record:** Actual result=`<执行后填写>`；Status=`NOT_EXECUTED`；Issue reference=`N/A`；Notes=`<填写>`。

### SW-PC-NORMAL — Normal-mode

- **Related FR:** FR-153～FR-172、FR-232～FR-234
- **Purpose:** 验证生成 MEX 在桌面 Simulink Normal mode 的启动、step、停止和错误路径。
- **Prerequisites/Configuration:** 当前生成实例、MEX、Normal-mode 测试模型和 Mock/真实 DSP endpoint。
- **Procedure:** 执行成功路径及当前 PC error scenarios；记录模型、MEX resolution、transcript 和输出。
- **Expected result:** 成功路径按 step 同步原子更新；错误路径停止 simulation 并保留当前 step outputs；不宣称 Accelerator/Fast Restart 等范围外能力。
- **Required evidence:** Simulink transcript、model path、MEX resolution、scenario log。
- **Execution record:** Actual result=`<执行后填写>`；Status=`NOT_EXECUTED`；Issue reference=`N/A`；Notes=`<填写 endpoint 类型>`。

### SW-DSP-HOST — DSP Host state-machine tests

- **Related FR:** FR-093～FR-152、FR-233、FR-238、FR-263～FR-266
- **Purpose:** 验证设备无关 Core、timeout/lifecycle、双实例隔离、W5300 SEND completion 和 close/Erratum/fault gate。
- **Prerequisites/Configuration:** MATLAB 和当前 Host C compiler fixture 可用。
- **Procedure:** 运行当前 `dsp_host` category；记录真实 test count、编译器输出和 fixture 名称。
- **Expected result:** 当前 Host tests 无 failed/incomplete；其结果仅作为软件机制证据，不替代 CCS 或 W5300 hardware。
- **Required evidence:** MATLAB/Host build/run log、category result。
- **Execution record:** Actual result=`<执行后填写>`；Status=`NOT_EXECUTED`；Issue reference=`N/A`；Notes=`Hardware remains USER_VALIDATION_PENDING unless separately executed`。

## 7. DSP 编译和数据类型

### DSP-BUILD-EABI — EABI CCS build

- **Related FR:** FR-228～FR-231、FR-234、FR-238、FR-251
- **Purpose:** 验证 App `eabi` 输出能集成到用户 CCS 工程。
- **Prerequisites:** 用户 CCS 工程、C2000 compiler、linker/startup/底层初始化已准备；当前生成输出可用。
- **Configuration:** App ABI=`eabi`；记录 CCS、compiler、DSP 和板卡。
- **Procedure:** 1) 在 App 选择 `eabi` 并 Generate；2) 从 CCS 工程移除旧生成文件；3) 加入当前公共、project、有效 instance `.c`；4) Include `<dsp_root>/inc`；5) 确认每个 `.c` 只编译一次且不 `#include "*.c"`；6) 设置与 generated config 一致的 EABI；7) build；8) 保存完整 build log。
- **Expected result:** 无 duplicate symbol、旧 API、unresolved generated symbol 或 ABI mismatch；若实际 compiler/工程不支持该配置，记录原因并保持 `NOT_EXECUTED / CAPABILITY` 或 `BLOCKED`，不得改为 `PASS`。
- **Required evidence:** App ABI/Generate 记录、CCS project file/config、完整 build log、source/include manifest。
- **Execution record:** Actual result=`<执行后填写>`；Status=`NOT_EXECUTED`；Issue reference=`N/A`；Notes=`<填写>`。

### DSP-BUILD-COFF — COFF ABI CCS build

- **Related FR:** FR-228～FR-231、FR-234、FR-238、FR-251
- **Purpose:** 验证 App `coffabi` 输出能集成到用户 CCS 工程。
- **Prerequisites:** 与 DSP-BUILD-EABI 相同，且用户工具链具有 COFF 能力。
- **Configuration:** App ABI=`coffabi`；记录实际 CCS/compiler support。
- **Procedure:** 按 DSP-BUILD-EABI 的 8 个步骤重新 Generate、清理旧文件并独立 build，ABI 改为 COFF；不得把 EABI 和 COFF 对象混合链接。
- **Expected result:** 与 DSP-BUILD-EABI 相同；无支持能力时如实记录 `NOT_EXECUTED / CAPABILITY`，不能用 EABI 结果代替 COFF。
- **Required evidence:** COFF Generate 记录、完整 build log、source/include manifest。
- **Execution record:** Actual result=`<执行后填写>`；Status=`NOT_EXECUTED`；Issue reference=`N/A`；Notes=`<填写>`。

### TYPE-ROUNDTRIP-01 — 六种类型 scalar/array wire round-trip

- **Related FR:** FR-158～FR-161、FR-233、FR-234、FR-238
- **Purpose:** 验证 PC↔DSP wire serialization 对六种支持类型和维度的保持。
- **Prerequisites:** representative project 已在当前 ABI 编译并联机；算法仅回送或可预测变换输入。
- **Configuration:** 输入与输出覆盖 `int16`、`uint16`、`int32`、`uint32`、`single`、`double`，每种至少有 scalar 或 array，整体同时存在 scalar 和 array；浮点含 normal finite、`+0`、`-0`。
- **Procedure:** 1) 记录每个 signal 的类型/维度/wire offset；2) 发送包含边界和可识别 bit pattern 的向量；3) 在 DSP 输入对象、DSP 输出对象和 Simulink outputs 三处记录值/bit pattern；4) 连续执行多个合法 step；5) 如执行 Inf/NaN/subnormal，仅比较 wire bit preservation，不要求算法数值运算。
- **Expected result:** integer 值、array 顺序、浮点 bit pattern 和端口映射一致；每合法 step 仅一次 `OnStep` 和一个匹配 `OUTPUT_DATA`；无串位、截断或部分 output update。
- **Required evidence:** project I/O table、input/output vectors、DSP watch/trace、PC transcript、step_index。
- **Execution record:** Actual result=`<执行后填写>`；Status=`NOT_EXECUTED`；Issue reference=`N/A`；Notes=`<列实际覆盖的特殊浮点>`。

## 8. 单实例与多轮会话

### SI-NORMAL-01 — 单实例正常启动、step 和停止

- **Related FR:** FR-101、FR-112、FR-134～FR-143、FR-160～FR-171、FR-238
- **Purpose:** 验证完整单实例正常会话生命周期。
- **Prerequisites:** DSP-BUILD 对当前 ABI 已有可接受结果；DSP/W5300/网络和一个实例 MEX 已准备。
- **Configuration:** 记录实例、Socket、port、Hash、PC/DSP timeout 和计划 step 数。
- **Procedure:** `PlatformInit` → instance `Init` → main 循环持续 `Run` → PC/Simulink connect → `SIM_START` → successful `RESPONSE` → step 0 → 连续若干正常 `INPUT_DATA/OUTPUT_DATA` → Normal Stop → `SIM_STOP` → DSP cleanup → 返回等待新连接。
- **Expected result:** `OnStart` 一次；每合法 step `OnStep` 一次且有对应 `OUTPUT_DATA`；step_index 从 0 严格顺序推进；正常 stop 时 `OnStop` 一次；DSP 不自动额外响应 `SIM_STOP`；连接关闭；close `DONE` 后实例可再次监听。
- **Required evidence:** PC/DSP transcript、callback count、step list、close/listen 状态、Simulink Normal Stop 记录。
- **Execution record:** Actual result=`<执行后填写实际 callback count>`；Status=`NOT_EXECUTED`；Issue reference=`N/A`；Notes=`<填写>`。

### SI-SESSION-02 — 用户启动新的会话

- **Related FR:** FR-112、FR-134、FR-140～FR-143、FR-163、FR-171、FR-234、FR-238
- **Purpose:** 区分“用户重新启动 simulation/session”和“PC 自动 reconnect”。
- **Prerequisites:** SI-NORMAL-01 能正常结束，且上次 channel close 为 `DONE`。
- **Configuration:** 使用相同正式配置；第一版 S-Function 自动 reconnect=`不支持`。
- **Procedure:** 正常结束上一会话 → 确认 DSP 返回可监听状态 → 用户重新启动新的 simulation/session → 建立新 TCP connection → 新 `SIM_START` → 执行 step 0 和至少一个后续 step。
- **Expected result:** 新会话成功；step_index 重置为 0；无旧 session header/payload/I/O 数据泄漏；恢复不是 S-Function 在断线后自动重连。
- **Required evidence:** 两个 TCP connection/session 标识、两轮 step_index、DSP cleanup/listen、PC start transcript。
- **Execution record:** Actual result=`<执行后填写>`；Status=`NOT_EXECUTED`；Issue reference=`N/A`；Notes=`<填写>`。

### SI-MULTISESSION — 多轮正常会话

- **Related FR:** FR-112、FR-134、FR-140～FR-143、FR-234、FR-238
- **Purpose:** 验证重复 start/steps/normal stop 后仍可建立后续会话。
- **Prerequisites:** SI-SESSION-02 通过或具备等价前置证据。
- **Configuration:** 计划多个回合；轮数不是冻结需求。
- **Procedure:** 重复“用户启动 session → 执行合法 steps → Normal Stop → 等待 close `DONE`/重新监听”，至少发生一次关闭后的再次会话；记录实际 `session_count=N`。
- **Expected result:** 每轮从 step 0 开始；callback 生命周期、输入输出和错误状态不跨轮泄漏；各轮正常 close 后可继续。
- **Required evidence:** `session_count=N`、每轮 callback/step/close 摘要和日志。
- **Execution record:** Actual result=`session_count=<执行后填写>`；Status=`NOT_EXECUTED`；Issue reference=`N/A`；Notes=`<填写>`。

## 9. 双实例和局部故障隔离

### DI-NORMAL-01 — 双实例独立运行

- **Related FR:** FR-101、FR-103～FR-105、FR-133、FR-153～FR-160、FR-234、FR-238
- **Purpose:** 验证两个实例拥有独立 Socket、port、MEX、context、算法和 step。
- **Prerequisites:** 两个实例已 Generate/Build/Download；DSP main 按实际固定顺序轮询两实例。
- **Configuration:** 例如 `axis_alpha`/`axis_beta`；分别记录 Socket、TCP port、S-Function/MEX、Hash、sample time 和 timeout。
- **Procedure:** 1) 启动 DSP 顺序轮询；2) 在一个 Normal-mode 模型中启动两个实例专用 S-Function；3) 两实例分别完成 `SIM_START`；4) 发送不同可识别输入并交错观察 steps；5) 正常停止两实例。
- **Expected result:** 两实例各自从 step 0 开始；输入输出不串实例；一个实例 step 不推进另一个实例 step；两个连接独立；结果不被描述为 DSP 并行线程执行。
- **Required evidence:** 两实例各自 PC/DSP log、MEX resolution、Socket/port、step 和 I/O 记录。
- **Execution record:** Actual result=`<执行后填写>`；Status=`NOT_EXECUTED`；Issue reference=`N/A`；Notes=`<记录 main Run 顺序>`。

### DI-ISOLATION-02 — 双实例局部故障隔离

- **Related FR:** FR-103、FR-116、FR-133～FR-136、FR-234、FR-238、FR-266
- **Purpose:** 验证 Instance B 的局部失败不停止 Instance A。
- **Prerequisites:** DI-NORMAL-01 已建立双连接；A 连续产生可观测 step。
- **Configuration:** 选择 B 的 disconnect、protocol error 或可控 IoDevice failure；记录注入方法。
- **Procedure:** 1) 保持 A 正常运行；2) 对 B 注入一种局部故障；3) 继续按同一 main 顺序轮询两实例；4) 观察 B cleanup/close 和 A 的后续多个 steps；5) 检查其他 Socket 和 W5300 公共状态未被改写。
- **Expected result:** B 结束/清理自己的 session；A 的 Socket、step、算法和通信继续；不发生 W5300 global reset；不修改其他 Socket；A 不被 B 的局部错误阻塞。若 B close `ERROR`，只有 B 进入 faulted，A 仍继续。
- **Required evidence:** 两实例分别的日志/step、W5300 reset/other Socket 证据、B GetLastError/close result。
- **Execution record:** Actual result=`<执行后填写>`；Status=`NOT_EXECUTED`；Issue reference=`N/A`；Notes=`<填写故障类型>`。

## 10. 协议错误矩阵

线缆错误码沿用冻结 V1：unknown type=`C2837X_ERR_UNKNOWN_TYPE (1)`，payload length=`C2837X_ERR_PAYLOAD_LENGTH (2)`，config/hash mismatch=`C2837X_ERR_CONFIG_MISMATCH (3)`，state=`C2837X_ERR_STATE (4)`，protocol version=`C2837X_ERR_PROTOCOL_VERSION (6)`，step=`C2837X_ERR_STEP_INDEX (7)`。本地 `C2837xBlock_GetLastError()` 与 wire error 相互独立；以下协议错误通常记录 `C2837X_BLOCK_ERROR_PROTOCOL`。（FR-146～FR-151）

连接和 TX 状态安全时尽力发送对应 `RESPONSE(error)`；若连接已经失效、Header 不完整或 TX 不安全，允许直接 close，不得规定超出 FR-147/FR-148 的强制响应。错误响应和 close 都跨多次 `Run` 有界推进。

### PROTO-VERSION — protocol_version mismatch

- **Related FR:** FR-134～FR-151、FR-234、FR-238
- **Purpose:** 验证不匹配 protocol version 在算法启动前被拒绝。
- **Prerequisites/Configuration:** 使用现有 protocol fixture、临时 test client 或受控 client version；记录 actual/expected version。
- **Procedure:** 建立 TCP connection，发送 Header/length 合法但 protocol_version 不匹配的 `SIM_START`；持续轮询至响应/close 完成；读取 GetLastError；随后仅在 close `DONE` 后尝试用户新会话。
- **Expected result:** 安全时发送 `C2837X_ERR_PROTOCOL_VERSION (6)`；当前 session terminate/cleanup；`OnStart=0`、`OnStep=0`、`OnStop=0`；GetLastError 记录协议错误；close `DONE` 后允许新会话。
- **Required evidence:** actual/expected version、raw/decoded response、GetLastError、callback count、close result。
- **Execution record:** Actual result=`<执行后填写>`；Status=`NOT_EXECUTED`；Issue reference=`N/A`；Notes=`<填写注入工具>`。

### PROTO-HASH — Interface Hash mismatch

- **Related FR:** FR-134～FR-151、FR-232、FR-234、FR-238
- **Purpose:** 验证 DSP/PC 配置不一致不会进入 normal running。
- **Prerequisites/Configuration:** DSP 与 PC 来自两次受控 Generate 的不同 Hash，或使用 test client；不得手工永久改 generated Hash。
- **Procedure:** 建立连接并发送 version 正确、Hash 错误的 `SIM_START`；记录两端 Hash、response、callback 和 cleanup；保存 PC `which <internal_name>_sfun -all`。
- **Expected result:** 安全时发送 `C2837X_ERR_CONFIG_MISMATCH (3)`；不进入 running；`OnStart=0`、`OnStep=0`、`OnStop=0`；session cleanup；close `DONE` 后允许新会话。
- **Required evidence:** DSP/PC generated Hash、Generate/build output、MEX resolution、raw/decoded response、GetLastError。
- **Execution record:** Actual result=`<执行后填写>`；Status=`NOT_EXECUTED`；Issue reference=`N/A`；Notes=`<填写>`。

### PROTO-LENGTH — payload length error

- **Related FR:** FR-134～FR-150、FR-234、FR-238
- **Purpose:** 验证固定长度错误或完整 Header 声明超限的处理。
- **Prerequisites/Configuration:** test client 能构造合法 Header 格式但错误 length；分别记录 phase 和 TX 安全性。
- **Procedure:** 在启动前或 running 中注入错误 fixed length；至少一项在 algorithm_started 后执行以验证 `OnStop`；持续轮询至 error response/close；记录无正常 output。
- **Expected result:** 完整 Header 且 TX 安全时尽力发送 `C2837X_ERR_PAYLOAD_LENGTH (2)`；TX 不安全时可直接 close；非法请求不调用 OnStep、不产生正常 `OUTPUT_DATA`；已启动算法 `OnStop` 一次；cleanup 后仅在 close `DONE` 时允许新会话。
- **Required evidence:** phase、declared/expected length、response 或 direct-close 原因、OnStep/OnStop、close result。
- **Execution record:** Actual result=`<执行后填写>`；Status=`NOT_EXECUTED`；Issue reference=`N/A`；Notes=`<填写>`。

### PROTO-TYPE — unknown/wrong message type

- **Related FR:** FR-134～FR-150、FR-234、FR-238
- **Purpose:** 验证未知 message type 不进入算法 step。
- **Prerequisites/Configuration:** test client 可发送未知 type；记录 phase。
- **Procedure:** 在连接有效且 TX 可用时发送 unknown type；运行中变体应先完成合法 start；持续轮询至 response/close。
- **Expected result:** 安全时发送 `C2837X_ERR_UNKNOWN_TYPE (1)`；非法请求 `OnStep=0`、无正常 `OUTPUT_DATA`；若算法已启动则 `OnStop` 一次；session cleanup。
- **Required evidence:** raw Header/type、response、callback count、GetLastError、close result。
- **Execution record:** Actual result=`<执行后填写>`；Status=`NOT_EXECUTED`；Issue reference=`N/A`；Notes=`<填写>`。

### PROTO-STATE — valid message in wrong protocol state

- **Related FR:** FR-129、FR-134～FR-150、FR-234、FR-238
- **Purpose:** 验证合法消息处于错误 `WAIT_SIM_START`/`SIM_RUNNING` 顺序时被拒绝。
- **Prerequisites/Configuration:** 使用已知合法 message type 和 length，但选择错误 phase。
- **Procedure:** 例如在首帧发送 `INPUT_DATA`，或 running 后再发送 `SIM_START`；分别记录实际 phase；持续轮询至 response/close。
- **Expected result:** 安全时发送 `C2837X_ERR_STATE (4)`；错误消息不触发 OnStep；已启动算法 OnStop 一次；session cleanup；close `DONE` 后可由用户新建 session。
- **Required evidence:** message/phase、response、callback count、GetLastError、close result。
- **Execution record:** Actual result=`<执行后填写>`；Status=`NOT_EXECUTED`；Issue reference=`N/A`；Notes=`<填写变体>`。

### PROTO-STEP — duplicate/skipped/mismatched step

- **Related FR:** FR-138～FR-150、FR-160～FR-171、FR-234、FR-238
- **Purpose:** 验证 step_index 严格匹配且不恢复、重发、跳步或接受重复。
- **Prerequisites/Configuration:** 已进入 `SIM_RUNNING`；test client 可控制 step_index。
- **Procedure:** 分别执行 duplicate、skipped 和其他 mismatched step；每个变体从干净新 session 开始；记录 expected/actual step、callback 和 outputs。
- **Expected result:** 当前非法请求不调用 OnStep、不产生正常 `OUTPUT_DATA`；安全时发送 `C2837X_ERR_STEP_INDEX (7)`；session terminate；不 retransmit、不接受 duplicate、不跳 step；PC S-Function 不自动恢复。
- **Required evidence:** 每变体 expected/actual step、raw/decoded response、OnStep/OnStop、PC outputs、close result。
- **Execution record:** Actual result=`<执行后填写三个变体>`；Status=`NOT_EXECUTED`；Issue reference=`N/A`；Notes=`<填写>`。

## 11. Timeout、断线和 IoDevice failure

### TIMEOUT-FIRST-FRAME — 首帧 transfer timeout

- **Related FR:** FR-121～FR-136、FR-148、FR-234、FR-238
- **Purpose:** 验证 TCP 建立后等待首个 `SIM_START` 数据使用 DSP `TRANSFER_TIMEOUT`。
- **Prerequisites/Configuration:** 记录 DSP `TRANSFER_TIMEOUT`、PC timeout 和 wall-clock；test client 可只连接或发送不完整首帧。
- **Procedure:** 建立 TCP connection，但不完整发送首帧/`SIM_START`；持续调用 `Run`，等待超过实际 DSP transfer timeout；记录首个字节/分段进度和触发时间。
- **Expected result:** 当前 session 结束并 cleanup；无 OnStart/OnStep/OnStop；GetLastError 为 timeout；允许直接 close；close `DONE` 后可新建 session。
- **Required evidence:** timeout 配置、wall-clock、bytes transferred、GetLastError、callback、close result。
- **Execution record:** Actual result=`<执行后填写>`；Status=`NOT_EXECUTED`；Issue reference=`N/A`；Notes=`<填写 PC/DSP 哪侧先触发>`。

### TIMEOUT-INTERACTION — running 交互 timeout

- **Related FR:** FR-126、FR-134～FR-136、FR-148、FR-234、FR-238
- **Purpose:** 验证完整响应发送后等待下一帧首个新数据使用 `INTERACTION_TIMEOUT`。
- **Prerequisites/Configuration:** 成功进入 running 并完成至少一个 output；设置测试中可观察的 timeout 顺序。
- **Procedure:** 在成功响应发送完成后停止发送下一合法 `INPUT_DATA`；持续 `Run`，等待超过 DSP interaction timeout；随后推进 close。
- **Expected result:** 已启动算法 `OnStop` 一次；当前 session 关闭；部分 Header/Payload、输入/输出对象和进度 cleanup；last error 保留；若 channel close `DONE`，实例最终可用于后续用户新会话。
- **Required evidence:** 最后完整 response、timeout/wall-clock、OnStop、GetLastError、I/O cleanup、close/listen。
- **Execution record:** Actual result=`<执行后填写>`；Status=`NOT_EXECUTED`；Issue reference=`N/A`；Notes=`<填写>`。

### TIMEOUT-TRANSFER-RX — 分段 RX 无进度 timeout

- **Related FR:** FR-114～FR-126、FR-134～FR-136、FR-238
- **Purpose:** 验证部分 Header/Payload 后无正进度时按 transfer timeout 终止。
- **Prerequisites/Configuration:** Host fixture 或可控 client；记录每次实际 receive progress。
- **Procedure:** 在首帧或 running frame 发送部分 Header/Payload后暂停；确认正进度曾刷新时间戳，再等待超过 transfer timeout；继续轮询另一个实例（如存在）。
- **Expected result:** Core/channel 按 timeout terminate，不 busy-loop；不处理不完整 frame、不调用非法 OnStep、不产生部分 output；其他实例不被卡住；close 后按 DONE/faulted 语义处理恢复。
- **Required evidence:** bytes transferred、RX stage、时间戳/wall-clock、Socket state、GetLastError、other-instance step。
- **Execution record:** Actual result=`<执行后填写>`；Status=`NOT_EXECUTED`；Issue reference=`N/A`；Notes=`<Header/Payload>`。

### TIMEOUT-TRANSFER-TX — 分段 TX pending timeout

- **Related FR:** FR-114～FR-126、FR-134～FR-149、FR-238、FR-265
- **Purpose:** 验证正常/错误 response 分段发送无确认进度时超时，且 Core 不提前提交发送进度。
- **Prerequisites/Configuration:** Host fixture、可控 driver stub 或硬件注入可保持 segment pending；记录 SEND event。
- **Procedure:** 使一个发送分段提交后不获得可向 Core 报告的正进度；持续 `Run` 超过 transfer timeout；记录 pending octets、Sn_CR/Sn_IR 和其他实例进度。
- **Expected result:** 超时终止；完整帧未发送前不递增 step、不进入 running、不部分产生 PC output；无内部长等待；其他实例继续；随后 close 的 DONE/ERROR 决定是否 faulted。
- **Required evidence:** actual bytes/pending octets、TX stage、Sn_CR/Sn_IR、GetLastError、step、other-instance log、close result。
- **Execution record:** Actual result=`<执行后填写>`；Status=`NOT_EXECUTED`；Issue reference=`N/A`；Notes=`<填写>`。

### DISCONNECT-START — `SIM_START` 期间断线

- **Related FR:** FR-134～FR-148、FR-162、FR-171、FR-234、FR-238
- **Purpose:** 验证启动 Header/Payload 或成功 response 发送期间断线。
- **Prerequisites/Configuration:** 可控 PC client/network；记录断线精确阶段。
- **Procedure:** 建立连接，在 `SIM_START` 接收或 start response 发送完成前断开；持续 DSP `Run` 至 cleanup/close。
- **Expected result:** 当前 session cleanup；`OnStop` 按 `algorithm_started`（OnStart 未成功则 0，已成功则一次）；无正常 step/output；PC 报告失败；无自动 reconnect；其他 Socket 不受影响。
- **Required evidence:** disconnect stage、callback count、PC error、GetLastError、close/other Socket。
- **Execution record:** Actual result=`<执行后填写>`；Status=`NOT_EXECUTED`；Issue reference=`N/A`；Notes=`<填写>`。

### DISCONNECT-RUN — running 期间断线

- **Related FR:** FR-134～FR-148、FR-171、FR-234、FR-238
- **Purpose:** 验证算法已启动后的对端断开。
- **Prerequisites/Configuration:** 已完成合法 start 和至少一个 step。
- **Procedure:** 在等待下一 frame 或当前传输期间断开 PC/network；持续 DSP `Run` 至错误和 close 完成；观察另一个实例。
- **Expected result:** 当前 session cleanup，OnStop 一次；不产生断线 step 的部分 output；PC simulation reports failure；不自动 reconnect；其他 Socket/实例继续。实际 GetLastError 需记录：Core 直接观察 peer-close 时为 `DISCONNECTED`，分段无进度可能按实际阶段表现为 `TIMEOUT`，驱动失败为 `IODEVICE`。
- **Required evidence:** last-good/first-bad step、断线阶段、PC error、GetLastError、OnStop、close/other instance。
- **Execution record:** Actual result=`<执行后填写>`；Status=`NOT_EXECUTED`；Issue reference=`N/A`；Notes=`<填写>`。

### DISCONNECT-PARTIAL — Header/Payload 部分传输后断线

- **Related FR:** FR-134～FR-148、FR-161、FR-171、FR-234、FR-238
- **Purpose:** 验证 truncated frame 不被解析为完整请求，也不部分更新 PC output。
- **Prerequisites/Configuration:** 可控 client/Mock 能在指定 byte offset 断开。
- **Procedure:** 对 RX Header、RX Payload，以及适用时 PC 接收 DSP Header/Payload 分别在部分传输后断开；记录 bytes 和 last-known-good outputs。
- **Expected result:** 当前 session cleanup；OnStop 按 algorithm_started；无非法 OnStep/部分 output；PC error 标识 truncated/disconnect/timeout 的实际阶段；无自动 reconnect；其他 Socket 不受影响。
- **Required evidence:** direction、stage、bytes、PC output before/after、callback、close result。
- **Execution record:** Actual result=`<执行后填写>`；Status=`NOT_EXECUTED`；Issue reference=`N/A`；Notes=`<填写变体>`。

### IODEV-RX-FAIL — IoDevice receive failure

- **Related FR:** FR-114、FR-134～FR-150、FR-234、FR-238
- **Purpose:** 验证 `receive()<0` 的 Core 处理和实例隔离。
- **Prerequisites/Configuration:** 当前 Host fixture、可控 driver stub 或实际硬件错误注入；算法已启动变体优先。
- **Procedure:** 在 receiving 阶段注入负返回；继续 `Run` 至 cleanup/close；同时轮询其他实例。
- **Expected result:** `C2837X_BLOCK_ERROR_IODEVICE`；当前 session cleanup；已启动算法 OnStop 一次；其他实例不受影响；不要求不安全连接发送 error RESPONSE。
- **Required evidence:** injection point/return、GetLastError、OnStop、close、other-instance step。
- **Execution record:** Actual result=`<执行后填写>`；Status=`NOT_EXECUTED`；Issue reference=`N/A`；Notes=`<填写注入方式>`。

### IODEV-TX-FAIL — IoDevice send failure

- **Related FR:** FR-114、FR-134～FR-150、FR-234、FR-238、FR-265
- **Purpose:** 验证 `send()<0` 或 W5300 SEND failure 的 Core 处理和实例隔离。
- **Prerequisites/Configuration:** 当前 Host fixture、driver stub 或硬件注入；记录是否为正常/错误 response。
- **Procedure:** 在发送阶段注入负返回/TIMEOUT/invalid Socket；继续 `Run` 至 cleanup/close；检查 step 未提前提交并继续轮询其他实例。
- **Expected result:** `C2837X_BLOCK_ERROR_IODEVICE`，除非已锁存更早的 primary error；当前 session cleanup，已启动算法 OnStop 一次；无完整发送确认则 step 不递增；其他实例不受影响。
- **Required evidence:** send stage/event、pending octets、primary/GetLastError、step、OnStop、close、other instance。
- **Execution record:** Actual result=`<执行后填写>`；Status=`NOT_EXECUTED`；Issue reference=`N/A`；Notes=`<填写>`。

## 12. 接近最大合法 Payload

### PAYLOAD-NEAR-MAX — 合法 near-max wire round-trip

- **Related FR:** FR-109、FR-123、FR-233、FR-237、FR-238
- **Purpose:** 验证 App 合法配置下接近但不超过 `max_payload_size_bytes` 的 generated capacity 和真实 round-trip。
- **Prerequisites:** 可通过 App validation 的大维度 I/O project；PC/DSP 能编译并联机。
- **Configuration:** 记录 `input_data_octets`、`output_data_octets`、`input_payload_octets`、`output_payload_octets`、`max_payload_size_bytes`、generated RX/TX capacity。
- **Procedure:** 1) 用 App 构造输入/输出 payload 接近但不超过 max；2) Preview/Generate；3) 检查 report 和 generated capacity；4) Build PC/DSP；5) 发送可检测尾部的完整向量并 round-trip；6) 另以 App validation 测试超过 max 的配置，不绕过校验。
- **Expected result:** near-max 配置可合法 Generate 和 wire round-trip，无 buffer overwrite/truncation；尾部字段正确；超过 max 的配置在写盘前拒绝。
- **Required evidence:** App report、配置和 generated capacity、build logs、完整首尾数据/packet、越界 validation log。
- **Execution record:** Actual result=`<执行后填写>`；Status=`NOT_EXECUTED`；Issue reference=`N/A`；Notes=`<填写距 max 的 octets>`。

## 13. W5300 Erratum 1

本节依据当前 `c2837x_w5300_channel.c`、`c2837x_w5300_socket.c` 和公开内部头文件。触发条件是当前 Socket 为 TCP 且 `Sn_TX_FSR != C2837xW5300Socket.tx_mem_size`。workaround 仅操作当前 Socket：临时 UDP OPEN → 确认 `SOCK_UDP` → 向 `0.0.0.1:5000` 发送 1 wire octet dummy → 观察 `Sn_IR_SENDOK` 或 `Sn_IR_TIMEOUT` → CLOSE → 确认 `SOCK_CLOSED`。各 `C2837X_W5300_CLOSE_*` 阶段跨多次 `Run` 推进，无全芯片 reset。（FR-263～FR-266）

当前 close 诊断可见的内部阶段依次为：

```text
C2837X_W5300_CLOSE_WAIT_EXISTING_CR
C2837X_W5300_CLOSE_CHECK_ERRATUM
C2837X_W5300_CLOSE_UDP_OPEN_ISSUE
C2837X_W5300_CLOSE_UDP_OPEN_WAIT_CR
C2837X_W5300_CLOSE_UDP_OPEN_WAIT_STATE
C2837X_W5300_CLOSE_DUMMY_WAIT_TX_SPACE
C2837X_W5300_CLOSE_DUMMY_SEND_ISSUE
C2837X_W5300_CLOSE_DUMMY_SEND_WAIT_CR
C2837X_W5300_CLOSE_DUMMY_SEND_WAIT_RESULT
C2837X_W5300_CLOSE_CLOSE_ISSUE
C2837X_W5300_CLOSE_CLOSE_WAIT_CR
C2837X_W5300_CLOSE_CLOSE_WAIT_STATE
C2837X_W5300_CLOSE_FAULTED
```

close transaction 相关 pending command 为 `C2837X_W5300_COMMAND_UDP_OPEN`、`C2837X_W5300_COMMAND_DUMMY_SEND` 和 `C2837X_W5300_COMMAND_CLOSE`。这些名称是当前源码诊断术语；未来实现变更时应以同一执行 commit 的头文件为准。

Erratum 证据至少记录当前 Socket、`Sn_TX_FSR`、当前 Socket TX 总容量、是否需要 workaround、UDP OPEN/`SOCK_UDP`、dummy send、SEND_OK/TIMEOUT、CLOSE/`SOCK_CLOSED`、close result、`faulted` 和 other Socket state。相关时再记录 `Sn_MR`、`Sn_CR`、`Sn_SSR`、`Sn_IR`、`Sn_RX_RSR`；不要求无关问题提供全部寄存器。

### ERRATUM-SENDOK — workaround dummy SEND_OK

- **Related FR:** FR-116、FR-240、FR-263～FR-266
- **Purpose:** 验证触发 Erratum 后 dummy SEND_OK 分支继续完成 CLOSE。
- **Prerequisites/Configuration:** Host fixture 或可控硬件条件使 TCP `Sn_TX_FSR` 小于/不同于当前 Socket TX 总容量，并使 dummy SEND 获得 `Sn_IR_SENDOK`。
- **Procedure:** 1) 记录 trigger；2) 重复调用 `Run`/channel close，每次记录 close stage；3) 观察 UDP OPEN、`SOCK_UDP`、dummy 1 octet SEND、SENDOK、CLOSE、`SOCK_CLOSED`；4) 观察 other Socket；5) close `DONE` 后由用户启动新 session。
- **Expected result:** SENDOK 后进入 CLOSE；当前 Socket closed，close=`DONE`；不长循环等待、不全局 reset、不修改 other Socket；后续当前实例可重新监听。
- **Required evidence:** 完整 stage/register timeline、close result、other Socket state、新 session 证据；若仅 Host fixture，硬件状态仍为 `USER_VALIDATION_PENDING`。
- **Execution record:** Actual result=`<执行后填写>`；Status=`NOT_EXECUTED`；Issue reference=`N/A`；Notes=`<Host/Hardware>`。

### ERRATUM-TIMEOUT — workaround dummy hardware TIMEOUT

- **Related FR:** FR-116、FR-240、FR-263～FR-266
- **Purpose:** 验证 dummy SEND 获得 `Sn_IR_TIMEOUT` 时仍继续 CLOSE。
- **Prerequisites/Configuration:** Host fixture、可控 stub 或硬件条件可产生 dummy SEND TIMEOUT event。
- **Procedure:** 按 ERRATUM-SENDOK 推进至 dummy result；注入/观察 `Sn_IR_TIMEOUT`；继续多次 `Run` 记录后续 CLOSE 和最终结果。
- **Expected result:** 不在 dummy SEND 永久等待；TIMEOUT event 清除后仍进入 CLOSE；最终依据 close 实际结果为 `DONE` 或 `ERROR/faulted`；其他 Socket 不受影响。注意“收到硬件 TIMEOUT event 后继续 CLOSE”不同于整个 close transaction 超过软件 deadline，后者应 fault。
- **Required evidence:** TIMEOUT event、close stage timeline、CLOSE/`SOCK_CLOSED`、final result/faulted、other Socket。
- **Execution record:** Actual result=`<执行后填写>`；Status=`NOT_EXECUTED`；Issue reference=`N/A`；Notes=`<Host/Hardware>`。

### ERRATUM-CLOSE-ERROR — close ERROR / faulted

- **Related FR:** FR-116、FR-131、FR-240、FR-263～FR-266
- **Purpose:** 验证 Erratum/close 失败只将当前通道置为 faulted，并实施恢复门禁。
- **Prerequisites/Configuration:** Host fixture、可控 driver stub 或可行硬件注入能使 close command/state/software deadline 失败；双实例优先。
- **Procedure:** 1) 在目标 Socket 的 close transaction 注入 ERROR 或无响应至软件 deadline；2) 记录 close stage、pending command、GetLastError、faulted 和 register access；3) 继续普通 `Run` 并尝试从 PC 新启动 simulation；4) 观察当前 Socket 不再 open/listen、other instance 继续；5) 执行一次失败 PlatformInit（如 fixture 支持）确认不恢复；6) 成功 PlatformInit 或 DSP reset 后再次观察当前 Socket。
- **Expected result:** 当前实例记录 `C2837X_BLOCK_ERROR_IODEVICE`；无全 W5300 reset、无其他 Socket 修改、无无限 close retry；当前 Socket 私有 `faulted`；普通重启 PC simulation 不能恢复；只有成功 PlatformInit 的新 generation 或 DSP reset 后才可再次 open/listen；公共 Core 仍使用通用 `WAIT_CONNECTION` 状态；other instance continues。
- **Required evidence:** error/deadline、`C2837X_W5300_CLOSE_FAULTED` 或等价、pending command、GetLastError、zero reopen/listen access、other Socket/instance、PlatformInit/reset recovery。
- **Execution record:** Actual result=`<执行后填写>`；Status=`NOT_EXECUTED`；Issue reference=`N/A`；Notes=`若无安全注入能力填 NOT_EXECUTED / CAPABILITY`。

## 14. 当前仓库可引用的真实测试入口

以下文件在本方案基线仓库中实际存在；执行前仍应以当前 commit 复核。本文只引用这些真实入口，不假定固定测试数量。

| 类别 | 真实入口/证据文件 | 用途 |
| --- | --- | --- |
| 总 runner | [`../../../tests/run_all_tests.m`](../../../tests/run_all_tests.m) | `protocol`、`app`、`dsp_host`、`pc` category；记录真实 count |
| App validation | [`../../../tests/app/test_project_validation.m`](../../../tests/app/test_project_validation.m) | 配置错误和路径边界 |
| Hash/CRC32 | [`../../../tests/app/test_interface_hash.m`](../../../tests/app/test_interface_hash.m)、[`../../../tests/app/test_crc32.m`](../../../tests/app/test_crc32.m) | canonical hash 与 golden |
| 文件保护 | [`../../../tests/app/test_preview_commit.m`](../../../tests/app/test_preview_commit.m)、[`../../../tests/app/test_candidate_files.m`](../../../tests/app/test_candidate_files.m) | Preview/commit、candidate/user-file 规则 |
| PC generation/build/atomic | [`../../../tests/app/test_sfun_build_candidates.m`](../../../tests/app/test_sfun_build_candidates.m)、[`../../../tests/app/test_sfun_step_candidates.m`](../../../tests/app/test_sfun_step_candidates.m) | build script 和输出原子性生成逻辑 |
| PC MEX/Normal-mode | [`../../../tests/pc/test_sfun_pc_integration.m`](../../../tests/pc/test_sfun_pc_integration.m) | MEX build、Normal-mode、错误场景 |
| PC Mock matrix | [`../../../tests/pc/run_sfun_pc_matrix.py`](../../../tests/pc/run_sfun_pc_matrix.py)、[`../../../tests/pc/sfun_mock_endpoint.py`](../../../tests/pc/sfun_mock_endpoint.py) | 当前 deterministic Mock scenarios |
| V1 protocol golden | [`../../../tests/protocol/test_legacy_v1_protocol_baseline.m`](../../../tests/protocol/test_legacy_v1_protocol_baseline.m) | frame/error-code baseline |
| Core protocol | [`../../../tests/dsp_host/test_s2_07_core_protocol.m`](../../../tests/dsp_host/test_s2_07_core_protocol.m) | type/state/length/step/lifecycle |
| DSP timeout/lifecycle | [`../../../tests/dsp_host/test_s2_08_timeout_lifecycle.m`](../../../tests/dsp_host/test_s2_08_timeout_lifecycle.m) | transfer/interaction timeout、cleanup、atomicity |
| 双实例隔离 | [`../../../tests/dsp_host/test_s2_09_dual_instance.m`](../../../tests/dsp_host/test_s2_09_dual_instance.m) | 独立状态、重复 session、局部错误 |
| SEND completion | [`../../../tests/dsp_host/w5300_send_completion_test.c`](../../../tests/dsp_host/w5300_send_completion_test.c) | pending segment、SENDOK/TIMEOUT |
| Erratum/close | [`../../../tests/dsp_host/w5300_close_erratum_test.c`](../../../tests/dsp_host/w5300_close_erratum_test.c) | SENDOK/TIMEOUT、deadline、fault gate、generation recovery |

MATLAB category runner 示例以 [`../../../tests/README.md`](../../../tests/README.md) 为准。独立 PC Mock 命令以 [`../../../tests/pc/README.md`](../../../tests/pc/README.md) 为准。只有实际执行后才能把对应软件用例标记 `PASS`；本方案编写本身不等于执行这些 suite。

## 15. S5-04 聚焦 FR trace

本表只追踪 S5-04 的测试、反馈和验收责任，不是 FR-001～FR-267 最终矩阵；完整最终追踪属于 S5-05。

| FR | 本文覆盖位置 |
| --- | --- |
| FR-233 | 第 2.1、6 节：交付方责任和软件回归 |
| FR-234 | 第 2.2、7～13 节：用户 CCS/DSP/硬件责任和验收用例 |
| FR-235 | 第 1、5.3 节：无证据不得 PASS |
| FR-236 | SW-GEN、SW-HASH、SW-FILE |
| FR-237 | SW-APP、SW-FILE、PAYLOAD-NEAR-MAX |
| FR-238 | DSP build、六种类型、single/dual、protocol、timeout、disconnect、IoDevice、near-max、isolation |
| FR-239 | SW-PC-ATOMIC 和验收模板 atomic-output detail |
| FR-240 | 第 3 节及 Erratum 用例：允许的自动化边界 |
| FR-241 | 第 16 节对问题反馈模板的引用 |
| FR-242 | 第 2.1 节：完整源码和文档交付范围 |
| FR-243 | 第 2.1 节和 SW-PC-MEX：源码交付，不以 MEX 二进制替代 |
| FR-244 | 第 2.1 节：不要求正式发布包 |
| FR-245 | 第 1、16 节：DSP 实机结论以用户真实验收记录为准 |
| FR-251 | 第 1、16 节：Stage 5 测试、反馈和验收材料边界 |
| FR-263 | 第 13 节：Erratum trigger 和处理目标 |
| FR-264 | 第 13 节：跨多次 Run 的非阻塞 close stages |
| FR-265 | TIMEOUT-TRANSFER-TX、IODEV-TX-FAIL、第 13 节：SEND completion 语义 |
| FR-266 | 第 5.3、DI-ISOLATION-02、ERRATUM-CLOSE-ERROR：faulted 和恢复门禁 |

## 16. 执行结束检查

1. 每个计划内 Test ID 都在验收记录中有明确状态；空白不算通过。
2. 所有 `NOT_EXECUTED`、`BLOCKED`、`USER_VALIDATION_PENDING` 项在专门章节列出原因和解除条件。
3. 每个 `FAIL` 都有 Issue reference，并使用 [问题反馈模板](problem_feedback_template.md)提供完整复现材料。（FR-241）
4. 软件、DSP compile、hardware、single-instance、dual-instance、error-path、Erratum 分开汇总，不用一项结果替代另一项。
5. DSP/W5300 最终结论只依据用户按本文执行并提交的真实验收记录。（FR-245）
6. 当前批次只产生测试/反馈/验收文档；Stage 5 最终 FR tracking 属于 S5-05，不在本文建立。（FR-251）
