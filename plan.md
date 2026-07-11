# C2837xBlock 多 IoDevice / 多算法实施计划

> **执行依据：** `requirements_multi_iodevice.md`（Frozen）
>
> **执行约束：** 实施时逐阶段完成、验证和评审；不得跨过未通过的阶段。

**目标：** 在保持 V1 wire format 的前提下，把当前单 W5300/单算法/单 S-Function 实现改造成可由用户运行时注入 IoDevice 的静态多 Block 架构，并由现有 App 生成多个 Algorithm Instance 和多个独立 MEX。

**架构：** `core/algorithm` 只保存通用协议、状态机和实例状态；`autogen` 保存每实例不可变配置、typed adapter 和 PC wrapper；用户在 `user/` 或自己的 DSP 工程中实现 Algorithm、IoDevice、初始化、映射和主循环。PC 端继续使用同步 TCP client，每个生成的 S-Function/MEX 拥有独立 context。

**技术栈：** ISO C11 可移植 Core、TI C2000 用户集成、MATLAB R2025b、Simulink C MEX S-Function、MATLAB App/uifigure、Windows sockets、MinGW GCC host test。

## 全局约束

- 不修改 `dsp/inc/c2837x_w5300_hal.h`、`dsp/inc/c2837x_w5300_regs.h`、`dsp/inc/c2837x_w5300_socket.h`、`dsp/src/c2837x_w5300_hal.c`、`dsp/src/c2837x_w5300_socket.c`。
- 不修改用户算法 `dsp/src/my_algorithm.c`，也不创建或修改 `user/**`；用户迁移在本计划外完成。
- 不创建 DSP 测试工程；AI/Codex 只提供 host-side 和 PC/Mock 验证。
- 不新增 Block Reset、IoDevice reset、`SetIoDevice`、Manager、动态注册表、`RunAll`、自动恢复或共享资源仲裁。
- `read/write` 必需，`poll/end_session` 可选；设备初始化和错误处理始终由用户负责。
- V1 消息类型、frame、little-endian、error code `0`–`8` 和 step wire layout不得改变。
- 任何阶段都不得声称 MEX、Simulink、DSP 或硬件验证已完成；只有实际执行相应命令并保存结果后才能标记通过。

## 已确认的现有基线

- DSP 单例位于 `dsp/src/c2837x_block.c`：`g_ctx`、`g_tick_counter` 和 `C2837xBlock_Run()` 内的 `static first_connected` 阻止多实例。
- DSP Core 直接包含并调用 W5300 HAL/Socket；`C2837xBlock_Init()` 同时初始化硬件、写网络寄存器、配置 Socket 0 内存。
- typed I/O 依赖 `dsp/src/c2837x_block_global_variable.c` 的全局输入输出以及无 context 的三个全局回调。
- App `app/C2837xBlockConfigurator.m` 只保存一个 config，并直接配置 gateway、subnet、MAC、Socket 和 W5300 TX/RX 缓存。
- Hash 生成器 `app/c2837x_block_build_hash_string.m` 当前把 DSP IP、gateway、subnet、TCP port 和 Socket 纳入 Hash。
- DSP/PC 生成器当前把共享 Core 和 W5300 驱动复制到每个输出目录，并生成单例符号。
- `simulink/c2837x_block_sfun.c` 使用 `g_c2837x_block_instance_count` 禁止多实例；当前输出解包发生在 step 校验之前。
- `simulink/build_c2837x_block_sfun.m` 只生成固定名称 `c2837x_block_sfun`。
- 仓库没有正式自动测试目录；只有协议向量、两个单实例 `.slx` 和创建单实例模型的脚本。

## 计划冻结的公共类型和名称

以下名称在阶段 1 固定，后续阶段不得自行改名：

```c
typedef uint16_t protocol_octet_t; /* 仅低 8 bit 有效 */

typedef struct C2837xBlockGeneratedConfig C2837xBlockGeneratedConfig;
typedef struct C2837xBlockAlgorithmOps C2837xBlockAlgorithmOps;
typedef struct C2837xBlockIoDeviceOps C2837xBlockIoDeviceOps;
typedef struct C2837xBlock C2837xBlock;

C2837xBlockResult C2837xBlock_Init(
    C2837xBlock *block,
    const C2837xBlockGeneratedConfig *generated_config,
    const C2837xBlockAlgorithmOps *algorithm_ops,
    void *algorithm_ctx,
    const C2837xBlockIoDeviceOps *iodevice_ops,
    void *iodevice_ctx);

C2837xBlockRunResult C2837xBlock_Run(C2837xBlock *block);
```

- `C2837xBlockGeneratedConfig` 固定保存 protocol version、config hash、input data size 和 output data size；不得保存 endpoint、Socket、SCI 或 IoDevice 信息。
- `C2837xBlockAlgorithmOps` 固定包含可空 `on_start`、必需 `process`、可空 `on_stop`，签名与 Frozen 需求一致。
- `C2837xBlockIoDeviceOps` 固定包含可空 `poll`、必需 `read/write`、可空 `end_session`。
- `read/write` 返回 `>0` 表示 octet 进度、`0` 表示无进度、`C2837X_BLOCK_IO_LINK_DOWN=-1`、`C2837X_BLOCK_IO_ERROR=-2`。
- `poll` 返回 `DOWN/READY/ERROR`；`end_session` 返回 `DONE/PENDING/ERROR`。
- `C2837xBlockResult` 固定区分 `OK/INVALID_ARGUMENT/INVALID_STATE/CONFIG_ERROR`；`C2837xBlockRunResult` 固定区分 `IDLE/PROGRESSED/ERROR`。
- `last_error` 使用简单 `uint16_t`：`0` 为 NONE，`1`–`8` 直接保存 V1 error code，`0x0100` 表示 poll/read/write IoDevice error，`0x0101` 表示 end_session error；这些扩展诊断值不得上 wire。
- Core 使用固定编译期最大 payload capacity（首版沿用当前默认 1024 octets），Init 只接受不超过该容量的生成配置；不引入动态内存。

---

## 阶段 1：现有单实例架构盘点与接口冻结

### 修改目标

建立可审查的旧到新映射，冻结公共接口和所有权，避免后续阶段继续引用旧单例或 W5300 专用语义。

### 涉及的现有文件

- 读取：`dsp/inc/c2837x_block.h`
- 读取：`dsp/src/c2837x_block.c`
- 读取：`dsp/inc/c2837x_block_algorithm.h`
- 读取：`dsp/inc/c2837x_block_config.h`
- 读取：`dsp/src/c2837x_block_config.c`
- 读取：`dsp/src/c2837x_block_global_variable.c`
- 读取：`app/C2837xBlockConfigurator.m`
- 读取：`app/c2837x_block_generate_dsp_files.m`
- 读取：`app/c2837x_block_generate_pc_files.m`
- 读取：`simulink/c2837x_block_sfun.c`
- 读取：`simulink/build_c2837x_block_sfun.m`

### 新增文件

- `docs/multi_iodevice_architecture_inventory.md`

### 明确不修改的用户文件

- `user/**`
- `dsp/src/my_algorithm.c`
- 全部 `dsp/**/c2837x_w5300_*`

### 实现步骤

- [ ] 记录所有全局/静态运行状态、W5300 直接调用、单例回调和生成器复制路径。
- [ ] 给每个现有文件标注目标归属：`core/algorithm`、`autogen`、PC shared support、legacy example 或用户文件。
- [ ] 在盘点文档冻结 `C2837xBlock_Init(block, generated_config, algorithm_ops, algorithm_ctx, iodevice_ops, iodevice_ctx)`、`C2837xBlock_Run(block)` 和只读 `last_error` 语义。
- [ ] 冻结 `protocol_octet_t` 低 8 bit 有效、Core 管理 step、adapter 只处理 user data 的边界。
- [ ] 列出 V1 error code `0`–`8` 与 Frozen 需求逐项对照结果。
- [ ] 记录旧 `plan.md` 中修改 W5300、固定 Socket 0、全局 callback 和单实例限制均已废止。

### 验证方法

运行：

```powershell
rg -n "g_ctx|g_tick_counter|first_connected|g_c2837x_block_instance_count|C2837X_BLOCK_SOCKET_NUM|C2837xBlock_On" dsp app simulink
```

预期：盘点文档逐项覆盖命令输出中的单例和硬件耦合点，没有未分类符号。

### 完成判据

- 所有当前文件均有唯一目标归属。
- 后续阶段使用的接口名称、buffer 单位和错误映射没有未定项。

### 风险和回退方式

- 风险：漏掉生成器字符串中的旧符号。
- 回退：本阶段只新增盘点文档；删除该文档即可回退，不影响现有实现。

---

## 阶段 2：Core 多实例化与全局运行状态清理

### 修改目标

把 DSP Core 从 W5300/全局单例改为可静态分配多个 `C2837xBlock` 的 CPU 无关基础库，并实现原子 `Init`。

### 涉及的现有文件

- 移动并重写：`dsp/inc/c2837x_block.h` → `core/algorithm/inc/c2837x_block.h`
- 移动并重写：`dsp/inc/c2837x_block_protocol.h` → `core/algorithm/inc/c2837x_block_protocol.h`
- 移动并重写：`dsp/src/c2837x_block.c` → `core/algorithm/src/c2837x_block.c`
- 移动并重写：`dsp/src/c2837x_block_protocol.c` → `core/algorithm/src/c2837x_block_protocol.c`

### 新增文件

- `tests/host/mock_iodevice.h`
- `tests/host/mock_iodevice.c`
- `tests/host/test_core_init.c`
- `tests/host/run_host_tests.ps1`

### 明确不修改的用户文件

- `user/**`
- `dsp/src/my_algorithm.c`
- 全部 `dsp/**/c2837x_w5300_*`

### 实现步骤

- [ ] 用 `<stdint.h>`、`<stdbool.h>` 和 `protocol_octet_t` 替换 Core 中的 `F28x_Project.h`、`Uint16/Uint32` 依赖。
- [ ] 将状态、RX/TX buffer、进度、`expected_step_index`、`algorithm_started`、注入引用和 `last_error` 全部放入调用者提供的 `C2837xBlock` 对象。
- [ ] 删除 `g_ctx`、`g_tick_counter`、函数静态连接标志、Socket 对象和所有 W5300 include/call。
- [ ] 定义每实例不可变 generated config，至少包含 protocol version、config hash、input/output data size 和 Core buffer capacity。
- [ ] 实现原子 `Init`：先校验全部指针、配置和容量，失败保持原状态；成功后一次性提交新引用并进入 `WAIT_LINK`。
- [ ] 选择公开 `C2837xBlock` 结构体以支持静态分配；把 `last_error` 标记为调用者只读诊断字段，不增加错误对象或历史。
- [ ] 在 host test 中创建两个 Block 和两个不同 context，验证两次 `Init` 不共享地址、状态、step、buffer 或错误记录。

### 验证方法

运行：

```powershell
tests\host\run_host_tests.ps1 -Test test_core_init
rg -n "F28x_Project|c2837x_w5300|static C2837xBlock|g_ctx|g_tick_counter|first_connected" core\algorithm
```

预期：host test 通过；第二条命令没有命中 CPU/W5300 或全局运行状态。

### 完成判据

- 两个静态 Block 可在同一 host 进程中独立初始化。
- 从 `UNINITIALIZED/ERROR` 的失败 Init 均保持原对象内容；活动状态 Init 返回 invalid state。

### 风险和回退方式

- 风险：移动公共头后现有 DSP 示例暂时不能直接编译。
- 回退：保留阶段 1 基线提交；整阶段使用一次独立提交，失败时回退该提交，不触碰 W5300 文件。

---

## 阶段 3：IoDevice 接口与有限 Run 状态机

### 修改目标

实现 Frozen 的 `read/write` 必需、`poll/end_session` 可选接口和 `UNINITIALIZED/WAIT_LINK/WAIT_START/RUNNING/ENDING/ERROR` 状态机。

### 涉及的现有文件

- 修改：`core/algorithm/inc/c2837x_block.h`
- 修改：`core/algorithm/src/c2837x_block.c`
- 修改：`core/algorithm/inc/c2837x_block_protocol.h`
- 修改：`core/algorithm/src/c2837x_block_protocol.c`
- 修改：`tests/host/mock_iodevice.h`
- 修改：`tests/host/mock_iodevice.c`
- 修改：`tests/host/test_core_init.c`

### 新增文件

- `tests/host/test_core_state_machine.c`

### 明确不修改的用户文件

- `user/**`
- `dsp/src/my_algorithm.c`
- 全部 `dsp/**/c2837x_w5300_*`

### 实现步骤

- [ ] 在 Core 公共头定义 IoDevice 操作表和 `DOWN/READY/ERROR`、部分 octet 进度、`LINK_DOWN`、`DONE/PENDING/ERROR` 结果语义。
- [ ] 让缺少 `poll` 等价于 `READY`，缺少 `end_session` 等价于 Core-only 会话收尾。
- [ ] 每次 `Run` 最多调用一次 poll、read、write、end_session，处理一个完整消息和一次 Algorithm process。
- [ ] 实现部分 header/payload/TX 跨 Run 保存以及 `read/write=0` 立即返回。
- [ ] 实现 `WAIT_START` 中启动响应尚未发完时断链仍调用一次 `on_stop`。
- [ ] 实现 `ENDING` 先完成/放弃最终错误 TX，下一次 Run 才调用 end_session；`ENDING` 不调用 poll/read。
- [ ] 实现 IoDevice `ERROR` 直接进入 `ERROR`，`Run(ERROR)` 不调用用户接口，成功重新 Init 是唯一 Core 恢复入口。
- [ ] 实现 `last_error` 保留、IoDevice 后发错误覆盖和成功新会话清零规则。

### 验证方法

运行：

```powershell
tests\host\run_host_tests.ps1 -Test test_core_state_machine
```

预期：Mock 调用计数证明每次 Run 不超过接口上限；零进度立即返回；ENDING 顺序和 ERROR 无调用均通过。

### 完成判据

- 所有六个状态都有测试覆盖的进入和退出路径。
- 一个成功启动的会话在停止、断链、可报告错误和 IoDevice 错误路径中恰好调用一次 `on_stop`。

### 风险和回退方式

- 风险：把最终错误响应的零进度放弃规则误用于正常 OUTPUT_DATA。
- 回退：状态机与测试同一提交；回退该提交恢复阶段 2 的多实例骨架。

---

## 阶段 4：Algorithm adapter 与 typed I/O 生成

### 修改目标

删除 DSP 全局 typed input/output，生成每实例 typed 类型和组合 adapter；Core 不接触实例类型或 step 之外的协议数据。

### 涉及的现有文件

- 修改：`app/c2837x_block_generate_dsp_files.m`
- 修改：`app/c2837x_block_validate_name.m`
- 停止生成/复制：`dsp/inc/c2837x_block_algorithm.h`
- 停止生成/复制：`dsp/inc/c2837x_block_config.h`
- 停止生成/复制：`dsp/src/c2837x_block_config.c`
- 停止生成/复制：`dsp/src/c2837x_block_global_variable.c`

### 新增文件

- `app/c2837x_block_validate_instance_name.m`
- 生成模板目标：`autogen/<instance>/dsp/c2837x_block_<instance>_config.h`
- 生成模板目标：`autogen/<instance>/dsp/c2837x_block_<instance>_algorithm.h`
- 生成模板目标：`autogen/<instance>/dsp/c2837x_block_<instance>_adapter.c`
- `tests/host/fixtures/example_algorithm.c`
- `tests/matlab/test_dsp_generation.m`

### 明确不修改的用户文件

- `user/**`
- `dsp/src/my_algorithm.c`
- 全部 `dsp/**/c2837x_w5300_*`

### 实现步骤

- [ ] 为 instance name 实现不改写字符的 ASCII C 标识符校验和不区分大小写冲突检查。
- [ ] 生成 `C2837xBlock_<instance>_InputData/OutputData` 和确定性 OnStep/可选生命周期声明。
- [ ] 生成 `C2837xBlock_<instance>_Process`，只解码 input data、调用用户 OnStep、编码 output data，不解析或生成 step。
- [ ] 让 adapter 检查固定 input/output data length，并在失败时返回 Algorithm/internal error。
- [ ] 删除生成全局 `c2837x_block_input/output` 和无 context 的全局 callback。
- [ ] DSP 生成器只生成实例差异文件，不再复制 W5300 HAL/Socket、用户算法或主循环。
- [ ] 用 tests fixture 提供 OnStep 实现，在 host 上编译生成 adapter，证明两个实例类型和符号不冲突。

### 验证方法

运行：

```powershell
matlab -batch "addpath('app'); run('tests/matlab/test_dsp_generation.m')"
tests\host\run_host_tests.ps1 -Test test_generated_adapters
```

预期：生成两个不同实例；生成文件不包含 `step_index` 解析、W5300、Socket 或全局 typed 数据。

### 完成判据

- 两个不同 typed I/O 实例可与同一 Core 一起 host 编译。
- 用户 Algorithm 只需实现生成头中声明的实例 OnStep；autogen 不包含用户算法实现。

### 风险和回退方式

- 风险：TI 编译器的 byte/word 存储模型与 host 不同。
- 回退：adapter 只依赖 `protocol_octet_t` 低 8 bit 契约；若 host 编译通过但用户硬件不通过，只修正 adapter 序列化，不修改 Core/IoDevice 边界。

---

## 阶段 5：每实例 Hash、step、V1 error response 与诊断

### 修改目标

让每实例 Hash、step、错误映射和 `last_error` 完全符合 Frozen 需求及现有 V1 wire format。

### 涉及的现有文件

- 修改：`app/c2837x_block_build_hash_string.m`
- 修改：`core/algorithm/src/c2837x_block.c`
- 修改：`core/algorithm/src/c2837x_block_protocol.c`
- 修改：`Protocol_Test_Vectors.md`
- 修改：`tests/host/test_core_state_machine.c`

### 新增文件

- `tests/matlab/test_instance_hash.m`
- `tests/host/test_protocol_vectors.c`

### 明确不修改的用户文件

- `user/**`
- `dsp/src/my_algorithm.c`
- 全部 `dsp/**/c2837x_w5300_*`

### 实现步骤

- [ ] 在 Hash 的 `protocol=0x0001` 后插入保留大小写的 `instance=<normalized_instance_name>`。
- [ ] 从 Hash 删除 PC endpoint、gateway/subnet、Socket、IoDevice 和硬件字段，保持其余 V1 字段顺序、数字格式、换行和 CRC32 参数。
- [ ] Core 从 INPUT_DATA 前 4 octet 解析 step，只把 user data 交给 adapter，并把当前 step 写回 OUTPUT_DATA 前 4 octet。
- [ ] 仅在完整 OUTPUT_DATA 被 write 全部接受后递增 DSP step；保留 uint32 回绕。
- [ ] 固定 error code 1–8 的映射；可报告错误必须产生 RESPONSE(error)，致命 IoDevice 错误不得产生响应。
- [ ] 实现最终错误响应零进度放弃规则和 `last_error` 的保留/清除生命周期。
- [ ] 更新黄金向量，增加两个不同 instance name 的 Hash 和同一 user data 下的 INPUT/OUTPUT frame。

### 验证方法

运行：

```powershell
matlab -batch "addpath('app'); run('tests/matlab/test_instance_hash.m')"
tests\host\run_host_tests.ps1 -Test test_protocol_vectors
```

预期：PC/DSP 黄金 octet 完全一致；error code、step 写入位置和递增时机全部通过。

### 完成判据

- V1 frame/message/error wire 值与 `spec_v2_3.md` 一致。
- Hash 只因实例协议配置变化而变化，不因 IoDevice/PC endpoint 变化而变化。

### 风险和回退方式

- 风险：旧 Hash 与新实例 Hash 不兼容。
- 回退：这是 Frozen 要求的有意不兼容；回退整个阶段可恢复旧 Hash，但不得在新旧算法间增加兼容分支。

---

## 阶段 6：现有 App 多实例配置改造

### 修改目标

把现有单实例 App 改成一个工程内管理多个 Algorithm Instance，并完全移除 DSP 设备、Socket 和 W5300 缓存配置。

### 涉及的现有文件

- 修改：`app/C2837xBlockConfigurator.m`
- 修改：`app/c2837x_block_generate_dsp_files.m`
- 修改：`app/c2837x_block_generate_pc_files.m`
- 修改：`app/c2837x_block_build_hash_string.m`
- 修改：`app/c2837x_block_validate_name.m`

### 新增文件

- `app/c2837x_block_validate_project_config.m`
- `app/c2837x_block_generate_project.m`
- `tests/matlab/test_multi_instance_config.m`

### 明确不修改的用户文件

- `user/**`
- `dsp/src/my_algorithm.c`
- 全部 `dsp/**/c2837x_w5300_*`

### 实现步骤

- [ ] 将 App 数据模型改成 project config + `instances` 数组；project 级只保留 autogen output root 和 Core max payload，实例只含 name、PC TCP endpoint、sample time、I/O、ABI/double。
- [ ] 增加实例列表、新增、删除、选择和编辑；复用现有 I/O table，不新建第二套工具。
- [ ] 从 UI、保存文件、Hash 和生成参数删除 gateway、subnet、MAC、Socket、TX/RX 缓存。
- [ ] 对实例名和派生 S-Function/MEX/符号/目录执行不区分大小写唯一性检查；对 endpoint 执行 `(address, port)` 唯一性检查。
- [ ] 保存/加载完整多实例 `.mat` 配置；旧单实例配置明确拒绝，不做迁移。
- [ ] `c2837x_block_generate_project` 顺序生成全部实例，并写一个简单 manifest：生成器版本、规范化工程摘要、实例列表、生成文件列表。
- [ ] 生成失败时报告实例名和原始错误，不增加 evidence、阶段状态机或回滚系统。

### 验证方法

运行：

```powershell
matlab -batch "addpath('app'); run('tests/matlab/test_multi_instance_config.m')"
rg -n "socket_num|gateway|subnet|mac|socket0_tx|socket0_rx|IoDevice|SciChannel" app
```

预期：MATLAB 测试完成双实例保存/加载/生成；第二条命令只允许出现在明确拒绝旧字段的迁移错误文本中。

### 完成判据

- App 可一次生成两个不同 Hash、不同 typed I/O 的实例。
- App 配置和生成物没有 DSP IoDevice、Socket、SCI channel 或硬件初始化字段。

### 风险和回退方式

- 风险：42 KB 单类 App 修改面较大。
- 回退：先把 project config 校验/生成放入独立 helper，再改 UI；UI 提交可单独回退而保留已验证 helper。

---

## 阶段 7：多 S-Function/MEX 生成和构建

### 修改目标

从同一 PC shared support 为每实例生成唯一 S-Function/MEX，并删除单实例限制和输出提前提交问题。

### 涉及的现有文件

- 修改：`simulink/c2837x_block_sfun.c`
- 修改：`simulink/c2837x_block_sfun.h`
- 修改：`simulink/c2837x_block_protocol.c`
- 修改：`simulink/c2837x_block_protocol.h`
- 修改：`simulink/build_c2837x_block_sfun.m`
- 修改：`app/c2837x_block_generate_pc_files.m`
- 修改：`app/c2837x_block_generate_project.m`

### 新增文件

- `app/c2837x_block_build_all_mex.m`
- 生成模板目标：`autogen/<instance>/pc/c2837x_block_<instance>_pc_config.h`
- 生成模板目标：`autogen/<instance>/pc/c2837x_block_<instance>_sfun_io.c`
- 生成模板目标：`autogen/<instance>/pc/c2837x_block_<instance>_sfun.c`
- 生成模板目标：`autogen/<instance>/pc/build_c2837x_block_<instance>_sfun.m`
- `tests/matlab/test_multi_mex_build_args.m`

### 明确不修改的用户文件

- `user/**`
- `dsp/src/my_algorithm.c`
- 全部 `dsp/**/c2837x_w5300_*`

### 实现步骤

- [ ] 把 `simulink/c2837x_block_sfun.c` 作为唯一 wrapper 模板源，由 PC 生成器写出带唯一 `S_FUNCTION_NAME` 的实例 wrapper；MEX output name由实例构建参数提供。
- [ ] 删除 `g_c2837x_block_instance_count` 和所有“Only one instance allowed”路径；每个 block 只使用自己的 PWork context。
- [ ] 保持 `simulink/c2837x_block_pc_socket.*` 和 `simulink/c2837x_block_protocol.*` 为共享 PC TCP support，不称为 IoDevice。
- [ ] 把 OUTPUT_DATA 校验顺序改为：type、length、DSP error、step、完整字段边界全部成功后，才调用生成的端口提交函数。
- [ ] 让每实例生成文件使用唯一 include guard、C symbol、S-Function name、MEX name 和目录。
- [ ] 将 `build_c2837x_block_sfun` 参数化为实例源目录、实例 wrapper、实例名和输出目录；共享 socket/protocol 源始终从仓库 `simulink/` 读取，保留 Windows/MinGW 与 MSVC 现有链接逻辑。
- [ ] `c2837x_block_build_all_mex` 遍历全部实例，逐一构建并在失败时报告实例；不增加复杂制品事务。

### 验证方法

运行：

```powershell
matlab -batch "addpath('app'); addpath('simulink'); run('tests/matlab/test_multi_mex_build_args.m')"
rg -n "Only one instance allowed|g_c2837x_block_instance_count" simulink app
```

预期：构建参数测试产生两个不同 S-Function/MEX 名；第二条命令无命中。实际 MEX 编译在本阶段执行前仍标记“未验证”。

### 完成判据

- 两个实例的 MEX 构建命令不存在文件名、宏或符号冲突。
- 失败 sample hit 在校验完成前没有任何输出端口写入。

### 风险和回退方式

- 风险：已加载 MEX 被 Windows 锁定导致替换失败。
- 回退：构建失败直接保留已存在文件并报告用户先卸载模型/MEX；不实现跨文件回滚系统。

---

## 阶段 8：host-side Core/Mock 回归门

### 修改目标

用一个小型 GCC 测试程序覆盖 Frozen Core 契约，不创建 DSP 测试工程或大型测试矩阵。

### 涉及的现有文件

- 修改：`tests/host/mock_iodevice.c`
- 修改：`tests/host/test_core_init.c`
- 修改：`tests/host/test_core_state_machine.c`
- 修改：`tests/host/test_protocol_vectors.c`
- 修改：`tests/host/run_host_tests.ps1`
- 读取：`Protocol_Test_Vectors.md`

### 新增文件

- `tests/host/test_two_instances.c`

### 明确不修改的用户文件

- `user/**`
- `dsp/src/my_algorithm.c`
- 全部 `dsp/**/c2837x_w5300_*`

### 实现步骤

- [ ] 覆盖两个静态 Block、不同 config/hash/typed adapter/context 和 1000 次独立交换。
- [ ] 覆盖部分 header、部分 payload、部分 TX、`read/write=0` 和单次 Run 调用上限。
- [ ] 覆盖 `poll/end_session=NULL` 缺省行为与 end_session `PENDING→DONE/ERROR`。
- [ ] 覆盖 Init 原子失败、ERROR 重新 Init、`last_error` 保留和成功新会话清零。
- [ ] 覆盖 V1 error code 1–8、可报告错误 RESPONSE(error) 和 IoDevice ERROR 直接 ERROR。
- [ ] 覆盖 OnStart 成功但启动响应未完成时断链、process 失败和所有 on_stop 恰好一次路径。
- [ ] 覆盖 step 仅由 Core 解析/生成，OUTPUT_DATA 完整接受后才递增和 uint32 回绕。

### 验证方法

运行：

```powershell
tests\host\run_host_tests.ps1
```

预期：脚本使用 `E:\Mingw_w64\mingw64\bin\gcc.exe` 或 PATH 中 GCC，以 `-std=c11 -Wall -Wextra -Werror` 编译并运行全部 host tests，最终返回 exit code 0。

### 完成判据

- Frozen Core 的关键正常路径、状态边界和错误分流均由可重复 host test 证明。
- 测试不 include 或链接任何 W5300、TI DSP 或用户文件。

### 风险和回退方式

- 风险：测试为追求覆盖引入大规模 fake 框架。
- 回退：Mock 只保留操作表、预置 RX/TX octet 队列和调用计数；删除没有直接需求对应的测试分支。

---

## 阶段 9：PC 双 S-Function、双 Mock endpoint 验证

### 修改目标

在同一 Normal mode 模型中运行两个不同 MEX，各连接一个独立 TCP Mock endpoint，验证 1000 步无串扰。

### 涉及的现有文件

- 读取：`simulink/create_test_model.m`
- 读取：`simulink/c2837x_block_c_function_test.slx`
- 读取：`simulink/c2837x_block_test.slx`
- 使用：阶段 7 生成的两个实例 MEX

### 新增文件

- `tests/pc/mock_dsp_endpoint.c`
- `tests/pc/create_dual_sfun_model.m`
- `tests/pc/run_dual_sfun_smoke.ps1`

### 明确不修改的用户文件

- `user/**`
- `dsp/src/my_algorithm.c`
- 全部 `dsp/**/c2837x_w5300_*`
- 现有单实例 `.slx` 文件

### 实现步骤

- [ ] 用标准 socket 编写一个可通过命令行指定 port、config hash 和确定性输出规则的 Mock endpoint；不引入第三方依赖。
- [ ] PowerShell 编排器编译 Mock，启动两个独立进程，并保证退出时终止两个进程。
- [ ] MATLAB 脚本创建临时双 S-Function 模型，两个实例使用不同端口、Hash 和 typed I/O。
- [ ] 两个 endpoint 分别验证 SIM_START、1000 个 INPUT_DATA step、OUTPUT_DATA step 和 SIM_STOP。
- [ ] 模型记录两个输出序列并验证各自规则、step 单调和不存在跨实例数据。
- [ ] 增加一个 RESPONSE(error) 场景，确认 S-Function 在失败 sample hit 不写输出并设置 Simulink error status。

### 验证方法

运行：

```powershell
tests\pc\run_dual_sfun_smoke.ps1
```

预期：脚本实际构建两个 MEX、启动两个 Mock、运行 Normal mode 1000 步并返回 exit code 0；任一环节未执行时结果必须标记“未验证”。

### 完成判据

- 同一模型加载两个唯一 MEX 并完成 1000 步。
- 两个 PC context 的 socket、Hash、step、I/O 和错误互不串扰。

### 风险和回退方式

- 风险：MATLAB/MEX 文件锁或后台 Mock 进程残留。
- 回退：编排器在 `finally` 等价清理路径中关闭模型、clear MEX 并终止自己启动的进程；不删除用户文件。

---

## 阶段 10：用户 DSP/W5300 集成说明与硬件验收入口

### 修改目标

向用户交付最小、明确的集成契约和硬件验收入口，不代替用户实现 IoDevice、初始化或 DSP 测试。

### 涉及的现有文件

- 修改：`README.md`
- 读取：`requirements_multi_iodevice.md`
- 读取：`core/algorithm/inc/c2837x_block.h`
- 读取：现有 W5300 HAL/Socket，仅用于列出用户适配边界

### 新增文件

- `docs/multi_iodevice_user_integration.md`
- `docs/multi_iodevice_hardware_acceptance.md`

### 明确不修改的用户文件

- `user/**`
- `dsp/src/my_algorithm.c`
- 全部 `dsp/**/c2837x_w5300_*`
- 用户 CCS 工程、主循环和硬件初始化代码

### 实现步骤

- [ ] 更新 README 目录和快速开始，删除“App 配置 Socket/W5300 缓存”和“生成器复制 W5300 驱动”的旧说明。
- [ ] 文档化用户负责的设备初始化、8 Socket 固定均分缓存、IoDevice context/ops、Algorithm context/ops 和运行时映射。
- [ ] 给出两个静态 Block 的声明、Init 注入顺序和 main loop 轮询顺序，只说明接口调用，不提供具体 W5300/SCI 实现。
- [ ] 说明 W5300 end_session 可关闭当前 Socket 并重新监听，SCI end_session 可清缓存；具体动作由用户决定。
- [ ] 说明 ERROR 后用户外部处理设备，再重新 Init 或重启 DSP；没有 Reset API。
- [ ] 硬件验收清单要求两个 W5300 Socket、两个 IoDevice、两个 Algorithm、两个 S-Function 完成 1000 步，并验证一次 SIM_STOP→end_session→重新监听→新 SIM_START。
- [ ] 明确所有未实际执行的 CCS、DSP 和硬件结果标记为“未验证”。

### 验证方法

运行：

```powershell
rg -n "SocketField|SocketTxField|SocketRxField|C2837X_BLOCK_SOCKET_NUM|copy.*w5300|Only one instance" README.md docs app core simulink
```

预期：仅在历史说明或明确禁止项中出现；新用户流程不要求修改 Core 或生成器来选择设备。

### 完成判据

- 用户可仅根据文档完成自己的 IoDevice、实例映射和主循环集成。
- 文档没有声称 AI/Codex 已完成 DSP、W5300 或硬件验证。

### 风险和回退方式

- 风险：文档示例误写成 W5300 专用公共接口。
- 回退：以 `core/algorithm/inc/c2837x_block.h` 为唯一接口源，删除任何具体寄存器或 Socket API 示例。

---

## 实施完成总门槛

- Frozen 需求编号、V1 wire format 和 error code 无变化。
- `core/algorithm` 无 TI/W5300 include、无全局运行实例、无设备分支。
- `autogen` 无用户 Algorithm、IoDevice、Socket、SCI channel、硬件配置或缓存表。
- App 能保存、加载、生成并构建至少两个实例，且派生名称无大小写冲突。
- host tests 全部通过；双 S-Function/双 Mock 1000 步实际执行后通过。
- W5300 HAL/Socket 和用户文件的 Git diff 为空。
- DSP/W5300 硬件验收仍由用户执行；未执行前明确标记“未验证”。

## 建议提交边界

每个阶段使用一个独立提交；阶段 2–5 如改动过大，可按“测试/接口”和“最小实现”拆成两个提交，但不得把不同阶段混在同一提交。任何阶段失败时只回退本阶段提交，不使用 `git reset --hard`，不修改或还原用户未提交内容。
