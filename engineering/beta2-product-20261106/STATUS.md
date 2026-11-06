# Beta 2 状态与证据索引

当前是候选审核进行中。**run11 为 13/13 scoped 原生组通过，33 张原始窗口图，正常退出；同包同隔离根自动新进程重启 6/6 通过。** run09 暂停超时与 run10 页面切换失败的原因仍未确定，原 FAIL 保留。 首次正式 ARM64/Intel CI 都已失败，修正后的批次仍待执行/收口。独立目视和精确候选 CUA 键盘已有 scoped PASS；最终 G/H、正式 CI 与工件尚未完成；已安装 Beta 1 未替换，不声明 `BETA2_REVIEW_READY` 或 `PRODUCT_READY`。

用户交付范围与操作说明见 [候选说明](../../docs/BETA2_CANDIDATE.md)，工程后续见 [交接](HANDOFF.md)，逐场景结论见 [验收矩阵](NATIVE-ACCEPTANCE-MATRIX.md)。下表只描述各自精确来源；后来的修改不继承早期整包通过。

## 当前可确认结果

| 范围 | 已观察事实 | 未完成 / 限制 |
| --- | --- | --- |
| 六页与三步引导 | 真实 owners 接线；run11 六页浅深、三步浅深、编辑/默认/关闭/重试/预览/历史/resize 对应 case 通过；引导外框 652×608 pt、设置初始内容 960×684 pt | 33 原图已非作者目视，无阻断发现；最终用户外观决定独立 |
| 控制中心 | run09 单行 responder 修正有局部对照；run11 七次展示/14 次 open-capture 稳定检查通过，包含四种暂停/隐藏状态，只有明确关闭 | 物理状态栏输入、外部点击仍 NOT_RUN；原图已获非作者 scoped 目视通过 |
| 暂停/隐藏 | run10/run11 真实 SQLite/owner 与四组合通过；run11 暂停 2.044s 的 40 次采样无新增，恢复后新 fixture 0.298s 收录 | 不推断暂停期间图片的恢复策略；run09 timeout 仍 UNATTRIBUTED |
| Escape/Return | 实际编译 UI/model 对象 + 合成 owner 的 attached/key sheet 探针通过；草稿/选区保持、0 写入/命令 | PASS 绑定旧严格 mask；f0e5b99 普通 Escape/Return 已另获 CUA PASS；CapsLock/Function 实际输入与正式 CI 待验证 |
| 进程与重启 | run11 原生 run 正常 exit 0 / 24.162s，自动同包同根新进程 6 项检查 PASS / exit 0 / 0.460s；跨进程快照相等 | scoped 隔离根验证，不是 Beta 2 生产升级；旧 d72 独立重启证据保留 |
| 正式 CI | 原 Native 两架构相同 12 case 失败；Feedback native/service 成功；两个 source gate 失败 | 修正后的批次与最终 G/H 五项结果 PENDING |
| 生产与恢复 | 已安装 Beta 1 binary 未变；稳定 G004741f ZIP 已核验；现有只读记录 94 媒体完整 | 没有 Beta 2 生产升级或回退；初始无逐行摘要，不能证明全时段逐字不变 |

## 原始运行记录

这些是独立的真实运行，原 report、原图、日志和失败均保留。`PNG` 列是已产生文件数，不表示每张都经过视觉批准；`NOT_RUN` 仍为缺失证据。

| 运行 / 源码 | 功能与图片 | 进程结果 | 当次边界 |
| --- | --- | --- | --- |
| [run01](evidence/native-run-01.json) / `45418bba` | 13 PASS，30 PNG / 3 NOT_RUN；整体 PARTIAL | runner 180s timeout | 缺图与退出挂起；另发现说明列过窄、caption 重叠、位置标记不足、引导宽 562 pt |
| [run02](evidence/native-run-02.json) / `bc903f7` | 12 PASS / 1 FAIL，27 PNG；其中 7 张 control 图被独立审查否决为裁切/黑色空区 | 正常 exit 0，20.16s | 引导尺寸失败；caption 与选中勾选在该版目视闭环；文件存在不等于有效图 |
| [run03](evidence/native-run-03.json) / `ea312a6` | 12 PASS / 1 FAIL，29 PNG | 正常 exit 0，14.99s | 引导六帧 652×608 pt；driver 提前点击禁用开关；部分 popover 帧仍处缩放阶段 |
| [run04](evidence/native-run-04.json) / `4174a04` | 11 PASS / 2 FAIL，23 PNG / 2 NOT_RUN | 正常 exit 0，29.65s | 三张完整 control 图说明列获局部视觉通过；两次打开过早关闭 |
| [run05](evidence/native-run-05.json) / `64ac68b` | 9 PASS / 4 FAIL，19 PNG / 3 NOT_RUN；磁盘 report completed | runner INCOMPLETE，180s timeout，exit -15；无 stdout 路径 | 原生激活交回与额外 resign observer 重叠；失败后草稿等待 Quit 决定；报告另经身份核对读取 |
| [run06](evidence/native-run-06.json) / `d72f966` | 9 PASS / 4 FAIL，26 PNG / 3 NOT_RUN | runner INCOMPLETE，180s timeout，exit -15 | 删除额外 observer 后首次浅色稳定，后续仍原生提前关闭；原 FAIL 不覆盖 |
| [run07](evidence/native-run-07-close-trace.json) / `5114b08` | 9 PASS / 4 FAIL，26 PNG / 3 NOT_RUN | completed 报告后有界诊断终止，38.63s / exit -15；不是 180s 超时，也不是正常 Quit | 三次意外关闭的立即调用链来自 AppKit resign-key，无 Riftlet 显式 close；私有原始栈不公开 |
| [run08](evidence/native-run-08-target-action.json) / `a2ac417` | 9 PASS / 4 FAIL，20 PNG / 2 NOT_RUN | runner INCOMPLETE，180s timeout / exit -15；报告另由同根文件恢复并核对 | 改标准 `NSApp.sendAction` 仍失败，排除 performClick 特有 tracking 是完整解释；没有修好结论 |
| [run09](evidence/native-run-09-native-responder.json) / `6796536` | 12 PASS / 1 FAIL，30 PNG / 0 NOT_RUN | 正常 exit 0，22.915s；stdout 回执完整 | 单行删除 show 后强制 responder，四次 popover 稳定；暂停/隐藏 timeout 未归因，整轮仍 FAIL |
| [run10](evidence/native-run-10-pause-trace.json) / `f0a03f7` | 12 PASS / 1 FAIL，28 PNG | 正常 exit 0，23.695s | 暂停/隐藏与 collector 观察通过；深色 display 之后 `pageNotPresented`，own-window 鼠标事件来源及因果未确定 |
| [run11](evidence/native-run-11-owned-page-trace.json) / `f0e5b99` | 13 PASS / 0 FAIL，33 PNG | 正常 exit 0，24.162s；自动 restart 6/6 PASS、exit 0 / 0.460s | 只增加 driver 页状态/hit trace，产品与 run10 相同；这次 scoped PASS 不归因前轮间歇失败 |

run09 的 driver 与其父 `a2ac417` 相同，只有一行产品变化；binary SHA-256 `599ef3884d3f89019f40a3e71a974f4123f233b13d16054b88c3a0bb1fd4e4f2`。这支持该次已观察 popover 问题的修复，不把一次内部 target-action 等同于物理输入。整轮 FAIL 时，自动 runner 不执行 restart 阶段。

run11 binary SHA-256 `9c33fddcb93accb379e240385aac7fd7a27b66b0c68e75d2fa4b17c6aa7e0fd5`；原生报告与两次进程/同根身份、33 张 PNG 的实际 SHA/尺寸均核对。自动重启前后五 JSON、完整资产 ID/媒体映射摘要、3 份媒体 hash、operations 0 / START 0 相等。重启没有制造 fixture、改偏好或重新弹出引导；该链与 d72 的独立 restart-only 分开记录。

## 独立补充证据

| 记录 | 已确认结果 | 限制 |
| --- | --- | --- |
| [bc903f7 CUA](evidence/cua-native-bc903f7.json) | Return 三步、位置选择、⌘,、归档 6.25、Quit 继续/应用后实际 22500 秒 | 同运行 binary 的隔离 wrapper；⌘W 和初窗尺寸当时失败，不是完整原包身份或 OS IME |
| [ea312a6 CUA](evidence/cua-native-ea312a6.json) | 先确认草稿后 ⌘W/继续；Quit 不保存后进程退出、86400 秒保留 | 未先观察草稿的连批操作保持 INCONCLUSIVE；工具错误不算产品失败 |
| [d72 原包 CUA](evidence/cua-native-exact-d72f966.json) | 精确原包隔离启动、引导 Escape；Quit 后原进程不在 | Quit 工具超时，无正常退出码；状态栏操作面不可用，实际点击 NOT_RUN |
| [d72 独立重启](evidence/independent-restart-d72f966.json) | 同包同 UUID 新进程正常 exit 0 / 0.466s；五 JSON/owners、SQLite pause/hide、1 媒体/asset 映射相等，操作/START 0，引导不重弹 | `PASS_SCOPED_NATIVE_RESTART`；原 run06 FAIL/timeout 和自动重启 NOT_RUN 均保留；不是生产升级 |
| [纯 AppKit 探针](evidence/pure-appkit-popover-key-probe.json) | 单个私有进程 9.847s 正常退出；后三次 popover 保持 non-key，只有明确关闭 | 第一次 action 后未展示；探针未做产品中的 `makeFirstResponder`，不能据此清除产品问题；无第二轮 |
| [Escape/CI 窄修](evidence/ci-settings-repair.json) | 真编译对象的 attached/key sheet Escape/Return、草稿/选区和 teardown 观察通过 | 旧严格 mask 与最新增量分开绑定；不是 XCTest、最终包或物理键盘验收；旧中间失败日志保留 |

实际对象探针原始记录中的 `keyEquivalentConsumed=false` 是未测量的历史占位字段，不用于通过结论。最新普通 Escape 接受 CapsLock/Function 状态的增量没有独立键盘 GUI 探针；run11 的普通关闭按钮流程不代替这项键盘验证。高对比度测试改读真实 effectiveAppearance；条件不足明确 XCTSkip/NOT_RUN，不再用不可移植的 bundle 初始化 fixture 假装实际高对比度。

run11 的非作者审查已逐张查看全部 33 原 PNG，无阻断视觉发现；原报告 SHA-256 `c574b00e0bed241d4ab7fa138c232e587443571ef6b00220eacd435d1999341f` 已绑定到 [run11 摘要](evidence/native-run-11-owned-page-trace.json)。[精确候选 CUA 键盘](evidence/cua-final-keyboard-f0e5b99.json)另外记录：⌘W 后 Escape/Return 保留 2.25 草稿、焦点与 dirty；⌘Q→Escape 取消退出；最后应用后目标进程不存在，JSON 为 8100 秒。最后 AX read 是 timeout，退出码未捕获，不补成成功 AX 读取或正常 exit code。CUA 未测 selection 范围、CapsLock/Function、物理键盘；相应边界保持。

## CI 与源码准入

[PR #43](https://github.com/haohongfei2001-png/Riftlet/pull/43) 为 Draft，初始源 `974e0bcde40f3f4d25ef1f1bbe0acc7d74575dc0`，正式基线 `c72fca78245a15a66ea6beaa980ec141f146bc1b`。首次 [Native 42205691399](https://github.com/haohongfei2001-png/Riftlet/actions/runs/42205691399) 两架构已结束：相同 12 个独立失败 case，共 24 次失败执行；原 ARM64/Intel 日志和 case 集合由 [首 CI 绑定](evidence/ci-974e0bc-first-failures.json) 保留。[Feedback 42205691613](https://github.com/haohongfei2001-png/Riftlet/actions/runs/42205691613) native/service SUCCESS，历史 composition 条件步骤 skipped。两项 source admission 因旧 PR42 记录 FAIL，不算准入完成。

已针对发现修正无效 UUID fixture、原生 alignment rect 与异步关闭断言、数值格式/编辑器断言、review 环境 fixture 和平台高对比度前提，并修复真实 Escape/Return 冲突。target build、parser 与有限独立探针的结果分开记录；没有把这些局部检查说成 XCTest 全通过。修正后的正式批次与最终五项 CI 仍待结果，最终非作者审查/G/直接 H/最终 App/ZIP 尚未收口。

更早的 PR42 主线 push 为 4 success / 1 ARM64 receipt 时序失败（Native 42184582609 / Feedback 42184582764）。那个原失败及后来的有界回执等待修正继续保留；它不代替本轮 Native 结果。本机 CLT 不含 XCTest，未用 shim 冒充其执行。

## 已安装版本与数据事实

Beta 1 安装 binary SHA-256 `c0ca439023a2fa92fd1cc08d4acff79dd780dc559d8a4c579af76d6fd5a76ea4`，推荐稳定恢复 ZIP `Riftlet-personal-beta.1-arm64-004741f.zip` 的 SHA-256 为 `c474a72157a3a1e513fa48f0bed1f696bdf38b5c6af669d434749a63cecef2cd`。实际路径保存在私有清单中；旧 `2a1622d` 候选只留作历史。

[已归档只读记录](evidence/production-readonly-current.json)的两次计数均为 94 assets、106 checkpoints、2 metadata、44 operations、0 compensation、18 START、94 media；当前全部媒体长度/hash 符合库存摘要，安装 binary 未变。初始基线只有计数与安装 hash，没有逐行/逐媒体摘要，故没有完整历史字节不变结论。此公开绑定和文档更新均未新增生产访问或写入。

最终包、完整原生验收、外观决定、重大 UI 合并、普通根升级与公开发行是不同结果；当前只完成表中有证据的部分。后续按 [交接中的下一步](HANDOFF.md#下一步与责任)推进，保留所有未完成状态与历史证据。
