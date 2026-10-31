# Riftlet｜固定版本复用清单

所有“已确认机制”均为 SOURCE-VERIFIED；本轮未在 macOS 编译或运行这些项目。成本是对片段独立性及适配范围的工程判断，属于 INFERRED，不是工时承诺。没有向 Riftlet 写入任何产品代码。

## 1. 固定版本与许可

| 项目 | 完整固定提交 | 已读许可／归属 | 最终角色 |
| --- | --- | --- | --- |
| [ssut/Sukurini](https://github.com/ssut/Sukurini/tree/c74210f81347a1df4ef407523361e7a45c12ab3e) | c74210f81347a1df4ef407523361e7a45c12ab3e | [Apache-2.0 LICENSE](https://github.com/ssut/Sukurini/blob/c74210f81347a1df4ef407523361e7a45c12ab3e/LICENSE)＋[NOTICE](https://github.com/ssut/Sukurini/blob/c74210f81347a1df4ef407523361e7a45c12ab3e/NOTICE)，Suhun Han | 小型 watcher 可采用；其余仅摘机制 |
| [m0ztop/Screenshoss](https://github.com/m0ztop/Screenshoss/tree/8ef6ef7cf721a2eb29f76a94815e6992d3d3a1ac) | 8ef6ef7cf721a2eb29f76a94815e6992d3d3a1ac | [MIT](https://github.com/m0ztop/Screenshoss/blob/8ef6ef7cf721a2eb29f76a94815e6992d3d3a1ac/LICENSE)，2026 Mert Oztopkara | 图片完整性与稳定性小函数 |
| [alejandrobujan/tendedero](https://github.com/alejandrobujan/tendedero/tree/32a3e47187fdea7b2fd43b3ab5a913f0ed33724a) | 32a3e47187fdea7b2fd43b3ab5a913f0ed33724a | [MIT 源码许可](https://github.com/alejandrobujan/tendedero/blob/32a3e47187fdea7b2fd43b3ab5a913f0ed33724a/LICENSE)，2026 Alejandro Buján；名称／图标／艺术素材另有限制 | 窗口骨架、首次点击；不用艺术资源及私有 CGS |
| [steipete/oracle](https://github.com/steipete/oracle/tree/fde96271db1611c0287fcfde3053c19325280d10) | fde96271db1611c0287fcfde3053c19325280d10 | [MIT](https://github.com/steipete/oracle/blob/fde96271db1611c0287fcfde3053c19325280d10/LICENSE)，2026 Peter Steinberger；package 0.22.1 | 输入／scope 思想及回归反例；不继承完整上传与成功判据 |
| [p0deje/Maccy](https://github.com/p0deje/Maccy/tree/54fb9f00b828a4ec367e706c0e276df90febe76a) | 54fb9f00b828a4ec367e706c0e276df90febe76a | [MIT](https://github.com/p0deje/Maccy/blob/54fb9f00b828a4ec367e706c0e276df90febe76a/LICENSE)，2025 Alex Rodionov；Paste 片段注明 Clipy 来源 | 剪贴板表示与键盘布局边界参考 |
| [Clipy/Screeen](https://github.com/Clipy/Screeen/tree/f8f4bfa6cb38cb69ec1ee104fb5ad949a92b2ae3) | f8f4bfa6cb38cb69ec1ee104fb5ad949a92b2ae3 | [MIT](https://github.com/Clipy/Screeen/blob/f8f4bfa6cb38cb69ec1ee104fb5ad949a92b2ae3/LICENSE)，2015–2020 Clipy Project | metadata predicate 参考；不引入 package |
| [openai/codex](https://github.com/openai/codex/tree/970111f6cb62cc02fe36a82ea7d71b37a2889c97) | 970111f6cb62cc02fe36a82ea7d71b37a2889c97 | [Apache-2.0](https://github.com/openai/codex/blob/970111f6cb62cc02fe36a82ea7d71b37a2889c97/LICENSE)＋[NOTICE](https://github.com/openai/codex/blob/970111f6cb62cc02fe36a82ea7d71b37a2889c97/NOTICE)；包含特定衍生部分说明 | 只研究文件最终确认语义，不引入 Rust、认证或接口代码 |

MIT 片段保留适用版权与许可。Apache-2.0 片段保留许可、适用归属与 NOTICE，标明修改。Maccy 的 Clipy 派生说明不能在摘取时丢失；若真正采用该段，应一并核对它指向的上游许可。许可义务不要求把 upstream 的追踪 SDK、更新器、产品名称或视觉资产带进 Riftlet。

## 2. 几乎直接可用：三小组

### R01｜目录 watcher：Sukurini

路径：[Sources/Sukurini/Core/FolderWatcher.swift](https://github.com/ssut/Sukurini/blob/c74210f81347a1df4ef407523361e7a45c12ab3e/Sources/Sukurini/Core/FolderWatcher.swift)

- 范围：3–6 的协议、60–85 的 O_EVTONLY／DispatchSource／cancel-close 生命周期、88–145 的 rename/delete/revoke 处理。
- 接口：start／cancel；onDirty／onFolderLost 回调；输入是获准的本地目录 URL。它只告诉 collector “目录变了”，不返回完整截图。
- 依赖：Foundation、Dispatch、POSIX，另有项目自己的 Log.watcher。
- 最少修改：移除／替换日志耦合；加入 sourceGeneration，忽略旧来源回调；continuous-write debounce 加最大合并等待；目录丢失后重新实例化；启动、唤醒与换源有界补扫。
- 成本：**低，局部适配。** 不应整套移植截图 store。
- 已知限制：目录事件不证明内容完整，也不是递归逐文件流；现有 trailing debounce 在连续事件下可能一直推迟执行。

### R02｜图片完整性原语：Screenshoss

路径：[Sources/ShossApp/ScreenshotImportService.swift](https://github.com/m0ztop/Screenshoss/blob/8ef6ef7cf721a2eb29f76a94815e6992d3d3a1ac/Sources/ShossApp/ScreenshotImportService.swift)

- 范围：71–74 FileSignature；76–99 稳定性检查；101–110 fileSignature；112–115 CGImageSourceGetStatus == statusComplete。
- 接口：candidate URL → signature／complete；上层 collector 跨一个共享时间窗比较候选，不给每张图顺序等待。
- 依赖：Foundation＋ImageIO。
- 最少修改：source file identity／symlink 过滤；来源复制前后复核；复制到私有 staging 后再做完整性与实际解码；成功后原子提升。尺寸／mtime 稳定不意味着未来永不变化。
- 成本：**低，适配成小 validator。** isCompleteImage 等函数接近直接可用；上层导入函数不能原样采用。
- 必须排除：57 行 moveItem 会移动用户原截图；15–69 的整段导入依赖命名筛选与串行等待。默认每文件 150 ms，十张仅该等待累计约 1.5 秒，这是源码推算，不是实测。
- 测试参考：[ScreenshotFilesystemIntegrationTests.swift](https://github.com/m0ztop/Screenshoss/blob/8ef6ef7cf721a2eb29f76a94815e6992d3d3a1ac/Tests/ShossTests/ScreenshotFilesystemIntegrationTests.swift) 25–87 的稳定／变化场景；源文件消失的断言应改为原件保持。本轮未运行这些测试。

### R03｜非激活窗口和第一击：Tendedero

路径：[Sources/Tendedero/LinePanel.swift](https://github.com/alejandrobujan/tendedero/blob/32a3e47187fdea7b2fd43b3ab5a913f0ed33724a/Sources/Tendedero/LinePanel.swift) 7–21、35–36；[GrabArea.swift](https://github.com/alejandrobujan/tendedero/blob/32a3e47187fdea7b2fd43b3ab5a913f0ed33724a/Sources/Tendedero/GrabArea.swift) 110。

- 接口：配置化几何／显示器／图层 → NSPanel；thumbnail view → onClick(assetId)，不成为第一响应者。
- 依赖：窗口骨架仅 AppKit；不要把 GrabArea 的 SwiftUI、拖放、长按、双击行为搬入。
- 最少修改：尺寸与位置全面参数化；去掉指针位置代表截图屏幕的假设；交互 panel 不能沿用 ignoresMouseEvents=true；collection behavior／最低可用 level 由真机确认。
- 成本：**低，几十行级别的 API 骨架；运行语义仍须真机验证。**
- 不继承 191 行等待 doubleClickInterval 的单击实现。装饰和交互层可独立，给视觉设计保留透明度、遮罩、间距和形状自由。

## 3. 需要有选择地改写

| ID／模块 | 精确来源 | 价值 | 需要修改／拒绝继承 | 成本与判断 |
| --- | --- | --- | --- | --- |
| R04 ImageIO 缩略图 | Sukurini Sources/Sukurini/Core/ThumbnailLoader.swift，330–355、374–384 | 下采样、图像朝向、point／pixel 区分 | 不带 192 MiB／1500 项缓存、4 workers、视频、图标 fallback；按目标屏幕 scale，不用 NSScreen.main 代替 | **小量自写更省。** 仅采用机制或约几十行 |
| R05 DOM 输入 | Oracle src/browser/actions/attachmentDataTransfer.ts | 真实字节→File／DataTransfer→原生 input setter | 移除 CDP／Node 包装、fake getter fallback；限定正确 composer；已有附件必须由页面 append 保留；真实目标验证前不可标已完成 | **中，受目标平台验证支配** |
| R06 DOM 证据身份 | Oracle attachmentEvidence.ts、composerRoot.ts | 限定 scope、保存实际节点、失效检查 | claim 必须核对真实身份；不用“仅新增一枚按钮”认领；不用首个可见 composer；补语言／surface profile | **中，需重写关键判据** |
| R07 进度观察 | Oracle attachmentProgress.ts、attachments.ts | 可列出上传中信号与旧兼容场景 | 不把 send 可用、spinner 不见、卡片存在、input.files 或 elapsed time 作为 READY；未知结构 fail closed | **不复制完成函数，重写小型正向 receipt profile** |
| R08 原生 Paste | Maccy Maccy/Clipboard.swift，100–110、122–148 | fileURL item 语义、Dvorak command-key 特例、Clipy 衍生经验 | 不带 Defaults／Sauce／History／AppState；先测 AX 菜单动作是否可省键位依赖；定向发送也不能绑定具体聊天 | **参考为主；真实 Mac 接受表示后再写小 writer** |
| R09 剪贴板临时恢复 | Sukurini Core/LatestScreenshotPaster.swift，65–100 | 多 representation 快照、changeCount 条件 | 不继承 58–61 固定 0.3 秒恢复；不假定 lazy provider 回调说明目标已消费 | **小量自写；无法给完美恢复保证** |
| R10 截图 metadata | Screeen Lib/Screeen/ScreenShotObserver.swift，43–54 | scoped NSMetadataQuery 与截图 predicate | 不直接带 package；补 initial gathering、分别处理 added/changed/removed、换源与恢复；不能让主路径等待 Spotlight | **几行自写更省，按实际需要启用补漏** |
| R11 文件最终确认模型 | Codex codex-rs/codex-api/src/files.rs，151–429 | file_id 贯穿 prepare／PUT／finalize 的状态区别 | 不继承接口、认证、use_case、512 MiB 限制或重试；只用来定义网页真实观察问题 | **研究证据，无运行依赖／无代码复用** |

补充固定链接：

- [Sukurini ThumbnailLoader.swift](https://github.com/ssut/Sukurini/blob/c74210f81347a1df4ef407523361e7a45c12ab3e/Sources/Sukurini/Core/ThumbnailLoader.swift)
- [Sukurini LatestScreenshotPaster.swift](https://github.com/ssut/Sukurini/blob/c74210f81347a1df4ef407523361e7a45c12ab3e/Sources/Sukurini/Core/LatestScreenshotPaster.swift)
- [Oracle attachmentDataTransfer.ts](https://github.com/steipete/oracle/blob/fde96271db1611c0287fcfde3053c19325280d10/src/browser/actions/attachmentDataTransfer.ts)
- [Oracle attachmentEvidence.ts](https://github.com/steipete/oracle/blob/fde96271db1611c0287fcfde3053c19325280d10/src/browser/actions/attachmentEvidence.ts)
- [Oracle attachments.ts](https://github.com/steipete/oracle/blob/fde96271db1611c0287fcfde3053c19325280d10/src/browser/actions/attachments.ts)
- [Maccy Clipboard.swift](https://github.com/p0deje/Maccy/blob/54fb9f00b828a4ec367e706c0e276df90febe76a/Maccy/Clipboard.swift)
- [Screeen ScreenShotObserver.swift](https://github.com/Clipy/Screeen/blob/f8f4bfa6cb38cb69ec1ee104fb5ad949a92b2ae3/Lib/Screeen/ScreenShotObserver.swift)
- [Codex files.rs](https://github.com/openai/codex/blob/970111f6cb62cc02fe36a82ea7d71b37a2889c97/codex-rs/codex-api/src/files.rs)

## 4. 明确不要带入的模块

| 来源 | 真实源码事实 | Riftlet 排除理由 |
| --- | --- | --- |
| Sukurini ScreenshotStore.swift，约 1019 行 | 包括转换、整理、backfill、远程目录轮询；321–330 只要求非空且 mtime 年龄≥2 秒；375–390 只比大小 | 不提供完整图片保证，带来过多不需要的产品状态 |
| Sukurini Package.swift | FirebaseAnalytics、FirebaseCrashlytics、libwebp、Sparkle | 当前研究选定的小片段无需这些依赖 |
| Sukurini ScreencaptureDefaults.swift setters | 写系统偏好并 killall screencaptureui | 用户只授权研究，不改变系统截图设置；将来只读提示与一次明确配置也足够 |
| Screenshoss ScreenshotLibrary.swift，约 931 行 | 图库、选择、存储等完整产品管理 | 2–3 张待用队列无需这些功能 |
| Screenshoss ScreenshotItem.swift 107–119 | 英文 Screenshot／Screen Shot 前缀 | 不能正确覆盖中文和自定义系统截图命名 |
| Tendedero AppDelegate.swift 438–444、550–563 | 30 Hz 指针计时器切换整个 panel 的 ignoresMouseEvents | 增加持续唤醒与快速入点点击的状态时序依赖 |
| Tendedero FullScreen.swift 6–10、31 | 私有 CGSMainConnectionID／CGSCopyManagedDisplaySpaces | 不进入产品；先用公开 collection behavior |
| Tendedero CaptureFlight.swift 142 | 120 Hz Timer 手工驱动动画帧 | 少量图层的遮罩／位移／透明度用 Core Animation 即可 |
| Tendedero Line.swift 89–90、226–228 | 超容量自动删除最旧项 | 不能擅自丢弃未用截图 |
| Tendedero ScreenshotWatcher.swift 34–41、153、177–181 | 自定义目录默认接受所有图；xattr 只检查存在；未分类条目也记 known | 会误收或漏收延迟 metadata；不作为主 ingestion 实现 |
| Oracle 整个附件／自动化流程 | 大量通用选择器、fallback、prompt／send 与 completion 兼容逻辑 | 当前契约只追加、绝不发送；继承整库比小 adapter 更危险、更难维护 |
| Maccy clipboard manager 整类 | timer、历史库、设置和 AppState 耦合 | Riftlet 只在一个明确操作期间临时写一次剪贴板 |
| Screeen 完整 observer | update 通知中 if/else-if 只处理一种变化；无 initial gathering；来源只初始化读取 | 需要修补的壳多于其核心价值 |

这些排除项对应的完整固定链接见 SOURCE_MANIFEST.json；无需下载上游完整仓库来实施 R01–R03。

## 5. 组合关系与依赖预算

设计接口，不是本轮已创建的工程：

~~~text
SourceAccess(URL, bookmark)
  → FolderWatcher(onDirty, sourceGeneration)
  → CandidateCollector(pending identities)
  → StableImageValidator
  → PrivateAsset(staging, verified decode, atomic promote)
  → QueueStore(assetId, operation)

ThumbnailRenderer(immutable asset URL, target scale)
  → RiftPanel(onClick assetId)
  → TransferCoordinator(target lease, operation)
  → one selected WebTransport / admitted MacAdapter
  → receipt {READY | DEFINITIVE_FAILURE | UNKNOWN}
~~~

优先使用 AppKit、Foundation/Dispatch、ImageIO、Core Animation、系统 SQLite；Mac adapter 需要时才加 ApplicationServices。SwiftUI 可以用于将来的设置 UI，不是空间裂缝必须使用的前提。

不引入 Firebase、AVFoundation、通用截图管理 SDK、浏览器自动化框架、clipboard history、模型 API、后端或全盘索引。Chrome 扩展若胜出，浏览器 JS＋小 Swift helper 即可。研究时查看的 Chromium／MCP 源码是机制证据，没有建议将它们作为运行依赖。

适合继承的是经过定位的实现细节，不是上游产品的全部架构。用原生 API 重写二三十行通常比适配数百行带状态的管理器更少工作。
