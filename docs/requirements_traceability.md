# DSP-SimBridge SCI-S5-04 最终 Traceability 与 SCI Final Audit

> 审计任务：SCI-S5-04。本文只覆盖冻结需求中的 FR-001～FR-095；不执行 SCI-G5，不把用户 DSP/CCS、真实 COM、真实 Simulink 联机或硬件结果推断为 PASS。
>
> Initial SCI-S5-04 audit finding (preserved): `BLOCKED` because the legacy V1 `docs/test_plan.md`, `docs/acceptance_record_template.md`, and `docs/problem_feedback_template.md` remained in top-level `docs` and were presented as the current test-material set.
>
> Resolved by SCI-S5-04-R1: the three historical V1 multi-instance/W5300 267-FR artifacts were moved to `docs/archive/multi_instance_v1/` and marked historical.
>
> Final authority audit: `PASS`; `CURRENT_AUTHORITY_BLOCKERS=0`. SCI-S5-04 Final Audit=`PASS`; SCI-G5 executed=`NO`; SCI-G5 readiness=`READY`.

## 1. 审计基线与当前 authority

- 当前唯一冻结需求：`requirements/requirements_sci_iodevice_v1.0_frozen.md`，应以其中 95 个 `### FR-xxx` 标题为本矩阵的唯一 FR 集合。
- 当前增量计划：根目录 `plan.md`，其中的 SCI-S5-04 定义本矩阵、Final Audit、历史归档审计和协议/热路径审计；SCI-G5 是独立后续 Gate。
- 当前实现 authority：本仓库实际 App、DSP、Simulink/PC、生成器和测试源文件；证据还包括已关闭阶段/Gate 的 Git 与测试材料。
- 契约：Project Format V4、Wire Protocol V1、Core API V2；目标固定为 `TMS320F28377D + PTP`。
- 最终 SCI 平台时钟：SYSCLK 200 MHz，LSPCLK = SYSCLK/4 = 50 MHz，LOSPCP=2；该值由 SCI-S5-02 收敛并由当前代码/文档保持一致。
- SCI-S5-04 implementation audit baseline / starting HEAD：`0700f3ab390aeac396723cb016fdf616ea96058b`。产品实现及 S5-01→该 baseline 的 protocol/W5300 changed-path audit 以此提交状态为基础；该 SHA 不是当前分支或远端 HEAD。
- SCI-S5-04 closing commit / current local and remote HEAD：`edf6be2f092964ffd9aeaa28bed8cb6c5aa4a490`。该提交包含最终 traceability、三份 legacy V1 validation artifacts 的 archive moves；当前 `feature/sci-iodevice-v1` 的 local/upstream HEAD 均为该 SHA。
- `0700f3ab390aeac396723cb016fdf616ea96058b` → `edf6be2f092964ffd9aeaa28bed8cb6c5aa4a490`：仅 documentation / traceability / archive governance change；无 product code 或 test code change。
- 历史 V1 协议基线：tag `legacy-v1-protocol-baseline`，commit `f209302ce3efc0fa15d217550f6d9b1dc00487fb`。
- 历史 267-FR 矩阵 `docs/archive/requirements_traceability_multi_instance_v1.md`、旧 requirements、旧 plan 和 R1 归档的三份 V1 测试资料仅作历史证据，不能作为当前 SCI FR-001～FR-095 依据；历史文件保持不变。

## 2. 状态和证据边界

| 状态 | 本文含义 |
| --- | --- |
| `REUSED_EVIDENCE_PASS` | 已有闭合阶段或既有测试/静态证据支持；本次 S5-04 未重新执行该测试。 |
| `STATIC_AUDIT_PASS` | 当前实现、生成器、配置或文档边界已完成聚焦静态检查。 |
| `GOVERNANCE_PASS` | 范围、归档、禁止项或测试策略的仓库治理约束已满足。 |
| `IMPLEMENTED / DSP_CCS_NOT_EXECUTED` | 软件实现和已有证据存在，但本次没有 DSP/CCS 目标编译、下载或实机证据。 |
| `IMPLEMENTED / USER_VALIDATION_PENDING` | 软件/生成证据存在，最终仍需要用户环境或硬件验证。 |
| `NOT_EXECUTED / MATRIX_NOT_REQUIRED` | 需求明确不要求该类大矩阵或硬件矩阵，本次不执行。 |

本次保留以下边界：DSP/CCS target build、真实 COM 硬件、真实 Simulink 通信、半双工硬件、混合 W5300/SCI 硬件均为 `NOT_EXECUTED`；SCI 硬件和最终 LSPCLK 硬件确认均为 `USER_VALIDATION_PENDING`。SCI-S5-02 产生的 MinGW64 8.1.0 代表性 SCI MEX 证据为 `REUSED PASS`；本次 S5-04 不重建 MEX，记为 `NOT_EXECUTED / NOT_REQUIRED`。

## 3. FR-001～FR-095 最终追踪矩阵

| FR | Requirement Summary | Implementation Evidence | Task/Gate | Verification Evidence | Status | Notes / Pending Boundary |
| --- | --- | --- | --- | --- | --- | --- |
| FR-001 | SCI 与 W5300 并存；支持 SCI-A/B/C/D、不同 SCI 多实例/混合实例，DSP 主循环轮询。 | `app/c2837x_block_iodevice_sci_definition.m`<br>`dsp/src/c2837x_block_sci.c`<br>`dsp/src/c2837x_block.c` | SCI-G2/G3/G4 CLOSED；SCI-S5-01 REUSED EVIDENCE | `tests/app/test_sci_iodevice_validation.m`<br>`tests/dsp_host/sci_iodevice_test.c` | IMPLEMENTED / DSP_CCS_NOT_EXECUTED | 软件实现与 Host 证据已存在；DSP/SCI 实机及混合硬件未执行。 |
| FR-002 | 一个算法实例静态绑定一个 IoDevice；一个物理 SCI 模块最多一个实例；无运行时切换或复用器。 | `app/c2837x_block_project_session.m`<br>`app/c2837x_block_validate_project.m`<br>`dsp/inc/c2837x_block_iodevice.h` | SCI-G1/G2/G3 CLOSED；SCI-S5-01 REUSED EVIDENCE | `tests/app/test_project_validation.m`<br>`tests/dsp_host/test_s2_09_dual_instance.m` | STATIC_AUDIT_PASS | 静态绑定/冲突校验已检查；未做硬件双实例验证。 |
| FR-003 | 保留现有 Core 多实例 API：PlatformInit、Init(instance)、Run(instance)、GetLastError(instance) 和 IoDeviceOps，不引入第二套 API 或共享默认上下文。 | `dsp/inc/c2837x_block.h`<br>`dsp/inc/c2837x_block_iodevice.h`<br>`dsp/src/c2837x_block.c` | SCI-G2 CLOSED；SCI-S5-01 REUSED EVIDENCE | `tests/dsp_host/test_s2_01_core_api.m`<br>`tests/dsp_host/test_s2_09_dual_instance.m` | REUSED_EVIDENCE_PASS | Core V2 证据来自已关闭阶段；本次未做 CCS 编译。 |
| FR-004 | Project V4、Wire V1、Core API V2 独立版本化；生成代码使用预期 API 2，版本不匹配必须编译失败。 | `app/c2837x_block_render_dsp_project_files.m`<br>`dsp/inc/c2837x_block.h`<br>`dsp/inc/c2837x_block_protocol.h` | SCI-G1/G2/G3 CLOSED | `tests/app/test_dsp_output_model.m`<br>`tests/dsp_host/test_s2_01_core_api.m` | STATIC_AUDIT_PASS | 版本常量和 compile-time gate 已静态确认；目标编译未执行。 |
| FR-005 | V1 线协议保持 4 字节头、既有消息类型/RESPONSE、little-endian、step_index、hash、错误含义和 framing；不新增 magic、CRC、实例 ID、握手或传输 framing。 | `dsp/inc/c2837x_block_protocol.h`<br>`dsp/src/c2837x_block_protocol.c`<br>`simulink/c2837x_block_protocol.c` | SCI-G0/G2/G4 CLOSED；SCI-S5-01 REUSED EVIDENCE | `tests/protocol/test_legacy_v1_protocol_baseline.m`<br>`tests/protocol/legacy_v1_golden_frames.m`<br>`Protocol_Test_Vectors.md` | REUSED_EVIDENCE_PASS | 与历史 tag/向量的协议审计无回归；未机械重跑完整 V1 套件。 |
| FR-006 | W5300 及其 hot path 不变；Run 不做完整静态校验，PC step 不做全量复制/堆分配，端口/元素/端序由生成期固定。 | `dsp/src/c2837x_block.c`<br>`simulink/c2837x_block_pc_socket.c`<br>`app/c2837x_block_render_dsp_instance_io_files.m` | SCI-S5-01 baseline `15f1311`；SCI-S5-04 focused audit | `tests/dsp_host/test_s2_07_core_protocol.m`<br>`tests/app/test_dsp_output_model.m` | REUSED_EVIDENCE_PASS | 从 S5-01 基线到 SCI-S5-04 implementation audit baseline `0700f3ab390aeac396723cb016fdf616ea96058b` 无 Core/W5300/PC socket hot-path 改动。 |
| FR-007 | V4 项目必须包含规定的 common、network、output、instances 字段，并固定 target/package。 | `app/c2837x_block_create_default_project.m`<br>`app/c2837x_block_validate_project_structure.m` | SCI-G1 CLOSED | `tests/app/test_project_v4_sci_model.m`<br>`tests/app/test_project_validation.m` | REUSED_EVIDENCE_PASS | V4/target/PTP 结构已由既有 App 测试支持。 |
| FR-008 | network 始终存在；仅 W5300 项目校验/生成网络字段，SCI-only 保留 network 但不因无效网络阻塞，mixed 同时生成两侧。 | `app/c2837x_block_validate_project.m`<br>`app/c2837x_block_iodevice_w5300_tcp_definition.m`<br>`app/c2837x_block_build_dsp_output_model.m` | SCI-G1/G3 CLOSED | `tests/app/test_project_validation.m`<br>`tests/app/test_dsp_generation_flow.m` | REUSED_EVIDENCE_PASS | W5300-only/SCI-only 条件分支已在源码和候选生成器中确认。 |
| FR-009 | 实例 IoDevice/type 字段支持 W5300 Socket/TCP 和 SCI module/baud/RX/TX/pin qualification/CTRL；RX/TX 只允许空或 GPIO<number>，无关字段不参与。 | `app/c2837x_block_create_iodevice.m`<br>`app/c2837x_block_iodevice_sci_definition.m`<br>`app/c2837x_block_validate_project_structure.m` | SCI-G1/G2 CLOSED | `tests/app/test_sci_iodevice_validation.m`<br>`tests/app/test_project_v4_sci_model.m` | REUSED_EVIDENCE_PASS | 字段集合及类型约束已验证；硬件 pinmux 未执行实机确认。 |
| FR-010 | V2/V3 迁移到 V4；保留 W5300 字段，解析 canonical SCI pin group，非 canonical 清空并记录 issue，不依赖 capability。 | `app/c2837x_block_migrate_project_v2.m`<br>`app/c2837x_block_migrate_project_v3.m`<br>`app/c2837x_block_project_session.m` | SCI-G1 CLOSED | `tests/app/test_project_v4_sci_model.m`<br>`tests/app/test_sci_iodevice_validation.m` | REUSED_EVIDENCE_PASS | 迁移和非 canonical 边界为软件证据；不改写旧 mat。 |
| FR-011 | 迁移标记 dirty，不能自动覆盖旧 mat；用户保存后才写入 V4。 | `app/c2837x_block_project_session.m`<br>`app/c2837x_block_migrate_project_v2.m` | SCI-G1 CLOSED | `tests/app/test_project_v4_sci_model.m`<br>`tests/app/test_project_validation.m` | REUSED_EVIDENCE_PASS | session dirty/save 行为已在 App 证据中保留。 |
| FR-012 | SCI 配置变化使 candidates 失效并要求 Generate；SCI module/baud/pin 不进入 Interface Hash。 | `app/c2837x_block_project_session.m`<br>`app/c2837x_block_build_interface_text.m`<br>`app/c2837x_block_build_dsp_candidates.m` | SCI-G1/G3 CLOSED | `tests/app/test_project_v4_sci_model.m`<br>`tests/app/test_dsp_output_model.m` | REUSED_EVIDENCE_PASS | hash 输入与生成失效边界已静态/软件验证。 |
| FR-013 | COM 不属于 Project，不进入 Interface Hash 或 DSP 生成；只改 COM 不要求 Generate/DSP/MEX rebuild。 | `app/c2837x_block_project_session.m`<br>`app/c2837x_block_render_sfun_files.m`<br>`app/c2837x_block_build_interface_text.m` | SCI-G3/G4 CLOSED | `tests/app/test_sci_s4_03_sfun_lifecycle.m`<br>`tests/app/test_sfun_build_candidates.m` | STATIC_AUDIT_PASS | COM 属于生成的 S-Function 参数；真实 COM 打开未执行。 |
| FR-014 | 只支持 TMS320F28377D + PTP；capability 来自固定 JSON，不提供 ZWT/PZP/package selector。 | `app/c2837x_block_create_default_project.m`<br>`app/capabilities/TMS320F28377D_PTP.json`<br>`app/c2837x_block_load_device_capability.m` | SCI-G1 CLOSED | `tests/app/test_device_capability.m`<br>`tests/app/test_project_v4_sci_model.m` | STATIC_AUDIT_PASS | target/package 限定和 capability provenance 已检查。 |
| FR-015 | capability 提供 schema/version、GPIO 和独立 RX/TX endpoint/module 事实；禁止 Cartesian 配对和散落 raw jsondecode。 | `app/c2837x_block_load_device_capability.m`<br>`app/capabilities/TMS320F28377D_PTP.json`<br>`app/c2837x_block_iodevice_sci_definition.m` | SCI-G1/G2 CLOSED | `tests/app/test_device_capability.m`<br>`tests/app/test_sci_iodevice_validation.m` | REUSED_EVIDENCE_PASS | loader normalization 和端点独立性已有软件证据。 |
| FR-016 | 用户配置不是 capability；COM 仅由 S-Function 运行时使用；不做磁盘 capability cache，只允许 session cache。 | `app/c2837x_block_load_device_capability.m`<br>`app/c2837x_block_project_session.m`<br>`app/c2837x_block_render_sfun_files.m` | SCI-G1/G4 CLOSED | `tests/app/test_device_capability.m`<br>`tests/app/test_sci_s4_03_sfun_lifecycle.m` | STATIC_AUDIT_PASS | 当前代码路径未发现磁盘缓存或 COM 进入 Project 的实现。 |
| FR-017 | W5300 固定资源仍由 platform reserved resources 管理，不放入 capability JSON。 | `app/c2837x_block_get_platform_reserved_resources.m`<br>`app/c2837x_block_iodevice_w5300_tcp_definition.m` | SCI-G1/G2 CLOSED | `tests/app/test_device_capability.m`<br>`tests/app/test_project_validation.m` | STATIC_AUDIT_PASS | 固定 W5300 GPIO 资源和 capability 事实分层已确认。 |
| FR-018 | 合并 capability、platform 和全部实例资源；检测重复 module、GPIO 冲突、自冲突、W5300 资源冲突、缺 endpoint 和派生 pinmux。 | `app/c2837x_block_validate_project.m`<br>`app/c2837x_block_validate_project_structure.m`<br>`app/c2837x_block_iodevice_sci_definition.m` | SCI-G1/G2 CLOSED | `tests/app/test_sci_iodevice_validation.m`<br>`tests/app/test_project_validation.m` | REUSED_EVIDENCE_PASS | 资源冲突矩阵未扩大为硬件矩阵。 |
| FR-019 | IoDevice 下拉框提供 W5300 TCP 和 SCI；新建默认 W5300。 | `app/C2837xBlockConfigurator.m`<br>`app/c2837x_block_create_default_instance.m`<br>`app/c2837x_block_create_iodevice.m` | SCI-G1 CLOSED | `tests/app/test_configurator_smoke.m`<br>`tests/app/test_project_v4_sci_model.m` | REUSED_EVIDENCE_PASS | UI/默认值由 App 测试和静态检查支持。 |
| FR-020 | Project 页负责项目/平台/网络/输出，Instance 页负责实例；不做固定 SCI-A/B/C/D 项目面板。 | `app/C2837xBlockConfigurator.m`<br>`app/c2837x_block_project_session.m` | SCI-G1 CLOSED | `tests/app/test_configurator_smoke.m` | STATIC_AUDIT_PASS | 页面职责和动态 module 选项已静态确认。 |
| FR-021 | Detail 页按 General/IoDevice/Algorithm 分区；算法 source 支持规定语义，IoDevice 字段按类型显示。 | `app/C2837xBlockConfigurator.m`<br>`app/c2837x_block_create_default_instance.m` | SCI-G1 CLOSED | `tests/app/test_configurator_smoke.m`<br>`tests/app/test_project_v4_sci_model.m` | REUSED_EVIDENCE_PASS | 未修改模型外部 COM 等字段。 |
| FR-022 | W5300 页显示 Socket/TCP；SCI 页显示 module、baud、RX/TX、pin type/qualification、CTRL。 | `app/C2837xBlockConfigurator.m`<br>`app/c2837x_block_create_iodevice.m` | SCI-G1 CLOSED | `tests/app/test_configurator_smoke.m`<br>`tests/app/test_sci_iodevice_validation.m` | REUSED_EVIDENCE_PASS | 类型感知控件和字段校验已有软件证据。 |
| FR-023 | SCI module 为 A-D；baud 提供五个选择，默认 57600；SCI 默认 module/pin 未选。 | `app/c2837x_block_iodevice_sci_definition.m`<br>`app/c2837x_block_create_iodevice.m`<br>`app/C2837xBlockConfigurator.m` | SCI-G1/G2 CLOSED | `tests/app/test_sci_iodevice_validation.m`<br>`tests/app/test_sci_baud_calculation.m` | REUSED_EVIDENCE_PASS | 默认值和五档请求 baud 已检查。 |
| FR-024 | CTRL 默认 Standard/High；选择 None 时禁用并隐藏相关配置。 | `app/c2837x_block_iodevice_sci_definition.m`<br>`app/C2837xBlockConfigurator.m` | SCI-G1/G2 CLOSED | `tests/app/test_sci_iodevice_validation.m`<br>`tests/app/test_configurator_smoke.m` | REUSED_EVIDENCE_PASS | CTRL None 语义覆盖 UI 与 descriptor。 |
| FR-025 | RX/TX endpoint 独立 capability 下拉；module 切换清除无效选择；CTRL 仅 None/GPIO 列表。 | `app/C2837xBlockConfigurator.m`<br>`app/c2837x_block_iodevice_sci_definition.m`<br>`app/c2837x_block_load_device_capability.m` | SCI-G1/G2 CLOSED | `tests/app/test_sci_iodevice_validation.m`<br>`tests/app/test_device_capability.m` | REUSED_EVIDENCE_PASS | endpoint 选择不做 Cartesian pairing；硬件 pinmux 待用户确认。 |
| FR-026 | Pin Type 仅 Standard/Pull-up；RX qualification 仅 Sync/Async；TX/CTRL 无 qualification 选项。 | `app/C2837xBlockConfigurator.m`<br>`app/c2837x_block_iodevice_sci_definition.m` | SCI-G1/G2 CLOSED | `tests/app/test_sci_iodevice_validation.m`<br>`tests/dsp_host/platform_sci_modes_test.c` | REUSED_EVIDENCE_PASS | UI、descriptor 和 platform mode 保持一致。 |
| FR-027 | Project 页只读显示 LSPCLK 和每个 SCI requested/actual/error；LSPCLK 不是用户参数。 | `app/C2837xBlockConfigurator.m`<br>`app/c2837x_block_get_sci_clock_config.m`<br>`app/c2837x_block_calculate_sci_baud.m` | SCI-S5-02 `c48e4aa` CLOSED；SCI-S5-03/R1 | `tests/app/test_sci_baud_calculation.m`<br>`docs/app_project_and_migration_guide.md` | REUSED_EVIDENCE_PASS | App/生成结果已统一到 50 MHz；最终硬件时钟仍待用户确认。 |
| FR-028 | 实例表显示 instance/name/type/algorithm/source/sample time/transport summary/hash/status，并按类型摘要。 | `app/C2837xBlockConfigurator.m`<br>`app/c2837x_block_build_transport_summary.m` | SCI-G1/G3 CLOSED | `tests/app/test_configurator_smoke.m`<br>`tests/app/test_project_v4_sci_model.m` | REUSED_EVIDENCE_PASS | transport summary 不泄露无关参数。 |
| FR-029 | SCI copy 复制非独占字段但清空 module/RX/TX，CTRL 回到 None 语义；不复制独占硬件绑定。 | `app/c2837x_block_project_session.m`<br>`app/c2837x_block_create_iodevice.m` | SCI-G1 CLOSED | `tests/app/test_project_v4_sci_model.m`<br>`tests/app/test_sci_iodevice_validation.m` | REUSED_EVIDENCE_PASS | copy 行为来自 session 级软件证据。 |
| FR-030 | capability 失败阻塞 SCI 项目，但不阻塞 W5300-only 项目。 | `app/c2837x_block_load_device_capability.m`<br>`app/c2837x_block_validate_project.m` | SCI-G1/G2 CLOSED | `tests/app/test_device_capability.m`<br>`tests/app/test_project_validation.m` | REUSED_EVIDENCE_PASS | 条件阻塞边界已在校验路径中确认。 |
| FR-031 | bring-up 使用 200 MHz `/14`；无 SCI 时 PlatformInit 不改 LSPCLK；有 SCI 时项目级初始化前设置一次，不能由实例/App 编辑。 | `app/c2837x_block_get_sci_clock_config.m`<br>`dsp/src/c2837x_block_platform.c`<br>`dsp/src/c2837x_block_platform.h` | SCI-G2 CLOSED；SCI-S5-02 `c48e4aa` CLOSED | `tests/dsp_host/test_s2_02_platform_init.m`<br>`tests/app/test_sci_baud_calculation.m` | REUSED_EVIDENCE_PASS | bring-up 历史边界和最终 `/4` 代码已一致；目标寄存器实测未执行。 |
| FR-032 | 最终 LSPCLK 综合五个 baud、平台共享约束和误差选择；最终固定平台并同步 App/BRR/actual/error/生成 DSP。 | `app/c2837x_block_get_sci_clock_config.m`<br>`app/c2837x_block_calculate_sci_baud.m`<br>`app/c2837x_block_render_dsp_project_files.m` | SCI-S5-02 `c48e4aa` CLOSED；SCI-S5-03/R1 | `tests/app/test_sci_baud_calculation.m`<br>`docs/simulink_mex_user_guide.md` | REUSED_EVIDENCE_PASS | S5-02 证据复用；不执行额外大矩阵，硬件最终确认 pending。 |
| FR-033 | BRR 为 16-bit H/L；solver 候选 1..65535，公式为 LSPCLK/(8*(BRR+1))，按绝对误差及较小 BRR tie-break。 | `app/c2837x_block_calculate_sci_baud.m`<br>`app/c2837x_block_iodevice_sci_definition.m`<br>`dsp/inc/c2837x_block_sci.h` | SCI-G2 CLOSED；SCI-S5-02 REUSED EVIDENCE | `tests/app/test_sci_baud_calculation.m`<br>`tests/app/test_sci_iodevice_validation.m` | REUSED_EVIDENCE_PASS | BRR=0 不作为 solver candidate；DSP runtime 不重算。 |
| FR-034 | PC 使用 nominal requested baud，不把 DSP actual baud 当作 PC 配置参数。 | `app/c2837x_block_render_pc_files.m`<br>`app/c2837x_block_render_sfun_files.m` | SCI-G4 CLOSED；SCI-S5-02 REUSED EVIDENCE | `tests/app/test_sci_s4_03_sfun_lifecycle.m`<br>`tests/app/test_sci_s4_05_software_loop.m` | STATIC_AUDIT_PASS | 生成诊断同时保留 requested/actual；真实 COM 配置未执行。 |
| FR-035 | SCI 固定 8N1、无 parity/flow control、async/full-duplex；关闭 autobaud/loopback/interrupt，FIFO 开启、delay=0、polling。 | `dsp/src/c2837x_block_platform.c`<br>`dsp/src/c2837x_block_sci.c`<br>`app/c2837x_block_render_sfun_files.m` | SCI-G2/G3/G4 CLOSED | `tests/dsp_host/test_s2_03_sci.m`<br>`tests/dsp_host/sci_platform_init_test.c` | REUSED_EVIDENCE_PASS | Host/静态证据支持配置；没有真实 SCI 示波或硬件证据。 |
| FR-036 | Standard 关闭 pull-up，Pull-up 开启；RX qualification 仅 Sync/Async。 | `dsp/src/c2837x_block_platform.c`<br>`app/c2837x_block_iodevice_sci_definition.m` | SCI-G2 CLOSED | `tests/dsp_host/platform_sci_modes_test.c`<br>`tests/app/test_sci_iodevice_validation.m` | STATIC_AUDIT_PASS | 选项范围及 platform 映射已静态确认。 |
| FR-037 | PlatformInit 按 descriptor 配置 RX/TX mux、pad、qualification 和可选 CTRL；不触碰未使用资源。 | `dsp/src/c2837x_block_platform.c`<br>`app/c2837x_block_iodevice_sci_definition.m` | SCI-G2 CLOSED | `tests/dsp_host/sci_platform_init_test.c`<br>`tests/dsp_host/platform_sci_modes_test.c` | STATIC_AUDIT_PASS | 目标寄存器初始化未在 CCS/硬件执行。 |
| FR-038 | PlatformInit/build 依 IoDevice 条件包含 W5300/SCI；SCI-only 不含 W5300，W5300-only 不含 SCI，mixed 两者都含；Init 不重复初始化平台硬件。 | `app/c2837x_block_build_dsp_output_model.m`<br>`app/c2837x_block_build_dsp_candidates.m`<br>`dsp/src/c2837x_block_platform.c` | SCI-G2/G3 CLOSED | `tests/app/test_dsp_output_model.m`<br>`tests/app/test_dsp_generation_flow.m` | REUSED_EVIDENCE_PASS | 条件依赖和一次性 PlatformInit 已审计；目标 build 未执行。 |
| FR-039 | 只报告可检测的 SCI 配置错误，追加 `SCI_INIT=-5`；不做完整 readback/loopback/probe，也不伪造硬件结论。 | `dsp/inc/c2837x_block.h`<br>`dsp/src/c2837x_block_platform.c`<br>`dsp/inc/c2837x_block_sci.h` | SCI-G2 CLOSED | `tests/dsp_host/sci_platform_invalid_config_test.c`<br>`tests/dsp_host/test_s2_03a_static_config.m` | STATIC_AUDIT_PASS | `-5` 与静态可检测错误已确认；没有硬件探测证据。 |
| FR-040 | mixed 所需资源任一失败返回错误，不进行通信；不要求回滚。 | `dsp/src/c2837x_block_platform.c`<br>`app/c2837x_block_validate_project.m` | SCI-G2/G3 CLOSED | `tests/dsp_host/sci_platform_invalid_config_test.c`<br>`tests/app/test_project_validation.m` | IMPLEMENTED / DSP_CCS_NOT_EXECUTED | 失败路径为软件实现；mixed 硬件故障注入未执行。 |
| FR-041 | 一个公共 SCI driver 覆盖 A-D；每实例保存 const HW config 和 mutable channel runtime，不动态切换、不共享 runtime。 | `dsp/inc/c2837x_block_sci.h`<br>`dsp/src/c2837x_block_sci.c` | SCI-G2 CLOSED | `tests/dsp_host/sci_iodevice_test.c`<br>`tests/dsp_host/sci_channel_runtime_test.c` | REUSED_EVIDENCE_PASS | runtime 隔离为 Host/静态证据；目标多实例未执行。 |
| FR-042 | 硬件初始化在 PlatformInit；channel_init 只初始化软件状态和 CTRL RX。 | `dsp/src/c2837x_block_platform.c`<br>`dsp/src/c2837x_block_sci.c` | SCI-G2 CLOSED | `tests/dsp_host/sci_platform_init_test.c`<br>`tests/dsp_host/sci_channel_runtime_test.c` | REUSED_EVIDENCE_PASS | init 分层已确认。 |
| FR-043 | 逻辑状态 CLOSED→OPEN→LISTENING；无 peer connect；LISTEN 空闲不超时；首个 RX octet 使 CONNECTED 且不消费该 octet。 | `dsp/src/c2837x_block_sci.c`<br>`dsp/inc/c2837x_block_iodevice.h` | SCI-G2 CLOSED | `tests/dsp_host/test_s2_04_sci.m`<br>`tests/dsp_host/sci_channel_runtime_test.c` | REUSED_EVIDENCE_PASS | 协议会话状态由软件 fixture 支持；无真实线缆验证。 |
| FR-044 | SIM_START 前只做一次 cleanup；会话结束清 FIFO/pending/error/CTRL RX 并再次等待，不重初始化硬件。 | `dsp/src/c2837x_block_sci.c`<br>`dsp/src/c2837x_block.c` | SCI-G2/G3 CLOSED | `tests/dsp_host/test_s2_05_sci.m`<br>`tests/app/test_sci_s4_05_software_loop.m` | REUSED_EVIDENCE_PASS | lifecycle 证据复用；真实 SIM_START 未执行。 |
| FR-045 | close 只关闭逻辑会话；后续重新 open/listen；无 TCP peer-close 语义。 | `dsp/src/c2837x_block_sci.c` | SCI-G2 CLOSED | `tests/dsp_host/test_s2_06_sci.m`<br>`tests/dsp_host/sci_channel_runtime_test.c` | REUSED_EVIDENCE_PASS | SCI 软件状态边界已覆盖。 |
| FR-046 | FIFO 按当前 available 轮询；8-bit octet 与 C28x Uint16 私有转换；wire length 为 octet 且偶数进度；单字节 staging/0。 | `dsp/src/c2837x_block_sci.c`<br>`dsp/inc/c2837x_block_sci.h` | SCI-G2 CLOSED | `tests/dsp_host/test_s2_04_sci.m`<br>`tests/dsp_host/sci_channel_runtime_test.c` | REUSED_EVIDENCE_PASS | buffer/进度规则来自 Host fixture；目标 FIFO 未执行。 |
| FR-047 | RXERROR/RXFFOVF 产生错误并有限清理；不做 resync、CRC、retry 或 retransmit。 | `dsp/src/c2837x_block_sci.c` | SCI-G2 CLOSED | `tests/dsp_host/test_s2_05_sci.m`<br>`tests/dsp_host/sci_channel_runtime_test.c` | REUSED_EVIDENCE_PASS | 错误清理路径有软件证据；硬件 error flag 未实测。 |
| FR-048 | FIFO 发送不等待；每实例一个 pending operation；中间 Run 只推进同一操作，不开始第二 segment。 | `dsp/src/c2837x_block_sci.c`<br>`dsp/inc/c2837x_block_sci.h` | SCI-G2 CLOSED | `tests/dsp_host/sci_tx_pending_test.c`<br>`tests/dsp_host/test_s2_05_sci.m` | REUSED_EVIDENCE_PASS | pending/send 语义已有 Host 测试源；未执行 target。 |
| FR-049 | Send 仅在所有 octet（含 stop bit）物理发送完后返回正数；中间返回 0，最终返回完整计数。 | `dsp/src/c2837x_block_sci.c`<br>`dsp/inc/c2837x_block_iodevice.h` | SCI-G2 CLOSED | `tests/dsp_host/sci_tx_pending_test.c`<br>`tests/dsp_host/test_s2_06_sci.m` | REUSED_EVIDENCE_PASS | TXEMPTY/最终计数逻辑已静态和 Host 审计。 |
| FR-050 | Core 有 INTERACTION/TRANSFER timeout；不自动改变 baud/LSPCLK；LISTEN 首字节前无限等待；Run 有界、非阻塞、无 delay。 | `dsp/src/c2837x_block.c`<br>`dsp/src/c2837x_block_sci.c` | SCI-G2/G3 CLOSED | `tests/dsp_host/test_s2_08_timeout_lifecycle.m`<br>`tests/app/test_sci_s4_05_software_loop.m` | REUSED_EVIDENCE_PASS | timeout/非阻塞软件证据复用；DSP/硬件未执行。 |
| FR-051 | CTRL=None 不做方向控制；可选 GPIO/polarity；默认和 cleanup 均回 RX。 | `dsp/src/c2837x_block_sci.c`<br>`dsp/inc/c2837x_block_sci.h`<br>`app/c2837x_block_iodevice_sci_definition.m` | SCI-G2 CLOSED | `tests/dsp_host/test_s2_06_sci.m`<br>`tests/dsp_host/platform_sci_modes_test.c` | REUSED_EVIDENCE_PASS | CTRL 软件/静态证据存在；真实 RS-485 未执行。 |
| FR-052 | 半双工 send 先置 CTRL TX 并返回 pending/0；无 setup delay；TX/FIFO 跨 Run 保持。 | `dsp/src/c2837x_block_sci.c`<br>`tests/dsp_host/sci_half_duplex_test.c` | SCI-G2 CLOSED | `tests/dsp_host/sci_half_duplex_test.c`<br>`tests/dsp_host/test_s2_06_sci.m` | REUSED_EVIDENCE_PASS | 半双工硬件不执行，Host/静态行为证据复用。 |
| FR-053 | 物理发送完成后才 CTRL RX 并报告完整进度；重复 send 继续同一 pending，不重复/覆盖。 | `dsp/src/c2837x_block_sci.c`<br>`dsp/inc/c2837x_block_sci.h` | SCI-G2 CLOSED | `tests/dsp_host/sci_half_duplex_test.c`<br>`tests/dsp_host/sci_tx_pending_test.c` | REUSED_EVIDENCE_PASS | 方向切换和 pending 语义未作硬件推断。 |
| FR-054 | Receive 只在 CTRL RX；处理 state contradiction/session cleanup；错误/终止停止填充、清 pending/FIFO、强制 RX。 | `dsp/src/c2837x_block_sci.c` | SCI-G2 CLOSED | `tests/dsp_host/test_s2_05_sci.m`<br>`tests/dsp_host/test_s2_06_sci.m` | REUSED_EVIDENCE_PASS | 软件状态机和清理路径已审计。 |
| FR-055 | PC 不控制 RTS/DTR DE；USB-RS485 适配器自行方向，软件不提供 direction adapter。 | `simulink/c2837x_block_pc_serial.c`<br>`simulink/c2837x_block_pc_serial.h` | SCI-G4 CLOSED | `tests/pc/pc_serial_host_test.c`<br>`docs/simulink_mex_user_guide.md` | STATIC_AUDIT_PASS | PC 源码关闭 DTR/RTS；适配器真实行为由用户验证。 |
| FR-056 | SCI S-Function 只有一个正的有限整数标量 COM 参数，且不可调谐；COM 存在 .slx，不在 Project。 | `app/c2837x_block_render_sfun_files.m`<br>`simulink/c2837x_block_pc_serial.c`<br>`simulink/c2837x_block_pc_serial.h` | SCI-G4 CLOSED | `tests/app/test_sci_s4_03_sfun_lifecycle.m`<br>`tests/app/test_sfun_candidates.m` | REUSED_EVIDENCE_PASS | 参数解析/非 tunable 为生成代码证据；未打开真实 COM。 |
| FR-057 | W5300 transport 参数 0 个、SCI 1 个；baud 已编译进生成物；transport/baud 需 Generate/MEX rebuild，COM 单改不需。 | `app/c2837x_block_render_sfun_build_files.m`<br>`app/c2837x_block_build_sfun_candidates.m`<br>`app/c2837x_block_render_sfun_files.m` | SCI-G3/G4 CLOSED | `tests/app/test_sfun_build_candidates.m`<br>`tests/app/test_sci_s4_04_transport_build_generation.m` | REUSED_EVIDENCE_PASS | 生成器候选/依赖证据复用；本次不构建 MEX。 |
| FR-058 | mdlStart 解析/打开/配置生成 baud、8N1/no flow、purge 一次、发送 SIM_START、等待 RESPONSE、初始化 step；失败启动并清理。 | `app/c2837x_block_render_sfun_files.m`<br>`app/c2837x_block_render_pc_files.m`<br>`simulink/c2837x_block_pc_serial.c` | SCI-G4 CLOSED | `tests/app/test_sci_s4_03_sfun_lifecycle.m`<br>`tests/app/test_sci_s4_05_software_loop.m` | REUSED_EVIDENCE_PASS | 生成 S-Function 和软件 fixture 证据复用；真实 Simulink/COM 未执行。 |
| FR-059 | COM invalid/busy/permission/config 错误立即 start error；不搜索、重试、等待、重连；purge 仅一次，禁止 bootloader A/sleep。 | `app/c2837x_block_render_sfun_files.m`<br>`simulink/c2837x_block_pc_serial.c` | SCI-G4 CLOSED | `tests/app/test_sci_s4_03_sfun_lifecycle.m`<br>`tests/pc/pc_serial_host_test.c` | REUSED_EVIDENCE_PASS | 错误和 cleanup 分支由 Host/生成测试支持；真实 OS COM 权限场景未执行。 |
| FR-060 | 同步 mdlOutputs 执行 input→INPUT→OUTPUT/RESPONSE 校验→原子输出→step++；mdlTerminate 尽力 SIM_STOP、不等 response、再 close。 | `app/c2837x_block_render_sfun_files.m`<br>`simulink/c2837x_block_sfun.c` | SCI-G4 CLOSED | `tests/app/test_sci_s4_03_sfun_lifecycle.m`<br>`tests/app/test_sfun_step_candidates.m` | REUSED_EVIDENCE_PASS | 生成路径的同步 lifecycle 已审计；真实 Simulink communication 未执行。 |
| FR-061 | serial write-all/read-exact 支持 partial；使用一个单调 deadline，partial 不重置 deadline。 | `simulink/c2837x_block_pc_serial.c`<br>`simulink/c2837x_block_pc_serial.h` | SCI-G4 CLOSED | `tests/pc/pc_serial_host_test.c`<br>`tests/app/test_sci_s4_05_software_loop.m` | REUSED_EVIDENCE_PASS | Win32 seam/partial/deadline 源码和既有测试证据复用。 |
| FR-062 | 保留 CONNECT/STEP/TERMINATE timeout；SCI Connect 不等待 peer；SIM_START/step 用 STEP，stop 用 TERMINATE。 | `app/c2837x_block_render_sfun_files.m`<br>`app/c2837x_block_render_sfun_build_files.m`<br>`simulink/c2837x_block_pc_error.h` | SCI-G4 CLOSED | `tests/app/test_sci_s4_03_sfun_lifecycle.m`<br>`tests/app/test_sci_s4_05_software_loop.m` | REUSED_EVIDENCE_PASS | timeout stage 映射已在生成器/错误模型中确认。 |
| FR-063 | 固定 8N1，关闭 flow control，DTR/RTS inactive 且不是协议字段。 | `simulink/c2837x_block_pc_serial.c`<br>`app/c2837x_block_render_pc_files.m` | SCI-G4 CLOSED | `tests/pc/pc_serial_host_test.c`<br>`tests/pc/pc_error_host_test.c` | STATIC_AUDIT_PASS | OS serial 配置已静态确认；无真实 USB-serial 设备验证。 |
| FR-064 | PC 使用 raw V1 octet，无额外 framing；按协议所需字节读取，不读取全部 available，也不引入第二 parser。 | `simulink/c2837x_block_protocol.c`<br>`simulink/c2837x_block_protocol.h`<br>`app/templates/protocol.c.in` | SCI-G0/G4 CLOSED；SCI-S5-04 protocol audit | `tests/protocol/test_legacy_v1_protocol_baseline.m`<br>`tests/pc/pc_serial_host_test.c` | REUSED_EVIDENCE_PASS | 共享协议模板和当前 PC 协议实现无 framing 扩展。 |
| FR-065 | serial/USB/protocol error 终止 simulation 并 close；无 reopen/retry/resend/skip/re-SIM_START/CTS 等恢复。 | `app/c2837x_block_render_sfun_files.m`<br>`simulink/c2837x_block_pc_serial.c`<br>`simulink/c2837x_block_pc_error.h` | SCI-G4 CLOSED | `tests/app/test_sci_s4_03_sfun_lifecycle.m`<br>`tests/pc/pc_error_host_test.c` | REUSED_EVIDENCE_PASS | 终止和错误分类证据复用；真实 Simulink 错误窗口未执行。 |
| FR-066 | PC 端仅 Windows desktop MATLAB/Simulink Normal，使用 native Win32 或等价接口，不依赖 MathWorks 私有 binary。 | `simulink/c2837x_block_pc_serial.c`<br>`app/c2837x_block_render_sfun_build_files.m`<br>`README.md` | SCI-G4 CLOSED；SCI-S5-03/R1 | `tests/pc/pc_serial_host_test.c`<br>`docs/simulink_mex_user_guide.md` | STATIC_AUDIT_PASS | Windows/Normal 边界已写入当前文档；其他平台不在范围内。 |
| FR-067 | 不依赖 Instrument Control Toolbox、Python、pyserial 或第三方 serial library；PC C 源码自包含。 | `simulink/c2837x_block_pc_serial.c`<br>`simulink/c2837x_block_pc_serial.h`<br>`app/c2837x_block_render_sfun_build_files.m` | SCI-G4 CLOSED | `tests/pc/pc_serial_host_test.c`<br>`tests/app/test_sfun_build_candidates.m` | STATIC_AUDIT_PASS | 依赖扫描和 build candidate 路径已检查。 |
| FR-068 | COM 是逻辑编号；COM10 用 native path；Update Diagram 只接受正整数静态参数；仅 mdlStart 打开，不枚举设备/VID/PID/刷新 UI。 | `simulink/c2837x_block_pc_serial.c`<br>`app/c2837x_block_render_sfun_files.m`<br>`app/C2837xBlockConfigurator.m` | SCI-G4 CLOSED | `tests/app/test_sci_s4_03_sfun_lifecycle.m`<br>`tests/pc/pc_serial_host_test.c` | REUSED_EVIDENCE_PASS | Windows path/参数边界有源码证据；实际 COM10 未执行。 |
| FR-069 | 多 SCI 可用不同 COM/mixed；同一 COM 由 OS exclusive open 失败；无 global registry。 | `simulink/c2837x_block_pc_serial.c`<br>`app/c2837x_block_render_sfun_files.m` | SCI-G4 CLOSED | `tests/pc/pc_serial_host_test.c`<br>`tests/app/test_sci_s4_03_sfun_lifecycle.m` | REUSED_EVIDENCE_PASS | per-instance context 与 OS exclusive 语义已审计；双 COM 实机未执行。 |
| FR-070 | 每个 DSP instance/simulation 生成独立实例 S-Function；可选 per-MEX duplicate guard；不共享 session。 | `app/c2837x_block_build_sfun_output_model.m`<br>`app/c2837x_block_render_sfun_files.m` | SCI-G3/G4 CLOSED | `tests/app/test_sfun_candidates.m`<br>`tests/app/test_sfun_step_candidates.m` | STATIC_AUDIT_PASS | 生成目录和 context 为实例化；未执行多 MEX Simulink 矩阵。 |
| FR-071 | PcError 在既有 enum 后增加 SERIAL；serial 错误不映射 TCP DISCONNECT，使用 SERIAL + os_error。 | `simulink/c2837x_block_pc_error.h`<br>`app/c2837x_block_render_sfun_files.m` | SCI-G4 CLOSED；SCI-S5-02 REUSED EVIDENCE | `tests/pc/pc_error_host_test.c`<br>`tests/app/test_sci_s4_03_sfun_lifecycle.m` | REUSED_EVIDENCE_PASS | enum 数值和 serial 分类已由既有 Host 测试支持。 |
| FR-072 | 错误 stage/fields 稳定，包含 instance、COM、generated baud、stage、category、step。 | `simulink/c2837x_block_pc_error.h`<br>`app/c2837x_block_render_sfun_files.m` | SCI-G4 CLOSED | `tests/pc/pc_error_host_test.c` | REUSED_EVIDENCE_PASS | 格式化字段已静态确认；未在 MATLAB GUI 展示错误。 |
| FR-073 | 保留 OS error/text；partial timeout 仍为 TIMEOUT，带 expected/actual length，不改成 DISCONNECT。 | `simulink/c2837x_block_pc_serial.c`<br>`simulink/c2837x_block_pc_error.h`<br>`app/templates/protocol.c.in` | SCI-G4 CLOSED | `tests/pc/pc_serial_host_test.c`<br>`tests/pc/pc_error_host_test.c` | REUSED_EVIDENCE_PASS | partial/error source 和 Host seam 证据复用。 |
| FR-074 | 协议诊断进入 mdlStart/mdlOutputs；不可恢复错误通过 ssSetErrorStatus 清理并终止，不复用旧输出。 | `app/c2837x_block_render_sfun_files.m`<br>`simulink/c2837x_block_pc_error.h` | SCI-G4 CLOSED | `tests/app/test_sci_s4_03_sfun_lifecycle.m`<br>`tests/app/test_sfun_step_candidates.m` | REUSED_EVIDENCE_PASS | 生成生命周期和 atomic output helper 已审计。 |
| FR-075 | terminate cleanup 错误不产生新的 simulation error、不覆盖主错误；不保留长 serial log/history。 | `app/c2837x_block_render_sfun_files.m`<br>`simulink/c2837x_block_pc_serial.c` | SCI-G4 CLOSED | `tests/app/test_sci_s4_03_sfun_lifecycle.m` | REUSED_EVIDENCE_PASS | terminate best-effort 语义来自既有软件证据。 |
| FR-076 | 每实例 S-Function root 自包含；W5300 使用 pc_socket，SCI 使用 pc_serial，只包含当前 transport，不共享 PC runtime。 | `app/c2837x_block_build_sfun_output_model.m`<br>`app/c2837x_block_render_sfun_files.m`<br>`app/c2837x_block_render_sfun_build_files.m` | SCI-G3/G4 CLOSED；SCI-S5-01 REUSED EVIDENCE | `tests/app/test_sfun_build_candidates.m`<br>`tests/app/test_sci_s4_04_transport_build_generation.m` | REUSED_EVIDENCE_PASS | 从 S5-01 到 SCI-S5-04 implementation audit baseline `0700f3ab390aeac396723cb016fdf616ea96058b` 无 W5300 PC socket hot-path 改动。 |
| FR-077 | TCP/SCI 共用同一 V1 protocol template/logic，不维护两套独立协议。 | `app/templates/protocol.h.in`<br>`app/templates/protocol.c.in`<br>`simulink/c2837x_block_protocol.c` | SCI-G3/G4 CLOSED；SCI-S5-04 protocol audit | `tests/protocol/test_legacy_v1_protocol_baseline.m`<br>`tests/app/test_pc_protocol_candidates.m` | REUSED_EVIDENCE_PASS | 共享模板和当前 protocol constants/frames 已核对。 |
| FR-078 | 生成 config 包含 device/baud/actual/protocol/hash/sample/payload/I/O；COM 不编译进去；用户只配置三个 timeout。 | `app/c2837x_block_render_dsp_instance_config_files.m`<br>`app/c2837x_block_render_sfun_files.m`<br>`app/c2837x_block_render_sfun_build_files.m` | SCI-G3/G4 CLOSED；SCI-S5-02 REUSED EVIDENCE | `tests/app/test_dsp_output_model.m`<br>`tests/app/test_sfun_build_candidates.m` | STATIC_AUDIT_PASS | 生成配置边界已审计；本次不 build MEX。 |
| FR-079 | build script 显式列出 pc_socket/pc_serial；先检查 Windows/prerequisite/writable/loaded MEX，再删除重建；失败保留旧 MEX。 | `app/c2837x_block_render_sfun_build_files.m`<br>`app/c2837x_block_build_sfun_candidates.m` | SCI-G4 CLOSED | `tests/app/test_sfun_build_candidates.m`<br>`tests/app/test_sci_s4_04_transport_build_generation.m` | REUSED_EVIDENCE_PASS | 仅静态/既有候选测试证据；本次未运行 mex。 |
| FR-080 | App 只负责 source/build script 生成，不自动 mex/delete/load/path/model edit。 | `app/c2837x_block_app_coordinator.m`<br>`app/c2837x_block_render_sfun_build_files.m`<br>`app/c2837x_block_validate_candidate_actions.m` | SCI-G3/G4 CLOSED | `tests/app/test_sfun_build_candidates.m`<br>`tests/app/test_candidate_files.m` | STATIC_AUDIT_PASS | App action boundary 已确认。 |
| FR-081 | Update Diagram 只静态编译配置，不执行 COM open/purge/SIM_START/DSP communication/device enumeration。 | `app/c2837x_block_render_sfun_files.m`<br>`app/C2837xBlockConfigurator.m` | SCI-G4 CLOSED | `tests/app/test_configurator_smoke.m`<br>`tests/app/test_sci_s4_03_sfun_lifecycle.m` | STATIC_AUDIT_PASS | runtime 动作只在 mdlStart/step/terminate 生成路径。 |
| FR-082 | device change 是 contract change；COM 由用户修改 .slx 参数；App 不自动重写 model。 | `app/c2837x_block_project_session.m`<br>`app/c2837x_block_app_coordinator.m`<br>`app/C2837xBlockConfigurator.m` | SCI-G1/G4 CLOSED | `tests/app/test_project_v4_sci_model.m`<br>`tests/app/test_sfun_build_candidates.m` | STATIC_AUDIT_PASS | Project 与 .slx COM 边界已静态确认。 |
| FR-083 | 只支持 desktop Normal；不支持 Fast Restart 持久 COM 或 Accelerator/Rapid/codegen/realtime/parallel。 | `app/c2837x_block_render_sfun_files.m`<br>`app/c2837x_block_render_sfun_build_files.m`<br>`README.md` | SCI-G4 CLOSED；SCI-S5-03/R1 | `tests/app/test_sci_s4_03_sfun_lifecycle.m`<br>`docs/simulink_mex_user_guide.md` | STATIC_AUDIT_PASS | 当前文档明确 Normal-only；其他模式不执行。 |
| FR-084 | 只执行必要测试，不要求 coverage matrix。 | `plan.md`<br>`app/c2837x_block_app_coordinator.m` | SCI-S5-01/S5-04 | `tests/README.md`<br>`docs/simulink_mex_user_guide.md` | GOVERNANCE_PASS | 本次按低成本 focused audit 执行，未跑 full suite。 |
| FR-085 | 最小测试集合覆盖 capability/schema、冲突、迁移、SCI/W5300/mixed 确定性生成、代表性 serial partial/deadline/SIM_START/step 和相关错误；允许复用不变证据。 | `plan.md`<br>`tests/app/test_sci_s4_03_sfun_lifecycle.m`<br>`tests/app/test_sci_s4_04_transport_build_generation.m` | SCI-S5-01 REUSED EVIDENCE；SCI-S5-04 | `tests/app/test_device_capability.m`<br>`tests/app/test_sci_iodevice_validation.m`<br>`tests/pc/pc_serial_host_test.c` | REUSED_EVIDENCE_PASS | 最小集合证据已映射；不扩展为多硬件矩阵。 |
| FR-086 | 不机械重跑完整 V1 suite；仅按当前影响范围复用/执行必要证据。 | `plan.md`<br>`tests/protocol/test_legacy_v1_protocol_baseline.m` | SCI-S5-01/S5-04 | `tests/protocol/test_legacy_v1_protocol_baseline.m`<br>`Protocol_Test_Vectors.md` | GOVERNANCE_PASS | 本次未执行 full V1 suite，协议采用 changed-path/static audit。 |
| FR-087 | 若编译器可用至少一个真实 SCI MEX；否则明确 NOT_EXECUTED/CAPABILITY。 | `app/c2837x_block_render_sfun_build_files.m`<br>`app/c2837x_block_build_sfun_candidates.m` | SCI-G4 CLOSED；SCI-S5-01 REUSED EVIDENCE | `tests/app/test_sci_s4_05_software_loop.m`<br>`docs/simulink_mex_user_guide.md` | REUSED_EVIDENCE_PASS | 代表性 SCI MEX（MinGW64 8.1.0）来自 SCI-S5-02，当前 S5-04 不重建且不伪造新结果。 |
| FR-088 | 不要求多 SCI/多硬件 matrix；mixed 只做确定性生成证据。 | `app/c2837x_block_build_dsp_candidates.m`<br>`app/c2837x_block_build_project_candidates.m`<br>`app/c2837x_block_build_sfun_candidates.m` | SCI-S5-01 REUSED EVIDENCE；SCI-S5-04 | `tests/app/test_dsp_generation_flow.m`<br>`tests/app/test_sfun_build_candidates.m` | GOVERNANCE_PASS | mixed hardware 未执行，确定性候选生成是边界内证据。 |
| FR-089 | 最终 SCI 硬件、用户 LSPCLK/baud/CTRL/mixed/稳定性由用户验证；无真实硬件不得写 PASS。 | `app/c2837x_block_get_sci_clock_config.m`<br>`app/c2837x_block_render_dsp_project_files.m`<br>`docs/ccs_integration_and_dual_instance_main.md` | SCI-S5-02 CLOSED；SCI-S5-03/R1 | `docs/simulink_mex_user_guide.md`<br>`docs/ccs_integration_and_dual_instance_main.md` | IMPLEMENTED / USER_VALIDATION_PENDING | SCI hardware、mixed hardware、最终 LSPCLK 硬件确认仍 pending。 |
| FR-090 | CCS/MEX/Simulink/hardware 未执行项必须显式标记，不能隐含为 PASS。 | `README.md`<br>`docs/ccs_integration_and_dual_instance_main.md`<br>`docs/simulink_mex_user_guide.md` | SCI-S5-03/R1 `f84f6e1`/`0700f3a` CLOSED；SCI-S5-04 | `docs/simulink_mex_user_guide.md`<br>`plan.md` | GOVERNANCE_PASS | 当前状态表已明确 NOT_EXECUTED、REUSED PASS、USER_VALIDATION_PENDING。 |
| FR-091 | 明确不实现 CRC/ACK/retry/retransmission/reconnect/resync/watchdog/autobaud/interrupt/DMA/industrial diagnostics。 | `dsp/inc/c2837x_block_protocol.h`<br>`dsp/src/c2837x_block_sci.c`<br>`simulink/c2837x_block_protocol.c` | SCI-G0/G2/G4 CLOSED | `tests/protocol/test_legacy_v1_protocol_baseline.m`<br>`README.md` | GOVERNANCE_PASS | 非目标静态审计通过；不把非目标误报为缺陷或硬件结果。 |
| FR-092 | Host 固定 Windows，DSP 固定 F28377D PTP；不支持 Linux/macOS serial、ZWT/PZP、package selector 或 multi-device capability。 | `simulink/c2837x_block_pc_serial.c`<br>`app/c2837x_block_create_default_project.m`<br>`app/capabilities/TMS320F28377D_PTP.json` | SCI-G1/G4 CLOSED；SCI-S5-03/R1 | `tests/app/test_device_capability.m`<br>`docs/simulink_mex_user_guide.md` | STATIC_AUDIT_PASS | 平台范围已静态确认。 |
| FR-093 | 旧 requirements、旧 plan 和历史材料仅作 archive/historical evidence。 | `requirements/archive/requirements_multi_iodevice_v1.0_frozen_rev2.md`<br>`docs/archive/plan_multi_instance_v1_completed.md`<br>`docs/archive/requirements_traceability_multi_instance_v1.md` | SCI-G0/S5-04 authority audit | `tests/protocol/test_stage0_repository_baseline.m`<br>`docs/archive/requirements_traceability_multi_instance_v1.md` | GOVERNANCE_PASS | 267-FR 矩阵 untouched 且不作为当前矩阵；R1 已将三份遗留 V1 测试资料归档并加 historical notice。 |
| FR-094 | 只使用新的 `plan.md` 增量 FR/SCI stage 约束，不恢复旧 Stage 6 或重跑旧 G0-G5。 | `plan.md`<br>`docs/requirements_traceability.md` | SCI-S5-04/R1/R2 | `plan.md`<br>`docs/simulink_mex_user_guide.md` | GOVERNANCE_PASS | SCI-G5 本次未执行；R1 已解除旧测试方案的 authority blocker。 |
| FR-095 | 当前规范集合由冻结 SCI requirements、新 plan、Project Source/current Dynamic Context/current batch 构成；旧 archive 非当前 authority，FR 编号稳定。 | `requirements/requirements_sci_iodevice_v1.0_frozen.md`<br>`plan.md`<br>`docs/requirements_traceability.md` | SCI-S5-04 authority audit | `plan.md`<br>`docs/requirements_traceability.md` | GOVERNANCE_PASS | 需求标题审计为连续 95 项；当前矩阵只保留 FR-001～FR-095。 |

## 4. Status 汇总与 Final Audit

### 4.1 矩阵结构审计

- 冻结需求标题：95 个；最小 FR-001，最大 FR-095；无缺号、无重复。
- 当前矩阵行：95 个；每个 FR 恰好一行；无额外 FR 行。
- 正式 implementation path references：237 个，由 S5-04 路径审计逐一 `Test-Path` 验证；`INVALID_PATHS=0`。
- 当前矩阵唯一新建 SCI traceability artifact：`docs/requirements_traceability.md`；这不等同于 SCI-S5-04 closing commit 的全部文件变更。

### 4.2 现有 authority 审计

- Current requirements: `requirements/requirements_sci_iodevice_v1.0_frozen.md`。
- Current plan: `plan.md`。
- Current SCI traceability: `docs/requirements_traceability.md`。
- Historical multi-instance materials: `requirements/archive/requirements_multi_iodevice_v1.0_frozen_rev2.md`、`docs/archive/plan_multi_instance_v1_completed.md`、`docs/archive/requirements_traceability_multi_instance_v1.md`、`docs/archive/multi_instance_v1/test_plan.md`、`docs/archive/multi_instance_v1/acceptance_record_template.md`、`docs/archive/multi_instance_v1/problem_feedback_template.md`。
- Initial blocker finding retained: the three legacy top-level paths `docs/test_plan.md`、`docs/acceptance_record_template.md` and `docs/problem_feedback_template.md` belonged to the historical V1 multi-instance/W5300 267-FR cycle and had been presented as current-looking test materials.
- Resolved by SCI-S5-04-R1: those three files now exist only under `docs/archive/multi_instance_v1/`, each with a historical notice and no current SCI authority role.
- Final authority audit: `PASS`; `CURRENT_AUTHORITY_BLOCKERS=0`. No second current S5-04 or current Project V2 test plan remains.

### 4.3 V1 protocol audit

- 历史 source/tag：`legacy-v1-protocol-baseline` → `f209302ce3efc0fa15d217550f6d9b1dc00487fb`。
- 当前协议证据：`dsp/inc/c2837x_block_protocol.h`、`dsp/src/c2837x_block_protocol.c`、`simulink/c2837x_block_protocol.c`、`tests/protocol/legacy_v1_golden_frames.m`、`Protocol_Test_Vectors.md`。
- 从 S5-01 evidence baseline `15f131119f7ee25c9917fd58b57d2602cd5b6aaf` 到 SCI-S5-04 implementation audit baseline `0700f3ab390aeac396723cb016fdf616ea96058b` 的 changed-path audit：协议实现路径无变更；W5300/Core/PC socket hot path 无变更。`app/templates/protocol.c.in`/`.h.in` 是共享生成模板，审计未发现新增 wire framing、magic、CRC、实例 ID 或新握手。
- 结论：`REUSED_EVIDENCE_PASS / NO RELEVANT PROTOCOL CHANGE`；本次没有机械重跑完整 V1 suite。

### 4.4 W5300 / hot-path audit

- S5-01 evidence baseline `15f131119f7ee25c9917fd58b57d2602cd5b6aaf` 到 SCI-S5-04 implementation audit baseline `0700f3ab390aeac396723cb016fdf616ea96058b` 的 changed-path 总数为 18；协议路径变更 0，关键路径检查中的 `dsp/src/c2837x_block.c`、W5300 DSP source、`simulink/c2837x_block_sfun.c`、`simulink/c2837x_block_pc_socket.c` 均无变更。
- 期间变更的 `app/c2837x_block_render_pc_files.m`、`app/c2837x_block_render_sfun_files.m` 属于 SCI serial binding/生成器路径；不改变 W5300 socket 实现或 Core Run hot path。
- 结论：`REUSED_EVIDENCE_PASS / NO W5300 HOT-PATH REGRESSION FOUND BY CHANGED-PATH AUDIT`。
- Protocol/W5300 implementation audit：`REUSED AUDIT EVIDENCE`。
- SCI-S5-04 closing documentation commit `edf6be2f092964ffd9aeaa28bed8cb6c5aa4a490`：仅 documentation / traceability / archive governance change；`NO PRODUCT CODE CHANGE`。

### 4.5 Status summary

下列计数由本文件矩阵行的 `Status` 字段静态计算，不代表本次重新执行了对应测试：

| Status | Rows |
| --- | ---: |
| `REUSED_EVIDENCE_PASS` | 62 |
| `STATIC_AUDIT_PASS` | 22 |
| `GOVERNANCE_PASS` | 8 |
| `IMPLEMENTED / DSP_CCS_NOT_EXECUTED` | 2 |
| `IMPLEMENTED / USER_VALIDATION_PENDING` | 1 |
| `NOT_EXECUTED / MATRIX_NOT_REQUIRED` | 0 |
| Total | 95 |

## 5. Evidence boundary handoff

### REUSED EVIDENCE

- SCI-S5-01 / earlier closed stages：App V4/migration、capability/resource validation、Core API V2、DSP SCI/runtime、CTRL、deterministic generator、W5300/SCI/mixed candidate generation、Windows `pc_serial`、S-Function/COM、PcError、representative SCI software loop。
- SCI-S5-02 commit `c48e4aa`：最终 LSPCLK/baud solver/BRR/diagnostics 收敛到 SYSCLK 200 MHz、LSPCLK 50 MHz、LOSPCP=2；代表性 MinGW64 8.1.0 SCI MEX 结果只作为 reused evidence。
- SCI-S5-03 commits `f84f6e1` 和 `0700f3a`：README、App/migration、CCS、Simulink/MEX 当前使用和状态边界文档。
- V1 protocol golden/vector 与既有 Host/MATLAB evidence：本次仅做 changed-path/static audit，不重跑 full suite。

### NOT_EXECUTED

- 本次 S5-04 未运行 full test suite、完整 V1 suite、MATLAB/Simulink 全量回归、MEX rebuild、CCS target build/download、DSP target test、真实 COM、真实 Simulink communication、SCI hardware、half-duplex hardware、mixed W5300/SCI hardware。
- SCI-S5-04 自身 MEX build：`NOT_EXECUTED / NOT_REQUIRED`；没有新增二进制或构建结论。
- 不执行多 SCI/多硬件 matrix；mixed 仅保留 deterministic generation evidence。

### USER_VALIDATION_PENDING

- SCI hardware bring-up、真实 SCI baud/BRR、CTRL/RS-485 方向、最终 LSPCLK 寄存器确认、稳定性和 mixed hardware 联机。
- 用户 CCS 工程集成、EABI/COFF/实际 compiler、DSP download、真实 Simulink/MEX 联机。

## 6. SCI-S5-04 交付判定

- Product files modified by this task：`NONE`。
- Tests modified by this task：`NONE`。
- R2 documentation modification：仅 `docs/requirements_traceability.md` 的 blocker resolution/status 文本；95 行矩阵、Implementation Evidence、Verification Evidence 和状态边界未重写。
- R3 documentation modification：仅修正 implementation audit baseline、closing commit/current HEAD 与 closing-files summary 表述；95 个 FR 的 Requirement Summary、Implementation Evidence、Task/Gate、Verification Evidence、Status 和状态边界未重写，仅更新 FR-006/FR-076 Notes 中的审计终点表述。
- SCI-S5-04 Final Audit：`PASS`；R1 已解除旧 `docs/test_plan.md` 及其同组历史模板造成的 authority blocker。
- SCI-G5 executed：`NO`。
- SCI-G5 readiness：`READY`；SCI-G5 仍须作为独立后续 Gate 决定，不能在本任务中宣称 PASS。
- Product tests executed：`NOT_EXECUTED / NOT_REQUIRED`；本任务仅执行文档级检查。

### SCI-S5-04 closing commit changed-files

- New current SCI traceability artifact：`docs/requirements_traceability.md`。
- Legacy V1 validation artifacts archived：
  - `docs/acceptance_record_template.md` → `docs/archive/multi_instance_v1/acceptance_record_template.md`
  - `docs/problem_feedback_template.md` → `docs/archive/multi_instance_v1/problem_feedback_template.md`
  - `docs/test_plan.md` → `docs/archive/multi_instance_v1/test_plan.md`
- Product code modified：`NONE`。
- Test code modified：`NONE`。

## 7. Git / low-cost checks

本次任务不执行 reset、checkout、merge、rebase、commit 或 push。最终检查应记录：

- `git status --short --branch`：工作分支为 `feature/sci-iodevice-v1`；初始状态 clean；Git 两次报告无法读取 `C:\Users\Sun/.config/git/ignore` 的权限 warning，但未显示工作区改动。
- `git diff --check`：应为通过；修改后的 traceability 文档无 whitespace error。
- `git diff --stat`：只应显示 `docs/requirements_traceability.md` 的 R3 文档修正；archive moves 已属于 closing commit，不是本次工作区修改。
- `git diff --name-only`：只应显示 `docs/requirements_traceability.md`。
- `git status --short --branch`（final）：只应显示 `M docs/requirements_traceability.md`，不应有其他路径。

## 8. SCI-S5-04 跨对话移交摘要

### 当前仓库、分支、HEAD

- Repository：`VainSuns/DSP-SimBridge`
- Branch：`feature/sci-iodevice-v1`
- Implementation audit baseline：`0700f3ab390aeac396723cb016fdf616ea96058b`
- SCI-S5-04 closing commit：`edf6be2f092964ffd9aeaa28bed8cb6c5aa4a490`
- Current HEAD before R3 commit：`edf6be2f092964ffd9aeaa28bed8cb6c5aa4a490`
- Current local HEAD：`edf6be2f092964ffd9aeaa28bed8cb6c5aa4a490`
- Remote/upstream HEAD：`edf6be2f092964ffd9aeaa28bed8cb6c5aa4a490`
- S5-01 closing baseline：无独立 S5-01 commit；按历史顺序以 `15f131119f7ee25c9917fd58b57d2602cd5b6aaf` 作为最后一个 S4-05 evidence baseline。

### 本次文件和计数

- New current SCI traceability artifact：`docs/requirements_traceability.md`
- Legacy V1 validation artifacts archived：
  - `docs/acceptance_record_template.md` → `docs/archive/multi_instance_v1/acceptance_record_template.md`
  - `docs/problem_feedback_template.md` → `docs/archive/multi_instance_v1/problem_feedback_template.md`
  - `docs/test_plan.md` → `docs/archive/multi_instance_v1/test_plan.md`
- FR rows：95；FR range：FR-001～FR-095；duplicates/missing：0
- Implementation path audit：`PATH_REFERENCES=237` 已逐一验证；`INVALID_PATHS=0`
- Product code modified：NONE
- Test code modified：NONE

### 已完成的新检查

- Git repository/remote/branch/local HEAD/upstream HEAD/status baseline
- Frozen FR heading count/range/duplicate/missing audit
- Current traceability row count/range/duplicate/missing audit
- Formal implementation path reference existence audit
- Current authority vs historical archive audit
- S5-01 evidence baseline→SCI-S5-04 implementation audit baseline changed-path protocol audit
- S5-01 evidence baseline→SCI-S5-04 implementation audit baseline W5300/Core/PC socket hot-path audit
- `git diff --check`、`git diff --stat`、`git diff --name-only`、final `git status --short --branch`

### 复用、未执行和待用户验证

- Reused：SCI-S5-01/earlier closed-stage App/DSP/generator/PC/S-Function/PcError/representative software-loop evidence；SCI-S5-02 final clock and representative MinGW64 8.1.0 MEX evidence；SCI-S5-03/R1 current docs；V1 protocol vectors。
- Not executed：SCI-G5、S5-04 MEX rebuild、full suites、CCS/DSP target build/download、real COM、real Simulink、SCI/half-duplex/mixed hardware。
- User pending：SCI hardware、final LSPCLK hardware confirmation、baud/CTRL/stability/mixed and user CCS/Simulink acceptance。

### Protocol / hot-path / resolved issues / next action

- Protocol：V1 framing and shared logic unchanged by S5-01 evidence baseline→SCI-S5-04 implementation audit baseline changed-path audit。
- W5300/hot path：no relevant implementation path changed; SCI generator binding changes are isolated。
- Resolved authority finding：SCI-S5-04-R1 archived the three legacy V1 test materials under `docs/archive/multi_instance_v1/` and added historical notices；current authority blocker count is 0。
- Readiness：`SCI-S5-04 PASS`；`SCI-G5 READY`。
- Next allowed action：only an independent SCI-G5 may be considered；SCI-G5 was not executed here。
- Next prohibited action within this handoff：do not add new features, do not enter later stages, do not infer hardware PASS, do not run unneeded full regressions, and do not modify the historical 267-FR archive。
