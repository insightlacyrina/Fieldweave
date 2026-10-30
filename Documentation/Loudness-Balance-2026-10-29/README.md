# 常驻音量平衡 · 0.3.1 · 2026-10-29

修复了“预设、HRTF 和手动处理参数改变后，保守 FIR 峰值衰减导致播放音量差异明显”的问题。应用的实时播放链路现在始终执行音量平衡，界面没有新增开关或旋钮。

## 处理方式

完整四路 FIR → 参考校准 → 双声道共同增益微调 → 末端样本峰值保护。

- 每次参数编译完成后，按完整 FIR（含耳机 EQ、宽度、Mid、HRTF、交叉馈送、前级和自动余量）估算 K 加权粉红声的输出能量；参考声道相关度为 0.5。不同预设、IR 原始电平和 FIR 自动衰减使用同一个校准方法，没有预设专用音量表。
- 播放目标为输入电平加“用户前级增益 − 6 dB”。保留统一余量，前级控制仍会改变实际输出音量。左右耳只用一个补偿增益，保留声像和左右差异；声音处理的相对比例不变。
- 根据实际捕获／输出的双声道 RMS 缓慢修正，500 ms 增益斜坡，增益增加至多 1 dB/s、减少至多 6 dB/s。微调限制为 −24 至 +12 dB，静态校准限制为 −60 至 +36 dB。输入低于 −70 dBFS、输出低于 −90 dBFS、静音或已消除的内容不追增益。
- 更新时暂停反馈，先移除旧的正向微调；保留旧的负向微调直到新 FIR 确认生效，然后平滑恢复新基准。参数导出可并行，增益／FIR 提交按序完成。等待稳定窗口后重新测量，避免旧任务和旧电平用于新滤波器。
- 输出样本上限为 −1 dBFS，或配置中更低的上限。极端信号触限时硬峰值保护优先于音量匹配，可能改变瞬态；不是过采样真峰值限幅。内容差异与参数极限仍可能影响收敛与主观响度。

这项改动针对应用的实时播放。原有导出 FIR、离线 WAV 渲染及 FIR 报告继续使用相同的基础 FIR 和保守静态峰值保证；它们不包含实时电平反馈。现有“自动余量”控制描述基础 FIR，关闭它不会关闭实时输出末端保护。

## 验证证据

- `Tests.log`：43 项测试通过，包含参考增益、采样率、静音／掉音、声道能量合并、峰值优先、反馈收敛、前级语义、实际预设及七套候选导入。
- `Offline-Verification.json`：直接用应用生成的播放处理链，经真实 CamillaDSP 4.1.3 RawFile 运行。四个预设、七套 HRTF、三组手动宽度／Mid／交叉馈送／EQ／前级组合共 14 组，相关粉红声 K 加权增益最大误差 0.000562 dB；满幅随机瞬态和反相信号均未超过配置上限；精确静音输出仍为零。此数字是指定参考信号的校准误差，不代表任意音乐的主观响度误差。
- `Below-Gate-Smoke.json`：首次硬件探测音低于反馈门限，完成了 14 组连续热切换、真实流量和路由恢复验证，设备削波计数为 0；因门限关闭，不用它证明动态反馈收敛。
- `Live-Verification.json`、`Live-Summary.json`：实际 BlackHole 2ch → CamillaDSP → NICEHCK NK1 Ultra 链路，14 组连续热切换的电平与动态补偿记录。每组播放 12 秒，取最后两秒比较输入／输出 RMS 与目标，最大绝对误差 0.198 dB，各组误差跨度 0.369 dB。捕获峰值 −48.44 dBFS、输出峰值 −56.29 dBFS、设备削波计数 0，退出时恢复到原 NK1 Ultra 路由。`Before/CoreAudio.json` 与 `After-Test-CoreAudio.json` 的设备音量／静音状态一致。
- `Build.log`：本机 Release 构建及 ad-hoc 签名。交付应用为桌面工程内 `dist/FieldWeave.app`，版本 0.3.1。

`Before/` 保存原自动配置、音频路由设置和设备状态；原应用包另存 `.build/FieldWeave-before-loudness.app`。硬件测试使用独立支持目录，结束时恢复原路由；不改物理设备音量。主应用恢复原来的自动保存配置。

用户完成 macOS 麦克风授权后，新版原生应用已接通并保持运行。`Native-App-Verification.json` 与 `Native-App-Raw-Meters.json` 记录了实际应用管理的引擎连续 8 次为 Running，低电平探测音的捕获／输出峰值分别为 −71.11／−85.85 dBFS，设备削波计数为 0。已从实际引擎配置确认参考校准、500 ms 平滑微调、−1 dBFS 末端保护三个阶段全部加载；探测前后设备音量及路由状态相同。应用界面显示“已就绪 · 等待音频”，系统播放链路保持 BlackHole → CamillaDSP → NK1 Ultra。该安静探测仅证明原生应用的真实流量；动态收敛误差仍以此前 14 组 CLI 硬件记录为准。`Native-App-Permission.log` 保留此次本地签名变化引起的系统重新授权记录。

## 重现离线验证

```sh
FIELDWEAVE_BALANCE_EVIDENCE=/tmp/FieldWeave-Balance ./scripts/test.sh
python3 scripts/verify-loudness.py /tmp/FieldWeave-Balance
```

Python 验证脚本需要 numpy。`scripts/verify-live-balance.py` 是明确使用本机音频设备的验证脚本，应先退出主应用，以免两个控制器同时占用链路；它使用限时 CLI 并负责恢复路由。CLI `--sequence` 支持在同一个控制器内连续热加载导出包，报告每次实际 RMS 增益与补偿值。

实现参考：[CamillaDSP 音量滤波器与样本限幅](https://github.com/HEnquist/camilladsp#volume)、[实时电平与平滑音量控制](https://github.com/HEnquist/camilladsp/blob/master/websocket.md)、[K 加权系数方程](https://github.com/jiixyj/libebur128/blob/master/ebur128/ebur128.c)。
