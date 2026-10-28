# 真实系统截图：受限内部候选与快吞噬 · 2026-10-28

## 当前决定

F 的真实证据交付 `493d1d8b898d18e34709463d2dceca8c85ad4014`，实际运行源码 `48574df19f34e5681ee98815750e279540e9eb9b`，同源 macOS CI `40656871851`。同一张新系统 PNG 已分别取得 **SC-INPUT、SC-START、SC-COMPLETE 限定 PASS**。本轮在正式 `871d825a43a759bb6dd8ded9cdc99a340d8e0e64` 上按真实祖先关系合入该证据；493d1d8 与871d825均继承f2ae645，使用保留双方父节点的合流，不重做第一、二阶段或重写上传机制。

独立开始证据审查与独立完成证据审查分别支持下列两个准入。安全失败／重试和普通生产没有获准。**F 的旧操作仍是旧 UNKNOWN；证据被采用不等于它的队列状态获得追溯授权。**

| 项目 | 当前边界 |
| --- | --- |
| 内部候选 uploadStarted | 仅新登记操作，严格同图／原目标／同节点递增进度及唯一输入；v2 start profile |
| 内部候选 completion | 独立完整 attached 证明，原节点／source／最终 load、精确内容；v2 completion profile |
| 普通启动 | 仍为 UnavailableAdapter；系统截图只收录，不因候选准入打开上传 |
| 安全失败、安全重试 | 关闭；failureSignal=nil、safeFailureProfiles为空 |
| F、A、D 与所有旧 UNKNOWN | 保留原操作、attempt、目标、历史和锁；只读观察，不补资格、不重传、不清除、不解锁 |
| 新版快吞噬真实交互 | 软件组合、完整 CI 和非作者审查分别验证；新候选的真实 Mac 单次体验仍由下一张全新截图验证 |

## 准入范围与证据

限定为显式 `--system-screenshot-candidate`，Chrome 中文 ChatGPT **普通已有聊天**，已识别的 `chatgpt-composer-react-persisted-20261027-v1` logical draft identity，完整原 Chrome session/window/tab/document/composer/draft 仍逐项绑定。Home、新建 local draft、Work、临时／只读聊天、其他浏览器不由这次准入覆盖。现有 v13 页面程序仍在每次输入／观察核对原 root、路由、节点和完整目标。

输入为原样单帧 **8-bit RGBA PNG（IHDR bitDepth=8、colorType=6）**；保守进一步限制非交错 PNG，沿用 ≤8 MiB、≤16,777,216 像素。F 的公开记录没有建立交错矩阵，不将新增非交错限制描述为另一项实机 PASS。Capture 可继续保存其他已支持的本地格式；不支持的候选输入提前拒绝，不改后缀、缩放、重编码或转换。预检查和实际完整 SHA 扫描的同一文件描述符均检查头部；只有真正参与上传且 hash 相等的字节才可登记资格。

F 的证据重点：

- 原系统 PNG 1746×1164，6,796,322字节，原件／私有副本 SHA-256 `0c19cb16f5c6dfdcaf0958284d6f40450912ea03babe5a79e1d268c2f06ff596`；系统截图元数据真实，显示内容为测试图案。
- 原 ACK 早于点击约1208.9ms；一次原生 CGEvent 点击，1 begin / 26 chunks / 1 commit，页面 inputCount 与独立 change 计数均1。不是物理鼠标或无 ACK 冷首击验收。
- 同一原进度节点2.4538636%→3.6807954%才取得严格开始，input→start约2151.4ms；最终 proof约8784ms。开始与完成有分别的时序和证据。
- 原附件100%→原进度结束→原最终image load→严格proof。独立显式 sRGB 解码的全部8,129,376通道零差异，完整 RGBA SHA-256同为 `6f20aa4069b1d28a3693527e3b7d1402e424a393271a3d38ec081c98b0f5d129`。
- 原正文48字符、选区8..11非折叠、页面聚焦但编辑器未聚焦、一张原稳定旧附件在已记录取样点和最终状态保留；附件总数1→2，未Send。

原始脱敏包：[F完成证据](../engineering/evidence/2026-10-28-system-screenshot-complete/README.md)。本轮审查的是公开脱敏包、不可变源代码及内部一致性；私有原图、完整目标与原始 SQLite 的读取与独立像素提取真实性依赖原交付中前位非作者的私有证据审查。本轮不冒称重新读取私有数据或重复真实上传。

实际记录环境为macOS27.0(26A428) arm64、Chrome156.0.8078.73。它是限定样本，不是全面系统／浏览器版本、物理鼠标、多屏、冷首击、MID、安全失败或自包含矩阵。

## 新旧操作隔离与既有交互复用

旧 profile 永不加入候选允许表：

- `chatgpt-web-system-screenshot-start-candidate-20261028-v1`
- `chatgpt-web-system-screenshot-attached-candidate-20261028-v1`

新的两个 profile 分别准入：

- 开始：`chatgpt-web-system-screenshot-start-restricted-20261028-v2`
- 完成：`chatgpt-web-system-screenshot-attached-restricted-20261028-v2`

`SystemScreenshotCandidateAdmission` 只在新的 append、文件格式与完整hash检查通过后、首次begin前登记。`QueueStore.claimDispatchCheckpoint` 在同一SQLite事务检查实际操作仍是原dispatchIntent、完整操作／asset/image／active operation相等，并首次写入有界资格；随机nonce使并发申请只有一个胜者。资格保存在既有v3 checkpoints，无迁移、时间戳猜测、库重建或旧记录回填。重复append即使携带相同资格也拒绝。

reconcile、恢复、旧journal和页面JSON不能登记资格。没有资格就保留v1观察；损坏、非规范、外来或身份不符的资格拒绝。新操作的资格可在重启后支持同一原操作只读观察，不能恢复旧点击或执行第二次begin/commit。资格只限定可用profile，**不是开始回执，也不是完成证明**。

原Core接收严格开始后写入upload_starts，并把队列可见性改为swallowed/reason=uploadStarted；既有UI执行原快速吞噬。之后原后台observePending接收独立完成proof才写succeeded/used，不重复动画、不弹成功Toast。没有正向开始时不补造开始；如果只有独立完成证明，仍沿用原legacyCompletion静默完成语义，不伪造upload_starts。

输入不明、观察丢失、超时、附件消失和上传异常不构成安全重试。已开始但尚未完成的新操作保持隐藏与原审计，只读跟踪；新操作失败／重试准入也仍关闭。普通模式、合成模式的数据根和策略隔离保持不变。

页面JS与48574df逐字节相同，SHA-256仍为 `c0afbd8a652c7a0e8fe6875ddbbd54f075e9c60bcda512eeb4df610e72f8948b`。完成依旧要求原文件字节相等，或相同尺寸、显式sRGB全部RGBA精确hash相等；没有像素容差。权限wake恢复、原事件前ACK、v9/v10/v12/v13兼容和旧操作只读路径保留。

## 验证与交付位置

完整macOS CI必须覆盖原生全套、当前Web与legacy、SQLite v1/v2→v3迁移、UNKNOWN和原点击／权限、候选准入、打包、Release构建及五项App/helper自检。候选自检明确标注GENERATED_FIXTURE、CHROME_NOT_RUN、SYSTEM_SCREENSHOT_NOT_RUN、GUI_NOT_RUN，不能替代新的真实Mac体验。

最终精确正式HEAD、CI run/job、实测checkout与源码树对应、非作者审查和候选App artifact由 [PR #1最新正式交接](https://github.com/haohongfei2001-png/Riftlet/pull/1) 固定；永久记录放在 [本轮集成证据](../engineering/evidence/2026-10-28-sc-restricted-admission/README.md)。候选App来自该次CI的 `Riftlet-macOS-development.zip`，为内部ad-hoc开发包，不是公证／公开发行版。

## 本地 Codex：只验证另一张全新截图的完整体验

1. 继承PR #1最终准确正式SHA，在独立worktree构建，或下载同一最终CI的App；保留旧分支、系统原件、私有媒体、原候选数据根、SQLite/WAL和全部审计。不要重建数据库，也不要把旧截图重新导入。
2. 从普通App菜单“打开真实截图内部候选…”进入，或按下列命令启动。确认菜单为 `Riftlet REAL TEST`。沿用首次使用、目录访问和原Chrome权限流程；已有普通实例可按原流程隐藏／退出，不能覆盖另一个Pro的App路径。

```bash
bash scripts/build-macos.sh
./build/Riftlet.app/Contents/MacOS/Riftlet --system-screenshot-candidate --acceptance-trace
```

3. 使用已支持的Chrome中文普通已有聊天。完整目标和原事件前ACK必须就绪；若旧UNKNOWN仍锁定同一业务草稿，保留其锁，使用原规则允许的另一独立已有聊天。不要修复／重播F、A、D的旧输入或旧proof。
4. 创建**另一张新的真实系统截图**，原样RGBA8非交错PNG且在上限内。记录系统元数据、源／副本hash、编码尺寸。保留可核对的原正文、选区与一张稳定旧附件；只选择愿意附加的内容，不Send。
5. 只点击一次原缩略图。记录同一asset/op/attempt/hash/完整target、先行ACK、唯一input、严格开始和upload_starts持久化；观察原快吞噬在真实开始后发生，记录实际时钟及UI边界，不人工补写开始。
6. 后台只读观察原操作，取得独立原附件proof与succeeded/used。验证完成不重复吞噬，原正文／选区／旧附件保留。F和全部旧UNKNOWN的原身份／状态／锁／审计保持；不得重传它们或清除锁以演示效果。

若某张新图没有可验证的中间开始进度，不伪造快速吞噬，也不重输它。记录该操作实际结果；若新图已经输入却结果不明，继续原操作只读观察。新的真实Mac报告要将SC技术限定PASS与本次SC-UX快吞噬结果分别填写，不能用旧CI或旧F替新App签字。

## 后续唯一集成入口

正式分支 `codex/engineering-foundation-20261027` 和PR #1仍由当前负责人唯一写入。后续本地Codex和反馈Pro的正式交接按实际共同祖先审查、组合并完整验证，不重复合入已有历史。反馈 `codex/feedback-v01-20261028` / Draft PR #7本次未合入；本轮Main仅更新候选说明与自检日志三个字符串，后续对共享App作最小差异合流。PR #1保持Draft，不合main、不发布、不要求浏览器扩展。
