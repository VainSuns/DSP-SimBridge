# App 项目与迁移指南

本文说明 C2837xBlockConfigurator 当前使用的 Project V4 结构、实例配置、
资源验证、保存/加载行为以及旧工程迁移。当前新工程使用 V4；V2/V3 只作为
兼容输入格式，不是新工程的编辑格式。

## 1. 当前合同

| 项目 | 值 |
| --- | --- |
| Project format | V4 |
| Protocol version | 1 |
| DSP model | TMS320F28377D |
| Package | PTP |
| Wire byte order | little-endian |
| ABI | eabi 或 coffabi |
| IoDevice | w5300_tcp、sci |

工程可以包含多个实例，也可以在同一工程中混合 W5300/TCP 和 SCI/串口。
每个实例的传输资源单独验证；公共网络结构仍属于 Project V4。

## 2. Project V4 持久化字段

MAT 文件默认名为 dsp_simbridge_project.mat，保存的顶层变量名为 project。
结构验证要求以下 V4 字段路径准确存在：

~~~text
project.format_version
project.common.dsp_model
project.common.package
project.common.protocol_version
project.common.abi
project.common.network
project.instances
project.output.dsp_root
project.output.sfun_root
~~~

project.common 的字段为：

~~~text
dsp_model
package
protocol_version
abi
network
~~~

project.common.network 的字段为：

~~~text
mac
ip
gateway
subnet
~~~

project.output 的字段为：

~~~text
dsp_root
sfun_root
~~~

App Project 页面显示的公共配置包括 DSP Model、Protocol Version、ABI、MAC、
IP、Gateway、Subnet、DSP Output Root 和 S-Function Output Root。DSP Model
与 Protocol Version 是当前合同字段，不能在页面中编辑；Package 是持久化的
PTP 目标字段，不是额外的用户可选传输设置。

### 实例字段

每个 project.instances(i) 要求包含：

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

algorithm 使用：

~~~text
mode
source_path
~~~

当前支持的算法 mode 是 generated_example 和 external_reference。使用外部
算法时，source_path 必须指向用户提供的外部 C 源文件。

### W5300 实例字段

当 iodevice.type = w5300_tcp 时，IoDevice 字段为：

~~~text
type
socket_number
tcp_port
~~~

默认值为 socket 0、TCP port 5000。App 添加 W5300 实例或复制 W5300 实例时，
会从可用资源中选择新的 socket/port，避免直接复制出冲突。

### SCI 实例字段

当 iodevice.type = sci 时，IoDevice 字段为：

~~~text
type
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

SCI 默认设置为：

~~~text
module                 = ''
baud                   = 57600
rx_gpio                = ''
tx_gpio                = ''
rx_pin_type            = 'Pull-up'
rx_qualification       = 'Async'
tx_pin_type            = 'Pull-up'
ctrl_gpio              = 'None'
ctrl_pin_type          = 'Standard'
ctrl_tx_active_level   = 'High'
~~~

SCI 支持模块 SCI-A、SCI-B、SCI-C、SCI-D，支持 baud 9600、19200、38400、
57600 和 115200。RX GPIO 与 TX GPIO 分别从当前模块的能力候选中选择；
它们不要求使用同一个 GPIO。CTRL GPIO 可以为 None，也可以选择能力文件
允许的 GPIO。

V4 SCI 不包含 pin_group、com_port 或 W5300 的 socket/TCP 字段。COM 号只在
Simulink SCI S-Function 中作为一个参数出现。

## 3. 新建、添加、切换和复制实例

### 新建工程和添加实例

新建工程得到一个 V4 项目，公共默认值为当前目标和协议合同，网络默认值为：

~~~text
MAC     = 00:08:DC:01:02:03
IP      = 192.168.1.100
Gateway = 192.168.1.1
Subnet  = 255.255.255.0
~~~

添加实例的默认 IoDevice 是 W5300/TCP。若选择 W5300，App 会分配第一个可用
socket 和 TCP port；若切换为 SCI，则使用 SCI 默认字段，并等待用户选择
module、RX/TX GPIO 等配置。

### 传输切换

切换实例的 IoDevice 类型会建立该类型的新设置，同时保留实例的：

~~~text
display_name
internal_name
sample_time_sec
max_payload_size_bytes
inputs
outputs
algorithm
~~~

切换为 SCI 会得到 SCI 默认 module/RX/TX/CTRL 选择状态；切换回 W5300 会得到
W5300 默认资源状态并重新执行资源验证。原传输类型专有字段不会混入新类型。

### 复制实例

复制会生成新的 display name 和 internal name，并复制采样时间、最大 payload、
I/O 和 algorithm。复制 W5300 时 App 分配新的 socket/TCP port；复制 SCI 时
不复制 module 或 GPIO 的独占资源，module、RX GPIO、TX GPIO 和 CTRL GPIO
会清空为待选择状态，baud 与 pin type/qualification 默认保持可用值。

复制得到的新实例 interface_hash 从默认值开始，需在 Generate 前通过当前
接口计算和验证。

## 4. SCI 能力、资源与校验

能力来源为：

~~~text
app/capabilities/TMS320F28377D_PTP.json
~~~

该能力文件描述目标硬件能力和合法 GPIO/mux 候选，不替代用户在项目中选择
的 baud、pin type 或具体资源。

App Preview/Validate 会检查：

- module 是否为 SCI-A/B/C/D；
- baud 是否为五个支持值之一；
- RX/TX GPIO 是否属于所选 module 的对应端点候选；
- RX/TX/CTRL pin type、RX qualification 和 TX active level 是否受支持；
- 同一工程内 SCI module 是否重复；
- RX/TX/CTRL GPIO 是否与其他 SCI 实例或活动平台资源冲突；
- SCI 实例数是否超过 4；
- W5300 socket、TCP port 和网络字段是否满足各自规则；
- I/O、算法、输出目录和接口 payload 是否满足 Project V4 合同。

SCI-only 工程不会因为 common.network 中的 IP 或网关字段而执行 W5300
网络语义检查；但是这些字段仍必须存在且通过结构验证。只要工程中有一个
W5300 实例，就会对网络字段执行对应的语义检查。

### 资源冲突处理

冲突必须在 App 中解决后再 Generate。这里的资源集合包括 capability、
Platform Reserved Resources 和其他 Instance 的占用。不要通过手工编辑 MAT
文件绕过验证；这样可能导致生成 descriptor 与目标板实际资源不一致。

## 5. SCI 时钟、baud 和页面显示

当前 SCI 时钟固定为：

~~~text
SYSCLK             = 200 MHz
LSPCLK divisor     = 4
LOSPCP encoding    = 2
LSPCLK             = 50 MHz
~~~

BRR 使用：

~~~text
actual_baud = 50,000,000 / (8 * (BRR + 1))
~~~

生成器在 1 到 65535 的 BRR 候选中选择 baud 绝对误差最小者，误差相同
时选择较小 BRR。SCI 页面显示：

~~~text
SCI Module
Requested Baud
Actual Baud
Baud Error (Actual - Requested)
RX GPIO
TX GPIO
RX Pin Type
RX Qualification
TX Pin Type
CTRL GPIO
CTRL Pin Type
CTRL TX Active Level
~~~

LSPCLK 只读显示为 50.000000 MHz (SYSCLK / 4)。当前验证器接受全部五个
支持 baud，不设置额外的 baud 误差阈值警告或拒绝规则。LSPCLK 是平台固定
配置、不可编辑，并由所有 SCI 实例共用；timeout 不会根据 Baud 或 payload
自动修改。

当 CTRL GPIO 为 None 时，CTRL Pin Type 和 CTRL TX Active Level 对运行时
不起作用；页面会将这两个控件置为不可用。

## 6. Interface Hash 与 Generate

Interface Hash 的输入是：

~~~text
protocol_version
wire byte order
ordered input/output count
ordered input/output name/type/dimension
input/output payload octets
max_payload_size_bytes
~~~

Interface Hash 不包括 IoDevice 类型、module、baud、BRR、RX/TX/CTRL GPIO、
pin type、COM 号、网络地址、package 或 sample time。

因此：

- 修改 I/O 顺序、名称、类型、维度或最大 payload 会改变 Interface Hash；
- 修改 SCI/W5300 传输设置、SCI pin 配置或 sample time 不改变 Interface Hash；
- 硬件或传输配置改变仍会使已生成候选失效，需要重新 Generate；
- 只有显式 Save 后，当前项目的 interface_hash 才写入 MAT 文件。

Preview 用于验证当前内存项目并准备生成候选。Generate 生成 DSP 和
S-Function 输出，但 App 不自动调用 MEX、不改 MATLAB path、不更新模型。

## 7. 保存、加载和 Dirty 行为

### 保存

Save 只保存顶层变量 project。保存成功后，当前 FilePath 指向该 MAT 文件，
Dirty 清除。

### 加载 V4

加载合法 V4 后，App 校验 persisted structure 和接口 hash。若保存的 hash
与当前接口计算值不一致，项目会保持 Dirty，以提示重新 Save/Generate。

### 加载旧格式

加载 V2、V3 或旧顶层 config 时：

1. 在内存中迁移到当前 V4 结构；
2. 不覆盖、不修改旧 MAT 文件；
3. 清空当前文件路径并标记 Dirty，要求用户确认并以 V4 重新保存；
4. 重新计算当前接口 hash，避免沿用旧格式的 hash 语义。

支持的持久化版本为 V2、V3 和 V4；更高版本不会被静默降级。

## 8. V2、V3 和旧 config 迁移

### V2

V2 迁移器要求旧实例为 w5300_tcp，并从旧实例复制 W5300 网络、socket、
TCP port、I/O、sample time、最大 payload 和 algorithm 字段。迁移结果使用
当前 V4 的目标、package、协议和字段布局。

V2 不包含当前 SCI V4 配置；需要 SCI 时，应在迁移后的 V4 项目中新增或切换
实例并重新选择 module、baud 和 GPIO。

### V3

V3 中的 W5300 实例保持 W5300 配置。对于 V3 SCI 实例，迁移器只接受旧
pin_group 的规范形式：

~~~text
SCI-A_TX<number>_RX<number>
SCI-B_TX<number>_RX<number>
SCI-C_TX<number>_RX<number>
SCI-D_TX<number>_RX<number>
~~~

规范字符串会分别转换为 tx_gpio = GPIO<number> 和
rx_gpio = GPIO<number>。空、非规范或无法解析的 pin_group 不会被猜测；
对应 GPIO 保持为空，随后由当前 V4 校验报告缺少或非法端点。

V3 的其他 SCI 字段会映射到当前 module、baud、pin type、qualification 和
CTRL 字段。V4 不再保存 pin_group。

### 旧顶层 config

旧配置会迁移为一个 W5300 V4 实例，并映射旧的 MAC、DSP IP、gateway、subnet、
socket、TCP port、sample time、最大 payload、I/O 和 algorithm。旧 ABI 会
映射为当前的 eabi 或 coffabi 合同；缺省 ABI 为 eabi。缺省协议版本为 1，
输出根目录按当前 V4 字段建立。

## 9. 典型配置检查清单

在 Generate 前确认：

- Project format 为 V4，DSP model 为 TMS320F28377D，package 为 PTP；
- 每个实例的 internal_name 唯一且可作为 C/MATLAB 标识符；
- SCI module、RX/TX GPIO、可选 CTRL GPIO 与目标接线一致；
- SCI module/GPIO 没有与其他实例或平台资源冲突；
- Requested Baud 与 DSP 侧使用的生成配置一致；
- W5300 工程的网络、socket 和 TCP port 正确；
- I/O 顺序、类型、维度和最大 payload 与 Simulink 模型一致；
- 输出根目录可写，外部 algorithm source_path 存在且属于用户工程；
- Preview 无结构、能力、资源、接口或输出目录错误；
- 重新 Generate 后，将新的 DSP/S-Function 输出用于后续构建。

## 10. 使用边界

- COM 号不属于 Project V4，不参与 Interface Hash，也不写入 DSP descriptor。
- 当前 SCI PC 侧为 Windows-only；W5300 的构建脚本支持 Windows 和 POSIX
  主机，但最终 Simulink 块仍按桌面 MEX/Normal mode 使用。
- SCI DSP 侧是轮询实现，没有中断或 DMA。
- 当前没有自动重连、重试、重发、固定 sleep 或 autobaud。
- 目标板 TI device support、链接脚本、外部算法和物理收发器由用户工程负责。
- 本指南描述 SCI-S5-03 当前文档合同；后续阶段的测试或交付结论不属于本指南。
