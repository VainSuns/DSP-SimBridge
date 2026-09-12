# Simulink / MEX 使用指南

本文说明 Project V4 生成的 Simulink S-Function 输出、MEX 构建、块参数、
SCI 串口生命周期、W5300/TCP 生命周期和 W5300/UDP 生命周期。传输类型由
每个实例的 IoDevice 决定；同一个 Project 可以包含不同类型的实例。

相关文档：

- [App 项目与迁移指南](app_project_and_migration_guide.md)
- [CCS 集成与双实例 main](ccs_integration_and_dual_instance_main.md)
- [Current UDP requirements traceability](requirements_traceability.md)

## 1. 使用边界

App Generate 只生成 DSP/S-Function 文件和构建脚本，不自动运行 MEX 构建、
修改 MATLAB path 或更新 Simulink 模型。用户应在生成完成后，把输出目录
用于自己的模型和构建流程。

SCI PC 侧使用 Windows 串口 API，当前只支持 Windows MEX 和 Simulink
Normal mode。W5300 的构建脚本支持 Windows 和 POSIX 主机；生成的桌面
S-Function 仍按 Normal mode MEX 路径使用。

SCI、W5300/TCP 与 W5300/UDP 都不承诺 Accelerator、Rapid Accelerator、模型代码生成或
并行 MEX 路径。生成的 S-Function 源文件会在非 Normal mode 或非 MATLAB
MEX 环境下拒绝不适用的调用。

## 2. 每个实例的 S-Function 输出

每个实例生成严格 11 个文件。不要用目录通配替换下面的显式文件清单：

~~~text
<internal_name>_sfun.c
<internal_name>_sfun.h
<internal_name>_sfun_io.c
<internal_name>_sfun_config.h
<internal_name>_sfun_user_config.h
<internal_name>_pc_error.h
<internal_name>_<pc_socket|pc_udp|pc_serial>.c
<internal_name>_<pc_socket|pc_udp|pc_serial>.h
<internal_name>_protocol.c
<internal_name>_protocol.h
build_<internal_name>_sfun.m
~~~

传输文件的选择如下：

| IoDevice | C/头文件对 |
| --- | --- |
| w5300_tcp | internal_name_pc_socket.c/.h |
| w5300_udp | internal_name_pc_udp.c/.h |
| sci | internal_name_pc_serial.c/.h |

W5300/TCP 实例使用 pc_socket，W5300/UDP 实例使用 pc_udp，SCI 实例使用
pc_serial。每个实例有自己的
sfun、配置、协议和 PcError 文件；公共 DSP/PC 代码不会通过运行时共享一
个未声明的 transport context。

## 3. MEX 构建

打开 MATLAB 后，在相应 S-Function 输出目录执行对应的
build_internal_name_sfun.m，或在自己的脚本中调用该构建脚本。生成脚本
使用显式源文件和头文件。

W5300/TCP 实例的源文件为：

~~~text
<internal_name>_sfun.c
<internal_name>_sfun_io.c
<internal_name>_pc_socket.c
<internal_name>_protocol.c
~~~

SCI 实例的源文件为：

~~~text
<internal_name>_sfun.c
<internal_name>_sfun_io.c
<internal_name>_pc_serial.c
<internal_name>_protocol.c
~~~

W5300/UDP 实例的源文件为：

~~~text
<internal_name>_sfun.c
<internal_name>_sfun_io.c
<internal_name>_pc_udp.c
<internal_name>_protocol.c
~~~

三种构建的对应头文件为：

~~~text
<internal_name>_sfun.h
<internal_name>_sfun_config.h
<internal_name>_sfun_user_config.h
<internal_name>_pc_error.h
<internal_name>_<pc_socket|pc_udp|pc_serial>.h
<internal_name>_protocol.h
~~~

一次构建只使用同一次 Generate 的文件。改动 user config 中的超时宏后，
必须重新构建 MEX；仅修改 SCI 块的 COM Port Number 不需要重新 Generate
或重新编译 MEX。

生成的 user config 默认值为：

~~~c
#define CONNECT_TIMEOUT_MS 5000u
#define STEP_TIMEOUT_MS 1000u
#define TERMINATE_TIMEOUT_MS 200u
~~~

CONNECT_TIMEOUT_MS 用于 W5300/TCP 的连接流程。SCI 串口打开和配置不是 TCP
connect；W5300/UDP 的 socket connect 也不是远端握手，不应把该宏描述为 UDP
reachability handshake。UDP 的远端启动确认由 `SIM_START -> RESPONSE` 使用
现有 `STEP_TIMEOUT_MS` 完成。三个宏都继续保留在每个生成的 user config 中，
并由对应传输的协议生命周期使用；它们是固定毫秒值，不会根据 Baud 或 payload
大小自动适配。

## 4. S-Function 参数和块配置

### W5300/TCP

W5300 S-Function 使用零个参数：

~~~text
ssSetNumSFcnParams(S, 0)
~~~

网络地址、TCP port 和 socket 来自生成的实例配置，不在块参数对话框中动态
输入。更改这些配置后，应回到 App Preview/Generate，再重新构建对应 MEX。

### W5300/UDP

W5300/UDP S-Function 同样使用零个参数：

~~~text
ssSetNumSFcnParams(S, 0)
~~~

DSP IP、UDP port 和 socket 来自生成的 Project/instance config，不在块参数
对话框中输入。PC local UDP port 不属于 Project，也不作为运行时参数保存。
更改 UDP 网络或 instance 设置后，应回到 App Preview/Generate，再重新构建
对应 MEX。

### SCI/串口

SCI S-Function 使用一个参数：

~~~text
COM Port Number
ssSetNumSFcnParams(S, 1)
ssSetSFcnParamTunable(S, 0, 0)
~~~

该参数必须是正整数、有限、非复数、标量，并且可表示为 uint32。参数值
只表示 Windows 主机上的 COM 号，例如 COM3 使用数值 3；不要填写字符串
COM3，也不要填写 DSP 端的 SCI 模块名。

COM Port Number 是 S-Function 运行时参数，不属于 Project V4 的 iodevice
字段，不写入 DSP descriptor、generated config 或 Interface Hash。修改 COM
号不会改变生成文件、接口 hash 或 DSP 代码，也不要求重新构建同一个 MEX；
它只影响本次 MEX 会话打开的 PC 串口。

SCI 的 module、Requested/Nominal Baud、RX/TX GPIO、pin type、qualification
和可选 CTRL GPIO 在 App 中配置，并在生成的 SCI descriptor 中传给 DSP。
COM 号则由 Simulink 块参数提供，两者职责不能互换。

## 5. Simulink 端口与采样时间

输入、输出端口的数量、顺序、名称、类型和维度来自当前实例 I/O 配置。
Simulink 模型的端口必须与本次 Generate 的 Interface Hash 对应；改变
端口或最大 payload 后，应重新 Preview、Generate 和 MEX build。

sample_time_sec 属于实例运行配置，不参与 Interface Hash。改变采样时间
仍应重新 Generate 并更新模型配置，确保模型调度与 DSP/PC 会话预期一致。

## 6. SCI 串口生命周期

### mdlStart

SCI S-Function 的启动顺序为：

1. 校验并解析 COM Port Number；
2. 创建串口/协议上下文；
3. 以 Windows 独占方式打开 COM 设备；
4. 配置 8N1、无流控和生成的 Requested Baud；
5. 显式清空 RX/TX 队列；
6. 设置 PcError 上下文；
7. 发送 SIM_START，等待 RESPONSE，并确认 Interface Hash/协议版本；
8. 将 step 初始化为 0，标记会话已启动。

PC 串口地址使用 Windows 的设备形式 \\\\.\\COM<number>。串口打开失败、
配置失败、清队列失败或 SIM_START 超时都会使启动失败，不会自动切换到
另一个 COM 号。

### mdlOutputs

每个 step 会：

1. 按当前输入端口打包 payload；
2. 发送 INPUT_DATA；
3. 在单一绝对截止时间内等待 DSP 的 OUTPUT_DATA/RESPONSE；
4. 验证长度和协议状态；
5. 先解码到临时输出，再一次性提交 Simulink 输出；
6. 成功后递增 step。

传输中断、协议错误、长度错误或 timeout 会关闭当前会话并记录错误。不会
用重试、重发或 serial recovery loop 掩盖 step 序列错误。

### mdlTerminate

若会话仍有效，SCI S-Function 会在 TERMINATE_TIMEOUT_MS 内尽力发送
SIM_STOP，不等待响应；随后销毁上下文、关闭串口并清理资源。Terminate
路径不建立新的连接，也不执行重连。

## 7. W5300/UDP 生命周期与 wire 合同

### mdlStart

W5300/UDP 的启动顺序为：

1. 创建 UDP socket（`SOCK_DGRAM`）；
2. 不绑定固定 PC local port，由 OS 分配 ephemeral local port；
3. `connect()` 只固定生成配置中的 DSP IP/UDP port，不证明 DSP 可达；
4. 发送一次 `SIM_START`，等待合法 `RESPONSE`；
5. 确认 Interface Hash/协议版本，将 step 初始化为 0。

DSP 从 W5300 UDP PACKET-INFO 学习 SIM_START 的 source IP 和 source port。
合法 SIM_START 被 Core 接受后，该 endpoint 成为 session peer；active session
只接受相同 IP+port 的 Datagram。其他 sender 的 Datagram 会被完整消费并静默
丢弃，不抢占 peer、不刷新 Core timeout，也不发送 RESPONSE。旧 session 结束
并完成 close/reopen 后，才允许新的 candidate 建立新 session。

### wire / step / terminate

UDP 的物理 framing 固定为：

~~~text
1 complete V1 frame = 1 UDP datagram
UDP physical datagram max = 1472 octets
V1 header = 4 octets
UDP max payload = 1468 octets
~~~

`mdlOutputs` 每个 step 发送一个完整 `INPUT_DATA` Datagram，再接收一个完整
`OUTPUT_DATA` 或 `RESPONSE` Datagram。PC transport 在第一次读取 Header 时
一次接收并暂存完整 Datagram，读取 Payload 时只能从同一 Datagram 提供数据；
Header 与 Payload 共用同一个 absolute deadline，不能跨 Datagram 拼接。

V1 UDP 生命周期为：

~~~text
SIM_START -> RESPONSE -> INPUT_DATA -> OUTPUT_DATA -> SIM_STOP
~~~

`mdlTerminate` 只 best-effort 发送一次 `SIM_STOP`，不等待 UDP ACK、不 retry、
不 retransmit。SIM_STOP 丢失时，DSP 依靠现有 interaction timeout 清理 session；
UDP 不新增 ACK/NAK、retry、retransmission、reorder buffer、duplicate suppression、
heartbeat、keepalive、automatic reconnect/resume、peer takeover 或 IP
fragmentation based larger-frame support。

### UDP timeout 与失败边界

`CONNECT_TIMEOUT_MS`、`STEP_TIMEOUT_MS` 和 `TERMINATE_TIMEOUT_MS` 仍存在，
但 `CONNECT_TIMEOUT_MS` 不表示 UDP remote handshake；UDP 的 reachability 由
`SIM_START -> RESPONSE` 的现有协议等待和 `STEP_TIMEOUT_MS` 判断。UDP socket
error、short/oversize Datagram 和 declared-length mismatch 使用现有 PC error
categories/framing stages；不会因为使用 UDP 而引入可靠传输语义。

## 8. W5300/TCP 生命周期

W5300/TCP S-Function 的块参数为零。mdlStart 建立 TCP 连接，完成
SIM_START/RESPONSE 后从 step 0 开始；mdlOutputs 交换 INPUT_DATA 和
OUTPUT_DATA；mdlTerminate 在终止截止时间内尽力发送 SIM_STOP，然后关闭
连接和清理上下文。

W5300/TCP、W5300/UDP 与 SCI 共用协议版本、Interface Hash、payload 检查和
step 序列语义，但使用不同的 PC transport 文件和连接初始化流程。

## 9. 波特率、LSPCLK 和错误诊断

当前 SCI DSP 时钟为：

~~~text
SYSCLK          = 200 MHz
LSPCLK divisor  = 4
LSPCLK          = 50 MHz
~~~

baud 使用生成的 BRR 和：

~~~text
actual_baud = 50,000,000 / (8 * (BRR + 1))
~~~

PC generated config/diagnostics 包含 Requested/Nominal Baud 和 Actual Baud
diagnostic information。PC serial configure 使用生成的 Requested/Nominal
Baud；Actual Baud 是 DSP BRR 量化后的诊断信息，不是要求 Windows serial
port 使用的另一个 baud。Baud Error (Actual - Requested) 是
App/calculator 的派生诊断，不是所有 generated config 的 runtime field。
DSP SCI descriptor 只包含 SCI module enum、BRR、RX/TX GPIO 及 mux、pin type、
RX qualification 和可选 CTRL 配置；不包含 Actual Baud、Baud Error 或 COM。
LSPCLK 是项目级 Platform configuration。当前支持 9600、19200、38400、
57600、115200；当前验证没有额外的 baud 误差阈值拒绝规则。

每个实例有独立的 PcError 头文件。诊断文本可包含 instance、COM、requested
或 actual baud、stage 和 category；串口异常通常属于 serial，期限异常
属于 timeout。调试时应保留原始错误文本和阶段信息。

PC 串口使用 8N1、无流控、独占打开、单一绝对 deadline 和部分传输继续使用
同一 deadline。打开/配置流程不插入固定 sleep；DSP 侧关闭 autobaud，不使用
bootloader "A" 握手。

## 10. Interface Hash 与传输设置

Interface Hash 描述协议接口，包含 protocol version、wire byte order、
有序 I/O 的数量/名称/类型/维度、payload 编码和最大 payload。

它不包含 COM 号、SCI module、baud、BRR、RX/TX/CTRL GPIO、pin type、网络
地址、package 或 sample time。因此：

- 只改 COM Port Number 不需要重新 Generate；
- 改 SCI module、baud、GPIO 或 W5300 网络设置需要重新 Generate，但不改变
  接口 hash；
- 改 I/O 顺序、名称、类型、维度或最大 payload 会改变接口 hash；
- 任何生成候选变更都应使用同一批次的 S-Function 文件重新构建 MEX。

## 11. MEX 构建错误和恢复边界

构建脚本会检查常见环境和文件问题，包括：

~~~text
C2837xBlock:MexBuild:ForeignMexLoaded
C2837xBlock:MexBuild:MexStillLoaded
C2837xBlock:MexBuild:CompilerUnavailable
C2837xBlock:MexBuild:SimulinkUnavailable
C2837xBlock:MexBuild:MissingFile
C2837xBlock:MexBuild:DirectoryNotWritable
C2837xBlock:MexBuild:UnsupportedPlatform
~~~

SCI 在非 Windows 主机上会报告 UnsupportedPlatform。运行时失败不会触发
自动重连、重试、重发或固定等待；应停止仿真、检查 COM 独占占用/目标板
状态/物理连接和生成配置，然后重新启动会话。

## 12. Update Diagram 的边界

Update Diagram 只做静态的 block parameter、port、sample-time 等配置检查。
它不会 open COM、purge 串口、发送 SIM_START、探测 DSP 或枚举 COM 设备。
真实串口打开和会话启动只发生在 Normal-mode MEX 的 mdlStart。

## 13. 双实例和模型更新

同一个 Simulink 模型可以放置多个实例块。每个实例使用自己的 MEX 文件和
实例配置；SCI 块各自提供自己的 COM Port Number。多个 SCI 块不能通过
填写同一个 COM 号来实现资源共享。

当更新 App 项目、I/O、算法、SCI 设置或 W5300 设置时：

1. 在 App 中 Preview 并解决验证错误；
2. Generate 新的 DSP/S-Function 输出；
3. 按实例重新构建受影响的 MEX；
4. 确认模型端口与 Interface Hash 一致；
5. 在 Normal mode 下重新运行。

## 14. 当前验证状态

| 项目 | 状态 |
| --- | --- |
| 文件数量、pc_serial/pc_socket/pc_udp 条件清单 | 已按当前生成器核对 |
| W5300/UDP startup/step/terminate 与 peer boundary | 已按当前实现核对 |
| UDP one-frame-one-datagram、1472/1468 framing | 已按当前实现核对 |
| SCI COM 参数校验和 Normal mode 边界 | 已按当前实现核对 |
| SCI mdlStart/mdlOutputs/mdlTerminate 流程 | 已按当前实现核对 |
| LSPCLK、baud、BRR 和 Interface Hash 说明 | 已按当前实现核对 |
| DSP/CCS target build | NOT_EXECUTED |
| SCI-S5-03/R1 MEX/MATLAB product tests | NOT_EXECUTED / NOT_REQUIRED |
| Representative SCI MEX from SCI-S5-02 (MinGW64 8.1.0) | REUSED PASS |
| Focused MATLAB/software tests from SCI-S5-02 / earlier closed stages | REUSED EVIDENCE |
| UDP-S6-01 software/build evidence | 297 passed / 0 failed / 3 incomplete |
| Representative generated UDP MEX (`axis_udp_sfun.mexw64`) | PASS |
| Representative generated TI UDP DSP sources | 11/11 compile-only PASS |
| Real COM hardware | NOT_EXECUTED |
| Real Simulink communication | NOT_EXECUTED |
| SCI hardware | USER_VALIDATION_PENDING |
| W5300 UDP hardware PIL | USER_VALIDATION_PENDING |
| Half-duplex hardware | NOT_EXECUTED |
| Mixed W5300/SCI hardware | NOT_EXECUTED |
| Final LSPCLK hardware confirmation | USER_VALIDATION_PENDING |
| Simulink 最终模型运行 | 未执行 |
| 目标板 SCI/W5300 通信和双实例 | 未执行 |
| 用户最终模型验证 | 待用户验证 |
| UDP-S6-03 final FR audit | PASS；FR-001～FR-080 = PASS，FR-081 = USER_VALIDATION_PENDING，FR-082 = PASS |
| UDP-G6 | NOT_EVALUATED |
