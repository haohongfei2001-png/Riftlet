# Beta 体验修复：正式组合记录

2026-10-28（北京时间）。此包记录将已交付体验修复纳入完整统一 Beta；不重新集成 Feedback、不改上传机制、不进行新真实截图输入。

## 来源与合流

- 正式基线：`b4bcfa41e8e237723b975d2a9a0059e955fa0c1f`，已包含 H 证据与 Feedback v0.1。
- Codex 源码：`fa74f3c68f05ab4eaccfc24e2f39c0177289ddb3`，父节点 e421。
- 证据后继：`8e1a1688e75db8c18965e073ae357010e7397a3a`，父节点 fa74；八份原始脱敏文件完整保留。
- 本次合流保留 b4bc、8e1 两个有序父节点；不重复 cherry-pick、压平或覆盖历史。
- Main 已审 blob：`05fe28ec734ba0d8c040810c737b26715a33d5de`。selection catch 合并 owner/revision-safe 提示、精确错误映射与 `selectionRejected` 诊断；render 后合并 prepared/cancelled 与三个 Feedback 投影调用。
- 其余七个交付文件精确等于 fa74。Main 相对 fa74 的全部新增/删除行，仍与原 e421→b4bc 的 Feedback 接线完全一致：20 行新增、1 行替换。

精确对象与来源见 `integration-inputs.json` 和 `feedback-object-review.json`。Core、Capture、Adapters、CSQLite、Resources、原迁移/权限/UNKNOWN测试、开始/完成准入、原点击授权与页面严格 sRGB 均不变。Feedback Core/UI/Demo/Host/测试/服务和 Package 保持原 f195；没有新 endpoint 或云资源。

## 审计与非作者审查

- `evidence-review.md`：非作者对八文件修复、公开脱敏证据及来源 CI 的独立复核，PASS，无阻断。
- `feedback-review.md`：非作者核对两个冲突、全部既有 Feedback、独立数据库/Keychain/本地待发送及无诊断授权副作用，PASS，无阻断。
- `audit-implementation.md`：独立作者更新固定来源审计，CLI 不提供来源覆盖，不访问网络或写 Git；10 项真实临时 Git fixture 通过。
- `audit-review.md`：集成负责人作为该审计的非作者复核，精确保护获准路径以外所有原对象；审计未禁用。
- `final-source-review.md`：另一位非作者收尾复核审计和当前包装/使用说明。

固定组合审计共 42 项：六个祖先、十个原截图路径、七个获准 UX 文件、十一个 Feedback 路径、两份证据目录、四个 UX 目录的其他原文件、其他 App 文件和精确 Main。源码提交存在后及正式 CI 中运行实际 commit 的审计，不能用未提交工作树代替。

## 验证及准确最终身份

来源 [Native CI40693945938](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40693945938) 只验证 fa74：463 原生，121 详细 passed/0 failed/0 skipped 属于463子集。不得当作新组合 CI。

完整组合继续使用原 Native foundation 与 Feedback v0.1 工作流，没有删减步骤。最终正式 SHA、实际 Actions checkout、Native/Feedback run/job、数量、完整日志复核、制品摘要及非作者结论固定在 [PR #1 的本轮正式交接](https://github.com/haohongfei2001-png/Riftlet/pull/1)。使用 [当前内部 Beta 安装说明](../../../docs/INTERNAL_BETA.md)，仅交付实际完整 CI 打包并下载核对的 `Riftlet-Internal-Beta.zip`；不拿 Feedback Demo 或来源 fa74 的独立 App 代替。

## 证据边界与下一步

人工 helper 记录来自 e421，Feedback 窗口软件操作来自 b4bc，修复 CI 来自 fa74，组合 CI 另行标识；都不冒充最终组合 App 的新真机运行。新提示主要通过 tooltip/AX 呈现，未增加持续可见队列徽标；没有缩短上传等待的声明。H 的约2.72秒总等待和约127ms动画是旧样本，不是本次速度对照。

无 ACK 冷首击仍未解决；真实 Chrome 物理附加、指定 CLEAR/补位后双击、多屏/Spaces/首装签名公证等未完成项保留。普通生产、安全失败/重试与反馈云端关闭。旧截图、H/F/UNKNOWN 不重传、不清除、不解锁；SQLite v3、媒体、历史和审计不重建。本轮没有操作真实 Mac 数据。

完成必要组合 CI 与包装核对后，下一步是创始人亲自正常体验，不再追加常规工程验证或重复 H 上传任务。确有新的体验问题时，再按实际现象进行小范围修复。
