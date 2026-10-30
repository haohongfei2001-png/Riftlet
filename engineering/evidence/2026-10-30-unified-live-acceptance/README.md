# 最新统一 App：真实系统截图与后续附加验收

2026-10-30。**限定上传闭环 PASS；完整草稿交互未全通过，普通生产开放不获准。**

使用最新正式 PR #1 `edbdc7aae45c35878694e9fa376757dac7b630a8` 的 CI 完整 App，在独立创建的 Chrome 测试标签、受支持的中文普通已有聊天中运行。没有接管原被占用标签，没有发送聊天消息。此交付仅归档证据，不修改产品源码、准入表、正式 PR、main 或云服务。

## 产品结果

| 项目 | 结果与范围 |
| --- | --- |
| 新系统截图→私有导入→原生微图 | PASS：三张实际 Command-Shift-4 区域截图；真实 screenshot metadata，未人工添加；只有后两张形成完整输入证据 |
| 原点击前完整 ACK／冻结／唯一输入 | PASS：trial2 与 trial3；CGEvent 经原生 WindowServer/AppKit 路由，非 AXPress、网页点击或人工物理鼠标 |
| 正向开始→快吞噬→后台完成 | PASS：两次均 begin=1、chunk=5、commit=1、page inputCount=1；同原附件递增进度；各自独立 attached，最终 succeeded/used/swallowed |
| 稳定旧附件保留 | PASS：trial3 将 trial2 的已完成附件保留，附件数1→2；这是顺序使用，非多图未决并发 |
| 正文保留 | PASS：两次前后正文一致；无聊天发送 |
| 非折叠选区保留 | trial2 PASS；**trial3 FAIL**：点击前8..15，最终0..0折叠。不能概括为草稿全部保留 |
| 编辑器未聚焦时附加 | PASS：两次点击前编辑器未聚焦；trial2后取样页面隐藏且编辑器已聚焦，不能声称整个过程保持焦点不变 |
| App 重启／旧操作不重新输入 | PASS（限定）：trial2后正常退出并重启同一正式包；恢复检查点原六个操作记录一致，只有 captureTarget/observe，无 begin/chunk/commit；随后trial3才创建第七个操作 |
| 旧 UNKNOWN／媒体／审计保留 | PASS：原五个操作身份、attempt、phase保持，旧20条checkpoint、旧start及22份媒体/捕获/日志文件逐字节保留；三个旧操作只有updated_at因只读观察变化 |
| 无 ACK 冷首击、物理鼠标、同草稿未决并发 | NOT_RUN；不由这两次预绑定成功推算自然使用成功率 |
| 真实导航 A→B→A、Chrome重启、网络异常、安全失败重生、Feedback 原生端到端、内置窗口/全屏 | NOT_RUN；本轮没有相应输入证据，不复述旧离线测试为真机通过 |

没有重传第一张或任何旧 UNKNOWN，没有补签 ACK、清库、改权限或配置。测试完成后正常退出本轮 App；新草稿与附件保持原状，未发送。原 Chrome 与其他任务标签未关闭、重载或更改。

## 精确程序、构建和环境

- 源码：`edbdc7aae45c35878694e9fa376757dac7b630a8`，结束前重查 PR #1 仍为此 SHA / OPEN / Draft。
- 已有完整 macOS CI：[41024560197](https://github.com/haohongfei2001-png/Riftlet/actions/runs/41024560197)，completed/success。没有为证据文档重复触发 CI。
- 实际下载并执行 arm64 artifact `12963810366` 的完整内部 Beta；manifest sourceHeadSHA 为上述正式源，CI checkout 为 `9b6063677672f2af6d9c9f0adf4ce115fa238385`。
- 可执行 SHA-256：`baf5643d32f3eacc7c7d4ebd590c3d4aecbad70604fca8f627bb1bcc2faf4646`；打包页面程序 SHA-256：`9b04975b7ee41a0f59cfc1e1ceb47e6855dd4c43e153e9304fb1f38996432e23`。
- 包校验和严格 ad-hoc 签名校验通过；manifest的14项构建输入对象与正式源一致。带仓库参数的包校验因本地没有临时PR merge对象而不能完整运行；未伪称该路径通过。另一次本地构建成功但**未用其包进行实测**。
- macOS27.0(26A428)，arm64；已安装Chrome156.0.8078.79。测试对正常Chrome固定PID、启动session、window、自己新建tab逐项约束；另一个招聘Chrome进程未操作。
- 启动 `--system-screenshot-candidate --acceptance-trace`，实际候选原数据根，未混入普通模式。沿用原候选数据时自动导入4张backlog，均未点击；资产数11→18，包括本轮3张新截图，操作5→7。未为消除锁更换数据根。

## 三层证据和时间链

公开数值见 [results.json](results.json)。原完整目标、asset/operation/attempt、hash、附件节点、源文件、数据库及日志保存在私有证据中，以 [private-evidence-sha256.json](private-evidence-sha256.json) 固定，不在公开仓库上传。

| 时段（从原mouseDown起） | trial2 | trial3 |
| --- | ---: | ---: |
| 点击前有效ACK领先 | 37,665.413ms | 291.201ms |
| AppKit吞噬开始 | 3,004.036ms | 1,930.870ms |
| AppKit close callback | 3,129.365ms | 2,055.489ms |
| 动画callback间隔 | 125.329ms | 124.619ms |
| 最终成功持久状态观察 | 8,147.526ms | 4,844.796ms |

这些是单次软件控制样本，不是性能分布或优化前后对照。`pixelPresentationMeasured=false`：close callback不是精确 WindowServer 像素消失时刻。trial3后窗口列表确认原输入窗口缺席，但没有连续采样其首次缺席时间。SQLite trace也明确是持久提交后的观察上界，而非精确commit时间。

点击条件是新截图完整导入、正确微图可见可定位、原测试草稿前台且预备数据齐全；驱动不等待armed=true。此流程含安全内容检查、基线采样和窗口定位，**不是未经准备的自然人工首击**。所有原事件时间原样保留，未以晚到回执回填。

每次系统区域手势后的15秒检查没有完整PNG，随后约60秒后观察到完整文件及导入（观察上界，不是精确的首次创建时刻）。T0实际捕获完成与T2首次可点击未测得，不归咎于watcher、不以推测补齐时间。全局点与缩放、实际down/drag/up、按键与修饰键释放留在私有驱动日志；未更改用户截图保存习惯。

## 内容证明及解码范围

两张原系统PNG分别1,167,012和1,167,115字节，702×482，非交错RGBA8；原件与私有副本字节SHA一致。页面最终图像loaded、尺寸匹配、原附件身份匹配；产品分别取得当前严格attached证明，独立于uploadStarted。

额外只读验证：将原文件仅解码到离屏图像（**未设置input、未派发change、未再次上传**），在Chrome用显式sRGB OffscreenCanvas与同一页面预览比较，全部1,353,456个RGBA通道完全一致，hash见results。解码scratch已删除。

同时保留一个不同结果：原生ImageIO显式sRGB/premultiplied RGBA解码的原图与页面预览hash不一致；Chrome解码原图hash则与Chrome预览、ImageIO解码预览hash相同。这将差异限定到原图的不同解码/色彩转换路径，**不把跨解码器不一致抹掉，不宣称服务端原文件字节保真**。产品现有浏览器sRGB严格相等判据没有放宽。

trial2还保留一个`errorOrInvalidated`首观察槽；该槽本身无发生时刻或细分原因，不能据此构造时间顺序。最终成功不回滚、旧操作不重新输入；不将其省略或称为安全失败证据。

## 未通过项与最小后续

**trial3选区折叠是实际体验FAIL，但根因尚未唯一定位。** 前后文本/HTML/聊天路径不变，前后页面可见且聚焦，编辑器均未聚焦；范围由8..15变为0..0。现有事件没有记录setter前、change后和selectionchange的原节点/用户事件代际，无法确定是原生点击、ChatGPT处理器重绘还是中间交互造成。

独立审查确认页面commit路径没有选区快照/恢复，但这不足以批准无条件异步恢复，后者可能覆盖用户后来的选区或另一个草稿。本轮不凭猜测改生产代码。最小后续仅是给现有测试路径补齐上述几个因果取样点，确认注入副作用后再做受原节点、目标和用户事件代际约束的最小修复；不重建传输、不重传本轮图片。

首次样本没有持久操作，且App有界trace在点击前已满；保留为**输入/路由原因NOT_PROVEN**，不能宣传成已证实的无ACK拒绝。另有两次旧windowID的驱动前置拒绝、trial3一次页面失焦的基线拒绝，均未发mouseDown/up。三张新截图/三次实际软件点击序列中，两次完整可核验成功，一次无回执；这不是人工自然首击成功率。

## 给唯一正式集成负责人

本分支只有脱敏证据，不是新产品候选，也不修改PR #1/#15。独立非作者审查见 [review.md](review.md)。可仅取本目录，不整体合入历史研究workflow或工具。

普通开放的代码差异仍需单独裁决：`ApplicationMode.usesWebAdapter`与`SystemScreenshotCandidateConfiguration`的普通`.capture`分支目前保持UnavailableAdapter；不能把候选策略整表借给普通模式。系统来源准入要维持逐原操作登记、格式/原hash/目标绑定及分别的start/completion策略；内置截图没有被本轮系统快捷键样本覆盖，应保持独立准入。safeFailure/safeRetry/Web continuation继续关闭。

本轮已证明当前统一包可完成受限系统截图附加和顺序第二张；**不支持宣布全面发行验收或普通上传开放**。下一项确切缺口是选区变化的因果定位，另保留冷首击、物理输入、真实多未决附件隔离等独立验收。
