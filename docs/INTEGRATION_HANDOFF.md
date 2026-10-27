# 正式工程集成交接 · 2026-10-27

北京时间。唯一正式工程分支仍为 `codex/engineering-foundation-20261027` / [Draft PR #1](https://github.com/haohongfei2001-png/Riftlet/pull/1)。本文件记录本轮合流、真实缺陷和下一条执行动作；不替代既有开发计划。本地 Codex 继续独占真实 Mac 的 W2/N1 验收，root 负责正式集成、共享契约和准入。

## 来源与集成范围

| 来源 | 不可变提交 | 处理 |
| --- | --- | --- |
| PR #1 原检查点 | `485fa87a31140f9d2e428db69ec5e0599b1f96ae` | 保留祖先和所有既有模块 |
| 本地 Codex 四个源码提交 | `268e70b3a20ec141fd5f7f079a56585f29b06adf`、`0100f4654b079cc05f0bca141a9bf2134d6d6d3e`、`f58b22762d1dc42368a6e13fe2ef3a8e2d156106`、`1909771d45ad00290dffe245b9a42e6e9f55203c` | 独立 Web/Core 审查后按原顺序保留 |
| 本地真机证据检查点 | `f075b8fe97eddf04d868e9e5fe589c51c9d12ad5` | 保留全部六份[原始交接证据](../engineering/evidence/2026-10-27-real-mac/README.md)；源码与1909771相同 |
| M1 / PR #3 | `88f9e362d7e1610929eeb42e77b3d7652477bd1f`，已测源码`7dfa8ecbd221095f6c99d289aba794b51ce37e95` | 保留M0接口、原生后端、34项既有M1测试及原始审查/CI证据 |

采用合流提交保留两侧完整祖先，不 squash 或覆盖贡献分支。源码/构建没有文本冲突；`EXECUTION_BOARD.md`、`VERIFICATION.md` 两处共享文档文件的冲突按两侧证据合并，旧状态标为历史。main、网站、设计和品牌资产没有加入本轮变更。

<!-- INTEGRATION_STATUS -->
**正式集成已验证：** 已测合流源码 [`76a8385be063bf225248c057262eb8d57e4be43f`](https://github.com/haohongfei2001-png/Riftlet/commit/76a8385be063bf225248c057262eb8d57e4be43f)。[macOS CI40453748396](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40453748396) / job122022173576于2026-10-27 13:11:09北京时间全部成功：**201/201原生测试、20/20页面VM、release/签名、三个自检**。v1→v2迁移/迁移回滚/补偿回滚/UNKNOWN恢复及三项新增M1回归均在完整执行日志中核对。root与非作者分别读取了run、job、完整日志和制品。

[永久验证](../engineering/evidence/2026-10-27-integration/verification.json)、[非作者审查](../engineering/evidence/2026-10-27-integration/review.json)、[实际CI摘录](../engineering/evidence/2026-10-27-integration/ci-excerpt.txt)及[工程App/helper/日志制品12711707097](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40453748396/artifacts/12711707097)。当前检查点在76a8385之上只保存这些文档/证据，源码、测试和构建输入未变；不要把它当作另一次真机验收。
<!-- END_INTEGRATION_STATUS -->

## 实际接口修复

新 Core 的 `observeCompleted` 允许成功后发现匹配原附件的迟到错误。原 M1 拒绝 `.succeeded`；仅放宽 phase 又会使已完成操作重新取得全局剪贴板所有权，并在 UNKNOWN 时不释放。

本轮负责人补充 `MacClipboardCoordinator.verifyConsumedObservation`：仅接受成功/补偿操作，短暂持锁读取完整身份相同的 `resolved + consumed` 墓碑，在任何 AX await 前释放。不设置输入所有者、不改 journal、不恢复剪贴板。已有所有者时拒绝观察且保留其锁。Adapter 的这两个状态直接返回原目标观察，绕过 clipboard settlement；Native executor 的 Paste 仍只允许 `dispatchIntent`。

三个定向回归分别覆盖：实际 SQLite 成功→UNKNOWN观察→迟到错误补偿→新连接恢复、原审计与journal字节保持；同/跨实例及子进程锁、错误/取消身份拒绝；原生 executor 的完成后观察零 Paste/剪贴板读取。真实客户端 provider/profile 和 App Mac 接线仍未启用，测试使用合成观察。

## 保留的准入事实

- 真机原交接支持五次受控中文 Home 生成 PNG 成功、三张系统窗口截图收录、原活跃草稿内 DOM 错误补偿/重启及具体标签撤销/锁用例。它没有证明新合流二进制已在真实 Mac 运行。
- POST100 网络故障尝试没有截获上传请求、没有实际 abort；迟到错误来自原卡片的受控 DOM 注入。**真实网络异常、普通线程、完整N1及真实截图两次操作闭环仍未通过。**
- 普通模式仍 `UnavailableAdapter`；Web只有显式生成图片验收；Mac默认禁用、内置profiles为空。生产成功与safe-retry注册表均为空，无Send、自动重传或配置绕过。
- v1→v2仅升级本地SQLite操作/补偿记录；不删除或重建既有队列、媒体、UNKNOWN或clipboard journal。旧页面程序无法恢复的原操作只保留/观察，不向新程序重放。

## 已确认的产品体验缺陷与自主修复决策

### UX-01：首次点击依赖预先收到的目标ACK — OPEN

现状：新打开或尚未预绑定的草稿，首次点击可能安全拒绝。当前自动预绑定不保证刚到达页面的首击成功，不能要求用户“先等一下再点”或重点击作为产品解决办法。

采用现有目标接口上的增量：前台应用变化、新截图到达和**有真实证据的**窗口/标签/composer变化自动触发预绑定，保留单个有界后备任务；截图和用户点击不增加新步骤。点击仍冻结原目标。若需将冷首击自动续做，必须由持续观察器证明同一原草稿身份跨越原点击时刻；只可保留该asset/原选择意图并在这份证据成立后继续一次。无跨点击证据时不捕获“后来当前的草稿”、不偷换目标。

验收由本地Codex在真实Mac执行：刚打开页面、截图先/后于页面、立即首击、延迟native事件、A→B→A、多窗口/同URL草稿替换、输入中切换。正常支持场景均为一次微图点击；证明缺失或发生目标变化时零输入且资产保留。先取得事件/身份证据再改原子输入边界；当前ACK早于原事件的保护保留。

### UX-02：一个UNKNOWN阻塞同标签的新草稿 — OPEN

现状：当前 `serializationKey` 整标签锁堵住了“rearm换代绕过未知操作”的漏洞，也阻塞同标签内真正不同的后续草稿。用户不得通过换标签、清库、确认或点击重试承担这项缺陷。

采用**稳定逻辑草稿身份**与**短时输入焦点代际**分离：持续观察仍绑定原operation/asset/attachment；输入epoch失效只撤销输入权。取得真实且可区分业务草稿的证据后，未决锁以该逻辑草稿为范围，同草稿恢复/换焦点不能解锁；已证明不同的新草稿可独立处理新图片。未证明时保留现有整标签回退锁，不能仅凭URL、DOM新节点、超时或rearm生成token缩小锁。

验收必须覆盖同草稿失焦再返回、新线程、同URL业务草稿替换、返回旧草稿、窗口移动及重启：旧操作只有observe、无第二次输入；不同且被证明的草稿不被旧UNKNOWN阻塞。不迁移旧UNKNOWN为无证据的新draft identity。

### 相关准入依赖（不以本轮CI关闭）

- 当前页面焦点epoch同时限制观察；失焦会撤销证明并结束对应成功watch。后台、切出再返回后的迟到失败须随UX-02分离观察生命周期后真机验证，不能由活跃卡片DOM故障推出。
- 补偿后安全重试尚有契约缺口：Core要求关联原非空attachment ID；normalizer的无残留失败要求attachmentAbsent且ID为空。准入前必须表达并验证“原附件已退役且不会自动完成”的关联证据，禁止把nil当通配符。当前空retry注册表保持不变。
- 页面32个generation、每代32个operation、64个成功watch及M1 journal256条墓碑均是开发上限；持续日常使用尚未验收，不能通过清除未决记录规避上限。

## 本地Codex下一轮直接续做

以PR #1最新正式检查点建新的真机worktree，保留原验收分支和队列；不要把正式分支 reset 到旧1909771或f075b8f：

```bash
git fetch origin codex/engineering-foundation-20261027
git worktree add -b codex/riftlet-real-mac-round2-20261027 ../Riftlet-real-mac-round2 FETCH_HEAD
```

核对本页及验证记录的已测源码SHA后，执行现有 `scripts/build-macos.sh`、三个已有自检和[MAC_ACCEPTANCE](MAC_ACCEPTANCE.md)。沿用既有SQLite及私有媒体，升级时保留UNKNOWN/补偿审计；不要降级v2数据库给旧v1构建。

下一轮只做实际闭环剩余项：真实请求执行环境中的网络中断/100%后异常、普通线程Chat识别、UX-01/02身份事实及物理N1。M1只接取得真实版本/AX结构证据的provider/profile，独立于Web。每项保留确切源码、一次输入、原目标、原附件、无Send及PASS/FAIL/NOT_RUN，不扩大本轮已取得证据。日常工程决定由负责人和本地Codex自行完成；正式分支统一由root整合，main和发行继续不动。
