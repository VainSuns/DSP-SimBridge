# C2837xBlock — DSP 在环仿真通信模块

[![MATLAB](https://img.shields.io/badge/MATLAB-R2024b%2B-blue)](https://www.mathworks.com/products/matlab.html)
[![License](https://img.shields.io/badge/License-MIT-green)](LICENSE)

C2837xBlock 是一个 DSP 在环仿真（DSP-in-the-Loop）通信模块，用于在 Simulink 仿真环境中验证运行在 TI C2000 DSP 上的控制算法。

## 📋 目录

- [概述](#概述)
- [特性](#特性)
- [系统架构](#系统架构)
- [目录结构](#目录结构)
- [快速开始](#快速开始)
- [详细使用说明](#详细使用说明)
- [协议规范](#协议规范)
- [配置参数](#配置参数)
- [故障排除](#故障排除)
- [开发指南](#开发指南)

## 概述

### 问题背景

受到硬件条件的限制，DSP 的控制算法无法在所有运行工况下得到验证。需要一种在环仿真方案，在 Simulink 仿真环境中对运行在 DSP 上的实际控制算法进行验证。

### 解决方案

构建 Simulink ↔ DSP 的双向 TCP/IP 通信链路：

1. **Simulink 端**：S-Function 模块读取仿真输入信号，通过 TCP/IP 将数据发送到 DSP；接收 DSP 处理后的结果，输出到 Simulink 仿真环境中。
2. **DSP 端**：以库的形式提供通信框架，接收输入数据、调用用户实现的控制算法、将结果返回 Simulink。
3. **配置工具**：MATLAB App 生成 Simulink 端和 DSP 端的配置文件，统一定义输入输出数据、网络参数和配置签名。

S-Function 仅负责数据转发，不涉及控制算法实现。控制算法完全在 DSP 端运行。

## 特性

- ✅ 支持 `int16`、`uint16`、`int32`、`uint32`、`single` 数据类型
- ✅ 支持 `double`（仅在 DSP 使用 EABI 且 64-bit double 时）
- ✅ 支持标量和一维数组
- ✅ 支持任意数量的输入/输出变量
- ✅ 自动生成配置文件和序列化代码
- ✅ 非阻塞通信，支持长时间仿真（step_index 自动回绕）
- ✅ 完整的错误码报告，便于调试
- ✅ 跨平台 socket 支持（Windows/POSIX）

## 系统架构

```
┌─────────────────────────────┐          TCP/IP           ┌─────────────────────────────┐
│         PC (Simulink)       │ ◄═══════════════════════► │         DSP (C2837x)        │
│                             │        (W5300)            │                             │
│  ┌──────────────┐           │                            │           ┌──────────────┐  │
│  │  S-Function  │ 输入数据 ─►│────── INPUT_DATA ────────►│──► 用户算法 ─►│ 返回结果     │  │
│  │  数据转发     │◄ 输出数据 │◄──── OUTPUT_DATA ────────│◄────────────│              │  │
│  └──────────────┘           │                            │           └──────────────┘  │
│         ▲                   │                            │                   ▲         │
│         │                   │                            │                   │         │
│  Simulink端配置文件          │                            │            DSP端配置文件      │
│  字节级序列化/网络参数        │                            │         word级序列化/网络参数  │
└─────────────────────────────┘                            └─────────────────────────────┘
```

### 通信流程

```
PC (Simulink)                              DSP
    │                                        │
    │──── SIM_START(version, hash) ────────►│  初始化
    │◄─── RESPONSE(0) ─────────────────────│  成功
    │                                        │
    │──── INPUT_DATA(step=0) ─────────────►│  输入
    │◄─── OUTPUT_DATA(step=0) ────────────│  输出
    │                                        │
    │──── INPUT_DATA(step=1) ─────────────►│  输入
    │◄─── OUTPUT_DATA(step=1) ────────────│  输出
    │                                        │
    │         ... 重复 ...                    │
    │                                        │
    │──── SIM_STOP ───────────────────────►│  结束
```

## 目录结构

```
C2837xBlock/
├── app/                            # MATLAB App 配置工具
│   ├── C2837xBlockConfigurator.m   # App 主文件
│   ├── c2837x_block_build_hash_string.m  # Hash 计算
│   ├── c2837x_block_crc32.m        # CRC32 实现
│   ├── c2837x_block_generate_dsp_files.m # DSP 文件生成器
│   ├── c2837x_block_generate_pc_files.m  # PC 文件生成器
│   └── c2837x_block_validate_name.m      # 变量名验证
│
├── dsp/                            # DSP 端源代码（参考实现）
│   ├── inc/                        # 头文件
│   └── src/                        # 源文件
│
├── simulink/                       # Simulink 端源代码
│   ├── c2837x_block_sfun.c         # C S-Function 主文件
│   ├── c2837x_block_sfun.h         # S-Function 头文件
│   ├── c2837x_block_pc_socket.c/h  # Socket 封装
│   ├── c2837x_block_protocol.c/h   # 协议实现
│   ├── build_c2837x_block_sfun.m   # MEX 编译脚本
│   └── c2837x_block_sfun_matlab.m  # MATLAB S-Function（遗留）
│
├── spec_v2_3.md                    # 协议规范文档
├── plan.md                         # 开发计划
└── README.md                       # 本文件
```

## 快速开始

### 前置条件

- MATLAB R2024b 或更高版本（带 Simulink）
- C 编译器（Windows: MinGW 或 MSVC）
- TI Code Composer Studio (CCS)
- TI C2000 DSP（C2837x 系列）
- W5300 以太网模块

### 步骤 1：配置输入输出变量

在 MATLAB 中打开配置工具：

```matlab
app = C2837xBlockConfigurator;
```

在 App 界面中：
1. 添加输入变量（如 `a`, `b`, `c`，类型 `int16`）
2. 添加输出变量（如 `sum`，类型 `int16`）
3. 配置网络参数（IP 地址、端口等）
4. 设置 DSP 和 PC 输出目录（**不能在项目文件夹内**）

### 步骤 2：生成配置文件

点击 **Generate** 按钮，App 会生成：
- **DSP 端文件**：配置头文件、序列化代码、全局变量定义
- **PC 端文件**：配置头文件、端口 I/O 代码

### 步骤 3：在 CCS 中创建 DSP 工程

#### 3.1 创建新工程

1. 打开 Code Composer Studio
2. 选择 **File → New → CCS Project**
3. 选择目标器件（如 TMS320F2837xD）
4. 设置工程名称和位置
5. 选择编译器版本和配置（建议使用 EABI）

#### 3.2 导入生成的 DSP 文件

将 App 生成的 DSP 文件复制到 CCS 工程目录：

```
your_ccs_project/
├── inc/                            # 头文件目录
│   ├── c2837x_block_algorithm.h    # 生成：用户算法接口
│   ├── c2837x_block_config.h       # 生成：DSP 配置
│   ├── c2837x_block.h              # 拷贝：DSP 主 API
│   ├── c2837x_block_protocol.h     # 拷贝：协议定义
│   ├── c2837x_w5300_regs.h         # 拷贝：W5300 寄存器
│   ├── c2837x_w5300_hal.h          # 拷贝：W5300 HAL
│   └── c2837x_w5300_socket.h       # 拷贝：Socket 封装
└── src/                            # 源文件目录
    ├── c2837x_block_config.c       # 生成：配置实现
    ├── c2837x_block_global_variable.c  # 生成：全局变量
    ├── my_algorithm.c              # 用户编写：算法实现
    ├── c2837x_block.c              # 拷贝：DSP 主实现
    ├── c2837x_block_protocol.c     # 拷贝：协议实现
    ├── c2837x_w5300_hal.c          # 拷贝：W5300 HAL
    └── c2837x_w5300_socket.c       # 拷贝：Socket 封装
```

#### 3.3 配置 CCS 工程

1. 在 CCS 中右键工程 → **Properties**
2. **Build → Include Options**：添加 `inc` 目录到包含路径
3. **Build → C2000 Compiler → Processor Options**：
   - Target: `--float_support=fpu64`（如需 double 支持）
   - ABI: `--abi=eabi`（与配置工具选择一致）
4. **Build → C2000 Linker → File Search Path**：确保链接所有源文件

### 步骤 4：编写自定义算法函数

编辑 `my_algorithm.c` 文件，实现三个回调函数：

```c
#include "c2837x_block_algorithm.h"

/**
 * @brief 仿真开始回调
 * @return 0 成功，非 0 失败
 */
int C2837xBlock_OnSimStart(void)
{
    // 初始化代码（如外设、变量等）
    // ...
    
    return 0;  // 返回 0 表示成功
}

/**
 * @brief 每个仿真步回调
 * @return 0 成功，非 0 失败
 */
int C2837xBlock_OnStep(void)
{
    // 读取输入变量（名称由配置工具定义）
    int16_t a = c2837x_block_input.a;
    int16_t b = c2837x_block_input.b;
    int16_t c = c2837x_block_input.c;
    
    // 执行控制算法
    int16_t sum = a + b + c;
    
    // 饱和处理（可选）
    if (sum > 30000) sum = 30000;
    if (sum < -30000) sum = -30000;
    
    // 写入输出变量（名称由配置工具定义）
    c2837x_block_output.sum = sum;
    
    return 0;  // 返回 0 表示成功
}

/**
 * @brief 仿真结束回调
 */
void C2837xBlock_OnSimStop(void)
{
    // 清理代码（如关闭外设、保存数据等）
    // ...
}
```

**输入输出变量访问**：

```c
// 读取输入（结构体字段名由配置工具定义）
int16_t val = c2837x_block_input.variable_name;

// 写入输出（结构体字段名由配置工具定义）
c2837x_block_output.variable_name = val;

// 数组类型变量
int16_t elem = c2837x_block_input.array_name[index];
c2837x_block_output.array_name[index] = elem;
```

**返回值约定**：
- `C2837xBlock_OnSimStart()` 和 `C2837xBlock_OnStep()` 返回 `0` 表示成功
- 返回非 `0` 值时，Simulink 端会收到错误码 5（ALGORITHM）并终止仿真

### 步骤 5：编译并烧录 DSP 程序

1. 在 CCS 中编译工程：**Project → Build Project**
2. 连接 DSP 硬件
3. 烧录程序：**Run → Debug**
4. 运行 DSP 程序

### 步骤 6：编译 PC 端 C S-Function

在 MATLAB 中切换到 PC 输出目录并编译：

```matlab
cd <your_pc_output_dir>
build_c2837x_block_sfun
```

### 步骤 7：运行 Simulink 仿真

1. 打开 Simulink 模型
2. 添加 S-Function Block，设置 Function name 为 `c2837x_block_sfun`
3. 连接输入输出端口（端口数量和类型由配置决定）
4. 运行仿真

## 详细使用说明

### MATLAB App 配置工具

#### 输入变量配置

| 参数 | 说明 | 示例 |
|------|------|------|
| Name | 变量名（C 标识符） | `a`, `b`, `input_array` |
| Type | 数据类型 | `int16`, `single`, `double` |
| Dim | 数组维度（1 为标量） | `1`, `10` |

#### 网络配置

| 参数 | 默认值 | 说明 |
|------|--------|------|
| DSP IP | 192.168.1.100 | DSP 的 IP 地址 |
| Gateway | 192.168.1.1 | 网关地址 |
| Subnet | 255.255.255.0 | 子网掩码 |
| TCP Port | 5000 | TCP 端口号 |
| Socket | 0 | W5300 Socket 编号 |

#### 输出目录规则

- DSP 和 PC 输出目录**不能**是项目文件夹的子目录
- 可以只生成一侧（留空另一侧）
- 文件已存在时会提示是否覆盖

### C S-Function

#### 支持的 S-Function 回调

| 回调函数 | 功能 |
|----------|------|
| `mdlInitializeSizes` | 配置端口数量、类型、宽度 |
| `mdlInitializeSampleTimes` | 设置固定离散采样时间 |
| `mdlStart` | 连接 DSP，执行 SIM_START 握手 |
| `mdlOutputs` | 每个采样点执行数据交换 |
| `mdlTerminate` | 发送 SIM_STOP，关闭连接 |

#### 错误码

| 错误码 | 含义 | 说明 |
|--------|------|------|
| 0 | 成功 | SIM_START 成功 |
| 1 | 未知报文类型 | 收到未知消息类型 |
| 2 | 报文长度错误 | Payload 长度不匹配 |
| 3 | 配置不匹配 | config_hash 不一致 |
| 4 | 状态错误 | 协议流程错误 |
| 5 | 内部错误 | DSP 内部错误 |
| 6 | 协议版本不匹配 | 协议版本不一致 |
| 7 | step_index 不匹配 | 仿真步索引错误 |
| 8 | 不支持的数据类型 | 数据类型或 ABI 不支持 |

## 协议规范

### 帧格式

```
+--------+--------+-------------------+
| type   | length | payload           |
| 2字节  | 2字节  | length字节        |
+--------+--------+-------------------+
```

- 字节序：little-endian
- `type`：消息类型
- `length`：payload 的 wire 字节数（必须为偶数）

### 消息类型

| 类型 | 值 | 方向 | 说明 |
|------|-----|------|------|
| SIM_START | 0x0001 | PC→DSP | 开始仿真 |
| INPUT_DATA | 0x0002 | PC→DSP | 输入数据 |
| OUTPUT_DATA | 0x0003 | DSP→PC | 输出数据 |
| SIM_STOP | 0x0004 | PC→DSP | 结束仿真 |
| RESPONSE | 0x0005 | DSP→PC | 响应/错误 |

### Payload 格式

**SIM_START** (6 字节)：
```
+------------------+------------------+
| protocol_version | config_hash      |
| 2字节            | 4字节            |
+------------------+------------------+
```

**INPUT_DATA** (4 + N 字节)：
```
+------------+----------+----------+-----+
| step_index | input[0] | input[1] | ... |
| 4字节      | 变长     | 变长     |     |
+------------+----------+----------+-----+
```

**OUTPUT_DATA** (4 + N 字节)：
```
+------------+-----------+-----------+-----+
| step_index | output[0] | output[1] | ... |
| 4字节      | 变长      | 变长      |     |
+------------+-----------+-----------+-----+
```

**RESPONSE** (2 字节)：
```
+------------+
| error_code |
| 2字节      |
+------------+
```

## 配置参数

### config_hash 计算

config_hash 是配置的 CRC32 签名，用于 PC 和 DSP 端验证配置一致性。

计算内容包括：
- 协议版本
- ABI 类型
- 网络参数（IP、网关、子网、端口）
- 采样时间
- 输入输出变量定义（名称、类型、维度）
- 数据大小
- double 模式

### 支持的数据类型

| 类型 | 字节数 | DSP C 类型 | Simulink 类型 |
|------|--------|------------|---------------|
| int16 | 2 | int16_t | SS_INT16 |
| uint16 | 2 | uint16_t | SS_UINT16 |
| int32 | 4 | int32_t | SS_INT32 |
| uint32 | 4 | uint32_t | SS_UINT32 |
| single | 4 | float | SS_SINGLE |
| double | 8 | double | SS_DOUBLE |

### 序列化函数生成

App 会根据输入输出变量类型自动生成对应的序列化函数：

**PC 端**：
- 输入类型 → `write_xxx_le()` 函数（打包发送给 DSP）
- 输出类型 → `read_xxx_le()` 函数（解包从 DSP 接收）

**DSP 端**：
- 输入类型 → `read_xxx()` 函数（解包从 PC 接收）
- 输出类型 → `write_xxx()` 函数（打包发送给 PC）

## 故障排除

### 连接失败

**问题**：`C2837xBlock: Failed to connect to DSP`

**可能原因**：
1. DSP 未运行或未监听指定端口
2. IP 地址或端口配置错误
3. 网络连接问题
4. 防火墙阻止连接

**解决方法**：
1. 确认 DSP 程序已烧录并运行
2. 检查 IP 地址和端口配置
3. 使用 `ping` 测试网络连通性
4. 临时关闭防火墙测试

### 配置不匹配

**问题**：`DSP error 3 (Config hash mismatch)`

**原因**：PC 和 DSP 的配置不一致

**解决方法**：
1. 重新运行 App 生成配置文件
2. 重新编译 DSP 程序
3. 确保 PC 和 DSP 使用相同的配置

### 协议版本不匹配

**问题**：`DSP error 6 (Protocol version mismatch)`

**原因**：PC 和 DSP 的协议版本不一致

**解决方法**：
1. 更新 PC 和 DSP 代码到相同版本
2. 重新生成配置文件

### 超时错误

**问题**：通信超时

**可能原因**：
1. DSP 处理时间过长
2. 网络延迟
3. DSP 程序卡死

**解决方法**：
1. 增加超时时间配置
2. 检查 DSP 程序是否有死循环
3. 检查网络连接质量

## 开发指南

### 添加新的数据类型

1. 在 `c2837x_block_validate_name.m` 中添加类型验证
2. 更新 `type_wire_bytes()` 函数
3. 更新 `type_to_c_type()` 函数
4. 更新 `type_to_simtype()` 函数
5. 更新序列化函数生成器

### 扩展 S-Function

C S-Function 的端口配置由 `c2837x_block_sfun_io.c` 自动生成。如需自定义：

1. 修改 App 的 `gen_sfun_io_c()` 函数
2. 重新生成配置文件
3. 重新编译 MEX 文件

## 版本历史

| 版本 | 日期 | 说明 |
|------|------|------|
| V2.3 | 2026-06-20 | C S-Function、完整协议实现、MATLAB App 配置工具 |
| V2.2 | 2026-06-19 | 协议规范完善、DSP 状态机重构 |
| V1.0 | 2026-06-19 | 初始版本，MATLAB S-Function |

## 关于本项目

本项目由 AI 辅助生成，包括：
- 协议规范文档（spec_v2_3.md）
- DSP 端通信库代码
- PC 端 C S-Function 代码
- MATLAB App 配置工具
- 单元测试和协议测试向量

开发过程中采用人机协作模式：AI 负责代码生成和实现，人工负责需求定义、代码审查和硬件验证。

## 许可证

本项目采用 MIT 许可证。详见 [LICENSE](LICENSE) 文件。

## 联系方式

如有问题或建议，请提交 Issue 或 Pull Request。
