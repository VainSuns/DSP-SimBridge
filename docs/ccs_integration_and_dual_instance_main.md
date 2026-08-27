# CCS 集成与双实例 main 使用指南

本文说明如何把 Project V4 生成的 DSP 输出加入 Code Composer Studio
工程，并在目标板上启动一个或多个实例。当前 DSP 输出支持 W5300/TCP、
SCI/串口以及两者混合；实际生成文件由工程中存在的 IoDevice 类型决定。

本文只描述代码集成和用户责任。CCS 编译、下载、目标板运行和双实例实机
收发不在本次文档更新中执行。

## 1. 生成输出与编译边界

在 App 中设置 DSP Output Root 并点击 Generate 后，输出根目录包含：

~~~text
<dsp_root>/
  inc/
  src/
~~~

将本次 Generate 得到的 inc 和 src 加入 CCS 工程。不要同时加入旧 Generate
目录中的同名核心文件，也不要把多个实例目录中的同一公共源文件重复编译。
每个生成的 C 源文件在一个 CCS 工程中只编译一次。

公共 DSP 文件始终存在：

~~~text
inc/c2837x_block.h
inc/c2837x_block_protocol.h
inc/c2837x_block_iodevice.h
src/c2837x_block.c
src/c2837x_block_protocol.c
src/c2837x_block_internal.h
src/c2837x_block_config_internal.h
src/c2837x_block_platform.h
src/c2837x_block_platform.c
src/c2837x_block_timer2.c
~~~

工程描述文件始终由生成器提供：

~~~text
inc/c2837x_block_project.h
src/c2837x_block_project.c
~~~

### W5300 条件文件

只要工程中存在 W5300 实例，还会生成：

~~~text
inc/c2837x_w5300_regs.h
inc/c2837x_w5300_hal.h
inc/c2837x_w5300_socket.h
inc/c2837x_w5300_channel.h
src/c2837x_w5300_hal.c
src/c2837x_w5300_socket.c
src/c2837x_w5300_channel.c
~~~

### SCI 条件文件

只要工程中存在 SCI 实例，还会生成：

~~~text
inc/c2837x_block_sci.h
src/c2837x_block_sci.c
~~~

因此 SCI-only 工程不应从旧 W5300 工程手工带入 W5300 源文件；混合工程则
需要两组条件文件。生成器会在项目描述中设置平台能力标志，使平台初始化
只启用当前工程存在的传输。

### 实例文件

每个实例都生成：

~~~text
inc/<internal_name>_config.h
inc/<internal_name>_user_config.h
inc/<internal_name>_algorithm.h
src/<internal_name>_config.c
src/<internal_name>_io.c
src/<internal_name>_algorithm.c
~~~

当 algorithm mode 为 external_reference 时，src 中的 algorithm C 文件由
用户提供的外部源文件替代；配置、I/O 和接口头文件仍使用本次 Generate
的版本。

## 2. CCS 工程设置

按目标板和 TI 编译器版本设置 C28x 编译选项、链接命令文件和启动代码。
生成输出的公共 include 根为：

~~~text
<dsp_root>/inc
~~~

平台源文件会从其所在的 src 目录包含内部头文件；通常不需要把整个 src
目录作为公共 include 路径。需要同时加入目标工程实际使用的 TI device
support/bitfield 头文件与库，并确保 F28x_Project.h 和对应外设寄存器定义
可见。

本生成器的核心 API 使用 EABI/COFFABI 合同和 API version 2。ABI 必须与
Project V4 和 CCS 工程的编译设置一致；不要混用不同 ABI 或另一份旧版
核心头文件。

## 3. main 的调用顺序

平台初始化只调用一次，且必须在任何实例运行前完成。典型结构为：

~~~c
#include "c2837x_block.h"
#include "c2837x_block_project.h"

int16 main(void)
{
    /* 按目标板工程完成时钟、PIE、看门狗和 TI 外设基础初始化。 */

    if (C2837xBlock_PlatformInit() < 0) {
        /* 记录平台错误；不要继续运行实例。 */
        for (;;) {
        }
    }

    C2837xBlock_Init(&g_instance_a);
    C2837xBlock_Init(&g_instance_b);

    for (;;) {
        C2837xBlock_Run(&g_instance_a);
        C2837xBlock_Run(&g_instance_b);
    }
}
~~~

g_instance_a、g_instance_b 只是说明调用顺序的占位名；真实实例对象和
实例数量由生成的 c2837x_block_project.h/.c 决定。单实例工程只调用一次
Init 和 Run；双实例工程按生成文件中声明的对象逐个调用。

运行期间可通过：

~~~c
C2837xBlock_Error error =
    C2837xBlock_GetLastError(&g_instance_a);
~~~

读取实例的最后错误。C2837xBlock 是不透明类型，应用代码不应直接改写其
内部状态、协议缓冲区或 SCI 运行时结构。

## 4. PlatformInit 的实际行为

当前 PlatformInit 顺序是：

1. 初始化 Timer2。
2. 若工程含 W5300，初始化 W5300、片上/外部存储配置和网络参数。
3. 若工程含 SCI，检查 SCI descriptor，设置 SCI 使用的 LSPCLK，再初始化
   SCI GPIO 复用、pin options 和 SCI 外设。
4. 完成平台初始化并返回成功或平台错误。

SCI 时钟合同为 SYSCLK 200 MHz、LSPCLK divisor 4、LOSPCP encoding 2，
所以 LSPCLK 为 50 MHz。LOSPCP=2 在 SCI 外设初始化前设置一次；没有 SCI
实例时，PlatformInit 不会仅为了 SCI 修改 LSPCLK。SCI descriptor 已包含
生成的 module、BRR、RX/TX 端点 mux、pin type、qualification 和可选 CTRL
配置；CCS main 不应再次手工覆盖这些字段。

DSP SCI 侧是轮询实现，不使用 SCI 中断或 DMA。SCI CTRL GPIO（若配置）在
发送前置为 TX-active，发送完成后等待 TX FIFO empty 和 TXEMPTY，再恢复
为接收状态。未配置 CTRL 时不执行方向 GPIO 操作。

## 5. TI device support 与硬件责任

DSP 平台代码通过 TI device support/bitfield 接口完成 SCI 外设和 GPIO
配置。用户 CCS 工程必须提供：

- 正确的 TMS320F28377D 设备头文件和寄存器定义；
- 与目标板匹配的时钟、启动和链接配置；
- 所选 SCI 模块对应的 RX/TX GPIO 复用与电气连接；
- 若使用 CTRL GPIO，匹配收发器方向控制的电平极性；
- 与 SCI 端点匹配的物理收发器、地线和电平；
- 外部算法源码及其依赖（若选择 external_reference）。

App 能力文件只保证生成配置在目标能力范围内，不会验证目标板上实际跳线、
收发器或连接器是否正确。本文不把 half-duplex 方向控制描述为已经完成
硬件验证。

不要在 CCS 工程中增加 bootloader "A" 握手、autobaud 或固定延时来补偿
协议。DSP 平台代码已关闭 SCI autobaud；PC 和 DSP 应使用同一生成的请求
波特率合同。

## 6. W5300、SCI 和混合工程差异

| 工程类型 | 需要的传输源 | PlatformInit 行为 |
| --- | --- | --- |
| 仅 W5300 | W5300 HAL/socket/channel | 初始化 W5300 与网络 |
| 仅 SCI | SCI 头文件与 c 文件 | 设置 LSPCLK 并初始化 SCI |
| 混合 | 两组传输源都需要 | 按生成 descriptor 启用两种设备 |

网络字段在 Project V4 中始终存在，但 SCI-only 工程不会因这些字段被用于
SCI 运行时；App 只在有 W5300 实例时执行网络语义验证。

## 7. 双实例注意事项

双实例的公共平台初始化只有一次。实例之间的 I/O、协议 step、传输资源和
错误状态独立。使用两个 SCI 实例时，必须选择不同的 SCI module；即使两个
模块的 baud 相同，也不能复用同一 SCI 资源或冲突 GPIO。

混合示例的原则是：

~~~text
C2837xBlock_PlatformInit()      once
C2837xBlock_Init(instance_A)    once
C2837xBlock_Init(instance_B)    once
loop:
    C2837xBlock_Run(instance_A)
    C2837xBlock_Run(instance_B)
~~~

现有 [dual_instance_main.c](examples/dual_instance_main.c) 是仓库中的双
W5300 示例，可用于理解 main 的调用顺序。混合 W5300/SCI 工程应以本次
Generate 的 c2837x_block_project.h/.c 和实例符号为准，不要照抄旧实例名
或旧传输初始化代码。

## 8. 错误和停止行为

PlatformInit 返回负值表示平台初始化失败；当前错误类别覆盖 Timer、
W5300 初始化/内存/网络和 SCI 初始化。失败后应用应记录错误并停止实例，
而不是继续调用 Run。

运行时错误由实例错误状态保存，PC 侧生成的 PcError 也会带 instance、
传输类别、阶段以及 SCI 的 requested/actual baud 等诊断信息。应用代码应
保留这些诊断，不要在 main 中静默清除后继续通信。

当前通信实现没有自动重连、重试、重发或固定 sleep。目标板复位、线缆、
收发器或参数变化后，应由上层停止并重新初始化整个会话。

## 9. CCS 集成检查清单

在下载前确认：

- 只使用同一次 Generate 的 inc/src 文件；
- 公共核心和 project C 文件没有重复编译；
- 工程 ABI 与 Project V4 一致；
- F28x_Project.h、TI device support 和链接文件来自目标工程；
- SCI descriptor 的 module、RX/TX GPIO、baud 和 CTRL 电平与硬件一致；
- 混合工程同时包含两类传输的条件文件；
- 所有实例的 algorithm、I/O 和配置源文件来自同一生成批次；
- PlatformInit 在 Init/Run 之前且只调用一次；
- PlatformInit 失败路径不会进入 Run；
- 下载前保存并记录 CCS 工程使用的生成目录。

## 10. 当前验证状态

| 项目 | 状态 |
| --- | --- |
| 源文件/头文件清单与当前生成器 | 已按当前实现核对 |
| Project V4、SCI descriptor 和 PlatformInit 顺序 | 已按当前实现核对 |
| DSP/CCS target build | NOT_EXECUTED / 待用户编译 |
| CCS 编译 | 未执行 |
| DSP 下载/运行 | 未执行 |
| SCI 实际收发和双实例目标板 | 未执行 |
| 用户最终 CCS 工程验证 | 待用户验证 |
