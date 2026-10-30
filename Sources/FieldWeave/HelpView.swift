import SwiftUI

/// The manual lives in its own sheet so the main workspace stays focused on controls.
struct HelpView: View {
    @AppStorage(AppLanguage.key) private var interfaceLanguage = "en"
    @Environment(\.dismiss) private var dismiss
    @FWState private var selected: HelpChapter = .start

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(Color.highBand)
                Text(helpText("FieldWeave User Guide", "FieldWeave 使用说明"))
                    .font(.system(size: 20, weight: .medium))
                Spacer()
                Button(helpText("Done", "完成")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)

            Rectangle().fill(Color.fieldLine).frame(height: 1)

            ScrollViewReader { reader in
                HStack(alignment: .top, spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(helpText("CONTENTS", "目录"))
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .tracking(2)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 12)
                                .padding(.bottom, 9)
                            ForEach(HelpChapter.allCases) { chapter in
                                Button {
                                    selected = chapter
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        reader.scrollTo(chapter, anchor: .top)
                                    }
                                } label: {
                                    HStack(alignment: .firstTextBaseline, spacing: 9) {
                                        Text(String(format: "%02d", chapter.rawValue + 1))
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundStyle(selected == chapter ? Color.highBand : Color.secondary)
                                        Text(chapter.title)
                                            .font(.system(size: 12))
                                            .multilineTextAlignment(.leading)
                                        Spacer(minLength: 0)
                                    }
                                    .foregroundStyle(selected == chapter ? Color.white : Color.white.opacity(0.65))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 9)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(selected == chapter ? Color.highBand.opacity(0.12) : Color.clear,
                                                in: RoundedRectangle(cornerRadius: 6))
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(selected == chapter ? .isSelected : [])
                            }
                        }
                        .padding(14)
                    }
                    .frame(width: 218)
                    .background(Color.fieldPanel.opacity(0.65))

                    Rectangle().fill(Color.fieldLine).frame(width: 1)

                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 30) {
                            ForEach(HelpChapter.allCases) { chapter in
                                chapterView(chapter)
                                    .id(chapter)
                            }
                        }
                        .padding(28)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(width: 960, height: 720)
        .background(Color.fieldBackground)
        .foregroundStyle(Color.white.opacity(0.88))
        .preferredColorScheme(.dark)
    }

    private func chapterView(_ chapter: HelpChapter) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(String(format: "%02d", chapter.rawValue + 1))
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(Color.highBand)
                Text(chapter.title)
                    .font(.system(size: 19, weight: .medium))
                    .accessibilityAddTraits(.isHeader)
            }
            ForEach(Array(chapter.blocks.enumerated()), id: \.offset) { _, block in
                if block.isCode {
                    Text(block.text)
                        .font(.system(size: 11, design: .monospaced))
                        .lineSpacing(4)
                        .textSelection(.enabled)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.fieldPanel, in: RoundedRectangle(cornerRadius: 7))
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.fieldLine))
                } else {
                    Text(block.text)
                        .font(.system(size: 13))
                        .lineSpacing(5)
                        .foregroundStyle(Color.white.opacity(0.75))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Rectangle().fill(Color.fieldLine).frame(height: 1).padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private func helpText(_ english: String, _ chinese: String) -> String {
    AppLanguage.isChinese ? chinese : english
}

private struct HelpBlock {
    let text: String
    var isCode = false

    static func prose(_ english: String, _ chinese: String) -> Self {
        Self(text: helpText(english, chinese))
    }

    static func code(_ text: String) -> Self { Self(text: text, isCode: true) }
}

private enum HelpChapter: Int, CaseIterable, Identifiable {
    case start, live, presets, width, center, importing, headphone, matrix, crossfeed
    case headroom, configuration, render, settings, display, controls, limits, troubleshooting

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .start: return helpText("Start here & signal path", "开始使用与处理顺序")
        case .live: return helpText("Live system audio", "实时系统音频")
        case .presets: return helpText("Presets & active settings", "预设与生效状态")
        case .width: return helpText("Stereo width & frequency", "立体声宽度与频率")
        case .center: return helpText("Mid / center shaping", "中置信号与中心声像")
        case .importing: return helpText("Import & review", "导入与确认")
        case .headphone: return helpText("Headphone EQ", "耳机校正")
        case .matrix: return helpText("HRTF / room matrix", "HRTF 与房间矩阵")
        case .crossfeed: return helpText("Crossfeed", "交叉馈送")
        case .headroom: return helpText("Output & headroom", "输出与余量")
        case .configuration: return helpText("Save & portable export", "保存与可移植导出")
        case .render: return helpText("Render an audio file", "渲染音频文件")
        case .settings: return helpText("Settings & language", "设置与语言")
        case .display: return helpText("Sound field & display", "声场与显示")
        case .controls: return helpText("Controls & shortcuts", "操作与快捷键")
        case .limits: return helpText("Formats & supported limits", "格式与支持范围")
        case .troubleshooting: return helpText("Troubleshooting", "常见问题")
        }
    }

    var blocks: [HelpBlock] {
        switch self {
        case .start:
            return [
                .prose("FieldWeave designs stereo FIR filters for headphone listening, applies them to live system audio and processes audio files offline. Change the sound controls and wait for “FIR ready”. You can then start live processing, export a FIR package or render a stereo WAV.",
                       "FieldWeave 用于设计耳机立体声 FIR 滤波器，可处理实时系统音频，也可离线处理音频文件。调整声音参数，等待“FIR 已就绪”后，即可开始实时处理、导出 FIR 包或渲染双声道 WAV。"),
                .prose("The processing order is headphone correction → frequency-dependent stereo width → Mid / center shaping → imported HRTF / room matrix → crossfeed → preamp and automatic headroom. The exported four filters combine this complete chain. Offline rendering and live processing use this same base FIR; live playback then adds its own level balance and sample-peak protection, described in Output & headroom.",
                       "处理顺序为：耳机校正 → 分频立体声宽度 → 中置信号与中心声像 → 导入的 HRTF／房间矩阵 → 交叉馈送 → 前级增益与自动余量。导出的四路滤波器包含这条完整处理链。离线渲染与实时处理使用相同的基础 FIR；实时播放随后追加独立音量平衡和样本峰值保护，详见“输出与余量”。")
            ]
        case .live:
            return [
                .prose("Live playback follows system playback → BlackHole → FieldWeave FIR → headphones. It requires an installed BlackHole stereo virtual device and CamillaDSP; the app does not install them. If no audio route is available, connect BlackHole 2ch and NICEHCK NK1 Ultra, then refresh devices. Choose the virtual device under Capture and the physical device under Headphone output. Device choices are locked while processing is starting or running; stop before changing them.",
                       "实时播放链路为：系统播放 → BlackHole → FieldWeave FIR → 耳机。需要已安装的 BlackHole 双声道虚拟设备与 CamillaDSP，应用不负责安装。若显示音频路由不可用，请连接 BlackHole 2ch 和 NICEHCK NK1 Ultra，再刷新设备。在“捕获设备”中选择虚拟设备，在“耳机输出”中选择物理设备。启动中或运行时设备选择被锁定，需要先停止处理再修改。"),
                .prose("Press Start processing after the FIR is ready. Only after the engine is ready does FieldWeave route the macOS default media output through BlackHole. Players with their own output selector must use System Default or BlackHole. When macOS asks for microphone access, allow it for virtual audio capture; this route does not select a physical microphone. Start when FieldWeave opens remembers whether to start the saved setup automatically.",
                       "FIR 就绪后点击“开始处理”。引擎就绪后，FieldWeave 才会将 macOS 默认媒体输出送入 BlackHole。自行选择输出的播放器须使用“系统默认”或 BlackHole。macOS 提示麦克风权限时，请允许虚拟音频捕获；此链路不选择物理麦克风。“打开 FieldWeave 时自动处理”会记住是否自动启动已保存的链路。"),
                .prose("Input and Output meters show actual stream sample peaks; Clipped samples reports clipping detected by the live engine. A successful parameter design updates the live FIR. While changes are pending or invalid, playback keeps the last applied FIR and the interface shows that state. Changing the design sample rate restarts the live engine. Live clock synchronization uses rate adjustment and asynchronous resampling; this does not convert imported IR or offline WAV files.",
                       "输入、输出电平表显示真实音频流的样本峰值；“削波样本”显示实时引擎检测到的削波。参数设计成功后会更新实时 FIR。更改尚未完成或无效时，继续播放上次生效的 FIR，界面会显示此状态。更改设计采样率会重新启动实时引擎。实时设备时钟通过速率调整与异步重采样同步；这不会转换导入的 IR 或离线 WAV 文件。"),
                .prose("Stop & restore output or quitting ends processing and restores the previous media output when BlackHole is still the selected system output. If you select a different output in macOS yourself, FieldWeave stops and respects that choice. A disconnected device, engine failure or clipping also stops processing. Reconnect the intended devices and review the error before restarting. The app does not choose fallback speakers on device failure.",
                       "点击“停止并恢复输出”或退出应用会结束处理；若系统输出仍为 BlackHole，则恢复之前的媒体输出。若自行在 macOS 选择另一输出，FieldWeave 会停止并保留该选择。设备断开、引擎故障或削波也会停止处理。重新连接目标设备，查看错误后再启动。设备故障时，应用不会选择扬声器作为备用输出。")
            ]
        case .presets:
            return [
                .prose("Neutral sets width to 100% across the spectrum. Studio uses mild widening. Immersive uses greater widening, especially at high frequencies. Vintage Stereo uses narrower lows and enables crossfeed. Every preset remains editable.",
                       "“中性”将全频宽度设为 100%；“录音室”提供轻度拓宽；“沉浸”提供更明显的拓宽，尤其是高频；“复古立体声”收窄低频并开启交叉馈送。所有预设都可继续编辑。"),
                .prose("Selecting a preset replaces the current sound configuration, including headphone correction, the imported matrix, center settings, crossfeed and output gain. It keeps the selected sample rate and FIR design lengths. Save a configuration first if you want to return to it.",
                       "选择预设会替换当前声音配置，包括耳机校正、导入矩阵、中心设置、交叉馈送和输出增益；保留当前采样率与 FIR 设计长度。若需要恢复当前声音，请先保存配置。"),
                .prose("Width, center, crossfeed and output controls trigger a new filter design. Headphone and matrix imports are drafts until you press their Apply button. A pending draft is not included in rendering, exporting or saving the active configuration. Export and render become available after the current design succeeds.",
                       "宽度、中心、交叉馈送和输出控件会触发滤波器重新设计。耳机校正与矩阵导入先进入草稿，点击各自的“应用”后才生效。待应用草稿不会进入渲染、导出或当前配置的保存结果。当前设计成功后，导出和渲染才可使用。")
            ]
        case .width:
            return [
                .prose("Width scales the difference between left and right channels. 100% keeps the original stereo width; 0% removes that difference; values above 100% increase it. Width does not measure the apparent distance of a sound source or create a measured room.",
                       "宽度控制会缩放左右声道之间的差异。100% 保留原始立体声宽度；0% 消除左右差异；超过 100% 会增大差异。它不测量声源的听感距离，也不生成实测房间。"),
                .prose("The three band controls cover lows at 20–250 Hz, mids at 250 Hz–6 kHz and highs at 6–20 kHz. They shape one continuous curve rather than three abrupt frequency blocks. Changing a band control restores the standard five-anchor layout.",
                       "三个频段控件分别对应低频 20–250 Hz、中频 250 Hz–6 kHz、高频 6–20 kHz，形成一条连续曲线，而非三个突然切换的频率区块。操作频段控件会恢复为标准的五锚点布局。"),
                .prose("In Frequency view, drag an anchor horizontally to change its frequency and vertically to change its width. The frequency axis is logarithmic. The dashed blue line is the requested width; the green line is the compiled width response. The green response appears only for a valid, completed design. This plot shows width, not the complete EQ or four-path output response.",
                       "在“频率”视图中，横向拖动锚点改变频率，纵向拖动改变宽度。频率轴采用对数刻度。蓝色虚线表示目标宽度，绿色实线表示编译后的宽度响应；只有当前设计有效且完成后才显示绿色响应。此图显示宽度，不是完整均衡或最终四路输出响应。")
            ]
        case .center:
            return [
                .prose("Center shaping affects Mid, the content shared by the left and right channels. It can move or change the level of centered vocals, but it also affects every other sound in Mid. It does not identify, extract or isolate vocals.",
                       "“中心塑形”处理 Mid，即左右声道共有的内容。它能移动居中人声或改变其电平，也会影响 Mid 中的所有其他声音；它不识别人声、不提取人声，也不做人声分离。"),
                .prose("Center height controls elevation from −45° to +45°: positive moves the center above, negative below. It changes Mid's audio using measured HRTF elevation cues and moves the purple center vertically. 0° preserves the existing center sound. The elevation describes the processing reference; perceived height depends on the listener and headphones.",
                       "“中心高度”控制 −45° 至 +45° 的仰角：正值向上，负值向下。它使用实测 HRTF 的高度线索改变 Mid 音频，并联动紫色中心上下移动；0° 保留现有中心声音。角度描述处理参考，实际听到的高度取决于听者和耳机。"),
                .prose("Center pan remains a left-panel slider with equal-power left/right positioning. Negative values move Mid left; positive values move it right. The bottom center knob controls height instead of pan. Mid level ranges from −12 to +6 dB. “Return to center” resets pan only. Turning Center shaping off bypasses pan, height and level; centered pan, 0° height and 0 dB level are neutral.",
                       "左右“中心声像”仍在左侧滑杆中采用等功率定位：负值向左，正值向右；底部原中心声像旋钮改为调节高度。“中置信号电平”范围为 −12 至 +6 dB。“回到中心”仅重置左右声像。关闭“中心塑形”会旁路声像、高度和电平；左右居中、高度 0° 且电平 0 dB 时保持中性。")
            ]
        case .importing:
            return [
                .prose("For headphone FIR or a matrix, select multiple WAV files at once or select their folder. You can still replace a single path using its file button. The import review checks each file and shows the proposed file, channel and destination mapping before it enters the draft.",
                       "导入耳机 FIR 或矩阵时，可以一次选择多个 WAV 文件，也可以选择所在文件夹；仍可通过单条路径的文件按钮替换一个文件。导入确认页逐个检查文件，在进入草稿前显示建议的文件、声道和用途映射。"),
                .prose("Review the mapping even when it is filled automatically. A stereo headphone file normally proposes channel 1 for the left ear and channel 2 for the right ear. Explicit LL/LR/RL/RR or LS_LE/LS_RE/RS_LE/RS_RE mono filenames can help propose a matrix mapping, but ambiguous names need your choice. The number of channels alone cannot establish a source direction or prove that a file is a measured HRTF.",
                       "即使已经自动填入，也请核对映射。立体声耳机文件通常建议左耳使用声道 1、右耳使用声道 2。明确的 LL／LR／RL／RR 或 LS_LE／LS_RE／RS_LE／RS_RE 单声道文件名可帮助生成矩阵建议；文件名含糊时需要自行选择。仅凭声道数无法确定声源方向，也不能证明文件是实测 HRTF。"),
                .prose("Rejected files are listed with their errors and cannot be mapped. Complete the required destinations using accepted files, or cancel and import corrected files. If you deliberately reuse one channel for multiple destinations, confirm “Use the same channel for multiple paths”. Choose “Use mappings” to stage the result, then press “Apply headphone EQ” or “Apply & validate matrix”. PEQ import also stages a draft. A full configuration has its own review and “Apply configuration” button.",
                       "被拒绝的文件会显示错误，不能用于映射。请用通过检查的文件补齐必需用途，或取消后重新导入已修正的文件。若确实要将同一声道用于多个用途，需要勾选“确认多个路径使用同一声道”。点击“确认映射”后先进入草稿，再点击“应用耳机均衡”或“应用并验证矩阵”。PEQ 导入同样先进入草稿。完整配置有独立确认页及“应用配置”按钮。"),
                .prose("A newer import supersedes an older pending import. If validation fails, the active configuration stays in place. Changing the sample rate can invalidate an open review; import again at the intended rate. Apply copies accepted IR assets into the app’s managed storage, so moving the original files afterward does not break that applied configuration.",
                       "新的导入会替代较早且尚未完成的导入。校验失败时保留原有生效配置。更改采样率可能使打开的确认页失效，此时请按目标采样率重新导入。应用时会将通过检查的 IR 复制到应用管理目录，因此随后移动原文件不会破坏这份已应用配置。")
            ]
        case .headphone:
            return [
                .prose("Bypass disables headphone correction. PEQ imports parametric peak-equalizer bands and applies the same correction to both ears. Stereo FIR uses a separate selected impulse-response channel for each ear. The app supplies no measured headphone calibration. In particular, no measured NICEHCK NK1 Ultra EQ is supplied; the included candidate preset files bypass headphone correction.",
                       "“旁通”关闭耳机校正。“PEQ”导入参数峰值均衡频段，对双耳使用相同校正。“立体声 FIR”为每只耳朵使用单独选定的脉冲响应声道。应用不附带实测耳机校准；其中也没有 NICEHCK NK1 Ultra 的实测均衡，随附候选预设文件将耳机校正设为旁通。"),
                .prose("A PEQ file must contain a JSON array. Every band must use exactly frequency_hz, q and gain_db, with numeric values. It is a band list, not a full FieldWeave configuration. For example:",
                       "PEQ 文件必须包含 JSON 数组。每个频段只能使用 frequency_hz、q 和 gain_db 这三个字段，值必须是数字。这是一份频段列表，不是完整的 FieldWeave 配置。例如："),
                .code("[\n  {\"frequency_hz\": 1000, \"q\": 0.707, \"gain_db\": -2}\n]"),
                .prose("Use at most 64 bands. Frequency must be from 1 Hz to one hertz below half the selected sample rate; Q must be 0.1–20 and gain −24 to +24 dB. Unknown fields, text in numeric fields and unsupported formats are rejected. A valid PEQ can still fail filter design if the impulse response cannot fit the configured EQ length without excessive tail loss.",
                       "最多支持 64 个频段。频率须在 1 Hz 至“当前采样率的一半减 1 Hz”之间；Q 为 0.1–20；增益为 −24 至 +24 dB。未知字段、数字字段中的文本及不支持的格式会被拒绝。若脉冲响应在配置的均衡长度内仍有过多尾部能量损失，字段有效的 PEQ 也可能无法完成滤波器设计。"),
                .prose("For FIR, complete both left and right destinations and inspect the channel choices. Two mono files can supply the two ears; one stereo file can supply both. Choosing the same channel for both ears is an intentional shared correction only when that is what your measurement requires. Press Apply after changing the mode, files or channels.",
                       "使用 FIR 时须补齐左耳与右耳两项，并检查声道选择。可用两个单声道文件分别提供双耳校正，也可从一个立体声文件读取双耳。只有测量确实要求共用校正时，才将双耳指向相同声道。更改模式、文件或声道后需要点击“应用”。")
            ]
        case .matrix:
            return [
                .prose("The four path names always read source first, output ear second. LL means left source → left ear; LR means left source → right ear; RL means right source → left ear; RR means right source → right ear. All four paths are required. These names are not the usual row-first notation used by every other convolution tool, so match their meaning when exchanging files.",
                       "四条路径名始终是“输入声源在前，输出耳朵在后”。LL 为左源→左耳；LR 为左源→右耳；RL 为右源→左耳；RR 为右源→右耳。四路均须齐全。其他卷积工具的矩阵命名可能不同，交换文件时请按实际含义对应。"),
                .code("LL: L source → L ear       LR: L source → R ear\nRL: R source → L ear       RR: R source → R ear"),
                .prose("Four mono WAVs can supply four paths. With a stereo response for each source, map the left-source file’s left/right ear channels to LL/LR, and the right-source file’s left/right ear channels to RL/RR. Verify the measurement’s actual ear order; stereo channel 1/2 is not proof of left/right ear order.",
                       "四个单声道 WAV 可分别提供四路。若每个声源对应一个双声道响应，则把左源文件中的左右耳声道映射到 LL／LR，把右源文件中的左右耳声道映射到 RL／RR。务必核对测量的真实耳序；立体声的声道 1／2 本身并不证明左右耳顺序。"),
                .prose("Choose Measured HRTF, Measured BRIR or Test only according to the actual data, and enter the measurement source. Enter and explicitly confirm each source’s coordinates: azimuth in degrees, elevation in degrees, distance in metres. Positive azimuth is left; positive elevation is up. Supported ranges are −180…180°, −90…90° and 0.001…100 m. Coordinates describe the imported measurement; editing them does not rotate or regenerate its IR. Importing replacement matrix files clears the kind, source and coordinate confirmation so you can verify the new measurement.",
                       "按实际数据选择“实测 HRTF”“实测 BRIR”或“仅测试”，填写测量来源。输入并明确确认两个声源的坐标：方位角（度）、仰角（度）、距离（米）。方位角正值向左，仰角正值向上；范围分别为 −180…180°、−90…90°、0.001…100 米。坐标用于描述导入测量；修改数字不会旋转或重新生成 IR。替换矩阵文件会清除类型、来源和坐标确认，以便重新核对新的测量数据。"),
                .prose("Preserve level keeps the imported values. Global peak scales all four paths together by their largest absolute sample, preserving the balance among paths. Neither choice proves calibration. Apply validates the full matrix. Turning the matrix off bypasses it. Test impulses are for mapping checks. Included Personal-HRTF candidates are measured HUTUBS donor pairs, with unvalidated personal match and no head tracking.",
                       "“保留电平”保持导入数值。“全局峰值”使用四路中最大的绝对样本值统一缩放，保留各路径的相对关系。两者都不代表完成校准。“应用”会校验完整矩阵；关闭矩阵开关则旁路此阶段。测试脉冲用于检查映射。随附的 Personal-HRTF 候选来自 HUTUBS 实测供体双耳；尚未验证与本人的匹配程度，且不提供头部跟踪。"),
                .prose("Personal-HRTF offers seven donor candidates at 48 kHz for frontal sources at ±30°. Select a candidate and press Apply HRTF candidate to load it. Applying a candidate sets the design to 48 kHz, replaces the externalization matrix and turns crossfeed off; the other current sound settings remain. These donor measurements are comparison candidates, not a measurement of your own ears.",
                       "Personal-HRTF 提供七套供体候选，采样率为 48 kHz，前方声源位于 ±30°。选择候选后点击“应用 HRTF 候选”加载。应用候选会将设计设为 48 kHz、替换外部化矩阵并关闭交叉馈送；其他当前声音设置保留。这些供体测量用于候选比较，不是对本人双耳的测量。")
            ]
        case .crossfeed:
            return [
                .prose("Crossfeed mixes a frequency-shaped, delayed part of each channel into the opposite ear. Low-frequency amount controls its strength, up to 30%; Delay ranges from 0 to 2 ms. The curve decreases toward high frequencies. It is off by default, except in the Vintage Stereo preset.",
                       "交叉馈送将每个声道的一部分信号经过频率塑形和延迟后混入另一耳。“低频混合量”控制强度，最高 30%；“延迟”范围为 0–2 ms。曲线会向高频逐渐减弱。默认关闭，“复古立体声”预设会开启。"),
                .prose("An imported HRTF / room matrix may already contain interaural information. Combining it with crossfeed is blocked unless you enable “Explicitly allow with IR matrix”. Use that option only when you intend to combine both stages. Disabling crossfeed bypasses its curve and delay.",
                       "导入的 HRTF／房间矩阵可能已包含双耳之间的信息。除非开启“允许与 IR 矩阵同时使用”，否则不允许同时使用交叉馈送。仅在确实希望组合这两个处理阶段时开启该选项。关闭交叉馈送会旁路其曲线与延迟。")
            ]
        case .headroom:
            return [
                .prose("Live playback always balances the complete processing chain across presets, HRTF candidates and manual sound edits. A weighted filter calibration supplies the starting gain; measured stereo input/output RMS slowly corrects it, using one gain for both ears. Silence and removed content are not amplified. The shared target is Preamp minus 6 dB; your Preamp remains the intentional output level control. No switch is required. Allow a few seconds to settle after a sound change.",
                       "实时播放始终对预设、HRTF 候选及手动声音调节进行音量平衡。先按完整滤波器的加权参考校准，再用真实输入／输出的双声道 RMS 缓慢修正，两耳共用增益。静音与已消除的内容不会被放大。共同目标为前级增益减 6 dB；前级增益仍用于主动控制输出音量。无需开关，声音变化后请留出数秒稳定时间。"),
                .prose("Live balance follows the compiled FIR and has its own final sample-peak ceiling, at most −1 dBFS. Extreme transients may hit this hard ceiling; protection takes priority over matching. This is not oversampled true-peak limiting or a guarantee of identical perceived loudness. FIR exports and offline WAV renders retain the static FIR gain and conservative headroom, without the live feedback stage. The Output / headroom panel reports that base FIR.",
                       "实时平衡位于基础 FIR 之后，并有最高 −1 dBFS 的末端样本峰值保护。极端瞬态可能触及硬上限，此时保护优先于音量匹配。这不是过采样真峰值限幅，也不保证所有音乐主观响度完全一致。FIR 导出与离线 WAV 渲染保留静态 FIR 增益和保守余量，不带实时反馈阶段。“输出 / 余量”面板的报告描述基础 FIR。"),
                .prose("Preamp adjusts the gain of the complete final filter. Automatic headroom can add attenuation to keep the calculated sample-peak bound below the configured ceiling for inputs bounded to full scale. It is a filter-wide gain adjustment, not a limiter or loudness normalizer.",
                       "“前级增益”调整完整最终滤波器的增益。“自动余量”可额外衰减，让满幅范围以内的输入所对应的计算样本峰值上界低于配置上限。它是对整个滤波器统一调整增益，不是限幅器或响度归一化。"),
                .prose("Headroom gain reports the extra automatic attenuation. Input peak bound reports the resulting worst-case output sample bound for unit-bounded inputs, rather than a measurement of the current music. Common delay is the shared design delay from width and crossfeed; it excludes audio-device buffering and may not include all delay already present in imported IRs. Width error measures the largest width-response approximation error.",
                       "“余量增益”显示额外的自动衰减。“输入峰值上界”显示满幅范围输入对应的最坏输出样本上界，不是当前音乐的实测峰值。“公共延迟”是宽度和交叉馈送设计引入的公共延迟，不含音频设备缓冲，也不一定包含导入 IR 自带的全部延迟。“宽度误差”表示宽度响应的最大逼近误差。"),
                .prose("Warnings describe the active design. While a design is pending or invalid, the panel can show the last valid report dimmed, but that old result cannot be exported or rendered as the current design. Without measured HRTF / BRIR data, the absence-of-externalization warning is expected. Turning automatic headroom off can cause an output clipping warning.",
                       "警告描述当前设计。设计尚未完成或无效时，面板可能以淡色保留上一次有效报告，但不能将旧结果当作当前设计导出或渲染。未提供实测 HRTF／BRIR 时，出现缺少真实外部化依据的警告属于预期行为。关闭自动余量可能出现输出削波警告。")
            ]
        case .configuration:
            return [
                .prose("Open configuration reads a native FieldWeave JSON, resolves relative WAV paths from that JSON’s folder, and lets you review its assets before replacing the current configuration. Invalid or missing dependencies keep the previous configuration active. Successful application stores IR copies under the app’s Application Support folder.",
                       "“打开配置”读取 FieldWeave 原生 JSON，按 JSON 所在目录解析相对 WAV 路径，并在替换当前配置前显示资产确认。依赖无效或缺失时保留原配置。成功应用后，IR 副本保存在应用的 Application Support 目录内。"),
                .prose("Save configuration writes the active settings to JSON. It does not package WAV files; references to the app’s managed assets are still local to this Mac. Valid active configurations are also autosaved under ~/Library/Application Support/FieldWeave/Autosave.json. Pending headphone and matrix drafts are not an autosaved sound configuration.",
                       "“保存配置”将当前生效设置写入 JSON，不打包 WAV 文件；指向应用管理资产的引用仍属于本机。有效生效配置也会自动保存在 ~/Library/Application Support/FieldWeave/Autosave.json。待应用的耳机校正与矩阵草稿不属于自动保存的声音配置。"),
                .prose("Use Export FIR package to transfer or archive a self-contained result. The new package folder contains LL/LR/RL/RR Float32 WAVs, configuration.json, imported WAV copies in assets/, report.json, response.csv and CamillaDSP templates. Open the packaged configuration.json to restore its settings. Keep the whole folder together so relative assets remain available.",
                       "要迁移或归档完整结果，请使用“导出 FIR 包”。新建的包目录包含 LL／LR／RL／RR 四路 Float32 WAV、configuration.json、assets/ 内的导入 WAV 副本、report.json、response.csv 及 CamillaDSP 模板。打开包内的 configuration.json 可恢复设置；请保留整个目录，以便相对路径资产可用。"),
                .prose("The CamillaDSP files are templates. Review and fill in CoreAudio device names yourself and run from the package folder. The offline template uses interleaved F64_LE raw audio, not WAV. Exporting does not install or start a playback system, and the exporter does not overwrite an existing package folder.",
                       "CamillaDSP 文件是模板。需要自行核对并填写 CoreAudio 设备名，并从包目录运行。离线模板使用交错 F64_LE 原始音频，不是 WAV。导出不会安装或启动播放系统，也不会覆盖已有包目录。")
            ]
        case .render:
            return [
                .prose("Wait until the current FIR is ready, choose “Render audio WAV”, select a stereo input WAV, then choose a different output file. The input rate must exactly match the selected FIR rate. Mono or multichannel audio is not accepted for rendering, even though IR import can read individual channels from multichannel WAVs.",
                       "等待当前 FIR 就绪，点击“渲染音频 WAV”，选择双声道输入 WAV，再选择另一个输出文件。输入采样率必须与当前 FIR 完全一致。渲染不接受单声道或多声道音频；IR 导入则可从多声道 WAV 中单独选择声道。"),
                .prose("Rendering applies all four compiled paths and retains the full convolution tail. It writes stereo IEEE Float32 WAV at the input sample rate. The status line reports the output frame count and sample peak. It does not automatically play or import the result into a music library.",
                       "渲染使用编译后的全部四路路径，并保留完整卷积尾部。输出为与输入同采样率的双声道 IEEE Float32 WAV。状态栏会显示输出帧数和样本峰值。应用不会自动播放结果或将其导入音乐资料库。"),
                .prose("If the calculated output peak exceeds full scale, the render is rejected rather than writing a clipped result. Lower Preamp or enable Automatic headroom, wait for a valid design, and render again. Input WAVs are limited to 256 MiB; the output, including its tail, must not exceed 50 million frames.",
                       "若计算出的输出峰值超过满幅，渲染会被拒绝，以免写出削波结果。降低前置增益或开启自动余量，等待设计有效后重新渲染。输入 WAV 不得超过 256 MiB；包含尾部的输出不得超过 5,000 万帧。")
            ]
        case .settings:
            return [
                .prose("Open the gear at the upper right. Language switches between English and Simplified Chinese and is remembered on this Mac. The interface language is independent of the sound configuration and does not alter filters or exported audio.",
                       "点击右上角齿轮打开设置。“语言”可切换 English 与简体中文，并在本机记住选择。界面语言独立于声音配置，不改变滤波器或导出音频。"),
                .prose("The sample-rate picker offers 44.1, 48 and 96 kHz. All imported IRs and rendered audio must match the selected rate. Changing it does not convert existing assets. Convert mismatched files explicitly outside the app before importing; automatic resampling is disabled.",
                       "采样率可选 44.1、48、96 kHz。所有导入 IR 和待渲染音频均须匹配所选采样率。更改此设置不会转换已有资产。请先在应用外明确转换不匹配的文件，再导入；自动重采样已禁用。"),
                .prose("Width FIR length offers 1,025, 2,049 and 4,097 taps. Longer nonconstant width filters can improve response approximation while adding design delay and processing cost. A constant width curve can use a shorter exact filter. The EQ and maximum matrix lengths are separate configuration values, not this picker.",
                       "宽度 FIR 长度可选 1,025、2,049、4,097 抽头。对于非恒定宽度曲线，更长的滤波器可改善响应逼近，同时增加设计延迟与处理量。恒定宽度曲线可以使用更短的精确滤波器。均衡长度和最大矩阵长度是独立的配置值，不由此选项控制。")
            ]
        case .display:
            return [
                .prose("Sound Field is a conceptual view driven by the controls. The colored layers reflect low, mid and high width; the purple center follows Mid pan, height and level. Center height uses the scene's vertical Z-height convention; it does not move the scene origin or the other colored layers. The scene is not a measured room, live spectrum analyzer, source tracker or physical simulation, and it cannot verify a file’s acoustic accuracy.",
                       "“声场”是由控件驱动的概念视图。彩色层反映低、中、高频宽度；紫色中心跟随 Mid 的左右声像、高度和电平。中心高度对应场景的竖直 Z 轴高度，不移动场景原点或其他彩色层。该场景不是实测房间、实时频谱、声源跟踪或物理仿真，也不能证明文件的声学准确性。"),
                .prose("DISPLAY changes only the drawing: Motion, Contours, Grid, Depth, Glow, layer visibility and layer intensity. These controls do not alter the FIR, rendering or exported audio. The scene has a fixed origin; dragging, scrolling or pinching it does not pan or zoom it.",
                       "“显示”仅改变绘制：动画、轮廓、网格、景深、辉光、各层显隐和强度。这些选项不改变 FIR、渲染或导出音频。场景原点固定，对场景拖动、滚动或捏合不会平移或缩放。")
            ]
        case .controls:
            return [
                .prose("Drag a knob’s rim to set its angle, or drag vertically from its center. Hold Shift while dragging for finer adjustment. Double-click a width knob to return to 100%; double-click center height to return to 0° or Mid level to return to 0 dB. A focused knob also supports arrow keys and accessibility adjustment. Left/right center pan is available as a slider in Mid / center on the left.",
                       "拖动旋钮外圈可按角度调节，从中心上下拖动也可调节；按住 Shift 拖动进行细调。双击宽度旋钮恢复 100%；双击中心高度恢复 0°，双击中置信号电平恢复 0 dB。获得焦点的旋钮也支持方向键及辅助功能调整。左右中心声像在左侧“中置信号 / 中心”的滑杆中调节。"),
                .prose("In Frequency view, drag anchors directly; the selected anchor’s frequency and width appear below the graph. Band controls and graph anchors edit the same active width curve.",
                       "在“频率”视图中直接拖动锚点；图下方会显示选中锚点的频率与宽度。频段控件与图中锚点编辑的是同一条生效宽度曲线。"),
                .code("⌘O       " + helpText("Open configuration", "打开配置") + "\n⌘S       " + helpText("Save configuration", "保存配置") + "\n⇧⌘E      " + helpText("Export FIR package", "导出 FIR 包") + "\n⇧⌘R      " + helpText("Render audio WAV", "渲染音频 WAV")),
                .prose("The upper-right question-mark button opens this guide. Select a topic in Contents to jump to it; the guide can also be read by scrolling from beginning to end. Done closes the guide.",
                       "右上角问号按钮打开本说明。点击目录条目可跳到对应章节，也可从头到尾滚动阅读。“完成”关闭说明。")
            ]
        case .limits:
            return [
                .prose("Native audio import accepts RIFF/WAVE PCM at 8, 16, 24 or 32 bits and IEEE float at 32 or 64 bits, including supported WAVE extensible headers. Compressed WAV, MP3, AAC, FLAC and AIFF are not native inputs. WAVs may contain 1–32 channels for IR selection, subject to memory and file limits.",
                       "原生音频导入支持 RIFF／WAVE：8、16、24、32 位 PCM，或 32、64 位 IEEE 浮点，包括所支持的 WAVE extensible 头。压缩 WAV、MP3、AAC、FLAC 和 AIFF 不是原生输入。IR 选择可读取 1–32 声道 WAV，同时受内存及文件大小限制。"),
                .prose("Each imported IR may contain at most 262,143 samples per channel and must match the design rate. A final matrix that exceeds its configured maximum length is accepted only when truncation stays within the configured tail-energy tolerance; otherwise design fails. The standard maximum matrix length is 65,536 taps.",
                       "每个导入 IR 的每声道最多 262,143 个样本，并须匹配设计采样率。最终矩阵超过配置的最大长度时，只有截断损失不超过尾部能量容差才会接受，否则设计失败。标准最大矩阵长度为 65,536 抽头。"),
                .prose("A batch may contain at most 128 WAV files. Folder selection reads immediate, nonhidden WAV children; it does not search nested folders. PEQ JSON is limited to 1 MiB and 64 bands. Files containing nonfinite samples or invalid WAV structure are rejected.",
                       "一次批量导入最多包含 128 个 WAV 文件。选择文件夹时，只读取该目录内直接包含且未隐藏的 WAV，不递归搜索子目录。PEQ JSON 最大 1 MiB、最多 64 个频段。含非有限样本值或 WAV 结构无效的文件会被拒绝。"),
                .prose("Configuration import accepts native version-1 FieldWeave JSON and rejects unknown or unsupported fields. It does not read YAML or SOFA directly. SOFA data must first be explicitly converted into the intended four WAV paths, with its real source coordinates and provenance preserved. A file name or a selected label cannot turn test data into measured data.",
                       "配置导入支持 FieldWeave 原生第 1 版 JSON，并拒绝未知或不支持的字段。不直接读取 YAML 或 SOFA。SOFA 数据须先明确转换成所需的四路 WAV，并保留真实声源坐标及测量来源。文件名或选中的标签不能把测试数据变成实测数据。")
            ]
        case .troubleshooting:
            return [
                .prose("An import is incomplete: inspect every destination, file and channel in the review. Four matrix paths and two headphone FIR paths must be complete. If two destinations point to the same channel, check that this matches the intended data. Rename ambiguous source files or choose the mapping manually.",
                       "导入尚未完成：在确认页检查每个用途、文件和声道。矩阵须齐四路，耳机 FIR 须齐左右耳。若两个用途指向同一声道，请核对数据是否确实如此。文件名含糊时，可重命名来源文件或手动映射。"),
                .prose("“Sample-rate mismatch”: compare the file rate with Settings. Select the intended common rate or convert the file outside the app, then re-import. Changing a rate label or a JSON number is not audio conversion.",
                       "“采样率不匹配”：核对文件采样率与设置。选择所需的共同采样率，或先在应用外转换文件，再重新导入。修改采样率标签或 JSON 数字不等于转换音频。"),
                .prose("A matrix will not apply: complete all four paths, choose the actual IR kind, enter its source, confirm measurement coordinates, and review the crossfeed opt-in. A file that decodes successfully may still fail these checks or the tail-energy check.",
                       "矩阵无法应用：补齐四路，选择真实 IR 类型，填写来源，确认测量坐标，并检查交叉馈送的叠加许可。文件成功解码后，仍可能未通过这些检查或尾部能量检查。"),
                .prose("Export or render is unavailable: wait for the current design and pending imports to finish, dismiss any error, and correct invalid settings. A dimmed previous report does not mean that the current design is valid. Apply headphone or matrix drafts first if you want those changes in the result.",
                       "无法导出或渲染：等待当前设计和待完成导入结束，处理错误并修正无效设置。淡色的旧报告不代表当前设计有效。若希望结果包含耳机校正或矩阵草稿，请先应用。"),
                .prose("No audible change: verify live processing is running, system playback uses BlackHole, and the selected headphone output is connected. Input and output meters should respond. Apps with their own output picker must use System Default or BlackHole. A pending or invalid design keeps the last applied FIR. Already binaural or spatialized audio should use a neutral preset or bypass the HRTF matrix to avoid processing it twice.",
                       "听不到变化：请确认实时处理已运行、系统播放使用 BlackHole、选定耳机已连接，输入输出电平应有响应。自行选择输出的播放器须使用“系统默认”或 BlackHole。参数待编译或无效时继续播放上次生效的 FIR。已经双耳化或空间化的音频应使用中性预设或旁路 HRTF 矩阵，避免重复处理。"),
                .prose("A saved configuration cannot find its files on another Mac: ordinary JSON saving does not bundle assets. Export a portable FIR package from the original Mac and transfer the entire package, then open its configuration.json. If the original assets were already missing, restore them before applying or exporting.",
                       "保存的配置在另一台 Mac 找不到文件：普通 JSON 保存不打包资产。请从原 Mac 导出可移植 FIR 包，传输整个包后打开其中的 configuration.json。如果原资产已经缺失，需要先恢复它们，再应用或导出。")
            ]
        }
    }
}
