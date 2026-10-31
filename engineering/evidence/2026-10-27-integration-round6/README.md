# 第六轮性能与严格目标识别：正式合流证据

2026-10-27（北京时间）。已测组合源码 **`81b6a61b4e648a1b8d6ccf4b569fd6d727a0cc76`**，双亲为正式 `1246c4a58119667ea48d1711f614c23717de58ad` 与第六轮交接 `65f7d54121a637e8a97d2f25f8bcd8069393eb4d`。共同祖先 `3bb13999b0f444c7748804eef1976e179a52a85e`。仅纳入其后的三个独有提交：`7878de3`、`c000cc1`、`65f7d54`；没有重复 cherry-pick 第五轮或压平双方历史。后续文档检查点保留此源码/测试/构建输入；精确正式 HEAD 见 [Draft PR #1](https://github.com/haohongfei2001-png/Riftlet/pull/1) 最终交接评论。

## 实际代码与组合边界

- v12 仅由代码配置最多 **256 KiB** 分块；通用/旧程序默认 **64 KiB**，native/page 总图上限一致为 **8 MiB**。逐块原 operation/attempt/index ACK、同一 no-follow 文件描述符两遍 SHA-256、大小/文件身份复核、页面 commit hash、唯一 input 与完整目标仍保留。丢 ACK/不确定 commit 不自动重发。
- 当前页面 schema2、早 start 返回及独立最终观察保留；增加冻结原 v11 的只读恢复，因此现为 v6–v11。旧操作仅 observe/schema1，不安装输入程序、不修复停用闭包、不补造 start 或 identity，不重新上传 UNKNOWN。
- Chrome 当前选择优先从一个严格绝对 tab-ID→window-ID→null descriptor 读取。四个精确字段、type/enum/utxt、ASCII 正十进制 Int64 均严格检查；不支持的形状走既有 ID 读取路径，transport 错误直接抛出。PID/launchDate、输入前原窗口/标签、capture 返回与完整页面 target 复核未减少，诊断日志不等于 ACK。
- **正式 App/Core/UI/Capture/GUI helper/Package 原样保留**：首次使用、`PassivePermissionResume`、被动权限预检、冻结原点击、SQLite v3、原生历史与快吞噬生命周期都没有回退。普通收录仍不上传，Web 仅隔离生成图片模式；start/completion 的开发组合不授予生产或安全重试。
- root 的唯一构建增量是复用当前测试产物，详细报告现有5个 Foundation 描述符用例。没有另写 Coordinator 或队列；第七轮只固定[最小共享接口与审查标准](../../../docs/ADAPTER_CONTRACT.md#第七轮顺序调度共享边界-v1实现待正式交接)。

## 实际 CI 与独立审查

第六轮原交接的 `NOT_RUN_QUEUED` 保留为历史。现已独立取得来源 [CI40513086114](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40513086114) / job122219591897 的完整日志：精确 c000cc1、325原生/72页面/54legacy、Release/签名/三个自检通过；这不代替下面的新组合测试。

组合源码 [CI40523594732](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40523594732) / job122256992376 **completed/success**，成功状态记录于 **22:44:24北京时间**。环境为 macOS14.8.9 /23J631 /ARM64 /Apple Swift5.10。

| 项目 | 实际结果 |
| --- | --- |
| 原生测试 | **380**：Core117 / Adapters121 / Capture63 / UI52 / App27 |
| 当前页面／legacy VM | **72 /54**，全部通过 |
| 生命周期／首用／Capture详细复跑 | **13 /3 /15**，逐项 passed、0 skipped |
| 呈现／Web组合／权限恢复／严格描述符详细复跑 | **4 /5 /8 /5**，逐项 passed、0 skipped；53项详细复跑均已包含在380中 |
| SQLite与原操作恢复 | v1→v2→v3 /v2→v3、迁移回滚/未来拒绝、UNKNOWN重启、首份start、迟到错误补偿、完整目标/跨profile锁等通过 |
| 回放与离线辅助 | 55文件/19用例/89轨迹前缀/2明确SIMULATED迟到错误；故障8、只读probe12、第五轮helper9/4/2、包装12通过 |
| Release／bundle／ad-hoc签名 | PASS |
| 四项App/helper自检 | PASS；CHROME_NOT_RUN、GUI_NOT_RUN、PERMISSIONS_NOT_REQUESTED、GATEKEEPER_NOT_RUN仍保留 |

实际 CI checkout 为 `ba63e76d481a5f11d101b7fc512e442d0a7578b3`，双亲 main `eba1a4f…` 与81b6a61。完整树可包含 main 的网站差异，**不能称两个完整tree相同**；root核对13组构建/测试/回放对象，非作者另取GitHub根对象复核均相同，没有合并main。实际完整日志192,634字符；[verification.json](verification.json)保存380个测试名、具体详细用例、原证据hash与对象，[ci-excerpt.txt](ci-excerpt.txt)保留138行实际日志。

root与三个独立执行者实际并行，分别审查Web传输/旧恢复、Chrome身份/权限组合、真实证据/顺序提案；没有共享源码争写。源码、root新增workflow和共享契约均有非作者审查；实际CI全日志及来源对象也独立核验，[review.json](review.json)记录范围。当前Linux不冒充本地Swift/真实Mac。独立实际运行的72+54 Node用例属于合成页面验证，提案lab10项不属于产品或正式Swift验收。

## 真实结果的准确范围

| 第六轮真实记录 | 可接受的结论／限制 |
| --- | --- |
| 7878de3 + 两个第五轮验收overlay | 相同3,147,775-byte生成图的新上传样本；一次input、获准start和独立最终proof |
| 历史53ebcc4对照 → 新7878de3样本 | 点击至AppKit close **5.510→3.669秒**，降低约33.42%；每版一次，队列中capture/observe负载不同，不是统计保证或完全归因分块的因果估计 |
| 分块与页面区间 | 49→13块，分块跨度2.771→0.893秒；页面input→start **2.178→2.235秒**，不能称页面上传加速33% |
| c000cc1 + 同样overlay | **三次只读capture、六次fast identity read、零新选择/输入**；不是最终源码的新完整上传验收，fallback未真机触发 |
| 无完整ACK冷首击 | **产品FAIL／安全拒绝有效**；普通草稿样本的原事件早于native完整校验约6.365ms、App发布约7.247ms，较晚ACK没有回放点击 |
| 同草稿第二张B | **产品FAIL／targetBusy输入前取消**；B原freeze accepted，仍无input/start；不是图片上传失败。A/B同logical draft但完整lease和host epoch不同 |
| 物理GUI／新ABA／MID／安全失败／自包含修复 | 本轮未验收，保留旧问题与限制 |

原真实运行环境 macOS27.0 /Swift6.4 /Chrome156.0.8078.48，点击为 software AX、physical=false。正式1246版本的首次使用权限前置不在上述样本中；**新组合二进制的真实权限、恢复、冷首击和实际时延均NOT_RUN**。实际动画请求仍为0.24秒，不是正式默认0.120秒实测；AppKit close也不是像素呈现。完整分析及反例见[13份原交接文件](../2026-10-27-real-mac-round6/README.md)。

## 原始数据与证据保留

第六轮13文件逐字节保留，目录树 **`55eacd6b1d654239f1b4660e91b850e01ba966d1`**；第五轮27文件也保持原树。没有修改原queued记录、失败案例、lab模型或私有manifest。

公开ledger声明schema3、原16份媒体未变、当前22资产/25操作、3补偿/4start及旧UNKNOWN保留；私有manifest33条共3,707,821 bytes。我们只核对公开脱敏记录的字段/hash引用与数值一致性，**没有本机私有原日志/数据库/媒体，不能独立重算这些原内容hash或重新做逐行保留对照**。现manifest不等同于DB/media inventory；后续本地验收继续保留私有基准和比较产物，不将私有内容上传公共仓库。没有清库、删除原件或重输旧未决图。

## 第七轮直接接入

本地Codex第七轮继续独立实现及真机验证，本会话未获取/读取/合入其进行中分支。接入时保留正式App而不是用旧e89覆盖。现 `AttachmentAdapter` / `TransferReceipt` / uploadStarted v1接口不变。

共享契约补足第六轮提案与正式权限组合的差异：原点击的完整边界和sequence必须在权限await前固定；唯一Coordinator drain使用新鲜、非capture、非请求权限的preflight；无intent选择可有界等待，intent后不能重新append；所有取消必须结束序号且允许未来新点击；解除锁发生在查询后park前也不能丢唤醒。原lab没有这些完整保证，不照搬为实现。本轮没有放开同草稿start/UNKNOWN或跨profile锁，没有准入另一资产的并发或提前输入。

[可运行开发App/helper/日志](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40523594732/artifacts/12743890195)：1,656,810 bytes，GitHub制品元数据SHA-256 `471f46ba8b32e14d0a7335a240e180c796ac16d29fd85233a91862769389b554`，保存至2026-11-10 **22:44:17北京时间**。这是ARM64/ad-hoc开发包，未公证/公开发行，没有声称在本环境下载重算制品。

工程入口 `Riftlet.app/Contents/MacOS/Riftlet --web-acceptance --acceptance-trace`，只用新生成图片，沿用原隔离Web数据根及全部UNKNOWN/审计/媒体；旧操作只读observe。复测需关联原事件→permissionRequestID→原ACK/完整target→唯一input→start→持久观察→UI→最终事实，并单独覆盖fallback、冷首击和第二张顺序提交。main、网站、设计与品牌不变，PR #1保持Draft，生产与安全重试仍关闭。
