> 2026-10-29 更新：现已接通真实系统音频链路，原生应用自动处理、七套 Personal-HRTF 导入、37 项测试及退出/重开均已验证。当前证据见 [实时链路验收](LiveAudio-2026-10-29/README.md)。下方保留原先离线版本的历史验证记录。

# FieldWeave 验证记录

验证日期：2026-10-16。本机 Apple M1、Apple Swift 6.4、Apple Command Line Tools。

## 原生视觉

Swift 几何生成 25,842 个粒子、32,680 个线顶点和 41,280 个面顶点。验证确定性、有限坐标和批次结构；Metal 两个真实渲染管线已在 Apple M1 上编译通过。渲染无 WebKit、Canvas、HTTP、浏览器或图片纹理依赖。

## 核心与跨实现验证

14 项原生测试通过（2 suites，0.834 秒）。独立核心测试覆盖：严格旁路、单声道折叠、纯 Side 保留、Mid 等功率声像、中性 Center 旁路、PCHIP 锚点及保形插值、Width FIR/Mid 公共延迟、FFT 对直接卷积、分块卷积及尾部、Crossfeed 延迟、四路非对称映射、PCM8/16/24/32 与 Float WAV、非有限样本拒绝、采样率不匹配、PEQ／矩阵截断审查、保守增益上界、削波拒绝、导出复制资产／重开配置和失败原子性。另检查配置未知字段不能被静默吞掉。

六例 Swift 导出及离线处理与原项目 Python/SciPy 独立比对：Neutral、FieldWeave、Mid-Pan、Crossfeed、Correction、Matrix-Test。四路 Float32 FIR 与原版最大绝对误差 2.05e-8，离线输出最大误差 7.44e-9。严格 Neutral 为完全相等。

六例导出包再用 CamillaDSP 4.1.3 的 **RawFile → File** 后端执行，逐样本对照导出的 Float32 FIR 的独立卷积，最大误差 2.50e-16。没有打开 CoreAudio、麦克风或系统音频设备。

完整逐例误差见 `Native-Verification.json`。这证明离线数值与文件链路；不构成真实耳机定位效果、实时设备路由或实时端到端延迟验证。

## 可重现方式

`./scripts/test.sh` 会使用 Apple 自带 Swift Testing。部分仅安装 CLT 的 SDK 没有 XCTest，脚本为此显式配置系统 Testing 框架和插件路径；不下载测试库。当前 SDK 同时暴露了需要额外插件的 `State` 宏，界面使用稳定 property-wrapper 类型别名 `FWState`，不依赖该宏插件。

`./scripts/build-app.sh` 构建 Release 应用、复制资源、生成代码绘制的应用图标并本地签名。应用部署目标 macOS 14，但本次仅在本机 Apple Silicon 环境实际运行；Intel 编译和其他系统版本尚未实机验证。

## 原生窗口验证范围

Release .app 已实际启动，默认声场、原生三列界面和 Metal 几何已目视检查。通过原生旋钮辅助操作将低频宽度从 120% 改至 122%，侧边滑块与实际余量报告同步更新。通过原生 Open 文件选择器导入 `Mid-Pan.json`，自动保存文件确认实际 pan=0.4、gain_db=-1。

文件选择器关闭后，电脑操作工具的窗口检查连接发生超时。对应用采样确认主线程仍在正常事件循环并持续执行 Metal 渲染；未发现应用主线程阻塞。此后没有继续声称已完成原生导出／渲染文件选择器的点击验证；这些功能的共享 Swift 核心通过原生命令行、完整文件读写和六例 CamillaDSP 后端验证。具体边界见 `Native-UI-Verification.json`。

应用签名检查 `codesign --verify --deep --strict` 通过。
