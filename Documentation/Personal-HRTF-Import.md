# Personal-HRTF 导入记录

来源私有仓库：`insightlacyrina/Personal-HRTF`，固定提交 `04c6c172a4e80c795656811b0eebd493d56af3e7`。

按照用户要求，GitHub 原始文件统一保存到 `/Users/zhuyongfei/Desktop/Personal-HRTF-Resources/source/`，保留仓库内目录结构。根目录 `download-manifest.json` 记录来源提交、每个文件的 Git blob SHA-1、SHA-256、字节数及 WAV 检查结果。没有下载个人照片、几何重建中间文件、已渲染的定位测试音频或本流程无需读取的 SOFA。

选取的 53 个原始文件包括七套候选的四路单声道 HRIR、四声道合并 WAV、原 CamillaDSP 配置、候选来源清单，以及许可和项目状态文档。所有文件逐项按 Git blob SHA-1 校验；候选清单中对应产品的 SHA-256 和长度也已核对。28 个单声道滤波器均为 48 kHz、IEEE Float32、418 个有限样本。导入没有改变任何滤波器系数，没有再次重采样，也没有独立对耳或方向归一化。

| FieldWeave 候选 | HUTUBS 实测供体 | 原仓库角色 |
|---|---|---|
| c01 | pp35 | 第四轮照片匹配估计基线，本次初始试听配置 |
| c02 | pp29 | 第四轮非个人化频谱 medoid 参考 |
| c03 | pp32 | 候选覆盖代表 |
| c04 | pp49 | 候选覆盖代表 |
| c05 | pp60 | 候选覆盖代表 |
| c06 | pp86 | 候选覆盖代表 |
| c07 | pp13 | 非个人化 DTF/ITD 折中参考 |

这些是**真实供体的双耳测量**，并非本人的直接测量。`measured_hrtf` 描述供体声学来源；每个本地配置的 `provenance` 都明确记载供体编号、来源提交及本人匹配和定位收益尚未验证。选择 c01 只是沿用原有照片匹配基线，并不表示它已经优于其它候选。原仓库当前仍在等待真实本人听测数据；没有可冒充已选个人赢家的结果。

## 原生配置

应用资源位于 `Sources/FieldWeave/Resources/PersonalHRTF/`；可移植、可直接在 FieldWeave 打开的副本位于 `Examples/PersonalHRTF/`。每份包括：

- `c01.json` 至 `c07.json`：48 kHz 原生配置，资产使用同目录下的相对路径。
- `c01/` 至 `c07/`：四路原始 WAV 和候选来源清单。
- `catalog.json`：可供界面枚举的候选编号、供体和配置路径。
- `ATTRIBUTION.txt`、`import-manifest.json`：署名许可与完整导入来源记录。

路径约定严格为输入源到输出耳：`LL = LS_LE.wav`、`LR = LS_RE.wav`、`RL = RS_LE.wav`、`RR = RS_RE.wav`。固定虚拟扬声器为前方左右 ±30°、仰角 0°、距离 1.47 m。SOFA 方位角正方向为左；右扬声器原源坐标 330°在本地表示为 −30°。来源中的名义接收点 ±0.75 m 未作为个人耳距或附加延迟使用。

初始配置采用 100% 立体声宽度、中置声像和 0 dB Mid 增益；额外交叉馈送关闭。原滤波器已包含源转换的共同延迟，本次没有额外对齐耳间起始点。初始配置的宽度处理严格旁路，最终矩阵保持 418 点；修改宽度等参数后，FieldWeave 按自身 FIR 设计加入公共延迟，并显示该值。数字安全设置为 −3 dB 前置增益、开启自动余量、−1 dBFS 峰值上界。原仓库 CamillaDSP 文件中的共同前置衰减**没有重复应用**；最终余量由 FieldWeave 对实际完整矩阵重新计算。

本机系统报告的耳机名称为 `NICEHCK NK1 Ultra`，USB 双声道，当前 48 kHz。原仓库未提供这个型号或这副耳机的实测校正，因此耳机 EQ 保持旁路。不能把 HRTF 供体校正、耳机声压校准或耳机频响校正混为一项。数字余量不代表已测声压或适合用户的音量。

## 复核

`scripts/import-personal-hrtf.py` 接受 GitHub connector `fetch_file` 输出汇总 JSON，核验来源后重建资源及配置；它本身不访问网络或改动系统音频设备。下载清单和原始候选清单可用于独立复核。

本次七套候选均已通过原生 Swift FIR 编译与实际安装 CamillaDSP 的离线四路不对称脉冲验证，最大绝对误差不超过 `3.26e-19`；尾部及输出帧数一并核对。结果保存在 `Personal-HRTF-Native-Validation.json` 和 `Personal-HRTF-Camilla-Validation.json`。这是文件、数值与离线路径验证，不等同于本人听觉效果或物理耳机声压测量。

```sh
.build/debug/fieldweave-cli validate Examples/PersonalHRTF/c01.json
.build/debug/fieldweave-cli build Examples/PersonalHRTF/c01.json /tmp/FieldWeave-Personal-c01
python3 scripts/verify-fir-package.py /tmp/FieldWeave-Personal-c01
```

供体数据及衍生滤波器按 CC BY 4.0 提供。原始署名：Brinkmann 等，2019，JAES，doi:10.17743/jaes.2019.0024；HUTUBS 数据 doi:10.14279/depositonce-8487。完整署名和转换说明保留在资源的候选清单与 `ATTRIBUTION.txt`。
