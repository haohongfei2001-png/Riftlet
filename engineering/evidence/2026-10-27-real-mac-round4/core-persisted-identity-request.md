# Pro 接口请求：识别已持久化会话的 logical identity

日期：2026-10-27。核对源码：`c9c68a66c4b6ff55ffe8048cff6f1cf781600519`。

**下列是待 Pro 审查的补丁文本；未应用到 Core、未编译、未测试，不代表生产准入。** 本次仅新增此文档，不修改 Core / UI / App、数据库或旧操作。

## 已核实的缺口

该版本页面程序从当前已提交 composer 的 React ancestry 交叉核对 mode / draft props 后，区分两种身份：

| profileID | id 原值 |
| --- | --- |
| `chatgpt-composer-react-20261027-v1` | `local-chatgpt:` + 36 字符 UUID |
| `chatgpt-composer-react-persisted-20261027-v1` | 36 字符裸 UUID |

`Sources/RiftletCore/Models.swift` 的 `LogicalDraftIdentity.isRecognized` 当前只识别第一种。第二种虽可保存进 `TargetLease`，但被当作未识别身份；`conflictsForDispatch` 因此维持同一 serialization scope 的整 tab 冲突，`QueueStore.markDispatchIntent` 拒绝新输入。这是保守拒绝，不应通过删除 UNKNOWN、重写旧身份或更改操作 ID 来消除。

## 最小建议补丁

仅替换 `Models.swift` 的以下识别实现；保留旧 profile 的现有规则，新增一个精确 profile 分支。不改 `conflictsForDispatch`、`serializationKey`、receipt equality 或 QueueStore。

```diff
diff --git a/Sources/RiftletCore/Models.swift b/Sources/RiftletCore/Models.swift
--- a/Sources/RiftletCore/Models.swift
+++ b/Sources/RiftletCore/Models.swift
@@
     public var isRecognized: Bool {
-        guard profileID == "chatgpt-composer-react-20261027-v1",
-              id.utf8.count == 50, id.hasPrefix("local-chatgpt:") else { return false }
-        return UUID(uuidString: String(id.dropFirst(14))) != nil
+        switch profileID {
+        case "chatgpt-composer-react-20261027-v1":
+            guard id.utf8.count == 50, id.hasPrefix("local-chatgpt:") else { return false }
+            return UUID(uuidString: String(id.dropFirst(14))) != nil
+        case "chatgpt-composer-react-persisted-20261027-v1":
+            guard id.utf8.count == 36 else { return false }
+            return UUID(uuidString: id) != nil
+        default:
+            return false
+        }
     }
```

不 trim、不从 URL/DOM 文字猜 UUID、不去前缀后把两个 profile 合并、不生成映射或重新编码已存 id。UUID 格式识别只是 Core 的闭集格式准入，页面身份真实性仍必须由 adapter 独立证明。

预期行为：同 scope、同新 profile 的相同 UUID（含大小写差异）仍冲突；不同 UUID 才能缩小锁范围。这也会使**已经持久化、原本携带该精确新 profile 与合法裸 UUID 的记录**在新代码中被识别，虽无数据库迁移，运行时锁范围仍发生变化，须测试数据库重开路径。旧记录若缺 identity、profile 未知或 id 不合法，继续整 tab 保护；旧 local profile 与新 persisted profile 无论 UUID 是否相同，都保持跨 profile 保守冲突，不做回填。该补丁不自动解除 UNKNOWN、重试输入或更改旧操作结果；跨 profile 拒绝不会因等待、重启或重新 arm 自行消失。

## 建议 Core 锁测试（均待实现 / 待运行）

优先扩展 `Tests/RiftletCoreTests/LogicalDraftIdentityTests.swift` 的现有 helper，沿用 `WebTargetLockTests.swift` 回归，不增加真实页面或输入动作。

1. **精确识别矩阵**：新 profile 接受标准 36 字符 UUID 大小写；拒绝空值、带 `local-chatgpt:`、前后空白/换行、缺连字符、非法 hex、截断/追加字符。旧 profile 仍只接受带原前缀的 UUID；未知 profile 即使 UUID 合法也拒绝。断言 `isRecognized`，避免仅凭冲突测试掩盖格式问题。
2. **新 profile 对称冲突**：同 tab 相同 UUID 的大小写版本、rearm、窗口移动、document 变化仍冲突；同 tab 不同合法 UUID 双向不冲突。不同 UUID 的任意一方畸形则双向冲突。
3. **跨 profile 永久保守**：local A 与 persisted A、local A 与 persisted B 均双向冲突；nil/未知 profile 与 persisted B 仍冲突。不得将 local→persisted 当成已证明的同一草稿映射。
4. **持久化 UNKNOWN / 重开**：以新 profile A 建 UNKNOWN，重开并执行恢复后，A 的新 lease 在 `markDispatchIntent` 仍抛 `targetBusy`，候选保留 `.prepared`；B 可进入 `.dispatchIntent`。旧 A 的 id、target、attempt、phase、已有 receipt/audit 保持原值，绝不自动重放。补一份旧版本格式的序列化 target fixture，证明原已存新 profile 在新识别逻辑下的行为，不能只测新建对象。
5. **旧锁不放宽**：复用旧 nil UNKNOWN 与 compensated/audit 重开测试，候选改为 persisted B 后仍拒绝；另将旧操作设为 local A，候选 persisted B，重开后仍拒绝。确认 UNKNOWN 和补偿记录未删除、未回填。
6. **receipt 仍精确匹配**：新 profile 同业务 UUID 但 focus/document/window 等不同的 receipt，以及新 profile B receipt，均不能用于 A 的原操作；抛 `mismatchedReceipt`，不吞噬、不保存错回执。保留不同 tab/session、非 Web surface、缺 tab 的原有回归。

具备 XCTest 的 CI 可合并运行 `LogicalDraftIdentityTests` 与 `WebTargetLockTests`；本轮不在缺 XCTest 的 CLT 环境重复尝试。测试通过只证明 Core 合成契约，不能代替新 profile 真机准入。

## 明确未解决的安全范围

页面身份依赖当前已观察到的 React props / root commit 信号。无可观察事件的业务 A→B→A（例如绕开受监测 setter、原地改写再恢复）残余仍存在；扩展 `isRecognized` 不补足连续性证明，也不使相关 limitation 测试变成 fail-closed PASS。现有物理首击证据不证明这个新 Core 补丁正确；生产注册表、跨 profile 自动解锁及新重试能力均不在本请求内。
