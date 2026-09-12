# Current UDP Requirements Traceability

本文是当前 W5300 UDP 周期的 development evidence map，供
`UDP-S6-03` final audit 使用。它不是 `FR-001..FR-082 FINAL AUDIT PASS`，
也不声明 `UDP-G6`。

## Authority and fixed contracts

本矩阵只引用当前 authority：

- [Frozen UDP V1.0 requirements](../requirements/requirements_w5300_udp_iodevice_v1.0_frozen.md)
- [Current UDP implementation plan](../plan.md)
- 当前 Repository 的实现、生成模板和测试入口
- UDP-S6-01 已经由 State 审核通过的实际 execution evidence

固定合同为：

~~~text
Project Format Version = 4
Wire Protocol Version   = 1
Core API Version        = 2
~~~

历史 SCI requirements、plan、multi-instance traceability 和 SCI
traceability 继续位于 archive；本文件不回填或改写这些历史材料。

## Status meaning

矩阵中的 status 是开发侧当前状态，不是最终审计 verdict：

- `IMPLEMENTED / EVIDENCE MAPPED — AUDIT PENDING`：实现和适用证据入口已列出，
  仍待 UDP-S6-03 对 FR 逐项作 final audit。
- `S6-01 SOFTWARE EVIDENCE RECORDED — AUDIT PENDING`：已记录 S6-01 实际软件
  结果；不把测试计数改写成全通过。
- `USER_VALIDATION_PENDING`：开发侧不能替用户完成的 W5300 UDP 实机验证。
- `IMPLEMENTED / OBSERVED NON-GOAL BOUNDARY`：已实现并在代码/文档边界中观察到
  Frozen 明确的第一版非目标。

## UDP-S6-01 evidence register

以下数字来自已审核的 UDP-S6-01 execution report；本任务不重新执行完整
S6-01 suite：

| Evidence slice | Actual result |
| --- | --- |
| Project/App UDP | 225 passed / 0 failed / 3 incomplete |
| DSP host/mock UDP | 9 passed / 0 failed / 0 incomplete |
| Relevant TCP regression | 26 passed / 0 failed / 0 incomplete |
| PC real localhost UDP | 30 passed / 0 failed / 0 incomplete |
| Mixed deterministic generation | 7 passed / 0 failed / 0 incomplete |
| Total | 297 passed / 0 failed / 3 incomplete |
| Incomplete cases | `testUnixRootOutputRelationships`, `testUnreadableOutputRootOnUnix`, `testUnwritableOutputRootOnUnix` |
| Incomplete reason | Windows platform assumption filtering of Unix permission tests |
| Frozen-required coverage gap | NONE |
| Representative generated UDP MEX | `axis_udp_sfun.mexw64` = PASS |
| MEX compiler | MinGW64 Compiler (C) 8.1.0 |
| Representative generated TI UDP DSP sources | 11 C files, 11/11 compile-only PASS |
| TI compiler | TI C2000 `cl2000` 25.11.0 |
| W5300 UDP hardware PIL | USER_VALIDATION_PENDING |

`3 incomplete` 不遮蔽 FR-076～FR-080 的 UDP required coverage；它们是平台假设
过滤结果，不应写成 `300/300 passed`。TI 结果只表示 generated C source
compile-only PASS，不表示完整 CCS project build、link、download 或 board
execution PASS。

## Traceability matrix

| FR | Requirement intent | Implementation area / source | Generation or configuration evidence | Test / evidence | Current status |
| --- | --- | --- | --- | --- | --- |
| FR-001–FR-008 | 新增第三种 `w5300_udp` IoDevice；保持多实例、V4、Wire V1、Core API V2；一个 Frame 对应一个 Datagram；UDP 不提供可靠传输；payload 上限为 1468。 | [`c2837x_block_create_iodevice.m`](../app/c2837x_block_create_iodevice.m)、[`c2837x_block_iodevice_w5300_udp_definition.m`](../app/c2837x_block_iodevice_w5300_udp_definition.m)、[`protocol.c.in`](../app/templates/protocol.c.in)、[`c2837x_block_protocol.c`](../dsp/src/c2837x_block_protocol.c) | Frozen requirements 的版本与 wire contract；[`build_interface_hash.m`](../app/c2837x_block_build_interface_hash.m)；UDP Project V4 model。 | [`test_project_model.m`](../tests/app/test_project_model.m)、[`test_iodevice_definitions.m`](../tests/app/test_iodevice_definitions.m)、[`test_pc_protocol_candidates.m`](../tests/app/test_pc_protocol_candidates.m)、V1 baseline tests。 | IMPLEMENTED / EVIDENCE MAPPED — AUDIT PENDING |
| FR-009–FR-010 | UDP canonical settings 为 `socket_number` + `udp_port`；TCP persisted schema 仍为 `socket_number` + `tcp_port`。 | [`c2837x_block_iodevice_w5300_udp_definition.m`](../app/c2837x_block_iodevice_w5300_udp_definition.m)、[`c2837x_block_iodevice_w5300_tcp_definition.m`](../app/c2837x_block_iodevice_w5300_tcp_definition.m)、[`c2837x_block_validate_project_structure.m`](../app/c2837x_block_validate_project_structure.m) | Defaults: socket 0, UDP port 5000；provider-owned settings structure。 | [`test_project_model.m`](../tests/app/test_project_model.m)、[`test_iodevice_definitions.m`](../tests/app/test_iodevice_definitions.m)、[`test_project_validation.m`](../tests/app/test_project_validation.m)。 | IMPLEMENTED / EVIDENCE MAPPED — AUDIT PENDING |
| FR-011–FR-017 | Socket 0..7 在 TCP/UDP 间全局唯一；TCP/UDP port namespace 分离；同号合法；UDP port 1..65535；任意 W5300 激活 network/platform resources；UDP payload 不超过 1468。 | [`c2837x_block_validate_project.m`](../app/c2837x_block_validate_project.m)、TCP/UDP provider `collect_resource_claims`、[`c2837x_block_get_platform_reserved_resources.m`](../app/c2837x_block_get_platform_reserved_resources.m) | [`TMS320F28377D_PTP.json`](../app/capabilities/TMS320F28377D_PTP.json)；UDP validation `UDP_PORT_INVALID`、`UDP_PORT_DUPLICATE`、`UDP_MAX_PAYLOAD_TOO_LARGE`。 | [`test_project_validation.m`](../tests/app/test_project_validation.m)、[`test_instance_operations.m`](../tests/app/test_instance_operations.m)、[`test_sci_iodevice_validation.m`](../tests/app/test_sci_iodevice_validation.m)。 | IMPLEMENTED / EVIDENCE MAPPED — AUDIT PENDING |
| FR-018–FR-022 | App selector 支持 TCP/UDP/SCI；UDP UI 只显示 Socket Number/UDP Port；summary、copy 和 switch 遵守 canonical settings。 | [`C2837xBlockConfigurator.m`](../app/C2837xBlockConfigurator.m)、[`c2837x_block_build_transport_summary.m`](../app/c2837x_block_build_transport_summary.m)、[`c2837x_block_create_iodevice.m`](../app/c2837x_block_create_iodevice.m) | UDP summary 为 `Socket n / UDP n`；UDP copy 通过用户输入新 socket/port，不自动猜测资源；switch 重建目标 settings。 | [`test_configurator_layout.m`](../tests/app/test_configurator_layout.m)、[`test_instance_operations.m`](../tests/app/test_instance_operations.m)、[`test_transport_summary.m`](../tests/app/test_transport_summary.m)、[`test_project_report.m`](../tests/app/test_project_report.m)。 | IMPLEMENTED / EVIDENCE MAPPED — AUDIT PENDING |
| FR-023–FR-025 | 独立 UDP Channel；复用 W5300 HAL/socket/平台基础设施；TCP stream/open/close 行为保持。 | [`c2837x_w5300_udp_channel.h`](../dsp/inc/c2837x_w5300_udp_channel.h)、[`c2837x_w5300_udp_channel.c`](../dsp/src/c2837x_w5300_udp_channel.c)、[`c2837x_w5300_socket.c`](../dsp/src/c2837x_w5300_socket.c)、[`c2837x_w5300_channel.c`](../dsp/src/c2837x_w5300_channel.c) | UDP provider 绑定独立 `c2837x_w5300_udp_iodevice_ops`；shared W5300 source closure。 | [`test_s3_01_w5300_udp_channel.m`](../tests/dsp_host/test_s3_01_w5300_udp_channel.m)、[`test_s2_04_w5300_nonblocking.m`](../tests/dsp_host/test_s2_04_w5300_nonblocking.m) 及相关 TCP regression。 | IMPLEMENTED / EVIDENCE MAPPED — AUDIT PENDING |
| FR-026–FR-032 | UDP OPEN 以 `SOCK_UDP` 完成；logical LISTENING；PACKET-INFO candidate；合法 SIM_START 建立 session peer；active peer 不被抢占。 | [`c2837x_w5300_socket.c`](../dsp/src/c2837x_w5300_socket.c)、[`c2837x_w5300_udp_channel.c`](../dsp/src/c2837x_w5300_udp_channel.c)、[`c2837x_block.c`](../dsp/src/c2837x_block.c) | UDP socket command progression；candidate/current endpoint state；Core WAIT_SIM_START/session semantics。 | [`test_s3_01_w5300_udp_channel.m`](../tests/dsp_host/test_s3_01_w5300_udp_channel.m)、[`test_s3_04_w5300_udp_lifecycle.m`](../tests/dsp_host/test_s3_04_w5300_udp_lifecycle.m)、[`w5300_udp_core_lifecycle_test.c`](../tests/dsp_host/w5300_udp_core_lifecycle_test.c)。 | IMPLEMENTED / EVIDENCE MAPPED — AUDIT PENDING |
| FR-033–FR-036 | 不增加 DSP full-frame buffer；Header/Payload 来自同一 Datagram；physical size 必须等于 `4 + N`；完整消费后才 `Sn_CR_RECV`。 | [`c2837x_w5300_udp_channel.c`](../dsp/src/c2837x_w5300_udp_channel.c)、[`c2837x_w5300_socket.c`](../dsp/src/c2837x_w5300_socket.c) | W5300 RX FIFO + 8-octet PACKET-INFO；transport 只读取 payload length 做 physical framing；delayed RECV commit。 | [`test_s3_02_w5300_udp_channel.m`](../tests/dsp_host/test_s3_02_w5300_udp_channel.m)、[`w5300_udp_channel_test.c`](../tests/dsp_host/w5300_udp_channel_test.c)、[`w5300_udp_core_lifecycle_test.c`](../tests/dsp_host/w5300_udp_core_lifecycle_test.c)。 | IMPLEMENTED / EVIDENCE MAPPED — AUDIT PENDING |
| FR-037–FR-044 | UDP TX 必须完整 Datagram 原子提交；pending SEND 不重复提交；SENDOK 只代表本地操作；destination/close/timeout/reopen 清理符合 Core contract。 | [`c2837x_w5300_udp_channel.c`](../dsp/src/c2837x_w5300_udp_channel.c)、[`c2837x_w5300_udp_channel.h`](../dsp/inc/c2837x_w5300_udp_channel.h)、[`c2837x_w5300_socket.c`](../dsp/src/c2837x_w5300_socket.c) | UDP `send()` contract `0 / count_octets / <0`；native UDP close 不进入 TCP erratum path；bounded close state。 | [`test_s2_03_w5300_udp_send.m`](../tests/dsp_host/test_s2_03_w5300_udp_send.m)、[`test_s3_04_w5300_udp_lifecycle.m`](../tests/dsp_host/test_s3_04_w5300_udp_lifecycle.m)、[`w5300_udp_send_test.c`](../tests/dsp_host/w5300_udp_send_test.c)。 | IMPLEMENTED / EVIDENCE MAPPED — AUDIT PENDING |
| FR-045–FR-047 | PC 使用 `SOCK_DGRAM`；local UDP port 由 OS ephemeral 分配；`connect()` 只固定 remote endpoint；可达性由 `SIM_START -> RESPONSE` 判断。 | [`pc_udp.c.in`](../app/templates/pc_udp.c.in)、[`pc_udp.h.in`](../app/templates/pc_udp.h.in)、[`c2837x_block_render_pc_files.m`](../app/c2837x_block_render_pc_files.m)、[`c2837x_block_render_sfun_files.m`](../app/c2837x_block_render_sfun_files.m) | 生成 UDP transport 不调用 `bind()`；DSP IP/UDP port 来自 generated config；S-Function 保持 0 transport runtime parameters。 | [`run_pc_udp_template_test.py`](../tests/pc/run_pc_udp_template_test.py)、[`pc_udp_host_test.c`](../tests/pc/pc_udp_host_test.c)、[`test_pc_protocol_candidates.m`](../tests/app/test_pc_protocol_candidates.m)。 | IMPLEMENTED / EVIDENCE MAPPED — AUDIT PENDING |
| FR-048–FR-053 | 完整 Datagram staging；一次 recv Header 接收整个 Datagram；Payload 只来自同一 staged Datagram；framing/oversize/declared length 检查；一次完整 send；Header/Payload 共用 absolute deadline。 | [`pc_udp.c.in`](../app/templates/pc_udp.c.in)、[`pc_udp.h.in`](../app/templates/pc_udp.h.in)、[`protocol.c.in`](../app/templates/protocol.c.in) | `PC_UDP_MAX_DATAGRAM_SIZE = 1472`；staging capacity 为 1473 guard；V1 header 为 4，UDP payload 上限为 1468；shared deadline binding。 | [`pc_udp_host_test.c`](../tests/pc/pc_udp_host_test.c)、[`pc_udp_protocol_loop_test.c`](../tests/pc/pc_udp_protocol_loop_test.c)、[`run_pc_udp_protocol_loop_test.py`](../tests/pc/run_pc_udp_protocol_loop_test.py)。 | IMPLEMENTED / EVIDENCE MAPPED — AUDIT PENDING |
| FR-054 | TCP、UDP、SCI 共用单一 V1 protocol template，通过 transport binding 分别绑定 `pc_socket`、`pc_udp`、`pc_serial`。 | [`protocol.c.in`](../app/templates/protocol.c.in)、[`protocol.h.in`](../app/templates/protocol.h.in)、[`c2837x_block_render_pc_files.m`](../app/c2837x_block_render_pc_files.m)、[`c2837x_block_render_sfun_files.m`](../app/c2837x_block_render_sfun_files.m) | `bind_udp_protocol` / `bind_serial_files`；不存在 `protocol_udp.c.in`。 | [`test_pc_protocol_candidates.m`](../tests/app/test_pc_protocol_candidates.m)、[`test_sfun_candidates.m`](../tests/app/test_sfun_candidates.m)、[`test_udp_s5_04_mixed_generation.m`](../tests/app/test_udp_s5_04_mixed_generation.m)。 | IMPLEMENTED / EVIDENCE MAPPED — AUDIT PENDING |
| FR-055–FR-060 | 显式 `useW5300/useTcp/useUdp/useSci` closure；W5300 common source 按需且只一份；TCP/UDP channel 条件生成；每个 instance 静态绑定自己的 channel/Ops。 | [`c2837x_block_build_dsp_output_model.m`](../app/c2837x_block_build_dsp_output_model.m)、TCP/UDP provider definitions、[`c2837x_block_render_dsp_project_files.m`](../app/c2837x_block_render_dsp_project_files.m) | `useW5300 = useTcp || useUdp`；UDP-only 不生成 TCP channel；mixed project config 只生成一次。 | [`test_dsp_output_model.m`](../tests/app/test_dsp_output_model.m)、[`test_dsp_integration_completeness.m`](../tests/app/test_dsp_integration_completeness.m)、[`test_udp_s5_04_mixed_generation.m`](../tests/app/test_udp_s5_04_mixed_generation.m)。 | IMPLEMENTED / EVIDENCE MAPPED — AUDIT PENDING |
| FR-061–FR-064 | 每个 S-Function instance 只带一个 PC transport；source selection 三路显式分支；Interface Hash 排除 transport-specific settings；fingerprint/dependency 记录真实闭包。 | [`c2837x_block_build_sfun_output_model.m`](../app/c2837x_block_build_sfun_output_model.m)、[`c2837x_block_render_sfun_files.m`](../app/c2837x_block_render_sfun_files.m)、[`c2837x_block_render_pc_files.m`](../app/c2837x_block_render_pc_files.m)、[`c2837x_block_build_interface_hash.m`](../app/c2837x_block_build_interface_hash.m) | 每 instance 11 files；`w5300_tcp -> pc_socket`、`w5300_udp -> pc_udp`、`sci -> pc_serial`；unknown IoDevice 明确报错。 | [`test_sfun_candidates.m`](../tests/app/test_sfun_candidates.m)、[`test_sfun_build_candidates.m`](../tests/app/test_sfun_build_candidates.m)、[`test_pc_protocol_candidates.m`](../tests/app/test_pc_protocol_candidates.m)、[`test_udp_s5_04_mixed_generation.m`](../tests/app/test_udp_s5_04_mixed_generation.m)。 | IMPLEMENTED / EVIDENCE MAPPED — AUDIT PENDING |
| FR-065–FR-075 | 复用现有 error categories；packet loss 最终表现为 timeout；保留 OS socket error；保留三类 timeout macro；short/long/oversize framing、alien peer、SIM_STOP best-effort 和 interaction-timeout cleanup 符合边界。 | [`pc_udp.c.in`](../app/templates/pc_udp.c.in)、[`c2837x_block_pc_error.h`](../simulink/c2837x_block_pc_error.h)、[`protocol.c.in`](../app/templates/protocol.c.in)、[`c2837x_w5300_udp_channel.c`](../dsp/src/c2837x_w5300_udp_channel.c)、[`c2837x_block.c`](../dsp/src/c2837x_block.c) | `CONNECT_TIMEOUT_MS`、`STEP_TIMEOUT_MS`、`TERMINATE_TIMEOUT_MS` 继续生成；UDP connect 不作为 remote handshake；Core timeout 负责 session cleanup。 | [`pc_udp_host_test.c`](../tests/pc/pc_udp_host_test.c)、[`pc_udp_protocol_loop_test.c`](../tests/pc/pc_udp_protocol_loop_test.c)、[`test_s3_04_w5300_udp_lifecycle.m`](../tests/dsp_host/test_s3_04_w5300_udp_lifecycle.m)、[`test_s2_08_timeout_lifecycle.m`](../tests/dsp_host/test_s2_08_timeout_lifecycle.m)。 | IMPLEMENTED / EVIDENCE MAPPED — AUDIT PENDING |
| FR-076 | Project/App 自动验证覆盖 UDP create/switch/save/load、V4、defaults、Socket/Port/resource/payload/summary/copy。 | [`c2837x_block_iodevice_w5300_udp_definition.m`](../app/c2837x_block_iodevice_w5300_udp_definition.m)、[`C2837xBlockConfigurator.m`](../app/C2837xBlockConfigurator.m)、project validation/generation services。 | S6-01 actual Project/App UDP slice. | S6-01: **225 passed / 0 failed / 3 incomplete**；3 个 incomplete 均为 Windows platform assumption filtering of Unix permission tests。 | S6-01 SOFTWARE EVIDENCE RECORDED — AUDIT PENDING |
| FR-077 | DSP host/mock UDP 覆盖 OPEN、PACKET-INFO、peer/filter、same-Datagram RX、physical length、delayed RECV、atomic TX、pending SEND、SENDOK、close 和 TCP regression。 | [`c2837x_w5300_socket.c`](../dsp/src/c2837x_w5300_socket.c)、[`c2837x_w5300_udp_channel.c`](../dsp/src/c2837x_w5300_udp_channel.c) | S6-01 DSP host/mock execution slice；host tests use production DSP sources with fixtures. | S6-01: **9 passed / 0 failed / 0 incomplete**。 | S6-01 SOFTWARE EVIDENCE RECORDED — AUDIT PENDING |
| FR-078 | 真实 OS localhost UDP 覆盖 SIM_START/RESPONSE、INPUT_DATA/OUTPUT_DATA、SIM_STOP、whole datagram、staging、timeout、short/mismatch。 | [`pc_udp.c.in`](../app/templates/pc_udp.c.in)、[`protocol.c.in`](../app/templates/protocol.c.in)、[`pc_udp_protocol_loop_test.c`](../tests/pc/pc_udp_protocol_loop_test.c) | S6-01 real localhost UDP execution slice；production-derived/generated `pc_udp` exercised by a local peer. | S6-01: **30 passed / 0 failed / 0 incomplete**。 | S6-01 SOFTWARE EVIDENCE RECORDED — AUDIT PENDING |
| FR-079 | UDP-only、TCP+UDP、UDP+SCI、TCP+UDP+SCI deterministic generation；确认 common source、channel、project config 和 per-instance MEX closure。 | [`c2837x_block_build_dsp_output_model.m`](../app/c2837x_block_build_dsp_output_model.m)、[`c2837x_block_build_sfun_output_model.m`](../app/c2837x_block_build_sfun_output_model.m)、[`test_udp_s5_04_mixed_generation.m`](../tests/app/test_udp_s5_04_mixed_generation.m) | 四个代表性 mixed combinations；unknown transport explicit failure。 | S6-01: **7 passed / 0 failed / 0 incomplete**。 | S6-01 SOFTWARE EVIDENCE RECORDED — AUDIT PENDING |
| FR-080 | MEX/TI compile result must reflect actual available compilers; host compile cannot be reported as TI build. | [`build_sfun.m` renderer](../app/c2837x_block_render_sfun_build_files.m)、[`test_pc_protocol_candidates.m`](../tests/app/test_pc_protocol_candidates.m)、[`test_sfun_build_candidates.m`](../tests/app/test_sfun_build_candidates.m) | MinGW64 C 8.1.0 built representative `axis_udp_sfun.mexw64`; TI C2000 `cl2000` 25.11.0 compiled 11 generated UDP C files. | S6-01: MEX = **PASS**；TI = **11/11 compile-only PASS**。No complete CCS build/link/download/board execution claim. | S6-01 SOFTWARE EVIDENCE RECORDED — AUDIT PENDING |
| FR-081 | 最终 W5300 UDP PIL 实机验证由用户执行，开发侧不得声明 hardware PASS。 | Frozen requirements FR-081；当前 UDP channel/PC transport 是开发实现，硬件连接和用户 CCS/board flow 不在本任务执行范围。 | 用户需执行最终 UDP PIL；Project 不保存 PC local UDP port，启动/step/terminate 需按当前 wire/session contract 验证。 | S6-01 未执行用户实机验证；无 hardware PASS evidence。 | USER_VALIDATION_PENDING |
| FR-082 | V1 第一版非目标：ACK/NAK、retry/retransmission、reorder/duplicate suppression、heartbeat/keepalive、resume/takeover、IP fragmentation larger-frame、随机 loss/长期矩阵及 performance gate。 | [`pc_udp.h.in`](../app/templates/pc_udp.h.in)、[`pc_udp.c.in`](../app/templates/pc_udp.c.in)、[`c2837x_w5300_udp_channel.h`](../dsp/inc/c2837x_w5300_udp_channel.h)、[`c2837x_w5300_udp_channel.c`](../dsp/src/c2837x_w5300_udp_channel.c)；current UDP docs。 | Frozen §8 governance；UDP uses one-frame-one-datagram and existing timeout/close path only. | S6-01 required software/build evidence did not claim these non-goals; static transport/lifecycle checks cover absence of retry/retransmission and extra protocol template. | IMPLEMENTED / OBSERVED NON-GOAL BOUNDARY |

Coverage is continuous and gap-free from `FR-001` through `FR-082`. The status
column intentionally leaves final audit open.

## Current closure boundary

The current documentation now describes `w5300_tcp`, `w5300_udp` and `sci`,
including representative mixed combinations and the UDP usage contract. The
current development evidence is recorded without changing the S6-01 meaning:

~~~text
297 passed / 0 failed / 3 incomplete
MEX = PASS
TI C2000 compile-only = PASS
W5300 UDP hardware PIL = USER_VALIDATION_PENDING
Final FR audit = PENDING UDP-S6-03
UDP-G6 = NOT DECLARED
~~~
