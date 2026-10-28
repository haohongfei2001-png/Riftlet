# 内置截图：技术复用、来源与证据边界

日期：2026-10-29（北京时间）。审计起点为薄界原生交接 `443d21da1a55c0061eafced823b5406879b96024`，包含截图入口候选 `5d6a683652d255af8c1d3e0d9533587fcc27a24d`。本文记录源码审查和公开 API 调查；实际运行结果由本增量的验证记录单独固定，不以文档代替截图验收。

## 1. 本轮技术决定

保留现有 AppKit 选择层、截图会话状态机、`/usr/sbin/screencapture` 后端、`PrivateAssetImporter`、SQLite v3、微图及历史。没有建立第二套截图工具，也没有引入第三方运行时。现有非交互截图命令能够接收已经冻结的窗口 ID 或区域，产物按原字节进入既有持久化路径；这是当前最小、可审阅的改进基础。

ScreenCaptureKit 的内容过滤和 HDR API 确有能力优势，但未测得本产品在目标 Mac 上的端到端收益。当前没有证据支持为表面速度替换全部截图后端。单独编写、编译或运行比较工具不构成生产后端准入。macOS 13 的兼容路径继续保留；新后端只有在原像素、颜色、排除行为、取消及故障矩阵均验证后才可替换对应路径。

## 2. 可复用源码与发现的缺陷

| 现有组件 | 保留的能力 | 起点审计发现 / 本增量约束 |
| --- | --- | --- |
| `ScreenshotEntryModel` / `ScreenshotEntryController` | 预测相机、固定模式槽、移动取消盖片、连续截图、薄界视觉 | 关闭功能必须同时移除观察器和无用定时器，而非只把面板透明化；模式默认值与当前会话顺序分开 |
| `InteractiveScreenshotController` | 原生区域/窗口/全屏选择、会话身份、迟到回调拒绝、WindowServer 自身窗口检查 | 需要检查休眠、Space、显示器 scale 变化及窗口几何变化；取消后旧任务不能恢复选择层 |
| `InteractiveScreenshotSystemCapture` | 非 shell 直接参数、独有子进程、取消/超时、原 PNG 验证 | 进程取消、任务结束和新会话之间不能串扰；原件保留与失败残片处理应区分 |
| `InteractiveScreenshotGeometry` / 命令生成 | AppKit/Quartz 原点转换、负坐标、多屏描述 | 起点最终命令调用 `.integral`，而预览保留浮点边界，可能使所见和实际矩形不同；不能把逻辑 point 当作 pixel，不能把单一 Retina scale 套用整个混合屏桌面 |
| `CompletedScreenshotImporter` | 跳过目录 watcher 的额外稳定等待，复用描述符/签名、格式、容量、哈希、journal 和 SQLite | 入口接受来源并不授予上传权限；不能让内置来源借用系统截图准入 |
| `ScreenshotEntryHost` | 截图后保持当前模式，接入既有 importer、微图与历史 | 起点按实际 xattr 将部分内置产物记为 `systemScreenshot`；本轮要求所有内置捕获都保持 `applicationScreenshot`，元数据仅作真实诊断 |
| `ScreenshotMarkupController` | 可选矩形标注、撤销、关闭时保留原件；不扩张编辑器范围 | 起点统一创建 8-bit bitmap，不能宣称 HDR/高位深编辑无损；原件不可被替换，无法保真编辑的格式应保守处理并清楚说明 |

以上是对固定起点的审计，不应误读为最终版本仍存在相同缺陷。修复与测试以最终提交的差异和验证表为准。审查捕获相关源码未发现使用 `CGS` / `SLS`、`dlsym`、`dlopen` 或 `_silgen_name` 调用私有窗口接口；不是对全仓库及所有外部依赖的通用安全保证。

## 3. 后端比较

| 维度 | 现有 `screencapture` | ScreenCaptureKit / `SCScreenshotManager` | Quartz / CoreGraphics 图像捕获 |
| --- | --- | --- | --- |
| 系统版本 | 当前 macOS 13 起候选已使用；具体命令契约应以相应 OS 的 `screencapture -h` 和实测固定 | ScreenCaptureKit 可服务 macOS 13；直接 `SCScreenshotManager.captureImage` 需 macOS 14。macOS 13 一帧流需要另外管理输出、完整帧、超时和停止 [A1][O1] | 旧图像 API 可用于旧系统，但 Apple 已将相关图像捕获接口标为 deprecated；不作为新默认后端 [A6] |
| 区域和缩放 | 参数是桌面矩形；当前实现保留工具输出，不另行缩放或编码。分数坐标解析、混合缩放和每 OS 精确 raster 结果仍须实测 | `SCContentFilter.contentRect` 是 points，`pointPixelScale` 给出 point→pixel 比率；显式配置输出尺寸。`sourceRect` 不能替代单窗口裁切，因为单窗口捕获忽略它 [A2][A3] | 对特定窗口可直接取图，但矩形、scale、alpha、颜色及新系统支持仍需验证 |
| 窗口身份 | Riftlet 冻结窗口 ID/PID 后调用 `-l`，曝光前后复核；OS 决定边框/圆角/阴影产物 | `desktopIndependentWindow` filter 表达单窗口；窗口 ID 来自 `SCWindow`。阴影、clip、子窗口配置可能改变尺寸，不能只拿 frame×scale 就假设全部窗口截图都正确 [A2][A4] | 可指定窗口/数组；不应通过私有接口获得额外权限或隐藏能力 |
| 隐藏 Riftlet | 本程序控制曝光时机，撤下/透明化自身窗口并检查 WindowServer；真实像素仍须确认 | 可在自己创建的 filter 中排除应用或具体窗口 [A2] | 构造指定窗口列表可影响自己的捕获内容；不能改变别人的截图行为 |
| 广色域和 HDR | 原 PNG 的 profile、bit depth、色彩块与原字节保留；这不证明命令的 PNG 已保存屏幕全部 HDR 亮度 | macOS 15 增加 HDR 截图 preset；像素格式、色彩空间、local/canonical display intent 都要明确。能力存在不等于当前 PNG/下游上传已支持 [A5] | 不能仅凭有 `CGImage` 就认定保留 HDR 或颜色管理；新 SDK 已不鼓励旧图像捕获接口 |
| 时延 | 包含子进程启动、曝光、编码、文件验证和导入；不能只测 `Process.run()` | 可能省去子进程；但 content 枚举、TCC、初帧、转换、编码仍有成本，收益尚未测得 | 单次 API 返回速度不代表完整 PNG→持久化→微图耗时 |
| 内存 | 读取原 PNG；ImageIO 缩略验证；标注另行解码。实际峰值应连同子进程计量 | 配置的 pixel buffer / CGImage / 编码副本和流 queueDepth 会影响内存；没有本产品实测数据 | 像素缓冲和编码副本有成本；只比较 PNG 文件大小不等于内存比较 |

**截至源码冻结前，尚无足以确定本产品真实耗时、内存或画质获胜者的数据。** 后续 CI 或真实 Mac 测量由本增量交接与结果记录固定；数值必须同时带 OS build、架构、显示器/缩放、backend、模式、样本数量、冷热状态和对应源 SHA。

### 分数选区与混合缩放

没有找到 Apple 对命令行 `-R` 分数坐标解析的可靠公开保证。把格式改为小数并通过字符串单测，不能证明多了 Retina 单像素能力。至少要在真实 2× 显示器显示已知像素图案，比较整数与半 point 位置、输出尺寸及边缘像素；相同命令还须验证负坐标和外接屏。未执行时标 `NOT_RUN`。

在 1× 与 2× 显示器上跨界的一张 PNG，必须选择统一像素栅格；不能同时声称“没有任何重采样”和“每块都按同一 points→pixels 系数”。保留系统原字节是保守的当前选择，但不替代混合屏精度验收。预览、冻结选区、最终命令和保存的几何记录至少必须一致。

本轮将整数 point 矩形统一用于预览、冻结和命令，去除最终一步静默扩大选区的差异；没有把未证明的小数参数变成生产契约。因此当前选区仍不是 2× 上任意半 point / 单像素边界。新增单显示器、完全位于屏内的区域/全屏尺寸后置检查：PNG 必须等于冻结矩形乘该显示器 scale，否则保留原文件并报告尺寸错误，不导入为成功截图。窗口阴影及跨显示器 raster 不在该尺寸推断内；测试通过仅证明拒绝逻辑，不证明系统每种拓扑的输出正确。

## 4. 开源实现的复用评估

此次只阅读实现和许可，没有复制以下项目源码到 Riftlet，故没有新增运行时或捆绑许可。许可相容的工程选择仍须保留原 notices；“开源”不自动意味着任意复制。

| 项目 / 核对版本 | 直接核对的实现与许可 | 适用结论 |
| --- | --- | --- |
| Snapzy `77d3d3feb7f46d1909dce8824f3b35d5709378a2` | `ScreenCaptureManager.swift`、`SingleFrameStreamCaptureSession.swift`；BSD-3-Clause [O1] | 原生捕获经验很相关：content cache 过期、输出 scale、单帧流完整状态和 exactly-once continuation 都值得对照。其完整 manager 涉及更多功能及 best-effort fallback，不宜整体移植；Riftlet 不应在失去选中目标后偷偷换屏或改抓区域 |
| Aperture `7591bb540c844fe6c47edeac34b17c25e92a717f` | macOS 录屏库、MIT [O2] | 许可证允许在保留 notice 等条件下复用，但录屏流程不是当前静态截图需求；引入它并不能减少现有截图的关键逻辑 |
| XCap `5c205f20cde2d5bdfcbc058db073cfd274a8eeda` | `src/macos/capture.rs`、Apache-2.0 [O3] | 核对版本用 `CGWindowListCreateImage` 后把缓冲转为 `RgbaImage`。跨语言依赖、旧捕获 API 和颜色元数据另建成本没有已证明收益，不引入 |

结论是复用 Riftlet 既有实现及 Apple 公共 API，不引入一个大型截图编辑器。Snapzy 的 macOS 13 单帧流仅是未来确有必要加入 SCK 兼容后端时的审查参照；不能借用它的测试或性能结论当作 Riftlet 实测。

## 5. 内置排除与系统截图的明确边界

Riftlet 发起的内置截图可以控制自己的窗口隐藏与捕获时机；SCK 后端也只能控制它自己创建的 filter。用户调用 Screenshot.app/系统快捷键时，Riftlet 不拥有对方的 filter 和曝光时机。两者的排除承诺必须分开。

Apple 目前将 `NSWindow.SharingType.none` 描述为不再使用的 legacy 值，并明确要求不要用它来隐藏或省略被捕获的内容 [A7]。本产品不能通过设置此属性宣称系统截图永远排除裂缝。也不应改系统快捷键、截图位置、系统缩略图偏好，或对系统截图按键进行拦截来掩盖这一限制。用户原有的独立隐藏裂缝设置继续适用。

## 6. 来源、上传与最小后续准入

内置截图由 Riftlet 发起，因此本轮统一记录 `applicationScreenshot`，包括有真实系统 screenshot xattr 的原 PNG；编辑产物同样属于该来源。原文件的 xattr 不伪造、不擦除；它不能单独证明本次来源等同既有系统截图验收链。

补充审计发现系统截图目录允许与 `root/captures` 重叠。原来可见的自有 PNG 在编辑器停留期间可能先被系统收录器发现；仅在 Host 传入 `.applicationScreenshot` 不足以阻止这条竞争路径。新原件从独占创建预留文件开始即使用隐藏 basename，派生 PNG 也如此，复用收录器原有 `.skipsHiddenFiles` 行为精确隔离自有产物；同目录内可见的真正系统截图继续按原流程收录。显式 built-in 导入若命中已有其他来源的 sourceKey，拒绝返回为成功，不重标历史或解除旧操作。该修复不追溯改名旧候选留下的可见原件，也不为它们制造新的上传证据。

保留以下既有边界：

- `PrivateAssetImporter` 继续验证原文件身份、尺寸/格式、容量、完整哈希和 durable journal；SQLite v3、不透明 sourceKey 去重及原文件不重建。
- `SystemScreenshotWebCandidate` 和准入登记仍只接受相应系统截图。`ReceiptPolicy` 对 `applicationScreenshot` 的开始、完成和重试均拒绝。
- 普通启动的 `ApplicationAttachmentComposition` 仍使用 `UnavailableAdapter`。关掉内置截图不会把普通模式升级成上传模式，也不会关闭原来的系统截图收录/受限上传。
- 原 F/H/旧 UNKNOWN 不新增资格、不补写上传开始、不清除锁、不重传。原目标身份、草稿内容/选区和既有附件保护不变。[L1]

最小后续改动必须由新真实证据驱动：在独立允许的测试草稿中，对一个新 `applicationScreenshot` 原 PNG 取得完整 file/hash→原点击目标→唯一输入→真实递增上传开始→微图吞噬→后台精确内容完成链；覆盖拒绝/目标变化/取消及未明结果。随后以独立、显式新 profile 和新操作登记扩展准入，不能只删除来源 guard 或把它重标为 `systemScreenshot`。开始、完成、安全失败/重试是三个独立决定；完成通过不自动开放重试。

当前登记 Mac 离线，因此这条新来源真实链是 `NOT_RUN`。可独立验收的本轮范围是内置截图原件→私有导入→微图/历史、取消生命周期和独立开关；不能对外写成“内置截图已实际上传并快吞噬”。

当前内置产物直接进入同一微图队列；没有将其几何伪装成已准入的系统截图元数据，也没有新增入缝模式。`ArrivalCaptureBridge` 的真实 source-geometry 路径目前只绑定既有系统来源，故内置截图采取已批准的静态降级。不能将设置中存在“磁力吸引”误写为内置三模式磁力轨迹均已实测。要为内置截图接入已有磁力路径，至少先验证同屏原 PNG 尺寸与选区映射；窗口阴影、混合缩放或编辑产物无法精确对应时仍应静态呈现。

用户主动打开统一设置、使用引导、历史、反馈或动效设置时，App 先取消当前截图会话，再展示交互窗口。该显式行为避免 status-bar 层级的选择面板截走设置开关点击，不改变持久启用状态。截图成功本身仍保持展开与当前模式。

## 7. 实测工具的最低证据格式

使用自建测试图案，禁止将真实桌面/聊天/窗口标题或用户截图提交公共仓库。测试工具只在 `CGPreflightScreenCaptureAccess()` 已允许时自动运行；没有授权就输出 `NOT_RUN`，不修改 TCC、不关闭系统保护、不自动请求权限。CI 可以编译该工具和执行允许范围的测试，但权限不足不能当成图像测试通过。

独立工具 `scripts/benchmark-builtin-capture.swift` 不链接入产品；它测量自己的合成窗口和内侧区域，输出 PNG 元数据、比较用 sRGB 摘要、各后端分段时延及明确标注范围的内存值。它不替代真实点击→原件→私有导入→微图的计时，也不代替 HDR、窗口遮挡、Spaces 或混合显示器验收。全屏内容必须单独显式选择，CI 不使用该选项；图像证据仅允许经完整合成图案核验后重新编码的可公开预览，原始截图字节不作为公共产物。

至少分别记录：

1. `select_confirmed`、自身窗口撤下确认、backend 开始/结束、原 PNG 完整验证、durable import 完成、微图首次可见及可点时间；报告完整链 p50/p95，而不是只截取最快一段。
2. 冷启动与连续截图分别取样；region/window/display 分开；失败和取消样本不得混入成功均值。
3. PNG IHDR 尺寸、bit depth、color type、ICC/sRGB/gAMA/cHRM 等存在性和哈希；原件与 private media 的 SHA-256 一致。颜色比较显式统一参考空间；不能把未经管理的 RGBA 字节相等当作广色域等价。
4. 父进程及子进程峰值、CPU、文件大小和失败残片；外接屏/scale/负坐标/阴影导致的尺寸差异逐例解释。
5. `PASS` / `FAIL` / `NOT_RUN` 与原因；物理鼠标、真实 TCC、Spaces、休眠/唤醒、断屏、混合屏不能由注入 fixture 代替。录屏须与精确二进制/源 SHA 和时间段匹配。

## 一手参考

- [A1 — Apple WWDC23: What’s new in ScreenCaptureKit（截图 API）](https://developer.apple.com/videos/play/wwdc2023/10136/)
- [A2 — Apple SCContentFilter（窗口/应用过滤、contentRect、pointPixelScale）](https://developer.apple.com/documentation/screencapturekit/sccontentfilter)
- [A3 — Apple SCStreamConfiguration.sourceRect（单窗口忽略此值）](https://developer.apple.com/documentation/screencapturekit/scstreamconfiguration/sourcerect)
- [A4 — Apple SCStreamConfiguration（尺寸、色彩、cursor、阴影、clip）](https://developer.apple.com/documentation/screencapturekit/scstreamconfiguration)
- [A5 — Apple WWDC24: Capture HDR content with ScreenCaptureKit](https://developer.apple.com/videos/play/wwdc2024/10088/)
- [A6 — Apple CGWindowListCreateImage（Deprecated）](https://developer.apple.com/documentation/coregraphics/cgwindowlistcreateimage?language=objc)
- [A7 — Apple NSWindow.SharingType.none](https://developer.apple.com/documentation/appkit/nswindow/sharingtype-swift.enum/none)
- [O1 — Snapzy 核对提交](https://github.com/duongductrong/Snapzy/tree/77d3d3feb7f46d1909dce8824f3b35d5709378a2)、[BSD-3-Clause](https://github.com/duongductrong/Snapzy/blob/77d3d3feb7f46d1909dce8824f3b35d5709378a2/LICENSE)、[单帧兼容实现](https://github.com/duongductrong/Snapzy/blob/77d3d3feb7f46d1909dce8824f3b35d5709378a2/Snapzy/Services/Capture/SingleFrameStreamCaptureSession.swift)
- [O2 — Aperture 核对提交及 MIT 许可](https://github.com/wulkano/Aperture/tree/7591bb540c844fe6c47edeac34b17c25e92a717f)
- [O3 — XCap macOS 捕获实现](https://github.com/nashaofu/xcap/blob/5c205f20cde2d5bdfcbc058db073cfd274a8eeda/src/macos/capture.rs)、[Apache-2.0](https://github.com/nashaofu/xcap/blob/5c205f20cde2d5bdfcbc058db073cfd274a8eeda/LICENSE)
- [L1 — Riftlet 既有受限系统截图准入](SYSTEM_SCREENSHOT_RESTRICTED_ADMISSION.md)
