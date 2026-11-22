# Build 60 持续验收记录

## 2026-11-23 · 恢复现场工作

产品源码为 `711cee3a1c7033ce4925082a83099b00da7087c6`，本轮起点为 `921c1a676b83d5a4585b9d643be300592cfb2ee3`。重新计算私有 DMG SHA-256 得到 `5a934119d6e65cbe82a62f5f208a2b95a200fa0cf170225ccd4e9016b1c0b54e`，独立安装回执 SHA-256 为 `6dd1c3b09e02b307862cc5759d83ea25f539bcf55cace1090e3539c46b775736`。ARM64 / Intel 同源 CI 均成功。PR #124 为 Draft，Issue #120 打开，公开版本为 1.0.5（31）。[签名与同包实站基线](RIFTLET_1.0.8_FINAL_RELEASE_REPORT.md) · [最终源码 CI](https://github.com/haohongfei2001-png/Riftlet/actions/runs/45045026977)

| 工作 | 已取得的证据与当前执行 |
| --- | --- |
| 原始 GUI 回执 | 已重读七次环境准备的逐次结果和独立裁决。两次 Edge 到达已登录草稿，七次都停在文件输入前。 |
| 当前环境 | 新读数显示系统前台已从 UserNotificationCenter 移到 Codex。显示器已醒、会话已解锁，验收宿主位于当前控制台用户的 Aqua 会话。只读取原生界面元数据。 |
| 浏览器验证 | 一名 GUI 执行者负责 Chrome、Edge 和专用草稿。验证正常激活与 AX/WindowServer 边界，维护唯一专窗和创建回执，等待与实站投递分别记账。 |
| 持续监督 | 在独立检出开发只读监督器、状态变化记录、持久化任务状态和对实际验收入口的串行调度。 |
| 恢复审计 | 复核原生点击、持久化记录、页面、界面和双快照验证，三个真实故障库各自复制后验证。 |
| 发行准备 | 在独立分支演练合并树，核对官网、签名更新源和应用内更新流程，准备双语发行说明。 |

当前没有需要用户执行的操作。状态变化后只在 PID、原窗、原标签、可见性、前台、登录、编辑器及上传入口同时得到实证时开始对应站点验收。待完成的发行门槛为同包 G1/G2、G4-C、G4-A 或经独立裁决的 G4-B、正式准入、合并、公开分发及升级验证。

## 05:56（上海）· 封存库和恢复链

三份独立的 build 59 故障库副本均完成了输入前取消、进程重启、显式新选取、一次受控附加、唯一 START 和迟到回执检查。每份原库重新计算的 SHA-256 都与封存值一致。已检查七个组件和十五项断言，逐项标明源码、SQLite 或无界面网页证据。签名 App 的实站 G4-C 仍待执行。[逐项审计](evidence/build60/recovery-architecture-audit.md) · [三组双快照哈希](evidence/build60/recovery-architecture-audit.json)

Edge 两次只读观察读到同一已登录专用草稿可见并聚焦。紧接投递前，前台回到 UserNotificationCenter，当前 Space 两款浏览器的可见 WindowServer 窗口均为零。对话框的用途未得到确认。验收尚未因此产生产品点击或文件输入。QA 监督器已由当前 Aqua 会话的 launchd 启动，初始状态只读。恢复后继续使用原创建回执、相同原草稿和独占 GUI 锁。目前无用户操作。

## 05:58（上海）· HTTP、系统大图与正式发行准备

C2 已从自有的非激活窗口取得 macOS 系统 PNG。它带有系统截图标记，2880 × 2816 像素、23,233,638 字节，九个中心像素样本相符。捕获前后的前台 PID 一致，原图保存于私有验收库。后续由同包实站测试记录实际输入字节、唯一请求、HTTP 状态和原卡变化。C1 的本地原生 XHR 对照观察到未过期时 201、自然过期后 403，并核对服务器收到的全文件。历史网站回执仅有上传地址摘要，仍没有当前上游授权期限。[C2 原图收据](evidence/build60/large-system-screenshot.json) · [五组 HTTP 对照](evidence/build60/http-expiry-control.json) · [OpenAI 单图限制](https://help.openai.com/en/articles/8555545-uploading-files-and-audio-to-chatgpt)

发行预备分支已从实际 main 核对至冻结产品源码。预演合并树与签名源码树完全一致。对当前公开更新源与 1.0.5（31）下载包分别复验 Ed25519，官网两处下载入口指向该包。独立签名更新工具回归 11/11。正式放行依赖 G1、G2、G4-C、G4-A 或取得独立裁决的 G4-B，以及适用于该主线差异的非作者准入。当前不需要用户动作。[发行树和签名检查](evidence/build60/release-preparation.json) · [双语说明草稿](RELEASE_NOTES_DRAFT.md) · [预备分支](https://github.com/haohongfei2001-png/Riftlet/tree/codex/release-1.0.8-build60-staging)

### 门槛通过后的发布次序

1. 在预备分支复核实际 main、冻结源码和候选树，取得非作者原文审查，用直接子提交仅写入准入文件。运行 `python3 -B scripts/verify-mainline-composition.py HEAD`，在正式 PR 上核对原生、双架构及反馈检查和两父合并树。合并后再核对真实 main 的父提交和 push CI。[正式主线规约](../../MAINLINE_GOVERNANCE.md)
2. 对已进入 main 的受审发行提交创建正式标签。发行归档采用签名公证回执中的原 DMG 和同包 SHA-256。发布前先用 `gh release create v1.0.8 --verify-tag --draft --notes-file "$notes" "$archive" "$checksums"` 准备完整草稿，核对附件后将其发布为不可变 stable Release。用于对外的双语正文取自审定后的说明。
3. 在冻结签名工作区运行 `RIFTLET_APPCAST_GH_AUTH=1 python3 -B scripts/release-appcast.py prepare --tools "$sparkle_bin" --workspace "$signed_workspace" --output "$new_feed"`。更新源要求标签位于 main，且相对已签名源码只容许准入文件差异。官网和生成的完整签名 XML 走常规 PR，复核 Pages 实际字节与现行支持矩阵。[Sparkle 发行流程](../../release/IN_APP_UPDATES.md)
4. 在官网和 stable feed 生效后，运行 `python3 -B scripts/release-appcast.py verify-public --receipt "$signed_workspace/formal-dmg/dmg-receipt.json"`。独立下载、安装并验签，另用隔离的 1.0.5（31）副本操作实际应用内更新并核对库与版本。

## 06:07（上海）· 同一草稿经过截图仓库的恢复路径

三组受控恢复已进一步将网页实际返回的 attachmentID、START evidenceID 对应到同一次 Core 写入的 SQLite 记录。每组原操作与新操作各有一次文件输入和一次 change，均无发送或提交。[对照结果](evidence/build60/recovery-architecture-audit.md)

Aqua 监督器已在独占锁下实测运行。初始只读进程完成一轮两浏览器有效采样，识别到宿主指纹变化后拒绝使用旧版本。最终宿主通过 16 项调度控制与 6 项宿主控制，启动后连续两轮观察到不满足真实投递条件，已确认零输入登记。[监督器及运行方法](../../../Tests/PreClickLease/g4/supervisor/README.md) · [原生前台回执](evidence/build60/gui-diagnosis-foreground-return.json)

整树非作者审查随后发现截图仓库会激活 Riftlet，而冻结网页程序在浏览器失焦时退休写凭据。回到原文档后，新点击取得的 draftGeneration 与旧 UNKNOWN 的严格比较可能冲突。监督器继续读取环境，build 60 的新投递已暂停，原操作与专窗保留。正在对冻结网页程序复现失焦、返回及显式重选。若证实缺陷，下一候选须重新绑定新的源码、DMG、公证、独立安装和整套站点证据。用户无须操作。

C1 的只读观察器可以从单个已完整归属的正常请求中投影经规范确认的过期时间。历史实站回执仅保留 URL 摘要。当前完成本地对照，真实 PUT 与实际响应继续由对应候选的站点收据决定。[C1 读数、测试及适用范围](../../../Tests/PreClickLease/g4/expiry-observation/README.md)

## 06:13（上海）· 已确认产品缺陷和独立宿主权限

非作者在冻结程序上用两款真实无界面浏览器的本地隔离页面验证了正常焦点切换。具名错误卡和无卡 UNKNOWN 各测两款浏览器。四次持续前台对照都取得新输入；四次经真实失焦并返回原编辑器的样本均在新输入前被 `TARGET_INVALID` 拒绝，原 Document、navigation entry、form、编辑器和附件均相同。截图仓库的正式入口会将 Riftlet 置于前台。build 60 停止发行，最小修复转入 build 61。所有同包结果将重新取得。

注册 Aqua 服务也已从其实际父进程读取无提示权限查询。会话已登录并解锁、显示器已醒、该执行者有 Accessibility 权限。它向普通 Chrome 和 Edge 发送 Apple Events 均需用户同意。前台是 UserNotificationCenter 的 AXSystemDialog，AXModal 为 false；两款浏览器都有基础窗口，当前可见普通窗口均为零。已记录的系统界面元数据无法确定对话框用途。这份回执描述后台 QA 执行者的权限。下一步是生成新候选、在正常已授权原生上下文比对窗口证据，使用该候选的独立安装和全新专用草稿继续。未要求用户操作。[注册进程现场数据](evidence/build60/registered-aqua-supervisor.json) · [Apple Accessibility 信任查询](https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions)

完整的非作者源码审查结论为 `CHANGES_REQUESTED`。报告固定了实际 main、build 60 源码和树，逐项核对 437 个变更路径，保存了 8 个本地真实浏览器对照。该源码不会进入正式准入。独立的当前交互任务随后用同一只读二进制查询 Chrome 和 Edge，两个目标均返回 `ALLOWED`；此前后台 Aqua 服务则均返回 `CONSENT_REQUIRED`。两者的 AX 检查均已通过。当时两个执行上下文都观察到同一个系统前台窗口。后续同包实站可由当前已授权的普通执行入口在桌面自然恢复后处理。[build 60 非作者原文报告](evidence/build60/mainline-nonauthor-review.json)

## 06:20（上海）· Build 61 源码冻结

正式候选切换到 1.0.8（61），源码 `49b9204974088c1983cda469910d9a78d8f4c43b`、树 `70ba40e23a3afa3561525b1943cb0e5ebc825de5`、网页资源 `2f6e2f6e1d80184813f6f967cc340638b96082abd5bd98c2f9e97b0597f982f2`。现在只有仍能连续证明原 Document、form、编辑器和路由的已输入 PNG 才能延续原草稿代号。失焦前取得的旧写票仍永久失效。build 60 已签名页面的只读观察指纹已随候选封装。[产品修复](https://github.com/haohongfei2001-png/Riftlet/commit/49b9204974088c1983cda469910d9a78d8f4c43b)

真实无界面 Chrome、Edge 的本地受控测试覆盖具名错误及 UNKNOWN，各自包含 START 前后两条分支。每个程序配置均观测到 56 次 setter、56 次 change、零发送，模式、编辑器或路由发生变化时拒绝写入。非作者另外重跑原 8 组，四个失焦场景均恢复到新输入一次，额外八次旧票写入均被拒绝。开发 App 构建通过，安装包校验器 24 项通过。该 Mac 只有 Command Line Tools，本地 XCTest 编译缺少 XCTest 模块；完整 Swift 套件正在两台正式 Xcode CI 运行。签名、公证、独立安装、G1/G2 和 G4 均按新 SHA 单独取证。[受控测试回执](evidence/build61/controlled-focus-recovery.json) · [双架构 CI](https://github.com/haohongfei2001-png/Riftlet/actions/runs/45077012085) · [同一 QA 二进制的权限对照](evidence/build60/gui-diagnosis-execution-context.json)

下一步在正式 DMG 完成后核验其 SHA-256、公证回执与独立安装，绑定本候选专用的浏览器任务。现有交互宿主对两款浏览器都有已生效的权限，真实投递还需要当前桌面有可见的原窗口并同时满足全部站点身份检查。目前无用户操作。

## 06:25（上海）· Build 61 同包工程结果

已从冻结源码生成一个双架构 Developer ID DMG，14,133,998 字节，SHA-256 为 `31df54cdc036dd67da3369eef9b9a4d130db67540fe5973920834b6c6a65d92e`。Apple 对 App 和 DMG 接受公证。独立执行者只读挂载，完整复制后比对安装树、两架构代码签名与网页资源，9/9 项签名、staple、Gatekeeper 与程序自检通过，卷已卸载。[签名及 DMG 收据](evidence/build61/signed-candidate.json) · [独立安装回执](evidence/build61/independent-install.json)

完整网页回归 384/384，Chrome 和 Edge 各自的凭据 19/19、图像预览 22/22，受控传输故障 8/8。真实编译的本机兼容模块与 build 56–60 原页面的 15 组历史标记一致。只提交脱敏收据，原 PNG、SQLite 和签名包均保存在私有验收目录。双架构完整 Swift 结果和网站输入单列跟踪。[本机回归](evidence/build61/local-regression.json)

## 06:36（上海）· 正式合并候选与私有证据封存

ARM64 与 Intel 两个独立 Actions 产物均解包核对，Swift 测试各 1,436 项通过，网页程序摘要与独立安装版本一致。非作者完整复核实际 main 至冻结源码的 483 个变更路径和 48 组浏览器对照，书面通过。G 的直接准入子提交 H 为 `fe34c3dbb3f7ba00a116612d720003f540739cf5`。正式 Draft PR #125 的预合并提交 `10ad18831eb356e455401bf26befa5780b6859d0` 由实际 main 与 H 依序组成，树等于 H。原生和 Feedback 的源码准入检查已通过，其他正式 PR 检查继续运行。[双架构产物](evidence/build61/dual-architecture-ci.json) · [完整非作者复核](evidence/build61/mainline-nonauthor-review.json) · [正式 Draft PR](https://github.com/haohongfei2001-png/Riftlet/pull/125)

本次重新从三份 build 59 故障库创建独立副本，用冻结 build 61 在本地原生浏览器内核重走恢复。三次均保留旧 UNKNOWN，新增唯一显式输入及持久化 START。已私有封存 56 个逐件复算的文件，含 6 份 SQLite 一致性备份和 3 份 PNG。私有清单 SHA-256 为 `4c56a993fa1cc5366e819dc65517cab8a8264ff38cb43dd10b56b3bab5855fae`。本次亦用独立安装验证 build 61 与已发布 build 31 的更新源、签名要求、公钥、最低系统版本相同，实收官网和 stable feed 均指向 1.0.5。[原库与恢复核对](evidence/build61/archived-recovery.json) · [发行路径验证](evidence/build61/release-preparation.json)

唯一实站执行者已在原 GUI 锁内移交到新验收驱动，原执行者的实站窗口创建和产品投递计数均为零。新驱动将原卡观察延续至用户重新选择和第二份数据库快照，也允许本轮已验证的 20–30 MiB 私有系统截图经产品通道进入大小测试。两款浏览器 Apple Events 已授权。前台仍为用途无法确定的系统窗口，两款浏览器的屏幕窗口和 AX 窗口数均为零。下一次桌面恢复时，同一执行者先执行 `edge/g4c`，再执行 `chrome/g1`、`edge/g2` 和单次大小实验。核验正式集成检查的命令为 `gh pr checks 125 --repo haohongfei2001-png/Riftlet`。待取得真实 G4-A 或获准 G4-B，以及 G4-C、G1、G2 后再进行发行独立复核。当前无需用户操作。[实际交互宿主回执](evidence/build61/gui-execution-checkpoint.json) · [发行报告](RIFTLET_1.0.8_FINAL_RELEASE_REPORT.md)

## 06:40（上海）· 可复现的实站执行环境

传入验收入口的源码与 DMG 摘要均已固定。已将私有执行器、正式 DMG、独立 App 和所需工具封存至用户私有档案，重新读取了归档的 452 个文件及 9 个 App 软链接。归档共 140,464,841 字节，SHA-256 为 `9dcdd64485b278d0e091704fc39ffcd5ad526d29d75cf24f19af40f51f5f4725`。现有执行者负责按原收据续查，每一轮按实际桌面重新核对准入条件。该执行者是唯一已授权的交互入口。

宿主当前读到 Stage Manager 的全局偏好为关闭。单独的屏幕采样、AX 读数和这个偏好仍不能定位其他应用的窗口所属 Space。用户会话已解锁，当前授权充足，原窗在屏上可见并具有焦点仍是必要外部条件。单个交互执行者已经运行，常规恢复路径由它自然触发；如原进程已退出，唯一执行者先核对持久 claim、原页与 SHA，再使用私有归档记录的 `staged-v2/interactive --source 49b9204974088c1983cda469910d9a78d8f4c43b --dmg-sha256 31df54cdc036dd67da3369eef9b9a4d130db67540fe5973920834b6c6a65d92e`。当前无需用户操作。[私有封存与桌面偏好回执](evidence/build61/issuer-custody.json)
