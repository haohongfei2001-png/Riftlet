# 修复版真实系统截图：SC-COMPLETE 限定通过

**SC-INPUT / SC-START / SC-COMPLETE：PASS。** 一张全新的真实系统 PNG 经实际 Riftlet 微图输入一次，原附件取得正向开始和严格 sRGB 完成 proof；候选 journal 持久记录 attached。非空正文、编辑器内非折叠选区及一张稳定旧附件完整保留。到此结束本轮，没有继续上传样本、MID或新功能研究。

本轮分支：`codex/riftlet-real-mac-acceptance-sc-complete-20261028`。从 `f2ae645451044649fbe73326952efbe084353869` 继续，运行的修复源码为 **`48574df19f34e5681ee98815750e279540e9eb9b`**。没有新增生产代码修改，没有写正式分支、PR #1 或 main。

## 唯一正式输入与目标

新图 F 为用户通过 macOS 原系统截屏流程取得的 selection PNG，metadata `kMDItemIsScreenCapture=1`。1746×1164、8-bit RGBA、6,796,322 字节，未转换或压缩；系统原件与私有副本 SHA-256 均为 `0c19cb16f5c6dfdcaf0958284d6f40450912ea03babe5a79e1d268c2f06ff596`。内容只有本地显示的彩色测试图；不是给生成文件添加 metadata。

原目标为独立的已有普通 ChatGPT 业务草稿，完整 logicalDraftIdentity 与 A、D 的 UNKNOWN 草稿不同。Chrome PID/session/window/tab/document/composer/draft、asset/op/attempt/hash 在点击前目标、页面、持久 journal 和数据库中逐字段一致。原 ACK 提前 **1208.909 ms**，不是无 ACK 冷首击或晚到 ACK 回填。

输入来源为 **CGEvent 软件 down/up**，实际经过原生微图输入窗口；不是 AXPress、文件选择器或人工物理鼠标。1 begin / 26 chunk / 1 commit 全部成功；256 KiB 分块不等于多次输入。原页面 inputCount=1，独立 change 计数=1，最终附件总数从 1 变为 2。没有发送消息。

## 开始、完成与保留

| 检查 | 实际证据 |
|---|---|
| SC-START | 原节点进度 2.4538636→3.6807954，hash 已验证；input→start **2151.4 ms**；原操作候选 start journal 已持久化 |
| SC-COMPLETE | 100%→原进度移除→原 image data-PNG load→严格 proof；input→proof **8784.0 ms**；proof identity/nodes/source 均为原对象，invalid/error=false |
| 独立内容核对 | 原文件先校验 SHA，再独立显式 sRGB OffscreenCanvas 解码；原件和原预览的 RGBA SHA 都为 `6f20aa4069b1d28a3693527e3b7d1402e424a393271a3d38ec081c98b0f5d129`；**8,129,376 通道零差异**，没有容差 |
| 非空正文 | 48 字符，前后内容相同 |
| 编辑器选区 | 8..11，非折叠，两端均在原 editor，选中文字保持 |
| 焦点 | 输入时与后续采样中 pageFocused=true，editorFocused=false；无需将编辑器聚焦作为附加前提 |
| 旧附件 | 一张已稳定完成的 48×32 PNG；原 card/image 节点、source、尺寸和完成状态保持，最终预览与准备文件逐字节相同 |
| 防重复/发送 | 只有一个正式新操作和一次输入；两张卡片而非重复截图；消息节点保持，无发送动作 |

上述保留性在 24 次输入后快照及最终快照中均成立；这不宣称覆盖每个未采样瞬间。页面事件顺序与原生 uptime 分开记录，不合成未经校准的跨时钟精确耗时。最终 startDisqualified=true 是进度节点正常移除后不再输出“当前上传中”开始证据，不抹除已保存的历史正向 start 或完成 proof。

原 PNG 与网页预览 PNG **不是字节完全相同**：预览重编码为 6,673,150 字节，SHA-256 `3eaa650ed13568739c4835244275a939b44d19e0cbe7e3ab538e0c198f20bcff`。本轮证明严格 sRGB 像素内容一致，不宣称服务端原文件字节保真。

## 三层状态分别记录

| 层 | 结束时事实 |
|---|---|
| 实际网页 | 原附件 complete；无进度、无错误；原节点/source 严格 proof 有效，原草稿保留 |
| 候选 journal | 同一 operation/attempt 的 unknown、input、start、attached 四个首次槽；input/start/attached 的 attachmentID 相同；provenance 保留 integratedDevelopment |
| SQLite v3 | F **unknown/visible**，reason=`observer-v2:attached:integratedDevelopment`；upload_starts=0。候选开始、完成、安全失败准入仍全部关闭 |

因此本轮 PASS 是真实候选观察和数据关联通过，**不是生产能力已开启、数据库 succeeded、自动吞噬或安全重试通过**。没有为演示填写准入表。

## 基线准备、旧状态与边界

- 为满足至少一张旧附件，先用独立 MAIN 准备脚本执行一次 3,045 字节生成小图的 file input/change；这仅是基线准备，不计作系统截图输入，也不是新的生产适配器。它已完成并稳定，正式 F 的观察器在此之后才安装，旧进度不混入新图证据。
- 初始准备页保留 v7/v8 root monitor，当前程序不能安全借用；未改写或删除这些旧监视器。正常打开同一独立业务线程的新文档后，稳定基线附件自动恢复，当前 v13 正常绑定。该老页面冲突仍未解决，不在本轮 PASS 范围。
- 准备期间日志记录过一次旧 A 的 mouse 选择；没有重输或新 attempt。准备日志触及数量上限，因此不单凭“没看到命令”证明全程无输入；开始/输入前/结束的一致性数据库备份及原操作身份、attempt和既有UNKNOWN保护共同复核。正式 F 日志只有一个选择和完整的输入链。
- 结束时旧 A 原页面 lookup 没找到原 operation，旧 D 原标签不可访问；没有刷新、迁移或重放它们来恢复页面证明。旧 A/D 的 SQLite 身份、attempt、UNKNOWN、原图和历史 journal 均保留。
- 候选数据根沿用，5→6 assets、3→4 operations，只有 F 新增 operation。旧 asset 行和全部10条旧 checkpoint 未变。A/D 只读恢复更新了观察时间/receipt，D也更新了reason；不宣称旧operation整行不变。B不变。补偿0→0，schema=3，quick_check=ok。
- 已保留系统原件、私有媒体、数据库/WAL、备份、原日志和历史工作树；未清库、删除或换数据根。仅移除本轮自己的诊断监听，退出候选 App；页面附件/正文和原监视器保留。

**人工物理鼠标 NOT_RUN。** 软件命中与焦点证据不冒充硬件来源。无 ACK 冷首击、多屏、MID、安全失败重生、生产准入不因本例而变为 PASS。

## 构建、CI、审查与交接

运行环境沿用本机 macOS 27.0 (26A428)、arm64、Chrome 156.0.8078.73。实际 App 可执行文件 SHA 与上一轮最终构建相同；bundled page source SHA-256 `c0afbd8a652c7a0e8fe6875ddbbd54f075e9c60bcda512eeb4df610e72f8948b` 与48574df精确一致，明确包含显式sRGB且无willReadFrequently的修复。

- 本轮未改生产 Sources、Tests、构建或CI输入。完整构建及 [macOS CI40656871851](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40656871851) 是**同一48574df源码已通过的运行**，本轮再次核实completed/success；不是新跑，也未重复触发限额资源。
- 非作者 reviewer 只读复核完整身份/因果、旧附件与选区保留、独立像素结果、数据保留和公开脱敏，无GUI输入、无源码写入。结果 PASS，物理和生产范围限制保留。
- [结果](result.json)、[分离时钟时间线](timeline.json)、[验证范围](verification.json)、[非作者审查](review.json)、[私有证据SHA索引](private-evidence-sha256.json)。公开文件不含系统截图字节、聊天正文、完整target、私有路径、数据库或原始日志。

**交给正式集成 Pro：** 本例已经具备对系统截图候选开始/完成分别进行受限准入审查的真实证据。保留来源和支持范围，不能由本次成功自动开启普通生产或安全重试；无需再重复上传 F、D 或其他旧样本。后续是否开启及Beta组合由正式负责人决定，本轮在此结束。
