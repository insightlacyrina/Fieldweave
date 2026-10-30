# 分发版本

FieldWeave 0.4.0（build 4）面向 Apple Silicon，最低 macOS 14。DMG 内包含完整应用、拖入 Applications 的入口与安装说明；应用包含原生 Swift DSP、Metal 着色器及 HRTF 数据资源。

实时系统音频需要另外安装 BlackHole 2ch 和 CamillaDSP；本版本默认检查 `/usr/local/bin/camilladsp`。DMG 不安装音频驱动、不捆绑这些外部程序，也不修改系统音量。虚拟音频捕获需要用户允许 macOS 麦克风权限。

这是本地 ad-hoc 签名构建，未经过 Apple Developer ID 签名或公证。发行文件附 SHA256 校验值。HUTUBS 衍生数据的 CC BY 4.0 署名随应用资源及 DMG 提供；供体测量不代表本人定位效果已验证。

仓库包含源码、示例、数据来源与可公开的验证摘要。本机自动配置、设备状态快照、临时播放目录及大批生成的验证包保留在本地，不进入版本控制；历史验证文档中指向这些文件的链接仅适用于原开发目录。
