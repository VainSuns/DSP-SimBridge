# C2837xBlock 多 IoDevice / 多算法实施计划

> **执行依据：** `requirements_multi_iodevice.md`（Frozen）
>
> **执行约束：** 实施时逐阶段完成、验证和评审；不得跨过未通过的阶段。

**目标：** 在保持 V1 wire format 的前提下，把当前单 W5300/单算法/单 S-Function 实现改造成可由用户运行时注入 IoDevice 的静态多 Block 架构，并由现有 App 生成多个 Algorithm Instance 和多个独立 MEX。

**架构：** `core/algorithm` 只保存通用协议、状态机和实例状态；`autogen` 保存每实例不可变配置、typed adapter 和 PC wrapper；用户在 `user/` 或自己的 DSP 工程中实现 Algorithm、IoDevice、初始化、映射和主循环。PC 端继续使用同步 TCP client，每个生成的 S-Function/MEX 拥有独立 context。

**技术栈：** ISO C11 可移植 Core、TI C2000 用户集成、项目实际支持且可从 PATH 启动的 MATLAB/Simulink、C MEX S-Function、MATLAB App/uifigure、Windows sockets，以及由 `CC` 环境变量或 PATH 选择的 C11 host compiler。

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
    void *iodevice_ctx,
    protocol_octet_t *rx_buffer,
    uint32_t rx_capacity,
    protocol_octet_t *tx_buffer,
    uint32_t tx_capacity);

C2837xBlockRunResult C2837xBlock_Run(C2837xBlock *block);
```

- `C2837xBlockGeneratedConfig` 固定保存 protocol version、config hash、input/output data size、input/output payload size 和本实例所需 RX/TX capacity；不得保存 endpoint、Socket、SCI 或 IoDevice 信息。
- `C2837xBlockAlgorithmOps` 固定包含可空 `on_start`、必需 `process`、可空 `on_stop`，签名与 Frozen 需求一致。
- `C2837xBlockIoDeviceOps` 固定包含可空 `poll`、必需 `read/write`、可空 `end_session`。
- `read/write` 返回 `>0` 表示 octet 进度、`0` 表示无进度、`C2837X_BLOCK_IO_LINK_DOWN=-1`、`C2837X_BLOCK_IO_ERROR=-2`。
- `poll` 返回 `DOWN/READY/ERROR`；`end_session` 返回 `DONE/PENDING/ERROR`。
- `C2837xBlockResult` 固定区分 `OK/INVALID_ARGUMENT/INVALID_STATE/CONFIG_ERROR`；`C2837xBlockRunResult` 固定区分 `IDLE/PROGRESSED/ERROR`。
- `last_error` 使用简单 `uint16_t`：`0` 为 NONE，`1`–`8` 直接保存 V1 error code，`0x0100` 表示 poll/read/write IoDevice error，`0x0101` 表示 end_session error；这些扩展诊断值不得上 wire。
- App 根据每实例 I/O 精确计算 data、payload、RX frame 和 TX frame capacity；不提供人工 max payload 配置。
- `autogen` 为每实例生成精确尺寸的静态 RX/TX buffer。Core 只保存注入的 buffer 指针和 capacity，不动态分配，也不保存统一最大数组。
- RX capacity 必须至少容纳 header 加 `max(SIM_START payload, INPUT_DATA payload)`；TX capacity 必须至少容纳 header 加 `max(RESPONSE payload, OUTPUT_DATA payload)`。Init 在提交状态前原子校验指针和精确容量。

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
- 修改：`spec_v2_3.md`

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
- [ ] 在任何实现代码修改前，把 Frozen 需求中的多实例 Hash、Core 独占 step、多 S-Function 和 DSP IoDevice wire-octet 边界同步到 `spec_v2_3.md`；保持既有 V1 frame、消息类型和 error code 不变。

### 验证方法

运行：

```powershell
rg -n "g_ctx|g_tick_counter|first_connected|g_c2837x_block_instance_count|C2837X_BLOCK_SOCKET_NUM|C2837xBlock_On" dsp app simulink
rg -n "instance=|step_index|多 S-Function|wire octet|IoDevice" spec_v2_3.md
```

预期：盘点文档逐项覆盖命令输出中的单例和硬件耦合点，没有未分类符号。

### 完成判据

- 所有当前文件均有唯一目标归属。
- 后续阶段使用的接口名称、buffer 单位和错误映射没有未定项。
- `spec_v2_3.md` 已成为多实例 Hash、step 所有权、多 S-Function 和 wire-octet 边界的同步协议事实源，且历史 V1 wire 定义未改变。

### 风险和回退方式

- 风险：同步 `spec_v2_3.md` 时误改历史 V1 wire 定义，或漏掉生成器字符串中的旧符号。
- 回退：协议同步使用独立提交；若 V1 frame/message/error golden diff 发生变化，回退该规格提交并重新仅加入多实例增量，不进入阶段 2。

---

## 阶段 2：Core 多实例化与全局运行状态清理

### 修改目标

把 DSP Core 从 W5300/全局单例改为可静态分配多个 `C2837xBlock` 的 CPU 无关基础库，并实现原子 `Init`。

### 涉及的现有文件

- 修改：`dsp/inc/c2837x_block.h`
- 修改：`dsp/inc/c2837x_block_protocol.h`
- 修改：`dsp/src/c2837x_block.c`
- 修改：`dsp/src/c2837x_block_protocol.c`
- 条件修改：`app/c2837x_block_generate_dsp_files.m`
- 条件修改：`README.md`
- 候选迁移目标：`core/algorithm/inc/c2837x_block.h`
- 候选迁移目标：`core/algorithm/inc/c2837x_block_protocol.h`
- 候选迁移目标：`core/algorithm/src/c2837x_block.c`
- 候选迁移目标：`core/algorithm/src/c2837x_block_protocol.c`

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
- [ ] 根据阶段 1 盘点决定 Core 是否迁移：若仓库生成器、README、现有 DSP/CCS include/source 路径或用户外部工程仍依赖 `dsp/inc`、`dsp/src`，首版原地重写；只有能同时更新全部构建路径且不破坏外部工程时才迁移到 `core/algorithm`。
- [ ] 若执行迁移，在 `dsp/inc` 保留同名兼容头转发到新公共头，并同步更新生成器复制路径和 README 构建路径；不得要求用户立即修改现有 CCS include 名称。若不迁移，在阶段 1 盘点文档中把现有 DSP Core 文件标记为 `core/algorithm` 所有权。
- [ ] 将状态、RX/TX buffer 指针和 capacity、进度、`expected_step_index`、`algorithm_started`、注入引用和 `last_error` 全部放入调用者提供的 `C2837xBlock` 对象；Core 对象不得包含统一最大 RX/TX 数组。
- [ ] 删除 `g_ctx`、`g_tick_counter`、函数静态连接标志、Socket 对象和所有 W5300 include/call。
- [ ] 定义每实例不可变 generated config，包含 protocol version、config hash、input/output data/payload size 和本实例精确 RX/TX capacity。
- [ ] 实现原子 `Init`：接收每实例 RX/TX buffer 指针和 capacity，先校验全部指针、配置及容量，失败保持原状态；成功后一次性提交新引用并进入 `WAIT_LINK`。
- [ ] 选择公开 `C2837xBlock` 结构体以支持静态分配；把 `last_error` 标记为调用者只读诊断字段，不增加错误对象或历史。
- [ ] 在 host test 中创建两个不同 payload 尺寸的 Block、buffer 和 context，验证实例不共享状态；分别传入不足 RX 和不足 TX capacity，确认 Init 失败且整个 Block 对象逐 byte 保持不变。

### 验证方法

运行：

```powershell
tests\host\run_host_tests.ps1 -Test test_core_init
$roots = @('dsp\inc', 'dsp\src'); if (Test-Path 'core\algorithm') { $roots += 'core\algorithm' }
rg -n -g "c2837x_block*" "F28x_Project|c2837x_w5300|static C2837xBlock|g_ctx|g_tick_counter|first_connected" $roots
```

预期：host test 通过；第二条命令在实际采用的 Core 路径中没有命中 CPU/W5300 或全局运行状态；未采用的候选目录可以不存在。

### 完成判据

- 两个静态 Block 可在同一 host 进程中独立初始化。
- 不同 payload 尺寸使用不同静态 buffer；容量不足时从 `UNINITIALIZED/ERROR` 的失败 Init 均保持原对象内容，活动状态 Init 返回 invalid state。
- 现有 DSP/CCS 工程原 include 路径仍可用，或已通过兼容头和构建路径调整得到等价验证。

### 风险和回退方式

- 风险：物理迁移公共头会影响仓库外 CCS 工程。
- 回退：无法证明外部路径安全时保持原地重写；若迁移验证失败，恢复原路径并保留兼容头，不触碰 W5300 或用户工程。

---

## 阶段 3：IoDevice 接口与完整协议状态机

### 修改目标

完整实现并独立验收 Frozen 的 IoDevice 接口、六状态状态机、step 所有权、V1 error response、`ENDING/ERROR` 和 `last_error` 生命周期。

### 涉及的现有文件

- 修改：阶段 2 最终采用的 `dsp/inc/c2837x_block.h` 或 `core/algorithm/inc/c2837x_block.h`
- 修改：阶段 2 最终采用的 `dsp/src/c2837x_block.c` 或 `core/algorithm/src/c2837x_block.c`
- 修改：阶段 2 最终采用的 `dsp/inc/c2837x_block_protocol.h` 或 `core/algorithm/inc/c2837x_block_protocol.h`
- 修改：阶段 2 最终采用的 `dsp/src/c2837x_block_protocol.c` 或 `core/algorithm/src/c2837x_block_protocol.c`
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
- [ ] Core 从 INPUT_DATA 前 4 octet 解析并校验 step，只把 user input data 交给 adapter；Core 把当前 step 写入 OUTPUT_DATA，并且只在完整 OUTPUT_DATA 被 write 接受后递增，保留 uint32 回绕。
- [ ] 实现 V1 error code 1–8 确定性映射；协议/Algorithm 可报告错误必须生成 RESPONSE(error)，不得发送部分 OUTPUT_DATA。
- [ ] 实现 `WAIT_START` 中启动响应尚未发完时断链仍调用一次 `on_stop`。
- [ ] 实现 `ENDING` 先完成/放弃最终错误 TX，下一次 Run 才调用 end_session；`ENDING` 不调用 poll/read。
- [ ] 实现 IoDevice `ERROR` 直接进入 `ERROR`，`Run(ERROR)` 不调用用户接口，成功重新 Init 是唯一 Core 恢复入口。
- [ ] 实现 `last_error` 在可报告错误后跨 `ENDING→WAIT_LINK` 保留、IoDevice 后发错误覆盖、成功新会话和成功重新 Init 清零规则。

### 验证方法

运行：

```powershell
tests\host\run_host_tests.ps1 -Test test_core_state_machine
```

预期：Mock 调用计数证明每次 Run 不超过接口上限；零进度立即返回；step、error code 1–8、ENDING 顺序、ERROR 无调用和 last_error 生命周期均通过。

### 完成判据

- 所有六个状态都有测试覆盖的进入和退出路径。
- 一个成功启动的会话在停止、断链、可报告错误和 IoDevice 错误路径中恰好调用一次 `on_stop`。
- 阶段 3 结束时 Core 的 step、V1 error response、ENDING、ERROR 和 last_error 已完整可用，不依赖阶段 5 补充运行逻辑。

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
- 生成模板目标：`autogen/<instance>/dsp/c2837x_block_<instance>_types.h`
- 生成模板目标：`autogen/<instance>/dsp/c2837x_block_<instance>_config.h`
- 生成模板目标：`autogen/<instance>/dsp/c2837x_block_<instance>_config.c`
- 生成模板目标：`autogen/<instance>/dsp/c2837x_block_<instance>_adapter.h`
- 生成模板目标：`autogen/<instance>/dsp/c2837x_block_<instance>_adapter.c`
- `tests/host/fixtures/example_algorithm.c`
- `tests/matlab/test_dsp_generation.m`

### 明确不修改的用户文件

- `user/**`
- `dsp/src/my_algorithm.c`
- 全部 `dsp/**/c2837x_w5300_*`

### 实现步骤

- [ ] 为 instance name 实现不改写字符的 ASCII C 标识符校验和不区分大小写冲突检查。
- [ ] 在 `<instance>_types.h` 生成 `C2837xBlock_<instance>_InputData/OutputData` typed 定义。
- [ ] 在 `<instance>_config.h/.c` 声明并定义唯一 `C2837xBlockGeneratedConfig C2837xBlock_<instance>_Config`，以及按本实例精确 RX/TX capacity 定义的静态 `C2837xBlock_<instance>_RxBuffer/TxBuffer` 和 capacity 常量。
- [ ] 在 `<instance>_adapter.h` 声明必需 `C2837xBlock_<instance>_OnStep`、可选 OnStart/OnStop 和通用 `C2837xBlock_<instance>_Process`；在 `<instance>_adapter.c` 实现 Process，只解码 input data、调用用户 OnStep、编码 output data，不解析或生成 step。
- [ ] 让 adapter 检查固定 input/output data length，并在失败时返回 Algorithm/internal error。
- [ ] 删除生成全局 `c2837x_block_input/output` 和无 context 的全局 callback。
- [ ] DSP 生成器只生成实例差异文件，不再复制 W5300 HAL/Socket、用户算法或主循环。
- [ ] App 根据每实例 I/O 自动计算 input/output data、payload、RX/TX frame capacity；删除任何人工 max payload 输入，只保留 V1 `length <= 65535` 和偶数字节校验。
- [ ] 用第一组 tests fixture 只实现必需 OnStep，确认 OnStart/OnStop 未实现时可链接；用第二组 fixture 实现 OnStart/OnStop 并注入对应通用操作指针，确认生命周期回调被正确调用。
- [ ] 为两个不同 payload 尺寸实例生成不同长度静态 buffer，并把各自 buffer/capacity 传给 Init。

### 验证方法

运行：

```powershell
matlab -batch "addpath('app'); run('tests/matlab/test_dsp_generation.m')"
tests\host\run_host_tests.ps1 -Test test_generated_adapters
```

预期：生成两个不同实例和完整的 types/config/adapter 五类文件；仅 OnStep fixture 与启用生命周期 fixture 均可链接；生成文件不包含 `step_index` 解析、W5300、Socket 或全局 typed 数据。

### 完成判据

- 两个不同 typed I/O 实例可与同一 Core 一起 host 编译。
- 用户 Algorithm 只需实现生成头中声明的实例 OnStep；autogen 不包含用户算法实现。
- 每实例 config 对象、Process 声明和精确尺寸 RX/TX 静态 buffer 均存在，且 Init 使用生成 capacity 完成原子校验。

### 风险和回退方式

- 风险：TI 编译器的 byte/word 存储模型与 host 不同。
- 回退：adapter 只依赖 `protocol_octet_t` 低 8 bit 契约；若 host 编译通过但用户硬件不通过，只修正 adapter 序列化，不修改 Core/IoDevice 边界。

---

## 阶段 5：每实例 Hash、协议向量与事实源回归

### 修改目标

完成每实例 Hash 变更，并用既有 V1 黄金向量和阶段 1 已同步的 `spec_v2_3.md` 证明协议事实源没有漂移；本阶段不再修改状态机、step 或错误处理。

### 涉及的现有文件

- 修改：`app/c2837x_block_build_hash_string.m`
- 修改：`Protocol_Test_Vectors.md`
- 读取：`spec_v2_3.md`

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
- [ ] 保留 `Protocol_Test_Vectors.md` 中所有现有 V1 向量及其历史 byte 值，只在文件末尾追加多实例 Hash 和实例隔离相关向量。
- [ ] 增加两个仅 instance name 不同的 Hash 向量，以及 IoDevice/PC endpoint 改变但 Hash 不变的向量。
- [ ] 用既有 V1 向量回归 frame header、SIM_START、INPUT_DATA、OUTPUT_DATA、RESPONSE 和 error code；不得用新向量替换历史向量。
- [ ] 对照阶段 1 更新后的 `spec_v2_3.md`，确认多实例 Hash、Core step 所有权、多 S-Function 和 wire-octet 边界与生成器结果一致。

### 验证方法

运行：

```powershell
matlab -batch "addpath('app'); run('tests/matlab/test_instance_hash.m')"
tests\host\run_host_tests.ps1 -Test test_protocol_vectors
git diff -- Protocol_Test_Vectors.md
```

预期：Hash 测试通过；全部历史 V1 向量继续通过；`Protocol_Test_Vectors.md` 的 diff 只在末尾新增多实例向量，没有删除或改写历史向量。

### 完成判据

- V1 frame/message/error wire 值与 `spec_v2_3.md` 一致。
- Hash 只因实例协议配置变化而变化，不因 IoDevice/PC endpoint 变化而变化。
- 阶段 3 的状态机、step、错误响应和诊断实现无新增修改。

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

- [ ] 将 App 数据模型改成 project config + `instances` 数组；project 级只保留 autogen output root，实例只含 name、PC TCP endpoint、sample time、I/O、ABI/double。
- [ ] 增加实例列表、新增、删除、选择和编辑；复用现有 I/O table，不新建第二套工具。
- [ ] 从 UI、保存文件、Hash 和生成参数删除 gateway、subnet、MAC、Socket、TX/RX 缓存和人工 max payload；App 只根据每实例 I/O 计算精确 data/payload/buffer 长度。
- [ ] 对实例名和派生 S-Function/MEX/符号/目录执行不区分大小写唯一性检查；对 endpoint 执行 `(address, port)` 唯一性检查。
- [ ] 保存/加载完整多实例 `.mat` 配置；旧单实例配置明确拒绝，不做迁移。
- [ ] `c2837x_block_generate_project` 顺序生成全部实例，并写一个简单 manifest：生成器版本、规范化工程摘要、实例列表、生成文件列表。
- [ ] 生成失败时报告实例名和原始错误，不增加 evidence、阶段状态机或回滚系统。

### 验证方法

运行：

```powershell
matlab -batch "addpath('app'); run('tests/matlab/test_multi_instance_config.m')"
rg -n "socket_num|gateway|subnet|mac|socket0_tx|socket0_rx|MaxPayloadField|IoDevice|SciChannel" app
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
- `tests/matlab/test_two_mex_build.m`

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
- [ ] 使用阶段 6 的两个真实生成实例调用 `c2837x_block_build_all_mex`，实际生成两个唯一名称 MEX，而不是只比较构建参数。
- [ ] 在 MATLAB 中对两个 MEX 分别执行 `which` 和 `exist(name,'file') == 3`；随后用一个故意缺失实例 wrapper 的测试配置触发失败，确认错误标识或消息包含具体实例名。

### 验证方法

运行：

```powershell
matlab -batch "addpath('app'); addpath('simulink'); run('tests/matlab/test_multi_mex_build_args.m')"
matlab -batch "addpath('app'); addpath('simulink'); run('tests/matlab/test_two_mex_build.m')"
rg -n "Only one instance allowed|g_c2837x_block_instance_count" simulink app
```

预期：构建参数测试和实际构建测试均通过；MATLAB 能定位两个 `exist(...,'file') == 3` 的 MEX；负向构建测试报告指定失败实例；最后一条命令无命中。

### 完成判据

- 两个实例 MEX 已实际成功生成，并可被 MATLAB 定位或加载。
- 构建失败能报告具体实例，不留下“哪个实例失败”未确定的错误。
- 生成 wrapper 的输出提交调用位于 type、length、DSP error、step 和字段边界全部校验之后；端到端失败行为由阶段 9B 独立验证。

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
- [ ] 使用两个不同 input/output payload 尺寸和不同精确 RX/TX buffer 的实例；覆盖 RX 或 TX capacity 少 1 octet 时 Init 失败且 Block 对象、原引用和 last_error 不变。
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

预期：脚本优先使用 `CC` 环境变量指定的编译器，否则从 PATH 查找支持 C11 的 `gcc`、`clang` 或等价编译器，以 `-std=c11 -Wall -Wextra -Werror` 或该编译器的等价严格选项编译并运行全部 host tests，最终返回 exit code 0。

### 完成判据

- Frozen Core 的关键正常路径、状态边界和错误分流均由可重复 host test 证明。
- 测试不 include 或链接任何 W5300、TI DSP 或用户文件。

### 风险和回退方式

- 风险：测试为追求覆盖引入大规模 fake 框架。
- 回退：Mock 只保留操作表、预置 RX/TX octet 队列和调用计数；删除没有直接需求对应的测试分支。

---

## 阶段 9：PC 正常双实例与 RESPONSE(error) 独立验证

### 修改目标

用两个互不依赖的验证入口分别证明正常双实例 1000 步无串扰，以及 RESPONSE(error) 时模型停止且失败步不提交输出。

### 涉及的现有文件

- 读取：`simulink/create_test_model.m`
- 读取：`simulink/c2837x_block_c_function_test.slx`
- 读取：`simulink/c2837x_block_test.slx`
- 使用：阶段 7 生成的两个实例 MEX

### 新增文件

- `tests/pc/mock_dsp_endpoint.c`
- `tests/pc/create_dual_sfun_model.m`
- `tests/pc/run_dual_sfun_smoke.ps1`
- `tests/pc/create_response_error_model.m`
- `tests/pc/run_response_error_smoke.ps1`

### 明确不修改的用户文件

- `user/**`
- `dsp/src/my_algorithm.c`
- 全部 `dsp/**/c2837x_w5300_*`
- 现有单实例 `.slx` 文件

### 实现步骤

- [ ] 两项验证使用独立模型、Mock 配置、运行脚本和结果判定；不得用一个场景的通过状态替代另一个场景。
- [ ] Mock endpoint 编译器优先取 `CC` 环境变量，否则从 PATH 查找项目支持的 C 编译器；脚本不得硬编码 MATLAB 版本或编译器绝对路径。

### 验证 9A：双 S-Function、双 Mock endpoint、1000 步

- [ ] 用标准 socket 编写一个可通过命令行指定 port、config hash 和确定性输出规则的 Mock endpoint；不引入第三方依赖。
- [ ] PowerShell 编排器编译 Mock，启动两个独立进程，并保证退出时终止两个进程。
- [ ] MATLAB 脚本创建临时双 S-Function 模型，两个实例使用不同端口、Hash 和 typed I/O。
- [ ] 两个 endpoint 分别验证 SIM_START、1000 个 INPUT_DATA step、OUTPUT_DATA step 和 SIM_STOP。
- [ ] 模型记录两个输出序列并验证各自规则、step 单调和不存在跨实例数据。

### 验证 9B：独立 RESPONSE(error) 失败路径

- [ ] 单独启动一个配置为“第一次成功交换后，在下一次 INPUT_DATA 返回 RESPONSE(error code 5)”的 Mock endpoint。
- [ ] 使用独立模型和脚本运行该场景，捕获 Simulink error status，并确认错误文本包含 DSP error code `5`。
- [ ] 记录输出序列和时间戳，确认仅存在成功 sample 的输出；失败 step 的仿真时刻和任何新输出值均未提交，模型不再推进后续 step。
- [ ] RESPONSE(error) 测试不复用 9A 的通过标志；任一验证失败都单独报告自己的脚本和场景。

### 验证方法

运行：

```powershell
tests\pc\run_dual_sfun_smoke.ps1
tests\pc\run_response_error_smoke.ps1
```

预期：9A 脚本实际加载阶段 7 的两个 MEX、启动两个 Mock、运行 Normal mode 1000 步并返回 exit code 0；9B 脚本收到 RESPONSE(error) 后确认模型停止、失败时刻无输出提交并返回 exit code 0。任一脚本未执行时，对应结果必须独立标记“未验证”。

### 完成判据

- 同一模型加载两个唯一 MEX 并完成 1000 步。
- 两个 PC context 的 socket、Hash、step、I/O 和错误互不串扰。
- 独立 RESPONSE(error) 模型在失败 step 设置错误并停止，输出日志没有失败 step 的新样本或输出值。

### 风险和回退方式

- 风险：MATLAB/MEX 文件锁、后台 Mock 进程残留，或把两个场景的结果混为一个总状态。
- 回退：两个编排器各自在 `finally` 等价清理路径中关闭自己的模型、clear MEX 并终止自己启动的进程；分别保存结果，不删除用户文件。

---

## 阶段 10：用户 DSP/W5300 集成说明与硬件验收入口

### 修改目标

向用户交付最小、明确的集成契约和硬件验收入口，不代替用户实现 IoDevice、初始化或 DSP 测试。

### 涉及的现有文件

- 修改：`README.md`
- 读取：`requirements_multi_iodevice.md`
- 读取：阶段 2 最终采用的 `dsp/inc/c2837x_block.h` 或 `core/algorithm/inc/c2837x_block.h`
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
$roots = @('README.md', 'docs', 'app', 'dsp', 'simulink'); if (Test-Path 'core') { $roots += 'core' }
rg -n "SocketField|SocketTxField|SocketRxField|C2837X_BLOCK_SOCKET_NUM|copy.*w5300|Only one instance" $roots
```

预期：仅在历史说明或明确禁止项中出现；新用户流程不要求修改 Core 或生成器来选择设备。

### 完成判据

- 用户可仅根据文档完成自己的 IoDevice、实例映射和主循环集成。
- 文档没有声称 AI/Codex 已完成 DSP、W5300 或硬件验证。

### 风险和回退方式

- 风险：文档示例误写成 W5300 专用公共接口。
- 回退：以阶段 2 确认的实际 Core 公共头为唯一接口源，删除任何具体寄存器或 Socket API 示例。

---

## 实施完成总门槛

- Frozen 需求编号、V1 wire format 和 error code 无变化。
- 阶段 2 确认的实际 Core 路径按 `core/algorithm` 所有权管理，且无 TI/W5300 include、无全局运行实例、无设备分支；若发生物理迁移，旧 DSP include 路径仍有兼容入口。
- `autogen` 无用户 Algorithm、IoDevice、Socket、SCI channel、硬件配置或缓存表。
- App 能保存、加载、生成并构建至少两个实例，且派生名称无大小写冲突。
- host tests 全部通过；双 S-Function/双 Mock 1000 步实际执行后通过。
- W5300 HAL/Socket 和用户文件的 Git diff 为空。
- DSP/W5300 硬件验收仍由用户执行；未执行前明确标记“未验证”。

## 建议提交边界

每个阶段使用一个独立提交；阶段 2–5 如改动过大，可按“测试/接口”和“最小实现”拆成两个提交，但不得把不同阶段混在同一提交。任何阶段失败时只回退本阶段提交，不使用 `git reset --hard`，不修改或还原用户未提交内容。
