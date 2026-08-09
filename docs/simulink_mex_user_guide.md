# Simulink 与 MEX 使用指南

本文说明如何把 App 生成的实例专用 C MEX S-Function 构建并接入用户自己的 Simulink 模型。操作基线为 MATLAB/Simulink R2024b 或更高版本，只覆盖桌面 Normal mode。

App 项目配置和 Generate 流程见 [`docs/app_project_and_migration_guide.md`](app_project_and_migration_guide.md)；DSP/CCS 文件集成、实例初始化和轮询顺序见 [`docs/ccs_integration_and_dual_instance_main.md`](ccs_integration_and_dual_instance_main.md)。

## 1. 使用边界

本文覆盖：

- Generate 后定位每个实例的自包含目录；
- 检查并选择 MATLAB 支持的 C MEX compiler；
- 构建每个实例自己的 MEX；
- 将实例目录加入 MATLAB Path；
- 放置和配置普通 S-Function Block；
- 按 App 表顺序连接 I/O；
- 使用 Normal mode 启动和正常停止仿真；
- 理解同步 step、原子输出、timeout 和错误文本；
- 配置双实例模型和排查常见问题。

本文不自动生成、修改或验证 `.slx`，也不替用户执行 DSP 下载或 W5300 联机验证。

## 2. Generate 后的实例目录

先按照 App 指南建立项目，成功完成 Preview 和 Generate。假设项目的 S-Function Output Root 为 `<sfun_root>`，生成结果按实例分目录：

```text
<sfun_root>/
├─ <instance_1_internal_name>/
├─ <instance_2_internal_name>/
└─ ...
```

每个 `<sfun_root>/<internal_name>/` 当前恰好包含以下 10 个文件：

| 文件 | 类别/维护者 | 用途 |
| --- | --- | --- |
| `<internal_name>_sfun.c` | `auto_generated` | Normal-mode C MEX S-Function callbacks 和实例 context 生命周期 |
| `<internal_name>_sfun.h` | `auto_generated` | 实例 context、临时输出对象和辅助声明 |
| `<internal_name>_sfun_io.c` | `auto_generated` | 端口设置、`INPUT_DATA` 打包、`OUTPUT_DATA` 解码和输出提交 |
| `<internal_name>_sfun_config.h` | `auto_generated` | S-Function、wire layout、sample time 和端口常量 |
| `<internal_name>_sfun_user_config.h` | `user` | 用户可编辑的 PC connect、step 和 terminate timeout |
| `<internal_name>_pc_socket.c` | `auto_generated` | 实例私有的跨平台 TCP 实现 |
| `<internal_name>_pc_socket.h` | `auto_generated` | Socket context 和结构化 PC error API |
| `<internal_name>_protocol.c` | `auto_generated` | 实例私有的 V1 frame 序列化和接收校验 |
| `<internal_name>_protocol.h` | `auto_generated` | 实例私有的 V1 wire 常量和 protocol API |
| `build_<internal_name>_sfun.m` | `auto_generated` | 当前实例的自包含 MEX build script |

每个实例目录都是自包含的，不依赖 `<sfun_root>` 中的共享 PC runtime，也不要把两个实例的源文件混合编译到一个 MEX。

`<internal_name>_sfun_user_config.h` 是用户文件；内容与新候选不同时，App Generate 默认保留现有文件，用户也可以在 Preview 中明确选择 Replace。其余 9 个文件当前都标记为 `auto_generated`，再次 Generate 时可能被替换，不建议手工修改。

## 3. MATLAB、Simulink 和 C compiler

第一版 PC/Simulink 基线是 MATLAB/Simulink R2024b 或更高版本，不额外承诺更早版本。C MEX compiler 必须是当前 MATLAB release 支持的 C compiler；本文不固定 Visual Studio、MinGW 或其他 compiler 版本，也不表示所有受支持 compiler 均已由本项目实际验证。

在 MATLAB 中检查当前选择：

```matlab
compiler = mex.getCompilerConfigurations('C', 'Selected')
```

如果结果为空，按当前 MATLAB 安装提供的选项选择 C compiler：

```matlab
mex -setup C
```

完成后再次执行 `mex.getCompilerConfigurations('C', 'Selected')` 确认结果。不要为本项目选择当前 MATLAB release 不支持的 compiler。

## 4. 构建实例 MEX

正式构建入口始终是实例目录中的 `build_<internal_name>_sfun.m`。不建议用户手工拼写 `mex` command。

### 4.1 方式 A：进入实例目录构建

```matlab
cd('<sfun_root>/<internal_name>')
run('build_<internal_name>_sfun.m')
```

### 4.2 方式 B：从任意当前目录构建

```matlab
run('<absolute-instance-path>/build_<internal_name>_sfun.m')
```

当前 build script 使用 `mfilename('fullpath')` 定位自己的 `script_dir`，因此方式 B 受支持。脚本不会永久修改 MATLAB 当前目录、MATLAB Path 或环境变量。

当前脚本显式编译：

```text
<internal_name>_sfun.c
<internal_name>_sfun_io.c
<internal_name>_pc_socket.c
<internal_name>_protocol.c
```

并引用同目录的 5 个 header：

```text
<internal_name>_sfun.h
<internal_name>_sfun_config.h
<internal_name>_sfun_user_config.h
<internal_name>_pc_socket.h
<internal_name>_protocol.h
```

脚本在调用 `mex` 前后负责：

- 定位并验证自己的实例目录；
- 检查目录可写和全部必需 source/header；
- 检查 `mex`、Simulink 和 `simstruc.h`；
- 检查已经选择受支持的 C compiler；
- 处理当前平台的 Socket link 参数；Windows 使用相应的 WinSock library；
- 检查是否已有同名 MEX 从其他目录加载，以及目标 MEX 是否仍被加载或锁定；
- 只将结果构建到实例目录；
- 成功后输出 `MEX Name`、`MEX Path`、`Protocol Version` 和 `Interface Hash`。

构建成功的目标为：

```text
<internal_name>_sfun.<mexext>
```

扩展名由 MATLAB 的 `mexext` 决定。例如 Windows 上常见结果是 `axis_alpha_sfun.mexw64`，但 `.mexw64` 不是跨平台固定后缀。

### 4.3 重复构建和已加载 MEX

build script 会处理实例目录中已有的同名目标，但应先停止所有正在使用该 S-Function 的仿真。

- 如果同名 MEX 已从另一个目录加载，脚本拒绝构建并报告 `C2837xBlock:MexBuild:ForeignMexLoaded`。
- 脚本会尝试 `clear <internal_name>_sfun`。如果目标仍被模型或 MATLAB 锁定，则报告 `C2837xBlock:MexBuild:MexStillLoaded`。停止仿真，关闭或卸载相关模型并释放该 MEX 后再构建。
- 不要手工强制删除正在使用的 MEX。
- 前置检查失败时，旧 MEX 不会被删除。正式开始重建后，旧目标会先删除；如果新构建失败，脚本不会恢复旧版本，并会清理能够识别的部分目标，避免新源码与旧二进制混用。
- 不要依赖 Fast Restart 来完成重建；第一版不承诺 Fast Restart。

当前与常见构建问题直接相关的 error identifier 包括：

```text
C2837xBlock:MexBuild:ForeignMexLoaded
C2837xBlock:MexBuild:MexStillLoaded
C2837xBlock:MexBuild:CompilerUnavailable
C2837xBlock:MexBuild:SimulinkUnavailable
C2837xBlock:MexBuild:MissingFile
C2837xBlock:MexBuild:DirectoryNotWritable
```

## 5. 让 MATLAB 找到实例 MEX

build script 不自动修改 MATLAB Path。按实例目录添加路径：

```matlab
addpath('<sfun_root>/<internal_name>')
```

双实例示例：

```matlab
addpath('<sfun_root>/axis_alpha')
addpath('<sfun_root>/axis_beta')
```

不要为了查找实例 MEX 而递归执行 `addpath(genpath('<sfun_root>'))`。实例目录级 `addpath` 更明确，也能降低旧目录或同名文件被意外加入的风险。

检查 MATLAB 实际解析到的文件：

```matlab
which <internal_name>_sfun -all
```

例如：

```matlab
which axis_alpha_sfun -all
```

确保首个实际解析结果是刚才构建的当前实例目录。如果 MATLAB Path 中存在另一个同名 `<internal_name>_sfun`，模型可能加载错误 MEX；应在停止仿真并释放已加载 MEX 后清理错误路径，再重新检查 `which`。

## 6. 放置和配置普通 S-Function Block

在用户自己的 Simulink model 中手工操作：

1. 打开 Simulink Library Browser。
2. 进入 `User-Defined Functions` → `S-Function`。
3. 将一个普通 S-Function block 放入模型。
4. 打开 block parameters，在 `S-function name`（底层属性名为 `FunctionName`）中填写：

   ```text
   <internal_name>_sfun
   ```

   例如：

   ```text
   axis_alpha_sfun
   ```

不要填写 `build_axis_alpha_sfun`、`axis_alpha_sfun.c` 或 `axis_alpha_sfun.mexw64`。

第一版 S-Function 没有对话框参数，不要增加 Block Parameters。IP、TCP port、Interface Hash、I/O、sample time 和最大 payload 编译在生成文件中，PC timeout 编译在用户配置头中。

## 7. 端口顺序、类型和宽度

每个 App input variable 生成一个 S-Function input port，每个 App output variable 生成一个 S-Function output port。顺序严格采用该实例在 App `Inputs` / `Outputs` 表中的当前顺序：

- 不按变量名排序；
- 不按类型排序；
- 不根据 C struct layout 推断。

例如 App Inputs 为：

| 内部顺序 | Name | Type | Dim |
| --- | --- | --- | --- |
| 0 | `voltage` | `single` | 1 |
| 1 | `current` | `single` | 3 |

则 Simulink 图中的连接是：

```text
Input Port 1 → voltage（single，width 1）
Input Port 2 → current（single，width 3）
```

App/generator 内部使用 0-based port index；Simulink 图形界面中用户看到的是第 1、第 2……端口。Outputs 同理。

当前支持的 port data type 为：

```text
int16
uint16
int32
uint32
single
double
```

每个端口的 data type 和 width 均由生成文件在编译期固定。用户只需连接类型和宽度兼容的信号，不要在 S-Function Block 中手工设置端口数量、类型或 width。连接不兼容时，应以用户执行 Update Diagram 或模型编译时的 Simulink diagnostics 为准。

## 8. Sample time 和 direct feedthrough

每个实例使用 App 中配置的 `sample_time_sec` 作为有限正数的固定离散 sample time，Offset 固定为 `0`。该值编译进 generated S-Function，不通过 Block 参数设置。

- 修改 `sample_time_sec` 后需要重新 Preview/Generate，并重新构建对应 MEX。
- sample time 只控制 Simulink simulation-time 调度。
- sample time 不发送给 DSP，不进入 Interface Hash，DSP 也不使用它进行周期调度。
- 不要把它理解为“DSP 每 `sample_time_sec` 必然执行一次”。

全部 input port 都是 direct feedthrough。如果模型形成 algebraic loop，S-Function 不会自动消除它；用户应根据模型设计显式加入 `Unit Delay`、`Memory` 或其他合适的延迟。

## 9. Normal mode 启动和同步 step

将模型的 Simulation Mode 设置为 `Normal`。准备启动前确认：

- 当前实例 MEX 已构建且 `which <internal_name>_sfun -all` 指向正确目录；
- 端口按 App 表顺序连接且类型/宽度兼容；
- DSP 程序已经下载并运行；
- DSP 侧持续轮询对应实例；
- PC/DSP IP 和实例 TCP port 与同一次 Generate 的配置一致；
- W5300 和网络可用。

仿真开始时，S-Function 创建当前实例的 PC context，建立 TCP 连接，发送包含该实例 Protocol Version 和 Interface Hash 的 `SIM_START`，等待成功 `RESPONSE`，然后令 `step_index = 0`。

每次 `mdlOutputs()` 采样触发一次完整、同步的通信：

```text
读取全部输入
→ 生成 INPUT_DATA
→ 发送当前 step_index
→ 等待 DSP 对应 OUTPUT_DATA
→ 完整校验和解码
→ 一次性更新全部输出
→ step_index + 1
```

这是真实的同步 wall-clock 等待，不是后台 step。仿真速度共同受 PC networking、DSP `Run` polling、W5300、DSP algorithm 和 MATLAB scheduler 影响。Simulink sample time 表示 simulation time，不保证等长 wall-clock 实时周期。

### 9.1 输出原子更新

S-Function 只有在以下内容全部成功后才一起提交当前 step 的全部 outputs：

- 收到完整帧；
- message type 正确；
- payload length 正确；
- `step_index` 正确；
- 所有 output field 均已解码到临时输出对象；
- 所有 output port 均可访问。

`RESPONSE(error)`、wrong type、wrong length、wrong step、truncated frame、timeout、disconnect 或 decode failure 都不会产生部分新输出。某个 output port 不会先于其他 output port 提交当前 step 的新值。

## 10. PC timeout 用户配置

每个实例的 `<internal_name>_sfun_user_config.h` 只提供以下三个用户 timeout，当前默认值为：

```c
#define CONNECT_TIMEOUT_MS     5000u
#define STEP_TIMEOUT_MS        1000u
#define TERMINATE_TIMEOUT_MS    200u
```

| 宏 | 用途 |
| --- | --- |
| `CONNECT_TIMEOUT_MS` | `mdlStart()` 中的 TCP connect |
| `STEP_TIMEOUT_MS` | `SIM_START` send/response、每次 `INPUT_DATA` send、每次 `OUTPUT_DATA` receive |
| `TERMINATE_TIMEOUT_MS` | 正常 terminate 时尽力发送 `SIM_STOP` |

这些 timeout：

- 不在 App UI 中编辑；
- 不保存到 project `.mat`；
- 不进入 Interface Hash；
- 不与 DSP timeout 协商；
- 与 DSP timeout 相互独立。

修改该用户配置头后，重新构建对应实例 MEX，不需要仅为 timeout 修改而手工编辑其他 generated header。

## 11. 错误文本和失败行为

S-Function 的结构化 PC error 文本以空格分隔字段。当前 formatter 可按错误现场提供：

```text
instance
stage
category
step_index
expected_type
actual_type
expected_length
actual_length
expected_step
actual_step
dsp_error
os_error
```

`instance`、`stage` 和 `category` 构成基本前缀；其余字段只在对应信息可获得时出现，并非每个错误都有全部字段。

示意格式如下；这不是本批实际运行日志，实际字段以具体错误为准：

```text
instance=axis_alpha stage=decode_output category=step_index step_index=10 expected_step=10 actual_step=11
```

常见 `stage` 的含义：

| stage | 用户可优先检查的环节 |
| --- | --- |
| `connect` | TCP 建连、IP、port、DSP/W5300 监听状态 |
| `send_frame` | `SIM_START`、`INPUT_DATA` 或 `SIM_STOP` frame 发送 |
| `recv_header` | 接收完整 protocol header |
| `recv_payload` | 按 header 声明长度接收 payload |
| `wait_response` | 等待和解析启动 `RESPONSE` |
| `wait_output_data` | 等待、分支和接收 `OUTPUT_DATA`/`RESPONSE` |
| `pack_input` | 访问 input port 并打包输入 |
| `step_output_length` | 当前 step 的 `OUTPUT_DATA` 固定长度校验 |
| `decode_output` | `step_index` 和 output field 解码 |
| `commit_output` | 检查并提交 Simulink output ports |

当前结构化错误 API 中的 `category` 及其含义如下：

| category | 含义 |
| --- | --- |
| `argument` | PC runtime 收到无效参数或当前调用前提不成立 |
| `timeout` | connect、send 或 receive 超过对应 PC timeout |
| `disconnect` | 对端在预期传输完成前正常关闭连接 |
| `socket` | 本地 Socket API 失败；如可获得，同时查看 `os_error` |
| `truncated` | header 或 payload 只收到一部分即断开 |
| `message_type` | 实际 message type 不是当前阶段期望的类型 |
| `payload_length` | payload length 与协议或当前实例的固定长度不符 |
| `payload_capacity` | header 声明的 payload 超过当前接收缓冲容量 |
| `dsp_response` | 收到 DSP `RESPONSE(error)`；如可获得，同时查看 `dsp_error` |
| `internal` | PC runtime 的内部计时或状态检查失败 |
| `step_index` | `OUTPUT_DATA` 的 step 与当前期望 step 不同 |
| `field_decode` | output field 解码失败 |
| `port_access` | 无法访问当前 Simulink input/output port signal |

出现 timeout、Socket error、protocol error、DSP `RESPONSE(error)`、length error 或 step error 时，当前 S-Function 会：

- 关闭当前连接；
- 不更新当前 step 的 outputs；
- 设置 Simulink error status；
- 使当前 simulation 失败/停止；
- 不自动 reconnect、retry、resend 或跳 step。

恢复时先解决根因，确认 DSP 状态允许重新开始，再重新启动 simulation。当前没有自动恢复机制。

## 12. 正常停止

建议始终使用 Simulink 的正常 Stop 结束仿真。如果 session 和 socket 仍有效，S-Function 会在 `TERMINATE_TIMEOUT_MS` 内尽力发送一次 `SIM_STOP`，不等待额外 `RESPONSE`，随后关闭 Socket 并释放 PC context。

如果连接此前已因错误关闭，terminate 不会重新连接，也不会再次发送。不要把强制结束 MATLAB 作为正常停止方法。

## 13. 双实例模型

每个实例具有独立目录、独立 MEX、独立 `FunctionName`、独立 TCP port、独立 context、独立 `step_index` 以及独立 timeout/error state。例如：

```text
<sfun_root>/axis_alpha/
  axis_alpha_sfun.<mexext>

<sfun_root>/axis_beta/
  axis_beta_sfun.<mexext>
```

分别构建：

```matlab
run('<sfun_root>/axis_alpha/build_axis_alpha_sfun.m')
run('<sfun_root>/axis_beta/build_axis_beta_sfun.m')
```

分别加入 Path 并检查解析结果：

```matlab
addpath('<sfun_root>/axis_alpha')
addpath('<sfun_root>/axis_beta')
which axis_alpha_sfun -all
which axis_beta_sfun -all
```

在模型中放置两个普通 S-Function Block，`FunctionName` 分别填写：

```text
axis_alpha_sfun
axis_beta_sfun
```

按各自在 App 中的 Inputs/Outputs 表连接 I/O。两个实例的 `sample_time_sec` 可以不同，各自值由各自 generated S-Function 固定。

这不是“一个通用 MEX + instance parameter”架构。Simulink 中存在两个实例专用 MEX，也不要据此推断 DSP algorithms 会并行执行；DSP 端仍由用户 `main` 中明确的轮询顺序推进。

## 14. Interface Hash 和配置变化

build script 成功时显示当前实例的 `Protocol Version` 和 `Interface Hash`。运行时 `SIM_START` 使用这两个值；DSP 与 PC 必须来自匹配的 Generate 配置。

遇到 `config hash mismatch` 时优先检查：

- DSP 和 S-Function 是否由同一项目配置生成；
- 是否只重新 Generate、替换或编译了一端；
- 模型是否仍使用旧 MEX；
- `which <internal_name>_sfun -all` 是否解析到旧实例目录。

不要手工修改 Hash。

配置变化后的操作如下：

| 变化 | 必要操作 |
| --- | --- |
| I/O name/type/dim/order | 重新 Preview/Generate；重新 build 对应 MEX |
| `sample_time_sec` | 重新 Preview/Generate；重新 build 对应 MEX |
| network/IP 或实例 TCP port | 重新 Preview/Generate；重新 build 对应 MEX |
| Interface Hash 相关配置，例如 protocol、I/O 或 max payload | 重新 Preview/Generate；重新 build 对应 MEX，并确保 DSP 端同步更新 |
| 任一 generated S-Function source/header 变化 | 重新 build 对应 MEX；如果变化源自项目配置，应先重新 Preview/Generate |
| 仅 `CONNECT_TIMEOUT_MS`、`STEP_TIMEOUT_MS` 或 `TERMINATE_TIMEOUT_MS` | 修改 `<internal_name>_sfun_user_config.h`；重新 build 对应 MEX |

不要直接修改 `*_sfun_config.h`、`*_protocol.h` 或 `*_sfun_io.c`；它们是自动生成文件。

## 15. 推荐故障排查顺序

### A. build script 找不到 compiler

1. 执行 `mex.getCompilerConfigurations('C', 'Selected')`。
2. 如为空，执行 `mex -setup C`。
3. 确认选择的是当前 MATLAB release 支持的 C compiler。

### B. Simulink 找不到 MEX

1. 检查 build script 是否成功输出 `MEX Name` 和 `MEX Path`。
2. 执行 `which <internal_name>_sfun -all`。
3. 对正确的实例目录执行 `addpath('<instance-directory>')`。

### C. `ForeignMexLoaded`

1. 停止相关 simulation，关闭或卸载使用同名 MEX 的模型。
2. 释放已加载的同名 MEX。
3. 清理错误 MATLAB Path，添加当前实例目录。
4. 用 `which <internal_name>_sfun -all` 复核后重新构建。

### D. `MexStillLoaded`

1. 停止所有使用该 MEX 的 simulation。
2. 关闭或卸载相关 model，释放对应 MEX。
3. 重新运行当前实例 build script；不要强制删除占用中的文件。

### E. `connect` / `socket`

依次检查 DSP 程序是否已运行、PC/DSP IP、实例 TCP port、DSP 轮询、W5300 状态、防火墙和物理网络。

### F. config / hash

确认 DSP 输出和 PC S-Function 来自同一次 Generate，并确认模型实际加载的是这次构建的 MEX。

### G. `step_index` / protocol / length

保存完整 error text，并记录当前 project config、生成文件版本和可重复的操作步骤。不要靠跳 step、重发或手工修改 Hash 绕过错误。

## 16. 手工最小模型流程

以下步骤全部由用户在 MATLAB/Simulink 中手工完成：

1. 在 App 中配置项目，完成 Preview 和 Generate。
2. 找到 `<sfun_root>/<internal_name>/` 并核对 10 个实例文件。
3. 执行 `mex.getCompilerConfigurations('C', 'Selected')`；如需选择 compiler，执行 `mex -setup C`。
4. 运行 `run('<absolute-instance-path>/build_<internal_name>_sfun.m')`。
5. 执行 `addpath('<sfun_root>/<internal_name>')`。
6. 执行 `which <internal_name>_sfun -all`，确认解析到当前实例目录。
7. 新建或打开用户自己的 Simulink model。
8. 从 `User-Defined Functions` → `S-Function` 放置普通 S-Function Block。
9. 将 `FunctionName` 填为 `<internal_name>_sfun`，不增加 Block Parameters。
10. 按该实例 App Inputs/Outputs 表顺序连接 ports。
11. 将 Simulation Mode 设为 `Normal`。
12. 用户执行 Update Diagram，并按 Simulink diagnostics 修正类型、width 或模型连接问题。
13. DSP/W5300 和网络准备完成后启动 simulation。
14. 使用 Simulink 正常 Stop 结束 simulation。

## 17. 第一版不保证或不验收的能力

以下能力不是第一版的保证或验收范围；这里的“不保证”不等于断言它们在所有环境都无法工作：

- 为项目自动生成 `.slx`；
- Accelerator；
- Rapid Accelerator；
- Fast Restart；
- Simulink Coder/code generation deployment；
- TLC inline；
- model-reference deployment；
- real-time target；
- parallel simulation；
- 自动 reconnect；
- 自动 retry/resend；
- 后台 step；
- PC/DSP timeout 协商。
