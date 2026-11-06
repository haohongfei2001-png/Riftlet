# Beta 2 原生产品交接 — 2026-11-06

本轮已把 V2 的六页设置、菜单栏控制中心和三步引导接入同一 Riftlet App。当前是**候选审核进行中**：已有同包完整 scoped 原生运行与自动重启通过，独立视觉和精确候选 CUA 键盘已有 scoped PASS，正式 CI 与最终工件仍未完成。已安装个人 Beta 1 保持不变；重大 UI PR 合并与普通数据根升级仍等待本轮最终外观决定。

用户交付入口是 [Beta 2 候选说明](../../docs/BETA2_CANDIDATE.md)。逐次结果见 [状态与证据索引](STATUS.md)，场景范围见 [原生验收矩阵](NATIVE-ACCEPTANCE-MATRIX.md)。当前不声明 `BETA2_REVIEW_READY` 或 `PRODUCT_READY`。

## 已交付的工程内容

| 内容 | 已完成的部分 | 仍需完成的部分 |
| --- | --- | --- |
| 原生产品 | 六页 AppKit 设置、三级参数、NSPopover/NSMenu、三步引导、既有 owners 与 Main 接线 | 正式 CI、最终工件与用户外观决定 |
| 保存与编辑 | 按域保存/重试、原始文本草稿、后台更新保留编辑控件、关闭/退出草稿确认 | 精确候选 CUA 的 Escape/Return 已通过；修正后的正式 XCTest 待完成 |
| 实际原生运行 | run11 为 13 PASS / 0 FAIL，33 张原始窗口图，正常 exit 0；实际暂停/恢复 collector 与四种状态通过 | 33 原图非作者目视与精确候选 CUA 键盘已通过；不覆盖物理状态栏或 OS IME |
| 重启持久化 | run11 同包同根自动 fresh-process 重启 6/6 PASS，正常退出；五 JSON、3 资产/媒体映射及摘要、operations/START 0 前后相等 | 这是隔离审核根；最终工件身份和生产升级另行核对 |
| 正式工程交付 | Draft PR #43、原始 CI 日志、多个精确 ARM64 中间包、原失败记录 | 最终非作者源码审查、G / 直接 H、五项 CI、最终 App/ZIP 与身份清单 |

run09 的单行产品修正移除了 popover 展示后主动指定首个 responder 的调用；在 driver 不变的一次对照中，四个到达的 popover 均保持 non-key、达到完整稳定尺寸，只由 driver 明确关闭。它关闭了这次程序化展示的已观察缺陷，**没有证明物理状态栏点击、第二次点击、外部点击或完整暂停/隐藏序列**。原 run01–08 结果不改写。[run09 绑定](evidence/native-run-09-native-responder.json)

[run10](evidence/native-run-10-pause-trace.json) 已观察暂停/隐藏与 collector 停止/恢复通过，但六页在深色 display 之后 `pageNotPresented`，仍为 12/13；记录到的 own-window 鼠标事件来源与因果均未确定。[run11](evidence/native-run-11-owned-page-trace.json) 仅增加 driver 页状态/hit trace，产品实现与 run10 相同，随后 13/13 与自动重启 6/6 通过。它给出了当前一次完整 scoped PASS，没有倒推 run09 超时或 run10 失败的原因。

Escape/Return 的真实对象代码探针使用实际 UI/model 编译对象和合成 owner：原生 attached/key sheet 收到事件后，草稿与选区保持、无 owner 写入或 host 命令。这个 PASS 绑定旧严格 modifier mask；最新允许 CapsLock/Function 状态的窄增量只有 target build/parser PASS，该对象探针不证明后继包、XCTest 或物理键盘；后继 f0e5b99 已另取得实际 CUA 键盘 scoped 结果。[修复与范围](evidence/ci-settings-repair.json)

run11 的非作者审查已逐张查看全部 33 原 PNG，无阻断视觉发现；原报告 SHA-256 `c574b00e0bed241d4ab7fa138c232e587443571ef6b00220eacd435d1999341f` 已绑定到 [run11 摘要](evidence/native-run-11-owned-page-trace.json)。[精确候选 CUA 键盘](evidence/cua-final-keyboard-f0e5b99.json)另外记录：⌘W 后 Escape/Return 保留 2.25 草稿、焦点与 dirty；⌘Q→Escape 取消退出；最后应用后目标进程不存在，JSON 为 8100 秒。最后 AX read 是 timeout，退出码未捕获，不补成成功 AX 读取或正常 exit code。CUA 未测 selection 范围、CapsLock/Function、物理键盘；相应边界保持。

## 来源与身份

- 正式基线：`c72fca78245a15a66ea6beaa980ec141f146bc1b`，PR #42 标准合并，父提交 `b61fc46` / `fdbf4c3`；tree `1816948` 与其已测试来源相符。
- 工作分支：`codex/beta2-native-product-20261106`；[Draft PR #43](https://github.com/haohongfei2001-png/Riftlet/pull/43) 初始 head `974e0bcde40f3f4d25ef1f1bbe0acc7d74575dc0`。这不是最终 G。
- 设计来源：已有 `design/settings-control-center-20261106` 的 `83b8ee478f13d3714697eda4cb3a7785576cb6e0`；revision-2 HTML SHA-256 `c58e4c7a3fa717a2fc5f68e8aaaf90e7950363a52c4047be182f9cb81fd67b58`。没有新增浏览器原型或信息架构。
- Beta 2 版本分配：`0.2.0 (2)`。最终 G/tree、直接 admission-only H、App/ZIP/hash 由最终独立清单绑定，当前均未借用中间包填充。

首次正式 CI 已结束：[Native 42205691399](https://github.com/haohongfei2001-png/Riftlet/actions/runs/42205691399) 的 ARM64 与 Intel 均失败，**两架构是相同 12 个独立 case**；[Feedback 42205691613](https://github.com/haohongfei2001-png/Riftlet/actions/runs/42205691613) 的 native/service 成功，历史 composition 条件步骤 skipped。两个 source gate 仍因继承 PR #42 admission 而 FAIL。修复与局部验证已经记录，完整批次重跑尚无结果；既有失败不称绿。[首 CI 失败绑定](evidence/ci-974e0bc-first-failures.json)

## 安装、数据与恢复包

本轮未安装 Beta 2。已安装 Beta 1 的可执行文件 SHA-256 仍为 `c0ca439023a2fa92fd1cc08d4acff79dd780dc559d8a4c579af76d6fd5a76ea4`。推荐保留的稳定恢复 ZIP 是 `Riftlet-personal-beta.1-arm64-004741f.zip`，SHA-256 `c474a72157a3a1e513fa48f0bed1f696bdf38b5c6af669d434749a63cecef2cd`，绑定 `personal-beta.1+004741f`；完整路径在私有升级清单中。旧 `2a1622d` 候选只是历史备份，不是推荐恢复版本。核验旧 ZIP 可用不表示已执行回退或已证明未来新数据能由旧版读取。

[既有只读数据记录](evidence/production-readonly-current.json)显示两次已记录计数均为 94 assets / 44 operations / 18 START，当前 94 份媒体的实际长度与摘要都符合库存记录，安装 binary 相同。初始记录没有逐行/逐媒体摘要，因此**不能声称观察期间所有历史行、媒体字节或配置逐字不变**。这份公开摘要不包含用户图片、资产身份、原始数据库行或私有路径；文档收口没有再次访问生产根。

## 下一步与责任

1. 已完成 run11 全部 33 原图的非作者审查和精确候选 CUA Escape/Return/退出取消分支；保留 run09/run10 未归因记录，不因后续通过改写历史。
2. 完成修正后的正式 CI 批次与最终源审查，形成 G / 直接 H、实际 PR checkout 与五项检查；把 run11 的来源与最终候选差异明确绑定。
3. 收口最终 App/ZIP/报告清单及已知平台限制。最终外观决定、重大 UI 合并和普通根升级分别记录真实结果，不由 scoped 原生 PASS 自动批准。

Root 负责共享契约、Main/Package/CI、集成 refs 和打包；各实现 lane 只写分配文件，非作者审查独立进行。此文档更新不修改产品或测试。平台项如 OS IME、VoiceOver、真实登录项、TCC、多屏热拔和 Beta 2 真实附件仍按矩阵单独标记；它们限制对应结论，不阻塞无依赖的工程工作。
