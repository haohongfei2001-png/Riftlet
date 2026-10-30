# 本地真实文件流程与隔离恢复

2026-10-30。本轮按最新裁决跳过被占用的 Chrome 标签和跨任务协调；真实 ChatGPT 首次附加为 **BLOCKED（测试资源占用）**，未接管、重载或输入该标签。以下不是 Web 上传验收，也不是正式组合 App 的完整验收。

## 实际产品结果

| 场景 | 结果与范围 |
|---|---|
| 真实系统 PNG → 私有导入 | **PASS**。上一轮已真实生成的 PNG 保留原件；以保留 metadata 的复制交付到全新隔离监听目录。初始数据库 0 张，实际收录 1 张，原件/监听副本/私有媒体 SHA-256 一致。不是再次系统截图，也没有构造 screenshot metadata。 |
| 微图与历史 | **PASS（AX/原生窗口观察）**。真实 AppKit image/number 输入窗口已显示，实际窗口图像可见；历史中选择唯一记录，显示正确预览、702×482、pending 状态。不是网页模型，人工物理输入 **NOT_RUN**。 |
| 无有效目标的本地点击 | **PASS（CGEvent 安全拒绝）**。窗口所有者与实际路由校验后一次点击；收到原 token、原窗口、原 asset，`noPublishedTarget`，仍 pending/visible，operations=0。普通 capture 本来没有 Web adapter，此项不能用于统计 ChatGPT 冷首击失败率。 |
| 隐藏、暂停、退出、重启 | **PASS**。仅操作隔离 App；重启后 3 张记录、媒体哈希、operations、upload_starts、compensations 与重启前完全一致；hidden/paused 持久保留，WindowServer 上该 App 可见窗口为 0。恢复收录后仍 3 张、0 操作、0 start，没有重复导入；随后正常退出。 |
| 内置截图选择及取消 | 通过现成原生入口启动，后通过“结束截图”取消并核对入口恢复。期间产生 **2 张未按预定步骤触发、无法归因输入来源的 applicationScreenshot**，私下保留。它们不是可计入区域/窗口/全屏验收的成功样本。没有记录原始 down/up 来源，不能断言人工操作、其他任务操作或产品 Bug。 |
| 内置三模式隔离 CI | **PARTIAL**。区域实际系统引擎→输出校验→私有导入/去重 PASS；窗口在引擎返回后、导入/metadata 前触发 `FOREIGN_OVERLAP_VETO`，全屏在捕获前触发同一保护，两者 **NOT_RUN**。单次执行既有探针后停止，不移除遮挡保护。CI 不证明本机物理交互或系统快捷键来源。 |
| Chrome 正确草稿、唯一输入、start、complete | **BLOCKED**。本轮没有 Web 输入，普通上传/重试/候选准入均不变。 |

本轮统计：真实旧原件的隔离交付 1 次，受控微图 CGEvent 点击 1 次且安全拒绝，未归因内置输出 2 张；Chrome 尝试/页面输入/uploadStarted 均为 0。没有新的系统快捷键尝试或人工物理点击，也没有将任何旧 UNKNOWN 改成新操作。

## 文件与时间链

真实 PNG 为 1,167,074 bytes、702×482、RGBA8 非交错；SHA-256：
`a4426f0d551a4ffffe8093bc4454690955324f0f9cffa59133ec30c7f257fd52`。
原系统快捷键来源见 [上一轮原始结论](../native-system-output/README.md)。本轮只验证真实文件后续本地链路，不重新声称 T0 已测。

同一 boot 的原生 uptime（秒），不回填或推测缺失事件：

| 事件 | uptime |
|---|---:|
| CaptureService 首次观察 | 692273.24216958333 |
| 私有复制与校验完成 | 692273.43789275002 |
| 数据库导入 await 返回后记录（非精确提交时刻） | 692273.4400277501 |
| MainActor 回调 | 692273.4400836667 |
| 已解码、输入窗口 visible/eligible 日志 | 692273.45255787508 |
| CGEvent 原 down | 692715.726124625 |
| AppKit 收到该事件 | 692715.74043275008 |
| selection submission | 692715.81188645842 |

首次观察至输入窗口日志约 **210.39 ms**。这不是系统截图 T0→T2 延迟；WindowServer 实际图像另有稍后的截图证明，首次像素呈现时刻未知。该本地点击为预定安全拒绝检查，不能据其晚于显示的时间推算自然点击表现。

## 精确版本、隔离与数据保留

- 专项源起点 `db10d806d026ee38ecbe568b6860c5f5555a1f63`；原生源码保持 `e5d77d3c82bf2769387049e533e93073d36ee6fb`，包含已审 `c308d46` 修复。
- 实际运行的是明确标记的 **TEST-ONLY 四文件 overlay**，不是正式 PR #1 二进制；独立 bundle、目录和监听来源，普通 capture/UnavailableAdapter，Feedback endpoint=nil。完整差异与构建身份见 [isolation.md](isolation.md)。抑制自动 onboarding，因此没有宣称默认首次启动体验通过。
- 本轮没有更改仓库生产 Sources/Tests/Package 或放宽任何安全判据。未取得可归因的本地产品 Bug，不为了交付代码而改行为。
- 旧候选数据根 **31 个文件逐字节哈希不变**，包括 SQLite/WAL/SHM、历史媒体与审计。原系统 PNG 保留；隔离新增 3 张、2 张内置原件、数据库和日志均保留。最初保留检查误把 manifest 的相对路径按 cwd 解释，已按原根纠正并保留两份检查记录；没有实际文件丢失。
- 系统截图 preferences 前后语义一致，未修改 TCC、保存习惯或 Chrome 配置。两次隔离 App 进程均正常退出。
- 构建 receipt 是“构建者尚未启动”的交付快照；后续 root 运行、退出、重启与最终结果有独立 runtime receipt，不应将旧快照误读为整个测试未运行。

私有 runtime receipt SHA-256：`40ee3353636fa620fe0b84087850c1be31f0704b9f3f4cfbade5e353ebe67224`。已将完整本地交付、四文件 overlay 源码、App、所有媒体/数据库/日志与 helper 存入持久私有证据目录（只排除构建缓存），339 文件清单 SHA-256：`8c3daeb7276af7d5b48d8d03901c409f3b40563220de12a114487f39530d46ad`。另核验 8 张 PNG 扩展属性，补齐首次字节复制未携带的 5 张属性后全部与来源一致，339 项字节哈希仍完全匹配；原件从未被修改。CI 日志作为后续补充清单保留。原图、窗口图像、完整路径、数据库、原始日志和 boot 标识不公开。

## 验证与审查边界

- 本次独立执行器提交：`07f2249ad189d7c5d318496bcfa18a3ddf65f4f1`；[macOS CI 41008775790](https://github.com/haohongfei2001-png/Riftlet/actions/runs/41008775790) completed/success，**原生模式结论仍为 PARTIAL**。一次 XCTest 覆盖现有三模式，逐模式结果见 [ci-native-outcomes.json](ci-native-outcomes.json)。区域为 CI 1× 屏、128×96；不能外推 Retina、鼠标选择、全屏/Spaces 或用户桌面。
- 工作流首先核对 Sources/Tests/Package 与 `e5d77d3` 无差异；没有重跑整套原生回归。既有完整 native CI `40914439852` 仅作为未变源树的历史结果引用，不冒充本次全套运行。临时 overlay 则有本次真实 release 构建及 strict 签名检查，不受原样源树 CI 等价保证。
- 单次 XCTest 的既有原始 summary 与 standalone benchmark verifier 格式不同，本次没有强行转换数据复用该 verifier。工作流成功只证明执行无断言失败，不会升级原始 NOT_RUN。
- 隔离构建/集成差异已获独立 PASS_LIMITED 审查；本地实际结果的非作者复核在 [review.md](review.md) 单列，不替代正式组合 App 的审查。

## 正式负责人可取的内容与停止边界

[integration-delta.md](integration-delta.md) 已实测：相对正式 PR #1 `98e66a9`，先取已审 6 文件修复，再取可选 9 文件诊断，共 14 个唯一路径，三方临时 index 应用无冲突；973 个其他 Git 对象不变。候选 tree 不是已构建/已审的正式提交。专用 workflow、TEST-ONLY overlay、研究元数据不要整体合入产品。

本轮不要求创始人体验。Chrome 恢复入口仍是：确认专用资源无其他输入所有者，新的独立测试操作，按可见操作条件执行一次原生微图选择，并核对点击前 ACK、原目标、唯一输入/start/complete；不能重放本轮旧图片或旧 UNKNOWN。区域/窗口/全屏的本机人为交互需无竞争桌面输入条件；本轮未归因输出不能替代它。保持原准入，不新增架构研究或重复上传。
