# 补充核对：并行原生入缝动效分支

设计交付末次远端盘点新增发现 `codex/arrival-none-magnet-native-20261028`。初始设计盘点未包含此分支，不能据此认定磁力吸引仍只有浏览器概念稿。

本次只读审查固定于 **`d552a7388af3890bf693bb3fb24f4b8fc5bc12e7`**；未修改该分支、正式工程、App、PR或本轮影片。它是必须继承审查的并行工程工作，不是本设计已自动集成的原生实现。

## 1. 实际祖先关系

本地先确认对象不存在，待主负责人完成fetch后读取Git对象。实际线性关系为：

| 提交 | 父提交 | 内容 |
| --- | --- | --- |
| `c38678db6da8c7703a0703eca867b875da6f2951` | `1920e0562db893a3292af89a89270a26ddb46a5f` | 原生none／magnet、可中断表现、保守源坐标 |
| `e76d79d4a99f706e6407bb58cb28a6ec4f36c354` | `c38678db6da8c7703a0703eca867b875da6f2951` | 捕获静默时钟与拓扑准入说明 |
| `e23dc47bfbd00534f30328ea5318ca0710917db2` | `e76d79d4a99f706e6407bb58cb28a6ec4f36c354` | Swift5.10测试夹具类型修正 |
| `d552a7388af3890bf693bb3fb24f4b8fc5bc12e7` | `e23dc47bfbd00534f30328ea5318ca0710917db2` | 使用Swift导入的CGImage.typeID保持原身份断言 |

与正式`1920e056`的merge-base就是`1920e056`。与预测入口`5d6a683652d255af8c1d3e0d9533587fcc27a24d`的merge-base也为`1920e056`；两条新增分支互不为祖先。不能认为合入其中一条就自然包含另一条，也不能重复合入正式Beta历史。

本分支的设计依据记录为PR#10的`0b73291652c11f5cb7b6e2792d001eb3340c988b`，尚未引用本轮统一视觉规格；出现以下差异是正常的并行来源差异，不能以整文件覆盖解决。

## 2. 已存在的原生能力，应直接继承

固定来源：[d552a738目录](https://github.com/haohongfei2001-png/Riftlet/tree/d552a7388af3890bf693bb3fb24f4b8fc5bc12e7)。相对正式基线共31个修改／新增路径。原有产品文件仅四个被改：`RiftletMain.swift`、`CaptureService.swift`、`RiftPanelController.swift`、`ThumbnailCache.swift`。

| 文件／组件 | 已实现责任 | 后续设计实施不应重复建设 |
| --- | --- | --- |
| `Sources/RiftletApp/ArrivalCaptureBridge.swift` | 单个串行可取消元数据读取、epoch、拓扑变化取消、source准入门 | 另建捕获或动画协调器 |
| `Sources/RiftletApp/ArrivalMotionPreferences.swift` | 单独JSON偏好、缺失与显式none区分、原子保存、坏／未来版本不覆盖 | 再造偏好存储或改SQLite |
| `Sources/RiftletCapture/ScreenshotSourceGeometry.swift` | 原系统文件签名／标记／有限四数字坐标验证，显示器和像素比例转换 | 猜鼠标位置、猜窗口、另建宽松源坐标解释 |
| `Sources/RiftletUI/ArrivalMotionMode.swift` | 闭集none／magnet、系统Reduce Motion覆盖、到达边界类型 | 加第三种或已淘汰特效 |
| `Sources/RiftletUI/MagnetMotionPlan.swift` | 可调几何／时钟数学模型、单sprite路径、精确finalFrame与edge、显式CA采样 | 根据网页临时再写完整轨迹系统 |
| `Sources/RiftletUI/MagnetFlightPresenter.swift` | 非激活透明NSPanel、共享CGImage、固定mask、cleanup/watchdog、原资产generation | 新浮窗生命周期或第二份资产 |
| `Sources/RiftletUI/ArrivalMotionSettingsController.swift` | 原生两选项窗口与共用运动预览 | 另造第二个设置或预览引擎 |
| `CaptureService.onImported`与Main接线 | durable import之后通知并立即发布，不等待元数据或整批扫描 | 延后收录到动画准备完成 |
| `RiftPanelController`与`ThumbnailCache`增量 | 原行、AX和输入岛立即建立；编号保留；首图解码时决定是否播放；同一CGImage交接；失效取消 | 将装饰变成输入面板，或绕过原点击保护 |

另有10个测试路径、两份workflow接线、三份实施／验收文档、三份证据记录、只读源坐标probe和精确增量审计。这里记录其存在与源码职责，**不把静态阅读写成测试通过**。

## 3. 当前真实源坐标准入仍关闭

`ArrivalSourceProfile.admittedOSBuilds`在该精确提交中是空集合。普通收录即使保存magnet也走静态显示；原生设置预览能工作，并不等于普通系统截图已获得可信源矩形。

`--arrival-metadata-candidate`只为本地明确的源坐标试验开放候选解释，不改变ApplicationMode、上传开始／完成策略、数据库或安全重试权限。本设计原型及影片不能替代这个准入门。

实际工程还有350ms到达候选截止、原firstSeen超过2秒静态降级、两秒拓扑静默启发式、450ms内连续捕获静态收束、最多一个source副本／pending candidate、768px解码上限和32百万backing像素overlay上限。它们是工程边界，不是实测性能结果；后续调视觉不能顺手删除。

坐标校验来自原始文件，不从丢失xattr的私有副本推断；跨屏、镜像、未知单位、阴影padding不符、源矩形过期或晚到均静态。该分支文档明确承认：当前拓扑与像素自洽仍不能证明捕获时拓扑，两秒静默也不能解决系统浮动缩略图和延迟落盘跨拓扑变化的歧义。不能因本轮视觉好看而批量放开OS-build列表。

## 4. 与本轮统一设计的具体差异

下表是实施时应做的最小差异，不是对并行分支的覆盖授权。本设计仍是推荐稿；最终视觉实施先由正式负责人审阅并保留已验证行为。

| 项目 | d552a738实际实现 | 本轮推荐 | 处理边界 |
| --- | --- | --- | --- |
| 动效总时长 | 440ms =100/70/270 | 560ms =123/101/260/76 | 440明确标为工程候选，未获艺术定稿；在既有参数／plan层调整，不另造Presenter |
| 起始副本 | 不大于实际源；最多200×130 | 最多240×150 | 保留“不放大真实小源、不移动源来制造路径”的工程约束 |
| 微颤 | 1.3pt×sin(3πu)×sin²(πu) | 上限1.2pt的阻尼定向微颤 | 用既有参数调整；不引入随机、旋转或反弹 |
| 路径 | 单sprite连续到最终部分遮挡frame；`28u⁶−48u⁷+21u⁸`，两端速度／加速度为0 | 加速穿过遮挡面后落位的四段空间因果 | 两者轨迹拓扑不同，不能只改duration就宣称已还原；复用同一CGImage、固定mask、实际targetFrame和中断owner |
| 入缝none范围 | 同时使press、swallow、rebirth零位移 | none只管入缝；快吞噬独立 | 本轮用户明确要求分离；从`effectiveArrivalMode`解耦业务后的视觉时长，Reduce Motion仍全局覆盖 |
| 补位 | 两模式均同步、0ms | 160ms视觉补位 | 原生刻意取消移动输入窗以避免180ms拒点与错点；不可为视觉恢复旧危险输入策略。复用原身份／原窗口保护后再实现表现层补位 |
| 按压 | magnet沿原配置80ms/2.5pt；none0位移 | 60ms到1.5pt，再80ms复位 | 仅视觉参数，不改原点击授权或延长ACK |
| 裂缝与尺寸 | 原72×56、25%遮挡、0.7pt线、60pt行距 | 同fit/遮挡/行距，Retina0.5pt及新空间定位／编号8pt | 从RiftLayout当前实际global frame取终点；不硬编码影片x=1426/y=230 |
| 设置 | 独立“截图动效…”原生窗口 | 统一设置里的“截图入缝”，两选项及清楚预览 | 复用其保存／失败恢复／预览；不要再加一份设置文件 |
| 动效中编号 | 已立即保留编号、AX owner及输入岛，图像本身暂隐 | 编号从assetReady即显即点 | 这一点一致，应保留；影片01已据主审修正为同一语义 |

原生440ms单sprite的连续运动有明确工程理由，560ms四段则是本轮艺术推荐；双方均非已批准物理品质结论。后续Codex须对照本轮可交互原型、真实比例帧和本文件列出的差异，复用已存在的资源／状态保护实现视觉，不能声称原来440ms已经等同560ms。

## 5. 与预测式入口组合时的最小接点

该分支自己的`docs/ARRIVAL_NATIVE_LOCAL_ACCEPTANCE.md`已列出并行重叠，应继承：

- `RiftletMain.swift`两条分支逐块合流：保留arrival preferences／settings／capture bridge与entry host，同时保留正式selection owner、visibilityRevision、Feedback hooks、原ACK和退出清理。不能替换整个Main。
- `RiftPanelController`若`captureSuppressed=true`，同步取消装饰，不仅隐藏原行。恢复后不补演旧飞行。
- header或队列几何改变时取消旧plan，用新行实际global imageFrame／clipFrame重算。保留`onGeometryChange`、capture session层级和原输入岛。
- 屏幕／Space／backing变化、hide、close统一走失效与清理；过期completion不能重新出现。
- arrival新增`CaptureService.onImported`观察与entry自有截图收录不是同一个来源。若entry输出没有可信系统截图元数据，继续静态；不能把`applicationScreenshot`伪装成systemScreenshot或synthetic来借准入。
- 继承精确对象审计；组合之后更新明确批准的对象与交接身份，不豁免整目录、不禁用旧审计。

## 6. 本次只读确认的保护与证据范围

Git树对象比较确认，该分支的以下内容与正式`1920e056`完全一致：`Sources/RiftletCore`、`Sources/RiftletAdapters`、`Sources/CSQLite`、`Sources/RiftletFeedback`、`Sources/RiftletFeedbackUI`、`Sources/RiftletFeedbackDemo`、`Package.swift`，以及H快吞噬和Beta UX两份既有证据目录。完整差异列表未包含Web适配器或上传准入修改。

固定提交中的`validation.json`仍写`IMPLEMENTED_AWAITING_MACOS_CI`且macOSCI为空；最新两个commit说明修复了Swift编译类型问题，d552说明保留Feedback run40716158097为用例执行前编译失败。**本补充没有读取Actions最终状态，不能据此宣称当前CI成功或失败。** 工程合流前由正式负责人重新核对实际远端HEAD、对应CI与非作者审查，不把这份静态设计审计当作准入结论。

结论：本轮设计交接必须从“已有原生到达实现待组合与视觉对齐”开始，不能从“没有原生磁力，需要重写”开始。本次只新增此说明，正式工程与两个并行工程分支保持不动。
