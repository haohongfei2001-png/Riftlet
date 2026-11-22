# Riftlet 1.0.8 最终候选验收

**总体 PARTIAL。** 当前唯一网站验收候选为 build 59。冻结产品提交 `69b76cb025ab552b3480e3af095b627891874712`，树 `7289c35504d9a2a27b82e240fafe175b4779dd16`，页面 SHA-256 为 `b6eee615982d839285ea6af4abb16018939f9be91b18215554e847f4a6eb2215`。#120 保持打开。

| build 59 同包项目 | 状态 |
|---|---|
| G1 普通 Chrome × ChatGPT | PARTIAL。冷、暖首图与旧附件保留通过。两秒内双图为 0/3，唯一完整双图用时 2.508 秒。非空原文和选区尚未实测。 |
| G2 普通 Edge × ChatGPT | PARTIAL。冷、暖首图、旧附件保留和三组两秒内双图通过。带非空原文和选区的实站用例尚未执行。 |
| G4 原卡明确失败、原图找回、显式新点击 | NOT_RUN |

同包实站共核实 17 张独立系统截图，Chrome 7 张、Edge 10 张。每张均有原草稿的 input、change 和唯一 SQLite START。所有已核对草稿的发送按钮点击、表单提交均为零。这里的 START 表示原附件已被草稿接收，服务端最终完成另有判据。[逐图独立复核](evidence/build59/independent-final-pairs.json)

## 11 月 22 日同包复验

本轮继续使用已签名、公证的 build 59。普通 Chrome 和 Edge 主进程均通过厂商签名、标准路径、内核路径与唯一进程出生身份核对。Chrome 控制器列出了归属本轮的 Temporary Chat 标签，读取 DOM 和截图均返回 `Debugger unattached`。原生窗口与原编辑器未能完成关联，关闭请求也未取得确认。Edge 进程存在；控制器列表没有 Edge，按名称创建临时页也报告不可用。两款浏览器均在填写草稿和投递前停止，本轮实站文件输入为 0。未操作个人对话或账户菜单。[本轮浏览器预检](evidence/build59/temporary-chat-access-recheck.json)

### Chrome 完整双图的时序

下表以首张 AppKit 鼠标事件时间为零。宿主时钟采用 macOS uptime，页面 input/change 采用原文档时钟。日志能确定 setter 在原生 commit 调用区间内执行，以及 input 到 change 的时差；精确的 setter 进入时刻未单独采样。[两款浏览器的四组逐图时序](evidence/build59/rapid-pair-timing.json)

| 同一 Chrome 草稿 | 第一张 | 第二张 |
|---|---:|---:|
| 托盘原行命中与像素核验（ms） | −3161.094 | −2192.745 |
| 点击凭据 ACK（ms） | −4262.350 | +1434.973 |
| AppKit mouseDown 事件（ms） | 0 | +2507.972 |
| AppKit 回调（ms） | +84.732 | +2625.378 |
| 原生 commit 调用区间（ms） | +575.591 至 +821.785 | +3143.789 至 +3371.636 |
| 宿主收到 setter 已进入、change 已返回的回执（ms） | +824.591 | +3374.616 |
| 页面 input → change 耗时（ms） | 5 | 4 |
| 原卡 attachmentAccepted 回执（ms） | +2208.680 | +4743.239 |
| 托盘收起动画起止（ms） | +2212.132 至 +2338.971 | +4745.546 至 +4871.831 |

第二张原行在首击前已可命中，凭据在首击后 1.435 秒就绪。验收器在 +2487.889 ms 完成第二张的最后一次行取样。首次原卡回执到收起动画开始相隔 3.452 ms，动画持续 126.839 ms。原日志没有把两次按下之间的每段调度等待分别计时，因而不能从 2507.972 ms 倒推出产品本身需要等待多久。Edge 已通过的三组均在首张收起前收到第二次按下。本轮保留其 3/3 同包成绩，新的 Edge 实站回归受环境阻塞。[时钟与取样说明](../../../Tests/PreClickLease/native/README.md)

### 非空选区与旧卡

实站判定仍为 Chrome、Edge 均 **NOT_RUN**。验收器已在两个隔离引擎的 contenteditable 编辑器中分别校准正向和反向选区。两端都使用安装包里的页面资源，以已成功附加的图为旧附件，录入固定 QA 原文，通过 Shift 加方向键选中第 12 至 40 个 UTF-16 偏移间的文字。第二次附加前后，原文、选区文本与方向、anchor/focus、编辑器、草稿代际及旧卡成员逐一一致。反转端点、折叠选区及用相同内容的克隆替换旧卡的对照均被识别。原来的 22 个改名预览回归在两款浏览器也分别通过。[选区原始结果](evidence/build59/controlled-nonempty-selection.json) · [验收器运行方式](../../../Tests/DerivedPreview/README.md) · [非作者独立重测](evidence/build59/independent-selection-review.json)

### 包、CI 和网页回归

从只读 DMG 独立安装后，App 和 DMG 均通过 Developer ID、Gatekeeper 与 staple 验证。安装的二进制包含 arm64 和 x86_64，三项本机自检在 ARM64 上通过。独立复核重新下载了冻结产品提交的两份 CI 归档，核对 ZIP 散列、每个架构的 1,434 项 Swift 测试，以及与签名 App 一致的网页资源。另行执行的 347 项离线测试、48 项无头 Chrome 测试、额外 4K 纹理场景以及 Chrome、Edge 各 5 项原文档测试均通过。[包与 CI 复核](evidence/build59/independent-package-ci-recheck.json) · [网页回归](evidence/build59/independent-web-regression.json)

## 普通 Chrome 的真实冷首击

从最终镜像安装的 App 在全新测试资料库启动。测试窗已核对普通 Chrome 厂商签名、进程出生、窗口、标签和账户菜单。第一张系统截图进入托盘后，验收器直接按下其原行，没有等待网页就绪。原始文档和编辑器的回执比 AppKit 收到的鼠标按下早 1,896.793 毫秒。网页收到同一份 5,516 字节 PNG，文件输入和变更各一次，发送和表单提交均为零。图片按原始 330 × 196 像素解码，原卡取得唯一 `attachmentAccepted`，托盘随后收起。鼠标事件由软件定向投递。

原验收器读取旧字段，第一次报告 `POSITIVE_START_NOT_VERIFIED`。非作者从原 SQLite 和现场页面事件读回当前字段 `attachmentAcceptanceEvidence`，核对了同一次操作、调用、卡片及原图。该图没有重投。草稿开场时没有旧附件，本次只计冷首图。[同包操作与证据哈希](evidence/build59/chrome-live-candidate.json) · [独立只读复核](evidence/build59/chrome-cold-independent.json)

在同一普通 Chrome 临时草稿继续测试时，以已成功的首图作旧附件，并逐像素核对原卡。随后五张新图各取得唯一 START。已完成的一组双图均成功附加，两个真实按下相隔 2,507.972 毫秒，超过两秒。下一组的第二张在 macOS 窗口检查阶段停止，投递标记未创建。余下两张未执行。[接续原始记录](evidence/build59/chrome-live-after-start.json) · [两款浏览器的独立复核](evidence/build59/independent-first-site-series.json)

第一次补验的全新临时草稿取得一张新图的 START。随后验收器把 macOS 对同一目录的两种路径写法判断为不同，双图均在鼠标投递前停止。已修正验收器并用原文件核验，两个旧样本都没有重放。[首次补验记录](evidence/build59/chrome-live-rapid-final.json)

最后一次补验在普通 Chrome 的另一个专窗完成进程、窗口、唯一标签和临时页核验。恢复这一测试窗后，看到了原编辑器、上传入口和已登录账户专属菜单项。关闭菜单的请求已送达，读取关闭结果时原窗已失去选中状态。随后核对仍为同一原窗口和标签，但 Chrome 当前选中了其他窗口。验收器在启动候选和投递图片前停止。引起窗口切换的原因未知。本次无需重新登录。[末次身份检查](evidence/build59/chrome-final-preflight.json) · [独立同包复核](evidence/build59/independent-final-pairs.json)

## 普通 Edge 的真实草稿

同包冷首图和暖首图均进入已登录的原临时草稿，原生凭据分别比按下早 2,468.786 和 1,090.216 毫秒。前两组快速双图的实际按下间隔为 1,517.955 和 1,574.502 毫秒。加上第三组首图，共七张不同原图，每张的原卡、完整像素、一次输入和唯一 SQLite START 均被核实。末次检查仍能识别前六张附件，整个草稿零发送、零表单提交。[逐图、逐次点击及回执](evidence/build59/edge-live-candidate.json)

首轮第三组第二张的外部鼠标投递已记录。AppKit 没有对应按下，原图仍在，数据库没有为它创建投递操作。验收进程外层的 40 秒超时终止了运行器；后续再从原网页和 SQLite 只读确认现场。此次双图没有通过。这张图没有重投。[未到达的原鼠标事件](evidence/build59/edge-unconfirmed-mouse.json)

随后在普通 Edge 的另一个已登录临时草稿中，用三张此前从未投递的新截图补验。先附加一张作为旧附件，再按下另两张。AppKit 的两次按下相隔 **582.373 毫秒**。三张各产生一次原文件输入、一次 change 和一条持久化 START，旧卡保持原节点，发送和表单提交均为零。同一安装包累计有三组合格双图，分布在两个草稿中。浏览器内原文件与预览的像素逐一相同；第二张在 macOS 与浏览器两种解码器之间的像素哈希有差异。[补验逐图记录](evidence/build59/edge-final-pairs.json)

### 原文和选区

两款浏览器的已登录临时草稿均由空白开始。现场观察确认了原编辑器及已有附件的保持。当时用于准备草稿的实机键盘验证仅覆盖隔离测试页中的一个字符。11 月 22 日复验的专用标签访问结果和受控选区校准见上文。两款浏览器这一项均为 **NOT_RUN**。受控页面的文字和选区回归单独计入同包回归。[已有键盘证据边界](../1.0.7/original-document-delivery/TARGET_DELIVERY_ACCEPTANCE.md)

## 已复现和修复的实站缺陷

签名 build 58 在两款已登录浏览器均把一次文件输入送入原草稿，随后保留 UNKNOWN。Edge 两张独立系统截图揭示原因。ChatGPT 的最终附件卡把文件显示名改为相同操作 UUID 的 .webp，图片数据仍为 PNG。第二张截图的全部像素、图片 alt 和移除按钮的哈希均已独立核实。[build 58 实站原始记录](BUILD58_ACCEPTANCE.md) · [名称和像素对照](evidence/build58/edge-converted-display-name.json)

build 59 对这一种重绘同时核对原草稿、完整操作 UUID、新卡与移除按钮的归属及图像内容。候选卡出现竞争、局部明确失败或在解码中被替换时维持 UNKNOWN。两款隔离引擎各通过 22 项受控回归，其中覆盖改名为 .webp 的附件卡。build 59 本轮实站可核对的成功附件卡显示为 .png。非作者审查已复核旧操作只读兼容、实际页面程序大小和原生轻量点击路径。[源码对照](evidence/build59/converted-source-regression.json) · [双架构 CI](https://github.com/haohongfei2001-png/Riftlet/actions/runs/44987854131)

[已登录草稿之前的原生路线与浏览器身份](PRECLICK_ARCHITECTURE.md) · [build 57 历史验收](BUILD57_ACCEPTANCE.md)

## G4 真实原卡失败恢复

已登录网站没有出现可归属到原卡的明确失败。两个本地对照标签各自到达同一测试资源。正式浏览器控制器随后在隔离校验中未返回，未能证实只能阻断这一标签且能恢复连接。没有对真实网站施加故障，没有触发旧操作重传。原卡失败、SQLite 保存该失败、找回原图及显式新点击成功附加，四步均为 NOT_RUN。受控恢复和旧版本只读续查各自保留独立证据。[同包现场限制](evidence/build59/g4-environment.json)

## 同一安装包

私有 DMG 大小为 13,775,789 字节，SHA-256 为 `666324176aadc4ffb9fd6fbfd0ca38772a169eb06394401f7abede374f7d3ee6`。App 和镜像各有独立的 Apple 公证票。另一名工程师从只读镜像另行安装，核实 arm64 与 x86_64 签名、Gatekeeper、三个旧版页面指纹及普通、网页、截图三项自检。[签名与安装](evidence/build59/installation.json) · [独立安装](evidence/build59/independent-install.json)

从同一签名 App 提取页面，在两款隔离引擎分别完成 19 项点击前凭据回归和 22 项改名预览回归。独立进程还分别读回 build 56、57、58 留下的待确认和已 START 两种状态。错误调用均被拒绝，续查没有再次输入。[原目标生命周期](evidence/build59/installed-page-results.json) · [改名预览](evidence/build59/installed-converted-previews.json) · [六个旧操作](evidence/build59/old-operations.json)

GitHub 的 arm64、x86_64 两项 CI 均在冻结提交上通过。每个架构执行 1,434 个 Swift 测试、19 项点击前凭据、22 项改名预览及 8 项离线恢复测试。原始 Actions 归档、架构与散列可逐项核查。[双架构作业记录](evidence/build59/ci.json)

前一轮已登录实站验收的两扇最终测试窗均按创建时的身份单独关闭。普通 Chrome 和 Edge 的原窗口集合与测试前完全一致，五个候选测试进程均已退出，三个本机验收监听程序均已停止。四份专用 SQLite 资料库已私下备份并核对原操作与 START。原始截图和现场收据也保存在私有验收存档中。[窗口、进程和资料归档核验](evidence/build59/workspace-cleanup.json)

## 推广结论

**PARTIAL，继续私有验收。** Chrome 尚缺三组两秒内双图。Chrome、Edge 均缺真实非空原文及选区保留，G4 缺真实服务对原附件明确报错后的完整恢复链路。已通过项固定于上述同一安装包。#120 保持打开，公开版本为 v1.0.5。[非作者逐图复核](evidence/build59/independent-final-pairs.json)
