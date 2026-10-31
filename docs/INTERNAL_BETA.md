## Feedback v0.1 最终云端结果 · 2026-10-29 15:39 UTC

**真实服务接收、D1持久化、三条唯一私有Issue投递、原Issue迟到协调与远端测试反馈删除已验证。真实Riftlet原生窗口端到端仍NOT_RUN。** 3个Issue经完整列表/正文核对后由owner永久删除；同一有权限连接确认3条精确Issue均410 Gone/deleted且完整state=all列表为空。经独审后的精确D1结案确认8行deleted、正文0、待删0、临时probe0、额度100/20；三条原凭证GET最终200/原ID/deleted/durable=true，语义断言3/3通过。

诊断反馈的实际创建→uncertain→原Issue迟到协调且删除意图保留有直接证据；没有直接捕获诊断请求HTTP201或注入分支踪迹，不能补称抓包通过。D1 Time Travel实读过去7天（未restore），在线清空不保证可恢复历史或物理备份即时删除。

两处Workers不支持的redirect:error已改manual，新增3项在旧源码失败、修复后24项本地回归通过并经非作者审查。Receiver最终39f6277e-11f2-455b-be27-8f0b6a795685；普通Delivery最终3c749b91-ace3-45d9-86e5-62e2dab06c35，临时变量/逻辑和probe表已清理。

云端终态已通过独立启用门禁，**本轮源码的Host已实际配置固定真实HTTPS接收地址**，只改原nil那一行，其他Host字节不变；配置不等于任意单条反馈已经接收/投递。最终准确源码、实际CI和对应统一App下载以[正式工程定值元数据](../engineering/evidence/2026-10-29-final-product/results.json)及[PR #1最终交接](https://github.com/haohongfei2001-png/Riftlet/pull/1)为准。历史H `2f308856…`完整ARM/Intel/Feedback已通过（49唯一Feedback/21服务），其local-outbox-only包不能冒称本轮新启用包。用户将真实Mac连接/操作留给Codex；清单已准备、未安排执行器、不要求本轮用户安装。

[准确云端版本、ID/Issue、删除证据与运维](../engineering/evidence/2026-10-29-feedback-cloud/README.md) · [准备给Codex的真实Mac验收](../engineering/evidence/2026-10-29-feedback-cloud/CODEX_REAL_MAC_E2E.md)。早先断连、资源未建、测试记录待删均已成为历史，不是当前外部授权阻塞。

## 以下为既有工程与包的历史检查点

旧SHA、下载、能力与阻塞只属于各自当时版本；最新交付以顶部/正式最终包身份为准，不改原始测试结论。

## 2026-10-29 Feedback 可靠性更新

当前统一 Beta 包含已审查的反馈可靠性修复。源码 `7ef6cd4b` 的完整 macOS15 Native/Feedback CI 已通过，实际 arm64/ad-hoc 安装包已下载并核验。正式工程后继、准确下载入口和校验值以 [PR #1](https://github.com/haohongfei2001-png/Riftlet/pull/1) 最新交接为准；整包仍包含 App、明确的内部候选启动入口、使用说明和构建清单。

反馈可保存草稿、预览自愿诊断、管理和取消本机待发送记录，但 Cloudflare 尚未部署、endpoint 为空，仍不能真实发送给开发者。既有截图行为、准入及数据根保留。这不是云端端到端交付完成，也不是已公证的公开发行版。下方旧下载与 SHA 均保留历史身份。

---

# 统一内部 Beta：体验修复 + 真实快吞噬 + Feedback v0.1

**本轮交付完整原生 App，供创始人开始真实使用体验。** 唯一正式分支仍是 `codex/engineering-foundation-20261027`；[PR #1](https://github.com/haohongfei2001-png/Riftlet/pull/1) 保持 Draft，不合并 main、不公开发行。准确最终正式 SHA、两项 macOS CI、实际下载制品及其 SHA-256 固定在 PR #1 最新集成交接，不能用旧来源 CI 代替组合 CI。

## 来源与集成纪律

| 来源 | 固定提交 | 本次处理 |
| --- | --- | --- |
| 本轮正式基线 | `b4bcfa41e8e237723b975d2a9a0059e955fa0c1f` | 已含 H 证据及 Feedback；不重复合入 |
| Codex 体验修复 | `fa74f3c68f05ab4eaccfc24e2f39c0177289ddb3` | 基于 e421 的八文件 App/UI/helper/测试最小修改 |
| 最终证据交接 | `8e1a1688e75db8c18965e073ae357010e7397a3a` | fa74 的直接子提交；八份脱敏证据原样继承 |
| 已有截图与真实证据 | `e421e668` / `c177174` | Core/Capture/Adapter/SQLite/资源/准入与 H 证据不变 |
| 已有 Feedback v0.1 | `f195bebbc22ed1a162b5866ca1fe6c7ccb9835b9` | 模块、Host、测试、服务与 Package 完全保留 |

本轮独立 worktree 从正式 b4bc 开始，按共同祖先 e421 合入 8e1，保留双方父节点与全部历史。Main 两处冲突逐块处理：selection catch 保留 owner/visibilityRevision 保护、`ProductStatus.clickFeedback(error)` 及原 selectionRejected 诊断；render 后保留 prepared/cancelled 展示及原 assets/operations/uiProjectionDeferred 诊断。其余七文件与 fa74 精确相同，Main 相对 fa74 仍只是原 Feedback 的 **20 行新增、1 行替换**，没有整文件覆盖。

`scripts/verify-internal-beta-integration.py` 保留原保护并核对 b4bc/fa74/8e1 真实祖先、获准文件精确对象及已审 Main。未批准的同目录文件仍逐对象固定；H、UX 证据与 Feedback 继续精确固定，CLI 无来源覆盖参数，CI 审计必跑。原 ApplicationMode、Info.plist、准入、SQLite v3、权限恢复、原点击、FIFO 调度、动画及后台观察没有重写。详见 [本轮集成记录](../engineering/evidence/2026-10-28-beta-ux-integration/README.md)。

## 这版实际改善什么

- 后一张原点击被接受而尚在提交队列时，提供“已接收，正在等待附加”；prepared 用中性“附加处理中”，不把可能已推进的输入误说成尚未上传。
- 取消、超时、原草稿变化和点击时页面尚未完成验证各有准确说明。异步提示受原选择 owner、visibilityRevision 和 operation 身份限制；未知原因不暴露原始错误、不授予重传。
- tooltip、辅助功能标签与帮助同步；按下/AXPress 清旧提示，清理旧阶段时保留较新的取消说明。当前主要通过 tooltip/辅助功能呈现，没有新增持续可见的排队徽标。
- 支持说明与已准入范围一致，不再显示“开始与完成均待准入”的过期文字。

没有改变上传速度或动画。约 2.72 秒仍是旧 H 的点击到原窗口消失，约 127 ms 是其中动画段，无 ACK 冷首击仍会安全拒绝。组合 CI 和交付完成后，优先创始人正常体验，不要求重做 H 上传验收。

## 已归档的真实快吞噬

[原始 H 脱敏证据](../engineering/evidence/2026-10-28-system-screenshot-swallow/README.md) 记录运行 **e421e668** 的一次新系统 PNG 操作：1652×1010、1,789,589 bytes、RGBA8 非交错；1 begin / 7 chunks / 1 commit，页面 input 与独立 change 各 1。原 effective ACK 在点击前约 35.635 秒，属于预绑定场景。

同一原进度节点 4.7100724% → 9.4201448% 给出严格开始，唯一 `upload_starts` 与原身份相符。AppKit 实际动画段约 **126.964 ms**；本例点击至 WindowServer 首次确认三个原窗口全部缺席约 **2.72 秒**，两者不能混称。后台独立原附件 proof 之后 SQLite 为 `succeeded/used`，可见性保持 `swallowed/reason=uploadStarted`、revision=1，没有第二次动画。

独立显式 sRGB 比较 **6,674,080 个 RGBA 通道零差异**；正文 48 字符、8..11 非折叠选区和一张旧附件在记录检查点保留。A/D/F 原身份、attempt、UNKNOWN、锁、旧 checkpoint、补偿与媒体保留；只读观察字段的变化由原报告明确披露。

本轮非作者审阅公开包、Git 和相关源码；原 `native_gui` 审查曾读取私有原图/SQLite/完整身份。本轮不声称重新取得私有证据或再次上传。**SC-INPUT / SC-START / SC-COMPLETE / SC-UX 为该新 H 的软件 CGEvent 限定 PASS；人工物理鼠标 NOT_RUN；无 ACK 冷首击未解。** 这不等于组合 Beta 的新真机验收，也不是全面发行通过。

## 创始人安装与启动

下载最终完整 CI 的 **`Riftlet-Internal-Beta.zip`**，不要将离线 Feedback Demo 当作此 App。解压后目录包含：

- `Riftlet.app`：完整原生截图与反馈 App。
- `Start-Riftlet-Internal-Beta.command`：本包明确的内部候选启动入口。
- `README-zh-CN.txt`：首次安装、权限、反馈和边界说明。
- `build-info.json`：精确 source head、实际 CI checkout、架构、构建/测试输入对象和包内摘要。

将整个目录放在固定位置，保持这些文件相邻。不要覆盖反馈作者或其他工作树的 App。已有旧实例先通过自己的菜单正常退出，保留全部数据。

**双击 `Start-Riftlet-Internal-Beta.command`。** 它会打开终端再用系统 `open` 启动同目录的完整 App，唯一模式参数为 `--system-screenshot-candidate`；无须手写命令。确认菜单栏为 **`Riftlet REAL TEST`**。启动器不重建数据、不杀进程、不改权限、不启用 trace，也不修改 App 的默认普通模式。仅双击 `Riftlet.app` 会进入只收录的普通模式；备用入口是其菜单“打开真实截图内部候选…”，随后正常退出普通实例。

本包是 ARM64 CI 开发制品，ad-hoc 签名，未 Developer ID 签名/公证；Finder/Gatekeeper 首装仍单列体验项。若系统阻止打开，在确认来源后使用系统“隐私与安全性”的正常允许流程；不关闭系统安全机制，不用清除 quarantine 的脚本。

首次使用与权限引导沿用正式实现：确认系统截图保存为文件，允许读取实际截图目录，主动检查 Chrome 自动化权限；按引导开启 Chrome“显示 → 开发者 → 允许来自 Apple 事件的 JavaScript”。没有浏览器扩展、每日新快捷键或自动发送。候选沿用原 `Riftlet-System-Screenshot-Candidate` 数据根，绝不迁移成新队列绕过旧锁。

## 体验范围

已准入：Chrome 中文 ChatGPT **普通已有对话**，原样单帧非交错 **8-bit RGBA PNG**，≤8 MiB、≤16,777,216 像素。实际 H 环境是 macOS 27.0 (26A428) arm64、Chrome 156.0.8078.73；CI 构建环境与真机证据分别记录。Home 新对话、Work、其他浏览器、ChatGPT 原生客户端、任意 PNG 编码和全部 OS 版本均未因本次集成扩张。

系统截图自动收录 → 原生裂缝/微图 → 对当前受支持草稿单击 → 严格真实开始后快速吞噬 → 后台独立成功，沿用原实现。FIFO 连续点击、内部历史、暂停、隐藏、归档及可见队列管理保持。无截图时无裂缝；无有效目标或没有开始证据时不假吞噬；最终完成不再演动画、不弹成功 Toast。

安全失败/安全重试及普通生产上传仍关闭。旧 A/D/F、H 和其他已经输入的图不重复输入，所有旧 UNKNOWN 不重传、不清除、不解锁。不得为了体验效果手补 `uploadStarted`、重建数据库或清除审计。

## Feedback v0.1

同一候选菜单中的“反馈与建议…”提供问题/建议文字、草稿保存与关闭重开、主动勾选诊断及可选提交前预览、本机记录、取消和删除流程。原实现使用独立 `Feedback-v01/feedback.sqlite` actor/连接/文件锁、Keychain 凭证和最多 64 条白名单诊断；不打开截图 SQLite writer，不自动采集原图、聊天正文、路径、hash、浏览器会话或原始 trace。用户主动输入的反馈正文是本地草稿/报告的正常内容。

**当前 endpoint 仍为 nil；没有部署 Cloudflare、创建 D1/Worker、配置私有 Issues 目的地或购买服务。** 点击“发送反馈”仅入本地 outbox，状态是“已保存在本机，等待服务接收”，attempts=0；不表示开发者已收到，不显示云端提交成功。服务与投递源码完整保留，实际云端端到端仍 NOT_RUN。

诊断 hook 只采样已有 capture/状态/可见性/phase 事实，不请求新目标、不更新 ACK、不改变吞噬或队列、不引入另一个上传状态机。真实 Keychain 权限、物理关闭重开/IME/VoiceOver 和点击延迟对照仍需在产品体验中准确记录，不由软件测试代签。

## 本地 Codex 与产品体验检查点

无需重跑已经完成的 H 验收，也无需修改上传机制。用 PR #1 最新交接固定的精确 SHA 建立独立 worktree；保留所有旧工作树、候选数据根、媒体/WAL/审计和反馈作者 App。构建入口：

```bash
bash scripts/build-macos.sh
bash scripts/package-internal-beta.sh
```

这将生成与 CI 相同结构的 `build/Riftlet-Internal-Beta.zip`。开发调试仍可直接使用原命令 `./build/Riftlet.app/Contents/MacOS/Riftlet --system-screenshot-candidate`；仅在需要且妥善保管私有日志时显式加入原 `--acceptance-trace`。

创始人体验检查点：正常首装/权限、自动收录、一次点击、原快吞噬/后台成功、FIFO/历史/暂停隐藏，以及反馈草稿关闭重开和本地待发送。新体验只使用愿意附加的**另一张全新系统截图**；这不是重传 H/F 或重复验收要求。无 ACK 冷首击、物理鼠标、多屏/全屏/Spaces、自包含、异常安全失败/重试、发行签名公证和云端反馈是剩余质量工作，出现问题应记录实际事实，不通过补证据或清库“恢复”。

后续正式开发以真实使用体验、可靠性和发行质量为中心。当前负责人持续负责实际交接的祖先审查与组合，不重建已完成计划、不重复合历史提交，也不承诺不存在的无人值守执行器。
