# 持续使用、UNKNOWN 与输入前拒绝：产品修复交接

2026-10-30。独立分支 `codex/riftlet-transfer-lifecycle-20261030`。
正式 PR #1 起点实读 `98e66a956d55b5fac71718bc627dd89705b2a506`，PR #15 `623d3725d0b3096f1dc7332e6cae11f47f7002c2`；二者和 main 均未修改。本轮未启动或占用 Chrome，没有打开原用户数据库、媒体或旧 UNKNOWN。

**结论：A/C 的限定根因已修复；B 的安全继续机制已实现并通过确定性测试，但真实 Web 资格仍关闭，不能宣称真实同草稿 UNKNOWN 阻塞已全部消除。**

## A：跨过累计 32 限制，保留原身份

正式源以累计 generation 和单 state operation 数量拒绝第 33 次；已完成/已移除附件也没有归还容量。在正式 `98e66a9` 的页面源码上执行本轮两个回归，实际得到 `BEGIN_REFUSED` 与 `LEASE_GENERATION_LIMIT`；相同回归在修复版通过。

现在的 32 限制约束**仍持有输入字节载荷的操作**，不是历史身份总数。完成/失效释放载荷；连续且可证明未变的 binding 可以续租，原操作 target 不被替换，旧 lease 仅用于原操作观察。真正失效的 generation 转成不持有 DOM/观察闭包的数据型只读记录，释放监听器与失效引用，保留 operation/asset/attempt/hash、原 target、开始和必要证明/错误审计。原 ID 永不重用，未清空 registry。

限定 PASS：同草稿 48 次完成输入（分别覆盖旧附件保留/移除）、48 次真实失效 generation 后第 49 个 state、48 次失焦续租、原附件迟到失败与另一附件独立完成。活跃载荷已占满 32 且无法释放时仍安全拒绝；身份审计记录在页面寿命内仍线性保留，不承诺常数内存。旧 state 无新能力时不追溯授予新证明。原有不可观察的业务 A→B→A 类别仍不受支持。

## B：结束输入调用不等于允许继续，必须另有资格

原锁包含两层：QueueStore 对所有未决操作检查目标冲突，SQLite 唯一索引又禁止同目标有两个未决行。原 uploadStarted 只改变可见性，没有持久的 append 返回事实。

新增机制同时要求：

- B 是新的有效 AcceptedSelection，保留原时间、target、visibility revision；输入前继续复核。
- A 的原 append 已返回；调用 nonce、完整身份、原 start receipt 与独立 continuation evidence 精确关联。
- 开始与“后续输入不替换原附件”分别获准；全部冲突 A 都满足条件，target 完全相同、逻辑身份已识别、同一运行期 Coordinator owner，且不是 compensated。
- 判定、新 B 槽位、dispatch intent、调用 nonce 都在同一个 SQLite 写事务中完成；之后 B 只有一次 append。

SQLite 保持 user_version=3，增加兼容扩展 `dispatch_exclusive`，旧行默认 1，原排他索引保留对这些行的约束；只有满足上述全部条件的新 B 在原子事务中取 0。不改原 target_key/target_json，不改 A 的身份、状态或锁标记。Core 仍扫描所有未决行，所以 B0 没有 start、A 完成后 B 独留 UNKNOWN、新 owner/重启等均不能放行 C。v1/v2 升级与扩展整体事务化；既有 v3 加锁后重读，扩展失败连同索引/列回滚。

限定 PASS：受控适配器中 A 获准开始后 B 实际继续，分别覆盖 B 成功/失败、48 个独立未决身份、多连接竞争、A 迟到补偿、错误附件关联、未返回调用、缺资格、新 epoch/new owner 和旧 v3 无调用记录。旧列逐字段保留、并发迁移、幂等与回滚均有回归。

**Web 不产生 continuation evidence，App 中新的两份 continuation registry 仍为空。** 目前真实证据不能证明第二次设置同一个 `input.files` 不会替换/取消 A；不能借用既有 start/completion profile 开锁。旧 UNKNOWN、commit 不明、跨重启未复核的资格继续保守。不要用旧程序接管新测试库。

## C：三种严格未输入结果，其余保守

`dispatchIntent` 原子生成调用 nonce。PreInputRejection 必须匹配当前 Coordinator 调用、原 operation/asset/attempt/hash/full target/nonce，且持久状态仍为 dispatchIntent、没有 receipt/start/返回记录；否则当前操作仍 UNKNOWN，不能退休另一个操作。

可恢复为保留原图的 failed/visible（若用户已移除/归档则保持其意图）：

1. 请求身份等前置检查后，本地 preflight/文件验证失败，尚无页面调用。
2. fresh begin 已完整确认新分配，commit 从未调用，又取得完整身份/nonce 的不可逆零输入退役证明。
3. fresh begin 因 32 活跃载荷容量拒绝：页面先为这个从未使用的新 ID 登记不可输入 tombstone，再返回完整的零输入证明。

下一次输入必须是新的用户点击、新 operation/attempt；不是自动重放，也不是 safe-retry。适配器还保留已进入 operationID 的轻量防重记录，直接重复旧请求不能制造本地未输入证明。

仍 UNKNOWN：重复/legacy 身份，nonce/证明缺失或不匹配，begin/discard 回执丢失，commit 已调用或结果不明，以及其他没有充分证明的拒绝。不是所有 begin 错误都能恢复；错误字符串、等待超时和最终失败标签不构成证明。reconcile 不创建调用资格，不重新输入。

## 验证、首次失败与独立审查

已测源码 **`f7f8acdd842005a2b65e914291f3a2912c4e4124`**。
[最终 macOS CI 41017793874](https://github.com/haohongfei2001-png/Riftlet/actions/runs/41017793874) completed/success：JS 167 pass/0 fail；完整 Native 套件成功、枚举 779 个用例；release App/ad-hoc 签名与三个离线自检通过。枚举数不意味着环境依赖用例都是真机 PASS。详见 [ci-results.json](ci-results.json)。本机完整 Swift build 成功；本机 CLT 缺 XCTest，Native 用例交给 CI，没有伪称本地执行成功。

[首轮 CI 41014794987](https://github.com/haohongfei2001-png/Riftlet/actions/runs/41014794987) 保留为 FAIL：暴露了 SQLite 唯一索引第二层阻断、过宽附件别名检查对 legacy 只读观察的影响，以及损坏文件用例的旧 UNKNOWN 预期。对应修复后才运行最终 CI。迁移审查另纠正了隔离 v1 fixture 中残留未来版本 metadata，生产冲突处理未被放宽。网络推送超时后最终远端 SHA 一致；没有修改系统网络配置。

非作者审查见 [review.md](review.md)：Core/SQLite 与页面分别由非作者审查；发现的问题已修复。没有变更正式组合审计、source review pins 或历史准入。

## 正式集成的最小取用范围

1. 若正式工程尚无 c308 修复，先取依赖 **`973a3e8c41b833dd47d655bd837e9ba5ebb40d7a`**：从 c308 提取的 3 份生产修改和 3 份回归，共 6 文件；没有取自然时间链诊断、浏览器架构实验、TEST-ONLY overlay 或旧来源审计。
2. 本轮产品提交依次取：
   - `9790cc3a5206f115e543399f1e63619227aa62f1`
   - `90dc466ada9acd24d7172607ef8e585a1a1010f3`
   - `f7f8acdd842005a2b65e914291f3a2912c4e4124`
3. **不要取** `f02ddafbaed7bab1bc843193fa4fef7b8b1a3515` 的专项 workflow；证据文档可作为交接参考，不整体代替正式 admission。

本轮产品差异共 14 路径，原 Feedback endpoint、薄界/UI、磁力、Resources、Package 不变。临时 index 中将依赖和产品 Sources/Tests 应用于正式 98e 基线：**0 冲突**，所得 tree `f043c283eeb49e1f3f8b3c2640ea43c7bbeeabde` 的 Sources/Tests/Resources/Package 与已测源完全一致；这不是新正式提交。完整校验在 [composition.json](composition.json)。若正式负责人已集成依赖，应逐文件跳过同等变更。

## Chrome 空闲后仍需的验收

全部真实 Chrome/物理端到端本轮均 **NOT_RUN**。需要新隔离样本验证：长期附加/移除及旧 v13 升级后的观察连续性；A 上传未结束时 B 是否保持独立附件；真实导航/失焦/刷新、迟到结果和传输丢回执。只有独立双附件隔离证据审查通过，才考虑启用 continuation；本轮不开放普通上传、生产新权限或 safe-retry，也不重传历史图片。完成此交接后停止扩展，由唯一正式负责人集成。
