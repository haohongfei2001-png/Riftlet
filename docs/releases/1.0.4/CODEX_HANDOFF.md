# Codex开工入口：Riftlet 1.0.4

当前私有 build 27 的实际交付见[候选报告](RC_REPORT.md)。以下为 PR #109 原始开工任务。

目标：按已决策规范完成消费级设置与托盘精修、必要产品修复和完整回归，交付**可安装、可复核的签名公证1.0.4 Release Candidate**。工程由Codex自主推进，不把日常设计/排版/调试问题反复交给用户。当前交付仅为规划；不要把以下任务或设计图称为已实现。

## 1. 先读的最小集合

1. 根`AGENTS.md`、[BASELINE](BASELINE.md)、[本入口](CODEX_HANDOFF.md)。
2. [DESIGN_SPEC](DESIGN_SPEC.md)：已裁决的产品、尺寸、字段和交互；[IMPLEMENTATION_PLAN](IMPLEMENTATION_PLAN.md)：T00–T10及依赖。
3. 开工当前包的[SETTINGS_INVENTORY](SETTINGS_INVENTORY.md)、[ACCEPTANCE](ACCEPTANCE.md)相关行；按需查[AUDIT](AUDIT.md)、[真实1.0.3界面](VISUAL_EVIDENCE.md)。
4. 提交正式PR前读[mainline admission](../../MAINLINE_GOVERNANCE.md)。历史quality/engineering/research是来源明确的证据，不是另一份活动计划。

总任务[#106](https://github.com/haohongfei2001-png/Riftlet/issues/106)；托盘[#107](https://github.com/haohongfei2001-png/Riftlet/issues/107)；全库查找[#108](https://github.com/haohongfei2001-png/Riftlet/issues/108)；其他工作复用计划列出的旧Issue。不得按PR100旧审计重新开发PR101已经完成的修复。

## 2. 源码与冻结边界

- 审计/规划B：`3f8149e2313fd81bbaee5a7bbbdbb1efca2fc81b`（PR105 merge）；1.0.3公开包为`v1.0.3-zip`、build25，ZIP SHA-256 `b9814f1df2fa44a8ae1aef3f491ea76fabbc9ff67ac1c0db41cbb55ed18aa836`。
- 规划分支：`plan/riftlet-1.0.4-consumer-20261117`。从其经过源码审查的实际head派生`dev/1.0.4-consumer`；它的产品代码来自B。实施前核对祖先关系及本规划PR最新检查，记录实际head，不猜测SHA。若规划已标准合主线，可从包含该规划的main派生；若main另有变化，先审delta并记录新的实施B。
- 冻结1.0.3不可变tag、公开安装资产、官网、Sparkle稳定feed、签名身份和密钥。当前官网ZIP1.0.3与稳定feed1.0.2是事实，不在本版开发顺手改齐。
- 不替换用户个人安装、不清生产库、不拿个人媒体/聊天作fixture。使用独立worktree、隔离用户或VM、专用synthetic图片/测试草稿。保留未提交工作，工作树冲突先隔离。

可以使用的起步命令（分支已存在就检查并继续，不强制覆盖）：

```sh
git fetch origin main plan/riftlet-1.0.4-consumer-20261117
git show --no-patch --format=fuller origin/plan/riftlet-1.0.4-consumer-20261117
git merge-base --is-ancestor 3f8149e2313fd81bbaee5a7bbbdbb1efca2fc81b origin/plan/riftlet-1.0.4-consumer-20261117
git switch -c dev/1.0.4-consumer origin/plan/riftlet-1.0.4-consumer-20261117
```

## 3. 实施次序与已定取舍

T00明确环境并保留已知FAIL；T01共享token/组件/偏好契约先行；T02设置+T04首用、T03托盘、T05全库查找按独占路径并行；T06统一呈现；T07核心/真实双图、T08实测性能；T09签名升级RC；T10贯穿并作同包终审。共享Main/QueueStore/CI/admission/ref只由集成负责人合入。

独立开发/集成分支内可正常合并已验证工作包，不需要逐包向用户申请普通集成许可。这里的合主线/发布限制仅约束main和正式发行通道，不阻止在独立分支完成最终RC。

不可再次发散的决定：

- 四个顶部页签通用/外观/截图/帮助；内容640×560pt，最小600×460pt；保留现有AppKit/owner，原生按钮不加装饰shadow。
- 真正新profile默认托盘3图；旧profile包括缺字段、丢失/坏配置保持原语义。普通设置减少工程参数；旧特殊值可渐进访问，不删用户控制权。
- 托盘双列/路径相关展开、相机位置与截图Fit保留。只新增背景透明度t0–.75和相机实体色；背景/内容/命中区分开，机身/镜头/键帽分开。边框/圆角/阴影固定设计；辅助功能覆盖effective但不覆盖saved。
- 红关闭/Cmd-W/Later同样延期；Chrome权限一步一个当前动作，不阻断系统截图本地使用。
- 仓库全库元数据搜索先于200条分页；不做OCR、云、自动清理或永久删除。
- 旧核心安全修复保留；START是真实交接，不是READY；未知结果不重传；不自动发送、不损原图、不打断原稿。

## 4. 当前1.0.3实际证据与待解问题

本轮直接使用公开ZIP的签名二进制，在授权Mac的隔离profile执行：设置14/14 PASS、37原生帧，同包重启数据一致；托盘42项中41 PASS、1 FAIL，45帧。失败`tray-owned-button-and-escape: trayCameraObscured`在点击前命中所有权检查发生，实际展开/Esc未被该用例验证。先记录top window/owner/bounds/scale再归因；不靠performClick或删oracle变绿。

该review模式禁用真实浏览器/TCC/登录注册/更新，不证明普通权限流程。首用红关闭在源码上没有deferred处理；review重启特判会遮蔽普通启动行为，必须在正常隔离用户/VM复测。旧实际三图附件间隔2–3分钟，不代替当前包A→B≤2秒快速两图。最低macOS、完整VO、多屏等未测格保持NOT_RUN，不能写“全平台通过”。

## 5. 测试、视觉与交付过程

自动化按改动风险选择当前CI已有命令/targets，必要反例覆盖配置迁移、查询乱序、层次mask、目标/once-only、旧UNKNOWN和prepared恢复；不为刷数量堆同义测试。Mac上运行实际产品host，浅深/最小窗口/中文英文/系统辅助功能/键盘和自然输入；真实应用图必须附source、version/build、binary/hash和环境，设计SVG明确非实现。

每包结束自查跨页面一致性和原核心回归；发现设计不合格或普通工程问题自行修复，再交独立审阅。不能让用户承担本来可由已授权Mac/CI执行的测试。不能获得的环境只阻塞对应格，继续其他工作，并给具体缺口和候选；不伪造证据、不绕权限。

每个case最少记录`caseID, sourceSHA, version/build, package/executableSHA256, macOS/arch/scale, mode, steps, observations, result, artifact hashes, blocker/fixSHA`。mode区分SOURCE/CONTROLLED/NATIVE/REAL_SERVICE/RELEASE；首次FAIL留存。runner汇总解析报告，不用exit0替代内部状态。

升级至少真实25→1.0.4及24→1.0.4私有签名feed，前后核对旧数据与新截图/恢复。同marketing版本的RC更新不能通过当前`isUpgrade`，RC修订手动替换隔离App，每次build递增，保持签名校验。最终若获发行授权，提升验收过的精确字节，不重新打一个未验收包。

## 6. 源审、CI与停止点

保留原B→G→H：完整实现/证据形成G；**非作者**审查实际B→G与G tree，报告literal JSON/hash和发现；修复形成新G重新审；H是G直接单父子提交、仅变`engineering/mainline/source-admission.json`，记录准确B/G/tree与不同reviewer/authorRole。沿用productionAdmission，不以新设计放宽传输权限。执行：

```sh
python3 -B scripts/verify-mainline-composition.py <H>
```

五项正式checks须对实际H通过，名字以仓库workflow实际job为准。source review、CI、原生/真实服务验收、签名和发行授权分别判断；主分支protected=false/rulesets=[]的既有治理缺口不因文档提交消失。无直接main push、force push、squash/rebase或门禁放宽。未获合并授权则交PR，不自作主张合主线。

**最终交付：** 一个`docs/releases/1.0.4/RC_REPORT.md`，链接安装包及SHA256、版本/build、源码与PR、真实运行截图、完整验收表、升级/恢复证据、性能报告、独立review、五项CI、已知限制和剩余Issue。P0未过则候选明确BLOCKED，不宣称可推广；P1主要设计必须完成；条件性能项可据实测收益有证据地延后。停止在私有可复核RC，**不发布1.0.4、不改stable feed/官网、不替换1.0.3公开安装包**。

## 7. 工作量与上下文纪律

每轮只加载当前包需要的源码和验收行，独立查询并行、依赖改动顺序执行。不要一次打印整个日志/JSON/图片base64；保存完整回执，向审阅者输出失败行、来源、hash和结论。每个完整小包及时提交checkpoint与Issue进度，记录下一步；预留测试、独立复核和交付空间。遇到具体新风险先查原因，以最小必要修复推进，不新增一套流程来代替解决产品问题。
