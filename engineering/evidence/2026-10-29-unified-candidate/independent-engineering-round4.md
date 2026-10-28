# Riftlet 统一候选：第四轮独立工程复审

## 审查结论与对象

审查人：`/root/engineering_review`。本轮对产品、Feedback UI、原生视觉 helper、工作流及证据声明保持非作者、只读审查。此报告由审查人新增；产品修复由正式集成人 `/root` 实施，视觉 helper 与 Feedback 计数修复由 `/root/acceptance_audit` 实施。审查人曾编写统一 composition gate 及其隔离测试，该部分由 root 独立复核，不以本报告构成自我批准。

当前审查基线为 `fea485ce5226ab519af8f5325412b2ef43ba4a5a`，本轮审查对象是其后的工作树差异。**源冻结与精确 source SHA 待定；本报告不批准尚未提供的提交，也不把源审查等同于 macOS 编译、实际交互或视觉通过。** 当前已读完的产品修补未发现源级阻断。helper 作者仍在完成正常／真实系统辅助功能 profile 的有限取证及末尾回归；其最终 diff 与 exact source 对象需另行确认。

## 1. 来源合同与目录重叠：采用范围明确收窄

远端新增的 `b901b5e10a94aa25165d0e020e50931ae8015a77` 内置截图候选和 `69600ab3c7fa9e373582613bd55d22075234b65a` 体验设计补充仅作为独立发现来源读取。二者不自动成为本轮批准输入，也未整体合入。正式输入仍是 formal `0e7ea8be…`、thin `443d21da…`、design `7e03bd2c…`。

**最终决定保留原合同，不采纳“所有内置图一律 applicationScreenshot”的新策略。** `docs/CAPTURE_ENTRY_2026-10-28.md` 第 57 行的既定规则继续有效：带真实系统截图元数据的原始 PNG 仍通过原 importer 及候选格式／身份预检；缺少元数据的图和编辑派生件为 `applicationScreenshot`。Host 的原判定表达式未修改，旧记录、旧原图及 UNKNOWN 不变。本轮前期讨论中关于全面改义的建议已被这一决定明确取代。

已确认的问题是私有 `captures/` 与用户选择的系统截图目录重叠时，观察器可能在标注完成前先行收录可见原件，随后 Host 再收录派生件。修复仅改变新建文件名：

- 新增 `Sources/RiftletCapture/InteractiveScreenshotOutput.swift`，为原件与派生件生成以点开头的独立 UUID 名称。
- 系统捕获和 Host 编辑输出两处生产调用共用该 factory。原件原有 `O_EXCL`、`O_NOFOLLOW`、私有目录和文件权限检查继续保留。
- active 与 retired 源扫描原本共用 `CaptureService.candidateFiles` 的 `skipsHiddenFiles`，无需放宽扫描准入或改写旧记录。Host 仍显式导入完成选择的一个文件。
- 新回归实际启动 `CaptureService` 并在 active／retired 目录间切换；断言可见系统图正常收录、隐藏原件不被观察器收录、只显式选择的派生件加入、所有字节及存储用量仍保留。另一个回归证明隐藏的原始 PNG 仍遵守原系统元数据规则。

这些回归使用新临时目录、生成 PNG 和显式合成 xattr，只证明软件准入与排除行为；不是系统截图、TCC 授权或上传验收证据。

## 2. 权限提示框中的晚到启动

`InteractiveScreenshotController.start` 在调用权限检查前建立本次启动令牌；提示框返回后仅允许仍有效的令牌继续创建截图会话。`cancel` 在检查会话是否已激活之前先撤销令牌。较新 start 可以替代仍悬挂的旧 start；旧提示框的返回不能重开区域模式或发出过期错误。

两条新增控制器回归分别在模拟权限回调内取消、或启动较新的全屏会话，检查无迟到选择窗口、无捕获请求、无过期错误以及新模式保留。该修复针对嵌套 run loop 的生命周期问题，没有引入新截图引擎、外部鼠标事件、自动权限申请或上传能力。真实系统权限提示框操作仍为 NOT_RUN。

## 3. 首次使用及辅助窗口收口

`SetupPresentation` 将首用说明、流程和下一步按实际 `SetupAttachmentState` 区分。普通生产关闭时明确为本地收录与查看，并说明授权不会开启上传；离线、synthetic、受限系统截图候选、不可用目标各有相应文本。About 共用该真实能力说明，不再对本地模式承诺单击附加。

Setup 将“不发送消息，不删除原截图”移到固定 footer，正文滚动不会让该说明消失；About 的反馈按钮恢复本征宽度。新增 112 pt 静态原生示意仅为批准纸张到边缘关系的装饰呈现，不接收点击，不持有真实截图，不赋予输入能力；其字体、颜色、像素对齐和 backing／appearance 重绘 API 未发现源级疑点，最终审美由非作者设计审查及新截图确认。

History 的行动说明只描述当前实际可用的按钮，不再对没有恢复／移出能力的 UNKNOWN 行显示无关承诺。上述变化没有改队列状态、目标选择、历史记录或执行权限。

## 4. Feedback 计数修复及审查中排除的 IME 回归

原 UI 用 Swift 字素数显示计数，正式 `FeedbackEnvelope` 按 Unicode scalar 和 UTF-8 字节限制校验；复杂 emoji 或组合符号可能造成用户看到未超限却无法提交。新 UI 的计数使用 `unicodeScalars.count`，正文有效性直接复用 Envelope 构造验证，不建立第二套准入规则。验证不建立 outbox、凭证或回执。空白／超限文本禁用提交；草稿文本继续保留。

审查中指出了一个新增交互风险：若把 `hasMarkedText` 纳入按钮 enabled 状态，而仅由 `textDidChange` 刷新，IME 单纯 unmark 后未必触发正文变化，可能导致按钮保持 disabled。作者已移除这个新增 gating；当前源码中的提交按钮仅依赖 loaded、busy、可编辑性、engine 和正文有效性。原 `submitCurrentDraft` 与 `saveBeforeClosing` 的 marked-text 安全 guard 原样保留。现有 IME 保护因此没有被削弱，也不新增对未可靠观察的 unmark 事件的依赖。

正式工程最新的草稿可靠保存、异步关闭锁定、关闭后重开、diagnostic 同意快照、nil endpoint、未真正接收不得显示成功等边界保持。待作者完成新的 Unicode／提交按钮原生回归后再确认其最终测试差异。

## 5. 原生视觉证据失效及 helper 修复

上一成功 CI 的独立视觉审查证明：24 张辅助窗口原尺寸 PNG 有效；13 张静态边缘 PNG、76 张动效 PNG 和 5 个 MOV 只捕获了背景，不能作为队列、入口或运动通过证据。根因是 `NSApp.orderedWindows` 是脚本化窗口集合，不含 NSPanel。实际 runner 的 Reduce Motion 同时开启，运动事件为 none。旧证据必须保留并标明失效范围，不能通过新增元数据将其升级为有效画面。

已读到的 helper 修复：

- 用 `NSApp.windows` 建立当前进程可见窗口 ID 集合，再由公开 `NSApplication.enumerateWindows(options: .orderedFrontToBack)` 取真实自有 onscreen 顺序。要求数量与集合完全一致，不读取其他进程 metadata。
- 单窗仅选择一个自有标题窗口；多窗必须包含自有 backdrop 且至少有一个产品窗口。每个 ID 保留精确整数转换、非零检查和 nil-callback CFArray 语义；仍使用公开 Swift Quartz overlay。
- 多窗 PNG 以同 bounds 的自有 opaque backdrop 原图为基准逐原始像素比较。至少 64 个像素存在大于 8 的通道差异才通过，防止背景被再次标为产品画面。原始图片不被缩放或修改。
- manifest 记录窗口数量、自有前后顺序、产品数量和像素差。driver 校验 ID 唯一、数量一致、像素差合理及起止真实辅助功能快照；旧 manifest 不满足新增条件。
- MOV 沿用有界时长、实际捕获时间戳、有限内存、无补帧和独立 NOT_RUN 规则。PNG 的像素最低检查不代替独立观看 MOV；WindowServer 自有合成场景也不证明实际桌面焦点、系统层级或物理鼠标操作。

审查人直接读取 Apple 官方文档确认：`enumerateWindows` 自 macOS 10.12 可用；`orderedFrontToBack` 明确为 app 自有 onscreen 窗口的前后顺序；`orderedWindows` 文档明确排除 panels。参考来源：

- <https://developer.apple.com/documentation/appkit/nsapplication/enumeratewindows(options:using:)>
- <https://developer.apple.com/documentation/appkit/nsapplication/windowlistoptions/orderedfronttoback>
- <https://developer.apple.com/documentation/appkit/nsapplication/orderedwindows>

## 6. 真实 CI 辅助功能基线

独立读取 GitHub 官方 runner-image 脚本发现，macOS runner 预设同时将 `com.apple.universalaccess` 下的 `reduceMotion` 与 `reduceTransparency` 写为 true。来源：<https://github.com/actions/runner-images/blob/main/images/macos/scripts/build/configure-system.sh>。

当前工作流仅调整临时 CI runner 的这两项正常基线，再用新 AppKit 进程读取 `NSWorkspace.shared` 的 Reduce Motion、Increase Contrast、Reduce Transparency 三个真实属性。正常证据要求三者均为 false；不能仅靠 defaults 命令退出码或输出宣称成功。helper 也独立记录起止真实属性。产品辅助功能 guard 不改，用户设备设置不改，不申请或绕过 TCC。

作者仍在补真实系统 reduced profile 的有限场景与 driver 预期 profile 校验；该部分的最终 diff、系统 readback 和新 CI 尚未审完，不在本次预备结论中自动批准。若实际状态不符，相关正常运动／材质证据必须失败或 NOT_RUN，不得用产品内强制 false 替代。

## 7. 组合、安全边界及已执行验证

未观察到本轮扩大普通生产上传、安全失败或安全重试准入；未修改 Chrome Web 适配器、uploadStarted、最终完成、原目标或精确内容证明要求；未重写 SQLite、旧 UNKNOWN 或原媒体。原 formal Feedback 修复、固定历史审计脚本和精确来源对象继续保留；新的 exact source pin 应在最终非作者确认后更新，不扩大目录豁免。

审查人独立执行结果：

| 检查 | 结果与范围 |
|---|---|
| 当前 diff 的只读产品／流程审查 | 已读范围未见未解决源阻断；最后 helper／UI 测试差异待冻结 |
| `Tests/NativeVisualEvidence` | 12 项 PASS，0.014 秒；为 manifest 拒绝回归，不是原生画面验收 |
| `git diff --check` | PASS |
| 最新修补的 macOS 编译与组合 Native／Feedback CI | 待运行／确认 |
| 最新原尺寸 PNG 与实际 MOV | 待重新取得并独立审阅 |
| 真实截图、物理鼠标、1x/2x 跨屏、旋转、多显示器变化、Spaces、全屏、实际 TCC／辅助窗口操作 | NOT_RUN；缺少在线授权 Mac 与真人操作条件 |

旧 H 上传验收不重跑，不新建 Feedback 私有仓库，不声称云端已部署，不请求创始人本轮安装。PR #1 维持 Draft，main 不合并，不公开发行。

## 8. 交付时应保留的质量分类

1. **已实质修补且有独立源审查／对应有限验证的项目：** 隐藏文件路径、防晚到权限启动、真实能力文案、footer／About／History、Feedback scalar 一致性、多窗捕获漏面板及旧证据诚实降级。原生修复是否最终通过，应由随后 exact source 的 macOS CI 和画面填实，不能提前写成全部验收通过。
2. **有明确方案、继续自主完成的项目：** 最终 helper profile 差异与回归收尾、exact source／pin 核对、组合 CI、有效原尺寸 PNG 和 MOV 的重新取得及独立审美审查。代码可以自主修的问题不得仅转成创始人待办。
3. **平台／真人条件尚缺的项目：** 真实桌面、真实截图流程、人工物理鼠标、多屏及 Spaces 等接受标准。持续明确 NOT_RUN 和恢复条件，不以软件事件、合成图、CI 截图或源审查冒充真实通过。

**精确对象确认栏：待 root 提供冻结 source commit 与 tree。确认消息将另行给出，CI 与视觉结论分别记录。**
