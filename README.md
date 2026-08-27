# DSP-SimBridge

DSP-SimBridge 是面向 TI TMS320F28377D PTP 目标的 Simulink S-Function
与 DSP 侧运行时桥接工程。当前产品格式为 Project V4，支持在同一个工程中
配置多个实例，并按实例选择 W5300/TCP 或 SCI/串口传输。

本文档描述当前可交付的使用边界。与旧工程格式有关的内容仅放在迁移章节，
不应作为新工程的配置方法。

## 当前版本与能力

| 项目 | 当前约定 |
| --- | --- |
| Project | V4，<code>protocol_version = 1</code> |
| Core API | version 2 |
| DSP 目标 | <code>TMS320F28377D</code> |
| 封装 | <code>PTP</code> |
| ABI | <code>eabi</code> 或 <code>coffabi</code> |
| Wire | 小端字节序，固定协议版本 1 |
| 传输 | W5300/TCP、SCI/串口，可混合使用 |
| SCI 时钟 | SYSCLK 200 MHz，LSPCLK = SYSCLK / 4 = 50 MHz |
| SCI 支持 | SCI-A、SCI-B、SCI-C、SCI-D；9600、19200、38400、57600、115200 |
| SCI PC 侧 | Windows MEX，Simulink Normal mode |

每个实例独立保存 I/O、算法、采样时间、最大 payload 和传输配置。实例之间
共享协议与平台初始化代码，但资源仍按实际 SCI 模块、GPIO、W5300 socket
和 TCP 端口做冲突检查。

## 架构概览

~~~text
App / Project V4
        |
        +--> DSP output: common core + project + instance files
        |                 + W5300 files when a W5300 instance exists
        |                 + SCI files when an SCI instance exists
        |
        +--> S-Function output: one 11-file set per instance
                          + pc_socket pair for W5300
                          + pc_serial pair for SCI
        |
        +--> Simulink block
              W5300: zero S-Function parameters
              SCI: one COM Port Number parameter
~~~

公共 DSP 核心负责协议、实例调度、Timer2 和错误状态；传输层只在工程中
出现对应设备时生成。SCI 的 DSP 侧采用轮询，不使用 SCI 中断或 DMA；PC 侧
串口采用 Windows 独占打开、8N1、无流控和绝对截止时间。

## Project V4

MAT 文件默认保存为 <code>dsp_simbridge_project.mat</code>，顶层变量名为
<code>project</code>。当前持久化结构至少包含以下字段：

~~~text
project.format_version
project.common.dsp_model
project.common.package
project.common.protocol_version
project.common.abi
project.common.network.mac
project.common.network.ip
project.common.network.gateway
project.common.network.subnet
project.instances
project.output.dsp_root
project.output.sfun_root
~~~

每个 <code>project.instances(i)</code> 包含：

~~~text
display_name
internal_name
iodevice
sample_time_sec
max_payload_size_bytes
inputs
outputs
algorithm
interface_hash
~~~

W5300 实例使用 <code>socket_number</code> 和 <code>tcp_port</code>。SCI 实例使用：

~~~text
module
baud
rx_gpio
tx_gpio
rx_pin_type
rx_qualification
tx_pin_type
ctrl_gpio
ctrl_pin_type
ctrl_tx_active_level
~~~

SCI 项目不保存 COM 号，也不保存 <code>pin_group</code>、<code>com_port</code> 或 W5300 的
socket/TCP 字段。COM 号属于 Simulink S-Function 参数；SCI 引脚必须由目标
能力文件和当前工程资源共同验证。

<code>common.network</code> 在 V4 结构中始终存在，但只有包含 W5300 实例的
工程才对网络字段执行语义检查。SCI-only 工程仍需保存合法的结构字段；这不
表示 SCI 运行时会访问网络。

V2、V3 和旧顶层 <code>config</code> 的迁移规则见
[App 项目与迁移指南](docs/app_project_and_migration_guide.md)。迁移只在加载
时建立内存中的 V4 项目，不回写旧 MAT 文件。

## 快速开始

1. 启动 <code>C2837xBlockConfigurator</code>，新建或加载 Project V4。
2. 在 Project 页面确认 DSP Model、Protocol Version、ABI、MAC、IP、Gateway、
   Subnet 以及 DSP/S-Function 输出根目录。
3. 添加实例并选择传输：

   | 传输 | 必填/关键设置 |
   | --- | --- |
   | W5300/TCP | socket number、TCP port |
   | SCI/串口 | SCI Module、Requested Baud、RX GPIO、TX GPIO；CTRL GPIO 可选 |

   SCI 的 RX/TX 是独立端点，可分别属于当前模块的不同 GPIO 候选。选择
   <code>CTRL GPIO = None</code> 时不使用方向控制；使用 CTRL 时还需确认 pin type
   和 TX active level。

4. 点击 Preview，解决结构、能力、资源和接口问题后再点击 Generate。
5. 将 DSP 输出目录加入 CCS 工程，将对应的 S-Function 输出目录用于 MEX
   构建。CCS 和 MEX 构建步骤见：

   - [CCS 集成与双实例 main](docs/ccs_integration_and_dual_instance_main.md)
   - [Simulink/MEX 使用指南](docs/simulink_mex_user_guide.md)

6. SCI S-Function 在 Simulink 中填写 COM Port Number；这是正整数、
   有限、非复数、可表示为 <code>uint32</code> 的标量。W5300 S-Function 没有参数。
7. 更新模型后重新编译受影响的 MEX，并以 Normal mode 运行。首次联调还需
   按目标板实际 SCI 模块、GPIO 复用、收发器和电平检查硬件连接。

## 生成输出

DSP 输出根目录下生成：

~~~text
inc/
src/
~~~

所有工程都有公共核心、协议、平台、Timer2、项目描述和实例文件；W5300
传输文件仅在存在 W5300 实例时生成，SCI 文件仅在存在 SCI 实例时生成。
每个实例还生成独立的配置、用户配置、算法和 I/O 文件。算法使用
<code>external_reference</code> 时，生成目录引用用户提供的外部 <code>.c</code> 文件，自动算法
文件不作为可编辑候选。

每个实例的 S-Function 输出严格为 11 个文件：

~~~text
<name>_sfun.c
<name>_sfun.h
<name>_sfun_io.c
<name>_sfun_config.h
<name>_sfun_user_config.h
<name>_pc_error.h
<name>_<pc_socket|pc_serial>.c
<name>_<pc_socket|pc_serial>.h
<name>_protocol.c
<name>_protocol.h
build_<name>_sfun.m
~~~

SCI 实例使用 <code>pc_serial</code>，W5300 实例使用 <code>pc_socket</code>。构建脚本按实例
显式列出源文件和头文件，不依赖整个目录通配；App 只生成文件和构建脚本，
不会自动调用 MEX、修改 MATLAB path 或更新 Simulink 模型。

## DSP 集成

DSP 侧公共 API 位于 <code>inc/c2837x_block.h</code>：

~~~c
int16 C2837xBlock_PlatformInit(void);
void C2837xBlock_Init(C2837xBlock *instance);
void C2837xBlock_Run(C2837xBlock *instance);
C2837xBlock_Error C2837xBlock_GetLastError(
    const C2837xBlock *instance);
~~~

典型 main 顺序是：

~~~c
if (C2837xBlock_PlatformInit() < 0) {
    /* 记录平台初始化错误并停止 */
}

C2837xBlock_Init(&g_instance_a);
C2837xBlock_Init(&g_instance_b);

for (;;) {
    C2837xBlock_Run(&g_instance_a);
    C2837xBlock_Run(&g_instance_b);
}
~~~

实际生成的实例变量和实例数量以 <code>c2837x_block_project.h/.c</code> 为准。不能在
<code>PlatformInit</code> 失败后继续运行实例。

<code>C2837xBlock_PlatformInit</code> 的实际顺序为：

1. 初始化 Timer2。
2. 若工程含 W5300，初始化 W5300、内存、网络。
3. 若工程含 SCI，验证生成的 SCI 描述符，设置 LSPCLK，再初始化 SCI
   GPIO 复用、pin options 和外设。
4. 完成平台初始化并返回结果。

SCI 平台初始化使用 TI device support/bitfield 接口完成 GPIO 和 SCI 配置；
用户仍需在 CCS 工程中提供对应的设备初始化头文件、链接配置和目标板连接。
方向控制 GPIO 在发送前置为 TX-active，等待 TX FIFO empty 与 TXEMPTY 后恢复
为接收状态。

## SCI 时钟与波特率

当前固定时钟合同为：

~~~text
SYSCLK = 200 MHz
LSPCLK divisor = 4
LOSPCP encoding = 2
LSPCLK = 50 MHz
actual_baud = LSPCLK / (8 * (BRR + 1))
~~~

生成器对请求波特率计算 16-bit BRR，在候选值中选择绝对误差最小者；误差
相同时选择更小的 BRR。当前支持值为 9600、19200、38400、57600 和 115200。
这些值都通过当前验证器；当前实现没有额外的误差阈值拒绝规则。

SCI 页面同时显示 Requested Baud、Actual Baud 和
Baud Error (Actual - Requested)。实际 baud、BRR、LSPCLK 和 SCI 引脚配置
会写入生成的 descriptor；不要在用户代码中再手工改一份 baud 配置。

## Interface Hash

Interface Hash 只描述 DSP/PC 之间的接口，不是硬件配置 hash。其输入包括：

~~~text
protocol_version
wire byte order
ordered input/output count
ordered input/output name/type/dimension
input/output payload encoding
max_payload_size_bytes
~~~

它不包括 SCI module、baud、BRR、RX/TX/CTRL GPIO、pin type、COM 号、网络
地址、package 或 sample time。修改这些硬件、传输或运行参数仍可能使已生成
候选失效并需要重新 Generate，但不会改变接口 hash；修改端口、类型、维度、
顺序或最大 payload 才会改变 hash。

## Simulink 与 MEX

两种传输的生命周期都包含初始化、启动会话、按 step 交换数据和终止会话。
SCI 的启动流程额外包含 COM 参数解析、串口独占打开、8N1 配置和显式清空
RX/TX 队列。SCI 只支持 Windows MEX 和 Simulink Normal mode，生成代码中
会拒绝非 Normal mode 的 MATLAB MEX 用法；W5300 构建脚本可接受 Windows 和
POSIX 主机。

SCI 不会自动重连、重试或重发，不使用固定 sleep，也不使用 bootloader 的
<code>"A"</code> 握手。DSP 侧关闭 autobaud；PC 与 DSP 必须使用生成的同一请求波特率
配置和匹配的硬件连接。

## 当前验证状态

| 范围 | 状态 |
| --- | --- |
| Project V4 结构、默认值、切换、复制、迁移文档 | 已按当前实现核对 |
| SCI 能力、GPIO/模块资源和 W5300 资源规则 | 已按当前实现核对 |
| SCI 50 MHz LSPCLK、BRR 计算、接口 hash 边界 | 已按当前实现核对 |
| 生成文件清单、S-Function 参数和构建脚本 | 已按当前实现核对 |
| MATLAB 单元测试、MEX 编译 | 未执行 |
| DSP/CCS target build | NOT_EXECUTED |
| Real COM hardware | NOT_EXECUTED |
| Real Simulink communication | NOT_EXECUTED |
| SCI hardware | USER_VALIDATION_PENDING |
| Half-duplex hardware | NOT_EXECUTED |
| Mixed W5300/SCI hardware | NOT_EXECUTED |
| Final LSPCLK hardware confirmation | USER_VALIDATION_PENDING |
| 用户最终模型联调 | 待用户验证 |

本次文档更新不修改产品代码、App 代码、DSP 代码、Simulink/MEX 代码、
测试、需求、计划、generator、schema、LSPCLK、BRR、PcError 或 MEX 实现。

## 已知边界

- SCI PC 侧为 Windows-only；串口使用独占打开，COM 号由 S-Function 参数提供。
- SCI DSP 侧为轮询实现，没有中断或 DMA 通道。
- 当前没有自动重连、重试、重发、固定 sleep 或 autobaud 流程。
- CTRL GPIO 是可选的；若使用，必须通过能力和资源验证。
- S-Function 输出为桌面 MEX/Normal mode 运行路径，不承诺 Accelerator、
  Rapid Accelerator、模型代码生成或并行 MEX。
- 目标板上的 TI device support、时钟启动、SCI 物理收发器、引脚连线、
  CCS 工程链接和外部算法源码仍由用户工程负责。

更多字段、迁移和资源规则见
[App 项目与迁移指南](docs/app_project_and_migration_guide.md)；DSP/CCS
集成见 [CCS 集成与双实例 main](docs/ccs_integration_and_dual_instance_main.md)；
MEX 构建与块参数见 [Simulink/MEX 使用指南](docs/simulink_mex_user_guide.md)。
