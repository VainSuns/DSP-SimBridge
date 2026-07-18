# DSP-SimBridge 多实例联合仿真需求规格

> **状态：Frozen V1.0 Rev.2**
>
> **冻结日期：2026-07-19**
>
> **适用项目：DSP-SimBridge / C2837xBlock**
>
> 本文件是第一版唯一有效需求基线，取代此前所有多 IoDevice、单实例、运行时注入 IoDevice、无 DSP 超时等旧版需求文件和审查意见。旧文件 `requirements_multi_iodevice (1).md` 属于错误需求，实施前必须删除，不得作为实现依据；`spec_v2_3.md` 仅可作为历史单实例资料保留，不是当前协议或实现事实源。
>
> 本文件定义产品范围、外部行为、模块职责、生成边界、集成方式、测试责任和阶段门禁；不包含详细设计、具体函数内部实现步骤、CCS 工程配置或硬件测试结果。
>
> **Rev.2 修订说明：** 在 Rev.1 基础上进一步冻结 PlatformInit 初始化期等待边界、公共 Core 与 W5300 通道私有关闭状态的归属、W5300 SEND 完成语义、关闭结果与故障终态、App 职责分离门禁、阶段0协议基线，以及 PC/Simulink 与 DSP 软件环境范围。

---

## 1. 目标、范围与非目标

### FR-001：产品定位

DSP-SimBridge 用于算法研发、调试和 Simulink—DSP 联合仿真，优先保证快速实现、结构清晰和单次研发会话可靠运行，不按工业通信产品设计。

### FR-002：第一版核心目标

第一版应允许一个 TMS320F28377D DSP 在同一裸机程序中承载多个独立算法实例，每个算法实例对应一个独立生成的 C S-Function，并可由 Simulink 分别驱动。

### FR-003：多实例执行模型

多个实例在同一个裸机 `while (1)` 中按用户给定顺序串行轮询。第一版不使用 RTOS、线程、任务调度器、多核并行、动态优先级或真正并行执行。

### FR-004：实例独立性

每个实例必须独立保存并管理：

- 输入和输出对象；
- RX/TX 软件缓冲区；
- IoDevice 通道状态；
- 连接与会话状态；
- 协议阶段；
- `step_index`；
- 收发进度；
- 超时时间戳；
- 算法启动状态；
- 最近一次本地错误。

一个实例的停止、断线、超时或协议错误不得直接修改其他实例。

### FR-005：连接关系

一个算法实例对应一个 DSP TCP 监听端口和一个生成的 S-Function。不同实例可以由同一个 Simulink 模型、不同 Simulink 模型或不同 MATLAB 进程分别连接，但同一 DSP 实例在任一时刻只处理一个 TCP 会话。

### FR-006：单模型模块使用边界

同一个生成实例的 S-Function 在同一 Simulink 模型中只放置一次。第一版依赖用户和 Simulink 模型约束，不增加额外的跨模块注册表或重复实例检测框架。

### FR-007：异常责任边界

用户算法发生内存破坏、死循环或长期不返回时，可能阻塞整个 DSP 主循环并影响全部实例。第一版不提供算法抢占、回调超时、算法看门狗或故障隔离容器，用户可通过调试器或系统复位恢复。

### FR-008：多轮会话

实例在正常或异常会话结束后，应关闭当前连接、执行统一清理并重新进入等待连接状态，允许在同一 DSP 复位周期内再次连接和运行。

### FR-009：第一版非目标

第一版不实现：

- SCI、USB、UDP 或其他以太网控制器；
- 动态实例创建、删除或注册；
- RTOS、线程、任务优先级或 `RunAll()`；
- 协议自动协商、自动降级或多版本并存；
- 自动重连、请求重发、丢步补偿或后台流水线；
- 错误历史数据库、持久化日志或远程诊断协议；
- CCS 工程、链接文件、启动代码或烧录流程生成；
- 自动生成 Simulink 模型；
- Simulink Coder、Embedded Coder、Rapid Accelerator 或实时目标部署；
- 正式安装包、Toolbox、独立程序或自动更新器；
- 自动硬件烧录和复杂硬件测试平台。

---

## 2. 术语、单位与协议事实源

### FR-010：C28x 存储单位

在 C28x 上，一个 C 语言可寻址存储单位为一个 16-bit word。例如：

```c
sizeof(int)     == 1
sizeof(int16_t) == 1
```

最终需求和生成代码不得把普通 8-bit CPU 的 C `byte` 概念直接用于 DSP 软件存储尺寸。

### FR-011：wire octet

`wire octet` 表示通信协议中的 8-bit 线缆单位。协议 Header 长度、Payload 长度、网络传输长度和 Interface Hash 中的长度均以 wire octet 表示。

### FR-012：C28x word

`C28x word` 表示 DSP 中的 16-bit 存储和寻址单位。DSP RX/TX 数组容量必须使用 word 数表示。

### FR-013：兼容字段名称

项目字段 `max_payload_size_bytes` 第一版继续保留。该字段中的 `bytes` 明确定义为 **8-bit wire octet**，不表示 C28x 的 `sizeof()` 单位或 DSP 软件缓冲区 word 数。

### FR-014：W5300 容量单位

W5300 内部每个 Socket 的 `8 KB` RX 和 `8 KB` TX 容量按 W5300 数据手册的 8-bit 字节单位理解，与 DSP 软件 word 缓冲区和 `max_payload_size_bytes` 相互独立。

### FR-015：协议事实源

消息类型、协议错误码编号、协议 Header、固定 Payload 字段、字段顺序和现有线缆含义，以仓库现有 `c2837x_block_protocol.h` 及其对应 V1 实现为唯一事实源。

阶段0必须将旧 V1 协议基线固定到以下不可变提交：

```text
f209302ce3efc0fa15d217550f6d9b1dc00487fb
```

可另外建立只读 tag `legacy-v1-protocol-baseline` 指向该提交。后续重构后的协议文件不得反向改变本条所指的历史 V1 线缆基线。

### FR-016：协议错误码兼容

第一版不得改变现有协议错误码的编号、符号或含义。旧错误码即使新架构不再主动产生，也应保留，不得重新赋予其他含义。

### FR-017：现有线缆协议保持

第一版保持现有 V1：

- 4 wire octet 协议 Header；
- 现有消息类型；
- 现有固定消息结构；
- 现有 `RESPONSE` 形式；
- 现有小端编码；
- 现有 `step_index` 位置和语义；
- 现有协议版本号 `1`。

不得增加 Magic、帧 CRC、实例 ID、新握手阶段或可选扩展字段。

---

## 3. App 项目模型

### FR-018：项目层级

App 项目配置分为项目公共配置和实例配置两个层级。

项目公共配置至少包含：

```matlab
project.format_version
project.common.dsp_model
project.common.protocol_version
project.common.abi
project.common.network
project.instances
project.output.dsp_root
project.output.sfun_root
```

### FR-019：项目格式版本

第一版项目格式固定为：

```matlab
project.format_version = uint16(2);
```

项目格式版本与通信协议版本、DSP Core API Version 相互独立。

### FR-020：项目公共 ABI

ABI 是项目级公共配置：

```matlab
project.common.abi = 'eabi'
```

或：

```matlab
project.common.abi = 'coffabi'
```

同一生成项目的全部 DSP 公共文件和实例文件必须使用同一个 ABI。实例中不得保存独立 ABI。

### FR-021：项目公共网络配置

项目公共网络配置至少包含：

```matlab
project.common.network.mac
project.common.network.ip
project.common.network.gateway
project.common.network.subnet
```

这些字段不复制到实例配置中。修改公共网络参数后，项目级 DSP 配置和全部实例 S-Function 路由配置需要重新生成，但 Interface Hash 和协议版本不变。

### FR-022：项目输出配置

输出路径只属于：

```matlab
project.output.dsp_root
project.output.sfun_root
```

不得在 `project.common` 或实例中重复保存相同输出路径。

### FR-023：实例配置

每个实例至少保存：

- `display_name`；
- `internal_name`；
- IoDevice 类型；
- W5300 Socket 编号；
- TCP 监听端口；
- S-Function 采样时间；
- `max_payload_size_bytes`；
- 输入变量表；
- 输出变量表；
- 算法文件模式；
- 外部算法源文件路径；
- 重新计算得到的 Interface Hash 辅助值。

### FR-024：删除旧字段

第一版删除实例级 ABI 和旧 `Double Mode` 配置。加载旧配置时，旧 `double_mode` 字段忽略，不恢复为有效选项。

### FR-025：App 实例操作

App 第一版必须支持：

- 新建实例；
- 编辑实例；
- 复制实例；
- 重命名实例；
- 删除实例；
- 调整输入输出表；
- 保存项目；
- 加载项目；
- 从旧单实例配置迁移。

### FR-026：主界面组织

主界面应具有项目公共配置区域、实例列表和当前实例详细配置区域。实例列表至少显示：

- 显示名称；
- 内部名称；
- IoDevice；
- Socket；
- TCP 端口；
- 采样时间。

### FR-027：显示名称

`display_name` 只用于 App 界面，不参与 C 标识符、文件名、MEX 名称、线缆协议或 Interface Hash。

### FR-028：内部名称

`internal_name` 决定：

- 生成目录名；
- 文件名；
- C 结构体、函数和实例符号；
- Include Guard；
- S-Function 名称；
- MEX 名称。

内部名称不参与 Interface Hash。

### FR-029：内部名称规则

内部名称必须：

- 首字符为 ASCII 字母，不得以下划线开头；
- 后续字符仅允许 ASCII 字母、数字和下划线；
- 是合法 C 标识符；
- 在项目内唯一；
- 不得仅大小写不同；
- 不得与 C 关键字、TI 编译器或运行库保留标识符、生成器保留字、公共 API 符号或 `step_index` 冲突。

App 可从显示名称自动生成初始内部名称，但用户修改后必须重新校验。

### FR-030：输入输出名称规则

输入和输出变量名称必须：

- 首字符为 ASCII 字母，不得以下划线开头；
- 后续字符仅允许 ASCII 字母、数字和下划线；
- 是合法 C 标识符。

一个实例的输入和输出共用一个名称作用域，不得重名、仅大小写不同，或与 C 关键字、TI 编译器或运行库保留标识符、生成器保留名称及 `step_index` 冲突。

### FR-031：实例复制规则

复制实例时可以复制：

- 输入输出定义；
- 采样时间；
- `max_payload_size_bytes`；
- IoDevice 类型。

复制后必须生成或重新指定：

- 新显示名称；
- 新内部名称；
- 新 Socket 编号；
- 新 TCP 端口；
- 新算法文件路径。

复制实例不复制原用户配置文件中的 DSP 或 PC 超时值。

### FR-032：外部算法复制时清空路径

原实例使用外部算法文件时，复制实例默认清空外部源文件路径，要求用户重新选择，避免两个强类型实例错误复用同一套实例专用回调符号。

### FR-033：实例删除

删除实例只修改 `project.instances` 和后续生成内容，不自动删除磁盘上的旧文件、旧 S-Function 目录或旧 MEX。

### FR-034：实例重命名

修改 `internal_name` 采用“生成新文件”语义。App 不自动重命名或删除旧文件，也不修改 CCS 工程、MATLAB Path 或 Simulink 模型引用。

### FR-035：遗留文件提示

当前 App 会话中发生内部名称修改或实例删除时，生成预览和结果页必须提示旧文件残留风险。第一版不要求跨 App 重启保存完整重命名历史。

---

## 4. 项目保存、加载与迁移

### FR-036：项目文件格式

项目保存为 MATLAB `.mat` 文件，默认名称：

```text
dsp_simbridge_project.mat
```

顶层有效变量为 `project`。

### FR-037：保存范围

项目文件保存完整配置状态，但不保存：

- 生成文件内容；
- MEX 二进制；
- 运行时连接状态；
- 当前协议进度；
- DSP 或 PC 用户超时宏值；
- CCS 工程状态；
- 临时预览候选内容。

### FR-038：Interface Hash 保存语义

项目文件可以保存上一次计算的 Hash 作为辅助信息，但加载后必须根据当前配置重新生成规范文本并重新计算。重新计算结果是唯一有效值；若保存值与重新计算值不同，应使用重新计算结果并将项目标记为存在未保存修改。

### FR-039：dirty 状态

App 必须区分：

- 从未保存；
- 已保存且未修改；
- 已保存但存在未保存修改。

关闭 App 或加载其他项目时，如存在未保存修改，应提供 Save、Don’t Save、Cancel。

### FR-040：生成不等于保存

生成项目使用当前 App 界面配置，不要求项目已经保存。生成成功不得自动保存 `.mat` 或清除 dirty 状态。

### FR-041：高版本项目

加载高于当前 App 支持的 `format_version` 时必须拒绝，并提示使用更新版本 App。不得静默降级。缺少 `protocol_version` 的旧配置迁移为 `1`；协议版本高于当前 App 支持值时拒绝加载，值为零或非法时判定项目损坏。

### FR-042：损坏项目

缺少关键字段、字段类型非法或版本为零的项目应判定为损坏并拒绝加载，不得凭猜测补全关键结构。

### FR-043：旧单实例迁移

旧项目存在顶层 `config` 时，可迁移为一个实例：

- `display_name = 'C2837xBlock'`；
- `internal_name = 'c2837x_block'`；
- IoDevice 设为 W5300 TCP；
- 迁移现有网络、Socket、端口、采样时间、最大载荷和 I/O；
- 项目标记为未保存修改；
- 原文件不自动覆盖。

### FR-044：旧 ABI 迁移

旧 ABI 字段按以下规则迁移：

- `eabi` → `eabi`；
- `coff` 或 `coffabi` → `coffabi`；
- 缺失 → `eabi`；
- 其他值 → 加载失败。

### FR-045：旧 Double Mode

旧 `double_mode` 不进入新项目有效结构，不参与 Hash，不生成兼容代码。

---

## 5. 数据类型与强类型算法接口

### FR-046：支持的数据类型

第一版 App 仅支持：

```text
int16
uint16
int32
uint32
single
double
```

### FR-047：不支持的数据类型

第一版不支持：

- `int8`、`uint8`、`boolean`；
- complex；
- enum；
- fixed-point；
- bus；
- string；
- 自定义结构体；
- 多维矩阵；
- 变长信号。

### FR-048：端口维度

每个变量是固定长度一维信号：

- `dim = 1` 表示标量；
- `dim > 1` 表示固定长度向量；
- `dim` 必须为正整数。

每个实例至少有一个输入和一个输出。

### FR-049：DSP 类型映射

DSP 侧映射固定为：

| App 类型 | DSP C 类型 |
|---|---|
| `int16` | `int16_t` |
| `uint16` | `uint16_t` |
| `int32` | `int32_t` |
| `uint32` | `uint32_t` |
| `single` | `float` |
| `double` | `long double` |

### FR-050：PC/Simulink 类型映射

S-Function 端口直接使用对应 Simulink 类型：

| App 类型 | Simulink 类型 |
|---|---|
| `int16` | `SS_INT16` |
| `uint16` | `SS_UINT16` |
| `int32` | `SS_INT32` |
| `uint32` | `SS_UINT32` |
| `single` | `SS_SINGLE` |
| `double` | `SS_DOUBLE` |

第一版不执行隐式类型转换、缩放、饱和或单位换算。

### FR-051：逻辑 double

逻辑 `double` 在线缆上固定为 8 wire octet IEEE 754 binary64。PC 端 C 类型为 `double`，DSP 本地类型为 `long double`。ABI 不改变 wire 编码。

### FR-052：编译期类型检查

生成代码必须使用 `<stdint.h>`、`<limits.h>`、`<float.h>` 和编译期断言验证：

```c
sizeof(int16_t)   * CHAR_BIT == 16
sizeof(uint16_t)  * CHAR_BIT == 16
sizeof(int32_t)   * CHAR_BIT == 32
sizeof(uint32_t)  * CHAR_BIT == 32
sizeof(float)     * CHAR_BIT == 32
sizeof(long double) * CHAR_BIT == 64
```

并检查 `FLT_MANT_DIG`、`FLT_MAX_EXP`、`LDBL_MANT_DIG`、`LDBL_MAX_EXP` 满足 single 和 binary64 表示要求。

### FR-053：强类型结构

每个实例生成独立的强类型输入输出结构。结构体仅用于用户算法接口，不是 wire image，不得依赖结构体 padding、对齐或整体 `memcpy` 进行线缆传输。

### FR-054：算法回调

每个实例必须提供且实现以下实例专用回调：

```c
int16 <Instance>_OnStart(void);

int16 <Instance>_OnStep(
    const <Instance>_InputData *input,
    <Instance>_OutputData *output);

void <Instance>_OnStop(void);
```

`OnStart` 和 `OnStep` 返回 `0` 表示成功，非零表示失败。三个回调均为必需符号，不使用 `NULL` 可选回调。

### FR-055：算法状态

第一版不向回调传入通用 `void *context`。用户可在实例算法 `.c` 文件中使用 file-static 状态。具有状态的同一回调集合不得直接绑定到多个实例。

### FR-056：适配器边界

公共 Core 只接触通用算法适配器和 `void *` 内部对象指针。自动生成适配器负责：

- 将完整合法输入解包到最终强类型输入对象；
- 调用实例专用强类型回调；
- 从最终强类型输出对象编码线缆数据。

用户算法不得接触协议 Header、通用 Payload 缓冲区或内部状态机。

### FR-057：输入提交原子性

只有完整帧通过消息类型、长度、协议状态和 `step_index` 校验后，才允许修改最终强类型输入对象并调用 `OnStep()`。

第一版固定处理顺序：

```text
完整接收帧
→ 校验消息类型、固定长度和协议状态
→ 从 Payload 前两个 C28x word 提取 step_index
→ 校验 step_index
→ 解码全部输入字段到最终强类型输入对象
→ 调用 OnStep()
```

在最终输入对象开始解码前，所有可能导致协议拒绝的检查必须完成。非法帧不得部分修改输入对象。

第一版不强制额外分配第二份临时强类型输入对象；若具体解码实现存在字段中途失败的可能，则实现必须使用临时对象或其他等价机制保证上述原子性。

### FR-058：输入覆盖

每个合法 `INPUT_DATA` 必须包含全部输入字段，并完整覆盖当前实例输入对象。输入指针只在当前回调调用期间有效，回调内视为只读。

### FR-059：输出对象

输出对象在实例初始化、新会话和统一清理时清零，但每个步骤前不清零。用户必须在成功的 `OnStep()` 中写入全部需要输出的字段；未写字段在首步可能为零，后续可能保留旧值。

### FR-060：输出提交原子性

只有 `OnStep()` 成功后才编码正常 `OUTPUT_DATA`。`OnStep()` 失败时不得发送陈旧或部分正常输出，应进入错误处理。

### FR-061：浮点位模式

single 和 double 的正零、负零、无穷、NaN、subnormal 等位模式应按 wire 规则原样保留，不做数值过滤。

### FR-062：别名安全

浮点与整数 word 间转换不得使用违反 strict aliasing 的指针强制转换。应使用安全 union、明确 word-copy helper 或编译器定义的等价安全方法。

### FR-063：数组优化

连续同类型数组可以使用与逐元素编码完全等价的块处理优化，但必须保持相同 wire 顺序、长度和 Hash，不依赖结构体布局。

---

## 6. wire 编码、载荷与软件缓冲区

### FR-064：wire 顺序

线缆编码固定为 little-endian。多 word 数值按低 16-bit word 在前；每个 16-bit word 在线缆上仍按低 octet 在前。

### FR-065：step_index

`INPUT_DATA` 和 `OUTPUT_DATA` Payload 的前 4 wire octet 为 `uint32 step_index`。用户算法输入输出结构不包含该协议字段。

### FR-066：Payload 完整长度

完整输入和输出 Payload 长度为：

```text
input_payload_octets  = 4 + input_data_octets
output_payload_octets = 4 + output_data_octets
```

其中 4 为 `step_index`。

### FR-067：最大载荷语义

`max_payload_size_bytes` 只作为实例协议 Payload 安全上限，不包括 4 wire octet 协议 Header，也不表示 W5300 内部容量、DSP 软件 word 数、C 结构体大小或一次调用必须完成的长度。

### FR-068：最大载荷校验

`max_payload_size_bytes` 必须：

- 是正偶数；
- 不超过协议长度字段可表达的最大偶数；
- 不小于该实例所有合法消息中的最大 Payload；
- 对 SIM_START、SIM_STOP、INPUT_DATA、OUTPUT_DATA 和 RESPONSE 均有效。

### FR-069：固定消息长度

第一版所有现有消息采用固定合法 Payload 长度，不支持可选扩展或变长字段。消息类型与声明长度不匹配即为协议错误。

### FR-070：Header 优先接收

DSP 必须先完整接收 4 wire octet Header，再解析消息类型和声明 Payload 长度，完成长度与状态校验后才接收剩余 Payload。

### FR-071：Header 非法、长度错误与超限处理

DSP 完整获得 Header 后，应先校验 Header、消息类型和声明 Payload 长度。

若 Header 已完整获得，且声明长度超过 `max_payload_size_bytes`、超过实例 RX 容量或不等于该消息固定长度：

- 不继续接收剩余 Payload；
- 不调用算法回调；
- 当前连接和 TX 状态仍可安全使用时，通过正常非阻塞发送状态机尽力发送现有长度或协议错误 RESPONSE；
- RESPONSE 发送完成、发送失败或发送超时后关闭当前会话并统一清理；
- 不尝试 drain 剩余数据。

Header 未完整获得、连接已经失效、IoDevice 失败或 TX 状态不可用时，允许直接关闭并统一清理。

### FR-072：DSP 缓冲区单位

DSP RX/TX 软件缓冲区使用 `Uint16` 或等价 16-bit word 数组。生成代码内部采用明确宏名：

```c
<INSTANCE>_MAX_PAYLOAD_OCTETS
<INSTANCE>_RX_FRAME_WORDS
<INSTANCE>_TX_FRAME_WORDS
```

### FR-073：RX 缓冲区容量

实例 RX 完整帧容量按实际最大合法入站消息计算：

```text
max_inbound_payload_octets =
    max(SIM_START, SIM_STOP, INPUT_DATA 的合法 Payload)

RX_FRAME_WORDS =
    (PROTOCOL_HEADER_OCTETS + max_inbound_payload_octets) / 2
```

若实现将 Header 和 Payload 分开存储，总容量必须等价，并在生成报告中分别列出。

### FR-074：TX 缓冲区容量

实例 TX 完整帧容量按实际最大合法出站消息计算：

```text
max_outbound_payload_octets =
    max(OUTPUT_DATA, RESPONSE 的合法 Payload)

TX_FRAME_WORDS =
    (PROTOCOL_HEADER_OCTETS + max_outbound_payload_octets) / 2
```

不得按用户设置的安全上限盲目分配整个 RX/TX 数组。

### FR-075：偶数边界

第一版支持的合法消息长度均应为偶数 wire octet。生成器和编译期检查必须验证：

```c
(payload_octets % 2u) == 0u
```

IoDevice 不得向公共 Core 返回半个 C28x word 的有效进度；奇数进度视为设备适配错误。

### FR-076：内存报告

App 生成报告应按实例显示：

- 输入数据 wire octet 数；
- 输出数据 wire octet 数；
- 输入和输出完整 Payload wire octet 数；
- RX/TX 软件缓冲区 C28x word 数；
- 项目协议缓冲区静态 word 总量。

报告不包含算法内部静态变量、结构体 padding、栈、链接器段或 W5300 内部 RAM。

---

## 7. Interface Hash 与版本体系

### FR-077：独立 Hash

每个实例独立生成一个 32-bit Interface Hash。不同实例的接口完全相同时允许 Hash 相同，连接路由由 TCP 端口区分。

### FR-078：Hash 唯一字段集合

Interface Hash 规范文本只包含下列字段，不允许实现者自行增加、删除、合并或重命名字段：

1. `protocol_version`；
2. `wire_endianness`；
3. `step_index_type`；
4. `step_index_octets`；
5. `step_index_offset_octets`；
6. `input_count`；
7. 每个输入按顺序展开的 `name/type/dim/element_octets`；
8. `output_count`；
9. 每个输出按顺序展开的 `name/type/dim/element_octets`；
10. `input_payload_octets`；
11. `output_payload_octets`；
12. `max_payload_octets`。

其中 `max_payload_octets` 的值来源于项目字段 `max_payload_size_bytes`。

### FR-079：Hash 排除项

Interface Hash 不包含：

- 显示名称和内部名称；
- MAC、IP、网关、子网；
- Socket 和 TCP 端口；
- 采样时间；
- DSP/PC 输出路径；
- 算法文件路径和复制模式；
- EABI/COFF ABI；
- DSP 和 PC 超时；
- RX/TX 实际 word 数；
- 用户算法源代码；
- Core API Version；
- 旧 `double_mode`。

### FR-080：Interface Hash 规范文本

规范文本必须使用以下唯一键名、唯一顺序和逐行格式：

```text
protocol_version=1
wire_endianness=little
step_index_type=uint32
step_index_octets=4
step_index_offset_octets=0
input_count=<N>
input[0].name=<name>
input[0].type=<type>
input[0].dim=<dim>
input[0].element_octets=<octets>
...
output_count=<N>
output[0].name=<name>
output[0].type=<type>
output[0].dim=<dim>
output[0].element_octets=<octets>
...
input_payload_octets=<value>
output_payload_octets=<value>
max_payload_octets=<value>
```

生成规则固定为：

- 字段顺序严格按上表；
- 输入和输出索引从 `0` 开始；
- 每个变量使用四行，不得合并为分号分隔的一行；
- 行与行之间使用单个 `LF`，即 `0x0A`；
- 最后一行后不附加额外 `LF`；
- 所有整数使用无前导零十进制；
- 类型名只允许 `int16`、`uint16`、`int32`、`uint32`、`single`、`double`；
- 变量名称保留原始大小写；
- 不包含路径、区域设置、平台换行、ABI、网络、采样时间、超时或其他实现配置；
- 完整文本按 UTF-8 编码为 wire octet 序列。

### FR-081：顺序参与 Hash

输入和输出变量的表格顺序参与 Hash。相同字段集合但顺序不同必须生成不同 Hash。

### FR-082：CRC32 算法

第一版复用仓库现有 CRC-32/ISO-HDLC 算法：

```text
width   = 32
poly    = 0x04C11DB7
init    = 0xFFFFFFFF
refin   = true
refout  = true
xorout  = 0xFFFFFFFF
```

计算过程：

```text
规范文本
→ UTF-8 wire octet 序列
→ CRC-32/ISO-HDLC
→ uint32 Interface Hash
```

CRC32 仅用于接口误配检测，不用于认证、防篡改或安全保护。第一版不增加 64-bit Hash、完整接口描述握手或碰撞后二级校验，也不要求 DSP Core 或 S-Function 在运行时重新计算 Hash。

### FR-083：CRC32 黄金向量

第一版固定以下黄金向量，最后一行后无 `LF`：

```text
protocol_version=1
wire_endianness=little
step_index_type=uint32
step_index_octets=4
step_index_offset_octets=0
input_count=1
input[0].name=input_value
input[0].type=single
input[0].dim=1
input[0].element_octets=4
output_count=1
output[0].name=output_value
output[0].type=single
output[0].dim=1
output[0].element_octets=4
input_payload_octets=8
output_payload_octets=8
max_payload_octets=1024
```

该规范文本 UTF-8 长度为 `392` wire octet，期望 CRC-32/ISO-HDLC 为：

```text
0xE45D900C
```

验收必须验证：

- MATLAB App Hash 函数计算结果为 `0xE45D900C`；
- DSP 自动配置常量为 `0xE45D900C`；
- 对应 S-Function 自动配置常量为 `0xE45D900C`。

该验证不要求 DSP 或 S-Function 增加运行时 CRC32 计算模块。

### FR-084：Hash 预览

App 应显示或允许复制：

- Interface Hash；
- 输入和输出 Payload 长度；
- 参与 Hash 的规范文本。

第一版不要求生成独立 Hash 描述文件。

### FR-085：通信协议版本

通信协议版本是项目级固定属性：

```matlab
project.common.protocol_version = uint16(1);
```

第一版 App 不提供编辑控件。

### FR-086：协议校验

SIM_START 校验顺序固定为：

```text
协议状态
→ protocol_version
→ Interface Hash
→ OnStart()
```

版本或 Hash 不匹配时不调用 `OnStart()`。

### FR-087：无协议协商

第一版不发送支持版本列表、能力位或降级建议。版本不一致时尽力发送现有版本错误 RESPONSE，随后结束会话。

### FR-088：协议版本提升

协议 Header、消息语义、固定 Payload 格式、错误 RESPONSE、`step_index`、wire 编码或交互顺序发生不兼容变化时必须提升协议版本并整体重新生成 DSP 与 S-Function。仅 App 界面、内部函数、驱动缺陷、错误文本、超时默认值或不改变 wire 行为的性能优化不提升协议版本。

### FR-089：Core API Version

第一版 DSP 公共 Core API Version 固定为：

```c
#define C2837X_BLOCK_CORE_API_VERSION  1u
```

项目级生成代码声明期望版本：

```c
#define C2837X_BLOCK_EXPECTED_CORE_API_VERSION  1u
```

Core API Version 描述公共 Core 与生成 DSP 配置之间的内部编译接口契约，不表示通信协议版本。

### FR-090：三类版本分离

必须区分：

| 版本 | 作用 |
|---|---|
| `project.format_version` | `.mat` 数据结构 |
| `protocol_version` | DSP—PC 线缆协议 |
| `CORE_API_VERSION` | DSP Core—生成代码编译接口 |

三者不得复用同一字段。

### FR-091：Core API 编译检查

项目级生成头文件声明期望的 Core API Version，并在编译期与公共 Core 比较。不匹配必须产生明确编译错误。

### FR-092：Core API 排除项

Core API Version 不在线缆上传输、不进入 SIM_START、不参与 Interface Hash、不由 PC 检查。

---

## 8. DSP 公共 API 与静态实例

### FR-093：公共 API

公共 API 固定为：

```c
typedef struct C2837xBlock C2837xBlock;

typedef enum
{
    C2837X_BLOCK_ERROR_NONE = 0,
    C2837X_BLOCK_ERROR_INVALID_ARGUMENT,
    C2837X_BLOCK_ERROR_PROTOCOL,
    C2837X_BLOCK_ERROR_TIMEOUT,
    C2837X_BLOCK_ERROR_DISCONNECTED,
    C2837X_BLOCK_ERROR_IODEVICE,
    C2837X_BLOCK_ERROR_ALGORITHM_START,
    C2837X_BLOCK_ERROR_ALGORITHM_STEP,
    C2837X_BLOCK_ERROR_INTERNAL
} C2837xBlock_Error;

int16 C2837xBlock_PlatformInit(void);
void C2837xBlock_Init(C2837xBlock *instance);
void C2837xBlock_Run(C2837xBlock *instance);
C2837xBlock_Error C2837xBlock_GetLastError(
    const C2837xBlock *instance);
```

### FR-094：不透明结构

`C2837xBlock` 对用户保持不透明。完整结构定义只存在于公共 Core 内部头文件，例如：

```text
src/c2837x_block_internal.h
```

### FR-095：生成实例

App 生成项目级实例声明和定义，例如：

```c
extern C2837xBlock g_current_loop;
extern C2837xBlock g_voltage_loop;
```

实例由生成代码静态定义并绑定私有只读配置。

### FR-096：禁止用户创建实例

用户不得自行在栈、静态区或动态内存中定义新的 `C2837xBlock`。DSP 端全部实例、缓冲区、通道和协议对象均为编译期静态资源，不得使用 malloc/calloc/realloc/free。

### FR-097：禁止复制实例

复制实例对象、使用 `memcpy` 复制实例或让两个实例共享同一配置、Socket、缓冲区和通道属于错误用法。第一版只在文档中禁止，不增加复杂运行时检测。

### FR-098：公共函数参数

`Init` 和 `Run` 假定参数是生成实例。可以进行轻量 `NULL` 防护，但不建立对象注册表、魔数或运行时签名验证。

### FR-099：最近错误

每个实例只保存一个 FR-093 定义的 `C2837xBlock_Error` 最近错误值。该值：

- 仅用于 DSP 本地诊断；
- 与线缆协议错误码相互独立；
- 不在线缆传输；
- 不进入 Interface Hash；
- 不建立错误历史。

会话统一清理不清除最近错误；正常完成后可恢复为 `C2837X_BLOCK_ERROR_NONE`。

### FR-100：PlatformInit 稳定错误值

`C2837xBlock_PlatformInit()` 的函数签名保持：

```c
int16 C2837xBlock_PlatformInit(void);
```

公共头文件同时定义稳定的平台初始化结果常量：

```c
typedef enum
{
    C2837X_BLOCK_PLATFORM_OK                    =  0,
    C2837X_BLOCK_PLATFORM_ERROR_TIMER_INIT      = -1,
    C2837X_BLOCK_PLATFORM_ERROR_W5300_INIT      = -2,
    C2837X_BLOCK_PLATFORM_ERROR_W5300_MEMORY    = -3,
    C2837X_BLOCK_PLATFORM_ERROR_NETWORK_CONFIG  = -4
} C2837xBlock_PlatformResult;
```

每个负值必须对应可实际检测的失败条件，不得保留无明确触发条件的占位错误。平台错误不与实例 `C2837xBlock_Error` 混用，也不在线缆传输。

### FR-101：用户主程序

用户主程序只需包含：

```c
#include "c2837x_block_project.h"
```

并按实例显式调用：

```c
if (C2837xBlock_PlatformInit() < 0)
{
    for (;;)
    {
        /* 用户故障处理 */
    }
}

C2837xBlock_Init(&g_current_loop);
C2837xBlock_Init(&g_voltage_loop);

for (;;)
{
    C2837xBlock_Run(&g_current_loop);
    C2837xBlock_Run(&g_voltage_loop);
}
```

`PlatformInit()` 返回负值后，调用者不得继续调用实例通信 API。第一版不生成 `RunAll()`、`InitAll()` 或完整通用 `main.c`。

---

## 9. DSP 平台、W5300 与 IoDevice

### FR-102：第一版 IoDevice

第一版 App 只显示并生成：

```text
W5300 TCP
```

公共 Core 仍通过统一 IoDevice 接口访问，不直接包含 W5300 分支。

### FR-103：单物理 W5300

一个项目对应一个物理 W5300。全部实例共享 MAC、IP、网关、子网、公共硬件初始化和固定 Socket 内存配置。

### FR-104：Socket 资源

每个实例独占一个 Socket，范围为 `0～7`，项目内不得重复。不动态查找空闲 Socket，不允许一个实例使用多个 Socket。

### FR-105：TCP 端口

每个实例独占一个 TCP 监听端口，范围 `1～65535`，项目内不得重复。不同 Socket 使用相同端口仍视为冲突。

### FR-106：W5300 内存配置

第一版固定所有 8 个 Socket：

```text
TX = 8 KB
RX = 8 KB
```

App 不提供 Socket 内存容量控件。

### FR-107：未使用 Socket

未绑定实例的 Socket 保持关闭，不监听、不生成占位实例，也不分配 DSP 协议缓冲区。

### FR-108：固定硬件连接

第一版 W5300 HAL 使用仓库当前 C2837x—W5300 硬件连接、EMIF 映射、数据宽度、复位控制、GPIO 复用和访问时序。App 不提供引脚和 EMIF 时序配置。

### FR-109：网络参数校验

App 至少校验：

- MAC 恰好 6 octet，非全零、非广播；
- MAC 首 octet 的 I/G 位必须为 `0`，即 `(mac[0] & 0x01u) == 0u`，必须为单播地址；
- IPv4 合法，非 `0.0.0.0`、非 `255.255.255.255`；
- 子网掩码位连续且非全零；
- 网关为合法 IPv4，可为 `0.0.0.0`。

允许本地管理 MAC，不强制 U/L 位为 `0`。第一版不进行实际连通性测试。

### FR-110：PlatformInit

`C2837xBlock_PlatformInit()` 只调用一次，负责：

- 当前仓库所需 W5300 物理和公共初始化；
- EMIF/GPIO/reset 等平台初始化；
- MAC/IP/gateway/subnet；
- 8 个 Socket 固定 8 KB RX/TX 配置；
- CPU Timer 2 共享计时源。

W5300 硬件复位至少满足：

```text
/RESET 低电平保持时间 >= 2 μs
/RESET 释放为高电平后，首次访问 W5300 寄存器前等待时间 >= 10 ms
```

实际延时值必须在阶段2依据所用 W5300 数据手册版本复核，不得直接沿用未经核对的旧代码常量。

`PlatformInit()` 不启动算法、不建立实例会话、不阻塞等待连接。数据手册明确要求的一次性复位、PLL 稳定或初始化等待不属于实例运行期网络等待。

### FR-111：PlatformInit 返回

`0` 表示成功，负值表示公共平台初始化失败。失败时不启动任何实例通信，不自动持续重试或复位 DSP，由用户主程序决定处理方式。

### FR-112：Init 语义

`C2837xBlock_Init(instance)` 为 `void`，只重置实例软件状态、输入输出对象、进度和诊断初始值，不重新初始化 W5300 芯片、Timer 2 或其他实例。用户在 `PlatformInit()` 成功后对每个生成实例调用一次；会话结束和重新监听由 Core 内部完成，不要求用户通过重复调用 `Init()` 恢复。

### FR-113：IoDevice 最小语义

IoDevice 至少提供以下等价语义：

```text
channel_init
open
listen
get_connection_state
receive
send
close
```

具体内部函数名可以调整，但最终只能存在这一套责任边界：

- `PlatformInit()` 不属于 IoDevice 操作表；
- `channel_init` 只重置当前实例的软件通道状态；
- `open/listen/get_connection_state` 单次调用工作量有界；
- `receive/send` 使用 FR-114 的 wire-octet 进度语义；
- `close` 只处理当前实例通道；
- 公共 Core 不直接使用 W5300 寄存器、命令值或 Socket 状态常量。

### FR-114：IoDevice 收发接口

核心收发接口采用 C28x word 指针和 wire octet 长度：

```c
int32 (*receive)(
    void *channel,
    Uint16 *data_words,
    Uint32 capacity_octets);

int32 (*send)(
    void *channel,
    const Uint16 *data_words,
    Uint32 count_octets);
```

返回值：

- `receive() > 0`：本次实际接收并提交给 Core 的 wire octet 数；
- `send() > 0`：按 FR-265 已确认完成的发送 wire octet 数；
- `0`：本次调用无可向 Core 提交的进度；
- `< 0`：设备失败。

合法正进度必须为偶数 octet。`send()` 将数据写入 TX FIFO 或仅发出 SEND 命令时不得提前返回正进度。

### FR-115：非阻塞 IoDevice

IoDevice 的 `open`、`listen`、`get_connection_state`、`receive`、`send` 和 `close` 单次调用均必须有界，不得等待完整帧、完整发送、对端响应或网络状态变化。

以下限制适用于 `C2837xBlock_Run()` 可到达的实例运行期 IoDevice、通道和 HAL 路径。运行期不得包含：

- 毫秒级固定延时；
- 等待 TX 缓冲区清空的循环；
- 等待 `Sn_CR` 清零的长循环；
- 等待 `Sn_SSR` 进入目标状态的长循环；
- 等待 `SEND_OK` 或网络事件完成的内部循环。

必须等待硬件或网络状态的操作，应由通道内部状态跨多次 `C2837xBlock_Run()` 调用推进，并由 CPU Timer 2 超时控制。

`PlatformInit()` 中一次性的 GPIO reset、PLL 稳定或器件数据手册明确要求的初始化等待，可以使用有明确依据且有界的固定延时，但不得在实例运行期重复执行。

### FR-116：close 语义

IoDevice `close` 必须：

- 只处理当前实例通道；
- 可重复调用；
- 单次调用工作量有界；
- 不复位 W5300 芯片；
- 不修改其他 Socket；
- 不等待 TX 缓冲区自然清空；
- 不使用固定延时或内部长轮询。

`close` 必须提供 DONE、BUSY、ERROR 或等价完成语义。建议接口形式为：

```c
int16 (*close)(void *channel);
```

返回值语义：

- `> 0`：DONE，当前 Socket 已确认关闭；
- `0`：BUSY，本次只完成一次有界推进，后续 `Run()` 继续调用 `close`；
- `< 0`：ERROR，关闭失败并进入 FR-266 规定的通道故障终态。

若关闭尚未完成，通道内部保存私有关闭阶段；公共 Core 可先完成协议清理并返回 `WAIT_CONNECTION`，后续轮询继续推进关闭阶段。只有 DONE 后才允许重新执行 TCP `open/listen`。

### FR-117：Core 设备独立性

公共 Core 不得引用 W5300 寄存器、Socket 状态常量或直接调用 W5300 驱动；这些内容只能存在于 W5300 IoDevice/HAL 层。

---

## 10. DSP 共享计时源与超时

### FR-118：共享计时源

第一版固定使用当前 CPU 的 CPU Timer 2，形成所有实例共享的微秒级单调计时源。

### FR-119：Timer 2 模式

Timer 2 采用无中断自由运行方式，不用于算法调度、不触发 `Run()`、不决定采样时间。

### FR-120：用户工程约束

`PlatformInit()` 成功后，用户工程不得停止、重装、重新预分频或复用 CPU Timer 2。App 不提供 Timer 选择控件。

### FR-121：DSP 用户超时宏

每个实例的 `<instance>_user_config.h` 只定义 DSP 通信超时：

```c
#define INTERACTION_TIMEOUT  5000u
#define TRANSFER_TIMEOUT     1000u
```

单位均为毫秒。

### FR-122：用户配置单一事实源

DSP 超时不在 App 中显示，不保存到 `.mat`，不在线缆协商，不进入 Interface Hash。用户配置头是唯一事实源。

### FR-123：超时范围

两个超时必须为正整数，并满足转换到微秒后小于 `0x80000000`。第一版不使用 `0` 表示关闭超时，也不支持无限或小时级等待。

### FR-124：回绕安全

超时判断使用无符号差值：

```c
Uint32 elapsed_us = now_us - start_us;
```

允许 Timer 2 计数自然回绕。

### FR-125：TRANSFER_TIMEOUT

以下阶段使用 `TRANSFER_TIMEOUT`：

- TCP 建立后等待首个 SIM_START 数据；
- 接收当前 Header 或 Payload；
- 发送当前正常或错误响应。

只在 IoDevice 返回正进度时刷新时间戳。

### FR-126：INTERACTION_TIMEOUT

前一完整响应发送完成后，等待下一帧第一个新数据时使用 `INTERACTION_TIMEOUT`。收到首个有效新数据后切换到传输无进度计时。

### FR-127：算法时间

用户 `OnStart`、`OnStep` 和 `OnStop` 执行时间不纳入通信超时，Core 不在回调期间抢占或终止算法。

---

## 11. DSP 非阻塞状态机

### FR-128：公共 Core 通信状态

公共 Core 的最小通信状态为：

```text
WAIT_CONNECTION
RECEIVING
FRAME_READY
SENDING
```

`FRAME_READY` 可以作为一次 `Run()` 内的瞬时处理状态。公共 Core 不增加 W5300 专用的长期 closing/reset/error 状态。

上述限制不禁止 IoDevice 通道内部保存命令、发送、关闭和故障子状态。W5300 通道可以保存私有 `send_pending`、`closing` 或 `faulted` 等等价状态，但不得将 W5300 寄存器或专用状态暴露为公共 Core 状态。

### FR-129：协议阶段

协议阶段至少区分：

```text
WAIT_SIM_START
SIM_RUNNING
```

IoDevice 状态负责连接和收发，协议阶段负责消息顺序、版本、Hash、`step_index` 和算法生命周期。

### FR-130：Run 有界推进

每次 `C2837xBlock_Run(instance)` 只完成当前状态的一次有限工作：

- `WAIT_CONNECTION`：一次 Socket 状态处理；
- `RECEIVING`：一次 `receive`；
- `FRAME_READY`：解析完整帧、校验、调用一次必要回调并构造响应；
- `SENDING`：一次 `send`。

不得在一次 `Run()` 内持续循环等待网络进度。

### FR-131：WAIT_CONNECTION 行为

`WAIT_CONNECTION` 首先处理当前通道未完成的关闭：

- `close == BUSY`：本次只推进一次 `close` 并立即返回，不得执行 `open/listen`；
- `close == DONE`：随后才允许检查 Socket 状态并进入正常打开流程；
- `close == ERROR`：锁存 `C2837X_BLOCK_ERROR_IODEVICE`，进入 FR-266 的当前通道故障终态，不得继续 `open/listen`。

关闭完成后的 W5300 TCP 状态处理按单次推进：

- CLOSED：尝试 open 一次后返回；
- INIT：尝试 listen 一次后返回；
- LISTEN：检查连接一次后返回；
- ESTABLISHED：初始化当前会话接收状态并开始首帧 `TRANSFER_TIMEOUT`。

普通 open/listen 失败可在后续 `Run()` 再试，不增加退避或全局 W5300 重置；已经进入 FR-266 故障终态的通道除外。

### FR-132：FRAME_READY 工作量

完整合法帧可以在一次 `Run()` 中完成解析、输入解包、回调和响应构造。响应发送可以跨多次 `Run()`。

### FR-133：无调度器

公共 Core 不提供优先级、公平性、时间片或按采样时间排序。用户主循环调用顺序就是实例轮询顺序。

---

## 12. 会话、算法生命周期与 step_index

### FR-134：统一清理

所有会话终止路径最终执行统一清理：

- 必要时调用一次 `OnStop()`；
- 关闭当前通道；
- 清除部分 Header/Payload 和发送进度；
- 清除当前会话长度和协议阶段；
- 将强类型输入输出对象清零；
- 保留最近错误；
- 返回 `WAIT_CONNECTION`。

缓冲区内容无需完整清零。

### FR-135：algorithm_started

只有 `OnStart()` 成功后才设置 `algorithm_started = true`。`OnStart()` 失败时不调用 `OnStop()`。

### FR-136：OnStop 统一规则

只要 `algorithm_started == true`，任何导致当前会话终止的路径都必须调用一次且仅一次 `OnStop()`，包括：

- 正常 SIM_STOP；
- OnStep 失败；
- 协议状态、长度、类型或 `step_index` 错误；
- Payload 超限；
- 交互或传输超时；
- 对端断开；
- IoDevice 接收或发送失败；
- 正常响应或错误响应发送失败。

### FR-137：SIM_START 成功边界

合法 SIM_START 通过版本和 Hash 校验后调用 `OnStart()`。`OnStart()` 成功后可以立即标记 `algorithm_started`，但在成功 RESPONSE 完整发送前不得处理 INPUT_DATA，也不得进入 `SIM_RUNNING`；只有成功 RESPONSE 完整发送后才进入 `SIM_RUNNING` 并开始等待 step 0。成功响应发送失败时必须按已启动会话调用一次 `OnStop()`。

### FR-138：OnStep 调用

只有处于 SIM_RUNNING、完整合法 INPUT_DATA 且 `step_index` 等于期望值时，才调用一次 `OnStep()`。

### FR-139：OnStep 失败

`OnStep()` 失败时：

- 不编码正常 OUTPUT_DATA；
- 调用一次 `OnStop()`；
- 能安全响应时尽力发送现有算法错误 RESPONSE；
- 随后关闭并统一清理。

### FR-140：正常 SIM_STOP

运行中收到固定长度合法的 SIM_STOP 时：

- 调用一次 `OnStop()`；
- 不发送 RESPONSE；
- 关闭当前连接；
- 执行统一清理；
- 返回 `WAIT_CONNECTION`。

PC 在 `TERMINATE_TIMEOUT_MS` 内尽力发送完整 SIM_STOP，但不等待 DSP 响应。第一版不复用同一 TCP 连接处理新会话。

### FR-141：step 初值

PC 和 DSP 每个新会话的步骤序号均从 `0` 开始。

### FR-142：PC step 更新

PC 在收到并完整校验匹配的 OUTPUT_DATA 后才递增本地 `step_index`。

### FR-143：DSP step 更新

DSP 在对应 OUTPUT_DATA 完整发送后才递增期望 `step_index`。部分发送期间不得提前递增。

### FR-144：step 异常

重复、跳过或不匹配的 `step_index` 结束当前会话。不重传、不跳步、不接受重复请求。

### FR-145：step 回绕

`step_index` 使用 uint32 自然回绕，第一版不增加回绕协商或特殊错误。

---

## 13. 错误响应与本地诊断

### FR-146：沿用协议错误码

第一版只使用现有协议错误 RESPONSE，不增加 IoDevice、W5300 或本地诊断专用线缆错误码。

### FR-147：可响应错误

连接仍有效且 TX 状态可安全使用时，应尽力发送现有错误 RESPONSE，例如：

- 版本不匹配；
- Hash 不匹配；
- 未知消息类型；
- 固定长度错误；
- 协议状态错误；
- `step_index` 不匹配；
- `OnStart()` 或 `OnStep()` 失败。

### FR-148：不可响应错误

以下情况允许直接关闭：

- 交互或传输超时；
- 对端断开；
- IoDevice 失败；
- Header 未完整获得；
- 声明长度超限且当前连接或 TX 状态无法安全发送错误 RESPONSE；
- 其他 TX 状态不可用情况。

若完整 Header 已获得且 TX 仍可安全使用，声明长度超限应按 FR-071 尽力发送长度错误 RESPONSE，而不是直接关闭。

### FR-149：错误响应非阻塞

错误 RESPONSE 使用与正常发送相同的非阻塞分段发送和 `TRANSFER_TIMEOUT`，不得通过内部持续发送循环阻塞其他实例。

### FR-150：错误优先级

实例应锁存导致会话终止的主要错误。`OnStop()` 本身为 void，不覆盖已经记录的主要错误。

### FR-151：GetLastError

`C2837xBlock_GetLastError()` 只读最近错误，不清除错误、不修改状态机、不访问 W5300。`NULL` 参数返回 `INVALID_ARGUMENT`。

### FR-152：无复杂诊断

第一版不提供错误历史、分类计数、错误时间戳队列、Flash 日志、远程日志、GetState、GetProgress 或强制会话控制 API。

---

## 14. S-Function 结构与调度

### FR-153：实例专用 S-Function

每个实例生成独立的 C MEX S-Function，名称固定为：

```text
<internal_name>_sfun
```

源代码中的 `S_FUNCTION_NAME` 必须与 MEX 基名一致。

### FR-154：自包含目录

每个实例 S-Function 目录自包含：

- S-Function 主体；
- 强类型 I/O 编解码；
- PC Socket；
- V1 协议副本；
- 自动配置头；
- 用户配置头；
- 构建脚本。

不同实例不依赖输出根目录中的共享 PC 运行库。

### FR-155：固定离散采样

每个实例使用 App 配置的有限正数固定离散采样时间，Offset 固定为 0。不支持 continuous、inherited 或 variable sample time。

### FR-156：DSP 不使用采样时间

采样时间只用于 S-Function 调度，不发送给 DSP、不进入 Hash，DSP 不运行周期定时器或丢步补偿。

### FR-157：直接馈通

全部输入端口设置为 direct feedthrough。模型存在代数环时，由用户在模型中显式加入 Unit Delay、Memory 或其他设计所需延迟。

### FR-158：端口映射

每个 App 输入变量生成一个输入端口，每个输出变量生成一个输出端口。端口顺序、类型和宽度与变量表一一对应。

### FR-159：无 Block 参数

S-Function 不提供对话框参数。IP、端口、Hash、I/O、采样时间、最大载荷和超时均编译进生成文件或用户配置头。配置变化后需要重新生成，影响 MEX 的变化需要重新编译。

### FR-160：一次采样一次 OnStep

每次 `mdlOutputs()` 固定执行：

```text
读取全部输入
→ 打包 INPUT_DATA
→ 发送当前 step_index
→ 等待对应 OUTPUT_DATA
→ 完整校验
→ 原子更新全部输出
→ step_index + 1
```

不得合并、跳过、重复或后台预计算步骤。

### FR-161：PC 步骤响应分支与输出原子更新

PC 收到完整步骤响应帧后，必须按以下顺序处理：

```text
接收完整帧
→ 校验 Header 和声明长度
→ 判断消息类型
   ├─ RESPONSE：校验 RESPONSE 固定长度并解析错误码，按错误终止
   └─ OUTPUT_DATA：校验固定长度和 step_index
→ 将全部输出字段解码到 PC 临时输出对象或等价临时缓冲区
→ 所有字段解码成功
→ 一次性提交全部 Simulink 输出端口
→ step_index + 1
```

`OUTPUT_DATA` 本身不包含协议错误码，错误码只从独立 RESPONSE Payload 解析。

在消息类型错误、长度错误、`step_index` 错误、截断、字段解码失败或 RESPONSE(error) 时，不得修改任何 Simulink 输出端口。

### FR-162：mdlStart

`mdlStart()` 依次：

```text
创建 PC 实例上下文
→ 建立 TCP 连接
→ 发送 SIM_START
→ 等待成功 RESPONSE
→ step_index = 0
```

失败时关闭 Socket、释放上下文并设置明确 Simulink error status。

### FR-163：mdlTerminate

正常停止且连接仍有效时，在终止超时内尽力发送一次 SIM_STOP，不等待额外响应，随后关闭和释放。此前已异常关闭时不得重新连接或再次发送。

### FR-164：Normal mode

第一版只保证 MATLAB/Simulink 桌面 Normal mode。不承诺 Accelerator、Rapid Accelerator、Fast Restart、代码生成、模型引用部署、实时目标、并行仿真或 TLC 内联。

### FR-165：墙钟实时性

S-Function 在 `mdlOutputs()` 内同步等待 DSP，仿真速度受网络、DSP 轮询、用户算法和 MATLAB 调度影响。采样时间表示仿真时间，不保证同等墙钟周期。

---

## 15. PC 超时与错误处理

### FR-166：PC 用户配置

每个实例的 `<instance>_sfun_user_config.h` 只定义：

```c
#define CONNECT_TIMEOUT_MS     5000u
#define STEP_TIMEOUT_MS        1000u
#define TERMINATE_TIMEOUT_MS    200u
```

### FR-167：PC 超时归属

PC 超时不在 App 中显示、不保存到 `.mat`、不进入 Hash、不与 DSP 协商。PC 与 DSP 超时相互独立，用户配置头是 PC 超时的唯一事实源。

### FR-168：CONNECT_TIMEOUT

只用于 `mdlStart()` 的 TCP 建连阶段。

### FR-169：STEP_TIMEOUT

同时用于：

- SIM_START 发送和等待启动 RESPONSE；
- 每次 INPUT_DATA 发送和 OUTPUT_DATA 接收。

第一版不再拆分发送和接收超时。

### FR-170：TERMINATE_TIMEOUT

只用于正常 `mdlTerminate()` 尽力发送 SIM_STOP。

### FR-171：PC 失败策略

PC 超时、Socket 错误、协议错误、DSP RESPONSE(error)、长度错误或 `step_index` 错误时：

- 关闭连接；
- 不更新输出；
- 设置 `ssSetErrorStatus()`；
- 停止当前仿真；
- 不自动重连、重试、重发或跳步。

### FR-172：错误文本

S-Function 错误信息在可获得时包含：

- 实例/S-Function 名称；
- 当前阶段；
- 当前 `step_index`；
- expected/actual 消息类型、长度和 step；
- DSP 协议错误码；
- 本地 Socket/OS 错误。

---

## 16. 算法文件模式

### FR-173：三种模式

实例算法文件固定为三种模式：

```text
generated_example
external_copy
external_reference
```

### FR-174：generated_example

若目标算法实现文件不存在，生成完整可编译示例：

```text
src/<internal_name>_algorithm.c
```

该文件属于用户可编辑文件。

### FR-175：external_copy

App 在生成时读取外部源文件，并将其内容复制为：

```text
src/<internal_name>_algorithm.c
```

复制内容保持源文件字节，不自动重写函数名、Include 或代码格式。目标文件按用户文件保护规则处理。

### FR-176：external_reference

App 不生成算法 `.c`，用户自行将外部源文件加入 CCS 工程。生成结果和文档必须提示该文件不在输出文件列表中。

### FR-177：外部文件校验

第一版外部算法实现文件只允许扩展名：

```text
.c
```

App 应检查：

- 路径存在；
- 可读；
- 是普通文件；
- 扩展名为 `.c`，大小写按当前平台文件系统规则比较；
- 预览和生成时内容可获取。

算法头文件由用户通过源文件 `#include` 和 CCS Include Path 管理，不作为外部算法实现文件选择对象。App 不进行完整 C 语法或回调符号解析。

### FR-178：外部文件快照

预览后外部源文件内容发生变化，候选快照必须失效并要求重新预览。

---

## 17. DSP 输出文件结构

### FR-179：DSP 根目录

DSP 输出固定为：

```text
<dsp_root>/
├─ inc/
└─ src/
```

### FR-180：公共文件

公共文件至少包括并沿用仓库现有 W5300 文件名：

```text
inc/c2837x_block.h
inc/c2837x_block_protocol.h
inc/c2837x_block_iodevice.h
inc/<existing_w5300_headers>

src/c2837x_block.c
src/c2837x_block_protocol.c
src/c2837x_block_internal.h
src/<existing_w5300_sources>
```

不创建第二套近义 W5300 文件名。

### FR-181：项目级文件

项目级生成：

```text
inc/c2837x_block_project.h
src/c2837x_block_project.c
```

用于统一导出有效实例并定义静态绑定。

### FR-182：实例文件

每个实例生成：

```text
inc/<instance>_config.h
inc/<instance>_user_config.h
inc/<instance>_algorithm.h
src/<instance>_config.c
src/<instance>_io.c
src/<instance>_algorithm.c
```

最后一项根据算法文件模式可能由示例生成、外部复制或不生成。

### FR-183：文件职责

- `<instance>_algorithm.h`：强类型结构和回调声明的唯一权威；
- `<instance>_algorithm.c`：用户算法实现；
- `<instance>_config.h/.c`：尺寸、Hash、适配器、静态绑定；
- `<instance>_io.c`：实例序列化和 IoDevice 通道绑定；
- `c2837x_block_project.*`：实例导出与项目级公共配置。

### FR-184：无旧单例文件

新生成结构不得输出旧单例配置、旧全局输入输出、旧通用 S-Function 或旧无参数 `Init/Run` 兼容文件。

---

## 18. S-Function 输出结构与构建

### FR-185：实例目录

每个实例输出到：

```text
<sfun_root>/<internal_name>/
```

至少包含：

```text
<instance>_sfun.c
<instance>_sfun.h
<instance>_sfun_io.c
<instance>_sfun_config.h
<instance>_sfun_user_config.h
<instance>_pc_socket.c
<instance>_pc_socket.h
<instance>_protocol.c
<instance>_protocol.h
build_<instance>_sfun.m
```

### FR-186：唯一符号

S-Function 目录内的文件名、非静态符号和宏均使用实例前缀，避免不同 MEX 构建或加载时冲突。

### FR-187：独立构建脚本

每个构建脚本只构建当前实例，显式列出源文件，不使用 `dir('*.c')` 自动纳入目录中的其他文件。

### FR-188：任意当前目录执行

构建脚本通过 `mfilename('fullpath')` 确定 `script_dir`，可从任意 MATLAB 当前目录执行，不永久修改当前目录、MATLAB Path 或环境变量。

### FR-189：构建前检查

调用 `mex` 前检查：

- 必需 `.c/.h` 存在；
- `script_dir` 可写；
- `mex` 可用；
- 当前目标 MEX 未被加载或占用。

失败时不删除旧 MEX。

### FR-190：开始重建

完成前置检查后：

```text
尝试卸载当前实例 MEX
→ 删除旧目标 MEX
→ 调用 mex 构建
```

旧 MEX 无法卸载或删除时立即终止并提示停止仿真。

### FR-191：构建失败不回退

正式开始重建后，构建失败时不恢复旧 MEX、不保存备份、不使用上一次成功版本，避免新源码与旧二进制混用。

### FR-192：MEX 输出

MEX 只输出到 `script_dir`，名称：

```text
<internal_name>_sfun.<mexext>
```

不自动复制、添加路径、修改模型或创建库。

### FR-193：构建成功信息

构建成功至少输出：

- MEX 名称；
- MEX 路径；
- Protocol Version；
- Interface Hash。

### FR-194：MEX 非 App 生成事务

App 只生成源码和构建脚本，不自动构建、比较、删除或管理 MEX。项目 `.mat` 不保存 MEX 构建状态。

---

## 19. 输出路径与文本规范

### FR-195：绝对输出路径

`dsp_root` 和 `sfun_root` 保存规范化绝对路径。第一版不支持相对项目路径、环境变量或占位符。加载项目时路径可以暂时不存在，直到预览或生成时才进行严格可访问性和类型检查。

### FR-196：独立目录树

两个输出根目录不得相同，也不得互相包含。

### FR-197：路径规范化

冲突检查前应处理：

- 绝对化；
- `.` 和 `..`；
- 尾部分隔符；
- Windows `/` 和 `\`；
- Windows 大小写不敏感比较。

### FR-198：目录不存在

目标目录可以尚不存在，预览显示“将创建”。生成时按需创建 `inc`、`src` 和实例目录。

### FR-199：文件目录冲突

目标路径或必需子路径已存在但类型不正确、候选文件映射到同一路径、仅大小写不同或文件与目录冲突时，写入前终止。

### FR-200：跨项目目录

不同项目可以人为使用同一输出目录，但 App 不自动隔离或识别所有权，只提示已有生成文件风险。

### FR-201：无 manifest

第一版不生成 `manifest.json`、owner 文件或历史生成清单。文件状态只比较当前候选内容与当前目标内容。

### FR-202：确定性文本

相同配置、相同模板和相同生成器版本必须产生逐字节一致的文本，不受时间、用户、计算机、当前目录、区域设置、实例选中状态或随机数影响。

### FR-203：编码和换行

由生成器模板产生的全部文本采用：

```text
UTF-8，无 BOM
LF
```

文件末尾恰好有换行，不写行尾空格和动态时间戳。`external_copy` 属于用户外部文件复制，不是模板生成文本，按 FR-175 保持源文件字节不变；已经存在且选择 Keep 的用户文件也不做编码或换行转换。

### FR-204：文件头

自动生成文件标记：

```text
AUTO-GENERATED FILE
Manual changes will be overwritten.
```

公共 Core 标记为 DSP-SimBridge core source。用户文件标记为 USER-EDITABLE FILE。自动生成头文件和用户配置头的 Include Guard 必须由内部名称和文件职责确定性生成，使用大写 ASCII、数字和下划线，项目内唯一且不依赖绝对路径。

### FR-205：无外部格式化

生成器直接产生最终格式，不调用 clang-format、编辑器格式化器、Git Hook 或外部脚本二次处理。

---

## 20. App 校验、预览与安全写入

### FR-206：即时校验

编辑期间执行轻量即时校验，包括名称、重复资源、数值范围、类型、维度、Payload 和明显路径冲突。即时校验不写磁盘、不连续弹出模态对话框。

### FR-207：完整校验

点击预览时执行完整校验，包括：

- 项目结构；
- 实例资源唯一性；
- 网络参数；
- I/O 和 Payload；
- Hash；
- 外部算法文件；
- 输出路径；
- 候选文件目标冲突；
- 模板可用性。

### FR-208：问题等级

校验问题分为：

- Error：阻止预览或生成；
- Warning：允许继续；
- Information：说明状态或后续动作。

问题集中显示，支持定位到实例、字段或文件。

### FR-209：预览不写盘

预览只执行：

```text
收集当前配置
→ 完整校验
→ 生成候选内容
→ 比较目标文件
→ 显示候选文件表
```

不得创建目录、写临时文件、复制算法、保存项目、构建 MEX、执行 `cd/addpath/savepath` 或永久修改 MATLAB 当前目录和搜索路径。

### FR-210：候选文件类别

候选文件分为：

1. 自动生成文件；
2. 公共 Core 文件；
3. 用户文件。

### FR-211：候选状态

- 不存在：固定为 Create；
- 内容相同：固定为 Skip，不更新时间戳；
- 自动生成/Core 内容不同：必须 Replace；
- 用户文件内容不同：默认 Keep，可选择 Replace。

### FR-212：强制项

自动生成文件或 Core 文件内容不同但未选择替换时，禁止执行生成并提示重新选择。该检查发生在候选表建立后，不属于预览前配置错误。

### FR-213：用户文件保护

用户配置头和算法实现内容不同时默认保留。App 不进行三方合并，也不自动把新模板片段插入旧用户文件。用户对 Keep/Replace 的选择只对当前预览有效，不保存到项目 `.mat`。

### FR-214：预览快照

候选表绑定当前会话快照，至少覆盖：

- 当前项目配置；
- Interface Hash 规范；
- 外部算法源文件内容；
- 公共 Core 和生成器模板内容；
- 目标文件内容或摘要；
- 输出路径。

任何影响候选结果的变化都使预览失效。

### FR-215：生成前复核

点击生成时重新检查：

- 快照仍有效；
- 路径仍可访问；
- 外部源仍可读且内容未变；
- 强制项均允许替换；
- 目标文件未在预览后被外部修改。

不满足时终止并要求重新预览。

### FR-216：写入策略

全部校验和候选生成完成后，文本文件先写临时文件，再替换目标文件。第一版不承诺跨所有文件的复杂全局事务或完整回滚。

### FR-217：失败报告

写入失败时必须说明阶段，并列出已经成功提交和尚未提交的文件，不得在未实际回滚时声称整个生成已回滚。

### FR-218：成功汇总

生成成功后集中显示：

- 新建；
- 替换；
- 相同并跳过；
- 用户选择保留；
- DSP/S-Function 输出路径；
- 各实例构建脚本；
- 需重新构建的 MEX；
- 已知旧实例文件提示。

---

## 21. 用户可编辑边界

### FR-219：DSP 用户文件

用户可编辑：

```text
<instance>_user_config.h
<instance>_algorithm.c
用户 main.c
用户 CCS 工程配置
```

### FR-220：PC 用户文件

用户可编辑：

```text
<instance>_sfun_user_config.h
```

### FR-221：禁止手改的生成文件

用户不应编辑：

- `<instance>_algorithm.h`；
- `<instance>_config.h/.c`；
- `<instance>_io.c`；
- 项目级实例文件；
- S-Function 主体、I/O、Socket 和协议文件；
- 自动配置头；
- 构建脚本；
- Interface Hash 和尺寸定义。

### FR-222：用户配置职责

DSP 用户配置头只承载两个 DSP 超时宏；PC 用户配置头只承载三个 PC 超时宏。自动配置头负责默认值、Include 和编译期范围检查。

### FR-223：公共 Core 修改

公共 Core 需要修改时应在 DSP-SimBridge 源仓库统一维护，不应只修改某个生成目录副本。Core 内容不同属于强制替换项。

---

## 22. 旧架构迁移与兼容边界

### FR-224：以现有仓库改造

开发优先复用现有协议定义、帧构造解析、W5300 HAL/Socket、非阻塞收发和 S-Function 生命周期代码。除非无法满足冻结需求，不得无理由整体重写。

`spec_v2_3.md` 仅可作为历史单实例资料保留，不是当前协议或实现事实源。现有 V1 协议事实只能依据 FR-015 指定的协议头文件和对应实现确认。

### FR-225：显式多实例 API

旧无参数：

```c
C2837xBlock_Init();
C2837xBlock_Run();
```

退出第一版，不保留默认实例或宏映射兼容层。

### FR-226：删除单例状态

现有全局 `g_ctx`、全局协议阶段、全局步骤、全局缓冲区和全局算法启动状态必须迁移到实例对象。只允许真正共享的平台资源保持项目级。

### FR-227：不保留旧运行文件

旧单实例配置、旧全局输入输出、旧通用 MEX 和旧单实例 API 文件不再生成。用户必须从 CCS 工程和 MATLAB 路径中移除。

### FR-228：协议兼容不等于源码兼容

第一版保持 V1 wire 协议，但 DSP C API、项目格式、生成目录、MEX 名称和二进制不兼容旧单实例架构，必须重新生成和编译。

### FR-229：禁止混合编译

不得同时编译新旧 `c2837x_block.c`、新旧配置、旧通用 S-Function 和新实例 S-Function。Core API Version 和重复符号应尽可能让错误组合在编译期失败。

---

## 23. CCS 与 Simulink 集成边界

### FR-230：不生成 CCS 工程

第一版不生成：

- `.project`、`.cproject`；
- build configuration；
- linker command file；
- Flash/RAM 切换；
- GEL；
- 启动代码；
- 中断向量表。

### FR-231：CCS 集成要求

文档要求用户：

- 将 `<dsp_root>/inc` 加入 include path；
- 加入公共、项目级和有效实例 `.c`；
- 每个 `.c` 只编译一次；
- 不使用 `#include "*.c"`；
- 移除旧单实例文件；
- 选择与 App 一致的 ABI；
- 确认 CPU Timer 2 未占用；
- 确认 W5300 HAL 对应实际硬件；
- 实现全部回调；
- 持续轮询全部启用实例。

### FR-232：Simulink 集成

文档说明用户：

1. 运行实例构建脚本；
2. 使实例目录可被 MATLAB 查找；
3. 放置普通 S-Function Block；
4. 填写 `<internal_name>_sfun`；
5. 按生成端口顺序连接；
6. 使用 Normal mode；
7. 正常停止仿真。

第一版 PC/Simulink 版本基线与当前仓库一致：MATLAB/Simulink R2024b 或更高版本。第一版不额外承诺更早 MATLAB 版本。MEX 编译器应为该 MATLAB 安装支持的编译器，具体使用环境按当前仓库构建方式执行。

第一版可提供示范模型，但不为每个项目自动生成 `.slx`。

---

## 24. 测试、验收与责任边界

### FR-233：交付方测试责任

交付方负责：

- App 功能和配置校验；
- 确定性生成；
- Hash/CRC32 黄金向量；
- 候选文件保护和写入；
- PC 端源码生成；
- 每实例 MEX 构建脚本；
- 可执行的 PC 协议和错误路径测试；
- DSP 集成与测试方案；
- 根据用户日志修正生成器、Core 和协议代码问题。

### FR-234：用户测试责任

用户负责：

- CCS 工程集成；
- EABI/COFF 编译；
- 底层初始化和链接配置；
- 烧录 TMS320F28377D；
- W5300 实机；
- 单实例和双实例联机；
- 协议错误、超时、断线和重连；
- 提交编译日志和验收记录。

DSP 侧 CCS、C2000 Compiler 及其他相关软件版本不作为第一版固定需求，也不建立固定版本矩阵。用户可使用其现有开发环境；兼容性以实际编译和实机测试结果为准，并在问题反馈和验收记录中记录实际版本。

### FR-235：无证据不得宣称通过

未经用户提供实际 DSP 编译或实机证据的功能只能标记为：

```text
已实现，待用户编译或实机验证
```

不得标记为已通过硬件测试。

### FR-236：确定性生成验收

同一项目连续预览/生成且配置、模板和外部文件未变化时：

- 自动生成文件全部相同；
- Hash 不变；
- 用户文件默认保留；
- 不出现动态时间戳差异。

### FR-237：配置错误验收

至少验证以下错误在写入前发现：

- 内部名称重复或仅大小写冲突；
- Socket/端口重复；
- 非法网络参数；
- 非法变量名称、类型或维度；
- Payload 超限；
- 输出目录冲突；
- 外部算法不存在；
- 候选路径冲突；
- 强制替换项未允许。

### FR-238：DSP 用户验收范围

用户测试方案覆盖：

- EABI/COFF 编译；
- 六种数据类型；
- 单实例正常启动、步骤、停止和再次连接；
- 双实例独立连接和运行；
- 版本/Hash/长度/type/step 错误；
- 首帧、交互和分段传输超时；
- 断线、IoDevice 收发失败；
- 接近最大合法 Payload；
- 其他实例不受局部错误影响。

### FR-239：输出原子性测试

PC 测试必须验证错误长度、错误 step、截断或 RESPONSE(error) 时不更新任何部分输出。

### FR-240：无复杂硬件自动化平台

第一版允许 MATLAB 脚本、Mock endpoint、手工 Simulink 模型、CCS 日志、断点记录和抓包，不要求 CI 自动烧录、自动操作 GUI 或无人值守硬件矩阵。

### FR-241：问题反馈模板

用户问题反馈至少包含：

- App/DSP-SimBridge 版本；
- 项目配置或 `.mat`；
- 生成文件列表；
- CCS 和编译器版本；
- ABI；
- 完整错误和警告；
- `main.c` 初始化/轮询；
- Simulink 错误；
- 复现步骤；
- 必要 Socket 状态、断点或抓包。

---

## 25. 第一版交付物

### FR-242：完整交付物

第一版交付：

1. MATLAB App 和项目管理源码；
2. DSP 公共 Core 和生成模板；
3. 每实例 S-Function 源码模板与构建脚本；
4. 集成、迁移、使用、测试和反馈文档。

### FR-243：源码交付

不得只交付 MEX 或其他二进制替代源码。MEX 不保证跨操作系统、MATLAB 版本、CPU 架构或编译器直接复用。

### FR-244：不要求正式发布包

第一版不要求 installer、`.mltbx`、release.zip、签名或 checksum 管理系统。

### FR-245：DSP 实机结论

DSP 实机最终验收以用户依据文档执行并提交的测试记录为准。

---

## 26. 实施阶段与一致性门禁

### FR-246：五阶段实施

第一版按以下五阶段实施：

1. **App 项目模型与生成框架**；
2. **DSP 公共 Core 多实例化**；
3. **实例 DSP 代码生成**；
4. **独立 S-Function**；
5. **文档与验收材料**。

### FR-247：阶段1——App 项目模型与生成框架

阶段1包括：

- App 多实例界面；
- `project` 结构、保存、加载和迁移；
- 实例操作；
- dirty 状态；
- 即时和完整校验；
- Hash；
- 候选文件生成、比较和快照；
- 用户文件保护；
- 安全写入和结果汇总。

阶段1使用内部固定候选文件夹具验证候选构建、比较、快照和提交事务，不要求提前实现阶段2～4的完整 Core、实例生成器或 S-Function 模板。

门禁至少确认项目往返保存、旧配置迁移、Hash 确定性、预览不写盘、用户文件保护、路径冲突、外部变化失效，以及 FR-267 规定的职责分离和独立测试边界。

### FR-248：阶段2——DSP 公共 Core 多实例化

阶段2包括：

- 不透明实例；
- 显式多实例 API；
- 删除单例状态；
- IoDevice；
- W5300 通道；
- 非阻塞状态机；
- W5300 Erratum 1 非阻塞关闭；
- 非阻塞 `Sn_CR` 命令发出和完成检查；
- FR-265 规定的 SEND 完成语义；
- FR-266 规定的关闭结果和通道故障终态；
- Timer 2；
- DSP 超时；
- 最近错误；
- Core API Version。

阶段2使用手写静态双实例配置夹具验证公共 Core，不要求提前实现阶段3的正式实例生成器。

阶段2门禁至少确认：

- 所有会话状态属于实例；
- 公共 Core 不直接依赖 W5300 寄存器和状态常量；
- `open/listen/receive/send/close` 的运行期路径不包含固定延时或等待网络状态的长循环；
- W5300 `/RESET` 低电平宽度和解除复位后的稳定等待已经按数据手册复核；
- `TIMER_INIT`、`W5300_INIT`、`W5300_MEMORY`、`NETWORK_CONFIG` 各自具有唯一且明确的检测点；
- SEND 正进度只在对应分段获得 `SEND_OK` 后提交给 Core；
- Erratum 1 处理可跨多次 `Run()` 推进，不阻塞其他实例；
- 关闭 BUSY/DONE/ERROR 语义和故障终态已覆盖；
- DSP 端无动态内存；
- 旧单例 API 和全局 `g_ctx` 已退出。

门禁以源码审核为主，DSP 编译由用户后续执行。

### FR-249：阶段3——实例 DSP 代码生成

阶段3包括：

- 项目级实例导出；
- 实例配置和用户配置；
- 强类型结构；
- 算法接口和适配器；
- 序列化；
- RX/TX word 缓冲区；
- Socket 通道绑定；
- 类型、尺寸、超时和版本编译检查。

阶段3将正式实例生成器接入阶段1已经验证的候选、比较、快照和提交框架，不通过伪造完整后续模板来满足阶段1或阶段2门禁。

### FR-250：阶段4——独立 S-Function

阶段4包括：

- 实例目录；
- 唯一模块名；
- 端口；
- 同步交互；
- PC 超时；
- 原子输出；
- 独立协议/Socket；
- 自包含构建脚本。

交付方至少完成 PC 可执行构建和错误路径验证。

### FR-251：阶段5——文档与验收材料

阶段5包括：

- App 使用；
- 迁移说明；
- CCS 集成；
- 双实例 main 示例；
- Simulink 使用；
- 用户编辑范围；
- EABI/COFF 检查项；
- 正常和异常测试步骤；
- 反馈模板；
- 验收记录模板。

### FR-252：阶段门禁

每阶段通过对应一致性门禁后再进入下一阶段。发现前置阶段问题时回退修正，不通过临时兼容层掩盖。

### FR-253：阶段状态标记

阶段报告状态至少区分：

- 未开始；
- 已实现待审核；
- 已通过静态审核；
- 已通过 PC 测试；
- 待用户 DSP 编译；
- 待用户实机验证；
- 已通过用户验证；
- 阻断；
- 废弃。

---

## 27. 需求冻结与变更控制

### FR-254：唯一基线

本文件是第一版唯一需求事实源。实现不得引用或恢复错误旧需求文件中的运行时 IoDevice 注入、无 DSP timeout、SCI 首版或旧单例设计。

### FR-255：稳定编号

本文件的 FR 编号进入开发后保持稳定。删除需求时保留编号并标记废弃；新增需求使用新编号，不通过修改旧条目含义隐藏变更。

### FR-256：需求优先级

冻结需求与旧代码、旧文档或早期草案冲突时，以本文件为准。

### FR-257：关键缺口处理

实现发现以下情况时，应暂停相关外部行为决定并提交：

- 涉及需求编号；
- 现有事实；
- 冲突或缺口；
- 影响范围；
- 可选方案；
- 推荐方案。

用户确认前不得自行改变协议、文件归属、公共 API、配置结构或用户可见行为。

### FR-258：禁止范围膨胀

第一版不得“顺便实现”已排除的设备、动态实例、异步通信、版本协商、自动恢复、CCS 工程生成、安装包或复杂自动测试。

### FR-259：需求追踪

每阶段交付应提供：

| 需求编号 | 实现文件 | 状态 | 验证方式 | 备注 |
|---|---|---|---|---|

实现、审核、测试和修复均通过 FR 编号追踪。

### FR-260：禁止伪完成

尚未实现的协议、IoDevice、序列化和超时路径不得以空函数或固定成功返回伪装完成。未实现路径必须明确报错或在阶段报告中标记。

### FR-261：变更记录

冻结后确需修改需求时，应记录：

- 变更编号和日期；
- 涉及 FR；
- 原规则和新规则；
- 原因；
- 影响文件；
- 是否重新生成；
- 是否需要用户重新测试。

---

## 28. 计划前仓库整理与 W5300 特殊约束

### FR-262：阶段0——仓库基线整理

正式五阶段实施前，执行不属于产品交付阶段的“阶段0”：

- 将正式需求保存为仓库唯一当前需求入口：`requirements/requirements_multi_iodevice_v1.0_frozen_rev2.md`；
- 删除错误文件 `requirements_multi_iodevice (1).md`；
- 删除旧 `plan.md`，不得在其基础上增量修改；
- `spec_v2_3.md` 删除或在文件首部标记 `DEPRECATED / HISTORICAL`；
- README、Codex 指令、审核报告和测试记录不得继续把 `spec_v2_3.md` 或旧 `plan.md` 标记为当前规范；
- README 在阶段0至少标明现有内容描述旧单实例实现，阶段5再按实际新实现整体重写；
- 将旧 V1 协议基线固定为提交 `f209302ce3efc0fa15d217550f6d9b1dc00487fb`，可建立只读 tag `legacy-v1-protocol-baseline`；
- 建立以 FR 编号为主键的需求追踪矩阵骨架；
- 根据本冻结需求从零生成新的 `plan.md`。

阶段0完成后，Codex 不得在无说明的情况下同时读取新旧冲突需求。

### FR-263：W5300 Erratum 1 触发条件和处理目标

当当前 Socket 处于 TCP 模式，且关闭时检测到：

```text
Sn_TX_FSR != 当前 Socket 配置的 TX 总容量
```

视为可能存在未完成发送，应执行 W5300 Erratum 1 workaround。

第一版不得通过等待 TX 缓冲区自然清空或固定延时解决。处理目标为：

```text
同一 Socket 临时切换为 UDP
→ 向 0.0.0.1 的固定内部端口发送 1 个 dummy wire octet
→ 关闭该 Socket
```

dummy 目标端口是 W5300 通道内部常量，不进入 App、项目配置、Interface Hash 或用户 TCP 端口冲突检查。

### FR-264：W5300 Erratum 1 非阻塞关闭阶段

Erratum 1 workaround 必须由当前实例 W5300 通道内部状态跨多次轮询推进，至少具有等价阶段：

```text
检查是否需要 Erratum
→ 发出 UDP OPEN
→ 后续轮询确认命令完成和 SOCK_UDP
→ 发出 1 octet dummy SEND
→ 后续轮询确认 SEND_OK 或 TIMEOUT
→ 发出 CLOSE
→ 后续轮询确认 SOCK_CLOSED
```

每次调用只允许：

- 发出一次命令；
- 或读取一次完成状态；
- 或推进一个有界阶段。

底层命令接口应提供“只写一次命令”和“只读一次是否完成”的等价能力，不得在函数内部等待 `Sn_CR`、`Sn_SSR`、`SEND_OK` 或 TX 空闲。

Erratum 关闭过程使用 CPU Timer 2 的传输超时或等价有界超时。无论 dummy SEND 得到 `SEND_OK` 还是 `TIMEOUT`，均继续进入 CLOSE；关闭过程通过 FR-116 和 FR-266 的 BUSY/DONE/ERROR 语义向上层报告，关闭完成前不得重新 OPEN/LISTEN 当前 Socket。


---

### FR-265：W5300 SEND 完成语义

W5300 `send()` 对一个发送分段保存私有 pending 状态，并采用以下唯一完成语义：

1. 当前没有 pending 发送时：
   - 清除与本次发送相关的旧 `SEND_OK/TIMEOUT`；
   - 向 TX FIFO 写入一个有界分段；
   - 写入发送长度；
   - 只发出一次 SEND 命令；
   - 保存 `pending_octets`；
   - 本次向公共 Core 返回 `0`。
2. 后续调用中：
   - `Sn_CR` 尚未完成时返回 `0`；
   - `Sn_CR` 已完成但尚无 `SEND_OK/TIMEOUT` 时返回 `0`；
   - 获得对应 `SEND_OK` 后，清除中断和 pending 状态，并返回 `pending_octets`；
   - 获得 `TIMEOUT`、Socket 失效或命令失败时返回负值。

Pending 期间不得重复写入同一分段或重复发出 SEND。公共 Core 在 `send()` 返回正值前不得移动发送偏移，累计正进度达到完整帧长度后，才允许执行成功握手完成、`step_index` 递增或错误响应后的关闭动作。

`SEND_OK` 只表示 W5300 SEND 命令完成，不表示对端应用已经处理该数据。

### FR-266：W5300 通道关闭故障终态

W5300 通道 `close()` 返回 ERROR 时：

- 当前实例记录 `C2837X_BLOCK_ERROR_IODEVICE`；
- 不复位整个 W5300；
- 不修改或阻塞其他 Socket 和实例；
- 不进行无限关闭重试；
- 当前 Socket 进入私有 `faulted` 或等价故障终态；
- 在下一次成功执行 `PlatformInit()` 或 DSP 复位前，不得对该 Socket 重新执行 `open/listen`。

公共 Core 仍保持 `WAIT_CONNECTION` 等通用状态，不增加 W5300 专用公共故障状态。`GetLastError()` 可用于读取该实例错误。

### FR-267：阶段1 App 职责分离门禁

阶段1必须使以下职责具有清晰且可独立测试的边界：

- 项目模型；
- 项目迁移；
- 配置校验；
- Interface Hash；
- 候选文件构建；
- 文件比较；
- 预览快照；
- 文件提交；
- App UI 协调。

不强制将其实现为九个类、九个文件或固定目录结构，但 App UI 回调不得继续直接承担全部项目模型、Hash、候选生成、比较和磁盘写入逻辑。

至少应能够绕过 UI，独立测试项目迁移、校验、Hash、候选比较、快照失效和提交行为。

---

## 附录 A：推荐项目结构

```matlab
project = struct( ...
    'format_version', uint16(2), ...
    'common', struct( ...
        'dsp_model', 'TMS320F28377D', ...
        'protocol_version', uint16(1), ...
        'abi', 'eabi', ...
        'network', struct( ...
            'mac', [], ...
            'ip', '', ...
            'gateway', '', ...
            'subnet', '')), ...
    'instances', [], ...
    'output', struct( ...
        'dsp_root', '', ...
        'sfun_root', ''));
```

实例示意：

```matlab
instance = struct( ...
    'display_name', '', ...
    'internal_name', '', ...
    'iodevice', struct( ...
        'type', 'w5300_tcp', ...
        'socket_number', uint16(0), ...
        'tcp_port', uint16(5000)), ...
    'sample_time_sec', 1e-4, ...
    'max_payload_size_bytes', uint32(1024), ...
    'inputs', [], ...
    'outputs', [], ...
    'algorithm', struct( ...
        'mode', 'generated_example', ...
        'source_path', ''), ...
    'interface_hash', uint32(0));
```

---

## 附录 B：DSP 输出示意

```text
<dsp_root>/
├─ inc/
│  ├─ c2837x_block.h
│  ├─ c2837x_block_protocol.h
│  ├─ c2837x_block_iodevice.h
│  ├─ c2837x_block_project.h
│  ├─ <existing_w5300_headers>
│  ├─ current_loop_config.h
│  ├─ current_loop_user_config.h
│  └─ current_loop_algorithm.h
└─ src/
   ├─ c2837x_block.c
   ├─ c2837x_block_protocol.c
   ├─ c2837x_block_internal.h
   ├─ c2837x_block_project.c
   ├─ <existing_w5300_sources>
   ├─ current_loop_config.c
   ├─ current_loop_io.c
   └─ current_loop_algorithm.c
```

---

## 附录 C：S-Function 输出示意

```text
<sfun_root>/
└─ current_loop/
   ├─ current_loop_sfun.c
   ├─ current_loop_sfun.h
   ├─ current_loop_sfun_io.c
   ├─ current_loop_sfun_config.h
   ├─ current_loop_sfun_user_config.h
   ├─ current_loop_pc_socket.c
   ├─ current_loop_pc_socket.h
   ├─ current_loop_protocol.c
   ├─ current_loop_protocol.h
   └─ build_current_loop_sfun.m
```

---

## 附录 D：固定术语

| 术语 | 固定含义 |
|---|---|
| wire octet | 8-bit 线缆单位 |
| C28x word | 16-bit DSP 存储/寻址单位 |
| Payload | 不含 4 wire octet Header 的协议载荷 |
| frame buffer | Header + 最大合法 Payload 对应的 DSP word 存储 |
| W5300 8 KB | W5300 内部 8-bit 字节容量 |
| Interface Hash | 当前实例线缆接口的 CRC32 |
| Core API Version | DSP Core 与生成代码的编译接口版本 |
| project format version | `.mat` 项目结构版本 |
| protocol version | DSP—PC wire 协议版本 |

---

## 附录 E：Rev.1 → Rev.2 变更记录

| 变更编号 | 日期 | 涉及 FR | 原规则 | 新规则 | 原因 | 重新生成 | 重新测试 |
|---|---|---|---|---|---|---|---|
| CHG-R2-001 | 2026-07-19 | FR-110、FR-115、FR-248 | 固定延时限制未区分初始化期和运行期 | 允许 `PlatformInit()` 使用数据手册要求的一次性有界等待，运行期继续禁止固定延时和长轮询 | 避免删除 W5300 必要复位/PLL 稳定等待 | 是 | PlatformInit 与 W5300 初始化 |
| CHG-R2-002 | 2026-07-19 | FR-116、FR-128、FR-131、FR-264、FR-266 | 公共状态与通道关闭子状态边界不完整 | 公共 Core 仅保留通用状态，通道私有保存 closing/faulted；close 使用 BUSY/DONE/ERROR | 闭合非阻塞关闭和失败终态 | 是 | 关闭、Erratum、再次监听、局部故障隔离 |
| CHG-R2-003 | 2026-07-19 | FR-114、FR-137、FR-143、FR-149、FR-248、FR-265 | `send()>0` 未明确代表 FIFO 接受还是 SEND 完成 | 只有对应分段获得 `SEND_OK` 后才向 Core 返回正进度 | 防止提前切换协议阶段或递增 step | 是 | 正常发送、错误响应、超时、断线 |
| CHG-R2-004 | 2026-07-19 | FR-247、FR-267 | App 职责分离未形成明确阶段门禁 | 冻结职责边界和独立测试要求，不固定类/文件数量 | 落实上次审核答复 | 否 | App 单元测试和阶段1门禁 |
| CHG-R2-005 | 2026-07-19 | FR-015、FR-262 | “现有 V1 实现”缺少不可变指向 | 固定历史协议基线提交 SHA，并允许建立只读 tag | 防止重构后历史协议基准漂移 | 否 | 阶段0仓库检查 |
| CHG-R2-006 | 2026-07-19 | FR-101、FR-109、FR-232、FR-234、FR-247～FR-249 | 平台失败示例、MAC 单播、环境范围和早期测试夹具未完整说明 | 明确失败后不得继续通信、MAC 单播、PC版本基线、DSP版本不固定及阶段夹具 | 完善计划输入和验收边界 | 视配置而定 | 对应 App/PC/DSP 测试 |

---

## 附录 F：冻结结论

第一版总体架构、App 配置模型、多实例生命周期、协议与单位边界、文件生成权限、旧架构迁移、W5300 SEND/关闭语义、Erratum 1 非阻塞处理、阶段计划和测试责任已经闭合。

完成 FR-262 的阶段0仓库整理后，可以依据本文件重新生成正式 `plan.md`。Codex、审核报告、计划和测试记录必须只引用本文件及其 FR 编号。
