# FieldWeave

Swift 原生 macOS 耳机声场塑形与空间音频渲染应用。采用 **SwiftUI + Metal + 纯 Swift DSP** 架构，原生交互与 FIR 滤波器编译运行于本地（无需浏览器、Python 或 Node.js 运行时）；实时音频捕获与卷积由 CamillaDSP 与 BlackHole 驱动。

---

## 运行与构建

- **预编译版本**：前往 [GitHub Releases](https://github.com/insightlacyrina/Fieldweave/releases) 下载面向 Apple Silicon（macOS 14+）的 DMG 镜像。系统音频依赖及配置参见 [分发说明](Documentation/Distribution.md)。
- **快速启动**：运行 `dist/FieldWeave.app` 或执行 `Open FieldWeave.command`；修改源码后可执行 `Build FieldWeave.command` 重新编译。
- **源码工程**：基于标准 Swift Package Manager，支持 Xcode 或 Apple Command Line Tools 构建：

```sh
./scripts/build-app.sh
./scripts/test.sh
```

---

## 耳机档案与重复试听 · 0.5.0

### 耳机档案管理
- 支持在统一的 DAC 输出下为不同耳机创建独立声学档案，精细记录形态类型（入耳 / 包耳 / 压耳）、耳塞/耳垫配置、佩戴状态，以及声学测量元数据（测量来源、参考点、目标曲线与有效频宽）。
- 切换档案即可恢复对应耳机的声学参数与专属校准 EQ。

### DSP 处理管线 (v2 拓扑)
- **处理架构**：音色均衡 (Tone EQ，前置) → 空间声场渲染 (Spatial Rendering) → 耳机播放校准 (Headphone Correction，最终输出耳级)。
- **向后兼容**：旧版 v1 配置支持保持原序载入，或通过档案管理无缝迁移至 v2 输出耳校准管线；切换风格预设时独立保留耳机校准与音色均衡设置。

### 内容处理模式
- **普通立体声 (Stereo)**：标准空间化处理。
- **虚拟扬声器 (Virtual Speakers)**：扬声器声场几何模拟。
- **已双耳化 (Pre-Binaural)**：核心强制旁路声场宽度、中心高度、音色 EQ、HRTF 与 Crossfeed，仅应用耳机播放校准。
- **手动模式 (Manual)**：提供各处理环节的自定义配置。

### 重复试听系统
- 内置原生双盲试听弹窗，支持在中性基线、通用空间设置、专属档案及候选 HRTF 之间进行随机隐藏盲听对比。
- 集成音频流有效性检测与电平稳态校验机制；提供测试素材、重戴状态记录与 5 项量化评分维度的本地存储。
- 架构设计与验证记录详见 [耳机策略实现记录](Documentation/Headphone-Strategy-2026-10-30/README.md)。

---

## 中心高度渲染 · 0.4.0

- **高度维度控制**：新增 **−45° 至 +45°** 连续高度滑杆与旋钮（正值为仰角，负值为俯角），联动控制 Mid 通道声学滤波与 Metal 视效中心层的垂直高度。0° 保持水平中性。
- **处理算法**：基于多仰角实测 HRIR 数据集。针对已知供体匹配，替换 Mid 通道仰角 HRIR，Side 通道保持原始水平渲染；针对未知导入矩阵，由仰角测量数据提取相对频谱线索进行合成。
- **管线编译**：高度处理直接编入最终 4 通道 FIR，支持实时热更新及离线渲染导出。相关实现详见 [中心高度实现与验证](Documentation/Center-Elevation-2026-10-29/README.md)。

---

## 实时音频引擎与自动响度平衡

### 系统音频捕获与路由
- 通过 BlackHole 2ch 捕获系统媒体音频，经 CamillaDSP 实时卷积后输出至目标音频设备（外接 DAC 或耳机）。
- **设备生命周期托管**：引擎就绪后切换系统默认输出设备；停止或退出时自动还原原始音频路由与静音状态；支持开机/启动自动连接与异步重采样时钟对齐。依赖系统路径 `/usr/local/bin/camilladsp` 与已安装的 BlackHole 2ch。

### 动态响度平衡 (Automatic Loudness Balance)
- **实时常驻机制**：对完整 4 通道 FIR 进行 K 加权粉红噪声参考校准，并结合双声道真实输入/输出 RMS 进行动态平滑微调。
- **参数规格**：左右声道增益严格联动（锁定声像定位与相对音色），500 ms 平滑过渡，底噪与静音阶段暂停增益调整；目标基准为前级增益 − 6 dB。

### 峰值限制保护 (Peak Limiting)
- 实时输出末级配置硬样本峰值保护（上限 ≤ −1 dBFS），优先防止硬件削波失真；离线 WAV 渲染与导出 FIR 采用静态保守余量设计。技术验证详见 [音量平衡验证](Documentation/Loudness-Balance-2026-10-29/README.md)。

### HRTF 数据集
- 内置 7 套 HUTUBS 供体实测 HRIR 数据（48 kHz，前方 ±30°，距离 1.47 m），默认启用 c01/pp35 基线，支持 c02–c07 快速对比切换。详见 [导入记录](Documentation/Personal-HRTF-Import.md)。

---

## 核心功能与交互规范

- **频段宽度 (Low / Mid / High Width)**：0–200% 可调，采用对数频率 PCHIP 插值生成 M/S 宽度 FIR 滤波器。提供 3 频段快速调节与 5 锚点频响曲线精细编辑。
- **中置信号 / 左右声像 (Mid / Center)**：支持等功率左右声像、±45° 高度及 −12 至 +6 dB Mid 电平调节。
- **耳机均衡 (Headphone EQ)**：支持导入严格校验的 PEQ JSON（参考 `Examples/PEQ-Bands.json`）及校准 IR WAV 文件或目录。
- **HRTF / 空间脉冲响应**：支持 4 通道 WAV 导入，规范路径映射为：`LL`（左入左出）、`LR`（左入右出）、`RL`（右入左出）、`RR`（右入右出）。
- **互馈 (Crossfeed)**：支持独立调节模拟互馈曲线与延迟参数，可与 HRTF/BRIR 级联使用。
- **前级增益与余量 (Preamp / Headroom)**：缩放总 FIR 增益，实时计算样本峰值上界、安全余量、设计延迟及宽度误差。
- **导出 FIR 包 (Export FIR Package)**：一键生成独立工作包，包含 4 通道 Float32 WAV、配置 JSON、引用的音频资产副本、频响数据 CSV 及 CamillaDSP 运行配置模板。
- **离线音频渲染 (Render Audio WAV)**：采用分块 FFT 快速卷积算法处理立体声 WAV，保留完整卷积尾音并写出 Float32 WAV。
- **Metal 3D 视觉系统**：程序化生成 25,842 粒子流、耳形膜面与曲面环，实时映射声像定位与高度参数变化。
- **配置持久化**：支持 44.1 / 48 / 96 kHz 采样率，配置自动保存至 `~/Library/Application Support/FieldWeave/Autosave.json`；已应用的外部 IR 自动缓存至应用支持目录。

---

## 技术规格与系统边界

- **音频格式**：支持同采样率的 PCM 及 32-bit IEEE Float WAV。外部 IR 需与当前工程采样率一致；外部 SOFA 数据需预先转换为 4 通道 WAV。
- **处理上限**：离线渲染支持最大 256 MiB 输入文件，输出限制为 5,000 万采样帧（48 kHz 下约 17.3 分钟）。
- **卷积架构**：离线与实时处理统一采用 4 通道独立 FIR 结构，分块 FFT 卷积优化峰值内存占用。

---

## 命令行工具 (CLI)

`FieldWeaveCore` 暴露了完整的命令行批处理接口，支持自动化测试与生产复核：

```sh
# 校验配置文件有效性
swift run fieldweave-cli validate Examples/FieldWeave.json

# 编译并导出 FIR 包
swift run fieldweave-cli build Examples/FieldWeave.json /tmp/FieldWeave-FIR

# 离线批量渲染音频文件
swift run fieldweave-cli render Examples/FieldWeave.json Examples/Inputs/Stereo-Test.wav /tmp/FieldWeave-rendered.wav
```

---

## 源码结构与验证

测试与跨平台数值比对参见 [验证记录](Documentation/Validation.md) 与 [Swift 与原版／CamillaDSP 数值比对](Documentation/Native-Verification.json)。

- `Sources/FieldWeave`：SwiftUI 视图组件、自定义旋钮控件、应用状态管理、Metal 场景管线与着色器。
- `Sources/FieldWeaveCore`：核心 DSP 库（PCHIP/Hann 窗 FIR、RBJ 双二阶滤波器、分块 FFT 卷积）、配置校验与 WAV 编解码。
- `Sources/FieldWeaveAudio`：CoreAudio 接口封装、CamillaDSP 进程生命周期管理、双通道电平监测与音频路由托管。
- `Sources/FieldWeaveAudioCLI`：音频设备枚举诊断与限时实时处理验证入口。
- `Sources/FieldWeaveCLI`：基于同一核心库的命令行批处理工具。
- `Tests/FieldWeaveCoreTests`：DSP 算法、导入校验、文件编解码与数值约束单元测试。
- `Examples`：示例配置文件与通道映射测试脉冲。
