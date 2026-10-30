# FieldWeave

Swift 原生 macOS 耳机声场塑形应用。**SwiftUI + Metal + 纯 Swift DSP**，原生界面和 FIR 编译无需浏览器、Python 或 Node；实时播放由已安装的 CamillaDSP 与 BlackHole 执行。项目源代码、可双击的应用和开发脚本均在这个桌面文件夹内。

## 打开

打包版本见 [GitHub Releases](https://github.com/insightlacyrina/Fieldweave/releases)。DMG 面向 Apple Silicon、macOS 14 或更新版本，安装与外部音频依赖见 [分发说明](Documentation/Distribution.md)。

双击 **`dist/FieldWeave.app`**，或双击 `Open FieldWeave.command`。修改代码后双击 `Build FieldWeave.command` 重新构建并打开。

工程采用 Swift Package；安装 Xcode 后可直接打开 `Package.swift`。本机仅用 Apple Command Line Tools 即可构建。最低部署目标 macOS 14，当前产物为本机 Apple Silicon 构建并使用本地 ad-hoc 签名。此版本是本地开发产物，不包含 Developer ID 公证或自动更新。

```sh
./scripts/build-app.sh
./scripts/test.sh
```

## 中心高度 · 0.4.0

左侧“中置信号 / 中心”新增 **−45° 至 +45° 的中心高度滑杆**，正值向上、负值向下；底部原“中心声像”旋钮改为“中心高度”，左右声像继续使用左侧滑杆。高度同时改变 Mid 音频和紫色中心的竖直位置，其他彩色层及场景原点不移动。双击高度旋钮恢复 0°；0° 严格保留此前的音频处理结果，关闭“中心塑形”会旁路高度、左右声像及 Mid 电平。

高度处理使用七套既有供体的多仰角实测 HRIR。能够按系数核对同一供体时，仅替换 Mid 的高度 HRIR，Side 保留原水平路径；旁路或未知导入矩阵使用测量数据生成相对高度频谱线索，避免盲目叠加整套 HRTF。Side 的保持指共同安全／响度增益之前的处理路径。数据来自供体，并非本人的耳朵测量；角度是处理参考，不能保证个人听感的精确高度。

高度已编入最终四路 FIR，离线渲染和导出均包含此处理；非零高度的导出包附带测量来源及 CC BY 4.0 署名。重新编辑含高度参数的配置需要 FieldWeave 0.4 或更新版本及相同内置数据版本。55 项测试、308 个 WAV 的独立来源检查、20 组真实 CamillaDSP 离线处理及原生实时高度热更新验证已通过；0.4.0 build 4 已构建、签名并在本机运行，控件联动、紫色层上下移动及保存重开均已核验。详见 [中心高度实现与验证](Documentation/Center-Elevation-2026-10-29/README.md)。

## 实时播放与 NK1 Ultra

右侧“实时系统音频”选择 BlackHole 2ch 捕获、NICEHCK NK1 Ultra 输出，点击“开始处理”。引擎就绪后才将系统默认媒体输出改为 BlackHole；直接播放 Apple Music、浏览器或其他使用系统默认输出的音频，即可听到当前 FIR 处理结果。自行指定输出的播放器须改为“系统默认”或 BlackHole。可勾选“打开 FieldWeave 时自动处理”，之后打开应用即可恢复链路。

停止处理或退出应用会恢复原媒体输出与 BlackHole 原静音状态；启动时仅解除虚拟捕获设备的静音，物理耳机音量不变。系统提示音的输出设备不改动。耳机断开、引擎退出或削波时停止处理，不自动回退扬声器；异常中断留下的路由记录会在下次启动恢复。此实现不安装驱动。本机依赖 `/usr/local/bin/camilladsp` 与已安装的 BlackHole 2ch。首次需允许 macOS 的音频捕获权限，界面中的输入、输出电平用于确认真实流量。

**自动音量平衡是实时播放的常驻特性，无需开关。** 四个预设、七套 HRTF、任意宽度／Mid／中心高度／交叉馈送／耳机 EQ 调节都经过同一链路：对完整四路 FIR 做 K 加权粉红声参考校准，再按真实输入／输出的双声道 RMS 缓慢修正。左右耳共用一个增益，保留声像和相对音色；静音、底噪、消失的内容不触发补偿。共同基准为前级增益减 6 dB，调节前级仍会主动改变音量。增益以 500 ms 平滑过渡，滤波器更新后重新等待稳定窗口；内容不同可能需要数秒收敛，并不承诺所有音乐的主观响度完全相同。

实时输出末端有不高于 −1 dBFS 的硬样本峰值保护（更低的已配置上限仍生效）；极端信号触及上限时以保护优先，可能改变瞬态，不是无损限幅或过采样真峰值保护。原有“自动余量”和报告仍描述基础 FIR；实时播放在其后追加平衡与峰值保护。离线 WAV 渲染和导出的 FIR 保留原有静态增益／保守峰值保证，不包含需要实时电平反馈的平衡链路。详见 [音量平衡验证](Documentation/Loudness-Balance-2026-10-29/README.md)。

源文件存放在桌面 `Personal-HRTF-Resources`，固定 GitHub 提交及逐文件 hash 见该目录的清单。七套 48 kHz、前方 ±30°、距离 1.47 m 的供体 HRIR 已作为独立候选导入，默认使用 c01/pp35 原照片匹配估计基线，保留 c02–c07 供比较。未执行本人听测，不能称为本人实测或已验证个人化；没有 NK1 Ultra 实测 EQ，导入预设的耳机校正旁路。详见 [导入记录](Documentation/Personal-HRTF-Import.md)。已预先双耳化的内容应旁路 HRTF，避免二次卷积。

## 界面与实际功能

- **Low / Mid / High width**：0–200%，实际驱动 log-Hz PCHIP 宽度曲线和 M/S FIR。频率页面可拖动锚点的频率和数值，分别显示目标曲线与实际编译响应。快捷三频段控制会恢复为五锚点布局。
- **Mid / center**：左侧提供等功率左右声像、±45° 中心高度和 −12 至 +6 dB Mid 电平；底部高度旋钮与左侧高度滑杆同步。紫色波峰跟随左右声像与高度移动，处理全部 Mid 内容，包括但不限于人声。关闭时严格旁路；左右居中、高度 0°、电平 0 dB 时保持中性。
- **Headphone EQ**：导入严格校验的 PEQ JSON（例见 `Examples/PEQ-Bands.json`），或批量选择校正 WAV／文件夹。单个立体声文件建议左耳声道 1、右耳声道 2；映射表可手动修改，歧义文件不自动分配。确认映射后为草稿，按 Apply 后校验生效。
- **HRTF / room**：导入四路 WAV，逐路径选择文件及通道、来源类型、归一化方式、测量来源和声源坐标，按 Apply 校验生效。路径名固定为**输入源→输出耳**：LL 左→左、LR 左→右、RL 右→左、RR 右→右。
- **Crossfeed**：默认关闭；与 HRTF/BRIR 同用须开启明确的允许叠加选项。其实际曲线及延迟保存到配置中。
- **Preamp / Automatic headroom**：实际改变最终 FIR 增益。界面读取编译结果，显示样本峰值上界、余量、公共设计延迟、Width 误差与警告；设计尚未完成或参数无效时不能导出旧结果。
- **Export FIR package**：在选定位置创建一个新目录，写入四路 Float32 WAV、可重开的配置 JSON、导入资产副本、报告、频率响应 CSV 和 CamillaDSP 模板。不覆盖已有目录，失败不留下半个包。
- **Render audio WAV**：选择匹配采样率的双声道 WAV，用当前实际 FIR 离线处理，保留完整卷积尾部并写出 Float32 WAV。超过满幅会拒绝输出，提示降低前置增益／使用自动余量。
- **DISPLAY**：只控制粒子动画、轮廓、网格、层显隐与亮度、投影景深和辉光，**不改变音频**。
- **Settings / 配置文件**：44.1／48／96 kHz、Width FIR 长度、原生 JSON 打开与保存；打开时先核对配置，再点击应用。语言选择保存在本机。有效配置自动保存到 `~/Library/Application Support/FieldWeave/Autosave.json`。未知字段及不支持的功能明确拒绝，不静默丢弃。

中心由 25,842 个粒子、耳形膜面、连续紫色曲面和细圆环构成；均由 Swift 几何及 Metal 着色器生成，无图片纹理和拉伸。坐标原点固定，场景内滚动、捏合、拖动无平移／缩放响应。粒子在局部约束范围内随机漂移，保持此前提高到三倍的速度。原生旋钮外圈按角度跟随，中心垂直拖动，Shift 细调，底部空隙不会跳到另一端；支持方向键和辅助功能调整。

导入 WAV 支持批量文件和文件夹（只读取一层，最多 128 个）。文件检查与解码在后台执行，立即列出实际采样率、声道数、长度及失败原因。矩阵仅对明确的 LL/LR/RL/RR 或 LS_LE/LS_RE/RS_LE/RS_RE 单声道文件名或 left_source/right_source 立体声文件提出映射；类型、来源、坐标需自行确认。重复使用同一声道需明确确认。

配置、PEQ 与 FIR 均先核对或暂存，成功应用后才替换生效结果；较新的导入或编辑会使旧任务失效。应用成功的 IR 副本保存在 `~/Library/Application Support/FieldWeave/Assets/`，原文件移动不再影响该配置；普通保存仍是本机 JSON 引用，可移植备份请使用完整 FIR 导出包。

右上角问号打开中英文使用说明，包含 16 章可点击目录，覆盖完整操作、映射约定、格式限制、快捷键及常见问题。

## 音频边界

应用支持离线设计、渲染和受控实时处理。实时引擎使用与导出相同的完整四路 FIR，参数编译成功后更新；失败或待编译时保留上次生效的滤波器。音频设备使用持久 UID 选择并核对名称唯一性，捕获与输出不能相同。捕获和播放时钟通过异步重采样与速率调整同步。场景仍是参数的概念可视化，并非检测到的音源、物理房间模拟或测量定位；实际音频流由独立电平表表示。

原生版本支持同采样率 PCM／IEEE float WAV；不支持直接导入 SOFA 或 YAML 配置，外部 IR 不自动重采样。内置高度数据可按设计采样率转换，界面提供的 44.1／48／96 kHz 已验证；这不放宽外部 IR 的同采样率限制。遇到 `polyphase` 和未实现语义字段会拒绝导入，避免产生表面可用但处理不一致的控制。原 Python 原型的可选 SOFA 适配器和重采样流程保留在原项目，可先将数据明确转换为四路匹配采样率的 WAV 再导入。宽度 FIR 会引入公共设计延迟；实际设备和分块延迟不包含在该数值中。

输入 WAV 限 256 MiB、输出最多 5,000 万帧；离线渲染采用分块 FFT 降低峰值内存。没有默认附带实测耳机校正；七套 HUTUBS 实测供体 HRTF 已导入，但与本人的匹配尚未验证。`Examples/Matrix-Test.json` 内的脉冲仅用于通道映射测试。

## 导出包与命令行

命令行程序与应用调用同一个 `FieldWeaveCore`，可用于自动化和复核：

```sh
swift run fieldweave-cli validate Examples/FieldWeave.json
swift run fieldweave-cli build Examples/FieldWeave.json /tmp/FieldWeave-FIR
swift run fieldweave-cli render Examples/FieldWeave.json Examples/Inputs/Stereo-Test.wav /tmp/FieldWeave-rendered.wav
```

导出包中 `configuration.json` 可再次在应用中打开，引用资产已复制到 `assets/` 并使用相对路径。CamillaDSP 需从包目录运行以解析相对路径；`camilladsp-offline.yml` 需要交错 F64_LE `input.f64`，不是 WAV。导出模板本身不自动启动；应用内实时控制器另外生成填写好设备与绝对资产路径的配置并负责启动。

## 验证与源码

见 [验证记录](Documentation/Validation.md)、[Swift 与原版／CamillaDSP 数值比对](Documentation/Native-Verification.json)。

- `Sources/FieldWeave`：原生界面、旋钮、状态管理、Metal 几何与着色器。
- `Sources/FieldWeaveCore`：配置、严格校验、PCHIP／Hann FIR、RBJ PEQ、FFT／分块卷积、WAV、可移植导出。
- `Sources/FieldWeaveAudio`：CoreAudio 设备、CamillaDSP 管理、流量电平与路由恢复。
- `Sources/FieldWeaveAudioCLI`：设备诊断及有时限的实时验证入口。
- `Sources/FieldWeaveCLI`：复用同一核心的本地命令行入口。
- `Tests/FieldWeaveCoreTests`：DSP、导入、文件与数值约束测试。
- `Examples`：六种可直接打开的配置和明确标记的测试脉冲。
