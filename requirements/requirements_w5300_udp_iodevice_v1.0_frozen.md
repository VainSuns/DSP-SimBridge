# DSP-SimBridge W5300 UDP IoDevice 增量需求规格

> **状态：Frozen V1.0**  
> **冻结日期：2026-09-06**  
> **适用项目：DSP-SimBridge / C2837xBlock**  
> **增量目标：在当前已完成的 W5300 TCP + SCI 多 IoDevice 基线上新增 `w5300_udp` IoDevice，用于降低 PIL 调试中 TCP stream/connection 带来的额外开销，同时保持现有 Project V4、Core API V2 与 Wire Protocol V1。**

---

## 0. 文档定位与继承基线

本文件是 **W5300 UDP IoDevice 增量冻结需求**。它只定义本次新增 `w5300_udp` 所要求的新行为，以及为支持 UDP 必须修改的既有合同。

本文件未明确修改的既有行为继续继承当前仓库已完成实现，不在本文件重复定义，也不得借本次增量恢复旧需求、旧计划、旧单实例方案或其他已废弃设计。

当前讨论时参考的仓库基线为：

```text
Repository：VainSuns/DSP-SimBridge
Baseline branch：main
Baseline HEAD：5b7466d23354a40ec58e4d14113e171d3f14bd87
```

本增量的直接前置规范为：

```text
直接前置冻结需求：
requirements/requirements_sci_iodevice_v1.0_frozen.md

直接前置实施计划：
plan.md
```

历史多实例需求 `requirements_multi_iodevice_v1.0_frozen_rev2.md` 仅作为历史追溯材料，不恢复为当前实施 authority。

当前版本基线：

```text
Project Format Version = 4
Wire Protocol Version  = 1
Core API Version       = 2
```

历史 V1 wire protocol 不可变基线：

```text
Commit：f209302ce3efc0fa15d217550f6d9b1dc00487fb
Tag：legacy-v1-protocol-baseline
```

实施开始前必须重新通过 GitHub/本地 Git 核对 Repository、Branch、Local HEAD、Remote HEAD、`git status`、冻结需求提交、实施计划提交以及前置任务提交；不得把本文件记录的讨论时基线当作实施时实时 Git 状态。

解释规则：

1. 本文件未明确修改的 W5300 TCP、SCI、Project V4、多实例 Core、App、生成、PC/S-Function 和 V1 wire protocol 行为保持不变；
2. `w5300_udp` 是第三种 IoDevice，不替代 `w5300_tcp`；
3. 不得新增第二套 Core transport API，不得恢复 shared `g_ctx`、旧单实例 Core、自动 reconnect/retry/resend 或其他已关闭方案；
4. 本文件只定义需求，不定义正式 Stage、Gate 或 Codex 小任务；实施计划必须在需求冻结后单独制定；
5. 本项目定位为研发使用，优先保证结构清晰、实现直接和热点路径效率，不以产品级网络可靠性为目标；
6. 未实际执行的测试、编译、硬件验证和门禁不得声明为 PASS。

---

# 1. 范围、版本与 Wire Contract

### FR-001：新增第三种 IoDevice

在现有：

```text
w5300_tcp
sci
```

之外新增：

```text
w5300_udp
```

同一 DSP 工程允许 `w5300_tcp`、`w5300_udp`、`sci` 混合存在。

### FR-002：静态 Instance → IoDevice 绑定保持

每个算法 Instance 在生成期静态绑定一个 IoDevice。不得在 DSP 运行时在 TCP、UDP、SCI 之间动态切换。

### FR-003：现有多实例 Core 合同保持

UDP 必须接入现有 `C2837xBlock_IoDeviceOps` 与实例化 Core。

公共 Core 用户 API、实例生命周期和 Core API V2 语义保持不变，不为 UDP 新增第二套 Core transport API。

### FR-004：版本保持不变

本次增量完成后继续固定：

```text
Project Format Version = 4
Wire Protocol Version  = 1
Core API Version       = 2
```

新增 `w5300_udp` 本身不构成 Project Format 变更，不建立 V4→V5 migration。

### FR-005：V1 Wire Protocol 不变

UDP 复用现有 V1 wire protocol。

以下语义保持不变：

- 4-octet Header；
- 现有 Message Type；
- RESPONSE；
- little-endian；
- `step_index`；
- Interface Hash；
- 现有 wire error code。

不得增加：

- Magic；
- CRC；
- UDP sequence；
- UDP ACK/NAK；
- retransmission field；
- Instance ID；
- Session ID；
- transport-specific handshake frame。

### FR-006：一个 V1 Frame 对应一个 UDP Datagram

对 `w5300_udp`：

```text
1 complete V1 Protocol Frame = 1 UDP Datagram
```

因此：

- `SIM_START` = 1 Datagram；
- `RESPONSE` = 1 Datagram；
- `INPUT_DATA` = 1 Datagram；
- `OUTPUT_DATA` = 1 Datagram；
- `SIM_STOP` = 1 Datagram。

不得把一个 V1 Frame 拆成多个 UDP Datagram，也不得把多个 V1 Frame 合并进同一个 UDP Datagram。

### FR-007：UDP 不实现可靠传输层

第一版 UDP 不实现：

- retransmission；
- ACK/NAK；
- reorder buffer；
- duplicate suppression buffer；
- lost-step compensation；
- heartbeat；
- keepalive；
- automatic peer/session reconnect or resume protocol；
- peer takeover；
- packet retry。

已有 `step_index` 继续负责检测不符合协议顺序的帧。

现有 Core 在一次 Session 结束后执行 `close → reopen/listen` 以准备新的独立 Session，不属于本条禁止的 automatic peer/session reconnect or resume protocol。

### FR-008：UDP Payload 上限

按标准 IPv4 Ethernet MTU 1500：

```text
UDP payload maximum without IP fragmentation = 1472 octets
```

V1 Header 为 4 octets，因此 `w5300_udp`：

```text
max_payload_size_bytes <= 1468
```

当前默认 `1024` 保持合法。

第一版不支持依赖 IP fragmentation 的 UDP Frame；需要更大 Payload 时使用 TCP。

---

# 2. Project / App / Resource Model

### FR-009：W5300 UDP canonical settings

`w5300_udp` 的持久化配置精确为：

```matlab
iodevice.type = 'w5300_udp';

iodevice.settings = struct( ...
    'socket_number', uint16(0), ...
    'udp_port',      uint16(5000));
```

不得额外保存 PC local port、remote peer port、remote PC IP 或其他运行时 peer 信息。

### FR-010：W5300 TCP persisted schema 不变

现有 `w5300_tcp` 继续使用：

```text
socket_number
tcp_port
```

不得为了统一 TCP/UDP 而把 `tcp_port` 重命名为通用 `port`，避免引入无意义的 Project migration。

### FR-011：W5300 Socket 资源跨 TCP/UDP 全局唯一

W5300 Socket Number 仅允许：

```text
0 ... 7
```

并且必须在全部 `w5300_tcp` + `w5300_udp` Instance 间全局唯一。

例如：

```text
TCP Socket 0 + UDP Socket 0
```

必须阻断。

### FR-012：TCP Port 与 UDP Port 的冲突域分离

TCP listen port 只在 TCP Instance 间要求唯一。

UDP local port 只在 UDP Instance 间要求唯一。

允许：

```text
TCP Port 5000
UDP Port 5000
```

同时存在，只要使用不同 W5300 Socket。

### FR-013：UDP Port 范围

`udp_port` 仅允许：

```text
1 ... 65535
```

应提供独立 UDP validation issue，例如：

```text
UDP_PORT_INVALID
UDP_PORT_DUPLICATE
```

不得把 UDP 配置错误错误地报告为 `TCP_PORT_*`。

### FR-014：Network 由任意 W5300 Transport 激活

`project.common.network` 在 Project V4 中继续存在。

只要项目存在：

```text
w5300_tcp
或
w5300_udp
```

就必须参与 W5300 Network validation 和 W5300 project generation。

SCI-only 项目继续不因 Network 无效而阻断。

### FR-015：W5300 Platform Reserved Resources 由任意 W5300 激活

只要存在 TCP 或 UDP W5300 Instance，就必须启用当前 W5300 固定 EMIF/GPIO/RESET 等 Platform Reserved Resources。

TCP/UDP 共用同一套物理 W5300 平台资源。

### FR-016：W5300 Platform 只初始化一次

Mixed：

```text
TCP + UDP
```

项目中，W5300 platform initialization 仍只执行一次。

不得因存在 UDP 再初始化一遍 W5300。

### FR-017：UDP Max Payload validation

仅对 `w5300_udp` 增加：

```text
max_payload_size_bytes <= 1468
```

现有 TCP/SCI 的最大 Payload 规则不因此缩减到 1468。

把已有大 Payload TCP Instance 切换为 UDP 时，不得自动裁剪配置；应由 validation 明确报错，用户自行修改。

### FR-018：IoDevice UI 增加 W5300 UDP

Instance IoDevice 下拉至少包含：

```text
W5300 TCP
W5300 UDP
SCI
```

现有默认新建 Instance 仍保持 `W5300 TCP`，除非后续正式需求另行修改。

### FR-019：UDP Instance UI 字段

W5300 UDP Instance 至少显示：

```text
Socket Number
UDP Port
```

不得增加：

```text
Remote IP
PC IP
PC local port
Peer port
```

### FR-020：Transport Summary

统一 transport summary 至少支持：

```text
W5300 TCP → Socket 0 / TCP 5000
W5300 UDP → Socket 1 / UDP 5000
SCI       → 现有 SCI summary
```

App Instance Table、Preview、Report 和上下文显示应复用同一 IoDevice-aware summary。

### FR-021：Copy W5300 UDP Instance

复制 UDP Instance 时复制非独占配置，但必须要求新的：

```text
socket_number
udp_port
```

不得自动猜测或自动分配空闲资源。

### FR-022：IoDevice switch 必须重建 canonical settings

在 TCP/UDP/SCI 间切换时，必须使用目标 IoDevice 的 canonical settings。

例如 TCP→UDP 后不得遗留：

```text
tcp_port
```

UDP→TCP 后不得遗留：

```text
udp_port
```

非当前 IoDevice 的历史字段不得参与校验、生成、Hash 或运行时。

---

# 3. DSP W5300 UDP Transport

### FR-023：独立 UDP Channel

新增独立 DSP UDP Channel，例如：

```text
c2837x_w5300_udp_channel.c
c2837x_w5300_udp_channel.h
```

不得把 UDP 大量分支塞入当前稳定 TCP channel。

### FR-024：共用 W5300 HAL / Socket 基础设施

UDP 必须复用现有：

- W5300 registers；
- W5300 HAL；
- FIFO access；
- Sn_CR command lifecycle；
- 通用 CLOSE primitive；
- W5300 platform initialization。

不得复制第二套 EMIF/W5300 HAL。

所有 `Run()` 可达的 UDP OPEN、RX、TX、RECV commit、SEND progression 与 CLOSE progression 必须保持有界、非阻塞。不得在热点路径 busy-wait `Sn_CR`、TX free space、`SENDOK/TIMEOUT`、`SOCK_UDP` 或 `SOCK_CLOSED`，不得通过 `delay_us()` 等阻塞延时等待硬件状态完成。

### FR-025：TCP 行为保持

现有 TCP：

- stream send；
- stream receive；
- connect/listen；
- TCP close erratum workaround；

均保持既有语义。

新增 UDP 不得把 TCP send/recv 改造成 Datagram 语义。

### FR-026：UDP OPEN

UDP Socket OPEN 必须：

```text
Sn_MR = UDP
Sn_PORT = configured udp_port
Sn_CR = OPEN
```

并以：

```text
SOCK_UDP
```

作为 OPEN 完成状态。

不得把 TCP 的 `SOCK_INIT` 当作 UDP OPEN 完成状态。

### FR-027：UDP logical LISTENING

W5300 UDP 没有 TCP `LISTEN` command。

因此 Core 的 `listen()` 仅作为逻辑适配。

当硬件状态为：

```text
SOCK_UDP
```

且当前无 candidate Datagram 时，应向 Core 报告 logical `LISTENING`。

### FR-028：W5300 UDP PACKET-INFO

W5300 UDP RX 的 8-octet PACKET-INFO 必须仅由 UDP transport 使用：

```text
Source IP    4 octets
Source Port  2 octets
DATA Size    2 octets
```

不得把 PACKET-INFO 暴露给 V1 Core / Protocol。

### FR-029：Candidate Peer

在 WAIT_CONNECTION 状态收到 UDP Datagram 后，UDP Channel 可以先缓存：

```text
candidate IP
candidate port
datagram size
```

并向 Core 报告 logical `CONNECTED`。

`get_connection_state()` 不得提前消费 V1 Frame bytes，只允许读取并暂存 W5300 PACKET-INFO。

### FR-030：合法 SIM_START 建立 Session Peer

产品语义固定为：

> 合法 `SIM_START` 的 Source IP + Source UDP Port 成为当前 Session Peer。

在 Core 完成 SIM_START 验证前，transport 可保留 provisional/candidate peer。

### FR-031：Active Session 只接受当前 Peer

Session active 后，只接受：

```text
source IP == peer IP
且
source UDP port == peer port
```

的 Datagram。

其他 sender 的 Datagram：

- 必须完整消费/丢弃；
- 不得修改当前 peer；
- 不得刷新 Core timeout；
- 不得修改 `step_index`；
- 不得发送 RESPONSE。

### FR-032：Active Peer 不可被抢占

当前 Session 未结束时，其他 source 发出的新 `SIM_START` 不得抢占当前 Session。

新 peer 只有在旧 Session 正常 `SIM_STOP`、timeout 或 error 结束并完成 close/reopen 后才可建立新的 candidate/session。

### FR-033：DSP RX 不增加完整 Frame 软件缓冲

DSP UDP 接收不增加第二个完整 ~1.5KB 软件 frame buffer。

应直接利用 W5300 RX FIFO 作为 Datagram staging storage。

### FR-034：Header/Payload 继续适配现有 Core receive API

Core 现有：

```text
receive(..., 4)
→ validate Header
→ receive(..., payload)
```

语义保持。

UDP Channel 必须从同一个 UDP Datagram 中：

1. 先向 Core 提供 4-octet V1 Header；
2. 再提供 Header 声明的 Payload；
3. 不得跨 Datagram 拼接。

### FR-035：UDP Physical Length 必须与 V1 Frame Length 完全一致

W5300 PACKET-INFO 中的 UDP DATA size 记为 `M`，V1 Header payload length 记为 `N`。

合法条件：

```text
M == 4 + N
```

以下情况必须拒绝当前 Session：

```text
M < 4
M > 1472
M != 4 + N
```

为保持现有 Core/Ops API 不变，DSP UDP transport 允许读取其刚刚交付给 Core 的 4-octet V1 Header 中的 `payload_length`，但仅用于验证 UDP Datagram 的 physical boundary。UDP transport 不得因此下沉 Message Type、Protocol Version、Interface Hash、`step_index`、RESPONSE code 等其他 V1 protocol semantic validation；这些语义仍由现有 Core/Protocol 层负责。

无需扩充 Wire V1 error code，可作为 transport/IoDevice framing failure。

### FR-036：Sn_CR_RECV 只在 Datagram 完整消费后提交

读取 PACKET-INFO 后不得立即执行 `RECV`。

只有当前 Datagram 的全部 V1 DATA 已被 Core 消费或被 transport 明确丢弃后，才执行：

```text
Sn_CR_RECV
```

零 Payload 的 4-octet V1 Frame 可在 Header 消费完成后立即提交 `RECV`。

### FR-037：UDP TX 必须原子提交完整 Datagram

UDP send 不得复用 TCP partial `socket_send()` 行为。

只有当 W5300 TX free space 能容纳完整 V1 Frame 时才允许：

1. 写 `Sn_DIPR`；
2. 写 `Sn_DPORTR`；
3. 一次写完整 V1 Frame 到 TX FIFO；
4. 设置完整 `Sn_TX_WRSR`；
5. issue exactly one `SEND`。

若 TX free space 不足完整 Frame：

```text
send() → 0
```

且不得写入任何 partial Datagram。

### FR-038：UDP IoDevice send 不允许 partial positive progress

对 `w5300_udp`：

```text
send() == 0
```

表示 pending / no completed send progress；

```text
send() == count_octets
```

表示完整 Datagram 已由 W5300 SEND operation 完成；

```text
send() < 0
```

表示失败。

不得返回：

```text
0 < send() < count_octets
```

### FR-039：Pending SEND 不得重复提交

UDP Frame 已写入 W5300 并 issue SEND 后，在后续 `Run()` 中：

- 不得再次复制 Frame；
- 不得再次 issue SEND；
- 只推进 command / poll `SENDOK` / `TIMEOUT`。

`SENDOK` 后才向 Core 返回完整 `count_octets`。

### FR-040：SENDOK 不代表 Peer Delivery

W5300 `SENDOK` 只表示本地 UDP transmit operation 完成，不表示 PC 已收到 Datagram。

DSP 不等待 ACK，不缓存 Frame 做重传。

### FR-041：UDP TX Destination

正常 Session 的所有 RESPONSE / OUTPUT_DATA 均发送到当前 Session Peer。

若初始 candidate Datagram 的 `SIM_START` 非法，但 Core 需要发送 error RESPONSE，可使用 candidate peer 作为临时 destination。

### FR-042：UDP Session Close

Session 结束后，UDP Channel 必须沿用现有 Core：

```text
terminate
→ close
→ reopen/listen
```

生命周期。

UDP `close()` 必须继续符合现有 IoDevice close contract：

```text
> 0  = close complete
  0  = busy / still progressing
< 0  = close error
```

关闭过程必须跨多次 `Run()` 有界推进，不得在单次调用中 busy-wait `Sn_CR`、`SENDOK/TIMEOUT` 或 `SOCK_CLOSED`。如果开始 close 时存在尚未完成的 W5300 command，允许先按现有 bounded command lifecycle 有界推进/接管，再 issue `Sn_CR_CLOSE`。

UDP close 继续复用现有 W5300 close timeout / `close_timeout_us` 语义，不增加 UDP-specific close timeout。

Native UDP `close()` 只执行简单 W5300 Socket CLOSE，不执行 TCP close erratum 的 dummy UDP send workaround。

### FR-043：Close 清除 Session 私有状态

UDP close 完成时必须清除：

- candidate peer；
- session peer；
- RX Datagram state；
- pending SEND state；
- close/session 私有状态。

关闭并重新打开 W5300 UDP Socket 同时作为清除未完整消费非法 Datagram 的机制，避免增加复杂 RX drain 状态机。

### FR-044：PC 异常退出依靠现有 Core timeout 回收

UDP 不增加 heartbeat / lease timeout。

PC 崩溃、被强制停止或 `SIM_STOP` 丢失时，DSP 通过现有 Core interaction timeout 终止 Session、close UDP socket，并恢复 LISTENING。

---

# 4. PC / MATLAB UDP Transport

### FR-045：PC UDP 使用 SOCK_DGRAM

PC 端新增独立 UDP transport，例如：

```text
pc_udp.c
pc_udp.h
```

使用：

```text
socket(AF_INET, SOCK_DGRAM, ...)
connect(DSP_IP, DSP_UDP_PORT)
```

UDP `connect()` 只固定 remote endpoint，不代表 TCP-style handshake。

`w5300_udp` generated S-Function 与现有 `w5300_tcp` 一样保持 0 个 transport runtime parameter；DSP IP 与 UDP Port 来自 generated project/config，不增加 COM/remote-port 等运行时 Block 参数。

`w5300_udp` 的 PC host / Simulink execution-mode 支持范围继承当前 `w5300_tcp` 基线；本增量既不扩大也不缩减既有支持范围。

### FR-046：PC local UDP port 由 OS 分配

PC 不在 Project 中保存 local UDP port。

默认由 OS 分配 ephemeral local port。

DSP 从 `SIM_START` Datagram 的 PACKET-INFO 自动学习 PC Source Port。

### FR-047：UDP peer 可达性由 SIM_START/RESPONSE 判断

PC UDP `connect()` 不负责确认 DSP 是否在线。

真正的启动成功条件继续是：

```text
send SIM_START
→ receive RESPONSE
```

未收到合法 RESPONSE 时由现有 timeout/error contract 结束启动。

### FR-048：PC 使用完整 Datagram staging buffer

PC 端允许私有完整 UDP Datagram staging buffer。

合法最大 Datagram 为：

```text
1472 octets
```

PC UDP transport 必须能够区分合法 `<=1472` octets 的 Datagram 与 oversize Datagram。允许通过 1473-octet guard buffer、OS 提供的 truncation indication 或其他等价方式实现；任何实现均不得把协议合法上限扩大到 1472 octets 以上。

### FR-049：第一次 recv Header 时一次接收完整 Datagram

当 protocol 调用：

```text
recv_exact(..., 4)
```

且当前无 staged Datagram 时，PC UDP transport 必须一次从 OS socket 接收完整 UDP Datagram 到私有 staging buffer，然后只把前 4 octets 提供给 protocol。

### FR-050：第二次 recv Payload 必须来自同一 staged Datagram

Protocol 解析 Header 后请求 Payload 时，UDP transport 必须从同一个 staging buffer 返回剩余 Payload。

不得从下一个 UDP Datagram 补足当前 Frame。

### FR-051：PC Datagram framing 检查

PC UDP transport 仅允许解析 V1 Header 中的 Payload Length 用于 Datagram boundary 验证。

必须验证：

```text
datagram_length == 4 + header.payload_length
```

Transport 不负责解析：

- Message Type 合法性；
- Protocol Version；
- Interface Hash；
- step_index；
- RESPONSE code。

这些继续由现有 protocol layer 处理。

### FR-052：PC UDP send 必须一次发送完整 Frame

Protocol 已构造完整 V1 Frame 后，UDP transport 必须执行一次完整 Datagram send。

不得使用 TCP 式 partial-send loop。

若 UDP `send()` 未按 Datagram 合同完成完整 Frame，则当前 Session 失败，不继续补发剩余部分。

### FR-053：Absolute deadline 继续保持

一次 V1 Frame receive 的 Header 与 Payload 继续共享一个 absolute operation deadline。

不得因 UDP staging 而对 Header / Payload 分别重新开始完整 timeout。

### FR-054：单一 V1 Protocol Template

TCP、UDP、SCI 继续共享同一个 V1 protocol implementation/template。

不得新增：

```text
protocol_udp.c.in
udp_protocol.c
```

应通过 transport binding 将同一 protocol 分别绑定到：

```text
TCP → pc_socket
UDP → pc_udp
SCI → pc_serial
```

---

# 5. Generated Closure 与 Mixed IoDevice

### FR-055：DSP 输出必须显式区分四类使用标志

生成阶段应具备等价于：

```text
useW5300
useTcp
useUdp
useSci
```

的显式 transport closure 语义。

其中：

```text
useW5300 = useTcp || useUdp
```

### FR-056：W5300 common source 只在需要时生成

存在任意 TCP/UDP W5300 Instance 时，DSP 输出包含：

```text
c2837x_w5300_regs.*
c2837x_w5300_hal.*
c2837x_w5300_socket.*
```

纯 SCI 项目不得无条件带入 W5300 代码。

### FR-057：TCP Channel 条件生成

只有存在 `w5300_tcp` Instance 时才输出 TCP channel source/header。

UDP-only 项目不得无理由带入 TCP channel 和 TCP close erratum 状态机。

### FR-058：UDP Channel 条件生成

只有存在 `w5300_udp` Instance 时才输出 UDP channel source/header。

### FR-059：W5300 Project-level Config 只能生成一次

Mixed TCP+UDP 项目中，共享：

```text
c2837x_w5300_project_config
```

及等价 W5300 project-level support 必须只生成一份。

TCP provider 与 UDP provider 不得各自生成重复同名全局符号。

### FR-060：Instance Channel 保持私有绑定

Project-level W5300 platform/config 共享，但每个 Instance 必须静态绑定自己的 transport channel 与 IoDevice Ops：

```text
TCP instance → TCP channel / TCP IoDevice Ops
UDP instance → UDP channel / UDP IoDevice Ops
SCI instance → SCI channel / SCI IoDevice Ops
```

### FR-061：每个 S-Function Instance 只带一个 PC Transport

每个生成的 Instance MEX 闭包只能包含当前 IoDevice 对应的一个 transport：

```text
w5300_tcp → pc_socket
w5300_udp → pc_udp
sci       → pc_serial
```

不得为了 mixed DSP project 让单个 Instance MEX 同时编译三种 transport。

### FR-062：Transport source selection 必须显式三路分支

S-Function output model、PC renderer 和 build script source selection 必须对：

```text
w5300_tcp
w5300_udp
sci
```

显式分支。

未知 IoDevice 必须明确报错，不得 fallback 到 TCP。

### FR-063：Interface Hash 不包含 Transport-specific 配置

IoDevice 类型、TCP/UDP/SCI transport selection、Socket/Port 等 transport-specific 配置本身不得进入 Interface Hash。

现有 Interface Hash 字段集合保持不变，包括既有 `max_payload_size_bytes / max_payload_octets`。因此 TCP↔UDP 切换只有在所有既有 Hash 输入均未改变时才保持相同 Interface Hash；若为满足 UDP 上限而修改 `max_payload_size_bytes`，Interface Hash 必须继续按现有规则重新计算。

### FR-064：Dependency / Fingerprint 只记录真实闭包

生成依赖和 fingerprint 必须按实际 transport closure 记录。

UDP-only 不得无理由依赖 TCP channel source；TCP+UDP mixed 则同时记录两种 transport definition/channel。

---

# 6. Error / Timeout / Session Lifecycle

### FR-065：不新增 UDP-specific public error category

优先复用现有 PC error contract：

- `TIMEOUT`；
- `SOCKET`；
- `TRUNCATED`；
- `PAYLOAD_LENGTH`；
- `DSP_RESPONSE`；
- `STEP_INDEX`；
- 其他已有 transport-neutral categories。

不得仅因为 transport 是 UDP 就增加通用 `UDP_ERROR`。

### FR-066：Packet Loss 不建立专用错误

UDP packet loss 不进行显式检测或重传。

例如：

- SIM_START 丢失；
- RESPONSE 丢失；
- INPUT_DATA 丢失；
- OUTPUT_DATA 丢失。

对于未收到预期 Datagram、且 OS 未显式报告 socket failure 的情况，最终由现有等待逻辑表现为 `TIMEOUT`。如果 OS 明确报告 socket error，则按 FR-067 保留真实 `SOCKET` 错误。

### FR-067：保留真实 OS Socket Error

若 OS 明确返回 socket error（例如本地 socket failure 或某些 ICMP-derived error），允许直接报告现有 `SOCKET`。

不得为了统一表现而强制吞掉真实 OS error 并全部转换成 timeout。

### FR-068：CONNECT_TIMEOUT_MS 保留统一配置合同

每个 S-Function user config 继续保留：

```text
CONNECT_TIMEOUT_MS
STEP_TIMEOUT_MS
TERMINATE_TIMEOUT_MS
```

UDP 不需要新增 UDP-specific timeout macros。

UDP 下 `CONNECT_TIMEOUT_MS` 不表示远端握手成功；实际 peer-response timeout 由 `SIM_START → RESPONSE` 使用的现有 step timeout 判断。

### FR-069：Datagram Header 不完整

UDP Datagram 总长度小于 4 octets 时，PC 端应报告现有：

```text
TRUNCATED
stage = recv_header
```

并提供合理的 expected/actual length diagnostics。

### FR-070：Datagram 比 Header 声明短

若：

```text
physical payload < header.payload_length
```

PC 端应报告：

```text
TRUNCATED
stage = recv_payload
```

不得继续读取下一 Datagram 补足。

### FR-071：Datagram 比 Header 声明长

若：

```text
physical payload > header.payload_length
```

PC 端应报告：

```text
PAYLOAD_LENGTH
stage = recv_payload
```

### FR-072：Oversize / Odd Length

超过合法 UDP Datagram 上限或违反现有偶数字节约束的 Datagram/Frame，继续归入现有 Payload Length / framing failure 语义，不新增新的 public error kind。

### FR-073：DSP UDP Transport Failure

W5300 UDP adapter/hardware failure继续映射为现有 DSP IoDevice error。

等待下一合法交互超时继续使用现有 Core timeout error。

### FR-074：Alien Peer Datagram 不算错误

Active Session 期间来自其他 IP+Port 的 Datagram 属于正常过滤行为：

- 静默丢弃；
- 不刷新 timeout；
- 不报 DSP error；
- 不发送 error response。

### FR-075：SIM_STOP 保持 Best-effort

PC `mdlTerminate()` 继续 best-effort 发送一次 `SIM_STOP`，不等待 UDP ACK、不重试、不新增 STOP RESPONSE handshake。

若 SIM_STOP 丢失，DSP 最终由现有 interaction timeout 回收 Session。

---

# 7. 开发验证与非目标

### FR-076：Project / App 自动验证

开发侧自动测试至少覆盖：

- `w5300_udp` create / switch / save / load；
- Project Format 仍为 V4；
- UDP canonical defaults；
- Socket 0～7；
- UDP Port 1～65535；
- TCP/UDP shared Socket duplicate；
- TCP port duplicate；
- UDP port duplicate；
- TCP Port 与 UDP Port 同号允许；
- any-W5300 network activation；
- any-W5300 platform resource reservation；
- UDP `max_payload_size_bytes <= 1468`；
- Copy UDP；
- transport switch canonical settings；
- UDP transport summary。

### FR-077：DSP Host / Mock UDP 验证

开发侧 Host/Mock 测试至少验证：

- UDP OPEN → `SOCK_UDP`；
- PACKET-INFO；
- candidate/session peer；
- alien peer drop；
- Header/Payload 同 Datagram receive；
- exact physical length；
- delayed `RECV` commit；
- atomic full-Datagram TX；
- TX free 不足时零 partial write；
- SEND pending 不重复提交；
- SENDOK 返回完整 positive progress；
- simple UDP CLOSE；
- close 清 peer/RX/TX state；
- UDP close 不进入 TCP erratum dummy-send path。

同时运行与修改点相关的现有 TCP regression。

### FR-078：PC localhost UDP 验证

PC 端必须使用真实 OS localhost UDP socket，并直接 exercise production-derived/generated `pc_udp` transport。测试 peer 可以是最小专用 harness，不要求实现完整 DSP simulator。

最小交互必须覆盖：

```text
SIM_START
RESPONSE
INPUT_DATA
OUTPUT_DATA
SIM_STOP
```

并覆盖：

- whole-Datagram send；
- staged Header/Payload receive；
- no cross-Datagram concatenation；
- timeout；
- short Datagram；
- declared-length mismatch。

### FR-079：Generated Closure 验证

开发侧 deterministic generation 至少覆盖代表性组合：

```text
UDP only
TCP + UDP
UDP + SCI
TCP + UDP + SCI
```

确认：

- W5300 common source 只生成一次；
- transport channel 条件生成；
- mixed W5300 project config 不重复；
- 每个 MEX 只带对应 transport；
- unknown transport 不 fallback TCP。

### FR-080：编译结果必须真实

若执行环境存在可用 MEX compiler，应实际执行相关 UDP MEX build。

若没有：

```text
NOT_EXECUTED / CAPABILITY
```

若执行环境存在可用 TI C2000 compiler，应实际执行对应 DSP compile。

若没有，同样明确标记：

```text
NOT_EXECUTED / CAPABILITY
```

Host compile 不得冒充 TI DSP compile PASS。

### FR-081：用户实机验证

最终 W5300 UDP PIL 实机验证由用户执行。

建议最小验证：

1. UDP SIM_START 成功；
2. 连续执行若干 PIL step；
3. I/O 数据正确；
4. SIM_STOP；
5. 再次建立 Session；
6. 根据研发需要比较 TCP/UDP 实际 latency / PIL execution speed。

在用户未反馈前必须记录为：

```text
USER_VALIDATION_PENDING
```

不得由开发侧或 Codex 声称硬件 PASS。

### FR-082：第一版明确非目标

本版本不要求：

- random packet-loss matrix；
- packet reorder stress；
- duplicate packet stress；
- long-duration stability；
- 8 Socket 满载并发；
- all-port exhaustive testing；
- all-payload exhaustive testing；
- IP fragmentation；
- jumbo frame；
- broadcast；
- multicast；
- automatic peer/session reconnect/resume protocol；
- heartbeat；
- peer takeover；
- ACK/retry/retransmit；
- throughput benchmark gate；
- TCP→UDP performance improvement percentage gate。

---

# 8. 冻结声明与规范治理

本文件于 2026-09-06 冻结为：

```text
requirements_w5300_udp_iodevice_v1.0_frozen.md
```

冻结结论：

```text
Status                  = Frozen V1.0
FR count                = 82
FR range                = FR-001 ... FR-082
Project Format Version  = 4
Wire Protocol Version   = 1
Core API Version        = 2
```

冻结后的规范治理规则：

1. 本文件是 W5300 UDP IoDevice 增量周期的冻结需求 authority；
2. 本文件未明确修改的既有 W5300 TCP、SCI、Project V4、多实例 Core、App、生成、PC/S-Function 与 Wire Protocol V1 行为继续继承直接前置冻结规范；
3. 正式批准的 UDP 实施计划在生成后与本文件共同构成本 UDP 增量周期的当前 implementation authority；
4. 当 UDP Frozen requirements 与 UDP approved plan 正式切换为仓库当前规范入口后，上一 SCI 周期需求与计划转为直接前置历史规范，不得继续与 UDP Frozen 版并列为 current implementation authority；
5. 历史多实例需求仅作为历史追溯材料，不恢复为 current authority；
6. Frozen 后 FR 编号保持稳定。若后续确需新增需求，只能从现有编号末尾追加；不得复用、重排或改变既有 FR 编号含义；
7. 对 Frozen 需求的任何语义修订必须通过明确的 Erratum / revision 机制记录，不得静默改写；
8. 实施阶段不得恢复本文件明确排除的 ACK/retry/retransmit、heartbeat、peer/session resume、IP fragmentation、产品级网络可靠性矩阵或其他非目标；
9. 实施开始前必须重新核对 Repository、Branch、Local HEAD、Remote HEAD、`git status`、冻结需求提交、批准计划提交及前置任务提交；
10. 未实际执行的测试、编译、硬件验证和 Gate 不得记录为 PASS。

本文件只冻结需求，不提前定义 Stage、Gate 或 Codex 小任务。正式实施计划必须基于本 Frozen V1.0 单独制定并审核批准。
