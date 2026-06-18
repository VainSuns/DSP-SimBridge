# C2837xBlock 实施计划

本文档依据 `spec_v2_3.md` 制定，目标是实现 C2837xBlock DSP 在环仿真通信模块，并将现有 W5300 驱动从 PIL 风格调整为本项目协议所需的非阻塞 TCP 字节流驱动。

## 1. 实施原则

1. 先完成可通信的最小闭环，再推进 MATLAB App 和 C S-Function。
2. 现有 W5300 驱动可以按本项目需求修改，不要求保留 PIL 包长、ALIGN 或函数命名。
3. 项目自有代码统一采用 `spec_v2_3.md` 命名风格。
4. DSP 端协议 `length` 永远表示 TCP 线上 8-bit wire byte 数。
5. DSP 端 payload 缓冲区使用 `uint16_t` / TI `uint16` word buffer。
6. 所有 TCP 收发必须处理粘包、拆包、部分发送和超时。
7. `C2837xBlock_Run()` 必须是非阻塞状态机，不得在等待连接、等待数据或等待 TX buffer 时长期自旋。
8. W5300 寄存器宏可保留接近数据手册的命名，项目对外 API 统一使用 `c2837x_*` 风格。

## 2. 命名风格规范

### 2.1 文件命名

项目自有文件使用小写 snake_case。

| 当前文件 | 目标文件 | 说明 |
|---|---|---|
| `inc/W5300_define.h` | `inc/c2837x_w5300_regs.h` | W5300 寄存器和位定义 |
| `inc/W5300_C2837x.h` | `inc/c2837x_w5300_hal.h` | W5300 C2837x 硬件访问层 |
| `src/W5300_C2837x.c` | `src/c2837x_w5300_hal.c` | W5300 C2837x 硬件访问实现 |
| `inc/W5300_Socket.h` | `inc/c2837x_w5300_socket.h` | W5300 socket 封装 |
| `src/W5300_Socket.c` | `src/c2837x_w5300_socket.c` | W5300 socket 封装实现 |

新增文件：

| 文件 | 说明 |
|---|---|
| `inc/c2837x_block.h` | DSP 通信库核心 API |
| `src/c2837x_block.c` | DSP 非阻塞状态机和协议调度 |
| `inc/c2837x_block_protocol.h` | 协议类型、错误码、帧 helper 声明 |
| `src/c2837x_block_protocol.c` | 协议组帧、解包、编码、解码 |
| `inc/c2837x_block_algorithm.h` | App 生成，用户算法接口 |
| `inc/c2837x_block_config.h` | App 生成，DSP 配置头 |
| `src/c2837x_block_config.c` | App 生成，DSP payload 序列化 |
| `src/c2837x_block_global_variable.c` | App 生成，输入输出全局变量 |

### 2.2 函数、类型和宏命名

| 类别 | 规则 | 示例 |
|---|---|---|
| DSP 公共 API | `C2837xBlock_*` | `C2837xBlock_Init` |
| 用户回调 | `C2837xBlock_*` | `C2837xBlock_OnStep` |
| 内部函数 | `c2837x_block_*` | `c2837x_block_recv_frame` |
| W5300 封装函数 | `c2837x_w5300_*` | `c2837x_w5300_socket_send` |
| 类型 | `C2837xBlock_*` / `C2837xW5300_*` | `C2837xBlock_State` |
| 项目宏 | `C2837X_BLOCK_*` / `C2837X_W5300_*` | `C2837X_BLOCK_PROTOCOL_VERSION` |
| 局部变量 | 小写 snake_case | `expected_step_index` |
| W5300 寄存器宏 | 可保留手册风格 | `Sn_MR`、`Sn_CR_OPEN` |

## 3. 阶段 0：基线整理

目标：在改逻辑前先建立清晰的边界。

任务：

1. 记录当前文件和函数清单。
2. 建立旧名称到新名称的映射表。
3. 明确哪些符号属于项目 API，哪些属于 W5300 寄存器/硬件定义。
4. 确认 DSP 端类型策略：
   - DSP 公共头包含 `F28x_Project.h`。
   - DSP 端用户数据结构可使用 TI 类型，如 `int16`、`uint16`。
   - PC/MEX 端配置代码使用 `stdint.h` 和 Simulink C API 类型。
5. 确认阶段一最小配置：
   - 输入：`a`、`b`、`c`，均为 `int16`。
   - 输出：`sum`，`int16`。
   - `INPUT_PAYLOAD_SIZE_BYTES = 10`。
   - `OUTPUT_PAYLOAD_SIZE_BYTES = 6`。

交付物：

- 命名映射表。
- 新文件布局。
- 阶段一固定配置。

验收：

- 全项目不再新增大驼峰 W5300 API。
- 新增项目文件均采用小写 snake_case。

## 4. 阶段 1：W5300 驱动重构

目标：把现有 PIL 风格驱动改成本项目所需的非阻塞 TCP 字节流驱动。

### 4.1 文件和 API 重命名

任务：

1. 重命名 W5300 文件。
2. 更新所有 `#include`。
3. 将旧 API 改为新 API。

建议 API：

```c
int16 c2837x_w5300_init(void);
void  c2837x_w5300_reset(void);

uint16 c2837x_w5300_read16(uint32 addr);
void   c2837x_w5300_write16(uint32 addr, uint16 data);

int16 c2837x_w5300_socket_open(C2837xW5300Socket* socket,
                               uint16 socket_num,
                               uint16 protocol,
                               uint16 port,
                               uint16 flags);
int16 c2837x_w5300_socket_listen(C2837xW5300Socket* socket);
int16 c2837x_w5300_socket_close(C2837xW5300Socket* socket);
int32 c2837x_w5300_socket_send(C2837xW5300Socket* socket,
                               const uint16* data_words,
                               uint32 wire_byte_count);
int32 c2837x_w5300_socket_recv(C2837xW5300Socket* socket,
                               uint16* data_words,
                               uint32 wire_capacity_bytes);
uint16 c2837x_w5300_socket_get_status(const C2837xW5300Socket* socket);
uint32 c2837x_w5300_socket_get_tx_free(const C2837xW5300Socket* socket);
uint32 c2837x_w5300_socket_get_rx_size(const C2837xW5300Socket* socket);
```

验收：

- 不再对上层暴露 `OpenSocket`、`CloseSocket`、`ListenSocket`、`SendStream`、`RecvStream`。
- W5300 封装层所有项目函数统一为 `c2837x_w5300_*`。

### 4.2 移除 PIL 包长语义

当前 `RecvStream()` 在非 `Sn_MR_ALIGN` 模式下会读取一个 `pack_size`，这属于 PIL/旧驱动语义，不符合 V2.3 TCP 字节流协议。

任务：

1. 修改 RX 逻辑为纯 TCP stream：
   - RX FIFO 有多少 wire bytes 就读多少，受调用方容量限制。
   - 不读取额外 `pack_size`。
   - 不假设一次读取就是完整协议帧。
2. 保留非阻塞返回：
   - 无数据返回 0。
   - socket 错误返回负值。
   - 读到部分数据返回实际 wire bytes。
3. 明确 `Sn_MR_ALIGN` 的使用策略：
   - 若本项目固定启用 ALIGN，则删除非 ALIGN 的 PIL 分支。
   - 若保留兼容，则非 ALIGN 分支也不得引入包长前缀。

验收：

- PC 发送任意拆分的协议帧，DSP 驱动只返回原始 TCP wire bytes。
- `Recv` 不再消费协议外的包长字段。

### 4.3 W5300 字节序自检

任务：

1. 增加固定测试向量：
   - PC payload：`01 02 03 04 05 06`
   - DSP 还原结果必须为同一顺序。
2. 文档化 word 映射：
   - 明确 `word[0]` 对应 `0x0201` 还是 `0x0102`。
   - 协议层据此统一 read/write。
3. 保留 `g_w5300_fifo_swap` 或改为 `c2837x_w5300_fifo_swap`，并明确它只属于 HAL 层。

验收：

- W5300 FIFO 字节序测试通过。
- `int16`、`int32`、`single` 原始字节测试通过。

### 4.4 非阻塞关闭和发送

任务：

1. 清理 `CloseSocket()` 中长时间等待 TX free size 的逻辑。
2. `socket_send()` 只发送 W5300 当前可接受的部分。
3. 由上层 DSP 协议状态机保存 `tx_sent_bytes` 和 `tx_total_bytes`。
4. UDP `SendToSocket()` 不属于主链路，可移动到调试/兼容区或暂不暴露。

验收：

- W5300 TX buffer 满时 `C2837xBlock_Run()` 不会卡死。
- 连接异常时可以有限时间内关闭并回到 `LISTEN`。

## 5. 阶段 2：DSP 通信库

目标：实现 `C2837xBlock_Init()` 和 `C2837xBlock_Run()`。

### 5.1 上下文设计

建议结构：

```c
typedef struct {
    C2837xBlock_State state;
    C2837xW5300Socket socket;

    uint16 rx_payload_words[C2837X_BLOCK_MAX_PAYLOAD_SIZE_WORDS];
    uint16 tx_frame_words[(C2837X_BLOCK_MAX_FRAME_SIZE_BYTES + 1u) / 2u];

    uint16 rx_header_words[2];
    uint16 rx_type;
    uint16 rx_length_bytes;
    uint32 rx_received_bytes;

    uint32 tx_total_bytes;
    uint32 tx_sent_bytes;

    uint32 expected_step_index;
    uint32 state_start_tick;
    uint32 frame_start_tick;

    uint16 last_error;
} C2837xBlock_Context;
```

任务：

1. 初始化 context。
2. 初始化 W5300。
3. 配置网络参数。
4. 打开 Socket 0。
5. 进入 `LISTEN`。

验收：

- `C2837xBlock_Init()` 成功返回 0。
- W5300 初始化失败、socket open 失败时返回非 0。

### 5.2 RX 组帧状态机

任务：

1. 先接收 4 wire bytes 帧头。
2. 解析 little-endian `type` 和 `length`。
3. 校验：
   - type 是否已知。
   - length 是否超过最大 payload。
   - length 是否为偶数。
   - length 是否匹配报文类型预期。
4. 分多次接收 payload。
5. 半帧超时后关闭 socket 并回到 `LISTEN`。

验收：

- 帧头 2+2 到达可正确组帧。
- payload 分多次到达可正确组帧。
- 多帧粘连可逐帧解析。
- 奇数 length 返回 `RESPONSE(2)`。

### 5.3 TX 分段状态机

任务：

1. 构造完整帧：
   - header 4 wire bytes。
   - payload even wire bytes。
2. 保存发送进度。
3. 每次 `C2837xBlock_Run()` 发送当前可发送部分。
4. 全部发送完成后再推进协议状态。
5. TX 超时后进入 `DISCONNECTED`。

验收：

- W5300 TX buffer 不足时可分多次发送。
- `OUTPUT_DATA` 和 `RESPONSE` 都可走同一发送状态机。

### 5.4 报文处理

任务：

1. `CONNECTED` 状态只接受 `SIM_START`。
2. `SIM_START`：
   - 校验 `length == 6`。
   - 校验 `protocol_version`。
   - 校验 `config_hash`。
   - 调用 `C2837xBlock_OnSimStart()`。
   - 成功返回 `RESPONSE(0)`。
   - 失败返回 `RESPONSE(5)`。
3. `SIM_RUNNING` 状态接受 `INPUT_DATA` 和 `SIM_STOP`。
4. `INPUT_DATA`：
   - 校验 length。
   - 校验 `step_index == expected_step_index`。
   - 解包 input。
   - 调用 `C2837xBlock_OnStep()`。
   - 成功返回 `OUTPUT_DATA(step_index)`。
   - 失败返回 `RESPONSE(5)`。
5. `SIM_STOP`：
   - 调用 `C2837xBlock_OnSimStop()`。
   - 关闭连接。
   - 回到 `LISTEN`。
6. 非法报文返回对应 `RESPONSE(error_code)`。

验收：

- 协议异常验收项全部通过。
- MATLAB 异常退出后 DSP 能回到 `LISTEN`。

## 6. 阶段 3：手工配置和最小算法

目标：不依赖 App，先完成固定 3 输入 1 输出闭环。

任务：

1. 编写 `c2837x_block_algorithm.h`。
2. 编写 `c2837x_block_global_variable.c`。
3. 编写 `c2837x_block_config.h`。
4. 编写 `c2837x_block_config.c`。
5. 编写 `my_algorithm.c`：
   - `C2837xBlock_OnSimStart()` 返回 0。
   - `C2837xBlock_OnStep()` 执行三数相加和饱和。
   - `C2837xBlock_OnSimStop()` 空实现。

验收：

- DSP 端可编译。
- payload offset 报告与 `spec_v2_3.md` 一致。
- 3 个 `int16` 输入和 1 个 `int16` 输出序列化正确。

## 7. 阶段 4：MATLAB S-Function 验证

目标：用 MATLAB Level-2 S-Function 完成阶段一通信验证。

任务：

1. 建立 TCP 连接。
2. 发送 `SIM_START(protocol_version, config_hash)`。
3. 等待 `RESPONSE(0)`。
4. 每个 sample hit：
   - 读取输入。
   - 打包 `INPUT_DATA(step_index)`。
   - 等待 `OUTPUT_DATA` 或 `RESPONSE(error)`。
   - 校验 `step_index`。
   - 写输出。
5. 仿真结束发送 `SIM_STOP`。

验收：

- 正常 1000 步通信无错误。
- 错 protocol version 返回 `RESPONSE(6)`。
- 错 config hash 返回 `RESPONSE(3)`。
- 错 length 返回 `RESPONSE(2)`。
- 错 step_index 返回 `RESPONSE(7)`。
- DSP 断开时 MATLAB 不会永久卡死。

## 8. 阶段 5：协议测试工具

目标：在无 DSP 硬件时验证 PC 侧协议实现。

任务：

1. 新增 `Protocol_Test_Vectors.md`。
2. 新增 `tools/c2837x_block_mock_dsp.py`。
3. Mock DSP 支持：
   - 正常 `SIM_START`。
   - 正常 `INPUT_DATA` 到 `OUTPUT_DATA`。
   - 粘包。
   - 拆包。
   - 半帧超时。
   - 错 length。
   - 错 step_index。
   - socket reset。
   - `RESPONSE(error_code)` 注入。

验收：

- MATLAB S-Function 能连接 Mock DSP 并完成 1000 步。
- Mock DSP 可稳定复现异常用例。
- PC 端字节流与 `Protocol_Test_Vectors.md` 一致。

## 9. 阶段 6：MATLAB App / 代码生成器

目标：由 App 生成 DSP 端和 Simulink 端配置文件。

任务：

1. App 配置输入输出变量。
2. App 配置网络参数。
3. App 配置 sample time。
4. App 配置目标 ABI 和 double 策略。
5. App 检查变量名：
   - 合法 C 标识符。
   - 非 C 关键字。
   - 非保留标识符。
   - 不重复。
   - 不与生成代码内部符号冲突。
6. App 计算：
   - `*_SIZE_BYTES`。
   - `*_SIZE_WORDS`。
   - payload size。
   - offset 报告。
7. App 检查：
   - payload size 不超过最大值。
   - payload size 为偶数。
   - `C2837X_BLOCK_MAX_PAYLOAD_SIZE_BYTES <= 65535`。
8. App 生成 CRC32 规范化字符串。
9. App 生成 `config_hash`。
10. App 生成 DSP 端文件。
11. App 生成 PC/C S-Function 端配置文件。

验收：

- App 输出的 CRC32 字符串可显示。
- 网络参数和 `sample_time_sec` 已纳入 hash。
- DSP 和 PC 配置文件中的 hash 一致。
- offset 报告与生成代码一致。

## 10. 阶段 7：C S-Function

目标：替代 MATLAB S-Function，提高通信稳定性和性能。

任务：

1. 实现 `c2837x_block_sfun.c`。
2. 实现 `c2837x_block_pc_socket.c`。
3. 实现 `c2837x_block_protocol.c`。
4. 实现 `build_c2837x_block_sfun.m`。
5. 在 `mdlStart` 中：
   - 检查单实例。
   - 分配 ctx。
   - 连接 DSP。
   - 发送 `SIM_START`。
   - 等待 `RESPONSE(0)`。
6. 在 `mdlOutputs` 中：
   - 读取输入端口。
   - 发送 `INPUT_DATA(step_index)`。
   - 等待 `OUTPUT_DATA` 或 `RESPONSE(error)`。
   - 校验 length 和 step_index。
   - 写输出端口。
7. 在 `mdlTerminate` 中：
   - 尽力发送 `SIM_STOP`。
   - 关闭 socket。
   - 释放 ctx。
   - 恢复单实例计数。

验收：

- MEX 一键编译成功。
- Normal mode fixed-step discrete 正常运行。
- variable-step solver 明确报错。
- 多实例明确报错。
- 任意启动失败路径都能释放资源。
- 等待 `OUTPUT_DATA` 时收到 `RESPONSE(0)` 按协议错误处理。
- `step_index` mismatch 能终止仿真。
- `UINT32_MAX` 溢出能终止仿真。

## 11. 阶段 8：最终验收

按以下顺序执行：

1. 命名风格扫描。
2. W5300 原始字节序验收。
3. DSP 端协议测试向量验收。
4. MATLAB S-Function 1000 步验收。
5. 协议异常验收。
6. Mock DSP 验收。
7. C S-Function 编译验收。
8. C S-Function 1000 步验收。
9. 大 payload 粘包/拆包验收。
10. DSP 断电、网线断开、socket reset 验收。

## 12. 推荐开工顺序

第一批只做以下内容：

1. 完成 W5300 文件和 API 重命名。
2. 移除 `RecvStream()` 中 PIL 包长语义。
3. 实现 W5300 raw TCP stream 收发。
4. 加入 W5300 字节序测试。
5. 实现 `c2837x_block.c` 的最小非阻塞状态机。
6. 用手写配置完成 `SIM_START`、`INPUT_DATA`、`OUTPUT_DATA`、`SIM_STOP` 闭环。

完成第一批后，再进入 MATLAB S-Function 和 App。这样风险最小，反馈最快。
