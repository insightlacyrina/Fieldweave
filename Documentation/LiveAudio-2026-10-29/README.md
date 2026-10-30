# FieldWeave 实时链路验收 · 2026-10-29

最终应用：`/Users/zhuyongfei/Desktop/FieldWeave/dist/FieldWeave.app`，版本 0.3.0，本机 ad-hoc 签名。已通过签名校验。应用已重开并保持运行，打开时自动处理已启用。

音频链路：系统默认媒体输出 → BlackHole 2ch → CamillaDSP 4.1.3 执行 FieldWeave 完整四路 FIR → NICEHCK NK1 Ultra USB 输出。IR、捕获与输出以 48 kHz 运行。使用独立时钟调整和异步采样率转换；这不是 bit-perfect 播放。

Personal-HRTF 原文件共 53 个，保存在桌面的 `Personal-HRTF-Resources`，固定 GitHub 提交 `04c6c172a4e80c795656811b0eebd493d56af3e7`。七套四路径 HRIR 已导入，本次生效 c01/pp35，保留当前低/中/高频宽度 125%/140%/165%。四路矩阵已启用，耳机 EQ 旁路，额外交叉馈送关闭，自动余量开启。当前完整 FIR 为 2466 点，公共宽度设计延迟 21.33 ms，不含设备缓冲和源 HRIR 固有延迟。

## 已验证

- 37 项 Swift Testing 测试全部通过，包含所有七套内置候选实际导入和 CoreAudio 路由选择约束，详见 `Tests.log`。
- 七套实际 CamillaDSP 离线四路不对称脉冲与原生导出一致，最大绝对误差 3.26e-19，详见上级目录两份 Personal-HRTF 验证 JSON。
- 初次实时测试发现 BlackHole 原输入/输出均静音。运行时现先记录原静音状态，再解除虚拟设备静音；停止及恢复时还原，物理耳机音量不改动。
- 自动化低电平播放验证中捕获和播放均非零，削波计数为 0；停止后恢复媒体输出和 BlackHole 原静音状态，见 `CLI-Smoke.json`、`Raw-Meters.json`、`CLI-Support/LiveAudio.log`。
- 已实际退出原生应用，确认媒体输出恢复为 NK1 Ultra，CamillaDSP 无残留；无参数重新打开后，保存的 c01 矩阵、现有宽度设置和自动处理恢复。
- 重开后再次播放低电平探测音，状态 Running，四路 HRTF 已生效，捕获峰值 -66.51602 dBFS、处理输出峰值 -91.01322 dBFS、削波样本 0，见 `App-Verification.json` 和 `App-Raw-Meters.json`。
- 实时更新包限制为当前/进行中包与三个最近完整缓存，避免持续调参无限积累导出文件。

## 使用与证据范围

应用保持运行时，直接播放 Apple Music、浏览器及使用系统默认输出的音频即可。自行选择输出的播放器应使用系统默认或 BlackHole。退出应用会恢复普通播放；下次打开自动接通。

这些是数字处理、设备及真实音频流证据，不代表实测耳机声压、本人听觉评价或定位改善。供体双耳确为测量，但未验证与本人匹配；原仓库未提供 NK1 Ultra 的实测 EQ，因此没有编造耳机校正。初始配置备份保存在 `Before-Activation/Autosave.json`。
