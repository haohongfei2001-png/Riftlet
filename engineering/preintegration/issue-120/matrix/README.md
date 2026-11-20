# #120 W5 验收矩阵

`results.json` 从仓库随附的 #121 原始规划矩阵读取 40 个组合，含 16 核心格、独立的国内千问和国际 Qwen、原 Firefox 条件记录。无须联网或切换分支。读取本地规划文件并核对固定 SHA-256；浅克隆和源码分发包同样可用。按 `requiredLiveCases` 和 `sharedCases` 可展开逐格数据。没有完整 case 的层级保留 `NOT_RUN`，独立记录已实际执行的子项。

从本目录执行：

```sh
python3 matrix.py
python3 matrix.py --browser chrome --provider chatgpt --case E01 --level L1
python3 -m unittest -v test_matrix.py
```

需要重新采集时，每批使用新的输出目录。实际运行 Chrome 或 Edge 须有对应安装包，使用临时独立配置、headless 模式与 loopback 控制页。输入由仓库内原网页程序执行。此入口不启动普通可见窗口，也不接管现有 profile。

```sh
out=$(mktemp -d)
python3 fixtures.py simulation chrome "$out"
python3 fixtures.py headless chrome "$out"
python3 fixtures.py headless edge "$out"
python3 matrix.py --fixtures "$out"
```

| 实际对象 | 本次可重复证据 | 入表范围 |
|---|---|---|
| Node 模拟的 Chrome × ChatGPT | I01 setter 抛错不重入、I03 portal 归属、E01 占位/旧卡拒绝 | 三个 L1 子项 |
| 真 Chrome 与 Edge 二进制 × ChatGPT 原网页资源 | 每个环境 31 次 setter、31 次 change、零发送；23 个错误卡形态反例和 4 种原卡退役情况 | 两个页面层 E04 子项；缺普通签名 App 和原生宿主，L2 待测 |
| 下一周期签名 App 与真实服务 | 尚无该候选，未启动线上测试 | L3 核心 0/16 |

记录与原始 TAP 成对保存。回放校验 #121 规划 hash、网页程序与夹具文件 hash、运行时目标、TAP 内容摘要、具名用例实际执行和独立页面计数。测试资产全部为合成。已有包、模拟通过和 headless 页面结果均不能改变产品级状态。

## 后续同包原生记录

`evidence.schema.json` 定义两种独立文件。运行记录保留来源提交、App 与 DMG 摘要、build、环境、Provider 版本和程序摘要、原生 operation/invocation 摘要与四项时间。观察者独立提供实际原稿卡、原文/选区/旧附件、误投与发送观察。正式入口在完成签名来源、主线基线、证据真实性和非作者的审核后，单独提供候选身份；不要从待检查的运行记录反推出期望候选。

```sh
python3 native_evidence.py reviewed-candidate.json native-run.json independent-oracle.json
```

此命令只读，可交叉核对最小 F01–F06/T01 正向与切换验收记录。T01 在建立 durable operation 之前安全拒绝时，记录原点击摘要、目标和本图摘要、零输入及独立页面/托盘观察。此时 operations 为空，preIntentRefusals 必须有双边匹配的真实点击，不能填造 operation ID。成功返回 `MATCHED_RECORD_ONLY`，不会写入矩阵。JSON Schema 负责字段结构；Python 检查跨文件的包、Host/Provider/case/surface/run、独立观察者、操作归属及观测结果。对 L2 要求实际签名隔离 composition、完整 inputEntered；L3 需要正常模式及已登录测试会话。只读核对不能独立证明外部收集者的身份、公证或上游测试是否真实，证据仍需非作者核对。无可见输入计数的 L3 填 null，单独保留原卡增加恰好一张的证据；只要缺少必要事实，即拒绝正向核对。F03 取原生实际点击时刻，检查至少三组小于两秒的不同图片/操作，约 0.5 秒和 1.7 秒分别按 350–650 和 1500–1900 毫秒核对。完整原始时延应随证据保存。F06 检查前一同图的正面回执先于明确新点击。

当前预集成刻意无 L2/L3 输入到 release 的通道。后续 W7/W8 使用正式候选原件、实际原生输入和独立页面观察，再接入正式准入。共享异常、系统资源、升级、分阶段崩溃和签名安装各有后续环境及证据，现有两种文件的结构不替这些项目签发 PASS。每次补测须在独立批次保存旧失败和超时，不能覆盖证据。

目标摘要用于比较是否仍在同一草稿。它覆盖浏览器及进程出生身份、窗口、标签、document、composer、draft epoch 和当前 Provider/profile/surface/mode。点击票据、operation 和 invocation 随每次点击独立记录；将它们纳入跨图比较的草稿摘要会把同稿的两次合法点击误判为切稿。原生各阶段时间使用同一单调时钟，未知值保留 null。明确在输入前拒绝的本图不能同时报告服务就绪、原卡已接收或收起耗时。

### 独立复核后的证据校验

发布的三份历史夹具收据固定到 #122 的 4daab3f。每份收据包含原始 TAP 摘要。新采集文件可单独回放，输出中 reviewedReceipt 表示是否与已审收据逐字节一致。改动测试计数、追加失败或中止行、混入第二份 TAP 总结均会使正向声明无效。

原生记录按批交叉核对时，把该候选的全部 run/oracle 文件对一次传给 native_evidence.py。运行、操作、调用、拒绝点击以及已接受的新卡身份均须跨批内各次运行唯一。接受观察需给出独立确认的提交载荷摘要 payloadSHA256 和原稿内新增成员摘要 newCardSHA256；成员摘要应绑定原稿身份、页面内卡片实例和该次新增，不能仅从文件名、图片内容、列表下标或 native operation 推导。观察器无法取得可靠关系时保留未核验。对 F04 的新草稿与已保存聊天分别核对不同的原稿身份，F03 三组须为连续点击。共享的 F04/F05 观察可以引用原有运行；复制一个 operation 再冠以新的 run 不构成独立采样。

结构和哈希核对只能产生 MATCHED_RECORD_ONLY。记录中填写两个不同名字仍无法认证独立观察者；证据原件、来源和受审 App 身份须由正式外部准入建立。批次内的复用检查对分开调用的其他文件没有可见性，归档时须用全集重放。当前核心 L3 仍为 0/16。

### 正式候选证据的计算入口

正式集成后，在当前签名工具链的 Mac 上运行以下命令。没有正式证据时，原有 matrix.py 继续重放本仓库的预集成快照。

```sh
python3 matrix.py --formal-evidence "$receipts" --package-workspace "$package_workspace"
python3 -B -m unittest -q
```

正式入口固定从 GitHub 的 #122 读取 main 基准和当前准入提交 H。H 必须只改源码准入文件；它的直接父项 G 是受审树。在 G 的本目录放置 acceptance-index.json。H 的独立审查 report 须在已有审查字段外明确承诺 issue120AcceptanceIndexSHA256（G 上索引原始字节的 SHA256）、issue120SignedCandidate（完整候选身份）和 issue120Verified107Merge（W0 已核验的 #119 合并 SHA）。代码验证 G 和报告对应、候选继承最终 1.0.7、资源 build 已增加、从候选源码到 G 产品文件保持一致。归并 G 到 main、发行授权及五项 CI 的收口继续由 W7/W8 负责。

候选身份的四项为 sourceSHA、build、appSHA256、dmgSHA256。其中 appSHA256 沿用 W0 定义，即完整 Riftlet.app 文件清单去除公共路径前缀后，按排序无空格 UTF-8 JSON 计算的 SHA256。核验器对实际签名工作区复用 release-dmg 的 App 清单、公证、签名、公证票据、Gatekeeper 与只读挂载校验。核验读取了 build 53 历史 DMG 以验证现有包格式；它不会进入下一阶段的矩阵。

索引的 schema 为整数 1，candidate 为上述身份，runs 是包含 run、oracle 两个摘要的数组，observations 是经过独立审查的专项观察收据摘要数组。所有原件在 receipts 下直接以内容的 SHA256 命名，包含敏感内容的原件须留在受控存储。每个 native/observer 文件对由 audit_batch 一次核对，实际输入次数或正向里程碑缺失保留 UNKNOWN。按浏览器版本、系统架构、Provider 版本及资源、模式、语言、账号类型分别归并。不同配置不拼凑成功。新增负面观察会保留，不因同一配置的其他成功批次而消失。

专项观察内的 candidate、kind、scope、level、case、status 绑定 productRaw 和 observerRaw 两份原始记录；双方须各自给出相同的候选与范围、自己的角色 product 或 independent、采集者 actor、实际 status 和独立原件 artifactSHA256。scope 字段按 global、host、provider 或 cell 从 VARIANT 投影。经审查的专项收据可证明共享门槛；即使双方填写 PASS，仍不能替代 F01–F06/T01 的 native/oracle。审核者负责确认原始日志、操作和观察者身份；摘要检查本身无法确认测量来自真实现场。正反例和完整 16 格的合成输入只在 test_formal_results.py 的临时目录生成。

计算分别给出每种配置的案例、L1/L2/L3、整包门槛以及 eligibleForReleaseReview。L3 要求同包全部 F01–F06/T01 和该格真实服务恢复；L2 要求签名 App 的首次附加及适用宿主、Provider 和共用反例。Safari 冷定位/执行环境、Brave 默认 Shields/执行环境分别有独立宿主门槛。单格记录通过但缺安装升级、性能、CI 或其他必需证据时，继续标记 PARTIAL。READY_FOR_RELEASE_REVIEW 只表示 16 个核心格记录达到复审条件；计算不启用产品配置、不修改官网或发行状态。
