# FieldWeave：入耳式与头戴式耳机是否应采用不同策略

研究日期：2026-10-29（America/Los_Angeles）。依据为当前桌面工程源码、随附 HRTF 来源记录，以及下列一手研究。本文是研究与工程建议；未修改 DSP、预设、系统路由或播放音量，未进行真人试听或耳机声学测量。

## 结论

**应区分耳机档案、校正条件和校准流程，同时共用声场处理核心。** 不建议直接做成“入耳模式加重 HRTF／crossfeed，头戴模式减弱”的两套固定音效。

决定最终效果的关键是：具体耳机在具体佩戴条件下的耳机到耳朵传递函数（HpTF）、HRTF 与校正数据是否采用兼容的测量参考点、内容是否已经双耳化，以及用户的实际试听结果。耳机形态适合用来指导校准步骤，不能单独决定正确的空间参数。

对本项目，优先顺序是：

1. 明确区分输出耳校正与创作音色 EQ，并处理当前左右耳不同 FIR 的施加顺序。
2. 将耳机档案与声场预设分离，切换声音风格时保留设备校正。
3. 在同一渲染器中，按耳机与佩戴条件保存校正、HRTF 试听排序及偏好参数。
4. 用实际重复佩戴与受控试听，决定是否需要不同默认值。

## 1. 证据支持什么

### 1.1 两类耳机都需要考虑播放传递函数

入耳式绕过了外部声场到耳廓的自然传播；头戴式虽然与耳廓产生声学相互作用，也不等于真实外部声源从不同方向到达时的滤波。不能认为“头戴式已经保留耳廓，所以不需要 HRTF”，也不能认为“入耳式只要补强耳廓增益就能外部化”。早期真人测量已将耳机到耳朵的传递函数视为双耳重放的重要变量；实验包含 14 款耳机、40 名受试者。[Møller 等，1995](https://aes.org/publications/elibrary/elibrary-page/?id=7954)

**工程推论：** 两类耳机都应经过同一套“渲染目标 + 播放校正”逻辑；未测量时，形态标签不能代替校正。

### 1.2 入耳式重点是耳塞、密封、插入位置及个体耳道

Samsung 的原始研究对 20 只真人耳道几何、每耳 5 个插入深度做有限元仿真，说明平均耳模拟器不能完整代表个体鼓膜处响应，且高频不确定性明显增大。这是仿真与模型比较，不能把其中误差范围直接当作用户这副耳机的实测误差。[Bezzola，2023](https://sra.samsung.com/publications/in-ear-headphones-on-ear-canal-simulator-vs-real-human-ear-geometries-quantifying-the-differences-with-simulations/)

**工程推论：** 入耳档案应记录耳塞型号／尺寸和约定佩戴状态；密封或插入改变后先复核佩戴。没有可靠个体测量时，不按单次尖峰／深谷生成激进窄带高频补偿，更不能用统一低频提升掩盖佩戴差异。

### 1.3 头戴式也不能只按型号一次校正

原始研究指出，佩戴位置、头耳尺寸、头梁和耳垫材料都会改变声学耦合；其个体化校正实验支持关注实际耦合，而非只依赖通用目标。[Celestinos 等，2019](https://aes.org/publications/elibrary/elibrary-page/?id=20605)

**工程推论：** 头戴档案应记录耳垫、位置、开放／封闭设计及 ANC／通透等工作状态；复核戴眼镜等可能改变接触条件的情况。开放／封闭是独立描述项，不应被“头戴式”一个标签吞掉。具体影响仍需该型号实测。

### 1.4 内容类型也是策略分支

Engel 等的正式期刊研究做了三次听测，每次超过 20 人，比较七种目标响应、两种耳机和两种重放带宽。其结果支持：空间内容与普通立体声内容可能偏好不同目标，且个体化校正时差异更强。这不能推广为所有耳机、所有双耳内容都强制采用某条目标曲线。[Engel 等，2022](https://aes.org/publications/elibrary/elibrary-page/?id=21564)

**工程推论：** 普通立体声偏好 EQ 与 HRTF／BRIR 重放补偿应分别定义。采用全 HRTF、DTF、不同参考点或已经补偿过的双耳素材时，不能不加区分地重复叠加“耳增益”。此处的“平坦”必须附测量参考点与渲染约定，不等于把任何耳模拟器原始曲线拉成水平直线。

### 1.5 外部化还有两类耳机共用的改进方向

有控制实验显示，虚拟声源随头运动保持世界坐标稳定，有助于外部化。它支持未来研究头部跟踪，不能证明某一种耳机形态应使用更强 HRTF。[Brimijoin 等，2013](https://journals.plos.org/plosone/article?id=10.1371/journal.pone.0083068)

FieldWeave 当前只有固定方向矩阵，没有头部跟踪。增加反射／BRIR 或动态渲染应作为独立功能研究，并分别评估外部化、音色与清晰度。

## 2. 应分别管理与应共用的内容

下表是依据上面证据提出的产品设计建议，不是已经验证的两类最佳参数。

| 项目 | 入耳式重点 | 头戴式重点 | FieldWeave 建议 |
|---|---|---|---|
| 档案身份 | 具体耳机 + 耳塞／尺寸 + 佩戴状态 | 具体耳机 + 耳垫 + 位置／工作状态 | 每副耳机独立；类型只是元数据 |
| 佩戴复核 | 密封、左右一致性、插入位置 | 重戴位置、耳垫接触、眼镜等条件 | 校准步骤可不同，判定依据为实际响应／试听 |
| EQ | 关注个体耳道与佩戴不确定性 | 关注耳廓耦合与重戴差异 | 共用 PEQ/FIR 引擎；保存来源、参考点、目标与有效条件 |
| HRTF/BRIR | 需要兼容的播放补偿与本人试听 | 同样需要兼容补偿与本人试听 | 可共用候选库；每个档案保存试听排序 |
| Width/Mid | 由内容与偏好决定 | 由内容与偏好决定 | 不因类型自动增加宽度或移动中心 |
| Crossfeed | 普通硬左右立体声可作为偏好选项 | 同样可作为偏好选项 | 与 HRTF/BRIR 同用维持默认关闭；类型不足以决定强度 |
| 音量 | 灵敏度与实际声压需单独处理 | 同样如此 | 保留双耳共用数字增益，但不宣称跨耳机等声压 |

建议两类的首次比较均从 Width 100%、Mid 居中／0 dB、额外 crossfeed 关闭开始，建立可解释的基线。这是实验控制选择，不是“最佳听感”结论。没有可信校正时，EQ 继续旁路并明确标注未校准。

## 3. 当前项目核查

### 3.1 已具备的能力和缺口

| 当前事实 | 源码／记录 | 意义 |
|---|---|---|
| 耳机参数只有 mode、peq、fir、provenance | [Configuration.swift:68](/Users/zhuyongfei/Desktop/FieldWeave/Sources/FieldWeaveCore/Configuration.swift:68) | 没有形态、耳塞／耳垫、测量目标与佩戴条件 |
| PEQ 双耳相同；FIR 可以左右不同 | [Compiler.swift:44](/Users/zhuyongfei/Desktop/FieldWeave/Sources/FieldWeaveCore/Compiler.swift:44) | 不应把两者当作相同的空间顺序问题 |
| 四个声音预设新建配置，只保留采样率与设计长度 | [FieldStore.swift:91](/Users/zhuyongfei/Desktop/FieldWeave/Sources/FieldWeave/FieldStore.swift:91) | 切风格会移除原耳机校正和 HRTF；建议分层保存 |
| 常规切换 HRTF 候选保留耳机校正，并关闭额外 crossfeed | [FieldStore+LiveAudio.swift:35](/Users/zhuyongfei/Desktop/FieldWeave/Sources/FieldWeave/FieldStore+LiveAudio.swift:35) | 可以保留这个独立比较方向；resetSound 另有整体重置语义 |
| 路由保存输出 UID，没有物理耳机身份 | [AudioDevices.swift:102](/Users/zhuyongfei/Desktop/FieldWeave/Sources/FieldWeaveAudio/AudioDevices.swift:102) | 同一 DAC 后更换被动耳机，不能只靠 UID 判断档案 |
| 单一 Autosave.json 保存声音状态 | [FieldStore.swift:41](/Users/zhuyongfei/Desktop/FieldWeave/Sources/FieldWeave/FieldStore.swift:41) | 尚无按耳机自动恢复的档案系统 |
| 响度模型与反馈使用数字信号，不测耳内声压 | [LoudnessReference.swift:3](/Users/zhuyongfei/Desktop/FieldWeave/Sources/FieldWeaveCore/LoudnessReference.swift:3)、[LoudnessBalance.swift:42](/Users/zhuyongfei/Desktop/FieldWeave/Sources/FieldWeaveAudio/LoudnessBalance.swift:42) | 数字等电平不能作为跨耳机等声压证据 |

随附七套 HRTF 是 HUTUBS 供体数据，本人匹配与定位收益尚未验证；NK1 Ultra 缺少实测耳机校正，当前为旁路。[现有导入记录:19](/Users/zhuyongfei/Desktop/FieldWeave/Documentation/Personal-HRTF-Import.md:19)、[导入记录:34](/Users/zhuyongfei/Desktop/FieldWeave/Documentation/Personal-HRTF-Import.md:34)

HUTUBS 同时提供的 HpIR 是特定受试者佩戴 HD800S／HD650 的数据，不能挪作 NK1 Ultra 或其它耳机的补偿。[HUTUBS 官方文档，2019](https://depositonce.tu-berlin.de/bitstreams/8f6e24a2-1c75-4f84-a50f-74a34bb480c7/download)

### 3.2 优先问题：输出耳校正的位置

当前代码先构造 Q，再左乘 Width、Center、HRTF/BRIR 和 Crossfeed。忽略公共增益，实际总矩阵为：

`M_current = X · E · C · W · Q`

其中 Q 是耳机校正，E 是双耳矩阵，矩阵下标为“输出耳 × 输入源”。依据：[Compiler.swift:56](/Users/zhuyongfei/Desktop/FieldWeave/Sources/FieldWeaveCore/Compiler.swift:56)、[Compiler.swift:64](/Users/zhuyongfei/Desktop/FieldWeave/Sources/FieldWeaveCore/Compiler.swift:64)、[Compiler.swift:69](/Users/zhuyongfei/Desktop/FieldWeave/Sources/FieldWeaveCore/Compiler.swift:69)。

如果 Q 用于补偿最终耳机的每耳播放传递函数，合理目标应为：

`M_playback = Q · X · E · C · W`

也就是所有空间混音完成后，再分别施加左耳和右耳补偿；共同数字增益及峰值保护随后处理。原因是需要让实际播放传递函数 H 与校正 Q 在兼容的声学参考点满足 `H · Q ≈ I`。现实中宜用有限带宽、平滑／正则化的近似，不能保证精确逆。

简单数值反例已经用独立矩阵运算核对：

```text
Q = [[2, 0], [0, 1]]
E = [[1, 0.2], [0.3, 1]]

当前 E·Q = [[2, 0.2], [0.6, 1]]
每耳 Q·E = [[2, 0.4], [0.3, 1]]
```

前者对左输入源送到右耳的路径也应用左耳校正；后者对所有到达右耳的路径使用右耳校正。共享校正 `Q=qI` 可以与线性时不变矩阵交换，所以现有双耳相同 PEQ 没有这个差别；**左右不同 FIR 配合空间混音时才暴露问题**。当前默认 EQ 旁路也不受影响。这是源码和代数结论，不是真人声学测量。

未来修正应区分“源音色 EQ”和“播放耳校正”，并通过配置版本或明确迁移保留旧配置效果，避免无提示地改变已有声音。当前严格字段校验也意味着不能直接往 v1 JSON 添加建议字段。[Configuration.swift:27](/Users/zhuyongfei/Desktop/FieldWeave/Sources/FieldWeaveCore/Configuration.swift:27)

### 3.3 测量参考点是后续校准的必要元数据

HRTF 与 HpTF 必须采用兼容参考点；耳道内驻波与测量位置变化会影响合成。堵耳道入口测量另有声学耦合假设，不能只因文件可导入就认定可直接配套。[Gunnarsson 与 Smailagić，2023，Two-Microphone Array for Binaural Measurements](https://uu.diva-portal.org/smash/get/diva2%3A1846126/FULLTEXT01.pdf)

更早的直接实验在 12 人身上分解自由场到耳道入口、压力分配和沿耳道传递，发现这些部分均有个体差异，而堵塞入口已包含完整空间信息。这进一步说明，测量参考点与耳道耦合应明确记录，不能用“图上是否平直”替代。[Hammershøi 与 Møller，1996](https://pubmed.ncbi.nlm.nih.gov/8675836/)

当前项目保存了来源与声源坐标，但未结构化保存耳道参考点、全 HRTF／方向性滤波及补偿目标。没有逐一核实来源前，不应宣称任意导入 EQ 与七套 HRTF 已经声学匹配。公共四路归一化也不等于耳机校准。

## 4. 推荐的产品策略

采用“内容处理方式 × 耳机档案”两层选择，声音风格另外保存。

- **耳机档案**：人工确认耳机身份、IEM／包耳／压耳／其它形态、开放／封闭／通气设计、耳塞／耳垫和工作状态；保存校正文件、测量者／夹具／参考点／目标、可信范围与是否个体实测。输出 UID 仅用于路由关联，可有多个档案共用 UID。
- **声音风格**：Width、Mid、crossfeed 等偏好；切换风格保留已选耳机校正。应提供显式“全部重置”，承担现有整体预设重置的用途。
- **HRTF 结果**：可共用一个候选库，但分别记录每个耳机档案下的试听排序。某一耳机上选中的供体，不直接标成其它耳机也验证有效的“个人 HRTF”。
- **普通立体声**：可选择保持立体声，或通过 HRTF/BRIR 模拟虚拟扬声器；crossfeed 作为单独偏好。不能仅用 IEM 标签触发固定加重。
- **已双耳化／已空间化内容**：默认保持中性宽度与中心，旁路新增 HRTF 和 crossfeed，避免再次渲染；耳机播放补偿仅在来源兼容时应用。这条规则对两类耳机相同。
- **未知耳机或无可信测量**：允许无校正试听，清楚显示状态；不生成看似精确的型号 EQ，不把听感偏好标为实测补偿。

这些是后续实现建议，当前应用尚未具备上述完整档案与自动分支。

## 5. 如何验证“分开策略”值得实施

本轮结论支持架构方向，尚不能给出这位用户在两副具体耳机上的最佳参数。建议先在每副耳机内部做比较，再讨论跨耳机一致性：

1. 先确认具体耳机和工作状态；固定佩戴条件与系统其它空间音效。不能把操作系统报告的输出名称直接当成实际被动耳机型号。
2. 每副耳机比较三个条件：中性／旁路基线、同一通用空间设置、该档案单独校准的设置。先确定播放校正，再筛 HRTF，最后微调宽度／crossfeed，避免同时改变全部变量。
3. 使用相同素材、隐藏候选标签并随机顺序；盲化限于同一副耳机内的软件条件，耳机形态本身无法真正盲化。先匹配音量；当前反馈需等待稳定。严谨试验宜另做固定增益的离线测试材料或实验控制，不能假定现有界面已有冻结反馈功能。
4. 分别记录音色自然度、中心稳定、外部化、左右区分及不适感。“更宽／更响”不直接等于外部化更准确。
5. 可先采用每副耳机至少 3 次摘戴、2 次独立试听作为项目探索方案；这是建议的起步规模，不是文献规定，也不足以证明人群层面优势。
6. 只有在多次佩戴与独立试听中仍有稳定收益，才把不同参数保存为该档案默认。若收益主要来自耳机 EQ，就保留共同空间参数。

当前随附矩阵只覆盖前方 ±30° 两个虚拟扬声器；它不能支撑完整前后／仰角定位测试。完整定位与头部跟踪需额外方向数据及动态渲染器。跨耳机相同数字 RMS 也不足以建立相同耳内声压，未做声学标定时应限制为每副耳机内部的偏好比较。

## 6. 决策与实施次序

| 次序 | 建议 | 完成判据 |
|---|---|---|
| 第一阶段 | 定义输出耳校正与源 EQ，迁移左右 FIR 顺序；分离档案与风格 | 非对称四路矩阵与左右不同校正验证通过；旧配置重开语义明确；切风格不丢设备校正 |
| 第二阶段 | 保存具体耳机、佩戴和测量元数据；提供内容处理选择 | 同一 DAC 的两副耳机可手选并分别恢复；未知／未校准状态可见；不重复空间化 |
| 第三阶段 | 做两类耳机内受控试听并保存结果 | 重复摘戴、独立会话仍支持差异参数；偏好与测量结论分开 |
| 后续研究 | 个体实测 HpTF、兼容 BRIR 与头部跟踪 | 有新增测量、方向数据和动态渲染验证，再宣称相应能力 |

**采用的方向：共用渲染器，按具体耳机与佩戴保存校正；以内容类型和试听证据决定空间策略。** 现阶段没有足够证据为所有入耳式与所有头戴式分别指定一套固定 EQ、宽度、crossfeed 或 HRTF 强度。
