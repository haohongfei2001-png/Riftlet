# #119 与 #122 双轨交付记录 · 2026-11-20

**PARTIAL。** #119 仍为 build 53 待验收候选。#122 已有独立开发 App、原生宿主代码和编译进产品的站点适配模块。同一正式包的核心登录组合通过数为 **0/16**。实际 main 仍为 `9fd8ad15`，公开版本仍为 1.0.5（31）。[双轨执行决定](https://github.com/haohongfei2001-png/Riftlet/pull/122#issuecomment-7033698539) · [逐格支持矩阵](matrix/results.json)

## 第一轨 · build 53

已用当前发行验证工具重新核对原签名包。产品源码 `0dc6780a`，源码审核 `f7287e05`，准入 `c7642464`。DMG SHA-256 为 `9458479641bde6147de37fda8b873507b2a312a153a76c08e166e50903583dee`。原五个 GitHub 作业均为 SUCCESS。[同包身份、验签与公证](build53-recheck.json) · [PR #119](https://github.com/haohongfei2001-png/Riftlet/pull/119)

| 项目 | 同包实际观测 | 准入结论 |
| --- | --- | --- |
| G1 Chrome | 原签名 App 的一次输入产生一次 START，页面出现对应预览。测试窗口实际落在已保存对话。文字由脚本写入，附加后未观察到其保留。 | 冷、暖首击、真实键盘文字和选区、既有卡片与三组小于两秒的连续双图仍缺少完整证据。 |
| G2 Edge | 输入返回，一张对应图片出现在原编辑器。原生记录为一次尝试，距创建 10.466 秒更新为 UNKNOWN，START 和 handled 均为零。图片为 2104 × 1652、687753 字节。 | 图片大小在 build 53 限制内。旧记录无法区分卡片归属、编码比较或回执丢失。原操作保持 UNKNOWN。 |
| G4 明确失败 | 上游已有本地恢复负例，#122 的本地网页可制造同卡明确失败并按原操作续查。 | 真实 ChatGPT 原卡服务失败、原图恢复、显式新点击到成功的整条路径仍为 NOT_RUN。 |

针对 Edge 这次 UNKNOWN，用原样本摘要核对原 PNG，在真实无界面 Edge 和冻结 build 53 网页程序上重放经审查的本地卡片。原字节预览 43 毫秒确认 START，同尺寸的浏览器重编码预览 202 毫秒确认 START；半尺寸负例观察至 2233 毫秒仍只有 inputTriggered。每例一次 setter、一次 change、零发送。该原图的尺寸和编码工作量在测得的卡片条件下可以通过。实站当时是否缩放图片、是否出现不同卡片或丢失回包仍未知。[Edge 原文件的回环收据](../../../Tests/Build53EdgeReplay/receipt.json)

先前真实会话已经确认 Chrome 和 Edge 登录。此次正式浏览器控制在连接阶段即返回 `Trusted RPC service is not configured: browser`，未进入任何个人标签。此次真实网站的新增键盘输入、附件提交及发送均为零。已将专用窗口、原生窗口和标签身份、原编辑器、真实定向键盘和旧附件的核验写入验收工具，九个隔离测试覆盖目标改变、键盘回包丢失、失焦后读原编辑器，以及测试窗口的一次性关闭和个人标签保护。历史点击仍归属历史样本。[原网站观察](https://github.com/haohongfei2001-png/Riftlet/pull/119#issuecomment-7033486754) · [脱敏 SQLite 记录](../../../docs/releases/1.0.7/evidence/build53-exploratory-store.json) · [验收工具与所需观测](../../../Tests/LiveDraftAcceptance/README.md)

恢复正式浏览器连接后，先在 Edge 新建独立测试草稿，记录原图的可见来源类型、解码尺寸、所属卡与 Remove 的关系，关联同一操作的 START。再在两种浏览器分别完成冷、暖和三组双图。G4 需要可安全观察的同一服务端附件明确失败。复用已知登录，原 UNKNOWN 只读。只有合格结果与同包经过独立准入，#119 才能进入 main。[W0 准入规则](W0.md)

## 第二轨 · 产品实现

| 工作包 | 已交付 | 尚缺 |
| --- | --- | --- |
| W1 | BrowserHost、ConversationProvider、带摘要的站点版本、原点击绑定、原操作只读续查已进入 Swift 产品模块。新站点使用原 TransferCoordinator 的执行队列和 QueueStore。旧数据可缺省新增绑定字段。 | 从含最终 1.0.7 的实际 main 接续独立增量并做正式升级和同包验收。 |
| W2 / W6 | Chrome、Edge 保留 build 53 的原生定位及异步原回包。开发 App 的普通截图点击可在原窗口、原标签读取新站点附件入口，结果只用于诊断。Brave 已实现按进程及原生窗口/标签定位、正常授权和脚本能力检测。Safari、Firefox 可在辅助功能许可下比较原窗口、网页及焦点对象。 | Safari 已复现同 URL 标签替换后旧索引错投。现有 AX 对象不足以证明冷点击的原文档。Brave 默认脚本权限及 Firefox 无扩展通道尚缺原站点正证。 |
| W3 / W4 | Claude、Gemini、DeepSeek、Kimi、国内千问、豆包、Perplexity、国际 Qwen 和 Grok 各有独立配置、资源摘要与只读入口。Gemini 支持检查已展开菜单与原上传按钮、文件输入之间的显式归属。共享的输入和原卡观察后端已编译并通过受控纵向验收。 | 八个扩展调查站点中，普通 Gemini 的匿名页面确认了编辑器和上传菜单。登录后图片模式、文件事件、卡片归属和服务行为仍须逐站证明。开发 App 对这些公开站点的文件写入仍关闭。 |
| W5 | 验收工具要求真实原操作、新操作、原卡失败、找回图片和手动重试能在同一组测量中吻合。19 组矩阵测试通过。 | 下一版本的签名 App L2、同包登录 L3 及性能、升级准入待验。 |
| W7 / W8 | 已构建独立应用标识和数据目录的开发 App，关闭自动更新。发行校验器继续验证原 build 53；含新资源的候选同时核验两项新资源的源码摘要。 | W0 仍返回 WAITING_FOR_107_BASELINE。双架构正式 CI、最终 Developer ID 候选、公证、同包安装与实站验收尚缺。 |

**一次贯通的开发验收。** Swift 后端在实际 SQLite 建立原操作，测试传输将同一调用送入真实无界面 Chrome 的本地网页。页面独立观测到 1 次 input、1 次 change、0 次错投和 0 次发送，原文字、选区和旧卡保留。重复写入遭拒。测试随后让这张卡明确失败，重开数据库后仍可按原身份只读查回。网页使用受控站点和临时浏览器配置。[实际产品资源回放收据](development-loopback.json) · [复跑入口](../../../Tests/Issue120Integration/README.md)

非作者复核发现并复测了旧点击身份或错 profile 可被接受、同 URL 往返后旧绑定复活等问题。两条 SQLite 连接竞抢同一持久输入，仅一个调用获准；重启后能读原操作且没有重新输入。矩阵曾接受脱离实际操作的找回事件，相应反例已纳入。完整审查与结论范围见[独立复核记录](DUAL_TRACK_REVIEW.md)。当前结论维持 #118、#120 打开，#119、#122 为 Draft。扩大推广条件尚未达到。

## 开发 App 与测试

可在开发 Mac 本地解包的 ARM64 ZIP `Riftlet-Provider-Development.zip` 使用产品提交 `9ea7e7f4`，SHA-256 为 `4e3da7c815bf4c5bad0d06c28e47ce8458b2ced324b405aacfc65251d926d42e`。已重新解包，逐项比对资源与源码，验证 deep/strict 签名，执行导入、持久状态、网页策略和首次使用自检。独立的受限系统截屏测试模式在此内部通道按配置拒绝，在普通开发通道通过原自检。ZIP 使用 ad-hoc 签名，未经公证。可公开安装的 Developer ID 交付仍以 W0 为前提。[包身份收据](development-app.json)

本地还运行了 128 项发行校验、26 项存储校验、19 项矩阵校验和 9 项真实草稿工具的隔离测试。独立回环测试覆盖真实 Chrome 页面资源、Swift 适配器、SQLite、重开后的同卡失败观察。完整 Xcode 测试转交实际 macOS CI。[开发分支 CI](https://github.com/haohongfei2001-png/Riftlet/actions/runs/44717916012)
