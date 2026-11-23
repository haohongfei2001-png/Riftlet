# Riftlet 1.0.8（build 62）发行报告

**RIFTLET 1.0.8 — NOT RELEASED**

正式候选的产品提交为 `871187f2be5eada68fccf2adcc07d120991e1c15`。通用安装包 `Riftlet-1.0.8.dmg` 共 14,225,854 字节，SHA-256 为 `66dedf34e9e224e2ba4ff18823e6b274434c205e3ad5f787990404e3859aec49`。当前公开稳定版为 1.0.5（31）。[独立安装及验签](evidence/build62/signed-package-independent.json)

## 签名候选的实站结果

| 普通浏览器 × ChatGPT Temporary Chat | 冷首图、暖首图 | 三组双图，两次 AppKit mouseDown 间隔 | 非空文字、非折叠选区与旧附件 |
| --- | --- | --- | --- |
| Google Chrome | PASS | PENDING | PASS。64 字符逐字相同，原编辑器的正向选区保持 12→40，旧卡保留。 |
| Microsoft Edge | PASS | PASS。568.318、616.109、650.829 ms。 | PASS。64 字符逐字相同，原编辑器、12→40 正向选区和旧卡均保留。 |

Edge 双图的首张已有附件和六张组内截图分别对应 7 次 input、7 次 change 和 7 条持久化 START。Chrome 选区测试核对了原附件与新附件的像素、文件输入和原草稿。两项的发送点击和表单提交均为零。[冷暖首图](evidence/build62/signed-browsers-cold-warm-independent.json) · [Edge 三组双图](evidence/build62/signed-edge-rapid-independent.json) · [Chrome 选区](evidence/build62/signed-chrome-selection-independent.json)

Edge 先在已有首图的原草稿中录入指定正文并选中 `preserve this original draft`。第二次真实点击只附加一张新截图，产生一次 input、一次 change 和一条新 START。首图的原始 Document、Composer、draftGeneration 已在输入前记录，与新操作一致。后验在同一原标签只读完成，两张图的解码像素各自匹配预览，零发送、零表单提交。[Edge 非空选区独立复核](evidence/build62/signed-edge-selection-independent.json)

## 恢复、兼容性与工程验证

| 项目 | build 62 的证据 |
| --- | --- |
| UNKNOWN 与明确失败后的恢复 | A–H 全部通过。通过实际产品 UI、AppKit 点击和 SQLite 核对原图、原始操作、显式重新选择、取消、迟到回执及重启。一次额外的测试在第二次点击前安全停止。 [受控恢复与历史说明](G4_FINAL_ACCEPTANCE.md) |
| 历史数据库 | 使用最终源码在三份封存的 build 59 故障数据库副本上验证迁移与恢复。原件摘要、原 PNG、原操作与收据均经独立复核。 [历史数据审计](evidence/build62/frozen-history-independent.json) |
| ARM64、Intel 和网页 | PR #125 的两个源码准入、两项原生架构及 Feedback 原生与服务检查共五项通过。ARM64 与 Intel 各通过 1,436 个不同 Swift 用例（各 1,414 项并行、22 项串行）。最终受控网页回归 408/408。 [Native CI](https://github.com/haohongfei2001-png/Riftlet/actions/runs/45155234835) · [Feedback CI](https://github.com/haohongfei2001-png/Riftlet/actions/runs/45155234922) · [非作者 CI 复算](evidence/build62/dual-architecture-ci.json) · [网页回归](evidence/build62/controlled-web-final.json) |
| 安装与更新签名 | Developer ID、App 与 DMG 两份 Apple 公证、两份 staple、Gatekeeper 和独立安装均通过。安装目录的 193 个项目与签名清单一致。1.0.5 与 1.0.8 的内置公钥均验证了下载归档的 EdDSA 签名。 [安装](evidence/build62/signed-package-independent.json) · [更新签名](evidence/build62/signed-update-archive.json) |

真实 ChatGPT 上游具名失败卡和 HTTP 4xx 缺少实站证据。发行判断采用已批准的产品恢复契约。START 表示草稿已开始接收对应图片，后续上传进度由 ChatGPT 显示，发送由用户决定。

## 1.0.5（31）升级至 1.0.8（62）

| 通道 | 结果 |
| --- | --- |
| 发布前，隔离测试 appcast | 已用 31 和 62 的正式公钥验证隔离 feed 和 DMG，应用内更新待执行。起点为正式签名 31，保留 51 个资产、2 个操作（含 1 条 UNKNOWN）、1 条 START、3 项设置及 86 个文件摘要。 [起始快照](evidence/build62/upgrade-31-baseline.json) · [隔离更新源](evidence/build62/staging-update-feed.json) |
| 发布后，从官网下载、GitHub 下载及公开 stable 应用内更新 | NOT_RUN。须从新的隔离 31 副本验证，并独立核对安装后身份、数据和设置。 |

[产品收口记录](FINAL_PRODUCT_CLOSURE.md) · [发行说明](RELEASE_NOTES_DRAFT.md) · [build 59–61 完整历史报告](https://github.com/haohongfei2001-png/Riftlet/blob/ff380f90ccc586c90f561125d088428f7b0fd18e/docs/releases/1.0.8/RIFTLET_1.0.8_FINAL_RELEASE_REPORT.md) · [历史 build 60 报告](https://github.com/haohongfei2001-png/Riftlet/blob/2babf8cafcfd924abdddaa0ba43a1d099af1acb7/docs/releases/1.0.8/RIFTLET_1.0.8_FINAL_RELEASE_REPORT.md)
