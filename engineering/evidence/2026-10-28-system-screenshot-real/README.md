# 真实系统截图首验与权限恢复修复 · 2026-10-28

**产品结果：真实 macOS PNG 已经通过 Riftlet 的实际鼠标选择路径输入到普通 ChatGPT 对话，并取得 v13 的原附件 `attached` 候选观察。SC-START 未取得；完整首击闭环和快速吞噬准入尚未成立。** 不将候选完成观察、内部 UNKNOWN 和生产成功混为一谈。

独立分支 `codex/system-screenshot-real-20261028`。正式起点 `4b7228a07a23381d3de467a44dd8490d73e26e7e`，交接时远端仍为该 SHA。实际修复源码 **`a5db972b7c4da20d30266ec8d1411fff9f434c13`**；CI 树 **`3f4e18a15d8cc77a367beca30ade338906df9d8d`** 仅追加本独立分支的 push 触发条件。没有写正式分支或 PR #1，也没有合入其他进行中 worktree。

## 真实结果与限界

| 项目 | 结果 | 实际证据 / 未通过原因 |
| --- | --- | --- |
| 系统来源与自动收录 | PASS | 人工使用系统区域截图；原件 `kMDItemIsScreenCapture=true`、type=selection。424×344 PNG，40,639 bytes；系统原件与私有副本 SHA-256 完全一致，未改 metadata、重编码或使用生成文件代替。内容经本地查看，仅含本次操作说明。 |
| SC-INPUT | PASS，限定修复后的一次原输入 | 点击前完整 ACK 提前7801.743ms；原目标冻结、session/host epoch 匹配；begin/chunk/commit各一次且成功。commit区间为点击后434.360–542.616ms；页面先有原附件 inputTriggered，随后 exactImageIdentity=true 的 attached。不是只凭命令执行成功。 |
| 冷首击 / 严格新图单击流程 | FAIL | 修复前6个mouse事件都无已发布ACK、零operation。修复后用户先重新点击旧图A，再点击新图B；没有自动重放，但不符合要求的“只点新图”试验顺序。A当时从未输入，修复后唯一一次输入；不能将其描述成首次物理点击就成功或真正无ACK冷首击通过。 |
| SC-START | FAIL（正向开始证据未取得） | journal有unknown/input/attached，**没有start槽**。`isUploading=true`不是独立开始证明。40KB小图可能缺少可捕获的两个递增中间进度，但本轮不能确定原因，不能声称已看见开始或据完成倒填开始时间。 |
| SC-COMPLETE | FAIL（完整验收证据缺失）；attached候选观察子项PASS | 持久attached观察：同op/attempt/hash/target、同attachment，exactImageIdentity=true、belongsToOriginalDraft=true、isUploading=false、hasError=false。v13仅在100→进度消失→后续load及内容匹配后返回该值。未取得独立预览hash/匹配分支导出，不能宣称服务端原文件保真、ICC/HDR或广泛页面兼容。 |
| 正文、选区、旧附件、未聚焦编辑器 | NOT_RUN | 浏览器控制读取/claim超时；没有本次完整前后快照，不能从产品已有单测或attached判据推导保留。没有自动发送消息；是否由用户另有页面操作不能仅凭本地日志判断。 |
| 候选策略与持久状态 | PASS | A保持UNKNOWN/visible；upload_starts=0，没有成功receipt或safe-retry授权。后来原观察invalidated仍保留首次attached，不重新输入。B prepared等待后因activation取消，phase=failed，并非“上传失败后安全重生”样本。 |
| 人工鼠标命中 | PASS，限定事件关联 | 请求用户操作后出现mouse来源、eventNumber、asset和目标冻结记录；同期执行者没有AXPress/CGEvent/CUA点击微图。用户只回复“ok”，未逐项报告；不能据此声明硬件事件鉴定、CLEAR/GAP、焦点保留或全套物理GUI通过。 |
| T0 / T1 / T2 | NOT_RUN | 持久firstSeen→import为196.465ms，仅此区间有效。没有系统实际完成T0、完整文件最早可用T1和首次可点T2的独立同步测量，不能称为端到端截图延迟。 |

上表的 PASS 都是窄范围事实；SC-START以及保留性证据缺口使三组完整准入尚未完成。**本轮不批准任何真实截图开始、完成或重试 profile。**

## 实际消除的阻断

`applyAutomationPermission` 在 granted→非granted 时调用 `TargetArmScheduler.request(invalidateEpoch:true)`，却丢掉其 idle 状态返回的 wake。现场最后一次browserNotFrontmost完成后约142ms权限检查返回unavailable；此后 `pending=true/inFlight=nil`，fallback、激活、新截图请求都合并进已有pending而不再启动捕获。后台权限恢复granted也未恢复ACK，用户点击持续被拒。

修复只消费该 wake：先同步新host epoch和deferred AX绑定，再调用现有 `performPendingArm()`。进行中的capture仍由原completion释放，旧epoch ACK仍被拒；没有新bridge、目标猜测、点击保存/回放、权限缓存或来源准入变化。

修复后真实日志有离开Chrome时的失败捕获、权限不可用后继续fallback、返回Chrome后新完整ACK，并最终执行上述唯一输入。**重启本身恢复初始预绑定不是修复证据**；关键是同一修复进程内再次经历不可用→返回后仍持续捕获，详见 `results.json` 和私有日志哈希。

另有独立诊断问题尚未改：多Chrome且前台非Chrome时，无session的权限检查可因接收者歧义返回unavailable，不能解释为TCC被撤销。旧selection日志的 `nil == nil` 可令foregroundSessionMatches=true；没有armedTarget时此字段不构成前台证明。本补丁没有放宽任一接收者检查。

## 三层状态对照

- **页面程序**：原附件一次inputTriggered→干净attached→后来invalidated。完成候选依赖v13绑定原节点/源及内容proof；本轮没有独立导出内部proof摘要或正文前后快照。
- **候选journal**：原完整identity的unknown/input/attached/errorOrInvalidated首次记录全部持久保留，不覆盖、不删除；无start。后来的invalidated不授予重传，也不自动擦除历史attached。
- **SQLite v3**：两张系统来源资产；A unknown/visible，B failed/visible；两项attempt1操作；upload_starts=0、compensations=0，integrity_check=ok。所有三个候选准入表为空。候选停止时无prepared/dispatching等在途操作；停止只针对本轮实例。

原始系统PNG、私有副本、数据库快照、完整target、raw logs只留本机。公开 `results.json` 只含别名A/B、hash、计数、相对时序、状态和匹配布尔值。没有提交真实图片、聊天正文、原始日志、数据库、凭据或私有路径。

## 构建、回归与审查

- 正式baseline CI [40629712964](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40629712964) 已读取 completed/success，精确HEAD4b7228；不当作修改后测试。
- 两次完整 `bash scripts/build-macos.sh` PASS（baseline和修复后）；修复构建通过bundle布局/资源/权限文案校验和development ad-hoc签名。未公证/发行。
- 修复后 `--system-screenshot-candidate-self-check` PASS；它使用生成fixture，只验证闭合准入及持久候选审计，不替代以上真实截图。
- 非作者独立纯Swift复现丢wake、消费wake恢复、在途capture拒旧ACK，全部PASS。新增3项 `TargetArmPermissionWakeTests`明确只测调度契约，不伪称AppKit wiring测试。
- 修改后 macOS CI [40647857737](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40647857737)：状态见 `validation.md`。仅触发一次，没有容量重试或空提交。
- 非作者代码与真实证据复核见 `review.md`。

## Pro 可直接接手

1. 审查/集成最小App唤醒修复和3项回归；CI分支过滤属于独立验收配置，可不合入正式分支。
2. 审查本轮SC-INPUT和限定SC-COMPLETE候选事实；**不要据此开启start、complete或safeFailure映射**。当前没有足够开始证据，也缺少正文/选区/旧附件完整对照。
3. 下一次测试需恢复可靠只读浏览器观察，选择另一份明确独立草稿和**新的、无敏感系统截图**，先记录保留性基线，再只输入一次并取得真实中间进度或精确字节请求开始。不能重传A或借用生成图profile；B取消不是许可回放旧点击。
4. 无ACK结构性空档、MID、安全失败、自包含、CLEAR/GAP完整物理矩阵、生产端到端及Beta发行仍保持原状态。本轮不重做这些实验，也不声称已完成可用Beta。
