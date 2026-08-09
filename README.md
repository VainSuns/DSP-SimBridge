# DSP-SimBridge

DSP-SimBridge 是面向算法研发、调试和 Simulink—DSP 联合仿真的多实例通信桥。当前产品使用 V2 项目格式，为一个 TMS320F28377D 裸机工程生成静态多实例 DSP 文件，并为每个实例生成独立的 C MEX S-Function 源码。

## Current V1 Scope

- 目标 DSP：TMS320F28377D。
- 第一版 IoDevice：W5300 TCP；一个项目对应一个物理 W5300。
- 实例在同一个裸机 `main` 循环中按用户定义的顺序串行轮询。
- 实例及其 Socket、TCP port、缓冲区、协议状态和算法绑定均在编译期静态确定。
- 每个 DSP 实例对应一个独立生成、独立构建的 C MEX S-Function。
- Wire protocol 保持历史 V1 兼容，当前协议版本为 `1`。
- PC 基线为 MATLAB/Simulink R2024b 或更高版本，使用桌面 Normal mode。
- 项目级 ABI 支持 `eabi` 和 `coffabi`；用户 CCS 工程必须与 App 项目选择一致。
- I/O 类型支持 `int16`、`uint16`、`int32`、`uint32`、`single` 和 `double`，每个变量是固定长度的一维标量或向量。

逻辑 `double` 在线缆上固定为 8 wire octet IEEE 754 binary64。DSP 生成代码使用 `long double` 并执行当前需求规定的编译期宽度与表示检查；ABI 不改变 wire 编码。

## Architecture

DSP 生成路径：

```text
App
→ V2 project validation / Preview / Generate
→ <dsp_root>/inc + <dsp_root>/src
→ DSP public Core
→ project-level static bindings
→ per-instance algorithm / config / typed I/O / W5300 channel
→ W5300 TCP
```

Simulink 生成路径：

```text
App
→ <sfun_root>/<internal_name>/
→ build_<internal_name>_sfun.m
→ <internal_name>_sfun.<mexext>
→ ordinary Simulink S-Function Block
```

每个实例独立管理输入/输出对象、RX/TX 软件缓冲区、Socket、TCP port、连接与会话、协议阶段、`step_index`、收发进度、超时状态、算法生命周期、PC context 和最近错误。MAC、IP、gateway、subnet、W5300 公共初始化和 CPU Timer 2 等真正的平台资源只在项目级共享。

## Key Features

- V2 `.mat` 项目保存、加载、dirty 状态和旧单实例配置迁移。
- 多实例 Add、Copy、Delete、命名和资源冲突校验。
- 强类型 I/O、确定性 wire layout、逐实例 Interface Hash 和内存报告。
- 不写盘的 Preview、候选文件比较、用户文件保护和快照复核。
- 确定性生成 DSP Core、项目级绑定、实例文件及自包含 S-Function 目录。
- 显式实例 DSP API、设备无关的非阻塞 Core、CPU Timer 2 通信超时和 W5300 通道状态机。
- 同步 Normal-mode step、PC 临时输出解码与原子提交、结构化错误文本。

## Requirements

[Frozen V1.0 Rev.2 requirements](requirements/requirements_multi_iodevice_v1.0_frozen_rev2.md) 是当前唯一需求事实源。本文、实现、测试和验收材料不得改变其中 FR 的含义。

- [Implementation plan](plan.md) — 任务拆分和阶段门禁计划，不是需求事实源。
- [Requirements traceability](docs/requirements_traceability.md) — frozen requirements 到实现、文档和验证状态的逐 FR 追踪。

## Quick Start

1. 按 [App 项目与迁移指南](docs/app_project_and_migration_guide.md) 启动 App，并创建或加载 V2 项目。
2. 配置项目公共网络、ABI、输出根、实例、Socket/TCP port 和 I/O。
3. 在 App 中执行 Preview，核对 Interface Hash、内存报告和候选动作，再执行 Generate。
4. 按 [CCS 集成和双实例 main 指南](docs/ccs_integration_and_dual_instance_main.md) 将 `<dsp_root>/inc` 与 `<dsp_root>/src` 集成到用户 CCS 工程。
5. 按 [Simulink 与 MEX 使用指南](docs/simulink_mex_user_guide.md) 分别运行每个实例的构建脚本。
6. 将实例目录加入 MATLAB Path，在模型中放置普通 S-Function Block，并把 `FunctionName` 设为 `<internal_name>_sfun`。
7. 按 App 的 I/O 顺序连接端口，使用 Normal mode；用户执行 Update Diagram 后再联机运行。
8. 按 [测试方案](docs/test_plan.md) 执行软件、CCS、DSP 和硬件验收，并将真实结果写入验收记录。

App 不生成或修改用户 `.slx`，也不自动构建 MEX、创建 CCS 工程、下载 DSP 或执行硬件测试。

## Documentation

- [App 项目与迁移指南](docs/app_project_and_migration_guide.md)
- [CCS 集成和双实例 main 指南](docs/ccs_integration_and_dual_instance_main.md)
- [Simulink 与 MEX 使用指南](docs/simulink_mex_user_guide.md)
- [测试方案](docs/test_plan.md)
- [问题反馈模板](docs/problem_feedback_template.md)
- [验收记录模板](docs/acceptance_record_template.md)
- [需求追踪](docs/requirements_traceability.md)

## Generated Outputs

DSP 输出根固定包含：

```text
<dsp_root>/inc/   public/generated headers and per-instance headers
<dsp_root>/src/   public Core, project bindings, per-instance I/O and algorithms
```

S-Function 输出按实例隔离：

```text
<sfun_root>/<internal_name>/
```

每个实例目录包含实例专用 S-Function、typed I/O、PC Socket、V1 protocol、自动配置头、用户配置头和 `build_<internal_name>_sfun.m`。完整文件职责和构建规则见 [App 指南](docs/app_project_and_migration_guide.md)与 [Simulink/MEX 指南](docs/simulink_mex_user_guide.md)。本文是 V2 多实例项目的当前入口；仓库中仍可能物理保留的旧单实例源码或说明与当前 V2 多实例 App 不一致，不作为当前用法或历史参考教程，也不得与 V2 输出混合编译或加载。

## DSP Public API

当前公共原型以 [`dsp/inc/c2837x_block.h`](dsp/inc/c2837x_block.h) 为准：

```c
int16 C2837xBlock_PlatformInit(void);
void C2837xBlock_Init(C2837xBlock *instance);
void C2837xBlock_Run(C2837xBlock *instance);
C2837xBlock_Error C2837xBlock_GetLastError(const C2837xBlock *instance);
```

`C2837xBlock` 对用户保持不透明。用户只能传入生成的项目实例，不得自行创建、复制或重新绑定实例对象。

## Execution Model

```text
C2837xBlock_PlatformInit() once
→ C2837xBlock_Init(&instance) once for each generated instance
→ repeatedly call C2837xBlock_Run(&instance) in user-defined order
```

`PlatformInit()` 失败后不得继续调用实例通信 API。DSP Core 不提供 scheduler、`RunAll()`、RTOS task 或按 sample time 的 DSP 调度；用户裸机主循环的调用顺序就是实例推进顺序。

W5300 通道关闭返回 ERROR 时，仅当前 Socket 进入私有 `faulted` 状态，不复位整个 W5300，也不恢复 `open/listen`；该 Socket 只有在后续一次成功的 `C2837xBlock_PlatformInit()` 或 DSP 复位后才可恢复。普通用户重新启动 PC simulation 不解除此门禁。

## Simulink Integration

每个实例的 S-Function/MEX 基名都是：

```text
<internal_name>_sfun
```

它用于普通 Simulink S-Function Block，当前只保证桌面 Normal mode。`sample_time_sec` 只影响 Simulink simulation-time scheduling；`mdlOutputs()` 同步等待一个完整 DSP step，它不表示 DSP wall-clock 周期。配置变化后按用户指南重新 Generate，并在需要时重建对应 MEX。

## Protocol

当前保持 V1 wire protocol：4 wire octet Header，消息 `SIM_START`、`INPUT_DATA`、`OUTPUT_DATA`、`SIM_STOP` 和 `RESPONSE`，little-endian 编码，`step_index` 为 `uint32`。详细行为、固定长度和错误码仍以 frozen requirements、当前 protocol source 和 protocol tests 为准；README 不定义第二份协议规范。

## User Editable Files

DSP 用户维护：

```text
<internal_name>_user_config.h
<internal_name>_algorithm.c
user main.c
user CCS project configuration
```

`external_reference` 模式下，算法源由用户在原路径维护并加入 CCS 工程。

PC 用户维护：

```text
<internal_name>_sfun_user_config.h
```

其他 generated files、Interface Hash、尺寸、协议副本和构建脚本不应手工维护。DSP 用户配置头只承载 `INTERACTION_TIMEOUT`、`TRANSFER_TIMEOUT`；PC 用户配置头只承载 `CONNECT_TIMEOUT_MS`、`STEP_TIMEOUT_MS`、`TERMINATE_TIMEOUT_MS`。

## Validation Status

当前实现具有 App、protocol、DSP Host、PC Mock、S-Function source/build-path 和 Normal-mode 相关的软件测试基础。软件或 Host 证据只能说明对应机制和生成逻辑，不能替代用户环境中的 TI CCS 编译、DSP 下载或 W5300 实机证据。

验证结论必须分层记录：

- App/protocol/DSP Host/PC 测试按实际 runner 和日志记录。
- 某一环境没有可用 C MEX compiler 时，MEX rebuild 为 `NOT_EXECUTED / CAPABILITY`；不得推断构建成功或产品失败。
- 用户手工 Update Diagram 和 Normal-mode 联机仍按实际验收记录填写。
- EABI 和 COFF CCS build 必须分别由用户实际执行并提供证据。
- DSP download、W5300 full hardware matrix、dual-instance hardware matrix 和 Erratum hardware matrix 在无用户证据时保持 `USER_VALIDATION_PENDING`。
- 未执行的项目不表示 PASS；不使用 “fully tested”、“hardware verified” 或 “production ready” 描述当前交付。

详细的当前证据边界与逐 FR 状态见 [需求追踪](docs/requirements_traceability.md)。

## Unsupported / Not Guaranteed in V1

以下能力不在 V1 保证或验收范围；这不表示它们在所有环境中技术上绝对不能工作：

- dynamic instance creation or registration
- RTOS scheduling, priorities, threads, or multi-core parallel execution
- SCI or other first-version IoDevice support
- 不提供 automatic reconnect、retry、resend、step recovery 或 background step
- automatic `.slx` generation or modification
- Accelerator, Rapid Accelerator, or Fast Restart
- Simulink Coder/Embedded Coder deployment, TLC inline, or model-reference deployment
- real-time target or parallel simulation
- CCS project, linker, startup, flashing, or download generation
- installer, release package, Toolbox, signing, or automatic update

## Testing and Feedback

执行和记录入口：

- [测试方案](docs/test_plan.md)
- [问题反馈模板](docs/problem_feedback_template.md)
- [验收记录模板](docs/acceptance_record_template.md)

未经实际执行及证据支持，不得把测试计划、模板、源码存在或 Host/Mock 结果记录为 DSP/hardware PASS。

## License

本项目采用 [MIT License](LICENSE)。
