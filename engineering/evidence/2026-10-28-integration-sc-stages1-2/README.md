# 真实系统截图第一、二阶段正式集成 · 2026-10-28

## 精确代码与历史

正式基础 `4b7228a07a23381d3de467a44dd8490d73e26e7e`，第一阶段交接 `5d2994c150646549830746cd83c264c600973689`，第二阶段交接 `f2ae645451044649fbe73326952efbe084353869`，最终产品源码 `48574df19f34e5681ee98815750e279540e9eb9b`。

实际线性链为 `4b7228a → a5db972 → 3f4e18a → 5d2994c → 867d93f → 48574df → f2ae645`。负责人在独立 worktree 以 `git merge --ff-only` 继承，没有重复 cherry-pick、squash 或额外源码改动。当前文档/证据提交的全部构建输入与已审、已测 f2ae645 相同；最终准确正式 HEAD 与其新 CI 结果固定在 [PR #1 最新交接](https://github.com/haohongfei2001-png/Riftlet/pull/1)。[对象与15份原证据清单](source-manifest.json)可逐项核对。

本次产品增量仅为：a5db972 权限失效 idle wake 消费；867d93f 严格完整 v9 owner 兼容与 nil-target 诊断修正；48574df 删除 canvas `willReadFrequently`，保留显式 sRGB 与精确字节／同尺寸完整 RGBA SHA-256。Core、Capture、UI、SQLite v3、首次使用、权限／原选择／UNKNOWN 和审计保持正式基础。第一、二阶段原始证据均保持原 blob 与 SHA-256。

## 所有权与反馈隔离

本轮用户明确指定当前负责人为唯一正式集成写入者。工作前重新读取所有远端 refs、PR #1／#7 和交接：正式 HEAD 是4b7228a；反馈 Pro 在 PR #1 的 [独立开发声明](https://github.com/haohongfei2001-png/Riftlet/pull/1#issuecomment-6460772079) 明确只写 `codex/feedback-v01-20261028`，不写正式工程分支。初次观察反馈 HEAD 为 `bf8d4b05616d4045af465868225615bf106db74d`，后续该分支可以继续推进，不应被本轮改写或强行冻结。

本次没有导入反馈的 Package／RiftletMain 接线，没有访问其本地工作树。正式 ref 只允许在再读当前 HEAD 后，使用预期4b7228a的非强制快进更新；未知远端改动必须先核对。后续正式交接仍由本负责人按实际祖先整合。PR #1 继续 Draft，main `eba1a4fc77648a665e1d5c1f2609df1314c3b079` 不写入、不合并、不公开发行。

独立集成分支是 `codex/riftlet-real-mac-acceptance-sc-integration-20261028`。[临时 Draft PR #8](https://github.com/haohongfei2001-png/Riftlet/pull/8) 的 base 是工程分支；创建 branch 本身没有启动 push CI，实际新 CI 由该 PR 触发，工作流和判据未修改。

## 本轮实际源码 macOS CI

[Run 40662720558](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40662720558)／job `122729461430`，于 **2026-10-28 17:16:55（UTC+8）** completed/success，**18个步骤全部成功**。这是本轮的新组合运行；来源 CI40656871851 单独保留，不替代它。

实际临时 checkout 为 `3be371d10c2a7a0482faa2cf82eb6aca6399aaaa`，双亲4b7228a/f2ae645，整棵 tree `33494e55f3e067782fa2b5f97d61450776f88286` **完全等于**已审 f2ae645。临时 checkout 用于 CI，不是 main 合并。负责人用本地 Git 对象，另一位非作者用 GitHub Git API 独立核对。

| 检查 | 实际结果 |
| --- | --- |
| 唯一原生测试 | **443**：Core138／Adapters137／Capture65／UI56／App47 |
| 详细软件 suite | 16组 **106 passed／0 skipped**，已包含在443中 |
| 当前页面／历史observe | **86／61**，0失败／0跳过 |
| 第二阶段证据工具fixture | **12** passed |
| 原证据回放／故障／probe | 19 case／55文件／89真实轨迹前缀；8 fault／12只读probe；2迟到错误明确为SIMULATED |
| 第五轮证据helper | **9＋4＋2** passed |
| SQLite／恢复 | v1/v2→v3、迁移回滚、未来版本拒绝、UNKNOWN重启、原身份/锁、补偿、首观察保持通过 |
| 权限／原点击 | 三项新wake回归及原ACK、epoch、被动恢复、取消、原选择／等待／原点击保护通过 |
| 打包 | 12项拒绝路径、Release、bundle资源／ad-hoc签名通过 |
| 可执行自检 | 四项App自检＋GUI helper自检，全部通过 |

完整机器结果：[source-ci.json](source-ci.json)／[全部443测试名与详细分组](verification.json)／[完整实际日志](source-ci-full.log)。日志UTF-8 250,164字节，SHA-256 `631fccb59e663d2ca575c7d00df4fde18367ff388d764a32ea2515a1460b94af`，负责人和非作者独立取得的日志hash相同。

[开发App／helper／日志制品12804193464](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40662720558/artifacts/12804193464)：1,923,964字节；GitHub元数据及上传日志digest `60c24150d4478730ba1a3540e097adc085fff9b8912868b552743f861aed5cb4`，到期2026-11-11 17:16:50（UTC+8）。未在本轮下载重算ZIP。ARM64／ad-hoc开发构建，未公证／发行。自检保留 GENERATED_FIXTURE、CHROME_NOT_RUN、SYSTEM_SCREENSHOT_NOT_RUN、PERMISSIONS_NOT_REQUESTED、GUI_NOT_RUN。

当前交接提交只含文档和上述证据；PR #1 还需绑定它的准确最终 HEAD 运行完整 CI，结果写入最新交接评论，不为反复记账另造提交。上述 run 的源码、时间、SHA 始终不改称最终文档 HEAD 运行。

## 非作者审查

三位独立 AI 审查者均没有撰写本轮被审产品源码：

- [权限／原ACK／点击恢复](review-permission.md)：先撤权与epoch更新再唤醒；新观察不能补签旧点击；单一在途、fresh passive permission 和原token撤销保留。
- [v9/v10/v12/v13与精确sRGB](review-web.md)：完整旧协议匹配，新旧权限隔离；旧UNKNOWN仅observe；完成仍严格绑定原附件内容。独立Linux86＋61通过；另有3个临时探针，单通道一级差异、尺寸差异均拒绝，匹配路径只用显式普通sRGB。探针不加入443／86的计数。[可复现临时补丁](review-web-probes.patch)及[审查日志](review-logs/)保留。
- [历史／原证据／CI覆盖](review-evidence.md)：六提交祖先、15份原证据、八组构建输入与11组基础保护对象一致；反馈没有混入。
- [最终文档与源码CI独立复核](review-docs-source-ci.md)：修正继承入口旧NOT_RUN陈述和旧附件措辞，独立核对完整实际日志、临时checkout、计数、打包及制品元数据。

**结论：无待处理集成阻断。** 这是真实完成的非作者AI工程审查，不是人类GitHub approval，不替代实际Mac/TCC/物理GUI或截图生产准入。三项新Swift测试明确只测scheduler契约，不冒称AppKit接线验收。

## 真实验收边界与直接续做

SC-INPUT、SC-START仅继承来源的限定PASS。第二阶段实际输入运行于867d93f，完整SC-COMPLETE为FAIL；48574df普通sRGB修复有同一原件／预览只读单变量精确对照，但**修复后的新真实系统截图输入仍NOT_RUN**。不能补签旧D的proof，也不能以CI、颜色对照或新文档宣布完成通过。

三份候选开始／完成／安全失败映射继续为空，普通production及safe-retry关闭。继承的正文48字符、选区8..11、未聚焦editor只覆盖其样本；旧附件基线为0，总附件0→1，非空旧附件保留未验证；物理鼠标、无ACK冷首击、ABA/MID、自包含和完整T0/T1/T2保留原状态。主集成及本轮审查没有新真实输入、Chrome操作或私有数据库／媒体写入；数据保留的真机声明是原交接事实，不冒称再次访问私有原件核验。

本地Codex直接从PR #1最终SHA新建独立worktree，沿用同一候选数据库和原命令，使用另一张新系统PNG在原规则允许的独立业务草稿取得修复后proof／attached及保留性证据。旧A/D与其它UNKNOWN只读；不补造uploadStarted、不清库、不换根绕锁、不自动重传或Send。详见[当前正式交接](../../../docs/INTEGRATION_HANDOFF.md)与[候选契约](../../../docs/SYSTEM_SCREENSHOT_WEB_CANDIDATE.md)。
