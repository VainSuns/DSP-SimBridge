# DSP-SimBridge W5300 UDP IoDevice 增量实施计划

> **计划状态：** Approved for Implementation
> **生成日期：** 2026-09-06
> **批准日期：** 2026-09-06
> **唯一需求基线：** `requirements_w5300_udp_iodevice_v1.0_frozen.md`
> **Repository：** `VainSuns/DSP-SimBridge`
> **建议实施分支：** `feature/w5300-udp-iodevice-v1`（由 Stage 0 基于实际 `main` 基线建立/核对）
> **讨论时 Remote main 基线：** `5b7466d23354a40ec58e4d14113e171d3f14bd87`
> **V1 wire protocol 基线：** `f209302ce3efc0fa15d217550f6d9b1dc00487fb` / `legacy-v1-protocol-baseline`
> **固定版本：** Project Format V4 / Wire Protocol V1 / Core API V2
> **实施对象：** DSP-SimBridge / C2837xBlock
> **计划命名规则：** 本增量周期使用 `UDP-Sx-yy` 与 `UDP-Gx`，避免与历史多实例和 SCI 周期任务编号混淆。
> **进度记录规则：** 本文件只定义任务、依赖、产物、最小验证和门禁，不回写实际完成状态。真实 Branch、HEAD、Remote HEAD、`git status`、测试、编译、硬件和 Gate 结果只记录在每批次跨对话移交摘要、Git 历史和真实日志中。

---

# 1. 计划目标与执行规则

本计划只实现冻结需求 `FR-001～FR-082`，目标是在当前已完成的 W5300 TCP + SCI 多 IoDevice 基线上新增 `w5300_udp`，完成 Project/App、DSP W5300 UDP、PC UDP、mixed generation、必要测试和文档闭环。

本计划不重新实现已经关闭的多实例 W5300 TCP 或 SCI 基础能力。冻结需求未明确修改的既有行为继续继承当前实现和既有证据。

## 1.1 执行规则

1. **一个 Codex 对话只执行一个小任务。**
   每个 `UDP-Sx-yy` 原则上对应一个独立 Codex 实施对话；不得在完成当前任务后顺带进入下一个 `UDP-Sx-yy`。

2. **一个 ChatGPT 对话可以负责一个完整 Stage 的任务分发与审核。**
   例如当前 ChatGPT 对话可审核整个 Stage 2，但每个 Codex 对话仍只执行 `UDP-S2-01`、`UDP-S2-02` 等单个小任务。

3. **开始任何实施任务前必须核对 Git。**
   Stage 0 至少核对：
   - Repository；
   - Branch；
   - Local HEAD；
   - Remote HEAD；
   - `git status`；
   - V1 protocol baseline；
   - 前置 SCI completion baseline。
   Stage 0 可以使用已审核确认、但尚未写入 Repository current authority 的 Frozen requirements / approved plan 正式输入文件。
   从 `UDP-S1-01` 开始，除上述项目外还必须核对：
   - Frozen requirements commit；
   - approved plan / root `plan.md` commit；
   - 前置任务提交；
   - 前置 Gate 状态。
   GitHub 只能证明远端事实，**本地 `git status` 必须在实际本地仓库中检查，不得从远端推断。**

4. **冻结需求优先。**
   本计划不得改变 FR 语义。发现计划与 Frozen requirements 冲突时，以 Frozen requirements 为准，并停止当前实现批次进行审核。

5. **Wire V1 / Core API V2 / Project V4 不升级。**
   本增量不得借 UDP 引入新的 wire version、Core API version 或 Project Format migration。

6. **保持研发项目定位。**
   优先结构直接、热点路径低开销、测试最小充分；不得引入产品级 ACK/retry/heartbeat/reorder/长期稳定性矩阵。

7. **W5300/C2000 外设访问继续使用现有官方 TI bitfield / 当前 W5300 HAL 路径。**
   不得通过裸地址指针重新实现 C2000 外设访问；不得绕过当前 W5300 HAL/regs/platform 分层复制第二套底层。

8. **不伪造环境能力。**
   未实际执行的 MATLAB、MEX、DSP/TI compiler、Simulink、硬件验证必须记录为：
   - `NOT_EXECUTED / CAPABILITY`；
   - 或 `USER_VALIDATION_PENDING`。
   未执行项目不得声明 PASS。

9. **用户最终实机验证不由 Codex 代替。**
   W5300 UDP PIL 实机连接、连续 step、SIM_STOP/重连和 TCP/UDP 性能比较由用户执行。

10. **Codex 不负责擅自提交、推送、创建 Tag 或扩大分支范围。**
    Codex 形成待审核工作区和真实测试结果；提交/推送由用户决定，除非用户在具体任务中另有明确授权。

11. **本计划批准本身不代表任何产品实现、测试、编译、硬件或 Gate 已经通过。**

## 1.2 状态术语

| 状态 | 含义 |
|---|---|
| 未开始 | 尚未实施 |
| 已实现待审核 | 当前小任务代码完成，但未经过独立审核 |
| 已通过静态审核 | 源码/生成/职责边界经只读审核通过 |
| 已通过 Host/MATLAB 测试 | 实际执行对应 host/MATLAB 自动测试并通过 |
| 已通过 MEX 编译 | 在实际可用 MEX compiler 环境中构建通过 |
| 已通过 DSP 编译 | 在实际 TI C2000 compiler/CCS 环境中构建通过 |
| `NOT_EXECUTED / CAPABILITY` | 当前执行环境不具备该项能力 |
| `USER_VALIDATION_PENDING` | 开发侧完成，但需要用户最终实机验证 |
| 已通过用户验证 | 用户提供真实实机结果并确认通过 |
| 阻断 | 需求冲突、测试失败、工作区异常或前置条件缺失 |
| 废弃 | 任务取消但编号保留 |

## 1.3 每个任务批次的最小交付信息

每个 `UDP-Sx-yy` 完成后必须输出跨对话移交摘要，至少记录：

- 当前任务编号与对应 FR；
- 实际修改文件；
- 未修改但重点复核的文件；
- 关键设计决定；
- 实际执行的测试/检查及真实结果；
- 未执行/无法验证项目；
- 当前 Repository / Branch；
- Local HEAD；
- Remote HEAD；
- `git status`；
- 当前任务是否已提交；
- 当前提交 SHA（若已提交）；
- 已知问题；
- 下一批次**允许**执行的任务；
- 下一批次**禁止**提前执行的任务。

计划文件本身保持静态，不把实际完成状态逐项写回本文件。

---

# 2. 增量实施起始基线

当前讨论与需求冻结时确认的远端基线：

```text
Repository        : VainSuns/DSP-SimBridge
Remote branch     : main
Remote HEAD       : 5b7466d23354a40ec58e4d14113e171d3f14bd87
Project Format    : 4
Wire Protocol     : 1
Core API          : 2
Existing IoDevice : w5300_tcp + sci
```

历史 Wire V1 不可变基线：

```text
Commit : f209302ce3efc0fa15d217550f6d9b1dc00487fb
Tag    : legacy-v1-protocol-baseline
```

**实施时必须重新核对实际 main HEAD。**
如果 `main` 已在需求冻结后继续前进，Stage 0 必须记录新的实际实施基线，并确认新增提交没有改变本 Frozen requirements 所依赖的关键合同。

当前实现中必须保留的关键基线：

- static multi-instance Core；
- `C2837xBlock_IoDeviceOps`；
- `PlatformInit()` / `Init(instance)` / `Run(instance)` / `GetLastError(instance)`；
- Wire V1 Header / Message / RESPONSE / `step_index`；
- Interface Hash 既有字段集合；
- W5300 TCP stream send/receive；
- W5300 TCP close erratum workaround；
- SCI 已完成行为；
- 每 Instance 独立 S-Function/MEX 输出；
- shared `protocol.c.in`；
- Preview/Snapshot/Commit 用户文件保护机制；
- DSP `Run()` 热路径不恢复重复静态配置校验；
- PC step 热路径不恢复无必要 heap/full-frame 二次复制。


---

# 3. 全局 FR 覆盖矩阵

| FR 范围 | 主要实施位置 |
|---|---|
| FR-001～FR-008 | 全局约束；UDP-S0、UDP-S2、UDP-S3、UDP-S4、UDP-S5 |
| FR-009～FR-022 | UDP Stage 1；Project / provider / validation / App |
| FR-023～FR-044 | UDP Stage 2～3；W5300 UDP primitives + DSP IoDevice Channel |
| FR-045～FR-054 | UDP Stage 4；PC UDP transport / protocol binding |
| FR-055～FR-064 | UDP Stage 5；DSP/PC generated closure 与 mixed integration |
| FR-065～FR-075 | UDP Stage 3～4；DSP/PC error、timeout、terminate |
| FR-076～FR-080 | 各 Stage 最小验证 + UDP Stage 6 最终软件证据收敛 |
| FR-081 | 用户最终 W5300 UDP 实机验证，不由 Codex 宣称完成 |
| FR-082 | 全 Stage 非目标约束 |

---

# 4. UDP Stage 0：规范入口与实施基线

Stage 0 不实现任何 UDP 产品代码，只建立新的增量周期规范入口和可验证实施基线。

## UDP-S0-01：核对 Repository / Branch / HEAD / 工作区与前置完成基线

- **对应 FR：** FR-001～FR-005、FR-082；Frozen §0 / §8 治理要求
- **前置任务：** 无
- **目标：**
  1. 核对 Repository 为 `VainSuns/DSP-SimBridge`；
  2. 获取实际 `main` Remote HEAD；
  3. 在本地仓库核对 Local HEAD、Remote HEAD、`git status`；
  4. 核对当前 SCI 周期已经完成，当前 `main` 可作为 UDP 起点；
  5. 核对 V1 wire protocol commit/tag 仍存在且未漂移；
  6. 确认 UDP Frozen requirements 与最终 approved plan 的正式输入文件已审核确定；本任务不要求它们已经成为 Repository commit；
  7. 确认建议新分支 `feature/w5300-udp-iodevice-v1` 是否已建立；如未建立，由用户决定创建，不由 Codex擅自扩展 Git 操作；
  8. 记录实际 UDP 实施起始 SHA。
- **非目标：**
  - 不修改产品代码；
  - 不修改 Project/App；
  - 不实现 UDP；
  - 不重新执行 SCI 全部 Gate。
- **最小验证：**
  - Git repository/branch/HEAD/status；
  - requirements/plan 文件存在；
  - protocol baseline commit/tag；
  - UDP base 与 SCI completion 的祖先关系。
- **阻断条件：**
  - 本地存在来源不明的未提交修改；
  - Frozen requirements / approved plan 未确定；
  - 实际 baseline 与已知完成基线无法建立清晰祖先关系。

## UDP-S0-02：切换 Repository current authority 并归档 SCI 周期入口

- **对应 FR：** Frozen §8 治理；FR-082
- **前置任务：** UDP-S0-01
- **目标：**
  1. 将 `requirements/requirements_w5300_udp_iodevice_v1.0_frozen.md` 设为当前 Frozen requirements；
  2. 将最终批准的 UDP plan 内容切换为根 `plan.md` 当前实施计划；
  3. 将上一 SCI Frozen requirements、SCI plan、SCI traceability 转为直接前置历史规范；
  4. 保留历史 Git 可追溯性；
  5. 更新 Repository 中会造成 current-authority 歧义的 README/traceability 链接；
- **建议归档目标：**
  - SCI Frozen requirements → `requirements/archive/requirements_sci_iodevice_v1.0_frozen.md`；
  - 当前 SCI `plan.md` → `docs/archive/plan_sci_iodevice_v1.0_completed.md`；
  - 当前 SCI traceability → 对应 archive 路径；
  - UDP Frozen requirements → `requirements/requirements_w5300_udp_iodevice_v1.0_frozen.md`；
  - UDP approved plan → root `plan.md`。
- **非目标：**
  - 不修改产品源码；
  - 不重写全部文档；
  - 不删除历史提交；
  - 不修改 ChatGPT Project Source 私有上下文文件并提交到研发仓库。
- **最小验证：**
  - current authority 搜索；
  - archive 文件可追溯；
  - README/traceability 不再指向 SCI 作为 current；
  - `git diff --check`。

### UDP Stage 0 Gate：UDP-G0

必须确认：

- Repository / Branch / actual implementation HEAD 已真实核对；
- Local `git status` 已真实核对；
- Frozen requirements 与 approved plan 已作为唯一当前实施入口；
- Frozen requirements commit 与 approved plan / root `plan.md` commit 已真实确定并记录；
- 上一 SCI 周期只作为直接前置历史规范；
- Wire V1 baseline 未改变；
- Stage 0 未混入 UDP 产品实现；
- 实际提交状态和 SHA 已记录；
- 可以进入 Stage 1。

---

# 5. UDP Stage 1：Project V4、Provider、Resource 与 App

Stage 1 只让 Project/App 完整认识 `w5300_udp`。
**本 Stage 不实现 DSP UDP 收发，也不实现 PC UDP socket。**

## UDP-S1-01：新增 `w5300_udp` Provider 与 canonical Project Model

- **对应 FR：** FR-001～FR-004、FR-009～FR-010、FR-013、FR-017、FR-022
- **前置门禁：** UDP-G0
- **目标：**
  1. 新增 `w5300_udp` IoDevice definition/provider；
  2. canonical settings 精确为：
     ```text
     socket_number
     udp_port
     ```
  3. UDP defaults：
     ```text
     socket_number = 0
     udp_port      = 5000
     ```
  4. Project Format 保持 V4；
  5. 不建立 V4→V5 migration；
  6. TCP persisted fields 保持 `socket_number + tcp_port`；
  7. 创建/结构验证/normalize 支持 `w5300_udp`；
  8. TCP/UDP/SCI type switch 时重建目标 canonical settings，不遗留 stale fields；
  9. UDP `max_payload_size_bytes > 1468` 明确 validation error，不自动 clamp。
- **非目标：**
  - 不实现 shared W5300 socket conflict；
  - 不修改 DSP transport；
  - 不修改 S-Function runtime；
  - 不加入 PC peer/local port Project 字段。
- **最小验证：**
  - create default UDP；
  - V4 round-trip；
  - exact settings fields；
  - TCP↔UDP↔SCI switch canonicalization；
  - UDP payload 1468/1469 边界；
  - 现有 TCP/SCI model tests relevant regression。

## UDP-S1-02：收敛 W5300 TCP/UDP Shared Resource Validation

- **对应 FR：** FR-011～FR-017
- **前置任务：** UDP-S1-01
- **目标：**
  1. TCP + UDP 共享 W5300 Socket 0～7 资源域；
  2. duplicate Socket 跨 TCP/UDP 必须阻断；
  3. TCP port 仅在 TCP scope 内唯一；
  4. UDP port 仅在 UDP scope 内唯一；
  5. 同数值 TCP Port / UDP Port 合法；
  6. any-W5300 (`tcp || udp`) 激活 `project.common.network` validation；
  7. any-W5300 激活既有 W5300 Platform Reserved Resources；
  8. UDP 使用独立 `UDP_PORT_INVALID` / `UDP_PORT_DUPLICATE` 等诊断，不冒充 TCP；
  9. SCI-only 行为保持不变。
- **非目标：**
  - 不实现 runtime socket allocation；
  - 不增加“总 W5300 instance 数”第二套冗余规则；
  - 不探测真实 W5300 socket 状态。
- **最小验证：**
  - TCP0 + UDP0 collision；
  - TCP5000 + UDP5000 allowed；
  - duplicate UDP port blocked；
  - any-W5300 Network activation；
  - SCI-only Network bypass regression；
  - existing W5300 GPIO reservation regression。

## UDP-S1-03：实现 UDP Copy / Summary / Session Model 行为

- **对应 FR：** FR-018～FR-022
- **前置任务：** UDP-S1-01～S1-02
- **目标：**
  1. IoDevice selector 支持：
     ```text
     W5300 TCP
     W5300 UDP
     SCI
     ```
  2. default Instance 仍为 W5300 TCP；
  3. UDP transport summary：
     ```text
     Socket n / UDP port
     ```
     或当前统一 summary style 的等价文本；
  4. Copy UDP 时复制非独占设置，但不允许产生资源冲突；
  5. Copy 的新 Socket + UDP Port 由用户明确给定，不自动猜测空闲资源；
  6. Project session/preview/report 使用统一 IoDevice-aware summary。
- **非目标：**
  - 不实现 GUI 布局；
  - 不实现 UDP runtime；
  - 不修改 Interface Hash transport 语义。
- **最小验证：**
  - copy UDP；
  - summary；
  - switch type 后无 stale setting；
  - existing TCP/SCI copy regression。

## UDP-S1-04：App 增加 W5300 UDP 配置界面

- **对应 FR：** FR-018～FR-022
- **前置任务：** UDP-S1-03
- **目标：**
  1. IoDevice 下拉加入 `W5300 UDP`；
  2. UDP Detail 仅显示：
     ```text
     Socket Number
     UDP Port
     ```
  3. 不显示 Remote IP / PC local port / peer port；
  4. TCP/SCI UI 保持既有字段；
  5. Instance Table / Preview / Issues 使用统一 summary；
  6. 切换 IoDevice 时 UI 与 canonical settings 同步；
  7. UDP payload 超限在 Issues/Generate validation 中明确显示。
- **非目标：**
  - 不做像素级 UI 测试；
  - 不新增高级 UDP networking options；
  - 不加入 peer 选择。
- **最小验证：**
  - App model state；
  - dynamic field visibility；
  - UDP defaults；
  - summary；
  - validation surfaced；
  - TCP/SCI UI relevant regression。

### UDP Stage 1 Gate：UDP-G1

必须确认：

- Project 仍为 V4；
- `w5300_udp` canonical settings 正确；
- TCP schema 未被重命名；
- TCP/UDP shared Socket collision 正确；
- TCP/UDP Port namespace 分离；
- any-W5300 Network/platform activation 正确；
- UDP max payload 1468；
- Copy/switch/summary/App 行为与 Frozen requirements 一致；
- Stage 1 未实现 DSP/PC UDP runtime。

---

# 6. UDP Stage 2：W5300 Socket UDP Hardware Primitives

Stage 2 只扩展 `c2837x_w5300_socket.*` 到足以支持 native UDP 的公共硬件/command primitives。
**本 Stage 不接 Core IoDevice semantics，不实现 peer/session/V1 state。**

## UDP-S2-01：实现 Native UDP OPEN 与 Simple CLOSE Primitive

- **对应 FR：** FR-023～FR-027、FR-042～FR-043
- **前置门禁：** UDP-G1
- **主要对象：**
  - `dsp/inc/c2837x_w5300_socket.h`
  - `dsp/src/c2837x_w5300_socket.c`
  - 必要 host/mock test fixture
- **目标：**
  1. 保持现有 TCP `socket_open()` / TCP target-state 语义不变；
  2. 增加正式 native UDP OPEN primitive；
  3. UDP OPEN 完成条件固定为 `SOCK_UDP`；
  4. 复用现有 command lifecycle，不 busy-wait；
  5. UDP close 复用 generic close primitives；
  6. close 支持现有 bounded progression 和 `close_timeout_us`；
  7. native UDP close 不进入 TCP close erratum dummy-send path。
- **非目标：**
  - 不实现 PACKET-INFO；
  - 不实现 UDP send；
  - 不新增 peer/session；
  - 不重构 TCP close erratum。
- **最小验证：**
  - UDP OPEN → SOCK_UDP；
  - pending OPEN progression；
  - simple CLOSE → SOCK_CLOSED；
  - close timeout/busy contract；
  - TCP OPEN/LISTEN/CLOSE existing regression。

## UDP-S2-02：实现 UDP RX Datagram FIFO Primitives

- **对应 FR：** FR-028、FR-033～FR-036
- **前置任务：** UDP-S2-01
- **目标：**
  1. 在 SOCK_UDP 下检查 RX available；
  2. 读取 8-octet W5300 PACKET-INFO；
  3. 返回 Source IP / Source Port / DATA Size；
  4. PACKET-INFO 后不立即 issue `Sn_CR_RECV`；
  5. 支持从当前 Datagram FIFO 读取指定 DATA bytes；
  6. 只有 Datagram 完整消费/丢弃后才 commit RECV；
  7. commit RECV 复用现有 receive command progression；
  8. socket primitive 不解析 V1 Message Type/Protocol Version/Hash/step。
- **非目标：**
  - 不实现 active peer filtering；
  - 不判断 SIM_START；
  - 不建立 full-frame software buffer；
  - 不改变 TCP `socket_recv()`。
- **最小验证：**
  - PACKET-INFO fields；
  - DATA staged read；
  - no early RECV；
  - final commit RECV；
  - representative zero/normal DATA physical flow；
  - TCP receive regression。

## UDP-S2-03：实现 UDP Atomic Datagram TX Primitive

- **对应 FR：** FR-037～FR-040
- **前置任务：** UDP-S2-01
- **目标：**
  1. UDP send primitive 与 TCP `socket_send()` 分离；
  2. TX free space < whole Datagram 时返回 pending/no-write；
  3. TX free 足够后：
     - 设置 destination IP；
     - 设置 destination port；
     - 一次写完整 Datagram；
     - 设置完整 TX WRSR；
     - issue exactly one SEND；
  4. 复用已有 SEND command progression；
  5. SEND pending 时不重复写 FIFO、不重复 issue SEND；
  6. SENDOK/TIMEOUT 由上层 Channel 使用；
  7. 不改变 TCP partial stream send。
- **非目标：**
  - 不定义 Core positive progress；
  - 不绑定 Session Peer；
  - 不实现 retransmit。
- **最小验证：**
  - free < whole size → no write；
  - free >= whole size → exactly one full write/SEND；
  - pending no recopy；
  - SENDOK/TIMEOUT progression；
  - existing TCP partial-send regression。

### UDP Stage 2 Gate：UDP-G2

必须确认：

- `c2837x_w5300_socket.*` 保持最小硬件 command state；
- peer/session/V1 语义未污染 socket layer；
- UDP OPEN 目标是 SOCK_UDP；
- RX PACKET-INFO / delayed RECV commit 正确；
- TX whole-Datagram primitive 正确；
- native UDP close 不进入 TCP erratum；
- 相关现有 TCP socket regression 实际通过；
- Stage 2 未实现 Core UDP Channel。

---

# 7. UDP Stage 3：DSP `w5300_udp` IoDevice Channel

Stage 3 新增独立 UDP Channel，并接入现有 Core API V2。

## UDP-S3-01：建立 UDP Channel 数据结构、OPEN/LISTEN 与 Candidate Peer

- **对应 FR：** FR-023、FR-027～FR-030、FR-042～FR-044
- **前置门禁：** UDP-G2
- **新增对象：**
  ```text
  dsp/inc/c2837x_w5300_udp_channel.h
  dsp/src/c2837x_w5300_udp_channel.c
  ```
- **目标：**
  1. 定义独立 `C2837xW5300UdpChannel`；
  2. Channel 保存：
     - W5300 socket；
     - candidate/current peer endpoint state；
     - current Datagram length/consumed/active；
     - pending UDP TX；
     - bounded close state/timer；
     实现允许使用一个 endpoint storage + validity/state 标志，不要求物理保存两份 candidate/session peer。
  3. `channel_init/open/listen/get_connection_state/close` 接入现有 IoDeviceOps；
  4. SOCK_UDP + no Datagram → logical LISTENING；
  5. Datagram 到达后只读取 PACKET-INFO，建立 candidate，logical CONNECTED；
  6. `get_connection_state()` 不读取 V1 Header；
  7. close 清所有 UDP-private state。
- **非目标：**
  - 不实现完整 RX payload；
  - 不实现 TX；
  - 不确认合法 SIM_START；
  - 不修改 Core API。
- **最小验证：**
  - CLOSED→OPEN→LISTENING；
  - candidate→CONNECTED；
  - no V1 Header consumption；
  - close clears state；
  - reopen/relisten。

## UDP-S3-02：实现 DSP UDP RX Adapter 与 Peer Filtering

- **对应 FR：** FR-030～FR-036、FR-065、FR-073～FR-074
- **前置任务：** UDP-S3-01
- **目标：**
  1. Core `receive(...,4)` 从当前 Datagram FIFO 读取 V1 Header；
  2. transport 允许仅读取该 Header 中 `payload_length` 验证 physical boundary；
  3. 合法条件：
     ```text
     M == 4 + payload_length
     ```
  4. Header semantic validation 仍由 Core；
  5. 后续 payload receive 只能来自同一 Datagram；
  6. zero-payload Frame 在 Header 完成后 commit RECV；
  7. active session 只接受 current peer；
  8. alien peer Datagram 完整消费/drop，`receive()` 返回 no progress；
  9. alien peer 不刷新 Core timeout；
  10. 无 full-frame DSP RAM buffer。
- **关键实现边界：**
  - UDP Channel 只能读取 `payload_length` 做 physical framing；
  - 不解析 Message Type、Protocol Version、Hash、step index 或 RESPONSE semantic。
- **非目标：**
  - 不实现 reorder/retry；
  - 不建立 peer takeover；
  - 不改变 Core header validator。
- **最小验证：**
  - exact Datagram；
  - M<4；
  - M>1472（代表性 case：PACKET-INFO DATA size = 1473，必须 reject/session failure，且不进入 payload receive）；
  - M!=4+N；
  - zero payload；
  - alien peer drop/no timeout refresh；
  - same peer receive；
  - no cross-Datagram concatenation。

## UDP-S3-03：实现 DSP UDP Atomic IoDevice Send

- **对应 FR：** FR-037～FR-041、FR-065～FR-066、FR-073
- **前置任务：** UDP-S3-01、UDP-S2-03
- **目标：**
  1. IoDevice `send()` 合同：
     ```text
     0                pending
     count_octets     confirmed complete
     <0               error
     ```
  2. 不允许 partial positive progress；
  3. first call：
     - 必须有 candidate/session destination；
     - whole frame <= UDP max；
     - TX free 不足 → 0 / no write；
     - 足够 → one whole Datagram / one SEND / return 0；
  4. pending call：
     - 不 recopy；
     - 不 reissue；
     - SEND unfinished → 0；
     - SENDOK → full positive count；
     - TIMEOUT/error → <0；
  5. candidate peer 可用于 initial SIM_START error RESPONSE；
  6. session peer 用于正常 RESPONSE/OUTPUT_DATA。
- **非目标：**
  - 不等待 peer ACK；
  - 不实现 retry；
  - 不修改 Core send loop。
- **最小验证：**
  - atomic progress；
  - no partial positive；
  - no duplicate FIFO write；
  - candidate/session destination；
  - SENDOK / TIMEOUT；
  - Core send-loop integration。

## UDP-S3-04：收敛 Session Ownership、SIM_STOP、Timeout/Error 与 Reacquisition

- **对应 FR：** FR-030～FR-032、FR-042～FR-044、FR-065～FR-075
- **前置任务：** UDP-S3-02～S3-03
- **目标：**
  1. candidate source 在 provisional Session 期间作为 transport source filter / response destination；若现有 Core 成功接受 SIM_START 并进入 `SIM_RUNNING`，该 endpoint 在协议语义上即成为 Session Peer；不要求新增 Core→Channel promotion hook，也不要求 UDP Channel 感知或解析 SIM_START 验证结果；
  2. invalid/non-SIM_START candidate 由现有 Core protocol state 拒绝；若 Core 拒绝 SIM_START，则沿现有 error-response → terminate → close 路径清除该 endpoint；
  3. active peer 不可被其他 sender 抢占；
  4. same peer 在 SIM_RUNNING 再发 SIM_START 由 Core 报现有 protocol/state error；
  5. SIM_STOP → terminate → close → reopen；
  6. interaction/transfer timeout 继续由 Core；
  7. close 后新 peer 可建立新 Session；
  8. PC crash / lost SIM_STOP 依靠 interaction timeout 回收；
  9. late stale Datagram 在 reopen 后按新 candidate + Core WAIT_SIM_START 语义处理；
  10. 不建立 reconnect/resume protocol。
- **非目标：**
  - 不增加 Core hook；
  - 不增加 heartbeat；
  - 不增加 force reset/takeover API。
- **最小验证：**
  - normal SIM_START→running→SIM_STOP→reacquire；
  - active alien cannot steal；
  - invalid candidate cleanup；
  - timeout cleanup；
  - lost SIM_STOP recovery path；
  - close contract `>0/0/<0`。

### UDP Stage 3 Gate：UDP-G3

必须确认：

- 独立 UDP Channel 已接入现有 IoDeviceOps；
- Core API V2 未改变；
- logical LISTENING/CONNECTED 正确；
- one V1 Frame = one Datagram；
- exact physical length；
- candidate/session peer ownership；
- alien peer drop；
- TX atomic positive-progress contract；
- normal close/reopen；
- no heartbeat/retry/session resume；
- DSP host/mock UDP Channel tests 实际通过；
- 相关 Core/TCP regression 实际通过。

---

# 8. UDP Stage 4：PC UDP Transport 与 Shared Protocol Binding

Stage 4 实现 PC `SOCK_DGRAM` transport，并使用真实 OS localhost UDP socket验证 production-derived/generated transport。

## UDP-S4-01：新增 `pc_udp` Template / Socket / Deadline / Atomic Send

- **对应 FR：** FR-045～FR-047、FR-052～FR-053、FR-065～FR-068
- **前置门禁：** UDP-G3
- **新增模板：**
  ```text
  app/templates/pc_udp.c.in
  app/templates/pc_udp.h.in
  ```
- **目标：**
  1. cross-platform UDP socket 支持范围继承当前 W5300 TCP host 基线；
  2. `SOCK_DGRAM + connect(DSP_IP,DSP_UDP_PORT)`；
  3. OS ephemeral local port；
  4. UDP connect 不当作 reachability handshake；
  5. reuse existing deadline/error style；
  6. whole V1 Frame exactly one OS send；
  7. writable wait 使用现有 absolute deadline；
  8. OS explicit error → SOCKET；
  9. no response → later protocol wait TIMEOUT；
  10. close/cleanup 与现有 PC transport lifecycle 一致，确保 socket/resource 正确释放。
- **非目标：**
  - 不新增 runtime local-port parameter；
  - 不增加 ACK/retry；
  - 不实现 receive staging（留 S4-02）。
- **最小验证：**
  - init/connect/close；
  - one complete Datagram send；
  - OS send failure mapping；
  - deadline/writable timeout；
  - no partial-send loop。

## UDP-S4-02：实现 PC UDP Datagram Staging Receive 与 Framing Diagnostics

- **对应 FR：** FR-048～FR-053、FR-069～FR-072
- **前置任务：** UDP-S4-01
- **目标：**
  1. private complete Datagram staging；
  2. 必须能检测 >1472 oversize；
  3. first `recv_exact(...,4)` 实际从 OS 读取整个 Datagram；
  4. 只返回前 4 octets 给 protocol；
  5. transport 只解析 Header `payload_length` 做 physical boundary；
  6. later payload 从同一 staged Datagram 返回；
  7. zero-payload Header delivery 后清 staging；
  8. no cross-Datagram concatenation；
  9. `<4` → TRUNCATED/recv_header；
  10. shorter-than-declared → TRUNCATED/recv_payload；
  11. longer-than-declared / oversize / odd physical framing → existing PAYLOAD_LENGTH/framing category；
  12. Header+Payload 共用一个 absolute deadline。
- **非目标：**
  - 不解析 Message Type / Hash / step / RESPONSE；
  - 不使用多个 Datagram 补帧；
  - 不扩展 public error enum。
- **最小验证：**
  - 4-byte zero payload；
  - normal payload；
  - short header；
  - short declared；
  - long declared；
  - oversize detection；
  - no cross-Datagram read；
  - absolute deadline continuity。

## UDP-S4-03：复用单一 `protocol.c.in` 并增加 UDP Binding

- **对应 FR：** FR-045、FR-047、FR-051、FR-054、FR-065～FR-075
- **前置任务：** UDP-S4-01～S4-02
- **目标：**
  1. 不新增 UDP protocol template；
  2. 增加 `bind_udp_protocol()` 或等价明确 binding；
  3. protocol API/semantic 保持：
     ```text
     SIM_START
     RESPONSE
     INPUT_DATA
     OUTPUT_DATA
     SIM_STOP
     ```
  4. UDP adapter 只承担 physical Datagram boundary；
  5. protocol 继续验证 Message Type / Version / Hash / step / response；
  6. UDP S-Function 保持 0 transport runtime parameter；
  7. CONNECT/STEP/TERMINATE timeout macros 继续统一存在；
  8. UDP reachability 由 SIM_START→RESPONSE 体现；
  9. `mdlTerminate()` SIM_STOP 保持 best-effort / no ACK。
- **非目标：**
  - 不完成 output model/build closure（留 Stage 5）；
  - 不修改 TCP/SCI protocol semantics。
- **最小验证：**
  - rendered/bound protocol symbol correctness；
  - TCP binding regression；
  - SCI binding regression；
  - UDP protocol startup/step/terminate static checks。

## UDP-S4-04：真实 localhost UDP 最小闭环测试

- **对应 FR：** FR-066～FR-072、FR-075、FR-078
- **前置任务：** UDP-S4-03
- **目标：**
  1. 使用真实 OS localhost UDP socket；
  2. 直接 exercise production-derived/generated `pc_udp` transport；
  3. test peer 只实现最小 harness，不实现完整 DSP simulator；
  4. 完成：
     ```text
     SIM_START
     RESPONSE
     INPUT_DATA
     OUTPUT_DATA
     SIM_STOP
     ```
  5. 验证 timeout；
  6. 验证 short/mismatch Datagram diagnostics；
  7. 验证 whole-Datagram send/staging receive。
- **非目标：**
  - 不建立随机 loss/reorder matrix；
  - 不做长期稳定性；
  - 不做性能 Gate。
- **最小验证：**
  - Frozen FR-078 明确列出的最小闭环与 framing/timeout cases。
- **MEX 编译：**
  - 若当前环境已具备可用 MEX C compiler，可在本任务末尾执行代表性 UDP MEX 编译；
  - 若没有，记录 `NOT_EXECUTED / CAPABILITY`，不阻断进入 Stage 5 的纯源码/host 集成，但最终 G6 必须再次明确该状态。

### UDP Stage 4 Gate：UDP-G4

必须确认：

- `pc_udp` 使用 SOCK_DGRAM；
- no handshake/retry/ACK；
- one frame one send；
- Datagram staging/framing 正确；
- shared protocol template 未分叉；
- UDP S-Function transport parameter contract 正确；
- 真实 OS localhost UDP 最小闭环实际通过；
- 关键 timeout/framing diagnostics 实际通过；
- MEX compile 若执行则记录真实结果，否则明确 capability 状态。

---

# 9. UDP Stage 5：DSP / S-Function Generated Closure 与 Mixed Integration

Stage 5 把前面已经完成的 DSP/PC runtime 纳入正式生成系统。
核心原则：**source selection 按实际 transport set 计算，而不是 TCP/SCI 二选一。**

## UDP-S5-01：扩展 DSP Output Model 为 `useW5300/useTcp/useUdp/useSci`

- **对应 FR：** FR-055～FR-058、FR-064、FR-079
- **前置门禁：** UDP-G4
- **目标：**
  1. 显式计算：
     ```text
     useTcp
     useUdp
     useSci
     useW5300 = useTcp || useUdp
     ```
  2. any-W5300 输出 shared regs/HAL/socket；
  3. TCP channel 仅 `useTcp` 时输出；
  4. UDP channel 仅 `useUdp` 时输出；
  5. SCI runtime 仅 `useSci` 时输出；
  6. UDP-only 不带 TCP channel；
  7. mixed dependency/fingerprint 只记录真实 closure；
  8. platform `use_w5300` 改为 any-W5300。
- **非目标：**
  - 不处理 project-level duplicate config ownership（留 S5-02）；
  - 不改 PC output model。
- **最小验证：**
  - UDP-only；
  - TCP-only regression；
  - SCI-only regression；
  - source/dependency absence/presence。

## UDP-S5-02：收敛 Shared W5300 Project Support 与 UDP Instance Binding

- **对应 FR：** FR-015～FR-016、FR-023、FR-041、FR-059～FR-060
- **前置任务：** UDP-S5-01
- **目标：**
  1. W5300 platform config 无论 TCP/UDP 数量都只生成一次；
  2. `c2837x_w5300_project_config` 或等价全局符号只定义一次；
  3. TCP provider 与 UDP provider 不各自重复生成 shared project support；
  4. UDP Instance config 静态包含 socket/udp_port；
  5. UDP Instance Channel/IoDeviceOps 正确绑定；
  6. TCP Instance binding 不改变；
  7. mixed TCP+UDP 共享一套 network/platform init。
- **非目标：**
  - 不创建 runtime shared dispatcher；
  - 不让 TCP/UDP channel 共用一个 instance state；
  - 不修改 protocol hash。
- **最小验证：**
  - TCP+UDP generated project source 中 shared config exactly once；
  - UDP-only binding；
  - mixed bindings；
  - existing TCP/SCI binding regression。

## UDP-S5-03：扩展 S-Function Output Model / Renderer / Build Closure

- **对应 FR：** FR-045、FR-054、FR-061～FR-064
- **前置任务：** UDP-S4-03、UDP-S5-01
- **目标：**
  1. transport source selection 显式三路：
     ```text
     w5300_tcp -> pc_socket
     w5300_udp -> pc_udp
     sci       -> pc_serial
     ```
  2. unknown type 明确 error，不 fallback TCP；
  3. 每个 Instance 输出：
     - shared generated sfun/common files；
     - one protocol pair；
     - one transport pair；
     - one build script；
  4. UDP MEX 只编译 `pc_udp`，不带 `pc_socket/pc_serial`；
  5. build script source selection 与 output model 完全一致；
  6. Interface Hash 不因 transport-specific fields 改变；
  7. existing `max_payload_size_bytes` 继续按既有 Hash 规则参与 Hash。
- **非目标：**
  - 不把 mixed DSP transport 复制进单个 MEX；
  - 不创建 transport-neutral runtime dispatcher。
- **最小验证：**
  - UDP generated file list；
  - TCP/SCI regression；
  - unknown type failure；
  - build source list；
  - hash transport invariance + max_payload sensitivity。

## UDP-S5-04：Mixed Deterministic Generation / Preview / Candidate Regression

- **对应 FR：** FR-055～FR-064、FR-076、FR-079
- **前置任务：** UDP-S5-01～S5-03
- **目标：**
  1. 代表性项目：
     ```text
     UDP only
     TCP + UDP
     UDP + SCI
     TCP + UDP + SCI
     ```
  2. 检查 DSP source closure；
  3. 检查 PC Instance closure；
  4. 检查 shared W5300 project config only once；
  5. 检查 Preview/Snapshot/Commit candidate determinism；
  6. 检查 dependency/fingerprint；
  7. 保持用户文件保护事务。
- **非目标：**
  - 不穷举所有 Instance 数量/Socket/Port/Payload；
  - 不建立组合爆炸矩阵。
- **最小验证：**
  - 上述四种代表组合；
  - deterministic regeneration；
  - path conflict / duplicate symbol absence；
  - existing TCP+SCI representative regression。

### UDP Stage 5 Gate：UDP-G5

必须确认：

- DSP source closure 真实按 used transport set；
- W5300 common source/platform config 只生成一次；
- UDP-only 无 TCP channel；
- mixed TCP+UDP/UDP+SCI/三者混合正确；
- 每个 MEX 只带一个 PC transport；
- unknown IoDevice 不 fallback TCP；
- shared protocol template；
- Interface Hash 现有合同保持；
- deterministic generation representative tests 实际通过。

---

# 10. UDP Stage 6：最终软件证据、编译能力、文档与移交

Stage 6 不新增功能，只收敛真实软件证据、可用编译环境结果和最终用户移交。

## UDP-S6-01：执行完整增量软件 Regression 与 Capability Build Check

- **对应 FR：** FR-076～FR-080
- **前置门禁：** UDP-G5
- **目标：**
  1. 汇总并执行 Frozen requirements 要求的实际可执行自动测试；
  2. 至少覆盖：
     - Project/App UDP tests；
     - DSP host/mock UDP tests；
     - relevant existing TCP regression；
     - PC real localhost UDP tests；
     - mixed deterministic generation tests；
  3. 不建立额外大矩阵；
  4. 检测实际 MEX compiler：
     - 有 → 编译代表性 UDP MEX；
     - 无 → `NOT_EXECUTED / CAPABILITY`；
  5. 检测实际 TI C2000 compiler/CCS 能力：
     - 有 → 编译代表性 generated DSP output；
     - 无 → `NOT_EXECUTED / CAPABILITY`；
  6. Host compiler 结果不得冒充 TI compile。
- **非目标：**
  - 不做硬件通信；
  - 不做随机 loss/long-run；
  - 不把性能作为 Gate。
- **产物：**
  - 真实测试清单与结果；
  - 编译能力状态；
  - 未执行项目列表。

## UDP-S6-02：更新 UDP 使用文档与 Traceability

- **对应 FR：** FR-076～FR-082；Frozen §8 governance
- **前置任务：** UDP-S6-01
- **目标：**
  1. 更新 README/current docs 的 IoDevice 列表；
  2. 更新 Project/App 使用说明；
  3. 更新 Simulink/MEX UDP 使用说明；
  4. 明确：
     - UDP one-frame-one-Datagram；
     - max payload 1468；
     - no reliability/retry；
     - PC ephemeral local port；
     - DSP learns peer from SIM_START；
  5. 更新 requirements traceability；
  6. 记录真实 build/test 状态；
  7. 未实机验证不得写成 hardware PASS；
  8. 只更新因新增 `w5300_udp` 而已经失真的现有文档和 current-authority / traceability，不要求新建完整产品级 UDP 用户手册。
- **非目标：**
  - 不重写历史 SCI/W5300 文档；
  - 不加入未实现的 roadmap 功能。

## UDP-S6-03：完成 FR-001～FR-082 Final Audit 与用户实机移交

- **对应 FR：** FR-001～FR-082
- **前置任务：** UDP-S6-02
- **目标：**
  1. 完成 FR traceability final audit；
  2. 确认所有开发侧必须实现的 FR 有源码/生成/测试证据；
  3. 明确所有 `NOT_EXECUTED / CAPABILITY`；
  4. 明确 FR-081：
     ```text
     USER_VALIDATION_PENDING
     ```
     直到用户实际验证；
  5. 生成最终跨对话移交摘要；
  6. 给出用户最小实机验证步骤：
     - SIM_START；
     - 若干连续 PIL steps；
     - I/O correctness；
     - SIM_STOP；
     - 再次 Session；
     - 可选 TCP/UDP latency/performance 比较。
- **非目标：**
  - Codex 不宣称硬件通过；
  - 不新增功能；
  - 不为 performance 设置固定百分比 Gate。

### UDP Stage 6 Gate：UDP-G6

开发侧 Gate 必须确认：

- FR-001～FR-080、FR-082 的开发责任已经闭合；
- FR-081 明确处于真实 `USER_VALIDATION_PENDING` 或用户已提供通过证据；
- 所有要求的自动测试均有真实结果；
- MEX/DSP compile 有能力则实际执行，无能力则明确标记；
- 文档/traceability 与真实状态一致；
- 不存在伪造 PASS；
- 工作区、HEAD、Remote HEAD、提交状态真实记录；
- 不存在未解决的 blocker。

`UDP-G6` 通过只表示 **开发侧 UDP 增量实现闭合**。
如果 FR-081 尚未由用户执行，最终项目状态必须明确写：

```text
Development gate : PASS
Hardware UDP PIL : USER_VALIDATION_PENDING
```

---

# 11. 建议提交序列

Codex 不负责擅自提交。以下仅作为用户审核后提交时的建议粒度：

```text
UDP-S0-02  docs: switch current authority to W5300 UDP cycle

UDP-S1-01  feat(project): add w5300_udp provider and canonical settings
UDP-S1-02  feat(project): validate shared W5300 TCP UDP resources
UDP-S1-03  feat(app): add UDP copy and transport summaries
UDP-S1-04  feat(app): add W5300 UDP instance configuration UI

UDP-S2-01  feat(w5300): add native UDP open and close primitives
UDP-S2-02  feat(w5300): add UDP datagram receive primitives
UDP-S2-03  feat(w5300): add atomic UDP datagram transmit primitive

UDP-S3-01  feat(dsp): add W5300 UDP channel lifecycle
UDP-S3-02  feat(dsp): add UDP datagram receive and peer filtering
UDP-S3-03  feat(dsp): add atomic UDP IoDevice send
UDP-S3-04  feat(dsp): finalize UDP session cleanup and reacquisition

UDP-S4-01  feat(pc): add UDP socket transport
UDP-S4-02  feat(pc): add UDP datagram staging and framing validation
UDP-S4-03  feat(pc): bind shared V1 protocol to UDP transport
UDP-S4-04  test(pc): verify production UDP transport on localhost

UDP-S5-01  feat(codegen): add transport-set DSP source closure
UDP-S5-02  feat(codegen): share W5300 project support across TCP and UDP
UDP-S5-03  feat(codegen): add UDP S-Function output and build closure
UDP-S5-04  test(codegen): verify deterministic mixed transport generation

UDP-S6-01  test: run final W5300 UDP software regression
UDP-S6-02  docs: document W5300 UDP transport and traceability
UDP-S6-03  docs: finalize W5300 UDP development audit
```

如果某个小任务实际只修改测试或文档，应以真实 diff 为准调整提交标题，不机械追求上述字符串。

---

# 12. 关键风险与控制

## 12.1 TCP 回归风险

**风险：** `c2837x_w5300_socket.*` 当前包含 TCP stream 和 TCP close erratum 相关状态，增加 UDP primitives 时容易破坏 TCP。

**控制：**
- UDP primitive 独立，不把 protocol branch 塞进 TCP `socket_send/recv`；
- 每个 Stage 2 任务运行相关现有 TCP regression；
- UDP close 明确跳过 erratum，但不删除 TCP erratum。

## 12.2 Datagram 与 Core stream-shaped API 适配风险

**风险：** Core 分两次读取 Header/Payload，而 UDP Datagram 必须原子。

**控制：**
- W5300 RX FIFO 作为 staging；
- PACKET-INFO 后延迟 RECV commit；
- transport 只读取 `payload_length` 做 physical boundary；
- 不跨 Datagram 拼接；
- no full-frame DSP RAM buffer。

## 12.3 Candidate/Session Peer 责任错位

**风险：** transport 过早把任意 Datagram source 当作长期 session peer，或在 active session 被其他 sender 抢占。

**控制：**
- candidate 与 session peer 分离；
- legitimate SIM_START 由 Core semantic 形成 session；
- active alien peer drop；
- close/reopen 后才允许新 peer。

## 12.4 Shared W5300 Project Support 重复定义

**风险：** TCP provider 与 UDP provider 各自产生同名 `c2837x_w5300_project_config`。

**控制：**
- shared support ownership 在 Stage 5 显式收敛；
- mixed TCP+UDP generation test 必须检查全局定义只出现一次。

## 12.5 UDP `connect()` 被误当作在线判断

**风险：** PC UDP connect 成功被错误解释为 DSP reachable。

**控制：**
- 文档/实现均保持 connect 只固定 endpoint；
- SIM_START→RESPONSE 才证明 protocol peer 工作；
- no response → STEP timeout；
- OS explicit socket error 保留 SOCKET。

## 12.6 测试过度扩张

**风险：** 把 UDP 天生不可靠转化为产品级 loss/reorder/long-run 测试工程。

**控制：**
- 严格遵守 FR-076～FR-082；
- 只做 representative framing/timeout/peer/closure tests；
- 不把 performance improvement percentage 设置为 Gate。

---

# 13. 明确不进入本计划的内容

本计划禁止提前实现或作为固定 Gate：

- Wire Protocol V2；
- Project Format V5；
- Core API V3；
- UDP ACK/NAK；
- retransmission；
- packet retry；
- heartbeat / keepalive；
- reorder buffer；
- duplicate suppression buffer；
- lost-step compensation；
- automatic peer/session reconnect/resume protocol；
- peer takeover / FORCE_CONNECT；
- Session ID；
- UDP Magic；
- UDP CRC；
- incoming IP fragmentation；
- jumbo frame；
- broadcast；
- multicast；
- 8 Socket 满载并发压力；
- random packet-loss matrix；
- long-duration stability matrix；
- throughput benchmark Gate；
- TCP→UDP 必须提升固定百分比；
- PC local UDP port Project 参数；
- runtime remote-peer selector；
- 重新设计现有 TCP stream transport；
- 重新设计现有 SCI transport；
- 恢复旧单实例/shared `g_ctx` 方案。

---

# 14. 本计划完成定义

W5300 UDP 增量开发侧完成需要同时满足：

1. Frozen requirements `FR-001～FR-082` 已完成最终 traceability；
2. `w5300_udp` 可作为第三种 IoDevice 在 Project/App 中配置；
3. TCP/UDP W5300 Socket shared resource 规则正确；
4. UDP payload 上限 1468；
5. DSP native UDP OPEN/RX/TX/CLOSE primitives 正确；
6. DSP UDP Channel 实现 candidate/session peer 和 one-frame-one-Datagram；
7. PC `pc_udp` 使用 SOCK_DGRAM + OS endpoint connect；
8. PC staging/framing 与 shared protocol binding 正确；
9. UDP-only / TCP+UDP / UDP+SCI / TCP+UDP+SCI generation closure 正确；
10. shared W5300 project config 只生成一次；
11. existing TCP/SCI required regression 没有被本增量破坏；
12. Frozen requirements 要求的软件测试有真实结果；
13. 可用编译环境中的 MEX/TI compile 有真实结果；不可用时明确 capability 状态；
14. 文档/traceability 与真实实现一致；
15. 未执行的用户硬件验证明确记录，不伪造 PASS。

若用户尚未执行实机 UDP PIL：

```text
Development Implementation = COMPLETE
Development Gate           = PASS
Hardware UDP PIL           = USER_VALIDATION_PENDING
```

仍然是合法的开发侧完成状态。

---

# 15. 计划审核与批准规则

本文件当前状态：

```text
Approved for Implementation
```

批准结论：

1. 本计划已经完成 Final Approval Audit；
2. 计划与 Frozen requirements `FR-001～FR-082` 对齐；
3. Stage、Gate、Codex 小任务边界已批准；
4. Stage 0 负责将本 approved plan 切换为 Repository root `plan.md` current authority；
5. 在 approved plan 与 Frozen requirements 都有明确 Git 提交、且 `UDP-G0` 通过前，不进入 `UDP-S1-01` 产品实现；
6. 本批准只表示计划可实施，不代表任何 UDP-S0～S6 或 UDP-G0～G6 任务已经开始或通过。

正式批准文件：

```text
plan_w5300_udp_iodevice_v1.0_approved.md
```
