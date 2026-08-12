# DSP-SimBridge SCI IoDevice 增量需求规格

> **状态：Frozen V1.0**  
> **冻结日期：2026-08-10**  
> **适用项目：DSP-SimBridge / C2837xBlock**  
> **增量目标：在已完成的多实例 W5300 基线上新增 SCI IoDevice，并完成 Project V3、Core API V2、App 和 PC/S-Function 的必要适配。**

---

## 0. 文档定位与继承基线

本文件是 **SCI IoDevice 增量需求**。它只定义本次新增功能，以及为支持 SCI 必须修改的既有合同；V1.0 已经实现且本文件未明确修改的行为继续沿用，不在本文件重复列为 FR。

历史已完成基线：

- Repository：`VainSuns/DSP-SimBridge`
- Branch：`feature/multi-instance-v1`
- 已完成实现基线 HEAD：`91135a87160e18999f68b0ac262b8a35b656806f`
- V1.0 多实例实施：`G0～G5 PASS / CLOSED`
- 历史需求：`requirements_multi_iodevice_v1.0_frozen_rev2.md`（归档后仅用于历史追溯）
- 历史计划：旧 `plan.md`（归档后仅用于历史追溯）
- V1 wire protocol 不可变基线：`f209302ce3efc0fa15d217550f6d9b1dc00487fb`
- V1 wire protocol tag：`legacy-v1-protocol-baseline`

解释规则：

1. 本文件未明确修改的 V1.0 已实现行为保持不变；
2. V1 wire protocol 的唯一不可变事实源是上述 commit/tag，当前仓库协议实现必须与之保持线缆兼容；
3. 不得借本次扩展恢复旧单实例 Core、shared `g_ctx`、旧 generic S-Function、共享 PC runtime、自动 reconnect/retry/resend、自动 MEX build 或其他已废弃方案；
4. 本文件不定义新的 Stage、Gate 或任务拆分；新的 `plan.md` 必须在本需求正式冻结后单独制定。

---

# 1. SCI 扩展范围与版本

### FR-001：SCI 与 Mixed IoDevice

本次在现有 W5300 TCP IoDevice 之外新增 `SCI` IoDevice，支持 TMS320F28377D 的 SCI-A、SCI-B、SCI-C、SCI-D。同一 DSP 工程允许 W5300 与多个不同 SCI Instance 混合存在并由现有裸机主循环轮询。

### FR-002：静态资源绑定

一个算法 Instance 在生成期静态绑定一个 IoDevice；一个物理 SCI 模块最多绑定一个 Instance。不得在 DSP 运行时切换 IoDevice，也不得在一个 SCI 模块上做逻辑多路复用。

### FR-003：现有多实例 Core 合同保持

SCI 必须接入现有实例化 Core。公共用户 API 继续保持 `PlatformInit()`、`Init(instance)`、`Run(instance)`、`GetLastError(instance)`；SCI 适配现有 `C2837xBlock_IoDeviceOps`，不得新增第二套 Core transport API，也不得恢复 default instance/shared `g_ctx`。

### FR-004：三类版本与 Core API 编译门

本次增量完成后固定：

```text
Project Format Version = 3
Wire Protocol Version  = 1
Core API Version       = 2
```

三者独立，不得混用。新 generated DSP project/header 必须使用现有 Core 编译门机制声明 `C2837X_BLOCK_EXPECTED_CORE_API_VERSION = 2`（或等价的编译期约束）；当其与 `C2837X_BLOCK_CORE_API_VERSION` 不一致时必须编译失败，禁止旧 generated DSP code 与 Core API V2 静默混用。

### FR-005：V1 wire protocol 不变

SCI 复用历史 V1 wire protocol。现有消息类型、4-octet Header、RESPONSE、little-endian、step_index、Interface Hash 语义和错误码线缆含义保持不变；不得增加 Magic、CRC、Instance ID、新握手层或 transport-specific framing。

### FR-006：W5300 与既有热路径保持

除本文件明确要求的 Project V3、条件 PlatformInit、mixed resource validation、App IoDevice-aware UI 与生成分支外，V1.0 已实现的 W5300 行为保持不变。新增 SCI 不得无理由恢复已关闭的 hot-path 性能回退：DSP `Run()` 不重复做完整静态配置校验，PC 每 step 不重新引入动态 heap/完整 Payload 二次复制，静态端口/元素/endian 优先继续由生成期展开。

---

# 2. Project V3 与迁移

### FR-007：V3 项目结构

V3 项目至少保存：

```matlab
project.format_version
project.common.dsp_model
project.common.package
project.common.protocol_version
project.common.abi
project.common.network
project.instances
project.output.dsp_root
project.output.sfun_root
```

当前固定 `project.common.dsp_model='TMS320F28377D'`、`project.common.package='PTP'`。

### FR-008：Network 条件有效

`project.common.network` 在 V3 中始终保留。有 W5300 Instance 时参与校验和 W5300 生成；SCI-only 项目中 Network 原值保留，但不得因 Network 无效阻止 Preview/Generate。

### FR-009：Instance IoDevice 条件配置

每个 Instance 保存 `iodevice.type` 及当前 IoDevice 的有效设置。W5300 有效字段为 Socket/TCP Port；SCI 有效字段至少包括 SCI Module、Baud、Pin Group、RX/TX Pin Type、RX Qualification、CTRL GPIO/Pin Type/Active Level。非当前 IoDevice 的历史字段不得参与校验、生成、Hash 或运行时配置。

### FR-010：V2→V3 自动迁移

加载 V2 项目时自动迁移为：

```matlab
project.format_version   = uint16(3);
project.common.dsp_model = 'TMS320F28377D';
project.common.package   = 'PTP';
```

全部历史 Instance 默认为 `W5300 TCP`，并保留原 Network、Socket/TCP Port、Sample Time、I/O、Algorithm 和输出根目录。当前允许把全部历史 V2 项目视为 PTP。V2→V3 migration 只迁移项目模型；迁移后必须重新 Generate DSP/PC candidates，旧 V2 generated C 不保证与 Core API V2 兼容。

### FR-011：迁移保存语义

V2→V3 迁移成功后项目必须保持 dirty，不自动覆盖旧 `.mat`；由用户显式 Save 后才写入 V3。

### FR-012：SCI 配置变化与生成

IoDevice、SCI Module、Baud、Pin Group、Pin Type、Qualification、CTRL GPIO 或 CTRL polarity 的变化必须使相关 generated candidate 失效并要求重新 Generate；这些字段不进入 Interface Hash。

### FR-013：COM 不属于 Project

PC COM Port Number 不保存到 DSP-SimBridge project `.mat`，不参与 Interface Hash，不影响 DSP code generation。COM 变化不要求重新 Generate、重新编译 DSP 或重新构建同一个 SCI MEX。

---

# 3. Device Capability 与资源冲突

### FR-014：当前 Capability Target

当前唯一 capability target 为 `TMS320F28377D + PTP`，唯一器件能力文件为：

```text
TMS320F28377D_PTP.json
```

本阶段不支持 ZWT/PZP，也不提供 Package selector。

### FR-015：Capability 内容与 Schema

Capability JSON 随源码发布、产品维护、用户只读；只保存固定器件事实，例如 SCI-A/B/C/D、合法 Pin Group、GPIO/PinMux。JSON 必须有独立 `schema_version`，MATLAB loader 统一校验并归一化；其他模块不得直接依赖 raw `jsondecode` 结构。

### FR-016：用户配置不进入 Capability

Baud、Pin Type、Qualification、CTRL polarity、具体 SCI/PinGroup/CTRL 选择属于 project `.mat`；COM 属于 S-Function runtime parameter。第一版不生成磁盘 `.mat` capability cache，但允许 MATLAB 会话内缓存。

### FR-017：Platform Reserved Resources 分层

W5300 固定 EMIF/GPIO/RESET 等占用属于 DSP-SimBridge Platform Reserved Resources，不属于 F28377D capability，不得写入 `TMS320F28377D_PTP.json`。

### FR-018：Generate 前资源校验

Generate 前必须合并 Device Capability、Platform Reserved Resources 与所有 Instance 选择，至少阻断：重复 SCI Module、SCI RX/TX/CTRL GPIO 冲突、CTRL 与自身 RX/TX 冲突、SCI GPIO 与 W5300 固定资源冲突，以及 capability 中不存在的 Module/PinGroup/GPIO/PinMux 组合。

---

# 4. App SCI 配置与布局

### FR-019：IoDevice 选择

Instance 的 `IoDevice` 改为下拉：`W5300 TCP` / `SCI`。新建 Instance 默认仍为 `W5300 TCP`。

### FR-020：Project 页与 Instance 页职责

Project 页继续负责 Target/Common、W5300 Network 和 Output Roots；不得建立 SCI-A/B/C/D 固定项目级 Panel。SCI 实际配置全部跟随选中的 Instance。

### FR-021：Instance Detail 布局

Selected Instance 详情至少分为 `General / IoDevice / Algorithm` 三个子区/子页。General 至少包含 Display Name、Internal Name、IoDevice、Sample Time、Max Payload；Algorithm Mode 及 External Source Path 保持既有算法源码来源语义。

### FR-022：IoDevice 专用字段

W5300 页面继续使用明确的 `Socket / TCP Port`。SCI 页面至少显示：SCI Module、Baud Rate、Actual Baud、Baud Error、Pin Group、RX Pin Type、RX Qualification、TX Pin Type、CTRL GPIO、CTRL Pin Type、CTRL TX Active Level。

### FR-023：SCI Module、Baud 与初始值

SCI Module 下拉固定 `SCI-A/B/C/D`。Baud 只允许 `9600 / 19200 / 38400 / 57600 / 115200`，默认 `57600`，不允许自由输入；上述五个候选均允许 Generate，第一版不依据 Baud Error 设置 Warning/Reject threshold。新建/切换到 SCI 时默认：Module=`Not Selected`、Pin Group=`Not Selected`、RX=`Pull-up + Async`、TX Pin Type=`Pull-up`、CTRL=`None`。

### FR-024：CTRL UI 默认值

CTRL 从 `None` 改为具体 GPIO 后，CTRL Pin Type 默认 `Standard`，CTRL TX Active 默认 `High`；CTRL=None 时 CTRL-specific 控件禁用或隐藏。

### FR-025：PinGroup/CTRL 由 Capability 驱动

Pin Group 下拉只列当前 SCI Module 的合法 capability 组合，并显示可读 RX/TX GPIO。切换 SCI Module 后旧 Pin Group 不合法时必须清空。CTRL GPIO 使用 `None/GPIOxx` 下拉，不允许自由输入任意数字；候选来自合法 GPIO，冲突由统一 validation 报告。

### FR-026：Pin Type 与 Qualification UI

Pin Type 仅提供 `Standard / Pull-up`；RX Qualification 仅提供 `Sync / Async`。TX/CTRL 不显示 Qualification。

### FR-027：LSPCLK 与 Baud 显示

项目存在 SCI Instance 时，Project/Common 区只读显示当前实际采用的项目级 LSPCLK 及其 SYSCLK 分频关系；每个 SCI Instance 只读显示 Requested Baud、Actual Baud 和 Baud Error。bring-up 阶段可显示约 `14.285714 MHz (SYSCLK / 14)`；最终 LSPCLK 收敛后必须显示最终实际值。LSPCLK 始终只读，不作为用户项目参数或每 Instance 参数。

### FR-028：实例列表与 Transport Summary

Instance Table 至少使用 `Display Name / Internal Name / IoDevice / Resource / Link / Sample Time`，并显示类型化文本，例如 `Socket 0 / TCP 5000` 或 `SCI-A / 57600 baud`。App 中其他实例选择、上下文标题、Report/Preview 也应复用统一 IoDevice-aware transport summary，不得把 SCI 显示成 Socket 文本。

### FR-029：SCI Instance Copy

复制 SCI Instance 时复制 Baud、Pin Type、Qualification、CTRL Pin Type/Active Level、Sample Time、I/O、Payload、Algorithm 等非独占配置；SCI Module、Pin Group 必须清空并要求用户重新选择，不自动分配下一个可用资源。CTRL 只有 `None` 或 `GPIOxx` 两种项目语义，不增加 `CTRL enable` 或第三状态：源 CTRL=`None` 时复制为 `None`；源 CTRL=`GPIOxx` 时复制实例的 CTRL 置为 `None`，不得复制原 CTRL GPIO。复制得到的 CTRL Pin Type/Active Level 可保留但在 CTRL=`None` 时禁用，用户后续选择新 GPIO 后再生效。

### FR-030：Capability 故障隔离

Capability JSON 缺失、损坏或 schema 不支持时 SCI 功能不可用，已有 SCI Instance 的项目不得 Preview/Generate；W5300-only 项目不得仅因 SCI capability 故障而失去 Load/Edit/Preview/Generate 能力。

---

# 5. SCI 时钟、Baud、GPIO 与 PlatformInit

### FR-031：LSPCLK bring-up 配置

当前 CPU Clock 继续为 200 MHz。SCI 初始 bring-up / 快速闭环验证阶段使用 `SYSCLK / 14`，即项目级 LSPCLK≈14.285714 MHz；其目的仅是优先验证 PC COM → SCI → DSP IoDevice → V1 Protocol → Core → Algorithm 的完整链路可以工作，不代表最终性能配置。没有 SCI Instance 时 `PlatformInit()` 不得为了 SCI 修改 LSPCLK；存在 SCI 时在 SCI 初始化前只设置一次当前项目级 LSPCLK。LSPCLK 不允许每实例配置，也不作为 App 可编辑项。

### FR-032：最终 LSPCLK 收敛

基础 SCI-PC 链路实现完成后，应从当前器件及实际时钟源允许的合法 LSPCLK prescaler 中选择一个最终平台值。最终值可以是 200 MHz，也可以是更合适的较低值，本需求不提前固定最大值。

选择时只做研发所需的必要评估，至少考虑全部支持 Baud 的理论量化误差和平台共享 LSPCLK 的影响；具备实机条件时，可结合一个代表性 SCI 配置的实际 SCI-PC 基本通信结果进行确认。

不要求建立 Baud × LSPCLK、大量 SCI Module 或硬件组合测试矩阵。

最终值一旦在本实现周期内确定，即作为 DSP-SimBridge 平台级固定配置使用，并同步驱动 App 显示、BRR、Actual Baud、Baud Error 和 generated DSP 配置；不得成为用户运行时或 Instance 可编辑参数。

### FR-033：BRR 与 Baud 计算

TMS320F28377D SCI 的 `SCIHBAUD` 与 `SCILBAUD` 共同组成 16-bit BRR。TI 硬件中 `BRR=0` 为特殊情况，其 Actual Baud 为 `LSPCLK / 16`，与 `BRR=1` 按普通 SCI Baud 公式得到的结果相同。因此 DSP-SimBridge V1 的统一 Baud 计算服务不将 `BRR=0` 作为求解候选；本项目合法候选 BRR 范围固定为：

```text
1 <= BRR <= 65535
```

对所有本项目合法候选 BRR，统一使用：

```text
ActualBaud = LSPCLK / (8 * (BRR + 1))
```

在上述范围内选择绝对 Baud Error 最小的整数 BRR；若完全同误差，选择较小 BRR。App Actual Baud/Error、generated DSP BRR 和 PC 诊断必须使用同一计算结果；DSP runtime 不得使用另一套公式重新求 BRR。`BRR=0` 虽为硬件可编码值，但不属于 DSP-SimBridge V1 的 Baud 求解候选范围，首版 calculator 无需实现其分段公式。

本合同依据 TMS320F2837xD Technical Reference Manual 的 SCI 章节及 TI SCI Reference Guide：`SCIHBAUD + SCILBAUD` 组成 16-bit BRR，`BRR=0` 使用特殊 Baud 定义，普通公式适用于 `BRR>=1`。

### FR-034：PC Baud

PC serial port 使用项目选择的 nominal Requested Baud，例如 57600；不尝试把 COM 设置成 DSP 量化后的 Actual Baud。

### FR-035：SCI 固定串口格式

DSP SCI 固定 8 data bits、no parity、1 stop bit、无 flow control、异步全双工 peripheral；禁用 autobaud、loopback、SCI/FIFO interrupts，启用 FIFO，FIFO delay=0，采用 polling。

### FR-036：Pin Type 与 Qualification 物理含义

`Standard`=GPIO internal pull-up disabled；`Pull-up`=internal pull-up enabled。RX `Sync`=synchronous qualification，`Async`=asynchronous qualification。不开放 Open Drain/Invert、3-sample、6-sample 或 Qualification Period。

### FR-037：PinMux/Pad/CTRL 初始化

`PlatformInit()` 根据 capability + project 设置选中 SCI 的 RX/TX PinMux、Pad、RX Qualification 和可选 CTRL GPIO；CTRL 初始为 RX。未使用 SCI/GPIO 不得被修改。

### FR-038：条件 PlatformInit 与构建依赖

`PlatformInit()` 只初始化当前项目实际使用的资源：SCI-only 不初始化 W5300，W5300-only 不初始化 SCI，mixed 同时初始化所需资源。Instance `Init()` 不重新初始化 W5300、SCI、LSPCLK/LOSPCP、PinMux、Timer2 或其他 Platform hardware。DSP generated/common source 与 build dependency 也必须按 IoDevice 收敛：SCI-only 不要求/链接 W5300 driver/HAL，W5300-only 不要求/链接 SCI driver，mixed 才同时包含两类 transport 依赖。

### FR-039：SCI_INIT 错误与无 read-back

新增 `C2837X_BLOCK_PLATFORM_ERROR_SCI_INIT = -5`，追加在既有 PlatformResult 错误之后，既有枚举数值不得重排。该错误仅表示 `PlatformInit()` 可实际检测的 SCI descriptor/config 内部不可执行错误，例如非法 module/BRR/pin descriptor、重复 module 或内部配置不一致。第一版不做完整 register read-back、loopback self-test 或外部设备探测，也不得把普通寄存器写入虚构成可检测的硬件初始化失败。

### FR-040：Mixed PlatformInit failure

mixed 项目中任一 required platform resource 初始化失败时 `PlatformInit()` 返回对应错误，所有实例通信不得开始；不要求回滚此前已完成的其他 platform 初始化。

---

# 6. DSP SCI Driver 与运行时

### FR-041：Common SCI Driver 与实例状态

DSP 只维护一套公共 SCI IoDevice/driver，支持 SCI-A/B/C/D，不依赖 generated instance name。每个 SCI Instance 生成独立 const Hardware Config 和独立 mutable Channel Runtime，不使用动态内存或共享可变运行时。

### FR-042：Hardware Init 与 channel_init 分工

SCI peripheral/PinMux/Baud 只在 `PlatformInit()` 初始化；`channel_init()` 仅初始化实例软件状态并确保 CTRL 为 RX。

### FR-043：逻辑连接状态

SCI 没有真实 peer-connect。状态按 `CLOSED -> OPEN -> LISTENING` 推进；LISTENING 无 RX byte 时持续等待且不启动通信 timeout。检测到第一个 RX octet 后报告 `CONNECTED`，但不得消耗该 octet；Core 接受连接后由 `receive()` 消费并开始 frame transfer timeout。

### FR-044：等待 SIM_START 与 session cleanup

进入新的 WAIT_SIM_START 前只清理一次 RX FIFO/error/private pending；不得无主机时每次 `Run()` 重复 flush。SCI session 继续使用既有 SIM_START→step→SIM_STOP/error 生命周期；结束时清理 RX/TX FIFO/private pending/error、CTRL 回 RX，并重新等待 SIM_START，不重新初始化 peripheral/Baud/PinMux。

### FR-045：SCI close 语义

SCI `close()` 只关闭当前逻辑 session；下一轮 `open/listen` 建立新 session。SCI 不产生 TCP-style peer close/disconnected 语义。

### FR-046：RX polling 与 octet/word 适配

`receive()` 使用 FIFO polling，只处理当前可用数据，不等待新 byte。SCI adapter 私下完成 8-bit serial octet 与 C28x `Uint16` word 转换；Core length/progress 继续使用 wire octet，正进度必须为偶数。只有一个 byte 时允许暂存并返回 0。

### FR-047：RX error

SCI RXERROR/RXFFOVF 或等价严重接收错误使当前 session 进入 IODEVICE error 并有限清理；不做 frame resync、CRC retry 或 byte retransmission。

### FR-048：TX polling 与 pending operation

`send()` 使用 FIFO polling，不等待 FIFO 空位；一次 Core `send(count_octets)` 视为一个完整 pending operation，中间 `Run()` 只推进该 operation，不接受第二个待发送 segment。

### FR-049：SCI send 完成语义

full-duplex/half-duplex 的 `send()>0` 都必须等本次全部 octets 已物理发送完成，包括最后 stop bit（TXEMPTY 或等价条件）；中间阶段返回 0，最终一次返回完整 `count_octets`。

### FR-050：Timeout 与 Run 有界

SCI 不新增 transport-specific TX timeout，继续使用 Core INTERACTION/TRANSFER timeout。Baud 或 LSPCLK 变化不得自动修改 DSP timeout；现有每实例 DSP user-config timeout 继续作为 timeout 事实源。等待 SIM_START 的 LISTENING 在首 byte 前无限等待；首 byte 到达后按既有 frame timeout 处理。所有 `Run()` 可达 SCI 操作必须有界、非阻塞，不得等待 RX/TX/TXEMPTY 或使用 `delay_us()`。

第一版不建立 Baud × Payload × Timeout 的自动适配、自动推荐、Warning 或 Generate Reject 机制，也不根据 Baud 或 LSPCLK 自动修改 DSP/PC timeout。低 Baud、大 Payload 或用户算法响应时间较长时，所需通信 timeout 由用户通过现有 DSP/PC user-config timeout 根据实际研发需要调整。

---

# 7. Half-duplex CTRL

### FR-051：CTRL 模式与 polarity

`CTRL=None` 表示无需 DSP 方向控制；选择 CTRL GPIO 后表示 DSP 侧 half-duplex transceiver direction control，仍属于同一 SCI IoDevice/V1 protocol。用户可配置 `CTRL TX Active=High/Low`；默认和 cleanup 状态必须为 RX。

### FR-052：Half-duplex send 起始与保持

新的 half-duplex send 首次进入时先切 CTRL→TX、保存 pending operation 并返回 0；不增加可配置 DE setup delay。pending TX 未完成前 CTRL 保持 TX，FIFO 可跨多个 `Run()` 填充。

### FR-053：Half-duplex send 完成

只有全部数据物理发送完成后才切 CTRL→RX；切回 RX 后本次 `send()` 才返回完整正进度。pending TX 存在时重复 `send()` 只能推进同一 operation，不得重复发送、重新切换、覆盖 pending 或启动第二 segment。

### FR-054：Half-duplex error 防御

`receive()` 只允许 CTRL 为 RX；内部状态矛盾按 IoDevice/session error 清理。TX 中发生错误或 termination 时停止继续填 FIFO，清理 pending/适当 FIFO 并强制 CTRL→RX，不保证 drain 已排队全部 bytes。

### FR-055：PC 侧方向控制边界

PC S-Function 不通过 RTS/DTR 控制 RS485 DE。使用 USB-RS485 时第一版要求适配器自动方向控制；软件 RTS/DTR direction adapter 不在本阶段范围。

---

# 8. PC SCI S-Function 与 Serial Transport

### FR-056：SCI Block 参数与 COM 保存

SCI instance-specific S-Function 只有一个 transport runtime 参数：positive finite integer scalar `COM Port Number`，non-tunable。COM 由 Simulink `.slx` 保存，不属于 DSP-SimBridge Project。同一个 generated MEX 可在不同 PC/模型/运行中使用不同 COM。

### FR-057：W5300/SCI 参数差异与 Baud

W5300 S-Function 继续 0 个 transport parameter；SCI 为 1 个 COM 参数。Baud 来自 Project 并编译进 generated SCI S-Function，不是 block parameter。W5300↔SCI 或 Baud 变化要求 Generate/MEX rebuild；仅 COM 变化不要求。

### FR-058：SCI mdlStart

SCI `mdlStart()` 必须：校验 COM、创建实例私有 PC context、打开 COM、配置 generated baud+8N1、关闭 flow control、purge RX/TX、发送 SIM_START、等待 RESPONSE(OK)、初始化 step_index。任一步失败均启动失败并释放资源。

### FR-059：Serial open 失败与启动边界

COM 不存在、被占用、权限/driver/config 失败时立即 `mdlStart` error；不自动搜索、切换、retry、等待或 reconnect。purge 只在 open/configure 后、SIM_START 前执行一次；正常 session 中不得 purge 后继续。不得发送 bootloader `'A'` autobaud handshake，也不加固定 serial-open sleep。

### FR-060：同步 step 与 terminate

SCI `mdlOutputs()` 保持现有同步单步：读全部输入→发送 INPUT_DATA(step)→等待 OUTPUT_DATA/RESPONSE→完整校验→原子更新全部输出→step_index++；不引入 async/pipeline/batch/skip/background thread。`mdlTerminate()` best-effort 发送 SIM_STOP、不等待 response，然后关闭 COM；SIM_STOP failure 不阻止 cleanup 或覆盖主错误。

### FR-061：Serial partial I/O 与 deadline

PC serial transport 提供同步、timeout-bounded 的 write-all/read-exact 语义，正确处理 partial read/write。一个 send/recv operation 使用单一 monotonic deadline，partial progress 不重启完整 timeout。

### FR-062：PC timeout 合同

继续保留 `CONNECT_TIMEOUT_MS / STEP_TIMEOUT_MS / TERMINATE_TIMEOUT_MS`。SCI 第一版保留 CONNECT_TIMEOUT 字段但不把它用于虚构的 peer-connect 等待；SIM_START send/RESPONSE、INPUT_DATA send/OUTPUT_DATA receive 各自继续使用 STEP_TIMEOUT；SIM_STOP best-effort send 使用 TERMINATE_TIMEOUT。

### FR-063：PC Serial 固定格式与控制线

PC serial 固定 8N1，禁用 XON/XOFF、CTS/RTS、DSR/DTR flow control；DTR/RTS 不用于协议或 RS485 direction，并在平台允许时保持 inactive。

### FR-064：Raw byte stream 与按需读取

SCI transport 只传输 V1 protocol octets，不增加 SOF/Magic/CRC/terminator/SLIP/COBS/额外 length prefix。Protocol 只消费当前 Header/Payload 所需 bytes，不用 `read all available` 建立第二套独立 frame parser。

### FR-065：Serial 错误终止 simulation

read/write timeout、OS serial error、USB removal、partial frame timeout、handle failure 或协议错误都终止当前 simulation 并关闭 COM；不 reopen、retry frame、resend INPUT_DATA、skip step 或重新 SIM_START。第一版不使用 CTS/DSR/DCD/RI 判断 peer 状态。

### FR-066：Windows-only 与实现参考

SCI host 第一版只支持 Windows desktop MATLAB/Simulink Normal mode。Windows 串口打开、8N1 配置、handle 生命周期、ReadFile/WriteFile 和 partial I/O 行为可优先参考目标 MATLAB 环境可获得的 MathWorks `rtiostream_serial.c` 或等价实现；不得因此引入必须依赖 MathWorks 私有 serial binary 才能运行的设计，也不要求直接链接 `libmwrtiostreamserial.dll`。

### FR-067：无额外 Serial 依赖

SCI MEX 不要求 Instrument Control Toolbox、Python、pySerial 或第三方 serial library；若 MathWorks 私有二进制依赖会造成版本/部署约束，应优先保持 self-contained C transport。

### FR-068：COM path、存在性与枚举

用户只输入逻辑 COM number；COM10+ native path 由 transport 内部处理。Update Diagram 只检查参数为正整数标量，不枚举设备、不检查存在/占用；真实 open 只在 `mdlStart()`。第一版不提供 COM 自动枚举、VID/PID 自动匹配或 Refresh COM UI。

### FR-069：多 SCI 与 COM 冲突

同一模型可运行多个不同 COM 的 SCI instance，并可与 W5300 mixed。相同 COM 被两个 SCI block 使用时依赖 OS exclusive open，第二个 `mdlStart()` 明确失败；不得建立跨 MEX 全局 COM registry。

### FR-070：同一 generated instance block

同一个 generated instance-specific S-Function 在一次 simulation 中只代表一个 DSP instance，正常模型只放置一次；允许 per-MEX duplicate guard，但不得引入共享 transport/session state。

---

# 9. PC 错误诊断

### FR-071：PcError 扩展

SCI 复用现有 `PcError` 框架并新增 `SERIAL` category；已有错误枚举编号不得重排。SCI 不使用 TCP `DISCONNECT` 表示 USB/handle/ReadFile/WriteFile failure，这些归入 `SERIAL + os_error`。

### FR-072：SCI 错误 stage 与用户字段

至少稳定区分 `serial_open / serial_configure / serial_purge / send_frame / recv_header / recv_payload / wait_response / wait_output_data`。用户可见错误至少包含 instance、COM、generated baud、stage、category；处于 step 时继续包含 step_index。

### FR-073：OS error 与 partial timeout

OS error 数值必须保留，并在可取得时附带 Windows system error text。SCI partial-frame deadline timeout 保持 `TIMEOUT`；当 timeout 前已经发生 partial progress 时，必须报告 expected_length/actual_length，不得错误改成 TCP-style DISCONNECT。

### FR-074：协议错误与 Simulink error

message type、payload length/capacity、step index、DSP RESPONSE error 继续复用既有 V1 diagnostics。`mdlStart()`/`mdlOutputs()` 不可恢复错误通过 `ssSetErrorStatus()` 终止 simulation 并完成 cleanup，不允许输出旧值继续运行。

### FR-075：Terminate 与日志边界

`mdlTerminate()` 中 SIM_STOP/close failure 不升级成新的 simulation error，也不覆盖主错误。第一版不新增长期 serial.log、packet trace、error history ring buffer 或持久化通信历史。

---

# 10. 生成、文件与 MEX Build

### FR-076：实例目录与 Transport 文件

继续沿用 V1.0 每实例独立、自包含 `<sfun_root>/<internal_name>/`。W5300 Instance 生成 `<instance>_pc_socket.c/.h`；SCI Instance 生成 `<instance>_pc_serial.c/.h`；实例目录只包含当前 transport 所需文件，不恢复共享 PC runtime。

### FR-077：Protocol 单一实现

TCP 与 SCI 共享同一套 V1 protocol template/逻辑；不得复制为长期独立演化的 `protocol_tcp` 与 `protocol_sci` 两套协议。

### FR-078：SCI generated config 与 user config

SCI generated config 编译进 IoDevice type、Requested Baud/必要 Actual Baud 诊断信息、Protocol Version、Interface Hash、Sample Time、Payload/I/O 等固定配置；COM 不编译进去。每实例 PC user config 继续只承担三个 PC timeout，不新增 serial-specific timeout 用户宏。

### FR-079：Build source list

W5300 build script 显式编译 pc_socket；SCI build script 显式编译 pc_serial；不得使用 `dir('*.c')` 等自动纳入所有源文件。SCI build 在删除旧 MEX 或 rebuild 前必须先检查 Windows 和必要 build prerequisites，失败时不得破坏已有 MEX。

### FR-080：App 不自动 Build MEX

Preview/Generate 仍只生成源码和 `build_<instance>_sfun.m`；App 不自动调用 `mex`、不自动删除/加载 MEX、不修改 MATLAB Path，也不自动修改 Simulink 模型。

### FR-081：Update Diagram

Update Diagram 只做 block parameter 静态校验、端口数/宽度/类型、sample time 等 compile-time 配置；不得 open COM、purge、发送 SIM_START、探测 DSP 或枚举 COM。

### FR-082：IoDevice 改变后的模型责任

W5300↔SCI 重新 Generate/rebuild 后，同名 instance-specific block 的参数合同会变化；已有 `.slx` 由用户自行增加/移除 COM 参数，App 不自动重写模型。

### FR-083：Simulink 支持范围

新增 SCI 仍只保证 desktop Normal mode；不要求 Fast Restart 保持 COM 跨 simulation session 打开，也不扩大到 Accelerator、Rapid Accelerator、codegen、real-time 或 parallel simulation。

---

# 11. 必要性测试与用户硬件责任

### FR-084：必要性测试原则

DSP-SimBridge 是研发工具。本阶段只执行证明 SCI 新功能和关键兼容边界正确所必需的测试，不以覆盖率为目标建立大规模组合测试矩阵。

### FR-085：开发侧最小必要验证

开发侧只执行证明本次 SCI 增量功能和关键兼容边界正确所必需的测试，至少覆盖：

- capability/schema 基本加载；
- SCI Module/PinGroup/GPIO/W5300 关键资源冲突；
- V2→V3 migration；
- SCI-only、W5300-only 和 mixed 的关键 deterministic generation；
- 一个代表性 SCI 配置的 serial partial read/write、deadline、SIM_START 和单步 INPUT/OUTPUT 基本协议路径；
- 与本次修改直接相关的关键 transport/protocol error 路径。

不要求增加 2×SCI、多 SCI、SCI-A/B/C/D 组合、全部 Baud、全部 PinGroup/GPIO、half-duplex CTRL、长期稳定性或其他组合矩阵测试。

已有 V1.0 软件证据仍有效且相关实现未修改时，应优先复用已有证据或执行最小必要回归，不机械重跑全部旧测试。

### FR-086：避免机械重跑 V1.0

V1.0 已有软件证据仍有效且相关实现未修改时，可以复用已有证据或做最小必要回归，不要求为本增量机械重跑全部旧测试。

### FR-087：MEX 验证按环境能力

若当前 MATLAB 环境已配置 C MEX compiler，应至少真实构建一个 SCI MEX 并完成必要验证；若无能力，必须记录 `NOT_EXECUTED / CAPABILITY`，不得宣称 PASS。

### FR-088：不建立多 SCI 或硬件组合矩阵

开发侧不要求 2×SCI/多 SCI 软件专项测试，也不要求遍历全部 Baud、SCI-A/B/C/D 组合、全部 PinGroup/GPIO、全数据类型×SCI、最大 Payload×SCI、多 SCI/mixed 实机矩阵或 USB adapter 品牌兼容矩阵。mixed 的低成本 deterministic generation 仅用于确认两类 IoDevice 生成分支可以共存，不扩张为多 SCI 或 mixed 硬件门禁。

### FR-089：最终硬件验证由用户执行

TMS320F28377D + PC 的最终 SCI 实机通信、最终 LSPCLK 实际确认、不同 Baud、half-duplex CTRL、mixed IoDevice 和长期稳定性等硬件验证均由用户根据实际研发需要和硬件条件执行。

开发侧不把这些项目扩张为固定硬件测试矩阵。

开发侧在具备条件时可以使用一个代表性 SCI 配置辅助完成基础 bring-up；若当前无硬件条件，应明确记录为待用户验证，不影响已经完成的软件实现和静态审核结论。

没有真实硬件证据时只能声明“已实现，待用户实机验证”，不得声明硬件 PASS。

### FR-090：未执行项目必须真实标记

未实际执行的 CCS、MEX、Simulink Normal-mode 或硬件项目必须明确标记未执行/待用户验证，不得通过计划、mock 或静态检查替代真实结果。

---

# 12. 非目标与文档治理

### FR-091：SCI 首版可靠性边界

第一版 SCI 面向研发联合仿真，不增加 CRC、ACK/NAK、frame retry、byte retransmission、自动 reconnect、复杂 resync、watchdog recovery、autobaud、SCI interrupt/DMA 或工业级冗余诊断。

### FR-092：平台与 Package 非目标

第一版 SCI host 只支持 Windows；DSP 只支持 TMS320F28377D PTP。Linux/macOS serial、ZWT/PZP capability、Package selector 和多器件 capability 不属于本阶段。

### FR-093：旧需求与旧计划归档

本需求正式冻结并进入仓库后，旧 `requirements_multi_iodevice_v1.0_frozen_rev2.md` 与已完成旧 `plan.md` 应归档并退出当前规范集合，但保留用于 G0～G5 历史追溯，不删除其 Git 历史证据。

### FR-094：新的实施计划

本需求正式冻结后必须重新制定新的 `plan.md`，只覆盖本文件的增量 FR；不得把 SCI 自动追加成旧计划“Stage 6”，也不得重新执行已关闭的 V1.0 G0～G5 任务，除非本增量明确要求必要回归。

### FR-095：SCI 实施期当前规范入口与 FR 稳定性

进入 SCI 实施后，当前规范集合应收敛为：本冻结需求、新 `plan.md`、`DSP-SimBridge_ChatGPT_Project_Instructions.md`、当前 Dynamic Context 与当前任务批次移交摘要；归档旧文件不得继续作为当前实现依据。正式冻结后本文件 FR 编号必须保持稳定：废弃条目不得复用编号，新增需求只能从末尾继续追加。

---

# 13. 冻结确认

本文件已于 2026-08-10 完成 Final Freeze Audit，并确认：

1. 完整覆盖本轮已确认的 SCI / Project V3 / Core API V2 / App / PC / Capability 决策；
2. 不重复已经实现且本轮不修改的 V1.0 完整需求；
3. 不与 V1 protocol baseline、当前多实例架构或已关闭 hot-path 基线冲突；
4. FR-001～FR-095 编号连续、无重复；
5. 未在冻结需求中预设新 Stage/Gate，也未写入任何未实际执行的测试、编译或硬件结果。

自本次冻结起，FR 编号按 FR-095 的治理规则保持稳定；后续新增需求从 FR-096 起追加。

