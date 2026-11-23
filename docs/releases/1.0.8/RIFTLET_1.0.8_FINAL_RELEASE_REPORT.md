# Riftlet 1.0.8（build 62）发行报告

**RIFTLET 1.0.8 — RELEASED**

正式版 1.0.8（62）的标签指向产品提交 `871187f2be5eada68fccf2adcc07d120991e1c15`。通用安装包 `Riftlet-1.0.8.dmg` 共 14,225,854 字节，SHA-256 为 `66dedf34e9e224e2ba4ff18823e6b274434c205e3ad5f787990404e3859aec49`。[GitHub Release](https://github.com/haohongfei2001-png/Riftlet/releases/tag/v1.0.8) · [下载 DMG](https://github.com/haohongfei2001-png/Riftlet/releases/download/v1.0.8/Riftlet-1.0.8.dmg) · [SHA256SUMS.txt](https://github.com/haohongfei2001-png/Riftlet/releases/download/v1.0.8/SHA256SUMS.txt) · [官网下载](https://riftlet.com/#release) · [Sparkle stable](https://riftlet.com/updates/stable.xml)

GitHub 于 2026 年 11 月 23 日 21:18:30（北京时间）发布 v1.0.8。PR #125 的合并提交为 `bbcbac2455697b874a2aca79be92b113630a93f0`，PR 与 main 各五项正式检查通过。官网两个下载按钮和公开更新源均指向同一签名 DMG。[公开下载与来源核对](evidence/build62/public-distribution.json) · [发布后非作者裁决](evidence/build62/public-independent-verdict.json)

官网 PR #127 的首次 ARM64 作业在隔离 Chrome 初始化时超时，受控用例通过 47/48。同一云端工作流的 ARM64 第 2 次作业通过。Intel、Native 源码准入、Feedback 源码准入及 Feedback 测试均在首次执行时通过。[首次失败的云端日志](https://github.com/haohongfei2001-png/Riftlet/actions/runs/45186045048/job/137731799406) · [ARM64 最终作业](https://github.com/haohongfei2001-png/Riftlet/actions/runs/45186045048/job/137744706398) · [公开下载与来源核对](evidence/build62/public-distribution.json)

## 正式签名包的实站结果

| 普通浏览器 × ChatGPT Temporary Chat | 冷首图、暖首图 | 三组双图，两次 AppKit mouseDown 间隔 | 非空文字、非折叠选区与旧附件 |
| --- | --- | --- | --- |
| Google Chrome | PASS | PASS。586.197、602.573、599.560 ms。 | PASS。64 字符逐字相同，原编辑器的正向选区保持 12→40，旧卡保留。 |
| Microsoft Edge | PASS | PASS。568.318、616.109、650.829 ms。 | PASS。64 字符逐字相同，原编辑器、12→40 正向选区和旧卡均保留。 |

Edge 双图的首张已有附件和六张组内截图分别对应 7 次 input、7 次 change 和 7 条持久化 START。Chrome 选区测试核对了原附件与新附件的像素、文件输入和原草稿。两项的发送点击和表单提交均为零。[冷暖首图](evidence/build62/signed-browsers-cold-warm-independent.json) · [Edge 三组双图](evidence/build62/signed-edge-rapid-independent.json) · [Edge 逐图核对](evidence/build62/signed-edge-rapid-per-image.json) · [Chrome 选区](evidence/build62/signed-chrome-selection-per-image.json)

Edge 先在已有首图的原草稿中录入指定正文并选中 `preserve this original draft`。第二次真实点击只附加一张新截图，产生一次 input、一次 change 和一条新 START。首图的原始 Document、Composer、draftGeneration 已在输入前记录，与新操作一致。后验在同一原标签只读完成，两张图的解码像素各自匹配预览，零发送、零表单提交。[Edge 非空选区独立复核](evidence/build62/signed-edge-selection-independent.json)

## Chrome 逐图时间线

每组第一张收到的 AppKit mouseDown 为 0 ms。宿主时间以毫秒计；表中网页 input / change 取自原 Document 的独立时钟，只在该时钟内比较。两张截图的原图、凭据及托盘可点区域均在首次点击前核实。setter 只能定位到原生调用区间。

| 组 / 图 | mouseDown | 凭据消费 | 原生 commit / setter 区间 | 网页 input / change | 原卡 accepted | 托盘动画开始 / 结束 |
| --- | ---: | ---: | --- | --- | ---: | --- |
| 1 / 1 | 0.000 | 138.047 | 267.505–403.081 | 120397 / 120399 | 2049.421 | 2052.324 / 2174.829 |
| 1 / 2 | 586.197 | 856.921 | 1006.668–1123.646 | 121130 / 121133 | 2616.138 | 2617.569 / 2752.255 |
| 2 / 1 | 0.000 | 192.547 | 323.896–453.309 | 128850 / 128852 | 2037.819 | 2039.738 / 2170.290 |
| 2 / 2 | 602.573 | 871.781 | 1036.831–1160.387 | 129564 / 129567 | 2600.112 | 2601.556 / 2723.247 |
| 3 / 1 | 0.000 | 137.021 | 267.705–414.289 | 137463 / 137465 | 2017.165 | 2036.267 / 2158.183 |
| 3 / 2 | 599.560 | 883.916 | 1052.356–1177.914 | 138248 / 138251 | 2631.472 | 2632.650 / 2757.229 |

六张组内截图和一张基准截图各有一次 input、一次 change 和一条持久化 START。三组分别保留原有 1、3、5 个附件节点，发送点击和表单提交均为零。七个预览的编码字节与各自原 PNG 完全一致，Chrome 对网页 File 和对应预览的解码像素也全部一致。第 4 张在本机 CoreGraphics 与 Chromium 两种解码器下的 RGBA 摘要有差异。[逐图完整机器回执](evidence/build62/signed-chrome-rapid-timeline.json) · [非作者逐图复算](evidence/build62/signed-chrome-rapid-independent.json) · [两款浏览器同包总表](evidence/build62/signed-browsers-complete.json)

已按原窗口、标签和草稿身份关闭完成验收的专窗。九个临时监听均已退出，测试版应用进程为零。早先有一个未点击的 Chrome 标签发生页面重载，原 Document 身份已失效，保留了该窗口。1,387 个原件保存在本机私有验收存档。[清理与私有归档摘要](evidence/build62/signed-browsers-archive-and-cleanup.json)

## 恢复、兼容性与工程验证

| 项目 | build 62 的证据 |
| --- | --- |
| UNKNOWN 与明确失败后的恢复 | A–H 全部通过。通过实际产品 UI、AppKit 点击和 SQLite 核对原图、原始操作、显式重新选择、取消、迟到回执及重启。一次额外的测试在第二次点击前安全停止。 [受控恢复与历史说明](G4_FINAL_ACCEPTANCE.md) |
| 历史数据库 | 使用最终源码在三份封存的 build 59 故障数据库副本上验证迁移与恢复。原件摘要、原 PNG、原操作与收据均经独立复核。 [历史数据审计](evidence/build62/frozen-history-independent.json) |
| ARM64、Intel 和网页 | PR #125 的两个源码准入、两项原生架构及 Feedback 原生与服务检查共五项通过。ARM64 与 Intel 各通过 1,436 个不同 Swift 用例（各 1,414 项并行、22 项串行）。最终受控网页回归 408/408。 [Native CI](https://github.com/haohongfei2001-png/Riftlet/actions/runs/45155234835) · [Feedback CI](https://github.com/haohongfei2001-png/Riftlet/actions/runs/45155234922) · [非作者 CI 复算](evidence/build62/dual-architecture-ci.json) · [网页回归](evidence/build62/controlled-web-final.json) · [文档提交的五项正式检查](evidence/build62/reviewed-documentation-ci.json) |
| 安装与更新签名 | Developer ID、App 与 DMG 两份 Apple 公证、两份 staple、Gatekeeper 和独立安装均通过。安装目录的 193 个项目与签名清单一致。1.0.5 与 1.0.8 的内置公钥均验证了下载归档的 EdDSA 签名。 [安装](evidence/build62/signed-package-independent.json) · [更新签名](evidence/build62/signed-update-archive.json) |

真实 ChatGPT 上游具名失败卡和 HTTP 4xx 缺少实站证据。发行判断采用已批准的产品恢复契约。START 表示草稿已开始接收对应图片，后续上传进度由 ChatGPT 显示，发送由用户决定。

## 1.0.5（31）升级至 1.0.8（62）

| 通道 | 结果 |
| --- | --- |
| 发布前，隔离测试 appcast | **十三项全部 PASS。** [逐项独立裁决](evidence/build62/staging-thirteen-requirements-independent.json)  活动的正式 31 通过 Sparkle 发现、下载、安装并重启为 62。应用菜单的三次原始记录、签名 feed、14,225,854 字节下载及安装后 193 项全部核验。51 个资产、2 条操作（含 1 条 UNKNOWN）、1 条 START、6 条检查点及全部旧列逐值相等，原 86 个文件与 3 项设置完整。 [实际升级和两份 SQLite 摘要](evidence/build62/staging-31-to-62-migration.json) · [逐行独立审计](evidence/build62/staging-active-sqlite-independent.json) · [更新和签名安装独立复核](evidence/build62/staging-51-to-51-independent.json) · [旧版基线](evidence/build62/upgrade-31-baseline.json) · [签名测试源](evidence/build62/staging-update-feed.json) |
| 发布后，GitHub 匿名下载和经官网按钮下载 | 两次分别取得 14,225,854 字节的完整 DMG，SHA-256 均为 `66dedf34e9e224e2ba4ff18823e6b274434c205e3ad5f787990404e3859aec49`。公开校验和文件相符。[公开下载与来源核对](evidence/build62/public-distribution.json) |
| 发布后，公开下载件的独立安装与普通启动 | App 和 DMG 的 Developer ID、staple 和 Gatekeeper 核对通过。另在隔离环境普通启动该公开副本，版本 1.0.8、build 62。两种架构的代码签名和全部 193 项文件、目录与符号链接都与签名清单匹配。[公开下载件独立安装与普通启动](evidence/build62/public-installation.json) |
| 发布后，另一份活动 31 副本经正式 stable 应用内更新 | 使用普通「检查更新」、安装和重新启动，版本从 1.0.5（31）升到 1.0.8（62）。51 个资产、2 条操作、1 条 UNKNOWN、1 条 START 和 6 条检查点保留，86 个文件、51 个 PNG 与 3 项设置核对相符。另外实测更新器缓存包含同 SHA 的完整 DMG。 [公开 stable 升级及前后 SQLite](evidence/build62/public-stable-upgrade.json) |

本次公开 stable 验证在点击「检查更新」前，对同一运行中的 31 先后备份两次。其间 32 个已有资产从可见转为自动归档。51 个资产的身份保持一致，2 条操作、1 条 UNKNOWN 和 1 条 START 均原样保留。下文首轮 staging 的 32 次导入来自复制文件后产生的新 inode，发生在另一份试验副本。 [公开 stable 升级及前后 SQLite](evidence/build62/public-stable-upgrade.json)

首份试验副本从冷态 51 行变为 83 行。准备时复制回桌面的 32 个文件有新的 macOS 文件身份，31 在下载更新前就完成了全部 32 次导入。最后一条早于下载 110.684 秒。后续副本按原 inode、出生时刻和 SHA 恢复这 32 个文件，数据库未经修改，在运行中的 31 和 62 均测得 51 行。[首轮原始审计](evidence/build62/staging-first-update-independent.json) · [逐行归因](evidence/build62/staging-first-update-attribution.json)

升级后的 62 从正常菜单打开截图仓库，显示 51 项、已归档缩略图和搜索入口。隔离 Mac 随后实际拍摄一张系统截图，仓库变为 52 项。该 PNG 为 177,315 字节，与 Riftlet 存档逐字节相同，旧操作与 START 数量均未变化。[历史界面、原媒体与设置](evidence/build62/staging-history-settings-independent.json) · [新系统截图与增量入库](evidence/build62/staging-new-screenshot-independent.json)

从升级后的仓库恢复这张新图到托盘，随后在同一进程的原缩略图上实际点击一次。前台没有可核实的 ChatGPT 草稿，普通应用提示 “Bring your intended ChatGPT draft to the front”。拒绝时新图仍在队列中。稍后的第四份快照显示它按日常闲置规则归档，状态仍为 pending，原 PNG、两条操作和一条 START 均保留。[普通队列点击与历史记录](evidence/build62/staging-queue-and-history.json) · [普通队列独立复核](evidence/build62/staging-queue-independent.json) · [非作者独立 OCR](evidence/build62/staging-queue-ocr-independent.json)

同一张 768×576 的新系统截图还经过升级包内的实际网页资源。在隔离的本地 Chromium 受控页中，该资源向原输入写入一次并产生一次 input、一次 change 和一次 attachmentAccepted。文件原始字节和预览的全幅 RGBA 均匹配，64 字符原文、12→40 选区及旧卡保留。发送、表单提交、外部网络请求均为零。普通 Chrome 与 Edge 的同包实站证据见上方双浏览器总表。[升级资源与新图的离线附加](evidence/build62/staging-local-attachment.json) · [原生 setter 与零网络独立复核](evidence/build62/staging-local-input-independent.json) · [全幅像素复核](evidence/build62/staging-local-input-pixels.json)

首次升级后，独立提取的 App 与签名清单的 193 个成员完全匹配。隔离机的 Edge 专窗 Apple Events 查询返回 `-1712`。宿主备用单图实测因自动审批限制，在创建进程和窗口前停止，实测输入为零。[升级后单图的实际执行范围](evidence/build62/upgrade-attachment-scope-first-run.json)

**发布前的隔离升级档案**

两轮原始升级记录、四份运行中 SQLite 快照、私有媒体与菜单回执共封存 168 件。私有 ZIP 的 SHA-256 为 `5bfea6a8ee0a2cd413e6ee9267e17e07486713d6b04387a5e762b03cfe95ed4c`，文件清单摘要为 `6247d67be91be717f11a654250e2b13fcac4f0c7638718098af787f2c889a0b9`。

发布后封存了两个公开下载入口取得的完整 DMG，以及 31 初始、31 归档后和 62 更新后的三份 SQLite 快照。私有归档 SHA-256 为 `e36c6038b9cb5ceaaaa941285487b1705992b97e56850c9b3c147428f7456fb6`。[公开安装与升级原件封存摘要](evidence/build62/public-install-upgrade-custody.json)

[产品收口记录](FINAL_PRODUCT_CLOSURE.md) · [发行说明](RELEASE_NOTES.md) · [build 59–61 完整历史报告](https://github.com/haohongfei2001-png/Riftlet/blob/ff380f90ccc586c90f561125d088428f7b0fd18e/docs/releases/1.0.8/RIFTLET_1.0.8_FINAL_RELEASE_REPORT.md) · [历史 build 60 报告](https://github.com/haohongfei2001-png/Riftlet/blob/2babf8cafcfd924abdddaa0ba43a1d099af1acb7/docs/releases/1.0.8/RIFTLET_1.0.8_FINAL_RELEASE_REPORT.md)
