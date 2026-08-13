# DSP-SimBridge SCI IoDevice 增量实施计划

> **计划状态：** Approved for Implementation
> **生成日期：** 2026-08-10
> **批准日期：** 2026-08-10
> **唯一需求基线：** `requirements/requirements_sci_iodevice_v1.0_frozen.md`
> **适用分支：** `feature/sci-iodevice-v1`
> **实施基线：** `91135a87160e18999f68b0ac262b8a35b656806f`
> **历史 V1.0 状态：** 多实例 W5300 的历史 G0～G5 已 PASS / CLOSED，本计划不重新执行，也不把 SCI 追加为旧计划 Stage 6。
> **V1 wire protocol 基线：** `f209302ce3efc0fa15d217550f6d9b1dc00487fb` / `legacy-v1-protocol-baseline`
> **实施对象：** DSP-SimBridge / C2837xBlock
> **计划命名规则：** 本增量周期使用 `SCI-Sx-yy` 和 `SCI-Gx`，与历史 `S0～S5 / G0～G5` 区分。
> **进度记录规则：** 本文件只定义任务、依赖、产物、最小验证和门禁，不回写实际完成状态。真实 HEAD、工作区、测试、编译、硬件和门禁结果只记录在任务移交摘要、动态上下文、Git 历史和真实日志中。

### Stage 1 Correction — SCI-S1-CORR-01

本纠正批次不新增 Stage、Gate 或 FR 编号：SCI capability 保存独立 RX/TX endpoint，废除 DSP-SimBridge Cartesian PinGroup；persisted Project schema 由 V3 升级为 V4。Wire Protocol 保持 V1，Core API target 保持 V2。V3 仅作为 migration source，旧 `pin_group` 只允许存在于 V3 migration parser。

---

## 1. 计划目标与执行规则

本计划只实现冻结 SCI 增量需求 FR-001～FR-095，目标是在已经完成的静态多实例 W5300 基线上新增 SCI IoDevice，并完成 Project V4、Core API V2、Capability、App、DSP SCI、Windows PC Serial S-Function、生成和必要文档适配。

本计划不重新实现已经关闭的 V1.0 多实例/W5300 基础能力。冻结需求未明确修改的 V1.0 行为继续复用现有实现和既有证据。

执行规则：

1. **一个对话只执行一个边界明确的任务批次。** 每个 `SCI-Sx-yy` 原则上对应一个独立实施/审核批次；每个 `SCI-Gx` 为独立只读门禁批次。
2. **开始任何实施任务前必须核对 Git。** 至少核对 repository、branch、HEAD、remote HEAD、`git status`、前置任务提交和前置门禁。
3. **冻结需求优先。** 不得通过计划解释改变 FR 语义，不得恢复旧单实例 Core、shared `g_ctx`、generic S-Function、共享 PC runtime、自动 reconnect/retry/resend、自动 MEX build 或其他废弃方案。
4. **V1 wire protocol 不变。** SCI 只增加 transport，不改变 Header、消息、错误码、step_index、Interface Hash 线缆语义或 framing。
5. **测试服务于研发目标。** 只执行证明 SCI 新功能和关键兼容边界所必需的最小验证；不建立多 SCI、全部 Baud、全部 RX/TX/CTRL GPIO、half-duplex、mixed 硬件或长期稳定性固定矩阵。
6. **不伪造环境能力。** 未实际执行的 MATLAB/MEX、DSP/CCS、Simulink 或硬件项目必须记录为 `NOT_EXECUTED` / `CAPABILITY` / `USER_VALIDATION_PENDING`，不得声明 PASS。
7. **硬件不是开发门禁的默认前提。** 最终 DSP/SCI/Baud/CTRL/mixed/长期稳定性实机验证由用户根据实际研发需要执行；开发侧无真实硬件证据时只能声明“已实现，待用户实机验证”。
8. **LSPCLK 分两阶段。** 实现与 bring-up 初期使用 `SYSCLK/14 ≈ 14.285714 MHz`；基础 SCI-PC 链路实现后再进行理论量化误差和平台影响评估，并在有条件时结合一个代表性实机结果，确定最终平台级固定 LSPCLK。最终值不预设必须为 200 MHz。
9. **Codex 不负责 Git 提交和分支操作。** Codex 只形成待审核工作区；提交、推送、分支和 Tag 操作由用户决定。
10. **本计划批准不代表任何实施或门禁已经通过。**

### 1.1 状态术语

| 状态 | 含义 |
|---|---|
| 未开始 | 尚未实施 |
| 已实现待审核 | 代码完成但尚未独立复核 |
| 已通过静态审核 | 结构、职责、生成合同或源码边界已审核 |
| 已通过 PC 测试 | MATLAB/MEX/host/mock 的实际测试通过 |
| 待用户 DSP 编译 | 需要用户在实际 C2000/CCS 环境编译 |
| 待用户实机验证 | 需要用户连接 TMS320F28377D/SCI/转换器验证 |
| 已通过用户验证 | 用户提供真实证据并确认通过 |
| `NOT_EXECUTED / CAPABILITY` | 当前环境缺少执行能力 |
| 阻断 | 需求冲突、实现失败或前置条件缺失 |
| 废弃 | 任务取消但编号保留 |

### 1.2 每个任务批次的最小交付信息

每个任务完成后必须记录：

- 任务编号与对应 FR；
- 实际修改文件；
- 关键设计决定；
- 实际执行的测试/检查、命令和真实结果；
- 未执行或无法验证项目；
- 当前 branch、HEAD、remote HEAD、`git status`；
- 已知问题；
- 下一批次允许和禁止执行的内容。

计划文件保持静态，不在任务完成后把任务状态逐项写回本文件。

---

## 2. SCI 增量实施起始基线

本增量基于已经完成的 V1.0 多实例 W5300 实现：

```text
Repository : VainSuns/DSP-SimBridge
Base HEAD  : 91135a87160e18999f68b0ac262b8a35b656806f
New Branch : feature/sci-iodevice-v1
V1.0 Gates : G0～G5 PASS / CLOSED
Protocol   : V1 immutable
Project    : V2
Core API   : V1
IoDevice   : W5300 TCP only
```

本计划实施前应把新的 SCI frozen requirements 和本计划切换为当前规范入口；旧 Rev.2 requirements、旧 plan 和旧 267-FR traceability 只保留历史追溯意义。

现有实现中需要保留的关键基线包括：

- 静态多实例 Core，不恢复 default instance/shared `g_ctx`；
- `PlatformInit()`、`Init(instance)`、`Run(instance)`、`GetLastError(instance)` 公共 API 形态；
- `C2837xBlock_IoDeviceOps` transport 抽象；
- V1 wire protocol、Interface Hash 和 step 语义；
- W5300 已关闭的 non-blocking、pending SEND、close/Erratum 和 faulted 行为；
- 每实例自包含 S-Function/MEX 生成结构；
- Preview/Snapshot/Commit 用户文件保护事务；
- 已关闭 hot-path 优化：DSP `Run()` 不重复完整静态校验、PC 每 step 不恢复 heap/full-copy、固定端口/元素/endian 继续由生成期展开。

---

## 3. 全局 FR 覆盖矩阵

| 需求范围 | 主要计划覆盖位置 |
|---|---|
| FR-001～FR-006 | SCI-S0、SCI-S2、SCI-S3、SCI-S5；架构/版本/兼容非回退 |
| FR-007～FR-013 | SCI-S1；Project V4、V2/V3 migration、conditional fields、COM 边界 |
| FR-014～FR-018 | SCI-S1；Capability、Platform Reserved Resources、resource conflict |
| FR-019～FR-030 | SCI-S1；App IoDevice-aware UI、defaults、copy、capability isolation |
| FR-031～FR-040 | SCI-S1、SCI-S2、SCI-S5；LSPCLK/BRR、PinMux、PlatformInit、SCI_INIT |
| FR-041～FR-050 | SCI-S2；公共 SCI driver、RX/TX/session、timeout、有界 Run |
| FR-051～FR-055 | SCI-S2；可选 half-duplex CTRL 运行合同 |
| FR-056～FR-070 | SCI-S4；COM 参数、Windows serial、S-Function lifecycle |
| FR-071～FR-075 | SCI-S4；PcError SERIAL、stage、OS error、cleanup |
| FR-076～FR-083 | SCI-S4；transport-specific S-Function generation、build、Update Diagram |
| FR-084～FR-090 | 各阶段最小验证 + SCI-S5 最终证据收敛 |
| FR-091～FR-095 | SCI-S0、全阶段非目标、SCI-S5 文档/治理 |

---

# 4. SCI Stage 0：规范基线切换与实施入口

Stage 0 不实现 SCI 产品功能，只把新的增量周期从历史 V1.0 周期中干净分离，并建立可以实施的唯一规范入口。

## SCI-S0-01：核对 SCI 分支与 V1.0 完成基线

- **对应 FR：** FR-005、FR-093～FR-095
- **前置任务：** 无
- **输入：** `feature/sci-iodevice-v1`、基线 `91135a87160e18999f68b0ac262b8a35b656806f`、V1 protocol tag/commit、当前仓库
- **目标：**
  1. 核对新分支确实从完成的 V1.0 基线开始；
  2. 核对工作区干净、remote 与 local 基线一致；
  3. 核对历史 `G0～G5` 已关闭且不作为本计划待执行门禁；
  4. 核对 V1 wire protocol tag/commit 仍存在且未漂移；
  5. 记录新 SCI 周期的实际起始 HEAD。
- **非目标：** 不修改产品代码；不实现 Project V4/SCI；不重新执行历史 G0～G5。
- **最小验证：** Git/remote/branch/HEAD/status、protocol baseline commit/tag、基线祖先关系。

## SCI-S0-02：切换 Repository 当前 requirements / plan 并归档历史入口

- **对应 FR：** FR-093～FR-095
- **前置任务：** SCI-S0-01
- **输入：** 新 frozen requirements、本计划、旧 Rev.2 requirements、旧完成 plan、仓库中的 current-spec 引用
- **Repository 目标：**
  1. 将 `requirements/requirements_sci_iodevice_v1.0_frozen.md` 作为当前唯一 frozen requirements；
  2. 用本计划替换根 `plan.md`；
  3. 旧 Rev.2 requirements、旧完成 plan 和历史 267-FR traceability 进入明确 historical/archive 状态，不再作为 current implementation authority；
  4. 保留完整 Git 历史和历史 G0～G5 追溯能力；
  5. 搜索并修正仓库中会让 Codex/开发者误把旧 requirements / old plan 当作 current authority 的必要引用。
- **固定归档策略：**
  - `requirements/requirements_multi_iodevice_v1.0_frozen_rev2.md` → `requirements/archive/requirements_multi_iodevice_v1.0_frozen_rev2.md`；
  - 旧根 `plan.md` → `docs/archive/plan_multi_instance_v1_completed.md`；
  - `docs/requirements_traceability.md` → `docs/archive/requirements_traceability_multi_instance_v1.md`；
  - 新当前入口固定为 `requirements/requirements_sci_iodevice_v1.0_frozen.md` 与根 `plan.md`；
  - 如仓库中现有链接必须同步调整，只做维持历史可追溯和消除 current-authority 歧义所必需的最小修改。
- **ChatGPT 项目来源维护边界：** `DSP-SimBridge_ChatGPT_Project_Instructions.md`、`DSP-SimBridge_Current_Dynamic_Context.md` 和当前 Stage 0 / SCI-G0 跨对话移交摘要由 ChatGPT/用户在 SCI-G0 关闭时同步维护；这些文件不属于研发仓库，不作为 Codex 修改目标，不进入 repository `git diff`，也不得复制或提交到 `VainSuns/DSP-SimBridge`。如继续维护 `DSP-SimBridge_Codex_Command_Guide.md`，只同步其工作方法示例/事实源路径，不作为产品 Gate。
- **非目标：** 不重写全部用户文档；不修改产品代码；不删除历史 Git 证据；不让 Codex 修改 ChatGPT Project Source 文件。
- **最小验证：** repository 搜索 current authority 引用；新 requirements/plan 可读取；固定 archive 路径存在且不再被标记为 current；`git diff --check`。

### SCI Stage 0 Gate：SCI-G0

必须确认：

- 新分支和起始 HEAD 已真实核对；
- 新 frozen requirements 与新 `plan.md` 是唯一当前研发入口；
- 历史 Rev.2 requirements / plan 只作历史追溯；
- V1 wire protocol baseline 未改变；
- Stage 0 未混入 SCI 产品实现；
- 本地工作区和实际提交状态记录真实；
- `SCI-G0` 通过并准备进入 Stage 1 时，分别确认两类证据：Repository 已完成当前规范入口切换与历史归档；ChatGPT/用户已将 `DSP-SimBridge_ChatGPT_Project_Instructions.md`、Dynamic Context 和 Stage 0 / SCI-G0 跨对话移交摘要同步到新分支、新 frozen requirements 和新 plan。ChatGPT Project Source 文件不得提交到研发仓库。

`SCI-G0` 与历史 `G0` 无关，不重新判定历史多实例阶段。

---

# 5. SCI Stage 1：Project V4、Capability 与 App 配置

Stage 1 先建立 SCI 的数据模型、器件能力、统一计算和用户配置边界，使后续 DSP/PC 生成只消费已经归一化和验证的 Project V4 数据。

## SCI-S1-01：建立 TMS320F28377D PTP Capability 与 loader

- **对应 FR：** FR-014～FR-017、FR-030
- **前置门禁：** SCI-G0
- **目标：**
  1. 新增唯一 `TMS320F28377D_PTP.json`；
  2. 只保存固定器件事实：SCI-A/B/C/D 的独立 RX/TX endpoint、GPIO/PinMux 能力，不计算或保存 PinGroup；
  3. 建立带 `schema_version` 的 MATLAB loader/normalizer；
  4. 其他 App/validator/generator 只消费 normalized capability，不直接依赖 raw `jsondecode`；
  5. W5300 EMIF/reset/GPIO 等固定占用保持 Platform Reserved Resources，不污染 capability；
  6. capability 缺失/损坏时可以明确禁用 SCI，但不得破坏 W5300-only 工作流；
  7. Capability 中的固定器件事实必须依据 TMS320F28377D PTP 的权威器件资料或当前 TI C2000 device-support 定义核对，并在 capability/维护文档或对应测试夹具中记录可追溯来源；不得根据记忆猜测 PinMux/GPIO 组合。
- **非目标：** 不支持其他 package/device；不做 `.mat` cache；不加入用户配置。
- **最小验证：** 正常 schema、unsupported schema、缺失/损坏 capability、W5300-only capability isolation，以及 capability 固定器件事实的来源可追溯性。

## SCI-S1-02：升级 Project V2/V3→V4 与 SCI Instance 模型

- **对应 FR：** FR-007～FR-013、FR-019、FR-023～FR-025、FR-029
- **前置任务：** SCI-S1-01
- **目标：**
  1. `project.format_version = 4`；
  2. 增加 `project.common.package='PTP'`；
  3. 保留 Project Network，但仅在存在 W5300 Instance 时参与有效性校验/生成；
  4. Instance 增加 `IoDevice=W5300 TCP/SCI` 与 SCI 配置字段；
  5. 新 Instance 默认 W5300；切换到 SCI 使用冻结默认值；
  6. V2/V3 自动迁移为 V4，全部旧 Instance 保持 W5300 语义且项目 dirty，不覆盖旧 `.mat`；V3 SCI canonical group 仅在 migration parser 中转换为独立 RX/TX；
  7. COM 不进入 Project；
  8. SCI Copy 不复制独占 Module/RX GPIO/TX GPIO/CTRL GPIO，CTRL 仍只有 `None/GPIOxx` 两态。
- **非目标：** 不实现 DSP/PC SCI runtime；不自动选择 SCI/RX GPIO/TX GPIO/CTRL GPIO。
- **最小验证：** V4 round-trip、V2/V3 migration、dirty、SCI defaults、copy、Network conditional semantics、COM 不进入 `.mat`。

## SCI-S1-03：建立统一 LSPCLK/BRR/Baud 计算服务

- **对应 FR：** FR-027、FR-031～FR-034
- **前置任务：** SCI-S1-02
- **目标：**
  1. 建立唯一 MATLAB 计算服务，输入项目级 LSPCLK 和 Requested Baud；
  2. 根据冻结公式在 DSP-SimBridge V1 固定合法候选范围 `1..65535` 内选择绝对 Baud Error 最小的整数 BRR；若存在完全相同的绝对误差，则选择较小 BRR；实现采用何种数学求解方式由实现者决定；
  3. 输出 BRR、Actual Baud、Baud Error；
  4. bring-up 初始平台配置采用 `SYSCLK/14 ≈ 14.285714 MHz`；
  5. 五个 Baud 均允许 Generate，不建立 error threshold；
  6. 服务允许后续 SCI-S5-02 替换最终平台 LSPCLK，而无需修改计算公式；
  7. `BRR=0` 是 TI 硬件特殊编码，但不纳入本项目 calculator candidate；首版 calculator 无需实现 `BRR=0` 的分段公式。
- **非目标：** 本任务不选择最终 LSPCLK；不根据 Baud 自动修改 timeout。
- **最小验证：** 五个支持 Baud 的 deterministic 计算、最小误差与 tie rule、非法输入；不验证私有求解步骤，不建立 Baud×LSPCLK 大矩阵。

## SCI-S1-04：实现 IoDevice-aware validation 与资源冲突检查

- **对应 FR：** FR-008～FR-009、FR-018、FR-025、FR-030
- **前置任务：** SCI-S1-01～SCI-S1-03
- **目标：**
  1. validation 合并 normalized capability、Platform Reserved Resources 和全部 Instance；
  2. 阻断重复 SCI Module；
  3. 阻断 RX/TX/CTRL GPIO 之间及与 W5300 固定资源的冲突；
  4. 阻断 capability 中不存在的 Module、RX GPIO、TX GPIO、CTRL GPIO 或 PinMux；
  5. SCI-only 项目不因 Network 非法失败；W5300 项目继续执行既有 Network 校验；
  6. capability 故障只阻断 SCI 项目/SCI 配置，不阻断 W5300-only。
- **非目标：** 不做运行时资源检测；不探测真实 GPIO 电气状态。
- **最小验证：** 关键重复/冲突、SCI-only Network bypass、W5300-only capability failure isolation。

## SCI-S1-05：重构 App 为 IoDevice-aware 配置界面

- **对应 FR：** FR-019～FR-030
- **前置任务：** SCI-S1-02～SCI-S1-04
- **目标：**
  1. 保留现有顶层 Project / Instances / Inputs/Outputs / Issues/Interface / Generation Preview；
  2. Selected Instance 详情形成 `General / IoDevice / Algorithm`；
  3. IoDevice 页面按 W5300/SCI 显示对应字段；
  4. RX GPIO、TX GPIO 和 CTRL GPIO 下拉由 capability 驱动；
  5. CTRL=None 时相关控件禁用/隐藏；
  6. 项目存在 SCI 时只读显示当前项目 LSPCLK；SCI Instance 显示 Requested/Actual/Error；
  7. Instance Table 与其他摘要使用统一 transport summary：`Socket 0 / TCP 5000` 或 `SCI-A / 57600 baud`；
  8. Module 改变时分别清空非法 RX/TX GPIO；不自动分配资源。
- **非目标：** 不测试像素尺寸/颜色/边距；不建立项目级 SCI-A/B/C/D 固定 Panel。
- **最小验证：** 用户行为和模型状态；UI 动态字段/默认值/summary；不做表现层像素测试。

### SCI Stage 1 Gate：SCI-G1

必须确认：

- V4 model / V2/V3 migration 可独立于 UI 测试；
- capability/schema/normalizer 边界清晰；
- W5300 Platform Reserved Resources 未写入器件 capability；
- 关键 resource conflict 能在 Generate 前发现；
- SCI-only 不被无效 Network 阻断；W5300-only 不被 SCI capability 故障阻断；
- App SCI 配置、copy、defaults、summary 与冻结需求一致；
- bring-up LSPCLK/BRR 计算单一且 deterministic；
- 未提前实现 DSP SCI 或 PC serial runtime。

---

# 6. SCI Stage 2：Core API V2 与 DSP SCI IoDevice

Stage 2 先用手写/测试 fixture 建立 Core V2 和公共 SCI IoDevice，不依赖正式 generator，从而先闭合 DSP 运行合同，再由 Stage 3 生成实际配置。

## SCI-S2-01：升级 Core API V2 与 PlatformResult

- **对应 FR：** FR-003～FR-006、FR-039
- **前置门禁：** SCI-G1
- **目标：**
  1. `C2837X_BLOCK_CORE_API_VERSION` 升为 2；
  2. 保留现有 expected-version compile gate，generated side 后续声明 expected=2；
  3. `C2837X_BLOCK_PLATFORM_ERROR_SCI_INIT = -5` 追加到现有枚举，不重排 0/-1/-2/-3/-4；
  4. 公共用户 API 形态保持不变；
  5. V1 wire protocol/Core message behavior 不变。
- **非目标：** 不实现 SCI peripheral；不修改 wire protocol；不恢复旧 API。
- **最小验证：** API/enum 静态审核、version mismatch compile fixture、V1 protocol existing evidence/minimal regression。

## SCI-S2-02：建立项目级 Platform SCI 配置合同与条件初始化

- **对应 FR：** FR-031、FR-037～FR-040、FR-042
- **前置任务：** SCI-S2-01
- **目标：**
  1. 为 PlatformInit 建立项目级 `use_w5300` + used SCI descriptors 的静态配置合同；
  2. bring-up 阶段有 SCI 时设置一次 `SYSCLK/14` LSPCLK；无 SCI 时不为 SCI 修改 LSPCLK；
  3. SCI-only 不执行 W5300 init；W5300-only 不执行 SCI init；mixed 初始化两者；
  4. mixed 任一 required resource init 失败则 PlatformInit fail，不要求 rollback；
  5. Instance `Init()` 不重复初始化 W5300/SCI/LSPCLK/PinMux/Timer2。
- **非目标：** 不实现 generator；本任务可先使用手写静态配置 fixture。
- **最小验证：** SCI-only/W5300-only/mixed 的调用边界；PlatformInit failure path；无 SCI 不改 LSPCLK。

## SCI-S2-03：实现公共 SCI descriptor、PinMux、FIFO 与 hardware init

- **对应 FR：** FR-035～FR-039、FR-041～FR-042
- **前置任务：** SCI-S2-02
- **目标：**
  1. 一套公共 SCI implementation 支持 A/B/C/D descriptor；
  2. const hardware config 与 mutable channel runtime 分离；
  3. 根据 descriptor 配置 RX/TX PinMux、pull-up、RX qualification、BRR、8N1、FIFO；
  4. 禁用 autobaud/loopback/interrupt/DMA，FIFO delay=0，polling；
  5. 可选 CTRL GPIO 初始化为 RX；
  6. 未使用 SCI/GPIO 不修改；
  7. `SCI_INIT` 只用于可实际检测的 descriptor/config 不一致，不伪造 register self-test；
  8. `channel_init()` 只重置当前 SCI Instance 的 mutable Channel Runtime、清理软件 pending 状态并保证 CTRL 回到 RX；不得重新初始化 SCI peripheral、重新设置 BRR/PinMux/LSPCLK，也不得修改其他 SCI Instance。
- **非目标：** 不做 read-back/loopback/外部设备探测；不增加中断/DMA。
- **最小验证：** descriptor/config 静态检查、可 host-test 的转换/分支；真实 TI 编译若未执行必须保持 pending。

## SCI-S2-04：实现 SCI logical connection、RX 与 session cleanup

- **对应 FR：** FR-043～FR-047、FR-050
- **前置任务：** SCI-S2-03
- **目标：**
  1. `CLOSED -> OPEN -> LISTENING` 逻辑状态；
  2. LISTENING 无 RX 时无限等待且不启动通信 timeout；
  3. 首个 RX octet 使 channel 报 CONNECTED，但不得被 connection probe 消耗；
  4. adapter 私下完成 8-bit serial octet ↔ C28x `Uint16`；Core 正进度仍为偶数 wire octet；
  5. 单 byte 可私有暂存并返回 0；
  6. 进入新 WAIT_SIM_START 前只执行一次 FIFO/error/pending cleanup；
  7. RXERROR/RXFFOVF 等严重错误结束当前 session，不 resync/retry；
  8. session close 后回到等待 SIM_START，不重新配置 peripheral/Baud/PinMux；
  9. SCI `close()` 只结束当前 logical session，并允许后续 `open -> listen -> WAIT_SIM_START`；不得模拟 TCP peer disconnect、产生 TCP-style disconnect semantics，也不得重新初始化 SCI hardware 或重新配置 Baud/PinMux/LSPCLK。
- **非目标：** 不增加 transport-specific timeout；不做 peer-connect 模拟等待。
- **最小验证：** 首 byte preservation、odd byte staging、one-time cleanup、RX error、bounded polling。

## SCI-S2-05：实现 SCI TX pending 与物理发送完成语义

- **对应 FR：** FR-048～FR-050
- **前置任务：** SCI-S2-04
- **目标：**
  1. 一个 Core `send(count_octets)` 对应一个完整 pending operation；
  2. FIFO 可跨多次 Run 填充，不等待 FIFO 空位；
  3. pending 期间不接受第二个 operation、不重复写入/发送；
  4. 只有全部 octets 且最后 stop bit 物理发送完成后，`send()>0` 才一次性返回完整 `count_octets`；
  5. 所有 Run 可达路径有界，不等待 TX/TXEMPTY、不使用 `delay_us()`；
  6. 继续使用现有 Core transfer timeout，不自动根据 Baud/LSPCLK/Payload 调整。
- **非目标：** 不增加 SCI-specific TX timeout、自适应 timeout 或 retry。
- **最小验证：** pending progression、no duplicate、physical-complete gate、bounded calls。

## SCI-S2-06：实现可选 Half-duplex CTRL 状态

- **对应 FR：** FR-051～FR-055
- **前置任务：** SCI-S2-05
- **目标：**
  1. CTRL=None 走普通 SCI；GPIOxx 时启用 DSP half-duplex direction；
  2. 新 send 首次切 CTRL→TX 并返回 0；
  3. pending 未完成保持 TX；
  4. 最后 stop bit 完成后切 RX，再返回正进度；
  5. receive 仅在 RX 状态；状态矛盾按 IoDevice error；
  6. abort/error/termination 强制 CTRL→RX；
  7. PC 不用 RTS/DTR 做方向控制。
- **非目标：** 不增加 DE setup delay 配置；不要求为该功能建立强制专项测试矩阵。
- **最小验证：** 必须完成代码合同/源码审核；若现有低成本 host fixture 能自然覆盖关键状态则执行并记录，但不得为了增加覆盖率专门扩建复杂测试框架。硬件保持用户验证。

### SCI Stage 2 Gate：SCI-G2

必须确认：

- Core API=2、expected version compile gate 有效；
- PlatformResult 旧数值未重排，SCI_INIT=-5；
- 公共 Core 不增加第二套 transport API；
- SCI hardware config/runtime 静态独立，无 malloc/shared mutable runtime；
- SCI-only/W5300-only/mixed PlatformInit 责任边界正确；
- RX 首 byte、odd-byte staging、session cleanup、TX pending/physical-complete 语义闭合；
- Run 可达 SCI 路径无固定等待/长轮询；
- half-duplex 代码合同实现，但不把专项硬件测试升级为门禁；
- 未实际进行的 CCS/硬件验证真实标记 pending。

---

# 7. SCI Stage 3：DSP 生成与 IoDevice 条件依赖

Stage 3 把 Stage 1 的 Project V4/Capability 和 Stage 2 的 Core/SCI runtime 接入正式 DSP candidate generation。

## SCI-S3-01：扩展 DSP 输出模型与项目级 Platform Config

- **对应 FR：** FR-004、FR-009、FR-012、FR-038～FR-040
- **前置门禁：** SCI-G2
- **目标：**
  1. generator 从 V4 project 计算项目是否使用 W5300、使用哪些 SCI；
  2. 生成项目级 Platform config/descriptor；
  3. generated header 声明 `C2837X_BLOCK_EXPECTED_CORE_API_VERSION = 2`；
  4. generated platform config 包含当前 bring-up LSPCLK/必要 SCI descriptors；
  5. 不把 COM 写入 DSP generation。
- **非目标：** 不生成 PC serial；不修改 protocol V1。
- **最小验证：** SCI-only/W5300-only/mixed output model、expected Core API V2、COM absence。

## SCI-S3-02：生成 SCI Instance 静态绑定与硬件配置

- **对应 FR：** FR-002、FR-009、FR-012、FR-031～FR-037、FR-041
- **前置任务：** SCI-S3-01
- **目标：**
  1. SCI Instance 生成 module、BRR、独立 RX endpoint、独立 TX endpoint、Pin Type、RX Qualification、CTRL GPIO/polarity 的 const config；
  2. BRR/Actual/Error 由 Stage 1 单一计算服务提供；DSP runtime 不重新计算；
  3. Instance IoDevice binding 继续使用现有 ops+channel；
  4. 每 Instance mutable channel 独立；
  5. Interface Hash 不因 SCI hardware config 改变。
- **非目标：** 不在 runtime 切换 transport；不生成 Instance ID 进入 wire。
- **最小验证：** 一个代表性 SCI generated config、hash invariance、symbol isolation。

## SCI-S3-03：按 IoDevice 收敛 DSP source / dependency

- **对应 FR：** FR-006、FR-038
- **前置任务：** SCI-S3-01～SCI-S3-02
- **目标：**
  1. SCI-only candidate/source list 不要求 W5300 driver/HAL；
  2. W5300-only 不要求 SCI driver；
  3. mixed 同时包含两类依赖；
  4. 不恢复共享或自动扫描源码；
  5. W5300-only generation 保持既有文件和行为，除本增量明确要求外不改动 hot path。
- **非目标：** 不要求生成 CCS 工程文件。
- **最小验证：** 三种 project 类型的 deterministic source/dependency set；无多 SCI组合矩阵。

## SCI-S3-04：接入 Preview/Snapshot/Commit 与关键 deterministic generation

- **对应 FR：** FR-006、FR-012、FR-018、FR-038、FR-084～FR-088
- **前置任务：** SCI-S3-01～SCI-S3-03
- **目标：**
  1. SCI hardware config 变化使相关 candidate/snapshot 失效；
  2. resource validation 在写盘前阻断冲突；
  3. SCI-only、W5300-only、mixed 生成结果 deterministic；
  4. 用户文件 Keep/Replace、Preview no-write、Commit transaction 继续复用 V1.0 服务；
  5. 不机械重跑未修改的 V1.0 全套测试。
- **非目标：** 不构建 MEX；不执行硬件。
- **最小验证：** 三种关键 generation、重复生成一致性、snapshot invalidation、关键 conflict rejection。

### SCI Stage 3 Gate：SCI-G3

必须确认：

- Project V4→generated Platform/SCI config 责任链闭合；
- Core API expected version=2；
- SCI-only / W5300-only / mixed 的 DSP source dependency 符合冻结需求；
- W5300-only 未被无关 SCI dependency/capability 破坏；
- SCI hardware 配置不进入 Interface Hash；
- Preview/Snapshot/Commit 继续 deterministic 且无无关回退；
- 没有恢复 hot-path 全量 validation/heap/full-copy；
- 未实际执行的 DSP CCS 编译保持 pending。

---

# 8. SCI Stage 4：Windows PC Serial 与 SCI S-Function

Stage 4 在既有 instance-specific S-Function/V1 protocol 基础上新增 self-contained Windows serial transport，不复制第二套 protocol。

## SCI-S4-01：实现 self-contained Windows `pc_serial` transport

- **对应 FR：** FR-059、FR-061～FR-068、FR-071～FR-073、FR-091～FR-092
- **前置门禁：** SCI-G3
- **目标：**
  1. 新建实例前缀 `pc_serial.c/.h` transport；
  2. 使用 Win32 serial API 或等价 self-contained C 实现 COM open/close/config/purge/read/write；
  3. 8N1、无 flow control，DTR/RTS 不用于协议/方向控制；
  4. COM10+ path 在内部处理；
  5. 实现 write-all/read-exact 与 partial I/O；
  6. 每个 send/recv operation 使用单一 monotonic deadline，partial progress 不重启 timeout；
  7. 保留 numeric Windows `os_error` 和可获得的 system text；
  8. `rtiostream_serial.c` 仅作为可用参考或等价实现依据，不依赖 MathWorks 私有 serial binary；
  9. 不依赖 Instrument Control Toolbox/Python/pySerial/第三方 serial library；
  10. `pc_serial` 只提供 raw V1 protocol octet stream，不增加 SOF/Magic/CRC/terminator/SLIP/COBS/额外 length prefix 或第二套 serial framing；Protocol 只请求和消费当前 Header 或当前 Payload 所需的确切 byte 数，不通过 `read all available` 建立第二套 frame parser；
  11. 禁用 software flow control；DTR/RTS 不承担协议或 RS485 direction，并在平台允许时保持 inactive。
- **非目标：** 不做 COM 枚举、VID/PID、auto reconnect、RS485 RTS/DTR direction。
- **最小验证：** 可注入/模拟的 partial read/write、deadline、COM path/error formatting；不需要真实硬件。

## SCI-S4-02：扩展 PcError 与稳定 Serial stage

- **对应 FR：** FR-065、FR-071～FR-075
- **前置任务：** SCI-S4-01
- **目标：**
  1. PcError 追加 `SERIAL`，旧编号不重排；
  2. 稳定 stage 至少区分 `serial_open / serial_configure / serial_purge / send_frame / recv_header / recv_payload / wait_response / wait_output_data`；
  3. partial-frame timeout 归 TIMEOUT 并报告 expected/actual length；
  4. USB/handle/ReadFile/WriteFile failure 归 SERIAL，不伪装 TCP DISCONNECT；
  5. 主错误不被 terminate cleanup error 覆盖；
  6. SCI 用户可见错误至少包含 `instance / COM / generated Requested Baud / stage / category`；处于 step 时继续包含 `step_index`；适用时继续包含 `expected_length / actual_length / os_error / Windows system error text`。
- **非目标：** 不建立长期日志、packet trace 或 history ring buffer。
- **最小验证：** 在现有 representative error-format focused validation 中验证一个或少量代表性 `SERIAL/TIMEOUT/protocol` 错误的字段、stage、length 与 os_error；不扩张错误组合矩阵。

## SCI-S4-03：生成 SCI S-Function 参数合同与 lifecycle

- **对应 FR：** FR-056～FR-065、FR-068～FR-070、FR-074～FR-078、FR-081～FR-083
- **前置任务：** SCI-S4-01～SCI-S4-02
- **目标：**
  1. W5300 S-Function 保持 0 transport parameter；SCI S-Function 固定 1 个 non-tunable `COM Port Number`；
  2. Update Diagram 只做 COM 正整数标量和 compile-time port/type/sample-time 校验，不 open/enumerate COM；
  3. `mdlStart`: validate COM→context→open/configure→purge once→SIM_START→RESPONSE(OK)→step=0；
  4. `mdlOutputs` 保持同步单 step 与原子输出；
  5. `mdlTerminate` best-effort SIM_STOP、不等 response、close；
  6. 不 reconnect/retry/resend/pipeline/thread；
  7. COM 不编译进 generated config，Baud 编译进去；PC COM 必须配置 generated **Requested/Nominal Baud**，不得使用 DSP 量化后的 Actual Baud；
  8. 保留现有 `CONNECT_TIMEOUT_MS / STEP_TIMEOUT_MS / TERMINATE_TIMEOUT_MS` 三个 user-config timeout：SCI 不使用 CONNECT_TIMEOUT 虚构 peer-connect 等待；SIM_START send 与 RESPONSE receive、INPUT_DATA send 与 OUTPUT_DATA receive 各自使用独立的 STEP_TIMEOUT operation deadline，partial progress 不重启 deadline；SIM_STOP best-effort send 使用 TERMINATE_TIMEOUT；
  9. serial open/configure 后不增加固定 sleep，不发送 bootloader `'A'` autobaud handshake；
  10. 同 COM 冲突依赖 OS exclusive open；不建全局 registry；
  11. 正常一个 generated instance block 只放一次，可选 per-MEX duplicate guard 但不共享 runtime。
- **非目标：** 不自动修改 `.slx`；不支持非 Windows/非 Normal mode；不增加 serial-specific timeout 宏。
- **最小验证：** generated block parameter contract、Requested Baud 配置、三类 timeout/deadline 合同、lifecycle static/host fixture、W5300 0-param regression。

## SCI-S4-04：生成 transport-specific 文件与 MEX build script

- **对应 FR：** FR-076～FR-083
- **前置任务：** SCI-S4-03
- **目标：**
  1. W5300 Instance 只生成/编译 `pc_socket`；SCI Instance 只生成/编译 `pc_serial`；
  2. protocol 继续使用同一 V1 template/逻辑，不分裂为 TCP/SCI 两份长期实现；
  3. build script 显式列源文件，不使用 `dir('*.c')`；
  4. Windows/prerequisite preflight 在删除旧 MEX 前完成；
  5. App 只生成 build script，不自动运行 mex 或改 Path/模型；
  6. W5300↔SCI 后 block parameter contract 变化由用户更新 `.slx`。
- **非目标：** 不自动 Build MEX；不自动安装编译器。
- **最小验证：** SCI/W5300 candidate file lists、explicit build source list、preflight behavior、deterministic text。

## SCI-S4-05：完成代表性 SCI 软件闭环与独立 MEX build 证据

- **对应 FR：** FR-058～FR-075、FR-084～FR-090
- **前置任务：** SCI-S4-01～SCI-S4-04
- **目标 A——代表性 SCI 软件闭环：** 使用一个代表性 SCI 配置，直接执行本阶段实际生产 `protocol + pc_serial` 代码（或 generator 输出的同一实际生产 C 源），完成开发侧最小软件验证：
  1. serial partial read/write；
  2. monotonic absolute deadline；
  3. SIM_START + RESPONSE(OK)；
  4. 单步 INPUT_DATA→OUTPUT_DATA；
  5. 与本增量直接相关的关键 serial/protocol error；
  6. 错误时输出不部分更新、step 不错误增加、session 结束。
- **目标 B——SCI MEX build：** 若当前 MATLAB 已配置 C MEX compiler，至少真实构建一个 generated SCI MEX，以证明 generated SCI S-Function + `pc_serial` + protocol 能在目标 MATLAB/MEX 环境成功编译和链接；不要求为了 MEX 再重复完整代表性协议闭环。若当前无 C MEX compiler，记录 `SCI_MEX_BUILD = NOT_EXECUTED / CAPABILITY`，不得宣称 PASS。
- **实现方式边界：** 可以使用低成本 host/mock serial backend、virtual COM、syscall injection、测试桩或 Windows 可控 endpoint 替代外部硬件/OS 对端，但不得另写一套与生产代码平行的 serial/protocol 实现来取得 PASS；mock 只能替代外部环境，不得替代被测产品代码。不得为了测试扩建产品级通信框架。
- **不要求：** 2×SCI、SCI-A/B/C/D 组合、全部 Baud、全部 RX/TX/CTRL GPIO、half-duplex CTRL、长期稳定性或硬件矩阵；MEX build 与代表性 protocol+pc_serial 软件闭环是两个独立证据。

### SCI Stage 4 Gate：SCI-G4

必须确认：

- Windows self-contained serial transport 完成；
- partial I/O 与 absolute deadline 行为有真实软件证据；
- SCI S-Function 只有 COM runtime parameter，Baud 来自 generation；
- `mdlStart/Outputs/Terminate` 与现有 V1 lifecycle 保持一致；
- `SERIAL/TIMEOUT/protocol` 错误分类和 stage 可诊断；
- W5300 继续 0-param / pc_socket，protocol 未复制分叉；
- 一个直接经过生产 `protocol + pc_serial` 的代表性 SCI 软件闭环已完成；
- SCI MEX build 作为独立证据：只在环境有 capability 时要求真实构建一个，不要求重复完整协议闭环；
- 不把无硬件条件解释为 Gate failure，也不宣称硬件 PASS。

---

# 9. SCI Stage 5：LSPCLK 收敛、集成文档与最终追踪

Stage 5 在 DSP 和 PC 基本链路实现完成后选择最终平台 LSPCLK，更新最终生成配置与用户文档，并完成 95 条增量需求追踪。

## SCI-S5-01：整理增量集成证据与最终收敛输入

- **对应 FR：** FR-001～FR-006、FR-038、FR-076～FR-090
- **前置门禁：** SCI-G4
- **目标：**
  1. 汇总 SCI-G1～SCI-G4 已有真实测试和审核证据；
  2. 判断相关代码未修改时哪些既有证据可以直接复用；
  3. 检查 Stage 4 是否实际修改 Stage 3 generator 或 DSP generation 关键路径；
  4. 只有相关实现发生变化时，才执行对应 focused regression；
  5. 整理当前 MEX、DSP/CCS、Simulink、SCI hardware、LSPCLK hardware confirmation 的真实执行或 pending 状态；
  6. 为 SCI-S5-02 最终 LSPCLK 收敛确定需要重新生成和验证的最小范围。
- **默认规则：** 不重新执行 SCI-only / W5300-only / mixed 全套 generation；只有存在实际影响时才执行对应必要回归。最终 LSPCLK 修改后的必要 generation/regression 统一在 SCI-S5-02 完成。
- **非目标：** 不机械重跑 Stage 3 或旧 V1.0 全套；不增加组合矩阵；不把历史 PASS 重新包装成当前新测试。
- **最小验证：** 证据来源、代码影响判断和 pending 状态与实际仓库/测试记录一致；只有发现真实影响时执行对应 focused regression。

## SCI-S5-02：评估并固定最终项目级 LSPCLK

- **对应 FR：** FR-027、FR-031～FR-034、FR-050、FR-084～FR-090
- **前置任务：** SCI-S5-01
- **目标：**
  1. 以 TMS320F28377D 当前实际 SYSCLK/clock source 为输入，列出合法 LSPCLK prescaler；
  2. 对五个支持 Baud 计算各候选的理论 BRR/Actual Baud/Error；
  3. 结合平台共享 LSPCLK 影响，选择最终固定 LSPCLK；
  4. 若用户此时具备硬件条件，可提供一个代表性 `/14` SCI-PC bring-up 结果作为辅助证据；若无硬件，不阻断理论收敛，但保持实际确认 pending；
  5. 不建立 Baud×LSPCLK、SCI Module 或硬件组合矩阵；
  6. 将最终 LSPCLK 同步到 App 只读显示、统一 BRR 服务、generated DSP Platform config 和 PC diagnostics；
  7. 不根据最终 LSPCLK 自动修改 DSP/PC timeout。
- **重要边界：** 最终值可以是 200 MHz，也可以是更合适的较低值；不得在评估前预设最大值。
- **最小验证：** 理论计算可复现；更新后一个代表性 SCI generation/软件路径与 W5300-only focused regression。

## SCI-S5-03：更新 SCI / Project V4 / CCS / Simulink 使用文档

- **对应 FR：** FR-007～FR-013、FR-019～FR-030、FR-031～FR-040、FR-055～FR-070、FR-076～FR-083、FR-089～FR-095
- **前置任务：** SCI-S5-02
- **目标：** 更新现有文档而不是建立第二套冲突文档，至少说明：
  1. Project V4 与 V2/V3 migration；
  2. SCI capability/Module/RX GPIO/TX GPIO/CTRL 配置；
  3. 当前最终 LSPCLK、Baud/Actual/Error 的意义；
  4. CCS 需要加入的 SCI/W5300 条件 source/HAL 和实际 pin/CTRL 集成责任；
  5. Simulink SCI Block 的 COM Port Number 参数；
  6. Windows-only / Normal mode / no auto reconnect；
  7. timeout 由用户配置，不自动按 Baud/Payload 适配；
  8. 用户硬件验证边界；
  9. W5300-only 既有使用路径继续有效。
- **非目标：** 不把未执行硬件写成 PASS；不要求安装包/CI/自动烧录。
- **最小验证：** 文档链接/API/字段/文件名与仓库实际实现一致。

## SCI-S5-04：完成 FR-001～FR-095 最终追踪与 SCI Final Audit

- **对应 FR：** FR-084～FR-095 以及全部 FR
- **前置任务：** SCI-S5-01～SCI-S5-03
- **目标：**
  1. 为 95 条 FR 建立逐条实现文件/状态/验证方式/备注；
  2. 明确哪些为软件 PASS、哪些为待用户 DSP 编译/实机、哪些为 capability 未执行；
  3. 确认历史 267-FR traceability 只属于 V1.0 历史周期；
  4. 审核 current normative references 已收敛到新 requirements + 新 plan；
  5. 审核 V1 wire protocol 与 W5300/hot-path 不发生非授权回退；
  6. 输出 SCI 周期最终动态上下文/跨对话移交事实，不把 ChatGPT 文件提交到仓库。
- **非目标：** 不为了让追踪表“全 PASS”而补做未要求的硬件矩阵或伪造结果。
- **最小验证：** FR count=95、missing=0、duplicate=0；repository paths valid；真实测试与 pending 状态一致；`git diff --check` / final status。

### SCI Stage 5 Gate：SCI-G5

最终 Gate 应确认：

- FR-001～FR-095 全部有实现/状态/证据映射；
- Project V4、Capability、App、Core API V2、DSP SCI、PC Serial、generation 和文档链闭合；
- 最终项目级 LSPCLK 已经选择并写入正式平台配置；若未有用户硬件证据，实际 LSPCLK 硬件确认仍明确 pending；
- 开发侧最小必要 SCI 软件闭环有真实证据；
- W5300-only / SCI-only / mixed 的 Stage 3 deterministic generation 证据仍有效；若后续相关代码发生变化，则对应必要 focused regression 已真实执行并通过；
- 无多 SCI、全部 Baud、全部 RX/TX/CTRL GPIO、half-duplex、mixed 实机或长期稳定性矩阵门禁；
- 未实际执行的 DSP/CCS/MEX/Simulink/hardware 项目均真实标记；
- 当前规范不再把历史 Rev.2 requirements / 旧 plan 当作 current implementation authority；
- V1 wire protocol 和已关闭 hot-path 基线未回退。

`SCI-G5 = PASS` 表示本增量的软件实施、文档和证据边界闭合，不等于用户所有 DSP/SCI 硬件验证已经完成。

---

## 10. 建议提交序列

以下仅为建议提交分组；实际可按任务规模继续拆分，但不得把多个 Stage 混成不可审核的大提交。

| 提交组 | 建议提交信息 | 主要范围 |
|---|---|---|
| SCI-0 | `docs: establish sci extension baseline` | SCI-S0-01～SCI-S0-02 |
| SCI-1A | `app: add f28377d capability and project v3` | SCI-S1-01～SCI-S1-02 |
| SCI-1B | `app: add sci baud validation and configurator` | SCI-S1-03～SCI-S1-05 |
| SCI-2A | `dsp: add core api v2 and sci platform config` | SCI-S2-01～SCI-S2-03 |
| SCI-2B | `dsp: add sci polling channel runtime` | SCI-S2-04～SCI-S2-06 |
| SCI-3 | `generator: add sci dsp generation and dependencies` | SCI-S3-01～SCI-S3-04 |
| SCI-4A | `sfun: add windows serial transport` | SCI-S4-01～SCI-S4-02 |
| SCI-4B | `sfun: add sci lifecycle generation and build` | SCI-S4-03～SCI-S4-05 |
| SCI-5 | `docs: converge sci lspclk and acceptance` | SCI-S5-01～SCI-S5-04 |

提交、推送和 Tag 均由用户审核后执行，Codex 不自动执行。

---

## 11. 关键风险与控制

| 风险 | 控制措施 |
|---|---|
| 新 SCI 需求重新扩张为完整 V1.0 重构 | 计划只映射 FR-001～FR-095；历史 V1.0 仅做必要回归 |
| 历史 G0～G5 与新 Gate 混淆 | 新周期统一使用 `SCI-G0～SCI-G5`、`SCI-Sx-yy` |
| Capability 混入板级 W5300 占用 | 器件 capability 与 Platform Reserved Resources 分层 |
| capability 故障破坏 W5300-only | SCI capability failure isolation 为 SCI-G1 必查项 |
| SCI 配置引入 Runtime 动态切换 | Instance 在 Generate 时静态绑定 IoDevice/Module |
| LSPCLK 过早写死为 /14 或 200 MHz | /14 只做 bring-up；SCI-S5-02 后再选择最终值 |
| Baud/timeout 被做成自动可靠性机制 | 冻结禁止 Baud×Payload×Timeout 自动适配；timeout 仍由 user config |
| C28x 16-bit char 与 serial octet 混淆 | SCI adapter 私有完成 octet↔Uint16，Core 仍以 wire octet 长度工作 |
| 首个 RX byte 被连接探测消费 | SCI-S2-04 明确 first-byte-preservation fixture |
| SCI send 过早返回导致 Core step 提前推进 | 只有最后 stop bit 完成后才提交正进度 |
| Half-duplex 提前切 RX | 物理 TX complete 后才 CTRL→RX；错误强制 RX |
| 为 half-duplex 扩张测试框架 | 只做低成本自然覆盖；硬件专项不作为强制门禁 |
| PC serial partial I/O 重启 timeout | 单一 monotonic absolute deadline |
| USB/serial 错误被错误分类为 TCP disconnect | PcError SERIAL + os_error；partial timeout 仍 TIMEOUT |
| TCP/SCI 复制成两套 protocol | protocol template/逻辑保持单一实现 |
| SCI-only 仍被迫链接 W5300 HAL | SCI-S3-03 source/dependency gate |
| W5300 hot-path 被 SCI 修改回退 | SCI-G3/SCI-G5 做 focused static/regression audit |
| 测试范围膨胀 | 只要求一个代表性 SCI 软件闭环，不建立组合矩阵 |
| 无硬件时伪造通过 | 所有 hardware 结果必须来自用户真实证据，否则 pending |

---

## 12. 本计划完成定义

SCI 增量计划完成必须同时满足：

1. `SCI-G0～SCI-G5` 全部通过；
2. 当前 repository authority 已切换为新 SCI frozen requirements + 新 `plan.md`；
3. Project V4 和 V2/V3→V4 migration 完成；
4. TMS320F28377D PTP capability 与 resource validation 完成；
5. App 完成 IoDevice-aware SCI 配置；
6. Core API V2、SCI Platform/driver/runtime 完成；
7. DSP generator 完成 SCI-only/W5300-only/mixed 条件生成与依赖收敛；
8. Windows `pc_serial` 与 SCI instance-specific S-Function 完成；
9. 开发侧一个代表性 SCI 软件闭环和关键错误路径具有真实证据；
10. 若当前 MATLAB 具备 MEX compiler，至少一个 SCI MEX 已真实构建并证明 generated SCI S-Function + `pc_serial` + protocol 可编译链接；否则保持 `NOT_EXECUTED / CAPABILITY`；该 MEX build 不要求重复完整代表性协议闭环；
11. 最终项目级 LSPCLK 已经过理论/平台必要评估后确定并写入正式配置；硬件确认若未执行保持待用户验证；
12. FR-001～FR-095 逐条 traceability 无缺失；
13. W5300/V1 protocol/hot-path 不发生非授权回退；
14. 未实际执行的 DSP/CCS/Simulink/hardware 项目没有被标记为 PASS；
15. 不存在被误标为 current authority 的历史旧 plan / Rev.2 requirements。

---

## 13. 明确不进入本计划的内容

本计划不包含：

- CRC、ACK/NAK、frame retry、byte retransmission；
- 自动 reconnect / resend / resync；
- watchdog recovery；
- autobaud；
- SCI interrupt / DMA；
- COM 枚举、VID/PID、自动匹配；
- 软件 RTS/DTR RS485 direction；
- Linux/macOS serial；
- ZWT/PZP / 多器件 capability；
- Baud × Payload × Timeout 自动适配/推荐/Warning/Reject；
- 多 SCI/2×SCI 固定测试；
- SCI-A/B/C/D 组合矩阵；
- 全部 Baud/RX/TX/CTRL GPIO 硬件矩阵；
- half-duplex CTRL 强制专项测试矩阵；
- mixed IoDevice 硬件门禁；
- 长期稳定性门禁；
- 自动 MEX build；
- 自动改写 Simulink `.slx`；
- CCS 工程生成、自动烧录、CI 硬件自动化；
- 安装包、Toolbox、正式 release 系统；
- 重新执行历史 V1.0 G0～G5。

---

## 14. 计划批准结论

本计划已经完成用户审核和 Final Plan Audit，状态更新为：

```text
Approved for Implementation
```

Final Plan Audit 结论：

```text
FR_NUMBER_COVERAGE              = PASS
STAGE_DECOMPOSITION             = PASS
DEPENDENCY_ORDER                = PASS
PROJECT_V4_COVERAGE             = PASS
CAPABILITY_COVERAGE             = PASS
APP_COVERAGE                    = PASS
CORE_API_V2_COVERAGE            = PASS
DSP_SCI_RUNTIME_COVERAGE        = PASS
PC_SERIAL_COVERAGE              = PASS
GENERATION_COVERAGE             = PASS
LSPCLK_SEQUENCE                 = PASS
V1_PROTOCOL_COMPATIBILITY       = PASS
W5300_NON_REGRESSION_BOUNDARY   = PASS
USER_HARDWARE_BOUNDARY          = PASS
MINIMUM_TEST_BOUNDARY           = PASS
PROJECT_SOURCE_BOUNDARY         = PASS

PLAN_FINAL_AUDIT                = PASS
PLAN_APPROVAL                   = ALLOWED
```

批准结论只表示：

- Stage 划分、任务边界、依赖、FR 覆盖和 Gate 定义已经确定；
- LSPCLK `/14 bring-up → 最终收敛` 顺序已经确定；
- 开发侧最小必要测试边界已经确定；
- 历史 V1.0 不作为 Stage 6 或重新实施对象；
- Repository 与 ChatGPT Project Source 的责任边界已经分离。

批准结论**不表示** `SCI-S0-01` 已执行、`SCI-G0` 已通过，也不表示任何软件测试、DSP/CCS 编译、MEX、Simulink 或 SCI 硬件验证已经通过。

实际实施必须从 `SCI-S0-01` 开始；开始前按项目规则重新核对 repository、branch、HEAD、remote HEAD、`git status`、V1.0 完成基线和当前规范入口。
