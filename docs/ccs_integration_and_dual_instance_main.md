# CCS 集成和双实例 `main` 示例

## 1. 范围与验证状态

App 只生成 `<dsp_root>/inc` 和 `<dsp_root>/src`。用户负责把这些文件集成到现有 CCS 工程，并负责器件初始化、系统时钟、链接文件、启动代码、中断向量表、Flash/RAM 配置、GEL、烧录和硬件调试。

本项目不生成 `.project`、`.cproject`、linker command file、启动代码、中断向量表或烧录脚本。本指南也不设计硬件接线、链接或启动流程。

当前状态：**已实现，待用户编译或实机验证**。本文的生成树和 Host 检查不代表已经通过 TI CCS/C2000 编译器或 W5300 实机验证。

## 2. Include Search Path

将以下目录加入 CCS Include Search Path：

```text
<dsp_root>/inc
```

- 不要把 `<dsp_root>/src` 作为公共 Include Search Path。
- 不要使用 `#include "*.c"`；`.c` 文件应作为独立编译单元加入工程。
- 用户算法依赖的其他头文件由用户自行加入 Include Search Path。
- 生成文件之间的实际 Include 关系以当前生成内容为准。
- 用户 `main.c` 只需包含 `c2837x_block_project.h`；该头继续包含公共 API 并导出静态实例。

## 3. CCS 源文件清单

下面只列需要编译的 `.c` 文件。头文件通过 Include Search Path 使用，不作为编译单元。**每个 `.c` 只能加入并编译一次**，生成目录中不存在的文件不得加入工程。

### 3.1 公共 Core：每个项目各一次

| 相对路径 | 职责 |
| --- | --- |
| `src/c2837x_block.c` | 公共实例生命周期与协议状态机 |
| `src/c2837x_block_protocol.c` | V1 wire 协议编解码 |
| `src/c2837x_block_platform.c` | 项目级平台初始化入口 |
| `src/c2837x_block_timer2.c` | 共享 CPU Timer 2 单调计时源 |
| `src/c2837x_w5300_hal.c` | W5300 GPIO、EMIF、复位与寄存器访问 HAL |
| `src/c2837x_w5300_socket.c` | W5300 Socket 操作 |
| `src/c2837x_w5300_channel.c` | 非阻塞 W5300 TCP IoDevice 通道 |

公共 Core 输出副本只应来自同一次生成。Core 如需修改，应在 DSP-SimBridge 源仓库统一修复后重新生成，不要只修改某个输出目录中的副本。

### 3.2 项目级：一次

| 相对路径 | 职责 |
| --- | --- |
| `src/c2837x_block_project.c` | 定义所有生成的 `g_<internal_name>` 静态实例及项目级公共绑定 |

### 3.3 实例级：每个有效实例各一次

| 相对路径 | 职责 |
| --- | --- |
| `src/<instance>_config.c` | 尺寸、Interface Hash、适配器和静态配置绑定 |
| `src/<instance>_io.c` | 实例序列化与 IoDevice 通道绑定 |
| `src/<instance>_algorithm.c` | 算法实现；是否生成取决于算法模式 |

### 3.4 双实例完整示例

以下清单来自当前生成器对 `current_loop: generated_example`、`voltage_loop: external_reference` 的真实临时生成结果：

```text
src/c2837x_block.c
src/c2837x_block_protocol.c
src/c2837x_block_platform.c
src/c2837x_block_timer2.c
src/c2837x_w5300_hal.c
src/c2837x_w5300_socket.c
src/c2837x_w5300_channel.c
src/c2837x_block_project.c
src/current_loop_config.c
src/current_loop_io.c
src/current_loop_algorithm.c
src/voltage_loop_config.c
src/voltage_loop_io.c
<用户原始路径>/voltage_loop_external.c
```

其中前 13 个是生成树中的编译单元，最后一个是 `external_reference` 的原外部源。`src/voltage_loop_algorithm.c` 不会生成，也不得加入工程。

## 4. 三种算法文件模式

### `generated_example`

- 生成 `src/<instance>_algorithm.c`。
- 该文件可由用户编辑。
- 将生成文件加入 CCS 工程一次。

### `external_copy`

- 外部源内容被复制到 `src/<instance>_algorithm.c`。
- CCS 只加入生成目录中的副本一次。
- 不要同时加入原外部源，否则可能产生重复回调符号。

### `external_reference`

- 不生成 `src/<instance>_algorithm.c`。
- 将原外部 `.c` 加入 CCS 工程一次。
- 原文件依赖的头文件由用户维护 Include Search Path。
- 不要添加一个不存在的生成算法文件。
- 不要让两个有状态实例错误复用同一套实例专用回调实现；各实例回调必须符合各自生成的强类型声明。

无论采用哪种模式，每个算法实现都只能编译一次。

## 5. 用户可编辑边界

用户可编辑：

```text
inc/<instance>_user_config.h
src/<instance>_algorithm.c
用户 main.c
用户 CCS 工程配置
```

`external_reference` 模式下，用户编辑的是原外部算法源。

以下自动生成内容不应手工修改：

```text
inc/<instance>_algorithm.h
inc/<instance>_config.h
src/<instance>_config.c
src/<instance>_io.c
inc/c2837x_block_project.h
src/c2837x_block_project.c
公共 Core 输出副本
Interface Hash 和尺寸定义
```

## 6. 禁止新旧单实例文件混合编译

迁移后应从 CCS 工程和相关路径中移除旧单实例文件及旧工程引用。不得同时使用：

- 新旧 `c2837x_block.c`；
- 旧单实例配置与新的项目级/实例级配置；
- 旧全局输入输出文件与新的实例 I/O；
- 旧无参数 `C2837xBlock_Init()`、`C2837xBlock_Run()` 调用与当前带实例参数的 API；
- 旧通用单实例 S-Function 与新实例 S-Function。

V1 wire 协议兼容不代表 DSP C API、生成文件或二进制兼容。必须重新生成并重新编译，不能拼接新旧输出。

## 7. ABI 与编译检查

- CCS 工程 ABI 必须与 App 项目级选择的 `eabi` 或 `coffabi` 一致。
- 同一项目的全部公共、项目级和实例级文件必须使用同一 ABI，不允许按实例混用。
- 生成代码包含 Core API Version 编译期检查；版本不匹配会产生编译错误。
- 生成代码包含数据类型宽度检查。使用逻辑 `double` 接口时，DSP 本地 `long double` 必须满足生成代码要求：`sizeof(long double) * CHAR_BIT == 64`。
- 本项目不猜测或固定用户的 CCS/C2000 Compiler 版本，也不虚构未执行的 TI 编译选项。
- 后续编译记录必须填写实际 CCS、C2000 Compiler、ABI 和目标器件工程配置。

## 8. 平台资源与用户工程责任

集成前确认：

- CPU Timer 2 未被其他模块占用；`PlatformInit()` 成功后不得停止、重装、重新预分频或复用它。
- W5300 HAL 的 GPIO、EMIF、复位和访问时序符合实际硬件。
- 一个项目只对应一个物理 W5300。
- 各实例 Socket 编号和 TCP port 来自生成配置，且互不重复。
- 用户现有工程负责器件/时钟初始化、链接、启动及存储布局。

## 9. 实例对象使用限制

`C2837xBlock` 是不透明类型。用户只能使用生成的
`c2837x_block_project.h` 导出的项目实例，例如
`g_current_loop` 和 `g_voltage_loop`。

禁止：

- 在栈、静态存储区或动态内存中自行定义新的
  `C2837xBlock` 实例；
- 使用 `malloc`、`calloc`、`realloc` 或 `free`
  创建、复制、调整或释放实例资源；
- 直接赋值复制实例对象，或使用 `memcpy`、`memmove`
  等方式复制实例内部状态；
- 将内部头文件加入用户代码，以绕过不透明类型边界；
- 将非生成实例传给 `C2837xBlock_Init()`、
  `C2837xBlock_Run()` 或 `C2837xBlock_GetLastError()`；
- 让两个实例共享同一实例配置、Socket、RX/TX 缓冲区
  或 IoDevice 通道；
- 手工修改 `g_<internal_name>` 的生成定义、配置绑定或
  内部资源指针。

每个生成实例的配置、Socket、协议缓冲区和 IoDevice
通道均由生成文件静态绑定。用户代码只负责按固定顺序
调用生成实例，不负责创建、复制、销毁或重新绑定实例。

当前第一版不建立对象注册表、实例魔数或复杂运行时合法性
检查，因此上述约束必须由 CCS 集成代码和工程文件严格遵守。

## 10. 初始化与裸机轮询顺序

固定流程为：

```text
用户现有底层/器件初始化
→ C2837xBlock_PlatformInit()
→ 检查返回值
→ 逐实例 C2837xBlock_Init()
→ while (1) 中按用户确定的固定顺序逐实例 C2837xBlock_Run()
```

- `C2837xBlock_PlatformInit()` 在项目中只调用一次。
- 返回值小于零后，不得调用 `Init`、`Run` 或其他实例通信 API；应进入用户定义的故障处理路径。
- 对每个生成实例显式调用一次 `C2837xBlock_Init()`。
- 主循环必须持续轮询全部启用实例，顺序由用户程序显式决定。
- 当前没有 `RunAll()`、`InitAll()`、默认实例、RTOS 调度或动态实例注册。
- 某个用户算法长时间不返回会阻塞整个裸机轮询循环。
- `C2837xBlock_GetLastError()` 只返回每实例最近的本地错误，不是线缆错误历史。

可复制的双实例代码见 [`examples/dual_instance_main.c`](examples/dual_instance_main.c)。示例使用 `g_current_loop`、`g_voltage_loop`，初始化和轮询顺序均为 `current_loop` 后 `voltage_loop`。

## 11. 后续 CCS 证据记录

用户后续应记录：

- CCS 版本；
- C2000 Compiler 版本；
- 目标器件；
- ABI；
- 实际 Include Search Path；
- 实际编译的 `.c` 文件列表；
- 编译命令或 build log；
- warning/error 数量；
- 是否存在重复符号、缺失符号或 Core API mismatch；
- DSP/CCS 编译结果；
- 实机验证状态。

未提供真实证据前，相关项目统一保持：**已实现，待用户编译或实机验证**。
