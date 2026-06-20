# C2837xBlock — DSP 在环仿真通信模块 Spec V2.3

> 本文档基于 `spec_v2_2.md` 继续修订，重点补齐 C S-Function 的工程结构、生命周期、端口映射、socket 管理、编译方式、错误处理和验收测试。

## 0. 修订说明

### 0.1 本版主要修改

1. 将数据大小宏拆分为 `*_SIZE_BYTES` 与 `*_SIZE_WORDS`，避免 C2000 端 `sizeof()` 与 TCP 线上字节数混淆。
2. 明确协议帧 `length` 永远表示 **TCP 线上 8-bit 字节数**。
3. 删除“`uint8_t` 实际等同于 `uint16_t`”的表述，改为 DSP 端使用 `uint16_t word buffer` 表示 TCP 字节流。
4. 明确协议线上格式统一采用 little-endian，禁止直接发送结构体或整数对象。
5. 明确 `RESPONSE` 的语义：`SIM_START` 的成功/失败应答，以及任意协议错误应答。
6. 增加 `step_index`，便于定位仿真步错误。
7. 定义 `config_hash` 的 CRC32 参数和规范化字符串格式。
8. 明确 `double` 仅在 C2000 EABI 且 `sizeof(double) * CHAR_BIT == 64` 时支持。
9. 将 DSP 通信框架统一为非阻塞状态机，消除 `C2837xBlock_Run()` 非阻塞与阻塞监听的矛盾。
10. 说明 `OnStep()` 死循环无法由轮询超时检测，只能由 Simulink 端超时或 DSP watchdog 发现。
11. 修正 W5300 缓冲区描述：按总 128 KB socket buffer 进行分配，不再写 TX/RX 各 128 KB。
12. 明确 V2.3 暂不提供用户级 `fprintf`/`DEBUG_MSG`，仅保留内部错误日志缓存。
13. 增加数组序列化顺序、S-Function 显式离散采样时间、TCP `send_all()` 要求和异常测试项。
14. 补充 C S-Function 输入端口连续性、启动失败清理、单实例计数生命周期、PC 端 timeout 宏和 sample time 哈希规则。
15. 增加 W5300 字节序自检、Mock DSP 和协议测试向量验收。
16. 补充 `step_index` 单调检查和 uint32 回绕策略，支持长时间仿真。
17. 将 DSP 用户回调改为可返回状态，避免 `OnSimStart()` / `OnStep()` 失败时无法向 Simulink 报错。
18. 修正 DSP 配置示例中依赖结构体 `sizeof()` 和 union 访问 `double` 的隐患。

### 0.2 版本范围

本文档定义 V2.3 的目标实现范围：

- 支持单 DSP、单 TCP 连接、单 Simulink S-Function 模块。
- 支持标量和一维数组。
- S-Function 模块以显式固定离散采样时间运行，每个 sample hit 执行一次同步通信交互。
- 支持 `int16`、`uint16`、`int32`、`uint32`、`single`。
- `double` 为可选支持项，仅在 DSP 工程使用 EABI 且确认 64-bit double 时启用。
- 暂不支持多实例、多 Socket、用户级 printf 调试流、日志批量上传、连续状态和异步多速率触发。

### 0.3 版本号关系

为避免文档版本、协议版本和代码生成器版本混淆，本项目采用以下约定：

| 项目 | 当前值 | 说明 |
|------|--------|------|
| 文档版本 | Spec V2.3 | 本文档版本，仅表示需求和设计文档修订状态 |
| 协议版本 | `0x0001` | `SIM_START.protocol_version` 使用的线上协议版本 |
| 配置生成器版本 | `C2837X_BLOCK_GENERATOR_VERSION` | MATLAB App / 代码生成器版本，由 App 维护 |
| DSP SDK 版本 | `C2837X_BLOCK_SDK_VERSION` | 通信库实现版本，由 DSP SDK 维护 |

Spec V2.3 **不改变线上协议版本号**，协议版本仍为 `0x0001`。只有当帧格式、报文类型或字段语义发生不兼容变化时，才递增 `C2837X_BLOCK_PROTOCOL_VERSION`。

---

## 1. 问题

受到硬件条件的限制，DSP 的控制算法无法在所有运行工况下得到验证。需要一种在环仿真方案，在 Simulink 仿真环境中对运行在 DSP 上的实际控制算法进行验证。

---

## 2. 解决方案

构建 Simulink ↔ DSP 的双向 TCP/IP 通信链路：

1. **Simulink 端**：S-Function 模块读取仿真输入信号，通过 TCP/IP 将数据发送到 DSP；接收 DSP 处理后的结果，输出到 Simulink 仿真环境中。
2. **DSP 端**：以库的形式提供通信框架，接收输入数据、调用用户实现的控制算法、将结果返回 Simulink。
3. **配置工具**：MATLAB App 生成 Simulink 端和 DSP 端的配置文件，统一定义输入输出数据、网络参数和配置签名。

S-Function 仅负责数据转发，不涉及控制算法实现。控制算法完全在 DSP 端运行。

### 2.1 整体架构

```text
┌─────────────────────────────┐          TCP/IP           ┌─────────────────────────────┐
│         PC (Simulink)       │ ◄═══════════════════════► │         DSP (C2837x)        │
│                             │        (W5300)            │                             │
│  ┌──────────────┐           │                            │           ┌──────────────┐  │
│  │  S-Function  │ 输入数据 ─►│────── INPUT_DATA ────────►│──► 用户算法 ─►│ 返回结果     │  │
│  │  数据转发     │◄ 输出数据 │◄──── OUTPUT_DATA ────────│◄────────────│              │  │
│  └──────────────┘           │                            │           └──────────────┘  │
│         ▲                   │                            │                   ▲         │
│         │                   │                            │                   │         │
│  Simulink端配置文件          │                            │            DSP端配置文件      │
│  字节级序列化/网络参数        │                            │         word级序列化/网络参数  │
└─────────────────────────────┘                            └─────────────────────────────┘
```

### 2.2 开发路线

采用渐进式开发策略：

1. **阶段一：通信验证**  
   手动编写最简配置文件，使用 3 个 `int16` 输入和 1 个 `int16` 输出，加法运算，用 MATLAB S-Function 验证通信协议和数据传输正确性。

2. **阶段二：功能完善**  
   开发 MATLAB App 生成配置文件，支持用户自定义输入输出变量、类型、维度、网络参数和 `config_hash`。

3. **阶段三：性能优化**  
   将 MATLAB S-Function 转换为 C S-Function，复用 App 生成的 PC 端字段级序列化代码，提高通信性能和仿真稳定性。

---

## 3. 通信协议

### 3.1 协议概述

协议参考 PIL（Processor-in-the-Loop）通信方式进行简化。V2.3 删除独立 `ON_STEP` 报文，每个仿真步由一次 `INPUT_DATA` 驱动：DSP 收到输入后立即调用 `C2837xBlock_OnStep()`，然后返回 `OUTPUT_DATA`。

通信流程：

```text
Simulink 端                                    DSP 端
    │                                              │
    │  ──── SIM_START ──────────────────────────►  │  校验协议版本和配置签名
    │  ◄──── RESPONSE(error_code=0) ─────────────  │  初始化成功
    │                                              │
    │  ──── INPUT_DATA(step_index=N) ───────────►  │  解包输入
    │                                              │  调用 C2837xBlock_OnStep()
    │  ◄──── OUTPUT_DATA(step_index=N) ──────────  │  返回输出
    │                                              │
    │  ... 重复 INPUT_DATA → OUTPUT_DATA ...       │
    │                                              │
    │  ──── SIM_STOP ───────────────────────────►  │  调用 C2837xBlock_OnSimStop()
    │                                              │  关闭连接并回到 LISTEN
```

异常流程：

```text
Simulink 端                                    DSP 端
    │                                              │
    │  ──── 任意非法报文 ───────────────────────►  │  类型/长度/状态/配置检查失败
    │  ◄──── RESPONSE(error_code>0) ─────────────  │  返回错误码
    │                                              │  关闭连接或回到 LISTEN
```

### 3.2 字节序与线上表示

协议线上格式统一采用 **little-endian**：

- `uint16` / `int16`：低字节先传输，高字节后传输。
- `uint32` / `int32`：最低有效字节先传输，最高有效字节后传输。
- `single`：按 IEEE 754 32-bit 二进制表示进行 little-endian 编码。
- `double`：按 IEEE 754 64-bit 二进制表示进行 little-endian 编码，仅在目标 ABI 支持 64-bit double 时启用。

禁止直接将结构体、整数对象或浮点对象作为 TCP 字节流发送。PC 端和 DSP 端都必须通过 App 生成的 `write_xxx()` / `read_xxx()` 函数进行显式编码和解码。

### 3.3 C2000/C28x 平台寻址约束

C2000/C28x 平台的最小可寻址单位为 16 bit。为避免协议线上 8-bit 字节数与 DSP 内部寻址单位混淆，本文档使用以下术语：

| 名称 | 含义 |
|------|------|
| wire byte | TCP 线上 8-bit 字节，是协议 `length` 的单位 |
| DSP word | DSP 端 `uint16_t` 缓冲区中的一个元素，对应 16 bit |
| `*_SIZE_BYTES` | payload 在线上传输时的 8-bit 字节数 |
| `*_SIZE_WORDS` | DSP 端存储同一 payload 需要的 16-bit word 数 |

约束：

1. 协议帧中的 `length` 永远表示 **wire byte 数**。
2. DSP 端接收缓冲区使用 `uint16_t[]` 保存 payload。
3. 当前支持的数据类型大小均为 2、4 或 8 字节，因此 payload `length` 必须为偶数。
4. DSP 端 `word_count = length / 2`。
5. DSP 端不得依赖 `uint8_t` 作为协议缓冲区类型。

示例：

```text
3 × int16 输入：
- TCP 线上 payload length = 6 wire bytes
- DSP 端 payload buffer = 3 个 uint16_t word
```

### 3.4 支持的数据类型

| 类型 | 线上字节数 | DSP word 数 | 说明 |
|------|------------|-------------|------|
| `int16` | 2 | 1 | 16 位有符号整数 |
| `uint16` | 2 | 1 | 16 位无符号整数 |
| `int32` | 4 | 2 | 32 位有符号整数 |
| `uint32` | 4 | 2 | 32 位无符号整数 |
| `single` | 4 | 2 | 32 位单精度浮点，IEEE 754 |
| `double` | 8 | 4 | 64 位双精度浮点，IEEE 754；仅 EABI 且 `sizeof(double) * CHAR_BIT == 64` 时支持 |

### 3.4.1 double 支持限制

`double` 是可选能力。MATLAB App 必须提供目标 ABI 配置项：

| 目标 ABI | double 策略 |
|----------|-------------|
| EABI，且确认 `sizeof(double) * CHAR_BIT == 64` | 允许使用 `double` |
| COFF ABI 或无法确认 double 为 64 bit | 禁止选择 `double`，或提示用户改用 `single` |

生成代码应包含编译期检查：

```c
#include <limits.h>
C2837X_STATIC_ASSERT((sizeof(double) * CHAR_BIT) == 64u,
                     double_word_size_mismatch);
```

C28x 上 `CHAR_BIT` 通常为 16，因此 64-bit double 常表现为 `sizeof(double) == 4u`。生成器不得只比较 `sizeof(double) == 4u`，否则在 8-bit `char` 的 PC/MEX 侧会把 32-bit double 误判为合法。

### 3.5 数组和维度

V2.3 支持标量和一维数组：

- 标量：维度为 1。
- 一维数组：维度为 N，生成 `type name[N]`。
- 二维及更高维矩阵暂不支持。若用户需要矩阵，应在 App 中显式展平成一维数组。

数组序列化顺序：

```text
x[0], x[1], x[2], ..., x[N-1]
```

禁止在 V2.3 中隐式使用 MATLAB column-major 或 C row-major 规则处理二维矩阵。

### 3.6 报文格式

所有报文采用统一帧格式：

```text
┌──────────┬──────────┬──────────────────────┐
│  type    │  length  │       payload        │
│  uint16  │  uint16  │   length wire bytes  │
│  2字节    │  2字节    │       变长           │
└──────────┴──────────┴──────────────────────┘
```

字段说明：

| 字段 | 类型 | 含义 |
|------|------|------|
| `type` | uint16 little-endian | 报文类型 |
| `length` | uint16 little-endian | payload 的线上 8-bit 字节数，不含 4 字节帧头 |
| `payload` | byte stream | 按报文类型定义 |

长度约束：

1. `length` 必须小于等于 `C2837X_BLOCK_MAX_PAYLOAD_SIZE_BYTES`。
2. 对于 `INPUT_DATA` 和 `OUTPUT_DATA`，`length` 必须等于配置文件中的预期大小。
3. V2.3 定义的所有 payload 长度均为偶数；DSP 端收到奇数 `length` 时，必须在解析 payload 前返回 `RESPONSE(error_code=2)`。
4. App 必须保证 `C2837X_BLOCK_MAX_PAYLOAD_SIZE_BYTES` 为偶数，且 `C2837X_BLOCK_MAX_PAYLOAD_SIZE_BYTES <= 65535`。

### 3.7 报文类型定义

```c
#define C2837X_MSG_SIM_START    0x0001u
#define C2837X_MSG_INPUT_DATA   0x0002u
#define C2837X_MSG_OUTPUT_DATA  0x0003u
#define C2837X_MSG_SIM_STOP     0x0004u
#define C2837X_MSG_RESPONSE     0x0005u
```

V2.3 暂不实现 `DEBUG_MSG`。保留 `0x0006` 及之后的类型供未来扩展。

#### 3.7.1 SIM_START（0x0001）— 仿真开始

方向：Simulink → DSP

payload：

```text
┌──────────────────┬──────────────────┐
│ protocol_version │   config_hash    │
│      uint16      │     uint32       │
└──────────────────┴──────────────────┘
```

payload 长度：6 wire bytes。

字段说明：

| 字段 | 含义 |
|------|------|
| `protocol_version` | 当前为 `0x0001` |
| `config_hash` | 配置签名，按 §6.3 定义的 CRC32 规范计算 |

DSP 收到后：

1. 校验 `length == 6`。
2. 校验 `protocol_version == C2837X_BLOCK_PROTOCOL_VERSION`。
3. 校验 `config_hash == C2837X_BLOCK_CONFIG_HASH`。
4. 调用 `C2837xBlock_OnSimStart()`。
5. 若返回 0，回复 `RESPONSE(error_code=0)` 并进入 `SIM_RUNNING`。
6. 若返回非 0，回复 `RESPONSE(error_code=5)`，调用必要清理并回到 `LISTEN`。

#### 3.7.2 INPUT_DATA（0x0002）— 输入数据

方向：Simulink → DSP

payload：

```text
┌────────────┬─────────────────────────────────────┐
│ step_index │ input_data                          │
│   uint32   │ 按配置文件定义顺序编码的输入变量       │
└────────────┴─────────────────────────────────────┘
```

payload 长度：

```c
C2837X_BLOCK_INPUT_PAYLOAD_SIZE_BYTES = 4 + C2837X_BLOCK_INPUT_DATA_SIZE_BYTES
```

其中：

- `step_index`：仿真步编号，固定从 0 开始。Simulink 端每成功完成一次 `INPUT_DATA → OUTPUT_DATA` 交互后按 uint32 modulo 2^32 加 1；DSP 端维护 `expected_step_index`，`SIM_START` 后重置为 0，并按相同 uint32 回绕规则更新。收到不等于期望值的 `INPUT_DATA` 时返回 `RESPONSE(error_code=7)` 并断开。DSP 端不得修改该值，只能在 `OUTPUT_DATA` 中原样返回。
- `input_data`：按配置文件定义顺序编码。

V2.3 支持 `step_index` 回绕。Simulink 端发送 `UINT32_MAX` 并成功收到对应 `OUTPUT_DATA` 后，下一步 `step_index` 回绕为 0；DSP 端 `expected_step_index` 也同步回绕为 0。回绕前后仍必须逐步匹配，不允许跳步、重发旧步或乱序。

DSP 收到后：

1. 校验 `length == C2837X_BLOCK_INPUT_PAYLOAD_SIZE_BYTES`。
2. 解析并校验 `step_index == expected_step_index`。
3. 调用 `c2837x_block_unpack_input_payload()` 解包输入数据。
4. 调用 `C2837xBlock_OnStep()`。
5. 调用 `c2837x_block_pack_output_payload()`。
6. 发送 `OUTPUT_DATA(step_index)`。
7. 发送成功后将 `expected_step_index` 按 uint32 modulo 2^32 加 1。

如果校验失败或 `C2837xBlock_OnStep()` 返回非 0，DSP 发送 `RESPONSE(error_code>0)`，而不是发送 `OUTPUT_DATA`。

#### 3.7.3 OUTPUT_DATA（0x0003）— 输出数据

方向：DSP → Simulink

payload：

```text
┌────────────┬─────────────────────────────────────┐
│ step_index │ output_data                         │
│   uint32   │ 按配置文件定义顺序编码的输出变量       │
└────────────┴─────────────────────────────────────┘
```

payload 长度：

```c
C2837X_BLOCK_OUTPUT_PAYLOAD_SIZE_BYTES = 4 + C2837X_BLOCK_OUTPUT_DATA_SIZE_BYTES
```

Simulink 收到后：

1. 校验 `length == C2837X_BLOCK_OUTPUT_PAYLOAD_SIZE_BYTES`。
2. 校验返回的 `step_index` 是否等于当前发送的步号。
3. 解包输出数据并写入 Simulink 输出端口。

#### 3.7.4 SIM_STOP（0x0004）— 仿真结束

方向：Simulink → DSP

payload：无，`length = 0`。

DSP 收到后：

1. 调用 `C2837xBlock_OnSimStop()`。
2. 关闭当前 TCP 连接。
3. 回到 `LISTEN` 状态，等待下一次仿真连接。

V2.3 中 `SIM_STOP` 正常情况下不要求返回 `RESPONSE`。如 `SIM_STOP` 长度错误或状态错误，可返回 `RESPONSE(error_code>0)`。

#### 3.7.5 RESPONSE（0x0005）— 应答/错误

方向：DSP → Simulink

payload：

```text
┌──────────────┐
│  error_code  │
│    uint16    │
└──────────────┘
```

payload 长度：2 wire bytes。

`RESPONSE` 用于两类情况：

1. `SIM_START` 的成功或失败应答。
2. 任意状态下的协议错误应答。

正常 `INPUT_DATA` 不返回 `RESPONSE`，而是返回 `OUTPUT_DATA`。异常 `INPUT_DATA` 返回 `RESPONSE(error_code>0)`，Simulink 端在等待 `OUTPUT_DATA` 时必须能够处理 `RESPONSE`。

错误码：

| error_code | 含义 | 处理建议 |
|------------|------|----------|
| 0 | 成功 | 仅用于 SIM_START 成功 |
| 1 | 未知报文类型 | 终止仿真，关闭连接 |
| 2 | 报文长度错误 | 终止仿真，显示期望长度和实际长度 |
| 3 | 配置不匹配 | 终止仿真，提示重新生成配置文件 |
| 4 | 状态错误 | 终止仿真，提示协议流程错误 |
| 5 | 内部错误 | 终止仿真，提示查看 DSP 日志 |
| 6 | 协议版本不匹配 | 终止仿真，提示更新 PC/DSP 端代码 |
| 7 | step_index 不匹配 | 终止仿真，提示通信流程异常 |
| 8 | 不支持的数据类型或 ABI | 终止仿真，提示修改配置 |

### 3.8 TCP 组帧规范

TCP 是字节流协议，不能假设一次 `recv()` 对应一个完整报文。接收端必须实现 `recv_exact()` 或等效状态机：

1. 接收 4 个 wire bytes 的帧头。
2. 解析 `type` 和 `length`。
3. 校验 `length` 是否超过最大缓冲区。
4. 继续接收 `length` 个 wire bytes 的 payload。
5. 完整组帧后交给协议解析层。

发送端也必须实现 `send_all()` 或等效的分段发送状态：

1. 先构造完整帧头和 payload。
2. 循环调用底层发送函数，直到所有 wire bytes 都写入 TCP 发送缓冲区。
3. 不得假设一次 `send()` 一定发送完整帧。

PC 端 `send_all()` 可以在带超时的阻塞循环中完成。DSP 端不得为了发送完整帧而在 `C2837xBlock_Run()` 中长时间自旋；若 W5300 TX buffer 暂不可写，必须保存待发送帧、已发送偏移和开始时间，在后续 `C2837xBlock_Run()` 调用中继续发送，直到完成或超时。

W5300 socket 关闭路径例外：为满足 W5300 Errata M_08082008（修正 `Sn_SSR` 可能从 undefined value 无法切换到 defined value 的问题），`c2837x_w5300_socket_close()` 必须保留 errata close sequence；当 TCP TX buffer 仍有残留数据时，可切换到 UDP 并调用 `send_to()` 发送 dummy data 后再执行 `CLOSE`。该序列属于硬件 errata workaround，不属于协议层普通 TX 分段发送。

### 3.9 超时机制

#### 3.9.1 Simulink 端超时

Simulink 端通过 MATLAB `tcpclient.Timeout` 或 C S-Function socket 超时实现：

| 等待对象 | 默认超时 | 超时处理 |
|----------|----------|----------|
| 建立连接 | 5 s | 报错并终止仿真 |
| SIM_START 的 RESPONSE | 5 s | 报错并终止仿真 |
| 每一步 OUTPUT_DATA 或 RESPONSE(error) | 5 s | 报错并终止仿真 |
| SIM_STOP 发送 | 1 s | 尝试关闭 socket |

#### 3.9.2 DSP 端超时

DSP 端使用非阻塞状态机，不在普通收发路径中长期阻塞。每次调用 `C2837xBlock_Run()` 只处理当前可用事件，然后返回；进入 socket close 时允许执行 W5300 Errata M_08082008 所需的 close sequence。

DSP 端状态超时建议：

| 状态 | 默认超时 | 超时处理 |
|------|----------|----------|
| `CONNECTED` 等待 SIM_START | 5 s | 关闭 socket，回到 LISTEN |
| `SIM_RUNNING` 等待下一帧 | 5 s | 关闭 socket，调用必要清理，回到 LISTEN |
| 接收半帧 | 5 s | 丢弃半帧，关闭 socket，回到 LISTEN |

#### 3.9.3 OnStep 执行时间限制

通信框架只能统计 `C2837xBlock_OnStep()` 正常返回后的耗时。若用户算法死循环或长期阻塞，框架无法靠轮询超时恢复，因为执行流已经停在用户函数中。

要求：

1. 用户算法不得阻塞。
2. 用户算法不得包含无限循环。
3. `OnStep()` 最坏执行时间必须小于 Simulink 端等待 `OUTPUT_DATA` 的超时时间。
4. 对安全性要求较高的项目，应启用 DSP watchdog，由系统级设计处理算法卡死问题。

### 3.10 协议合法性检查

DSP 在收到每个报文后必须进行以下校验：

1. `type` 是否为已知报文类型。
2. `length` 是否超过最大 payload。
3. `length` 是否符合对应报文类型的预期长度。
4. 对 DSP 端 `uint16_t` payload buffer，`length` 是否为偶数。
5. 当前状态是否允许该报文出现。
6. `step_index` 是否等于当前状态保存的 `expected_step_index`。
7. 当前配置是否支持 payload 中使用的数据类型。

不通过时发送 `RESPONSE(error_code>0)`。

Simulink 端也必须对 DSP 返回帧执行同等级检查：`OUTPUT_DATA.length`、`OUTPUT_DATA.step_index`、`RESPONSE.length == 2` 和等待阶段允许的报文类型均不满足时，应终止仿真。

### 3.11 数据完整性

V2.3 依赖 TCP 保证字节流可靠传输，不额外增加帧级 CRC。配置一致性通过 `SIM_START.config_hash` 校验。

未来如需增强，可扩展帧格式：

```text
header + payload + crc16
```

但 V2.3 暂不实现。

---

## 4. Simulink 端

### 4.1 S-Function 模块

S-Function 仅在 PC 端运行，负责数据转发，不涉及控制算法实现。不需要生成 TLC 文件，除非后续需要支持代码生成。

#### 4.1.1 功能职责

1. 读取 Simulink 模型中的输入信号。
2. 按协议打包 `SIM_START`、`INPUT_DATA` 和 `SIM_STOP`。
3. 通过 TCP/IP 发送报文到 DSP。
4. 接收 DSP 返回的 `RESPONSE` 或 `OUTPUT_DATA`。
5. 将输出数据解析后写入 Simulink 输出端口。
6. 发生错误时调用 Simulink 报错接口终止仿真。

#### 4.1.2 采样时间约束

V2.3 仅支持：

```text
与求解器无关，S-Function 模块以固定步长离散采样时间运行
```

限制：

- 不支持 continuous states。
- 不支持多速率异步触发。
- S-Function 每个 sample hit 执行一次完整通信交互：发送 `INPUT_DATA`，等待 `OUTPUT_DATA` 或 `RESPONSE(error)`。
- S-Function 不负责校验模型求解器是否为 fixed-step。只要 Simulink 调用该模块的 sample hit，模块就按配置的离散采样时间执行同步通信。

#### 4.1.3 输入输出端口映射

V2.3 固定采用以下端口布局：

1. 每个标量变量映射为一个 Simulink 输入/输出端口。
2. 每个一维数组变量映射为一个向量端口。
3. 所有端口按照 App 配置中的变量顺序排列。

暂不支持：

- Bus 输入/输出。
- 多维矩阵端口。
- 将不同类型变量合并到同一个向量端口。

#### 4.1.4 MATLAB S-Function

阶段一使用 MATLAB Level-2 S-Function 快速验证。阶段一可固定为：

- 输入：`a`、`b`、`c`，均为 `int16`
- 输出：`sum`，`int16`

MATLAB S-Function 可以不引用 C 配置文件，但仍必须遵守 V2.3 协议：

- `SIM_START` 包含 `protocol_version` 和 `config_hash`。
- `INPUT_DATA` 包含 `step_index`。
- 等待返回时同时处理 `OUTPUT_DATA` 和 `RESPONSE(error)`。

#### 4.1.5 C S-Function

阶段三使用 C MEX S-Function 替代 MATLAB Level-2 S-Function，用于降低 MATLAB 层解释执行开销，提高仿真步通信稳定性。C S-Function **仍然只运行在 PC/Simulink 端**，不包含 DSP 控制算法，也不参与嵌入式代码生成。

V2.3 的 C S-Function 目标范围：

- 支持 Simulink Normal 模式仿真。
- S-Function 模块使用 App 生成的固定离散采样时间运行，不负责检查模型求解器类型。
- 支持单个 C2837xBlock 实例连接一个 DSP。
- 支持 App 生成的标量和一维数组端口。
- 支持 `int16`、`uint16`、`int32`、`uint32`、`single`，以及满足 ABI 条件时的 `double`。
- 不生成 TLC，不支持 Simulink Coder 代码生成。
- 暂不支持 Accelerator、Rapid Accelerator、多实例、多 DSP 或异步后台收发线程。

##### 4.1.5.1 C S-Function 文件组成

阶段三 App 或工程模板应生成/提供以下 PC 端文件：

```text
simulink/
├── c2837x_block_sfun.c             # C MEX S-Function 主文件
├── c2837x_block_sfun.h             # S-Function 内部上下文和辅助声明，可选
├── c2837x_block_pc_socket.h        # PC 端 socket 封装接口
├── c2837x_block_pc_socket.c        # Windows/POSIX socket 实现
├── c2837x_block_protocol.h         # 报文 type、error_code、frame helper 声明
├── c2837x_block_protocol.c         # send_all/recv_exact/send_frame/recv_frame
├── c2837x_block_config.h           # App 生成，PC 端配置头文件
├── c2837x_block_config.c           # App 生成，PC 端字段级序列化实现
└── build_c2837x_block_sfun.m       # App 生成或模板提供的 mex 编译脚本
```

其中：

- `c2837x_block_sfun.c` 负责 Simulink 回调、端口读写、错误上报和生命周期管理。
- `c2837x_block_protocol.c` 负责协议帧组包/拆包，不依赖 Simulink API。
- `c2837x_block_pc_socket.c` 负责平台 socket 差异封装。
- `c2837x_block_config.c` 只负责 PC 端 `uint8_t*` payload 字段级序列化。

##### 4.1.5.2 C S-Function 生命周期

C S-Function 必须实现以下主要回调：

| S-Function 回调 | 职责 |
|---|---|
| `mdlInitializeSizes` | 配置参数数量、输入输出端口数量、端口宽度、端口数据类型、PWork 数量 |
| `mdlInitializeSampleTimes` | 设置 App 生成的固定离散采样时间 |
| `mdlStart` | 分配上下文、初始化 socket、连接 DSP、发送 `SIM_START`、等待 `RESPONSE(0)` |
| `mdlOutputs` | 每个 sample hit 读取输入端口、打包 `INPUT_DATA`、等待 `OUTPUT_DATA` 或 `RESPONSE(error)`、写输出端口 |
| `mdlTerminate` | 发送 `SIM_STOP`、关闭 socket、释放上下文 |

推荐采用显式采样时间参数：

```c
#define C2837X_BLOCK_SAMPLE_TIME  1.0e-4  /* 由 App 或用户配置生成 */
```

V2.3 由 App 生成显式 `C2837X_BLOCK_SAMPLE_TIME_SEC`，并将该值写入 `config_hash` 的 `sample_time_sec` 字段。C S-Function 不需要检查模型求解器类型；求解器配置由用户模型负责。

##### 4.1.5.3 S-Function 上下文

C S-Function 不应使用全局变量保存连接状态，避免多次启动仿真后状态残留。应通过 `PWork` 保存上下文指针：

```c
typedef struct {
    c2837x_socket_t sock;
    uint8_t tx_buf[C2837X_BLOCK_MAX_FRAME_SIZE_BYTES];
    uint8_t rx_buf[C2837X_BLOCK_MAX_FRAME_SIZE_BYTES];
    C2837xBlock_InputData input_cache;
    C2837xBlock_OutputData output_cache;
    uint32_t step_index;
    uint32_t connect_timeout_ms;
    uint32_t step_timeout_ms;
    uint32_t terminate_timeout_ms;
    int connected;
    int sim_started;
} C2837xBlockSfunContext;
```

`PWork[0]` 保存 `C2837xBlockSfunContext*`：

```c
ssSetNumPWork(S, 1);
ssSetPWorkValue(S, 0, ctx);
```

V2.3 仅支持单实例。实现中可以使用静态实例计数防止用户在同一模型中放置多个 C2837xBlock：

```c
static int g_c2837x_block_instance_count = 0;
```

单实例计数必须遵守完整生命周期规则：

1. `mdlStart` 在成功通过单实例检查并准备分配上下文前，将计数加 1。
2. `mdlStart` 任意失败路径必须将计数恢复。
3. `mdlTerminate` 释放上下文后必须将计数减 1。
4. 计数不得小于 0。
5. 必须在 Fast Restart、多次启动/停止仿真场景下验证计数不会残留。

在 `mdlStart` 中若计数大于 0，应调用 `ssSetErrorStatus()` 报错并立即返回，不得继续连接 DSP。

##### 4.1.5.4 端口配置规则

C S-Function 的端口由 App 生成的配置决定：

- 每个标量变量对应一个端口，宽度为 1。
- 每个一维数组变量对应一个端口，宽度为数组长度。
- 端口顺序与 `config_hash` 规范化字符串中的变量顺序完全一致。
- 输入端口设置 `DirectFeedThrough = 1`。
- 输入端口必须设置 `RequiredContiguous = 1`，因为生成代码使用 `ssGetInputPortSignal()` 并按 C 数组方式访问端口数据。
- 端口数据类型必须与配置类型一致。

示例端口配置：

```c
static void mdlInitializeSizes(SimStruct *S)
{
    ssSetNumSFcnParams(S, 0);

    if (!ssSetNumInputPorts(S, C2837X_BLOCK_INPUT_COUNT)) return;
    ssSetInputPortWidth(S, 0, 1);
    ssSetInputPortDataType(S, 0, SS_INT16);
    ssSetInputPortDirectFeedThrough(S, 0, 1);
    ssSetInputPortRequiredContiguous(S, 0, 1);

    ssSetInputPortWidth(S, 1, 1);
    ssSetInputPortDataType(S, 1, SS_INT16);
    ssSetInputPortDirectFeedThrough(S, 1, 1);
    ssSetInputPortRequiredContiguous(S, 1, 1);

    ssSetInputPortWidth(S, 2, 1);
    ssSetInputPortDataType(S, 2, SS_INT16);
    ssSetInputPortDirectFeedThrough(S, 2, 1);
    ssSetInputPortRequiredContiguous(S, 2, 1);

    if (!ssSetNumOutputPorts(S, C2837X_BLOCK_OUTPUT_COUNT)) return;
    ssSetOutputPortWidth(S, 0, 1);
    ssSetOutputPortDataType(S, 0, SS_INT16);

    ssSetNumSampleTimes(S, 1);
    ssSetNumPWork(S, 1);

    ssSetOptions(S, SS_OPTION_EXCEPTION_FREE_CODE);
}
```

App 生成 C S-Function 时，应根据变量类型生成对应的 Simulink 数据类型：

| 配置类型 | Simulink C API 数据类型 |
|---|---|
| `int16` | `SS_INT16` |
| `uint16` | `SS_UINT16` |
| `int32` | `SS_INT32` |
| `uint32` | `SS_UINT32` |
| `single` | `SS_SINGLE` |
| `double` | `SS_DOUBLE` |

##### 4.1.5.5 `mdlStart` 连接流程

`mdlStart` 执行一次仿真启动握手：

```text
分配 ctx
初始化 socket 子系统
连接 DSP IP:PORT
发送 SIM_START(protocol_version, config_hash)
等待 RESPONSE
    RESPONSE(error_code=0): 进入运行状态
    RESPONSE(error_code>0): ssSetErrorStatus 并终止仿真
    超时/断开: ssSetErrorStatus 并终止仿真
```

伪代码：

```c
static void mdlStart(SimStruct *S)
{
    C2837xBlockSfunContext* ctx = NULL;

    if (g_c2837x_block_instance_count > 0) {
        ssSetErrorStatus(S, "C2837xBlock: only one instance is supported");
        return;
    }
    g_c2837x_block_instance_count++;

    ctx = (C2837xBlockSfunContext*)calloc(1, sizeof(*ctx));
    if (ctx == NULL) {
        ssSetErrorStatus(S, "C2837xBlock: failed to allocate context");
        goto fail;
    }

    ctx->connect_timeout_ms   = C2837X_BLOCK_PC_CONNECT_TIMEOUT_MS;
    ctx->step_timeout_ms      = C2837X_BLOCK_PC_STEP_TIMEOUT_MS;
    ctx->terminate_timeout_ms = C2837X_BLOCK_PC_TERMINATE_TIMEOUT_MS;
    ctx->step_index = 0u;
    ssSetPWorkValue(S, 0, ctx);

    if (c2837x_socket_connect(&ctx->sock,
                              C2837X_BLOCK_IP_ADDR,
                              C2837X_BLOCK_TCP_PORT,
                              ctx->connect_timeout_ms) != 0) {
        ssSetErrorStatus(S, "C2837xBlock: failed to connect DSP");
        goto fail;
    }

    ctx->connected = 1;

    if (c2837x_protocol_send_sim_start(&ctx->sock,
                                       C2837X_BLOCK_PROTOCOL_VERSION,
                                       C2837X_BLOCK_CONFIG_HASH,
                                       ctx->step_timeout_ms) != 0) {
        ssSetErrorStatus(S, "C2837xBlock: failed to send SIM_START");
        goto fail;
    }

    if (c2837x_protocol_wait_response_ok(&ctx->sock, ctx->step_timeout_ms) != 0) {
        ssSetErrorStatus(S, "C2837xBlock: SIM_START rejected by DSP");
        goto fail;
    }

    ctx->sim_started = 1;
    return;

fail:
    if (ctx != NULL) {
        if (ctx->connected) {
            c2837x_socket_close(&ctx->sock);
        }
        free(ctx);
        ssSetPWorkValue(S, 0, NULL);
    }
    if (g_c2837x_block_instance_count > 0) {
        g_c2837x_block_instance_count--;
    }
}
```

##### 4.1.5.6 阻塞行为和仿真时间说明

C S-Function 在 `mdlOutputs()` 中执行同步通信：发送 `INPUT_DATA` 后等待 DSP 返回 `OUTPUT_DATA` 或 `RESPONSE(error)`。因此模块不保证实时墙钟执行。若 DSP 响应时间大于 Simulink sample time，仿真会变慢，而不是丢步。

`C2837X_BLOCK_PC_STEP_TIMEOUT_MS` 应大于 DSP `C2837xBlock_OnStep()` 的最坏执行时间和网络往返时间，但不应设置过大，否则 DSP 异常时 MATLAB 可能长时间卡住。

##### 4.1.5.7 `mdlOutputs` 单步通信流程

每个仿真步执行：

```text
读取 Simulink 输入端口
填充 C2837xBlock_InputData
pack INPUT_DATA payload，包含 step_index
send_frame(INPUT_DATA)
recv_frame()
    OUTPUT_DATA: 校验 length 与 step_index，unpack，写输出端口，step_index 按 uint32 回绕规则加 1
    RESPONSE(error): 校验 length == 2 且 error_code > 0，转换错误码为文本，ssSetErrorStatus
    RESPONSE(0): 协议错误，ssSetErrorStatus
    其他 type: 协议错误，ssSetErrorStatus
```

伪代码：

```c
static void mdlOutputs(SimStruct *S, int_T tid)
{
    C2837xBlockSfunContext* ctx =
        (C2837xBlockSfunContext*)ssGetPWorkValue(S, 0);

    if (ctx == NULL || !ctx->connected || !ctx->sim_started) {
        ssSetErrorStatus(S, "C2837xBlock: invalid runtime state");
        return;
    }

    /* 1. 读取输入端口到 input_cache。实际代码由 App 按配置生成。 */
    const int16_T* u0 = (const int16_T*)ssGetInputPortSignal(S, 0);
    const int16_T* u1 = (const int16_T*)ssGetInputPortSignal(S, 1);
    const int16_T* u2 = (const int16_T*)ssGetInputPortSignal(S, 2);
    ctx->input_cache.a = (int16_t)u0[0];
    ctx->input_cache.b = (int16_t)u1[0];
    ctx->input_cache.c = (int16_t)u2[0];

    /* 2. 打包并发送 INPUT_DATA。 */
    c2837x_block_pack_input_payload(ctx->tx_buf,
                                    ctx->step_index,
                                    &ctx->input_cache);

    if (c2837x_protocol_send_frame(&ctx->sock,
                                   C2837X_MSG_INPUT_DATA,
                                   C2837X_BLOCK_INPUT_PAYLOAD_SIZE_BYTES,
                                   ctx->tx_buf,
                                   ctx->step_timeout_ms) != 0) {
        ssSetErrorStatus(S, "C2837xBlock: failed to send INPUT_DATA");
        return;
    }

    /* 3. 等待 OUTPUT_DATA 或 RESPONSE(error)。 */
    uint16_t type = 0;
    uint16_t length = 0;
    if (c2837x_protocol_recv_frame(&ctx->sock,
                                   &type,
                                   &length,
                                   ctx->rx_buf,
                                   sizeof(ctx->rx_buf),
                                   ctx->step_timeout_ms) != 0) {
        ssSetErrorStatus(S, "C2837xBlock: timeout waiting DSP response");
        return;
    }

    if (type == C2837X_MSG_OUTPUT_DATA) {
        uint32_t returned_step = 0u;
        if (length != C2837X_BLOCK_OUTPUT_PAYLOAD_SIZE_BYTES) {
            ssSetErrorStatus(S, "C2837xBlock: invalid OUTPUT_DATA length");
            return;
        }

        c2837x_block_unpack_output_payload(ctx->rx_buf,
                                           &returned_step,
                                           &ctx->output_cache);
        if (returned_step != ctx->step_index) {
            ssSetErrorStatus(S, "C2837xBlock: step_index mismatch");
            return;
        }

        int16_T* y0 = (int16_T*)ssGetOutputPortSignal(S, 0);
        y0[0] = (int16_T)ctx->output_cache.sum;

        ctx->step_index++;  /* uint32 modulo 2^32 wrap is intentional */
    }
    else if (type == C2837X_MSG_RESPONSE) {
        if (length != 2u) {
            ssSetErrorStatus(S, "C2837xBlock: invalid RESPONSE length");
            return;
        }
        uint16_t error_code = c2837x_protocol_parse_response(ctx->rx_buf, length);
        if (error_code == 0u) {
            ssSetErrorStatus(S, "C2837xBlock: unexpected RESPONSE(0) during step");
            return;
        }
        ssSetErrorStatus(S, c2837x_protocol_error_to_string(error_code));
        return;
    }
    else {
        ssSetErrorStatus(S, "C2837xBlock: unexpected frame type");
        return;
    }
}
```

##### 4.1.5.8 `mdlTerminate` 关闭流程

`mdlTerminate` 必须尽最大努力通知 DSP 仿真结束，但不能因为 DSP 无响应而卡住 MATLAB：

```text
如果 connected：
    如果 sim_started：发送 SIM_STOP，使用短超时
    关闭 socket
释放 ctx
清理 socket 子系统
```

伪代码：

```c
static void mdlTerminate(SimStruct *S)
{
    C2837xBlockSfunContext* ctx =
        (C2837xBlockSfunContext*)ssGetPWorkValue(S, 0);

    if (ctx != NULL) {
        if (ctx->connected && ctx->sim_started) {
            (void)c2837x_protocol_send_frame(&ctx->sock,
                                             C2837X_MSG_SIM_STOP,
                                             0u,
                                             NULL,
                                             C2837X_BLOCK_PC_TERMINATE_TIMEOUT_MS);
        }

        if (ctx->connected) {
            c2837x_socket_close(&ctx->sock);
        }

        free(ctx);
        ssSetPWorkValue(S, 0, NULL);

        if (g_c2837x_block_instance_count > 0) {
            g_c2837x_block_instance_count--;
        }
    }
}
```

##### 4.1.5.9 PC 端 socket 封装要求

C S-Function 不应在 `c2837x_block_sfun.c` 中直接散落调用 WinSock 或 POSIX API，应通过统一接口封装：

```c
typedef struct {
#ifdef _WIN32
    SOCKET fd;
#else
    int fd;
#endif
} c2837x_socket_t;

int c2837x_socket_connect(c2837x_socket_t* s,
                          const char* ip,
                          uint16_t port,
                          uint32_t timeout_ms);
int c2837x_socket_send_all(c2837x_socket_t* s,
                           const uint8_t* data,
                           uint32_t length,
                           uint32_t timeout_ms);
int c2837x_socket_recv_exact(c2837x_socket_t* s,
                             uint8_t* data,
                             uint32_t length,
                             uint32_t timeout_ms);
void c2837x_socket_close(c2837x_socket_t* s);
```

协议层必须基于 `send_all()` 和 `recv_exact()` 实现：

```c
int c2837x_protocol_send_frame(c2837x_socket_t* s,
                               uint16_t type,
                               uint16_t length,
                               const uint8_t* payload,
                               uint32_t timeout_ms);

int c2837x_protocol_recv_frame(c2837x_socket_t* s,
                               uint16_t* type,
                               uint16_t* length,
                               uint8_t* payload,
                               uint32_t payload_capacity,
                               uint32_t timeout_ms);
```

##### 4.1.5.10 错误处理规则

C S-Function 中任何通信错误、协议错误、配置错误或 DSP 返回错误，都必须通过以下方式上报：

```c
ssSetErrorStatus(S, "C2837xBlock: ...");
```

不得使用 `printf()` 作为唯一错误提示。允许辅助使用：

```c
ssPrintf("C2837xBlock: diagnostic message\n");
```

错误发生后：

1. 当前 `mdlOutputs` 立即返回。
2. Simulink 终止仿真。
3. `mdlTerminate` 负责释放 socket 和内存。

##### 4.1.5.11 MEX 编译方式

App 应生成 `build_c2837x_block_sfun.m`，用于编译 C S-Function：

```matlab
function build_c2837x_block_sfun()
%BUILD_C2837X_BLOCK_SFUN Build C2837xBlock C MEX S-Function.

src = {
    'c2837x_block_sfun.c', ...
    'c2837x_block_config.c', ...
    'c2837x_block_protocol.c', ...
    'c2837x_block_pc_socket.c' ...
};

if ispc
    mex('-R2018a', src{:}, 'ws2_32.lib');
else
    mex('-R2018a', src{:});
end
end
```

编译输出的 MEX 文件名应与 S-Function 名称一致，例如：

```text
c2837x_block_sfun.mexw64
```

Simulink 模型中 S-Function block 的 Function name 填写：

```text
c2837x_block_sfun
```

##### 4.1.5.12 与 MATLAB S-Function 的差异

| 项目 | MATLAB S-Function | C S-Function |
|---|---|---|
| 目标阶段 | 阶段一 | 阶段三 |
| 实现语言 | MATLAB | C/MEX |
| socket | `tcpclient` | WinSock/POSIX 封装 |
| 配置文件 | 可固定写死 | 必须使用 App 生成 PC 端配置 |
| 序列化 | MATLAB 字节数组 | `uint8_t*` 字段级序列化 |
| 性能 | 较低 | 较高 |
| 调试便利性 | 高 | 中 |
| 代码生成 | 不支持 | V2.3 不支持，未来需 TLC |

#### 4.1.6 Simulink 端接收逻辑

每个仿真步：

```text
发送 INPUT_DATA(step_index=N)
等待下一帧：
    如果 type == OUTPUT_DATA:
        校验 step_index
        解包 output_data
        输出到 Simulink
    如果 type == RESPONSE 且 error_code > 0:
        校验 length == 2
        显示错误并终止仿真
    如果 type == RESPONSE 且 error_code == 0:
        按协议错误处理并终止仿真
    其他情况:
        显示协议错误并终止仿真
```

### 4.2 TCP/IP 通信

MATLAB S-Function 使用 MATLAB `tcpclient`。C S-Function 使用 Windows Socket API 或跨平台 socket 封装。

连接参数：

- DSP IP 地址
- TCP 端口号
- 超时时间

仿真结束时，Simulink 主动发送 `SIM_STOP`，然后关闭连接。

---

## 5. DSP 端

### 5.1 库的形式

DSP 端以库形式提供通信框架，不包含板级设备初始化代码。用户负责：

- 系统时钟配置
- GPIO 和 EMIF1 初始化
- W5300 硬件连接相关配置
- 中断配置
- 其他外设初始化
- watchdog 策略

### 5.2 提供的文件

```text
c2837x_block/
├── inc/
│   ├── c2837x_block.h                 # 库核心 API
│   ├── c2837x_block_algorithm.h       # 用户最小接口，App生成
│   ├── c2837x_block_config.h          # DSP端配置头文件，App生成
│   ├── W5300_define.h                 # W5300寄存器定义
│   ├── W5300_C2837x.h                 # W5300硬件抽象层
│   └── W5300_Socket.h                 # Socket API
└── src/
    ├── c2837x_block.c                 # 状态机和协议处理
    ├── c2837x_block_global_variable.c # 输入输出全局变量定义，App生成
    ├── c2837x_block_config.c          # DSP端序列化代码，App生成
    ├── W5300_C2837x.c                 # W5300驱动
    └── W5300_Socket.c                 # Socket API实现

my_algorithm/
├── my_algorithm.c                     # 用户算法实现
└── ...
```

### 5.3 库核心 API（c2837x_block.h）

```c
#ifndef C2837X_BLOCK_H
#define C2837X_BLOCK_H

#include "F28x_Project.h"

int16 C2837xBlock_Init(void);
void C2837xBlock_Run(void);

#endif /* C2837X_BLOCK_H */
```

#### 5.3.1 C2837xBlock_Init

初始化通信库：

1. 初始化 W5300。
2. 配置网络参数。
3. 打开指定 socket。
4. 进入 `LISTEN` 状态。

该函数在 `main()` 初始化阶段调用一次。返回 0 表示初始化成功，非 0 表示 W5300、socket 或网络参数初始化失败，用户工程应进入安全降级或错误停机路径。

#### 5.3.2 C2837xBlock_Run

非阻塞状态机调度函数。用户在主循环中反复调用：

```c
void main(void)
{
    SystemInit();
    BoardInit();
    if (C2837xBlock_Init() != 0) {
        for (;;) {
            /* 初始化失败，用户工程在此进入安全处理。 */
        }
    }

    while (1) {
        C2837xBlock_Run();
        /* 其他后台任务 */
    }
}
```

要求：

- `C2837xBlock_Run()` 普通收发路径不得长期阻塞；socket close 路径必须执行 W5300 Errata M_08082008 所需的 close sequence。
- 若当前无连接或无数据，应快速返回。
- 若收到完整报文，则处理一次事件后返回。

### 5.4 用户接口（c2837x_block_algorithm.h）

由 MATLAB App 生成，用户算法只需要包含该头文件。

```c
#ifndef C2837X_BLOCK_ALGORITHM_H
#define C2837X_BLOCK_ALGORITHM_H

#include "F28x_Project.h"

typedef struct {
    int16 a;
    int16 b;
    int16 c;
} C2837xBlock_InputData;

typedef struct {
    int16 sum;
} C2837xBlock_OutputData;

extern C2837xBlock_InputData  c2837x_block_input;
extern C2837xBlock_OutputData c2837x_block_output;

int16 C2837xBlock_OnSimStart(void);
int16 C2837xBlock_OnStep(void);
void C2837xBlock_OnSimStop(void);

#endif /* C2837X_BLOCK_ALGORITHM_H */
```

回调返回值约定：

| 回调 | 返回值 | 框架行为 |
|------|--------|----------|
| `C2837xBlock_OnSimStart()` | 0 | 发送 `RESPONSE(0)`，进入 `SIM_RUNNING` |
| `C2837xBlock_OnSimStart()` | 非 0 | 发送 `RESPONSE(5)`，清理并回到 `LISTEN` |
| `C2837xBlock_OnStep()` | 0 | 打包并发送 `OUTPUT_DATA` |
| `C2837xBlock_OnStep()` | 非 0 | 发送 `RESPONSE(5)`，不发送 `OUTPUT_DATA` |

`C2837xBlock_OnSimStop()` 不返回状态；框架在调用后关闭当前连接并重新监听。

### 5.5 DSP 状态机

状态定义：

```c
typedef enum {
    C2837X_STATE_LISTEN = 0,
    C2837X_STATE_CONNECTED,
    C2837X_STATE_SIM_RUNNING,
    C2837X_STATE_DISCONNECTED,
    C2837X_STATE_ERROR
} C2837xBlock_State;
```

状态转移：

```text
INIT
 ↓
LISTEN
 ↓  TCP连接建立
CONNECTED
 ↓  收到合法SIM_START并初始化成功
SIM_RUNNING
 ↓  收到SIM_STOP或连接断开或超时或协议错误
DISCONNECTED
 ↓  关闭socket并重新打开监听
LISTEN
```

状态行为：

| 状态 | 行为 |
|------|------|
| `LISTEN` | 检查 socket 是否有连接；无连接立即返回 |
| `CONNECTED` | 等待 `SIM_START`；收到非法报文返回错误 |
| `SIM_RUNNING` | 处理 `INPUT_DATA` 或 `SIM_STOP` |
| `DISCONNECTED` | 关闭 socket，清理状态，重新进入 `LISTEN` |
| `ERROR` | 发送 `RESPONSE(error)` 后转入 `DISCONNECTED` |

异常进入 `DISCONNECTED` 的条件：

- TCP 断开
- 接收超时
- 半帧超时
- 协议错误
- MATLAB 异常退出
- W5300 socket 状态异常

### 5.6 通信主循环逻辑

```text
C2837xBlock_Run()
    │
    ├─ LISTEN:
    │     检查是否有TCP连接
    │     无连接则返回
    │
    ├─ CONNECTED:
    │     尝试接收完整报文
    │     期望 SIM_START
    │     校验 protocol_version + config_hash
    │     调用 OnSimStart
    │     如果返回0：发送 RESPONSE(0)，expected_step_index = 0，进入 SIM_RUNNING
    │     如果返回非0：发送 RESPONSE(5)，进入 DISCONNECTED
    │
    ├─ SIM_RUNNING:
    │     尝试接收完整报文
    │     如果 INPUT_DATA:
    │         校验 length
    │         解析并校验 step_index == expected_step_index
    │         unpack input
    │         调用 OnStep
    │         如果返回0：pack output，发送 OUTPUT_DATA(step_index)，expected_step_index 按 uint32 回绕规则加 1
    │         如果返回非0：发送 RESPONSE(5)，进入 DISCONNECTED
    │     如果 SIM_STOP:
    │         调用 OnSimStop
    │         进入 DISCONNECTED
    │     如果非法报文:
    │         发送 RESPONSE(error)
    │         进入 DISCONNECTED
    │
    └─ DISCONNECTED:
          关闭socket
          重新监听
```

### 5.7 内部调试输出

V2.3 不提供用户级 `fprintf` 或 `DEBUG_MSG` 报文。通信框架可以实现内部错误日志缓存，用于调试或断点查看，但不对用户算法公开。

阶段二开发计划中的“DSP 端 fprintf 调试输出”调整为：

```text
实现框架内部错误日志缓存，不提供用户级 fprintf。
```

未来如需支持用户调试输出，应单独定义 `DEBUG_MSG` 报文，并规定 Simulink 在等待 `OUTPUT_DATA` 时如何处理夹杂的调试消息。

### 5.8 W5300 资源分配

W5300 提供内部 socket buffer，V2.3 仅使用 Socket 0。规格文档中不假设 TX 和 RX 各有 128 KB，而是按总 buffer 资源进行分配。

建议配置：

| Socket | TX buffer | RX buffer | 用途 |
|--------|-----------|-----------|------|
| Socket 0 | 64 KB | 64 KB | Simulink ↔ DSP 通信 |
| 其他 Socket | 0 | 0 | 未使用 |

最终 TX/RX 大小以 W5300 数据手册、驱动实现和寄存器配置为准。App 中可将 TX/RX buffer 分配作为高级参数，默认使用单 Socket 均分策略。

W5300 驱动层必须增加字节序自检。推荐固定测试向量：PC 发送 payload 字节序列 `01 02 03 04 05 06`，DSP 端经 W5300 驱动读取后，必须能够还原等价的线上字节顺序 `01 02 03 04 05 06`。如果驱动内部以 `uint16_t word` 暂存，则必须在驱动文档中明确 `word[0]` 对应 `0x0201` 还是 `0x0102`，并由协议层统一转换。

---

## 6. 配置文件

### 6.1 配置文件生成方式

- **手动编写**：阶段一快速验证使用。
- **MATLAB App 生成**：正式使用时由图形界面配置并生成。

### 6.2 DSP 端生成文件

DSP 端使用以下文件：

1. `c2837x_block_algorithm.h`：数据结构、全局变量声明和用户回调声明。
2. `c2837x_block_config.h`：协议参数、网络参数、大小宏和序列化函数声明。
3. `c2837x_block_config.c`：DSP 端 `uint16_t word buffer` 序列化实现。
4. `c2837x_block_global_variable.c`：输入输出全局变量定义。

### 6.3 config_hash 定义

`config_hash` 使用 CRC-32/ISO-HDLC。

参数：

| 参数 | 值 |
|------|----|
| width | 32 |
| poly | 0x04C11DB7 |
| init | 0xFFFFFFFF |
| refin | true |
| refout | true |
| xorout | 0xFFFFFFFF |

计算输入为 UTF-8 编码的规范化字符串。字符串格式必须固定，字段顺序不得变化。

示例：

```text
protocol=0x0001
abi=eabi
endianness=little
dsp_ip=192.168.1.15
gateway=192.168.1.1
subnet=255.255.255.0
tcp_port=5000
socket_num=0
sample_time_sec=0.0001
input_count=3
input[0].name=a;type=int16;dim=1
input[1].name=b;type=int16;dim=1
input[2].name=c;type=int16;dim=1
output_count=1
output[0].name=sum;type=int16;dim=1
input_data_size_bytes=6
output_data_size_bytes=2
input_payload_size_bytes=10
output_payload_size_bytes=6
double_mode=disabled
```

规则：

1. 换行符固定为 `\n`。
2. 变量名保持用户配置原文，但 App 必须先校验其为合法 C 标识符，且不得是 C 关键字、保留标识符、重复名称或与生成代码内部字段冲突。
3. 类型名使用固定小写枚举：`int16`、`uint16`、`int32`、`uint32`、`single`、`double`。
4. 一维数组维度写为实际元素个数，例如 `dim=8`。
5. 标量维度写为 `dim=1`。
6. 必须包含 `input_data_size_bytes`、`output_data_size_bytes`、`input_payload_size_bytes`、`output_payload_size_bytes`。
7. 若启用 double，`double_mode=eabi64`；否则 `double_mode=disabled`。
8. 必须包含 `sample_time_sec`。该值应与 Simulink C S-Function sample time 和 DSP 算法配置采样周期一致。
9. 必须包含 App 生成的网络参数：`dsp_ip`、`gateway`、`subnet`、`tcp_port` 和 `socket_num`。
10. `sample_time_sec` 必须使用 locale-independent 的十进制文本，例如 MATLAB `sprintf('%.17g', value)`；不得受系统区域设置影响写成逗号小数。

MATLAB App、PC C 端和 DSP C 端如都实现 CRC32，则必须对同一规范化字符串得到相同结果。V2.3 推荐由 MATLAB App 计算 `config_hash` 后写入 PC 和 DSP 配置文件，DSP 端不必运行时重新计算。

### 6.4 静态断言兼容宏

为兼容不同 TI C2000 编译器版本，App 生成代码应使用封装宏：

```c
#if defined(__STDC_VERSION__) && (__STDC_VERSION__ >= 201112L)
#define C2837X_STATIC_ASSERT(cond, name) _Static_assert((cond), #name)
#else
#define C2837X_STATIC_ASSERT_JOIN_(a, b) a##b
#define C2837X_STATIC_ASSERT_JOIN(a, b)  C2837X_STATIC_ASSERT_JOIN_(a, b)
#define C2837X_STATIC_ASSERT(cond, name) \
    typedef char C2837X_STATIC_ASSERT_JOIN(static_assertion_, __LINE__)[(cond) ? 1 : -1]
#endif
```

### 6.5 DSP 端配置头文件示例（c2837x_block_config.h）

```c
#ifndef C2837X_BLOCK_CONFIG_H
#define C2837X_BLOCK_CONFIG_H

#include <stdint.h>

/* ---- 静态断言兼容宏 ---- */
#if defined(__STDC_VERSION__) && (__STDC_VERSION__ >= 201112L)
#define C2837X_STATIC_ASSERT(cond, name) _Static_assert((cond), #name)
#else
#define C2837X_STATIC_ASSERT_JOIN_(a, b) a##b
#define C2837X_STATIC_ASSERT_JOIN(a, b)  C2837X_STATIC_ASSERT_JOIN_(a, b)
#define C2837X_STATIC_ASSERT(cond, name) \
    typedef char C2837X_STATIC_ASSERT_JOIN(static_assertion_, __LINE__)[(cond) ? 1 : -1]
#endif

/* ---- 协议配置 ---- */
#define C2837X_BLOCK_PROTOCOL_VERSION  0x0001u
#define C2837X_BLOCK_CONFIG_HASH       0xXXXXXXXXu
#define C2837X_BLOCK_SAMPLE_TIME_SEC   1.0e-4

/* ---- 网络配置 ---- */
#define C2837X_BLOCK_IP_ADDR           0xC0A80164u   /* 192.168.1.15 */
#define C2837X_BLOCK_GATEWAY           0xC0A80101u   /* 192.168.1.1   */
#define C2837X_BLOCK_SUBNET            0xFFFFFF00u   /* 255.255.255.0 */
#define C2837X_BLOCK_TCP_PORT          5000u
#define C2837X_BLOCK_SOCKET_NUM        0u
#define C2837X_BLOCK_ENABLE_DOUBLE     0u

#define C2837X_BLOCK_MAX_PAYLOAD_SIZE_BYTES       1024u
#define C2837X_BLOCK_MAX_FRAME_SIZE_BYTES         (4u + C2837X_BLOCK_MAX_PAYLOAD_SIZE_BYTES)

/* ---- 报文类型 ---- */
#define C2837X_MSG_SIM_START           0x0001u
#define C2837X_MSG_INPUT_DATA          0x0002u
#define C2837X_MSG_OUTPUT_DATA         0x0003u
#define C2837X_MSG_SIM_STOP            0x0004u
#define C2837X_MSG_RESPONSE            0x0005u

/* ---- 数据数量 ---- */
#define C2837X_BLOCK_INPUT_COUNT       3u
#define C2837X_BLOCK_OUTPUT_COUNT      1u

/* ---- 线上字节数 ---- */
#define C2837X_BLOCK_INPUT_DATA_SIZE_BYTES      6u
#define C2837X_BLOCK_OUTPUT_DATA_SIZE_BYTES     2u
#define C2837X_BLOCK_INPUT_PAYLOAD_SIZE_BYTES   (4u + C2837X_BLOCK_INPUT_DATA_SIZE_BYTES)
#define C2837X_BLOCK_OUTPUT_PAYLOAD_SIZE_BYTES  (4u + C2837X_BLOCK_OUTPUT_DATA_SIZE_BYTES)

/* ---- DSP 端 word 数 ---- */
#define C2837X_BLOCK_INPUT_DATA_SIZE_WORDS      (C2837X_BLOCK_INPUT_DATA_SIZE_BYTES / 2u)
#define C2837X_BLOCK_OUTPUT_DATA_SIZE_WORDS     (C2837X_BLOCK_OUTPUT_DATA_SIZE_BYTES / 2u)
#define C2837X_BLOCK_INPUT_PAYLOAD_SIZE_WORDS   (C2837X_BLOCK_INPUT_PAYLOAD_SIZE_BYTES / 2u)
#define C2837X_BLOCK_OUTPUT_PAYLOAD_SIZE_WORDS  (C2837X_BLOCK_OUTPUT_PAYLOAD_SIZE_BYTES / 2u)
#define C2837X_BLOCK_MAX_PAYLOAD_SIZE_WORDS     (C2837X_BLOCK_MAX_PAYLOAD_SIZE_BYTES / 2u)

/* ---- payload 打包/解包函数 ---- */
void c2837x_block_unpack_input_payload(const uint16_t* payload_words,
                                       uint32_t* step_index);
void c2837x_block_pack_output_payload(uint16_t* payload_words,
                                      uint32_t step_index);

#endif /* C2837X_BLOCK_CONFIG_H */
```

### 6.6 DSP 端配置源文件示例（c2837x_block_config.c）

```c
#include "c2837x_block_config.h"
#include "c2837x_block_algorithm.h"
#include <limits.h>
#include <string.h>

/* ---- 静态断言 ---- */
C2837X_STATIC_ASSERT((sizeof(uint16_t) * CHAR_BIT) == 16u,
                     uint16_bit_size_mismatch);
C2837X_STATIC_ASSERT((sizeof(uint32_t) * CHAR_BIT) == 32u,
                     uint32_bit_size_mismatch);
C2837X_STATIC_ASSERT((sizeof(float) * CHAR_BIT) == 32u,
                     single_bit_size_mismatch);
C2837X_STATIC_ASSERT((C2837X_BLOCK_INPUT_DATA_SIZE_BYTES % 2u) == 0u,
                     input_data_size_must_be_even);
C2837X_STATIC_ASSERT((C2837X_BLOCK_OUTPUT_DATA_SIZE_BYTES % 2u) == 0u,
                     output_data_size_must_be_even);

static inline void write_uint16(uint16_t* buf, uint32_t* offset, uint16_t val)
{
    buf[(*offset)++] = val;
}

static inline uint16_t read_uint16(const uint16_t* buf, uint32_t* offset)
{
    return buf[(*offset)++];
}

static inline void write_int16(uint16_t* buf, uint32_t* offset, int16_t val)
{
    write_uint16(buf, offset, (uint16_t)val);
}

static inline int16_t read_int16(const uint16_t* buf, uint32_t* offset)
{
    return (int16_t)read_uint16(buf, offset);
}

static inline void write_uint32(uint16_t* buf, uint32_t* offset, uint32_t val)
{
    buf[(*offset)++] = (uint16_t)(val & 0xFFFFu);
    buf[(*offset)++] = (uint16_t)((val >> 16) & 0xFFFFu);
}

static inline uint32_t read_uint32(const uint16_t* buf, uint32_t* offset)
{
    uint32_t lo = (uint32_t)buf[(*offset)++];
    uint32_t hi = (uint32_t)buf[(*offset)++];
    return lo | (hi << 16);
}

static inline void write_int32(uint16_t* buf, uint32_t* offset, int32_t val)
{
    write_uint32(buf, offset, (uint32_t)val);
}

static inline int32_t read_int32(const uint16_t* buf, uint32_t* offset)
{
    return (int32_t)read_uint32(buf, offset);
}

static inline void write_single(uint16_t* buf, uint32_t* offset, float val)
{
    uint32_t raw;
    memcpy(&raw, &val, sizeof(raw));
    write_uint32(buf, offset, raw);
}

static inline float read_single(const uint16_t* buf, uint32_t* offset)
{
    uint32_t raw = read_uint32(buf, offset);
    float val;
    memcpy(&val, &raw, sizeof(val));
    return val;
}

#if C2837X_BLOCK_ENABLE_DOUBLE
/* double 仅在启用 double64 时生成。 */
C2837X_STATIC_ASSERT((sizeof(double) * CHAR_BIT) == 64u,
                     double_bit_size_mismatch);

static inline void write_double64(uint16_t* buf, uint32_t* offset, double val)
{
    uint16_t raw_words[4];
    memcpy(raw_words, &val, sizeof(raw_words));
    buf[(*offset)++] = raw_words[0];
    buf[(*offset)++] = raw_words[1];
    buf[(*offset)++] = raw_words[2];
    buf[(*offset)++] = raw_words[3];
}

static inline double read_double64(const uint16_t* buf, uint32_t* offset)
{
    uint16_t raw_words[4];
    double val;
    raw_words[0] = buf[(*offset)++];
    raw_words[1] = buf[(*offset)++];
    raw_words[2] = buf[(*offset)++];
    raw_words[3] = buf[(*offset)++];
    memcpy(&val, raw_words, sizeof(raw_words));
    return val;
}
#endif

void c2837x_block_unpack_input_payload(const uint16_t* payload_words,
                                       uint32_t* step_index)
{
    const uint16_t* buf = payload_words;
    uint32_t offset = 0;

    *step_index = read_uint32(buf, &offset);

    c2837x_block_input.a = read_int16(buf, &offset);
    c2837x_block_input.b = read_int16(buf, &offset);
    c2837x_block_input.c = read_int16(buf, &offset);
}

void c2837x_block_pack_output_payload(uint16_t* payload_words,
                                      uint32_t step_index)
{
    uint16_t* buf = payload_words;
    uint32_t offset = 0;

    write_uint32(buf, &offset, step_index);

    write_int16(buf, &offset, c2837x_block_output.sum);
}
```

> 注：`double64` 只有在 C2000 EABI 且确认 `(sizeof(double) * CHAR_BIT) == 64` 时允许生成。正式生成代码不得通过 `uint16_t*` 直接强制访问 `double` 对象；若无法用测试向量确认 `memcpy` 后的 word 顺序与协议 little-endian word 顺序一致，App 应禁用 double。

### 6.7 Simulink 端配置头文件示例

```c
#ifndef C2837X_BLOCK_CONFIG_H
#define C2837X_BLOCK_CONFIG_H

#include <stdint.h>

#define C2837X_BLOCK_PROTOCOL_VERSION  0x0001u
#define C2837X_BLOCK_CONFIG_HASH       0xXXXXXXXXu
#define C2837X_BLOCK_SAMPLE_TIME_SEC   1.0e-4

#define C2837X_BLOCK_IP_ADDR           "192.168.1.15"
#define C2837X_BLOCK_TCP_PORT          5000u

#define C2837X_BLOCK_MAX_PAYLOAD_SIZE_BYTES       1024u
#define C2837X_BLOCK_MAX_FRAME_SIZE_BYTES         (4u + C2837X_BLOCK_MAX_PAYLOAD_SIZE_BYTES)

#define C2837X_BLOCK_PC_CONNECT_TIMEOUT_MS        5000u
#define C2837X_BLOCK_PC_STEP_TIMEOUT_MS           1000u
#define C2837X_BLOCK_PC_TERMINATE_TIMEOUT_MS      1000u

#define C2837X_BLOCK_INPUT_COUNT       3u
#define C2837X_BLOCK_OUTPUT_COUNT      1u

#define C2837X_BLOCK_INPUT_DATA_SIZE_BYTES      6u
#define C2837X_BLOCK_OUTPUT_DATA_SIZE_BYTES     2u
#define C2837X_BLOCK_INPUT_PAYLOAD_SIZE_BYTES   (4u + C2837X_BLOCK_INPUT_DATA_SIZE_BYTES)
#define C2837X_BLOCK_OUTPUT_PAYLOAD_SIZE_BYTES  (4u + C2837X_BLOCK_OUTPUT_DATA_SIZE_BYTES)

typedef struct {
    int16_t a;
    int16_t b;
    int16_t c;
} C2837xBlock_InputData;

typedef struct {
    int16_t sum;
} C2837xBlock_OutputData;

void c2837x_block_pack_input_payload(uint8_t* payload,
                                      uint32_t step_index,
                                      const C2837xBlock_InputData* src);
void c2837x_block_unpack_output_payload(const uint8_t* payload,
                                        uint32_t* step_index,
                                        C2837xBlock_OutputData* dst);

#endif /* C2837X_BLOCK_CONFIG_H */
```

### 6.8 Simulink 端配置源文件示例

```c
#include "c2837x_block_config.h"
#include <string.h>

static inline void write_uint16(uint8_t* buf, uint32_t* offset, uint16_t val)
{
    buf[*offset]     = (uint8_t)(val & 0xFFu);
    buf[*offset + 1] = (uint8_t)((val >> 8) & 0xFFu);
    *offset += 2u;
}

static inline uint16_t read_uint16(const uint8_t* buf, uint32_t* offset)
{
    uint16_t val = (uint16_t)((uint16_t)buf[*offset] |
                              ((uint16_t)buf[*offset + 1] << 8));
    *offset += 2u;
    return val;
}

static inline void write_int16(uint8_t* buf, uint32_t* offset, int16_t val)
{
    write_uint16(buf, offset, (uint16_t)val);
}

static inline int16_t read_int16(const uint8_t* buf, uint32_t* offset)
{
    return (int16_t)read_uint16(buf, offset);
}

static inline void write_uint32(uint8_t* buf, uint32_t* offset, uint32_t val)
{
    buf[*offset]     = (uint8_t)(val & 0xFFu);
    buf[*offset + 1] = (uint8_t)((val >> 8) & 0xFFu);
    buf[*offset + 2] = (uint8_t)((val >> 16) & 0xFFu);
    buf[*offset + 3] = (uint8_t)((val >> 24) & 0xFFu);
    *offset += 4u;
}

static inline uint32_t read_uint32(const uint8_t* buf, uint32_t* offset)
{
    uint32_t val = ((uint32_t)buf[*offset]) |
                   ((uint32_t)buf[*offset + 1] << 8) |
                   ((uint32_t)buf[*offset + 2] << 16) |
                   ((uint32_t)buf[*offset + 3] << 24);
    *offset += 4u;
    return val;
}

void c2837x_block_pack_input_payload(uint8_t* payload,
                                      uint32_t step_index,
                                      const C2837xBlock_InputData* src)
{
    uint32_t offset = 0;

    write_uint32(payload, &offset, step_index);
    write_int16(payload, &offset, src->a);
    write_int16(payload, &offset, src->b);
    write_int16(payload, &offset, src->c);
}

void c2837x_block_unpack_output_payload(const uint8_t* payload,
                                        uint32_t* step_index,
                                        C2837xBlock_OutputData* dst)
{
    uint32_t offset = 0;

    *step_index = read_uint32(payload, &offset);
    dst->sum = read_int16(payload, &offset);
}
```

### 6.9 C S-Function 工程模板

除 §6.7 和 §6.8 的 PC 端配置文件外，阶段三还需要 C S-Function 工程模板。App 可以直接生成完整 `c2837x_block_sfun.c`，也可以生成配置文件并复用固定模板。

#### 6.9.1 `c2837x_block_sfun.c` 生成策略

推荐策略：

- 固定模板负责 S-Function 生命周期、socket、协议收发和错误处理。
- App 生成以下配置相关代码片段：
  - 端口数量、宽度、数据类型设置。
  - 从输入端口拷贝到 `C2837xBlock_InputData`。
  - 从 `C2837xBlock_OutputData` 拷贝到输出端口。
  - `config_hash`、payload size 和 sample time 宏。

生成器应避免把 socket 和协议代码重复生成到每个工程中；这些代码应作为稳定模板维护。



#### 6.9.2 C S-Function 标准入口骨架

`c2837x_block_sfun.c` 必须使用 Level-2 C MEX S-Function 入口结构：

```c
#define S_FUNCTION_NAME  c2837x_block_sfun
#define S_FUNCTION_LEVEL 2

#include <stdint.h>
#include "simstruc.h"
#include "c2837x_block_config.h"

#ifdef MATLAB_MEX_FILE
#include "simulink.c"
#else
#include "cg_sfun.h"
#endif
```

V2.3 不生成 TLC 文件，不支持 Simulink Coder 代码生成。因此工程模板应主要面向 MEX Normal 模式仿真。

#### 6.9.3 端口读写代码生成示例

以 3 个 `int16` 输入和 1 个 `int16` 输出为例，App 生成输入读取代码：

```c
static void c2837x_sfun_read_inputs(SimStruct* S,
                                    C2837xBlock_InputData* dst)
{
    const int16_T* u0 = (const int16_T*)ssGetInputPortSignal(S, 0);
    const int16_T* u1 = (const int16_T*)ssGetInputPortSignal(S, 1);
    const int16_T* u2 = (const int16_T*)ssGetInputPortSignal(S, 2);

    dst->a = (int16_t)u0[0];
    dst->b = (int16_t)u1[0];
    dst->c = (int16_t)u2[0];
}
```

输出写回代码：

```c
static void c2837x_sfun_write_outputs(SimStruct* S,
                                      const C2837xBlock_OutputData* src)
{
    int16_T* y0 = (int16_T*)ssGetOutputPortSignal(S, 0);
    y0[0] = (int16_T)src->sum;
}
```

对于一维数组变量，生成器应使用循环逐元素拷贝：

```c
for (int i = 0; i < N; ++i) {
    dst->arr[i] = (int16_t)u[k][i];
}
```

#### 6.9.4 C S-Function 编译脚本

App 应生成或提供以下脚本：

```matlab
% build_c2837x_block_sfun.m
mex('-R2018a', ...
    'c2837x_block_sfun.c', ...
    'c2837x_block_config.c', ...
    'c2837x_block_protocol.c', ...
    'c2837x_block_pc_socket.c', ...
    'ws2_32.lib');   % Windows only
```

非 Windows 平台不链接 `ws2_32.lib`。生成脚本必须根据 `ispc` 自动选择链接参数。

#### 6.9.5 C S-Function 使用限制

V2.3 中，C S-Function 有以下限制：

- 仅支持 Normal 模式仿真。
- 仅支持单实例。
- 不支持 Simulink Coder 代码生成。
- 不支持 Accelerator/Rapid Accelerator。
- 不支持多线程异步通信。
- 不支持在同一仿真步内重入调用。

如果用户违反单实例、执行模式或重入限制，S-Function 应在启动阶段或首次运行时报错，而不是静默运行。S-Function 不要求检查模型求解器类型。

#### 6.9.6 C S-Function Mask 建议

建议提供 Simulink Mask，显示以下只读信息：

- DSP IP 地址。
- TCP 端口号。
- 协议版本。
- `config_hash`。
- 输入变量列表。
- 输出变量列表。
- sample time。

V2.3 中这些参数由 App 生成文件固定，不建议用户在 Mask 中手工编辑，避免与 `config_hash` 不一致。

### 6.10 MATLAB App 功能

MATLAB App 提供图形界面，允许用户：

1. 配置输入输出变量。
2. 设置变量名称、数据类型和一维维度。
3. 自动计算 `*_SIZE_BYTES` 与 DSP 端 `*_SIZE_WORDS`。
4. 配置目标 ABI：EABI/COFF。
5. 根据 ABI 控制是否允许 `double`。
6. 生成 `C2837X_BLOCK_SAMPLE_TIME_SEC`，并将 `sample_time_sec` 纳入 `config_hash`。
7. 检查 payload 大小上限：`INPUT_PAYLOAD_SIZE_BYTES <= C2837X_BLOCK_MAX_PAYLOAD_SIZE_BYTES`、`OUTPUT_PAYLOAD_SIZE_BYTES <= C2837X_BLOCK_MAX_PAYLOAD_SIZE_BYTES`、`C2837X_BLOCK_MAX_PAYLOAD_SIZE_BYTES` 为偶数且不超过 65535。
8. 检查 `INPUT_PAYLOAD_SIZE_BYTES` 和 `OUTPUT_PAYLOAD_SIZE_BYTES` 均为偶数。
9. 根据 W5300 Socket TX/RX buffer 分配检查单帧长度是否小于实际可用缓冲区。
10. 配置网络参数，并将 App 生成的网络参数纳入 `config_hash`。
11. 生成 DSP 端和 Simulink 端配置文件。
12. 生成 `config_hash`。
13. 显示规范化 hash 字符串预览。
14. 保存/加载 `.mat` 配置。
15. 可选执行 Ping 测试。
16. 生成协议报告，包括变量偏移、类型、维度、线上字节数和 DSP word 数。
17. 拒绝非法、重复、保留或与生成代码内部符号冲突的变量名。

### 6.11 偏移报告示例

对于 3×`int16` 输入和 1×`int16` 输出：

```text
INPUT_DATA payload:
step_index : offset_bytes=0, size_bytes=4, offset_words=0, size_words=2
input.a    : offset_bytes=4, size_bytes=2, offset_words=2, size_words=1
input.b    : offset_bytes=6, size_bytes=2, offset_words=3, size_words=1
input.c    : offset_bytes=8, size_bytes=2, offset_words=4, size_words=1

total input_payload_size_bytes = 10
total input_payload_size_words = 5

OUTPUT_DATA payload:
step_index : offset_bytes=0, size_bytes=4, offset_words=0, size_words=2
output.sum : offset_bytes=4, size_bytes=2, offset_words=2, size_words=1

total output_payload_size_bytes = 6
total output_payload_size_words = 3
```

---

## 7. 开发计划

### 阶段一：通信验证

1. 手动编写 DSP 端配置文件，支持 3×`int16` 输入和 1×`int16` 输出。
2. 实现 W5300 单 Socket TCP 连接。
3. 实现 `SIM_START`、`INPUT_DATA`、`OUTPUT_DATA`、`SIM_STOP`、`RESPONSE`。
4. 实现 TCP 组帧、`send_all()`、半帧超时和错误处理。
5. 实现 MATLAB S-Function。
6. 搭建使用显式离散采样时间的 Simulink 测试模型。
7. 验证 1000 步以上连续通信。

### 阶段二：配置工具

1. 开发 MATLAB App 配置界面。
2. 生成 DSP 端配置文件。
3. 生成 Simulink C S-Function 端配置文件。
4. 生成 `config_hash` 和协议报告。
5. 支持 `int16`、`uint16`、`int32`、`uint32`、`single`。
6. 按 ABI 策略支持或禁用 `double`。
7. 支持标量和一维数组。
8. 实现配置保存/加载。

### 阶段三：性能优化

1. 将 MATLAB S-Function 转换为 C S-Function。
2. 复用 PC 端 App 生成的 `uint8_t` 序列化代码。
3. 优化 socket 发送和接收缓冲策略。
4. 增加大 payload 粘包/拆包测试。
5. 编写用户文档和示例工程。

---

## 8. 阶段一示例文件

阶段一快速验证使用 3 个 `int16` 输入和 1 个 `int16` 输出。

### 8.1 c2837x_block_algorithm.h

```c
#ifndef C2837X_BLOCK_ALGORITHM_H
#define C2837X_BLOCK_ALGORITHM_H

#include <stdint.h>

typedef struct {
    int16_t a;
    int16_t b;
    int16_t c;
} C2837xBlock_InputData;

typedef struct {
    int16_t sum;
} C2837xBlock_OutputData;

extern C2837xBlock_InputData  c2837x_block_input;
extern C2837xBlock_OutputData c2837x_block_output;

int C2837xBlock_OnSimStart(void);
int C2837xBlock_OnStep(void);
void C2837xBlock_OnSimStop(void);

#endif /* C2837X_BLOCK_ALGORITHM_H */
```

### 8.2 c2837x_block_global_variable.c

```c
#include "c2837x_block_algorithm.h"

C2837xBlock_InputData  c2837x_block_input;
C2837xBlock_OutputData c2837x_block_output;
```

### 8.3 c2837x_block_config.h

```c
#ifndef C2837X_BLOCK_CONFIG_H
#define C2837X_BLOCK_CONFIG_H

#include <stdint.h>

#define C2837X_BLOCK_PROTOCOL_VERSION  0x0001u
#define C2837X_BLOCK_CONFIG_HASH       0xXXXXXXXXu
#define C2837X_BLOCK_SAMPLE_TIME_SEC   1.0e-4

#define C2837X_BLOCK_IP_ADDR           0xC0A80164u
#define C2837X_BLOCK_GATEWAY           0xC0A80101u
#define C2837X_BLOCK_SUBNET            0xFFFFFF00u
#define C2837X_BLOCK_TCP_PORT          5000u
#define C2837X_BLOCK_SOCKET_NUM        0u

#define C2837X_BLOCK_MAX_PAYLOAD_SIZE_BYTES       1024u
#define C2837X_BLOCK_MAX_FRAME_SIZE_BYTES         (4u + C2837X_BLOCK_MAX_PAYLOAD_SIZE_BYTES)

#define C2837X_BLOCK_INPUT_COUNT       3u
#define C2837X_BLOCK_OUTPUT_COUNT      1u

#define C2837X_BLOCK_INPUT_DATA_SIZE_BYTES      6u
#define C2837X_BLOCK_OUTPUT_DATA_SIZE_BYTES     2u
#define C2837X_BLOCK_INPUT_PAYLOAD_SIZE_BYTES   10u
#define C2837X_BLOCK_OUTPUT_PAYLOAD_SIZE_BYTES  6u

#define C2837X_BLOCK_INPUT_DATA_SIZE_WORDS      3u
#define C2837X_BLOCK_OUTPUT_DATA_SIZE_WORDS     1u
#define C2837X_BLOCK_INPUT_PAYLOAD_SIZE_WORDS   5u
#define C2837X_BLOCK_OUTPUT_PAYLOAD_SIZE_WORDS  3u

void c2837x_block_unpack_input_payload(const uint16_t* payload_words,
                                       uint32_t* step_index);
void c2837x_block_pack_output_payload(uint16_t* payload_words,
                                      uint32_t step_index);

#endif /* C2837X_BLOCK_CONFIG_H */
```

### 8.4 my_algorithm.c

```c
#include "c2837x_block_algorithm.h"

int C2837xBlock_OnSimStart(void)
{
    return 0;
}

int C2837xBlock_OnStep(void)
{
    int32_t tmp = (int32_t)c2837x_block_input.a
                + (int32_t)c2837x_block_input.b
                + (int32_t)c2837x_block_input.c;

    if (tmp > 32767) {
        tmp = 32767;
    } else if (tmp < -32768) {
        tmp = -32768;
    }

    c2837x_block_output.sum = (int16_t)tmp;
    return 0;
}

void C2837xBlock_OnSimStop(void)
{
}
```

> 示例算法中加入饱和处理，避免 3 个 `int16` 相加时发生溢出后直接截断，便于测试结果解释。

---

## 9. 验收标准

### 9.1 阶段一验收

- [ ] MATLAB S-Function 能与 DSP 建立 TCP 连接。
- [ ] `SIM_START` 协议版本匹配时返回 `RESPONSE(0)`。
- [ ] `SIM_START` 协议版本不匹配时返回 `RESPONSE(6)`。
- [ ] `config_hash` 匹配时允许进入仿真。
- [ ] `config_hash` 不匹配时返回 `RESPONSE(3)`。
- [ ] 3×`int16` 输入数据正确传输到 DSP。
- [ ] DSP 返回的 1×`int16` 输出与 Simulink 端预期一致。
- [ ] `INPUT_DATA` payload 中的 `step_index` 能在 `OUTPUT_DATA` 中原样返回。
- [ ] 连续运行 1000 步以上无通信错误。
- [ ] 仿真结束后 DSP 重新进入 `LISTEN` 状态。

### 9.2 协议异常验收

- [ ] 未知报文类型返回 `RESPONSE(1)`。
- [ ] `INPUT_DATA length` 为奇数时返回 `RESPONSE(2)`。
- [ ] `INPUT_DATA length` 小于预期值时返回 `RESPONSE(2)`。
- [ ] `INPUT_DATA length` 大于预期值时返回 `RESPONSE(2)`。
- [ ] `CONNECTED` 状态下收到 `INPUT_DATA` 返回 `RESPONSE(4)`。
- [ ] `SIM_RUNNING` 状态下再次收到 `SIM_START` 返回 `RESPONSE(4)`。
- [ ] `INPUT_DATA.step_index` 不等于 DSP `expected_step_index` 时返回 `RESPONSE(7)`。
- [ ] `C2837xBlock_OnSimStart()` 返回非 0 时返回 `RESPONSE(5)` 并回到 `LISTEN`。
- [ ] `C2837xBlock_OnStep()` 返回非 0 时返回 `RESPONSE(5)`，且不得发送 `OUTPUT_DATA`。
- [ ] Simulink 等待 `OUTPUT_DATA` 时收到 `RESPONSE(error_code>0)` 能终止仿真并显示错误。
- [ ] Simulink 等待 `OUTPUT_DATA` 时收到 `RESPONSE(0)` 或 `RESPONSE.length != 2` 能按协议错误终止仿真。
- [ ] `OUTPUT_DATA.step_index` 与当前步号不匹配时 Simulink 端能报错。

### 9.3 TCP 组帧验收

- [ ] 帧头拆成 2+2 字节到达时能正确组帧。
- [ ] payload 分多次到达时能正确组帧。
- [ ] 多个报文粘在一次 read 中到达时能逐帧解析。
- [ ] `send_all()` 能处理底层部分发送。
- [ ] 半帧超时后 DSP 能关闭连接并回到 `LISTEN`。

### 9.4 C2000 平台验收

- [ ] DSP 端 `C2837X_BLOCK_INPUT_DATA_SIZE_BYTES` 与 `C2837X_BLOCK_INPUT_DATA_SIZE_WORDS` 转换正确。
- [ ] DSP 端 word buffer 分配、offset 报告和 W5300 收发容量使用 `*_SIZE_WORDS`，协议 `length` 和 App 计算仍使用 `*_SIZE_BYTES`。
- [ ] DSP 端 payload 解析函数接收 `uint16_t*` word buffer，不通过 `void*` 掩盖对齐要求。
- [ ] 生成代码不依赖 `sizeof(C2837xBlock_InputData)` 或 `sizeof(C2837xBlock_OutputData)` 判断 payload 大小。
- [ ] `int16`、`uint16`、`int32`、`uint32`、`single` 在 PC 与 DSP 间序列化一致。
- [ ] 如启用 `double`，EABI 下 `(sizeof(double) * CHAR_BIT) == 64` 检查通过，`double64` 测试通过，且生成代码不得通过 `uint16_t*` 强制访问 `double` 对象。
- [ ] 如使用 COFF ABI，App 禁止选择 `double` 或给出明确错误提示。

### 9.5 MATLAB App 验收

- [ ] App 能生成 DSP 端全部文件。
- [ ] App 能生成 C S-Function 所需 PC 端配置文件。
- [ ] App 能显示变量偏移报告。
- [ ] App 能显示 CRC32 规范化字符串。
- [ ] MATLAB、PC C、DSP C 如都计算 CRC32，应得到一致结果。
- [ ] `sample_time_sec` 已纳入 CRC32 规范化字符串。
- [ ] App 生成的网络参数已纳入 CRC32 规范化字符串。
- [ ] App 检查 payload 大小不超过 `C2837X_BLOCK_MAX_PAYLOAD_SIZE_BYTES` 和协议 `uint16 length` 上限。
- [ ] App 检查 `C2837X_BLOCK_MAX_PAYLOAD_SIZE_BYTES`、`INPUT_PAYLOAD_SIZE_BYTES` 和 `OUTPUT_PAYLOAD_SIZE_BYTES` 均为偶数。
- [ ] 变量名非法时 App 能实时提示。
- [ ] 变量名为 C 关键字、保留标识符、重复名称或与生成代码内部符号冲突时 App 能实时提示。
- [ ] 二维及以上维度配置被禁止或要求用户显式展平。

### 9.6 阶段三验收

- [ ] C S-Function 能替代 MATLAB S-Function 正常工作。
- [ ] C S-Function 可通过 `build_c2837x_block_sfun.m` 一键编译生成 MEX 文件。
- [ ] `mdlStart` 能正确连接 DSP、发送 `SIM_START` 并处理 `RESPONSE(error_code=0)`。
- [ ] `mdlStart` 任意失败路径均能关闭已打开 socket、释放 ctx、恢复单实例计数。
- [ ] `ssSetInputPortRequiredContiguous()` 已为所有输入端口设置。
- [ ] `mdlOutputs` 每个 sample hit 正确发送 `INPUT_DATA(step_index)` 并等待 `OUTPUT_DATA`。
- [ ] Simulink 输入端口到 `C2837xBlock_InputData` 的拷贝顺序与配置一致。
- [ ] `C2837xBlock_OutputData` 到 Simulink 输出端口的写回顺序与配置一致。
- [ ] `PWork[0]` 正确保存和释放 C S-Function 上下文，无内存泄漏。
- [ ] `mdlTerminate` 在正常停止和异常停止时都能关闭 socket 并释放资源。
- [ ] 使用 App 生成的离散采样时间时，通信步数与 sample hit 一致。
- [ ] C S-Function 不检查模型求解器类型；求解器配置由用户模型负责。
- [ ] 单模型中放置多个 C2837xBlock 实例时明确报错或禁止使用。
- [ ] 等待 `OUTPUT_DATA` 时收到 `RESPONSE(error_code>0)` 能终止仿真并显示可读错误。
- [ ] `step_index` 不匹配时 C S-Function 能终止仿真并报告错误。
- [ ] `step_index` 达到 `UINT32_MAX` 并成功完成该步后，下一步回绕为 0，PC 与 DSP 端继续保持步号匹配。
- [ ] DSP 断电、网线断开、socket reset 时 C S-Function 能超时退出，不会卡死 MATLAB。
- [ ] 大 payload 下 TCP 粘包/拆包测试通过。
- [ ] MATLAB 仿真异常停止后 DSP 能自动回到 `LISTEN`。

### 9.7 W5300 字节序和原始字节验收

- [ ] PC 发送固定 payload `01 02 03 04 05 06`，DSP 端能够还原相同线上字节顺序。
- [ ] W5300 驱动文档明确 16-bit FIFO/host bus 读取时的 byte-to-word 映射关系。
- [ ] 协议层 read/write 函数基于该映射通过 `int16`、`int32`、`single` 原始字节测试。

### 9.8 PC 端 Mock DSP 验收

阶段三建议提供 PC 端 Mock DSP 工具：

```text
tools/
└── c2837x_block_mock_dsp.py
```

Mock DSP 至少支持：

- 接收 `SIM_START` 并校验 `protocol_version` 与 `config_hash`。
- 接收 `INPUT_DATA(step_index)` 并返回 `OUTPUT_DATA(step_index)`。
- 注入错误：长度错误、`step_index` 错误、超时、半帧、粘包、`RESPONSE(error_code)`。

验收项：

- [ ] C S-Function 可在无 DSP 硬件时连接 Mock DSP 并完成 1000 步通信。
- [ ] Mock DSP 可复现 timeout、socket reset、粘包、拆包异常。
- [ ] MATLAB S-Function 和 C S-Function 均能通过 Mock DSP 基础协议测试。

### 9.9 协议测试向量验收

建议新增 `Protocol_Test_Vectors.md`，提供字节级测试向量。示例：

```text
SIM_START:
type = 0x0001
length = 0x0006
protocol_version = 0x0001
config_hash = 0x12345678

wire bytes:
01 00 06 00 01 00 78 56 34 12
```

验收项：

- [ ] PC 端 `send_frame()` 生成的字节流与测试向量一致。
- [ ] DSP 端组帧和解包结果与测试向量一致。
- [ ] W5300 FIFO 字节顺序测试覆盖上述向量。


---

## 10. 后续扩展项

以下内容不属于 V2.3 实现范围，但可作为后续版本规划。V2.3 默认不主动复位 DSP；watchdog 配置和复位策略由用户工程负责，通信库只要求用户算法不得阻塞。

1. `DEBUG_MSG` 用户调试输出报文。
2. `DETAILED_ERROR` 带字符串的详细错误报文。
3. 帧级 CRC16/CRC32。
4. 二维矩阵和 Bus 信号支持。
5. 多实例 `block_id`。
6. DSP 内部变量日志上传。
7. Simulink 与 DSP 时间同步字段 `sim_time_ns`。
8. watchdog 集成和异常复位恢复策略。
9. 多 Socket 或多客户端调试通道。
