# 普通 App 两资产原生回执检查点 — 2026-11-15

**阶段一通过：两张新资产各一次真实微图点击，都取得严格匹配的产品回执及明确输入前拒绝。商业 Edge × ChatGPT 双图未通过，文件输入、上传开始、最终完成仍为零。** 本检查点只覆盖已签名运行的 H `d23267fe825f9ad2384b35b03db9fe2692485741`，不覆盖后续 Edge 预算修复源码。

普通测试 App 正常入口 PID 为 53644；本读取器重新计算可执行文件 SHA-256 为 `8f68a1dc1907371271e7a17b90866d1527cac4e48d03ed0a7757f87708b562f9`，与签名包回执一致。[源码、实际可执行文件与读取范围](runtime-identity-readback.json) · [包构建时原始回执](signed-package-receipt.json)。包回执内 `normalAppLaunch: NOT_RUN` 是构建时状态，后续运行由 App 原始日志和冻结发送配置单独证明。

| 新资产 | 本机前测 UTC | 精确回执 | 原始拒绝 |
| --- | --- | --- | --- |
| fresh-04，UUID `A86F0DC4-2B0F-4496-9F8A-DA62830DE4A9` | 12:56:52 | 输入窗 3442，事件 27172，tag 183970661135835；2 App + 7 原生边界 + 1 选择回执 | `edge_click_pin` 序号 13：`documentEditorPin`，108.945583 ms；序号 22：`resolveSelection / invalidReply` |
| fresh-05，UUID `A512DCFC-B06A-4A76-8AE7-2908FC6D365A` | 12:58:06 | 输入窗 3452，事件 10183，tag 267215259898689；2 App + 7 原生边界 + 1 选择回执 | `edge_click_pin` 序号 28：`originalSelectionRecheck`，100.515 ms；序号 37：`resolveSelection / nativeEventFailed(-1712)` |

两张分别由 macOS `screencapture` 生成，哈希和字节数不同：fresh-04 为 `fcd3e2c5748e888c8d47363b441d325361823a828f64452859eb0a13526971f8` / 62,508 字节；fresh-05 为 `568de2784c37e0c6bfcc2de4b81a8eff4d022d72ded5be772ab80ef4d50c8991` / 62,346 字节。原始截图标记来自保存的捕获元数据。普通 App 收录的 UUID、SHA、大小与之匹配；本证据读取器没有查看或重新读取 PNG 内容。两次按序操作间隔约 74 秒，不是快速连续点击验收。[完整分阶段结果](acceptance.json) · [原始 App 日志](acceptance-recent.jsonl) · [首图严格回执](calibration-01-receipt-1.json) · [第二图严格回执](calibration-01-receipt-2.json)

两次前测均是同一隔离 Edge 窗口内的唯一测试编辑器，中性正文完全匹配、选区 14 字符、基线附件 1 张。第二次前测支持第一次拒绝后这些状态仍在；本检查点没有第二次点击后的草稿快照，也没有成功输入后的保留证据。两次均没有创建持久化附件操作。只读数据库为 5 资产、0 操作、0 上传开始，全部图片仍为 pending/visible。[数据库脱敏快照](asset-and-queue-snapshot.json)

原 `restart-01` 两张无回执资产仍保留，未重发、未改判成功/拒绝；fresh-03 也未点击。旧 UNKNOWN 指外部投递回执不确定，不能伪装成数据库已创建的上传操作。更新前数据库及媒体身份摘要已备份，数据库和图片没有提交到仓库。旧 `315978e` 第二张丢回执的根因仍未证明。[旧失败与 UNKNOWN 原件](../edge-double-image-20261115/resumption.json)

在后续预算修复换包前，13:18:34Z 的[独立备份回执](before-budget-fix-backup.json)再次记录 5 资产、0 操作、0 上传开始；5 张原截图及其 5 份私有副本的 SHA/大小与上述快照一致。本读取器只核对该 manifest，没有再次读取图片内容。

## 当前拒绝的解释边界

两次错误属于不同原生阶段，不能合并，也不能把第一张 `invalidReply` 当作网页拒绝编辑器的证据。H 源码使用 150 ms 的总点击预算，并要求每次原生事件至少还剩 50 ms。源码分析正在核对两次 native round trip 与最终原选择复核如何消耗预算。第二张已进入最终复核，依 H 源码的执行顺序，这意味着此前文档绑定返回了 `bound`；该判断来自源码顺序，不是独立捕获的页面回执。

后续源码修复已把 Edge 执行环境准备与文档绑定合成一次原生 evaluation；150 ms 总预算、50 ms 最小剩余门槛和最终完整身份复核不变。新包尚未运行，本目录不把源码推断、性能模型、新增 XCTest 或后续修复测试当作该真实运行包的成功输入、START 或完成。

## 鼠标工具与三个中性对照

V2 发送器验证事件的副本，保留待投递的原事件；每张只投递一对，并有界等待原身份的产品回执，绝不重发。39 项纯安全测试通过，原始受限环境失败也保留。[工具 manifest](neutral/v2-manifest.json) · [39 项日志](neutral/v2-pure-tests-native-context.log) · [本地工具源码](tool-sources/ExactMouseV2.swift)

| 独立中性 AppKit 场景 | 立即退出发送器 | 被动等待原回执的发送器 |
| --- | --- | --- |
| 基线事件对象 | down/up 均收到 | down/up 均收到 |
| 事件序列化完整 round trip | 观察为零 | down/up 均收到 |
| 副本验证，保留原事件 | down/up 均收到 | down/up 均收到 |

[基线原始报告](neutral/run-20261115-01/report.json)、[round-trip 原始报告](neutral/run-20261115-roundtrip-01/report.json)、[副本验证原始报告](neutral/run-20261115-copyreadback-01/report.json)及每次 sender/config/reservation/ACK 原件全部保留。结果只适用于三个有界自有窗口实验，不证明通用因果关系，也不追认旧投递的真实根因。当前商业页面回执通过范围仅是原生入口，不是附件传输。

## H 源码 CI

独立复核确认 H 的五项必要 CI 都在 attempt 1 成功；实际执行 merge `5e07809dbcddbdfe914da8e7af75990c990bb639` 的 tree 与 H 相同。五个新 Edge XCTest 在 ARM64/Intel 的 1,435 项并行测试中实际执行；新两资产无标记 AppKit 测试分别有 0.029 秒、0.059 秒的明确 PASS 日志。原有条件跳过和 appearance 跳过保留。托管 ARM64 普通 Edge 实验仍是首图 `-1744`、第二图 NOT_RUN，不能替代上方本机两图回执。[完整独立复核](ci/README.md) · [CI 元数据、原始日志哈希、逐项执行与跳过](ci/ci-verification.json)

官方 artifact digest 与上传日志相互匹配；本地 ZIP 下载受传输阻塞，没有声称对 ZIP 字节重新计算哈希。没有重跑工作流。后续 Edge 预算修复需要自己的源码 SHA 和 CI，不能沿用 H 的绿色结果。

## 证据完整性与隐私

[manifest.json](manifest.json)逐项记录原始文件 SHA-256、公开副本 SHA-256、原始相对位置和路径脱敏规则。未含机器路径的原件保持字节一致；源码/配置中的本机 home、临时构建目录和 App 绝对路径用占位符替换，公开源码不冒称编译原件。原始工具源码、二进制哈希和未脱敏文件保留在本地工程档案。公开的脱敏配置不是可重新投递旧操作的授权或输入。

此读取器只复制已有证据、在一个只读事务内查询隔离数据库、核算实际可执行文件哈希，并对已保存 trace 复核原回执；没有 GUI、鼠标投递、Apple Events、账号/权限修改、图片内容读取或产品写入。最终商业验收、快速点击、标签切换、无响应、上传失败/完成及成功输入后的内容保留仍未通过。PR #69 保持 Draft，不合并或发行。
