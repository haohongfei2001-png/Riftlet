# 第五轮真实快吞噬与首次使用工程：正式合流证据

2026-10-27（北京时间）。已测合流源码 **`caa6a65b69c6038154a2fff65f2fb1157125bb7e`**，双亲分别为正式首次使用检查点 `e655b1e04241990ec35acbb79b5b6bc8ee95b960` 与第五轮原交接 `3bb13999b0f444c7748804eef1976e179a52a85e`。原始已测 Web 源码为 `53ebcc4da4b0df508edc11f6ead9ea4d8a843dad`。后续文档检查点保留此源码/测试/构建输入；确切正式 HEAD 见 [Draft PR #1](https://github.com/haohongfei2001-png/Riftlet/pull/1) 的最终交接评论。

## 实际集成

- Web v11、schema 2 的原进度开始观察/严格解码/正常化、append 早返回，以及 v6–v10 schema 1 原操作只读兼容，与第五轮交接源码一致。初始缺数值仅等待，后续两个有限递增且小于100的原节点样本才可能给出开始；保留唯一 input、File hash、完整身份及序列/时钟校验。修复真实 NodeList 观察缺陷，未放宽最终图片完成判据。
- `WebAcceptanceConfiguration.receiptPolicy` 在唯一 `.webAcceptance` 组合中准入 `chatgpt-web-zh-progress-start-development-20261027-v1`；运行时与打包自检共用该策略。普通模式仍是 `UnavailableAdapter`，生产 start/completion/retry 和 synthetic retry 注册表均空。页面不能自行指定 profile 或重试权。
- 采纳两个已审查 overlay 的最小内容：AppKit scheduled/start/close 回调、已提交可见状态观察上界、仅可见 synthetic 行的 AX identifier/Enabled。原行选择保护和窗口排序保持；失败的 `acceptance-ax-window-overlay.patch` **只存档，不应用**。
- 保留 SQLite v3、Capture、原生历史、首次使用/设置界面与权限保护。新增回归验证 input 不吞、start 隐藏且未成功、UNKNOWN 数据库重开只观察、较晚 READY 不重复改变可见修订、迟到错误补偿与不重传。没有数据迁移版本变化或清库。

## 修复实际发现的权限恢复缺陷

e655b1e 在首次 Chrome 未运行/未获授权时不会安装 armer/watch，其激活/唤醒观察器也位于被跳过路径，之后只能手动设置重检。现以 `PassivePermissionResume` 在独立宿主事件中做新鲜被动检查：仅 Web 验收模式、Chrome 激活或唤醒、未安装观察器时请求；合并事件、丢弃旧代际结果，取消后等待旧调用排空，不缓存授权、不新增轮询。原安装 latch 保留，恢复与查询 await 后复核取消/终止状态。

点击在权限 await 前冻结的完整 target 仍原样交给 Coordinator；没有 ACK 不等待较晚 ACK，也不重捕获/回放。arm、点击、背景观察的原被动权限保护保留，新增 `permission_check` 仅在显式 trace 中记录起止时间及 asset/capture/attempt/epoch 关联。新权限检查对真实时延的影响仍需新二进制真机测量。

原 checker 仍选择第一个运行中的 Chrome，而真实输入/观察按前台或原 lease 进程复核。跨实例保守误拒没有本轮真机复现，保持未验证范围；没有为此扩大第六轮工作或跳过权限/目标验证。

## 完整 macOS CI 与非作者审查

[run40515643640](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40515643640) / job122228775354，completed/success 记录于 **21:53:30 北京时间**。环境 macOS14.8.9 /23J631 /ARM64 /Apple Swift5.10。

| 项目 | 实际结果 |
| --- | --- |
| 原生测试 | **369**：Core117 / Adapters110 / Capture63 / UI52 / App27 |
| 原生命周期／首用窗口／Capture 详细复跑 | 13 /3 /15，全部 passed，0 skipped |
| 新呈现边界／Web组件组合／被动权限恢复详细复跑 | 4 /5 /8，全部 passed，0 skipped；均已计入369，不重复累加 |
| 当前页面／旧版只读 VM | 68 /45 |
| 第五轮诊断 helper／初始 probe／版本化 probe | 9 /4 /2，明确离线夹具 |
| Python 包装拒绝路径 | 12 |
| 历史回放／故障／只读 probe | 55文件、19用例、89trace前缀、2明确SIMULATED迟到错误；8 /12 |
| Release、资源/许可/bundle、ad-hoc签名 | PASS |
| 原持久状态／Web隔离／首次使用／GUI helper 四项自检 | PASS；CHROME_NOT_RUN、PERMISSIONS_NOT_REQUESTED、GUI_NOT_RUN、GATEKEEPER_NOT_RUN 保留 |

冻结 v1→v2→v3 /v2→v3、迁移回滚/未来拒绝、UNKNOWN、第一份 start、补偿/重开、旧profile/跨profile锁均在本次完整执行中。组件测试使用实际 adapter/normalizer/Core/App policy，但桥、权限和字节样本明确注入；不是浏览器或网络验收。详细 AppKit 测试不是物理输入或像素测量。

实际临时 PR checkout 为 `ed5397665b6586729237244211a9fbcc0ef175c5`，父为实际 main `eba1a4fc77648a665e1d5c1f2609df1314c3b079` 与合流源码。root 核对13组输入对象，独立审查者另通过 GitHub 树比较全部构建/回放根对象，均一致；没有合并 main。源码与实际完整日志分别由非作者审查，见 [review.json](review.json)、[verification.json](verification.json) 和 [实际日志摘录](ci-excerpt.txt)。本轮首次完整 CI 即通过，没有以旧源码的运行替代新合流测试。

## 第五轮真实证据保留的范围

[原始27文件](../2026-10-27-real-mac-round5/README.md)全部逐字节保留，树为 `5a22c1bbeffbc0188b5bf4c2da951fce20a85a54`；包括 v9 start失败、v10最终未决及失败CUA实验。原 patch 的上下文空白也保留，不能为了格式检查改写原hash。

| 原真实样本 | 结论 |
| --- | --- |
| v11 start → AppKit close → 独立最终成功 | 有范围PASS：一张生成图、预绑定ACK、editor聚焦、空文本/零旧附件、软件AX单击；input=1 |
| 点击→close | 5.510秒，不能写成点击后253ms消失 |
| 动画调用→close | 252.683ms；原实际配置0.24秒，正式默认0.120秒未由此验收 |
| start→AppKit调用 | 58.8–322.2ms跨时钟区间，close早于页面最终proof约4.893–5.156秒 |
| Core成功首次观察 | 约26.869秒；是观察上界，不是精确COMMIT或页面完成时刻 |
| 日志限制 | pixelPresentationMeasured=false；32次未关联operation的-1728不得归因本图 |

**以上真实 App 基于 e89d49f 加临时 overlay，不包含 e655b1e 的新权限前置。** 因而这些数字不能作为新正式合流二进制的性能或权限验收。新二进制真实 TCC/Chrome 后启动/授权恢复/点击时延均 NOT_RUN。

原私有数据未访问或复制到本环境；审查仅核对脱敏保存 ledger：旧11 assets/17 operations/3 compensations与私有媒体保留，新增5图各一次输入，3成功/2未决，2份start审计保留。没有借此宣称本会话重新核对了真机私有文件，也没有重输旧未决图。

## 可运行版本与下一次真机合流入口

[development App/helper/日志](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40515643640/artifacts/12739217183)：1,650,427 bytes，SHA-256 `98bb5f342e02d4196b6ec8acd8cf56835c6eaf5e1179c7d84761b2d889369d4d`，保存至2026-11-10 **21:52:28北京时间**。ARM64/ad-hoc，未公证/公开发行。普通打开保留首次使用/收录；离线模拟仍单独隔离。

工程真机入口为 `Riftlet.app/Contents/MacOS/Riftlet --web-acceptance --acceptance-trace`，沿用原独立 Web 数据根，不删除数据库/媒体/补偿。只使用新生成图片和原用户点击，或明确记录 software AX 的既有 helper；不得重新点击旧未决图来补成功样本。权限未具备时通过既有原生设置入口恢复，不绕过 OS。

本地 Codex 第六轮继续独立分支；本会话未读取、合并或改写其进行中源码。其正式交接后由唯一负责人统一整合，不要求中断当前小包。保留本轮 App 权限/首用边界，测原事件→权限→预绑定/原ACK→input→start→持久观察→UI→最终事实。冷首击、真实业务ABA/同URL、正文/附件/选区矩阵、MID、物理穿透/全屏/多屏与自包含继续原待验项。真实安全失败和安全重试仍单独未准入。
