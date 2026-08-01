# App 项目与旧配置迁移指南

本文说明当前多实例 `C2837xBlock Configurator` 的项目配置、迁移、Preview 和 Generate 流程。界面字段、文件动作和项目状态均以当前 V2 App 实现为准。

## 1. 范围

本文覆盖：

- 启动 App 和默认空项目；
- 项目公共配置；
- 实例以及输入、输出管理；
- Interface Hash 和内存报告；
- 项目保存、加载和 dirty 状态；
- 旧单实例 `config` 文件迁移；
- Generation Preview、候选文件动作和 Preview 失效；
- Generate 和生成结果查看；
- 从空项目建立双实例项目的完整示例。

本文不覆盖 CCS 工程集成、DSP 编译与下载、W5300 实机、Simulink 模型接入、MEX 构建与运行或 POSIX 验证。这些工作不能从本文推断为已经验证。

## 2. 启动和默认项目

先让 MATLAB 能找到仓库的 `app` 目录，再运行：

```matlab
app = C2837xBlockConfigurator;
```

App 启动后创建一个从未保存的空 V2 项目，不自动创建实例。此时工具栏只有 `Save`、`Load`、`Preview` 和 `Generate`；不存在 `New Project`、`Edit` 或 `Rename` 按钮。`Generate` 初始不可用，成功完成一次有效 `Preview` 后才会启用。

主页签为：

- `Project`
- `Instances`
- `Inputs / Outputs`
- `Issues / Interface`
- `Generation Preview`

`Inputs / Outputs` 内含 `Inputs` 和 `Outputs`；`Issues / Interface` 内含 `Issues` 和 `Interface Hash / Memory`；`Generation Preview` 下方内含 `Candidate Content` 和 `Generation Result`。

默认公共配置如下：

| 字段 | 默认值 | 启动时状态 |
| --- | --- | --- |
| `DSP Model` | `TMS320F28377D` | 只读 |
| `Protocol Version` | `1` | 只读 |
| `ABI` | `eabi` | 可选 `eabi` 或 `coffabi` |
| `MAC` | `00:08:DC:01:02:03` | 可编辑 |
| `IP` | `192.168.1.100` | 可编辑 |
| `Gateway` | `192.168.1.1` | 可编辑 |
| `Subnet` | `255.255.255.0` | 可编辑 |
| `DSP Output Root` | 空 | 可编辑或 `Browse` |
| `S-Function Output Root` | 空 | 可编辑或 `Browse` |

空项目因没有实例且两个输出根为空，不能通过完整 Preview 校验。

## 3. 项目公共配置

在 `Project` 页签的 `Project Common Configuration` 中配置公共字段。

- `DSP Model` 和 `Protocol Version` 由当前 App 固定，只读。
- `ABI` 可在 `eabi` 和 `coffabi` 之间选择。
- `MAC` 使用六个十六进制字节；必须是非全零、非广播的单播地址。
- `IP`、`Gateway` 和 `Subnet` 使用点分十进制 IPv4。项目 IP 不能是全零或广播地址；Subnet 必须是非零连续掩码。`Gateway` 可以是 `0.0.0.0`。
- 两个输出根都必须设置为规范化绝对路径。可以直接输入，也可以用各自的 `Browse` 选择目录。
- `DSP Output Root` 和 `S-Function Output Root` 必须不同，且任何一个都不能包含另一个。
- 已存在的输出根必须可读、可写；非空目录会产生 Warning，因为 App 不推断其中现有文件的归属。
- 输出根尚不存在时，其最近的现有父目录必须可读、可写。Preview 不创建目录，Generate 才按需创建。

## 4. 实例和 I/O 管理

### 4.1 实例操作

`Instances` 页签提供 `Add`、`Copy` 和 `Delete`。

- `Add` 创建一个实例，自动选择第一个未使用的 W5300 Socket（`0`～`7`）和从 `5000` 开始的第一个未使用 TCP port。实例名依次建议为 `instance_1`、`instance_2` 等；初始包含一个 `single` 输入 `input_value` 和一个 `single` 输出 `output_value`。
- `Copy` 复制当前实例的 IoDevice 设置、Sample Time、Max Payload Limit、全部输入、全部输出和 Algorithm Mode；Display Name、Internal Name、Socket 和 TCP port 会重新自动分配。External Source Path 和保存的辅助 Interface Hash 不复制，均从空值/默认值开始。因此复制采用外部算法模式的实例后，应重新选择其源文件。
- `Delete` 删除项目中的实例，但不会删除磁盘上此前生成的文件。界面会要求确认并明确提示这一点。

没有独立的 Rename 按钮。选中实例后，在 `Instance Detail` 中直接修改 `Display Name` 或 `Internal Name`。修改 `Internal Name` 不会重命名或清理磁盘中的旧目录和文件。

`Internal Name` 必须是合法名称：以英文字母开头，后续只含英文字母、数字或下划线；不能是 C 关键字、实现保留名、生成代码保留符号或使用保留前缀 `C2837X_`；在项目内按不区分大小写的方式唯一。不同实例的 Socket 和 TCP port 也必须唯一。当前 `w5300_tcp` 最多支持 8 个实例。

实例详情还可编辑：

- `Socket`：`0`～`7`；
- `TCP Port`：有效且未被其他实例占用的端口；
- `Sample Time`：有限正数；
- `Max Payload Limit (wire octets)`：偶数，范围 `6`～`65534`，且不能小于实际输入或输出 Payload；
- `Algorithm Mode`：`generated_example`、`external_copy` 或 `external_reference`。后两者要求选择 `External Source Path`。

### 4.2 输入和输出

先在 `Instances` 表中选择实例，再打开 `Inputs / Outputs`。`Inputs` 和 `Outputs` 两侧都支持：

- `Add`
- `Remove`
- `Move Up`
- `Move Down`

表格列为 `Name`、`Type`、`Dim`。当前支持的数据类型是：

- `int16`
- `uint16`
- `int32`
- `uint32`
- `single`
- `double`

`Name` 使用与 `Internal Name` 相同的标识符规则；同一实例的输入和输出共享名称空间，名称按不区分大小写的方式唯一。`Dim` 必须是有限正整数。每个实例至少保留一个输入和一个输出，因此表中只剩一行时 `Remove` 不执行删除。

输入和输出在表中的顺序就是接口顺序。`Move Up` 或 `Move Down` 会改变 canonical text 和 Interface Hash。

## 5. Interface Hash 和接口报告

Interface Hash 是每个实例接口规范的 CRC-32，用于确认通信两端采用相同的 wire 接口。它从当前配置生成 canonical text 后重新计算；项目文件中的 `interface_hash` 只是上次保存的辅助值，不是加载后的权威值。

canonical text 包含：

- `Protocol Version`；
- 固定的 little-endian、`uint32` step index 约定；
- 有序的输入和输出数量；
- 每个输入和输出的顺序、`Name`、`Type`、`Dim` 和元素字节数；
- Input Payload、Output Payload 和 Max Payload 的字节数。

因此，修改协议版本、I/O 名称、类型、维度、顺序或 Max Payload 会改变 Hash。以下项目字段不参与 Hash：`format_version`、`DSP Model`、`ABI`、MAC/IP/Gateway/Subnet、Display Name、Internal Name、IoDevice、Socket、TCP port、Sample Time、Algorithm Mode/Source Path、两个输出根以及保存的旧 Hash 值。

在 `Issues / Interface` → `Interface Hash / Memory` 中选择实例后，可以查看：

- Project Total Protocol Buffer Words；
- Max Payload Limit；
- Interface Hash；
- Input/Output Data Octets；
- Input/Output Payload Octets；
- Instance Protocol Buffer Words；
- RX/TX Frame Words；
- Canonical UTF-8 Octets；
- Canonical Hash Text。

加载 V2 项目时，App 会按当前配置逐实例重新生成 canonical text 和 Hash，并用重新计算值覆盖文件中保存的辅助值。如果任一保存值不同，项目加载成功但被标记为存在未保存修改；全部匹配时保持已保存且未修改状态。

## 6. 保存、加载和 dirty 状态

### 6.1 Save

点击 `Save` 保存当前项目。首次保存会打开 `Save Project` 对话框，默认文件名是 `dsp_simbridge_project.mat`。MAT 文件只写入一个顶层变量：`project`。

App 区分三种状态：

- 从未保存：`FilePath` 为空；新启动项目属于此状态。
- 已保存、未修改：有 `FilePath`，dirty 为 false。
- 已保存、已修改：有 `FilePath`，dirty 为 true。

保存前会执行完整配置校验。只有 Information 时直接保存；存在 Warning 或 Error 时，App 会显示问题并询问 `Save Current Configuration` 或 `Cancel`。选择前者会按当前配置保存，即使配置仍不能 Preview 或 Generate。

`Save` 只保存 `.mat` 项目，不执行代码生成。

### 6.2 Load、关闭和 dirty

点击 `Load` 选择 `.mat` 文件。加载其他项目或关闭 App 时，如果当前项目 dirty，App 提供 `Save`、`Don't Save` 和 `Cancel`：

- `Save`：先保存当前项目，再继续加载或关闭；首次保存仍需选择路径。
- `Don't Save`：放弃当前未保存修改并继续。
- `Cancel`：保持当前项目和窗口不变。

高于当前支持的项目格式或协议版本会被拒绝，`Issues` 中会明确提示当前 App 不支持，并建议使用更新版本 App。损坏或不完整项目使用一般加载失败提示。

Generate 与保存是独立事务：Generate 不自动保存 `.mat`，成功后也不清除 dirty 状态。

## 7. 旧单实例配置迁移

旧项目 MAT 文件的顶层变量是 `config`，V2 项目的顶层变量是 `project`。使用 `Load` 选择只包含顶层 `config` 的旧文件时，App 自动将其迁移为一个 V2 实例；如果文件既无 `project` 也无 `config`，则拒绝加载。

迁移结果：

- `display_name`：`C2837xBlock`
- `internal_name`：`c2837x_block`
- IoDevice：`w5300_tcp`
- 迁移 MAC、DSP IP、Gateway、Subnet、Socket、TCP port、Sample Time、Max Payload、Inputs 和 Outputs。
- `abi=eabi` 保持为 `eabi`；旧 `coff` 或 `coffabi` 映射为 `coffabi`；缺少 ABI 时默认为 `eabi`。
- 缺少 `protocol_version` 时使用 `1`；值为 `1` 时迁移；高于支持版本时拒绝并提示使用更新版本 App；零值或非法值视为损坏。
- Algorithm 使用 `generated_example`，External Source Path 为空。
- `double_mode`、旧 Socket buffer 字段、旧 DSP/PC 输出路径、旧 Hash 以及 I/O 中的旧辅助 Hash 字段不迁移。
- 两个新输出根保持为空，需在 Preview 前重新设置。

迁移会重新计算实例 Interface Hash。原旧文件不会被覆盖；迁移后的 `FilePath` 为空且 dirty 为 true。点击 `Save`，在对话框中选择一个新的 `.mat` 路径，即可将迁移结果保存为顶层变量为 `project` 的 V2 项目。

## 8. Preview 和候选文件动作

点击 `Preview` 后，App 会：

1. 对当前项目执行完整配置校验；
2. 构建 DSP、S-Function 和实例候选文件；
3. 收集生成模板和 Core 依赖；
4. 读取所需的外部算法源；
5. 将候选字节与目标文件比较；
6. 建立包含项目、接口、依赖、外部源、候选文件、动作基线和目标文件状态的 Preview snapshot。

Preview 只读取和计算：它不创建输出目录、不写候选文件、不复制外部算法源、不保存项目，也不构建 MEX。

候选文件分为：

- `auto_generated`：由当前项目配置生成；
- `core`：项目公共 Core 文件；
- `user`：允许用户维护的文件。

候选状态与动作规则如下。界面 `Selected Action` 中的实际值为小写 `create`、`skip`、`replace`、`keep`；下表用对应的技术名称表示。

| 状态或类别 | 默认/固定动作 | 用户能否修改 |
| --- | --- | --- |
| `missing` | Create | 否 |
| `same` | Skip | 否 |
| `different auto_generated` | Replace | 否 |
| `different core` | Replace | 否 |
| `different user` | Keep | 可改为 Replace |

用户文件不同于候选内容时默认 `Keep`，避免自动覆盖本地修改。将其改为 `Replace` 会用候选内容覆盖当前用户文件。动作选择只属于当前 Preview snapshot，不写入项目文件，也不改变项目 dirty 状态。

在候选表中选择一行，可在 `Candidate Content` 查看候选内容。

## 9. Preview 失效

以下变化会使现有 Preview 不再可提交，必须重新点击 `Preview`：

- 项目配置变化；
- Interface Hash 或接口规范变化；
- 输出路径变化；
- 外部算法文件路径或内容变化；
- 生成模板或 Core 依赖变化；
- 候选文件集合或内容变化；
- 目标磁盘文件在 Preview 后被外部创建、删除、替换或修改；
- 已选动作不再符合候选状态和类别规则。

界面内的项目编辑会立即禁用 `Generate` 并清除旧 Preview 显示。磁盘、依赖或外部源的变化会在 Generate 提交前复核时被发现；此时 Generate 被拒绝或失败，需重新 Preview。

## 10. Generate 和结果

`Generate` 使用当前已确认的 Preview snapshot，而不是重新接受一组未预览的文件。提交前会重新验证 snapshot、当前项目、输出路径、Interface Hash、依赖、外部算法源、候选文件、动作和目标文件状态。

验证通过后，App：

1. 只为需要 Create 或 Replace 的目标按需创建输出目录；
2. 按候选顺序处理 `Create`、`Replace`、`Skip` 和 `Keep`；
3. 对 Create/Replace 在目标同目录写入临时文件，验证临时内容，再移动为目标文件并复核最终内容。

该策略保护单个文件的发布过程，但不承诺跨所有文件的全局原子事务。提交在首个失败处停止；此前已创建的目录或已成功提交的文件不会整体回滚，因此结果可能是 `partial_failure`，后续文件显示 `not_attempted`。

在 `Generation Preview` → `Generation Result` 查看：

- Status 和 Phase；
- DSP/S-Function Output Root；
- created、replaced、skipped、kept、failed 和 not-attempted 计数；
- 创建的目录和未能清理的临时文件；
- 每个实例的 S-Function 目录、`build_<internal_name>_sfun.m` 和预期 `<internal_name>_sfun.<mexext>`；
- 每个候选文件的最终结果；
- `external_reference` 实例的原始外部源及需要由用户处理的引用；
- Delete 或 Internal Name 修改造成的旧文件风险。

Generate 不自动运行每实例的 MEX build script，也不自动保存项目。

## 11. 双实例完整示例

下面的步骤从启动后的空项目建立两个实例：

```text
instance_1
Socket: 0
TCP Port: 5000

instance_2
Socket: 1
TCP Port: 5001
```

1. 在 MATLAB 中运行 `app = C2837xBlockConfigurator;`。
2. 打开 `Project`，确认只读的 `DSP Model=TMS320F28377D`、`Protocol Version=1`，按需要检查 `ABI`、MAC、IP、Gateway 和 Subnet。
3. 为 `DSP Output Root` 和 `S-Function Output Root` 选择两个不同且互不包含的绝对路径。
4. 打开 `Instances`，点击 `Add`。第一个实例应自动成为 `instance_1`、Socket `0`、TCP port `5000`。
5. 选中 `instance_1`，在 `Inputs / Outputs` 中编辑默认输入和输出，或用 `Add` 增加端口；设置每行的 `Name`、`Type`、`Dim`，并按需要调整顺序。
6. 回到 `Instances`，选中第一个实例并点击 `Copy`。复制出的第二个实例应自动成为 `instance_2`、Socket `1`、TCP port `5001`。也可以改用 `Add`，再单独配置其 I/O。
7. 在第二个实例的详情中确认或修改 `Internal Name`、Socket 和 TCP port，使其保持 `instance_2`、`1`、`5001`；如复制了外部算法模式，重新选择 External Source Path。
8. 依次选中两个实例，在 `Issues / Interface` → `Interface Hash / Memory` 检查各自的 Interface Hash、Payload 和 canonical text。
9. 点击 `Save`，用默认文件名 `dsp_simbridge_project.mat` 或新文件名保存 V2 项目。
10. 点击 `Preview`。如 `Issues` 中存在 Error，按字段提示修正后重新 Preview。
11. 在 `Generation Preview` 检查每个候选的 Category、State、Selected Action 和 Mandatory。重点确认不同的 `user` 文件是否保持 Keep，或确实需要改为 Replace。
12. Preview 有效且 `Generate` 启用后点击 `Generate`。
13. 打开 `Generation Result`，检查状态、六类文件计数、逐文件结果、两个输出根和两个实例的构建脚本/预期 MEX 名称。

此流程到生成结果为止，不包含 CCS、DSP、硬件、Simulink 或 MEX 操作。

## 12. 已知限制和风险

- Delete 只删除项目实例，不删除磁盘旧文件。
- 修改 `Internal Name` 不重命名或清理旧目录。
- Generate 不自动保存项目，成功后不清除 dirty。
- Generate 不自动构建 MEX。
- 对不同的用户文件选择 Replace 会覆盖本地修改。
- Preview 后发生任何相关配置、依赖、外部源、候选或目标文件变化，都必须重新 Preview。
- Generate 没有跨所有文件的完整回滚；中途失败可能留下已创建目录、已提交文件或报告出的临时文件。
- DSP/CCS 编译和 W5300 实机验证尚未由本文执行。
- POSIX MEX 和 GitHub CI 不属于本文的验证结论。
