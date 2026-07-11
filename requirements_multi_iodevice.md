# C2837xBlock 多 IoDevice / 多算法联合仿真需求

> 状态：Frozen（研发精简版）
>
> 日期：2026-07-11
>
> 本文件只定义首版功能、最小接口和验收边界，不包含详细实施计划、具体设备驱动设计或工业产品化要求。

## 1. 目的与所有权

### REQ-SCOPE-001：研发联合仿真

本项目用于算法开发、调试和 Simulink-DSP 联合仿真。首要目标是快速实现一个 DSP 上的多个独立算法实例，使同一个 Simulink Normal mode 模型能够通过多个 S-Function 分别驱动这些实例。

本项目不是工业通信产品。发生异常时允许研发人员在 Core 外部处理或复位设备、重新初始化 Block 或重启 DSP 后重新运行，不要求无人值守、自动恢复、高可用、冗余、功能安全或确定性实时响应。

### REQ-SCOPE-002：首版范围

首版只要求完成并验收以下主链路：两个 W5300 Socket、两个用户 IoDevice、两个 Algorithm、两个静态 Block Instance 和两个独立 S-Function。

通用 Core 和 IoDevice 接口不得包含 W5300 特有假设。SCI、Windows COM 和其他设备的具体实现延后。DSP 侧 Algorithm typed I/O、Hash 和 adapter 不因 IoDevice 类型变化而变化；但 SCI/Windows COM 的 PC transport 仍可能需要新增实现或重新生成对应 PC wrapper，首版不承诺现有 TCP S-Function 可以直接连接 SCI。

### REQ-SCOPE-003：职责边界

AI/Codex 负责的范围仅包括：

- 上层 V1 协议 Core；
- 最小 IoDevice 接口；
- `C2837xBlock` 多实例状态机和必要公共函数；
- 通用 Algorithm 生命周期；
- App、多实例生成和 PC TCP/S-Function 联合仿真路径。

用户负责：

- 用户 Algorithm 实现和 context；
- 所有 IoDevice 实现和 context；
- W5300、SCI 或其他设备的初始化、配置、连接、错误处理和外部恢复；
- Socket、FIFO、内存表、EMIF、GPIO、时钟和中断等设备集成；
- Algorithm 与 IoDevice 的运行时注入关系；
- DSP 主循环和工程集成；
- DSP、IoDevice 和真实硬件测试。

Core、App 和生成器不得检查、生成、修改或复制用户设备初始化与底层操作。现有 W5300 HAL、Socket 驱动以及 `c2837x_w5300_socket_close()`、`c2837x_w5300_socket_send_to()` 不属于本次整改范围。

### REQ-SCOPE-004：快速实现优先

首版只实现多实例联合仿真主链路所必需的功能。没有实际研发问题证明需要之前，不增加复杂错误分类、自动恢复、设备健康管理、共享资源管理、制品事务系统或大规模测试矩阵。

### REQ-SCOPE-005：目录和文件所有权

项目文件按所有权分为以下三类；目录名表达职责，具体文件名和子目录可结合现有项目调整，不得只为匹配示意结构而无必要地搬迁或重命名现有文件。

```text
C2837xBlock/
├─ core/
│  └─ algorithm/   AI/Codex 负责的通用代码
├─ user/           用户负责的代码
└─ autogen/        现有 App 生成的实例差异代码
```

`core/algorithm/` 可以包含通用 Block 状态机、V1 解析和组帧、RX/TX 部分进度、Algorithm 生命周期、IoDevice 接口、`Init/Run`、通用协议支持，以及 PC TCP/S-Function 所需的可复用支持。它不得包含用户 Algorithm/context、具体设备驱动、Socket 或 SCI channel、硬件配置、用户主循环、Algorithm-IoDevice 固定映射或实例专用 typed I/O。

`user/` 完全由用户维护，AI/Codex、App 和生成器均不得覆盖。它包含用户 Algorithm/context、IoDevice/context、设备与板级配置、运行时注入、主循环、工程集成和 `end_session` 的具体实现。

`autogen/` 由现有 App 生成并允许重新生成时覆盖。它只包含每个 Algorithm Instance 的协议配置、typed input/output、序列化与反序列化、`config_hash`、sample time、typed adapter、S-Function wrapper 和 MEX 构建参数，不得包含用户 Algorithm、IoDevice/context、设备编号、硬件配置、W5300 缓存表或 Algorithm-IoDevice 映射。

## 2. C2837xBlock Core

### REQ-CORE-001：静态独立实例

每个 Algorithm 必须对应一个静态分配的 `C2837xBlock` 实例。实例必须独立保存协议状态、RX/TX 缓冲区和进度、生成配置引用、`expected_step_index`、Algorithm/IoDevice 注入引用、`algorithm_started` 及一个简单最后错误类别。

所有实例共享同一份 Core 代码，不得使用单个全局运行上下文、动态实例注册表、中央 Manager 或 `RunAll()`。

### REQ-CORE-002：必要公共函数和注入

支持层只提供等价于以下两个会修改或推进 Block 的公共操作；具体 C 签名可按现有命名风格确定：

- `C2837xBlock_Init(...)`：同时注入生成配置、Algorithm 操作表和 context、IoDevice 操作表和 context，并初始化上层协议状态；
- `C2837xBlock_Run(instance)`：有限、非阻塞地推进一次本实例状态机。

首版使用 `Init` 完成 IoDevice 运行时注入，不要求新增 `SetIoDevice()`，不引入“已 Init 但未注入设备”的中间状态，也不支持运行中动态切换 IoDevice。

`Init` 只允许在 `UNINITIALIZED` 或 `ERROR` 中调用；在 `WAIT_LINK/WAIT_START/RUNNING/ENDING` 中调用必须返回 `INVALID_STATE` 或等价错误，不得修改当前状态、注入引用或活动会话。首次和重新 `Init` 均不得调用 Algorithm 或 IoDevice 操作。

`Init` 必须具有原子语义：先完成全部参数、生成配置、Core RX/TX buffer capacity、Algorithm `process`、IoDevice `read/write` 及其他必需操作指针校验；所有校验成功前，不得修改 Block 的任何已有状态、错误记录或注入引用。

- 从 `UNINITIALIZED` 调用失败时保持 `UNINITIALIZED`；
- 从 `ERROR` 重新调用失败时保持原 `ERROR`、原生成配置、原 Algorithm/IoDevice 引用和原 `last_error`；
- 只有全部校验成功后，才能一次性清除 RX/TX、部分帧、`expected_step_index` 和会话状态，保存新的生成配置、Algorithm 和 IoDevice 引用，把 `last_error` 清除为 `NONE`，并进入 `WAIT_LINK`；
- `Init` 失败不得留下部分初始化状态。

生成配置指针和必需操作指针不得为空。`algorithm_ctx` 和 `iodevice_ctx` 可以为 `NULL`；Core 只保存并原样传递，是否接受空 context 由对应用户回调决定。Core 不得推断、检查或参与用户是否已经初始化、配置、关闭、清理、复位或重新配置设备，也不得调用操作表之外的用户函数。

### REQ-CORE-003：最小状态

Block 只需要以下外部状态：

- `UNINITIALIZED`：尚未成功调用 `Init`；
- `WAIT_LINK`：IoDevice 尚未报告可开始新的协议会话；
- `WAIT_START`：链路可用，等待完整 `SIM_START`；
- `RUNNING`：启动成功响应已完整发送，可以处理 `INPUT_DATA`；
- `ENDING`：会话已经决定结束，正在处理最终错误响应或 transport 收尾；
- `ERROR`：IoDevice 已无法继续通信，或最终错误响应/会话收尾阶段发生无法报告的 IoDevice 错误。

`Init` 成功后进入 `WAIT_LINK`。提供 `poll` 时，`poll=READY` 后进入 `WAIT_START`；未提供 `poll` 时，下一次 `Run` 按 `READY` 处理并进入 `WAIT_START`。合法 `SIM_START` 的 `on_start` 成功且启动成功响应被 IoDevice 完整接受后进入 `RUNNING`。合法 `SIM_STOP`、`LINK_DOWN` 或终止性协议错误进入 `ENDING`。`ENDING` 完成后进入 `WAIT_LINK`。

`ERROR` 是当前初始化周期的终止状态。`Run` 在该状态只返回 `ERROR`，不得调用任何 Algorithm 或 IoDevice 操作。用户完成 Core 外部的设备或工程处理后，只能重新调用 `Init` 或重启 DSP；Core 不提供 Reset API。

Core 不维护 W5300 shared、SCI 失步或任何具体设备寄存器状态。

### REQ-CORE-004：Run 状态机边界

`Run` 必须根据当前实例状态推进协议，并保存跨调用的部分 header、payload、RX/TX 和结束进度。每次调用的工作必须有限，最多执行：

- 一次可选 `poll`；
- 一次 `read`；
- 一次 `write`；
- `ENDING` 中一次可选 `end_session`；
- 处理一个完整消息；
- 调用一次 Algorithm `process`；
- 生成一个响应。

以上是单次调用上限，不要求每次按固定顺序执行全部操作。正常状态中 Core 应优先推进已有 TX，再按当前状态读取或处理一个消息；只有完整消息通过校验后才能发生协议转换或调用 Algorithm。

未提供 `poll` 时，Core 不调用它并始终按 `READY` 处理。提供 `poll` 时，`WAIT_LINK` 中 `poll=DOWN` 保持原状态；`WAIT_START` 中 `poll=DOWN` 且 `algorithm_started=false` 时清除未完成 RX/TX 并返回 `WAIT_LINK`；若 `algorithm_started=true`，必须先调用一次可选 `on_stop` 并清除该标志，再清除会话进度并进入 `ENDING`。`RUNNING` 中 `poll=DOWN` 同样按 `LINK_DOWN` 停止 Algorithm 并进入 `ENDING`。`WAIT_START` 中 `read/write=LINK_DOWN` 采用相同的 `algorithm_started` 规则。任一活动状态中 IoDevice 报告 `ERROR` 时，必须先停止已启动 Algorithm，再进入 `ERROR`。

`ENDING` 中必须先处理待发送的最终错误响应：本次最多调用一次 `write`，且同一次 `Run` 不得再调用 `end_session`。错误响应完整发送、`write=0` 或 `write=LINK_DOWN` 后放弃剩余 TX 并转入会话收尾阶段；`write=ERROR` 时进入 `ERROR`。只有不存在最终错误 TX 时才可调用一次可选 `end_session`。`end_session=DONE` 或未提供时，Core 清除 RX/TX、部分帧、`expected_step_index` 和会话状态后进入 `WAIT_LINK`。`ENDING` 中不得调用 `poll/read`。

没有 RX 数据、没有 TX 空间、链路未就绪或本次没有可推进工作时必须立即返回。Core 不得在一次 `Run` 内循环等待 IoDevice 状态改变；即使设备仍有更多数据，也必须返回并由用户主循环再次调用。

### REQ-CORE-005：Run 返回语义

`Run` 至少应让调用者区分：

- `IDLE`：本次没有可推进工作；
- `PROGRESSED`：本次收发、解析、Algorithm 调用或状态转换产生了进度；
- `ERROR`：实例已处于或进入 `ERROR`。

Core 只保留一个适合研发定位的 `last_error`，其生命周期为：

- 发生可报告的 protocol/Algorithm 错误时，在进入最终错误响应流程前更新 `last_error`；
- 即使错误会话随后完成 `ENDING → WAIT_LINK`，`last_error` 仍保留；
- 下一次合法 `SIM_START` 成功，且启动成功响应被 IoDevice 完整接受并进入 `RUNNING` 时，把 `last_error` 清除为 `NONE`；
- 从 `ERROR` 成功重新 `Init` 时把 `last_error` 清除为 `NONE`；
- `Run` 在 `ERROR` 中重复调用不得修改 `last_error`。

IoDevice 无法继续通信而进入 `ERROR` 时，Core 必须先把对应 IoDevice 错误写入 `last_error`。如果会话先发生可报告错误、随后在错误响应或 `end_session` 阶段发生 IoDevice 错误，后发生的 IoDevice 错误替换先前记录，保持“最后错误”的简单语义。

`last_error` 只需保存便于研发定位的最后错误类别，例如 protocol error code、Algorithm/internal error、IoDevice error 或 `IODEVICE_END_SESSION_ERROR`；具体设备错误由用户 IoDevice 保存和解释。如果 `C2837xBlock` 是公开结构体，`last_error` 可以作为调用者只读的诊断字段；如果 Block 是不透明结构体，Core 必须提供一个简单等价读取接口。读取不得推进状态机、调用用户函数或修改错误记录。首版不得增加复杂错误对象、错误历史、自动恢复或跨实例错误传播框架。

### REQ-CORE-006：Algorithm 生命周期

每个 Block 必须保存 `algorithm_started`，并遵守：

1. 合法 `SIM_START` 时，若提供 `on_start` 则调用并检查结果；未提供等价于成功。两种成功路径均立即置 `algorithm_started=true`，不等待启动成功响应发送完成。
2. `on_start` 失败时不得设置 `algorithm_started` 或调用 `on_stop`；Core 必须生成现有 V1 Algorithm/internal error 的 `RESPONSE(error)` 并进入 `ENDING`。
3. 只要 `algorithm_started=true`，合法 `SIM_STOP`、`LINK_DOWN`、终止性协议错误、IoDevice `ERROR`、Algorithm `process` 失败和 `end_session` 失败都必须调用一次 `on_stop`。
4. 调用 `on_stop` 后必须立即清除 `algorithm_started`，保证一个已启动会话恰好调用一次，不得只根据 `state==RUNNING` 推断是否需要停止。
5. `on_stop` 为无失败语义的可选 `void` 回调；未提供时只清除 `algorithm_started`。

用户回调的执行时间不受 Core 约束。回调不返回会阻塞用户主循环中的后续实例，这属于用户 Algorithm 责任。

### REQ-CORE-007：多实例调度和隔离

用户必须能够在同一个串行主循环中依次调用多个实例的 `Run`。一个实例返回 `IDLE` 或进入 `ENDING/ERROR`，不得直接修改或停止其他实例。

“同时运行多个算法”表示多个独立实例被串行协作调用，不表示并行执行，也不要求跨实例同步屏障或共享 step。

Core 不管理 IoDevice 所有权、占用关系、锁或共享冲突。多个 Block 错误地注入同一个不具备共享安全性的 IoDevice，属于用户集成错误。

### REQ-CORE-008：组合 Algorithm adapter

Core 只处理 wire octet，不得保存、分配或引用实例专用 typed input/output 类型，也不得包含实例专用头文件。首版只保留一套组合 Algorithm 操作语义：

- `on_start(algorithm_ctx)`：可选，返回成功或失败；
- `process(algorithm_ctx, input_data, input_data_length, output_data, output_data_capacity, output_data_length)`：必需，输入输出均为不含 `step_index` 的用户数据 wire octet buffer，返回成功或失败；
- `on_stop(algorithm_ctx)`：可选、无返回值。

完整 V1 `INPUT_DATA` 和 `OUTPUT_DATA` payload 的长度分别固定为：

```text
4 + input_data_size_bytes
4 + output_data_size_bytes
```

前 4 wire bytes 的 `step_index` 完全由 Core 负责。Core 从完整 `INPUT_DATA` payload 中解析并校验当前 step，只把其后的 `input_data` 及 `input_data_size_bytes` 传给 `process`；adapter 不得解析 step。`process` 只生成 `output_data`；Core 把已经校验的当前 step 编入 `OUTPUT_DATA` payload 前 4 wire bytes，再追加 adapter 生成的用户输出数据。adapter 不得读取、维护或生成 `step_index`。

每实例 `autogen` typed adapter 必须在 `process` 内完成“input data wire octets → typed input → 用户 OnStep → typed output → output data wire octets”。Core 不得知道 typed storage 的大小和布局。

Core 必须在调用 `process` 前确认完整 `INPUT_DATA` payload 长度等于 `4 + input_data_size_bytes`，并向 `process` 传入恰好为 `input_data_size_bytes` 的 `input_data_length`；不一致时不得调用 `process`，必须按现有 V1 length error 进入最终错误响应和会话结束流程。`process` 成功时必须设置 `output_data_length`，且其值必须严格等于 `output_data_size_bytes`；不一致时按 Algorithm/adapter error 处理，不得发送部分 `OUTPUT_DATA`。`Init` 必须保证 `output_data_capacity >= output_data_size_bytes`，否则按 Core/config 初始化错误拒绝初始化。

App 为每个实例生成 typed 数据类型、以下确定性用户回调声明及一个确定性通用 `process` adapter；`<instance>` 必须直接替换为该实例的 `normalized_instance_name`，不得改变大小写：

```c
bool C2837xBlock_<instance>_OnStart(void *user_ctx);
bool C2837xBlock_<instance>_OnStep(
    void *user_ctx,
    const C2837xBlock_<instance>_InputData *input,
    C2837xBlock_<instance>_OutputData *output);
void C2837xBlock_<instance>_OnStop(void *user_ctx);

bool C2837xBlock_<instance>_Process(
    void *algorithm_ctx,
    const protocol_octet_t *input_data,
    uint16_t input_data_length,
    protocol_octet_t *output_data,
    uint16_t output_data_capacity,
    uint16_t *output_data_length);
```

`C2837xBlock_<instance>_OnStep` 是用户必须在 `user/` 实现的唯一 typed 回调，生成的 `process` adapter 必须直接调用它。`C2837xBlock_<instance>_OnStart` 和 `C2837xBlock_<instance>_OnStop` 为可选生命周期回调：用户实现时把它们分别放入注入的通用 `AlgorithmOps.on_start/on_stop`，不实现时对应指针为 `NULL`；`autogen` 不得无条件引用未启用的可选符号。注入的 `AlgorithmOps.process` 必须指向该实例生成的通用 `process` adapter。Core 始终只调用通用 `on_start/process/on_stop`，用户 Algorithm 实现不得放入 `autogen`。

## 3. DSP IoDevice 接口

### REQ-IO-001：接口组成

DSP IoDevice 由用户提供的操作表和不透明 `ctx` 组成：

- 必需 `read(ctx, buffer, capacity)`：读取最多 `capacity` 个 wire octet；
- 必需 `write(ctx, buffer, count)`：接受最多 `count` 个待发送 wire octet；
- 可选 `poll(ctx)`：非阻塞推进并查询 transport 是否可开始或继续协议会话；
- 可选 `end_session(ctx)`：结束当前 transport 会话并推进到可等待下一次仿真的状态。

`Init` 缺少 `read` 或 `write` 时失败；缺少 `poll` 或 `end_session` 不失败。Core 只调用实际提供的操作，不调用或推断其他设备操作。`algorithm_ctx` 和 `iodevice_ctx` 均可为 `NULL`，Core 只原样传递。

接口不包含设备类型枚举、W5300 Socket、SCI channel、硬件 init、设备错误结构或平台寄存器信息。`end_session` 是协议会话生命周期操作，不等同于规定所有设备都必须物理断开。

### REQ-IO-002：非阻塞结果

提供 `poll` 时使用以下最小状态：

- `DOWN`：当前不能开始或继续协议会话，但不是设备错误；
- `READY`：当前可以收发协议数据；
- `ERROR`：IoDevice 无法继续。

`read` 和 `write` 使用相同的最小结果语义：

- 正数：本次实际读取或接受的 wire octet 数；
- `0`：当前没有数据或没有发送空间，不是错误；
- `LINK_DOWN`：收发过程中发现当前 transport 会话已经结束；
- `ERROR`：IoDevice 无法继续。

未提供 `poll` 时等价于始终返回 `READY`。

提供 `end_session` 时使用最小结果 `DONE/PENDING/ERROR`；Core 每次 `Run` 最多调用一次。`PENDING` 时保持 `ENDING` 并立即返回，后续 `Run` 再调用；用户实现必须保证在外部 transport 条件稳定后，重复调用最终返回 `DONE` 或 `ERROR`，不得永久返回 `PENDING`。`DONE` 时进入 `WAIT_LINK`；`ERROR` 时进入 `ERROR`。未提供时，Core 不执行 transport 收尾，清除自身会话状态并直接进入 `WAIT_LINK`，视为用户 IoDevice 或外部代码已完成必要处理。Core 不为此增加 wall-clock timeout 或自动恢复。

Block 不解释 IoDevice 的具体错误。IoDevice 调用自身的阻塞时间属于用户实现责任；Core 只保证不通过循环重复调用来等待结果。

### REQ-IO-003：wire octet 语义

IoDevice 与 Core 之间的单位是 wire octet，数值范围固定为 `0x00`–`0xFF`。支持层必须定义适合目标编译器的 `protocol_octet_t` 或等价类型；即使底层 C 存储单元宽于 8 bit，也只有低 8 bit 有效。

W5300 的 16-bit FIFO 配对、SCI 的 byte 收发、奇数字节保存和硬件字节顺序都由用户 IoDevice 实现。Core 不得出现 W5300 FIFO swap、SCI FIFO 或寄存器分支。

### REQ-IO-004：接口充分性和会话结束

同一套 Core 必须能在不修改 Core 源码的情况下绑定不同用户 IoDevice。合法 `SIM_STOP` 后，W5300 IoDevice 的 `end_session` 可以关闭当前 Socket 并重新进入 open/listen 流程；SCI IoDevice 的 `end_session` 可以清理本通道会话缓存并保持或重新报告 `READY`。具体动作完全由用户实现。

若实现 W5300、SCI、Mock 或其他设备时必须向 Core 加入设备分支，说明 IoDevice 抽象不充分，应调整通用接口，而不是把设备逻辑放入协议状态机。

PC 侧不使用“DSP IoDevice”名称，也不要求实现本操作表；PC 侧组件称为 PC TCP client、PC TCP context 或现有等价名称。

### REQ-IO-005：W5300 固定缓存策略

首版由用户在 W5300 初始化代码中将芯片可配置的 TX 份额平均分配给 8 个 Socket，并将可配置的 RX 份额平均分配给 8 个 Socket。未使用的 Socket 仍保留固定均分所得缓存。本文件不把 W5300 描述为 TX、RX 各自拥有一个完整 128 KB 池；实际总容量、TX/RX 划分、寄存器值和单位以用户现有初始化代码及芯片约束为准。

App 不提供 W5300 缓存配置，`autogen` 不生成 W5300 缓存表，也不根据 Instance 数量、payload 或 sample time 动态计算缓存。具体寄存器值和单位由用户现有初始化代码确定；除非真实联合仿真证明固定策略不足，否则不增加动态缓存功能，也不为此修改现有 W5300 HAL 或 Socket 驱动。

## 4. 协议与会话

### REQ-PROTOCOL-001：保持 V1

首版保持 `spec_v2_3.md` 已定义的 V1 wire frame、消息类型、错误码、little-endian、payload 类型和 `protocol_version=0x0001`。不得增加 Magic、帧 CRC、重试消息、设备编号或新握手阶段。

PC codec 和 DSP codec 可以采用适合各自平台的实现，但必须产生相同 wire octet。

### REQ-PROTOCOL-002：每实例 config_hash

每个实例必须具有独立 `config_hash`，并继续使用现有 V1 CRC32 参数、字段顺序、数字格式和换行规则。唯一的 Hash 格式变化是把以下字段紧接在现有 `protocol=0x0001` 字段之后：

```text
instance=<normalized_instance_name>
```

除插入该字段外，其他既有字段顺序不变。`instance` 的值必须使用保留原始大小写的 `normalized_instance_name`。PC TCP 地址/端口、IoDevice 类型、Socket 和 SCI channel 均不得进入 Hash。App 计算 Hash 并写入 PC/DSP 常量；DSP 不进行运行时 Hash 计算，也不增加多版本 Hash 兼容层。

### REQ-PROTOCOL-003：每实例 step_index

每个实例独立维护 PC `step_index` 和 DSP `expected_step_index`：

- 有效 `SIM_START` 后两端从 `0` 开始；
- DSP 仅在完整 `OUTPUT_DATA` 帧被 IoDevice `write` 全部接受后递增 `expected_step_index`；
- PC 仅在完整接收、校验并解码对应 `OUTPUT_DATA` 后递增 `step_index`；
- DSP 不等待也无法知道 PC 是否已完成校验；
- 两端均按 uint32 模 `2^32` 回绕；
- 合法 `SIM_STOP` 或新会话开始时按 V1 会话规则清零。

一个实例的 step 不得读取或修改其他实例的 step。

### REQ-PROTOCOL-004：正常结束和错误结束

收到合法 `SIM_STOP` 时，Core 按 `algorithm_started` 规则停止 Algorithm、清零本会话 step，并进入 `ENDING`。`poll/read/write` 报告 `LINK_DOWN` 时同样停止 Algorithm 并进入 `ENDING`，不直接扩大为设备错误。

可报告错误必须按下表使用现有 V1 error code，不得新增、重排或改变 wire 值：

| 可报告错误 | V1 error code |
|---|---:|
| 未知报文类型 | `1` |
| 协议 payload 长度错误，包括完整 `INPUT_DATA` payload 长度不符合实例配置 | `2` |
| `config_hash` 不匹配 | `3` |
| 当前状态不允许收到该消息 | `4` |
| `on_start` 失败、`process` 失败、adapter 内部错误，或 `process` 成功但 `output_data_length` 不符合生成配置 | `5` |
| `protocol_version` 不匹配 | `6` |
| `step_index` 不匹配 | `7` |
| 不支持的数据类型或 ABI | `8` |

输入协议长度不符合实例配置属于 protocol length error，必须使用 error code `2`；`process` 返回成功但输出长度错误属于 Algorithm/adapter internal error，必须使用 error code `5`。上述错误均必须生成现有 V1 `RESPONSE(error)`。若 `algorithm_started=true`，Core 必须先调用一次可选 `on_stop` 并立即清除该标志，然后进入 `ENDING`，不得发送部分 `OUTPUT_DATA`。

Core 必须按正常部分 TX 机制对最终 `RESPONSE(error)` 进行有限 best-effort 发送。进入 `ENDING` 后必须先推进该错误响应；只有完整发送、`write=0` 或 `write=LINK_DOWN` 后才能进入可选 `end_session` 阶段，且同一次 `Run` 不得同时调用二者。不得为错误响应增加 DSP wall-clock timeout。此“零进度即放弃”规则只适用于已经决定结束会话的最终错误响应，不适用于启动成功响应或正常 `OUTPUT_DATA`。

`poll/read/write=ERROR`、错误响应发送时 `write=ERROR` 或 `end_session=ERROR` 表示 IoDevice 已经无法继续通信。Core 必须先按生命周期规则停止已启动 Algorithm，再直接进入 `ERROR`，不得尝试或继续发送协议响应。所有进入 `ERROR` 的路径都必须保证已启动 Algorithm 的 `on_stop` 已恰好调用一次；重新 `Init` 不再调用 `on_stop`。具体设备处理由用户完成；Core 不实现自动重试、自动恢复、自动重同步或错误作用域传播。

## 5. Simulink S-Function

### REQ-SFUN-001：每实例独立模块

每个 Algorithm Instance 必须生成唯一的 S-Function/MEX 名称和独立 PC TCP context。一个 Normal mode 模型必须能够同时加载至少两个不同实例模块。

每个模块独立保存 TCP 连接、`config_hash`、`step_index`、输入输出定义和本地 timeout，不得使用限制整个模型只能存在一个 C2837xBlock 的全局标志。

### REQ-SFUN-002：同步联合仿真

每个 S-Function 必须保持现有同步联合仿真语义：

- `mdlStart` 打开本实例 PC TCP client 并完成 `SIM_START`；
- `mdlOutputs` 完成一次 `INPUT_DATA → OUTPUT_DATA` 交换；
- `mdlTerminate` best-effort 发送 `SIM_STOP`，随后关闭本实例 PC TCP client。

通信耗时只影响仿真墙钟速度，与 Simulink 仿真步长无速率绑定关系。所有当前 sample hit 的模块 callback 返回后，Simulink 才推进仿真时间。

### REQ-SFUN-003：失败即停止

任一 S-Function 连接失败、timeout、收到错误响应或发现协议/step 错误时，必须设置 Simulink error status，使整个模型停止。DSP 侧局部错误仍不得直接修改其他 DSP 实例；其他 S-Function 随模型停止执行各自正常终止流程。

PC 必须先完整校验和解码响应，再一次性提交本 sample hit 的全部输出。失败 sample hit 不得写入任何输出端口；无需清零上一次成功输出。

### REQ-SFUN-004：首版模式

首版只支持并验收 Simulink Normal mode 的串行 callback。Accelerator、Rapid Accelerator、代码生成、并行仿真、多个 MATLAB 进程和 Fast Restart 不在范围内。

## 6. App 与生成

### REQ-GEN-001：改造现有 App 支持多实例

必须直接改造现有 App，不得新建第二套配置工具。App 至少支持 Algorithm Instance 列表的新增、删除、选择和编辑，保存和加载多实例配置，一次生成全部实例，一次构建全部实例 MEX，并显示具体失败实例及错误。

每实例配置只包含：规范化实例名、PC TCP 地址和端口、sample time、输入定义、输出定义以及必要的 ABI/double 选项。S-Function、MEX、外部 C 符号前缀和 `autogen` 实例目录由规范化实例名确定性派生。

用户输入的实例名必须匹配 ASCII C 标识符字符规则：首字符只能是 `A-Z`、`a-z` 或 `_`，后续字符只能是 `A-Z`、`a-z`、`0-9` 或 `_`。App 校验失败时必须要求用户修改，不得自动 trim、删除、替换、转义字符或改变大小写。通过校验的原始字符串就是 `normalized_instance_name`，Hash 和所有派生规则均保留其原始大小写。

App 必须检查以下唯一性：实例名、`(PC TCP 地址, PC TCP 端口)` 组合、派生 S-Function 名、派生 MEX 名、外部 C 符号前缀和 `autogen` 实例目录。实例名及所有派生文件名、目录名、模块名和符号前缀必须按不区分大小写检查唯一性，不允许仅大小写不同的两个实例同时存在。

PC TCP endpoint 只表示 PC S-Function 的连接目标。用户负责保证 `user/` 中实际 IoDevice 的监听或连接参数与其一致。

### REQ-GEN-002：Algorithm Instance 和生成物边界

Algorithm Instance 配置只表示实例名、I/O、sample time、ABI/double 模式、协议配置、`config_hash`、S-Function/MEX 和 typed adapter；它与一个独立 `C2837xBlock` 运行实例配套，但不包含该运行实例的可变状态。

`autogen` 只包含不可变实例配置、typed I/O、adapter、Hash 和 S-Function wrapper。RX/TX、状态机、`expected_step_index`、`algorithm_started` 和 last error 必须存储在用户静态分配的 `C2837xBlock` 对象中。App 不生成已实例化运行 context；Block 对象由用户集成代码或现有工程中不会覆盖用户修改的位置声明，不得放入 App 反复覆盖的实例配置文件。

App 配置和 `autogen` 中不得出现 `IoDeviceId`、`DeviceType`、`SocketIndex`、`SciChannel`、`IoDeviceOps`、`IoDeviceContext` 或 Algorithm 到设备的全局绑定表，也不得包含 `end_session` 策略、W5300 缓存、FIFO 或板级配置。

用户可以在 `user/` 中把 Algorithm A/B 分别注入 W5300 Socket 0/1，也可以在 DSP 侧以后改为 SCI 或 Mock IoDevice，而无需改变或重新生成 Algorithm typed I/O、Hash 和 adapter。PC transport/wrapper 是否需要新增实现或重新生成，按 `REQ-SCOPE-002` 执行。生成器不得输出或覆盖用户 Algorithm、IoDevice、设备初始化或用户主循环。

### REQ-GEN-003：简单生成和构建

共享 Core/协议支持只保留一份；每实例只生成协议配置、Hash 常量、typed I/O 与 adapter、S-Function wrapper 和 MEX 构建参数。

生成输出只需一个简单 manifest，记录生成器版本、规范化工程配置摘要、实例列表和生成文件列表。不要求文件逐项 SHA-256、MEX manifest、project evidence、阶段状态机、文件锁预检或复杂提交回滚系统。

统一构建入口应尝试构建全部实例 MEX，并明确报告失败实例；首版不要求旧单实例配置自动迁移，也不建立独立制品事务系统。

## 7. 最小验证与用户验收

### REQ-TEST-001：协议和 Core 最小回归

AI/Codex 只在 host-side 或现有测试框架中提供最小验证，不创建新的 DSP 测试工程。范围限于：

- 现有 V1 wire-octet 黄金向量；
- Core + Mock IoDevice 冒烟测试，确认 Core 独占 `step_index`、adapter 只接收/生成用户 data；
- 两个静态 Block，使用不同 Hash 和 typed I/O；
- 部分收发以及 `read/write=0` 时 `Run` 立即返回；
- 单实例错误不修改另一实例；
- V1 error code `1`–`8` 的确定性映射；可报告的协议/Algorithm 错误发送 `RESPONSE(error)`，IoDevice `ERROR` 直接进入 `ERROR`；
- 可选 `poll/end_session` 的缺省语义，以及 `ERROR` 中 `Run` 无操作、重新 `Init` 可开始新初始化周期；
- `Init` 失败不改变原状态、注入引用或 `last_error`；成功重新 `Init` 和成功进入新 `RUNNING` 会话时按需求清除 `last_error`；
- App 拒绝非法实例名和仅大小写不同的实例名；
- PC 双 S-Function 连接两个 Mock endpoint 的主链路。

除发现真实缺陷所需的回归用例外，不扩展大型错误矩阵、Fake 组合或生成式测试工程。

### REQ-TEST-002：PC/Mock 冒烟验证

项目侧主链路冒烟验证应在同一 Normal mode 模型中加载两个不同 TCP S-Function，连接两个 Mock endpoint，完成至少 1000 次独立交换，并验证两个实例的 Hash、step、输入和输出互不串扰。

### REQ-TEST-003：用户 DSP 和硬件验收责任

DSP Core 集成、用户 IoDevice、W5300/Socket/FIFO/内存表、板级初始化、设备错误、外部恢复、Algorithm 注入和主循环的测试均由用户完成。AI/Codex 不创建 DSP 测试工程，也不修改用户现有测试工程。

用户应确认 IoDevice 无数据或无发送空间时，`Run` 立即返回并允许主循环继续调用其他实例；并使用两个 W5300 Socket、两个 IoDevice、两个 Algorithm 和两个 S-Function 完成至少 1000 次真实联合仿真交换，至少验证一次 `SIM_STOP → end_session → W5300 重新等待连接 → 新 SIM_START`。

未执行的 MEX、Simulink、DSP 或硬件验证必须明确标记为“未验证”，不得以需求文档代替验证结果。

## 8. 明确延后或排除

### REQ-COMPAT-001：非首版内容

以下内容不进入首版：

- SCI 和 Windows COM 的具体实现与测试；
- 中央 Manager、动态实例注册表和 `RunAll()`；
- 自动设备匹配、资源占用表和共享设备仲裁；
- 运行中动态切换 IoDevice；
- 自动恢复、自动重试和设备健康管理；
- Block Reset API、IoDevice reset API 和 reset 状态机；
- W5300 HAL/Socket 驱动修改；
- 工业级 timeout、冗余和无人值守恢复；
- 多版本 Hash 兼容和旧配置自动迁移；
- 多份 manifest、project evidence 和制品阶段状态机；
- 大型测试矩阵和自动生成 DSP 测试工程。

## 9. 规格事实源和后续入口

`spec_v2_3.md` 继续作为 V1 wire frame、消息、错误码、数据类型、CRC32 参数和既有 Hash 字段格式的正式事实源。本文件定义多实例、运行时注入、Algorithm adapter 和 IoDevice 抽象的研发首版增量；如两者存在冲突，在实施前必须把本文件确认后的协议增量合并回 `spec_v2_3.md`，避免长期存在两个协议事实源。

本文件已冻结，可以据此制定实施计划。实施开始前如需改变接口、状态或职责边界，必须先修订本文件。不得以计划或文档声称已完成 MEX 构建、Simulink、DSP 或硬件验证。
