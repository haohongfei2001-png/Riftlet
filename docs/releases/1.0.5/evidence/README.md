# 本次受控源码实验

范围：Linux / Node，现有 `Tests/WebPageProgram/independent-input-fixture.cjs` 加冻结的生产页面程序。没有运行真实 Chrome、Apple Events、macOS App 或 ChatGPT。本目录是历史审计见证，不是新产品回归套件。

审计者和另一位复核者各执行一次，结果一致。生产脚本 SHA-256：`5fffb4b9fcee31af401a00259b3cf0cdbf7577c8f990dddbbd1ec99bfe16de3f`。脚本强制要求输入工作树HEAD为 `f3153b10dac4445720f1c20c8836ddbbea625c49`，避免在修复后源码上误当作通过标准。

```sh
git worktree add --detach /tmp/riftlet-104-audit f3153b10dac4445720f1c20c8836ddbbea625c49
node docs/releases/1.0.5/evidence/reproduce-baseline.cjs /tmp/riftlet-104-audit
```

| 实验 | 实际观察 | 可以推出 / 不能推出 |
|---|---|---|
| 同附件START后加入失败标记 | 仍uploadStarted、hasError=false，setter=1、send=0 | 当前脚本不会观察该START后错误；不能据此认定真实服务使用该错误DOM |
| 101个成功START | 101条operation/DOM binding，chunks=0、send=0 | 元数据/DOM绑定无退休；不能宣称101张完整像素缓冲泄漏或测得特定RSS |

原始输出在 [observed-baseline.ndjson](observed-baseline.ndjson)。脚本退出0表示复现了本次审计的旧行为，**不表示产品已通过1.0.5验收**。实施后为修正后的契约补针对性反例，不修改此历史见证来制造绿灯。
