# 统一内部 Beta：真实快吞噬 + Feedback v0.1

**本轮交付完整原生 App，供创始人开始真实使用体验。** 唯一正式分支仍是 `codex/engineering-foundation-20261027`；[PR #1](https://github.com/haohongfei2001-png/Riftlet/pull/1) 保持 Draft，不合并 main、不公开发行。准确最终正式 SHA、两项 macOS CI、实际下载制品及其 SHA-256 固定在 PR #1 最新集成交接，不能用旧来源 CI 代替组合 CI。

## 来源与集成纪律

| 来源 | 固定提交 | 本次处理 |
| --- | --- | --- |
| 已正式准入的截图源码 | `e421e6687651c2fac1441410c1af2bd5b8151e55` | 截图/Core/Capture/UI/Adapter/资源/原测试全部保留 |
| H 真实快吞噬交接 | `c177174e400064d8ec8bb79685c33d01c4e93b89` | e421 的直接子提交，仅七份脱敏证据；原样继承，不重复合源码 |
| Feedback v0.1 / PR #7 | `f195bebbc22ed1a162b5866ca1fe6c7ccb9835b9` | 保留分支祖先；完整接入原 Core/UI/Demo/测试/服务源码 |

独立 integration worktree 从 c177 开始，以保留双亲的 merge 合入 f195；共同祖先是 `4b7228a`。共享 Main 自动三方合流后相对 e421 仅原 Feedback 的 **20 行新增、1 行替换**，没有以旧 Main 整文件覆盖。`Package.swift` 与 f195 交付完全相同。原 ApplicationMode、Info.plist、准入表、SQLite v3、权限恢复、原点击授权、FIFO、动画及后台观察没有重写。

`scripts/verify-internal-beta-integration.py` 对实际 Git commit 核对三方祖先、精确目录对象、其他原 App 文件和固定已审 Main blob；不依赖可能滞后的 PR base 元数据。源反馈隔离脚本及其四项 Git 回归完整保留。本轮新增审计是这一固定组合的质量门；后续获授权改动相关源文件时，应明确更新相应来源/审核记录，不能关闭审计来掩盖覆盖。

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

同一候选菜单中的“反馈与建议…”提供问题/建议文字、草稿保存与关闭重开、主动勾选诊断及提交前预览、本机记录、取消和删除流程。原实现使用独立 `Feedback-v01/feedback.sqlite` actor/连接/文件锁、Keychain 凭证和最多 64 条白名单诊断；不打开截图 SQLite writer，不采集原图、正文、路径、hash、浏览器会话或原始 trace。

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
