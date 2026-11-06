# 有限精修原生验收记录

2026-11-06。本文件是本轮新增证据的索引。当前 **before 12/14 FAIL、两次 after 13/14 FAIL 均保留；最新 after-03 为 14/14 scoped PASS、39 PNG 字节/尺寸核对、同包新进程重启 6/6 PASS，两进程均正常 exit 0**。正常 39 图非作者目视已 scoped PASS；真实系统提高对比度运行和 CUA 的实际有限结果已补录。正式 CI/G/H 与用户外观决定仍待收口。原始数据不进入公开仓库。总体范围和原 G/H 身份见 [README](README.md)。

## 旧轮次与本轮 before 分开记录

| 运行 | 精确来源与实际结果 | 能支持的结论 | 不能推断的结论 |
| --- | --- | --- | --- |
| [run09](../beta2-product-20261106/evidence/native-run-09-native-responder.json) | `6796536dca650d4d9e09da2e636aba807f44bc7c`；12/13，30 PNG，正常 exit 0；`orthogonal-pause-hidden-sqlite` 为 `conditionTimedOut` | 同 driver 下删除展示后的强制 responder 请求，四次实际到达的 popover 稳定 | 无该次完整 switch→adapter trace，不能确定超时是否由本轮收录竞态造成；暂停观察区间当时未到达 |
| [run10](../beta2-product-20261106/evidence/native-run-10-pause-trace.json) | `f0a03f74ac1e23041ef5ce93774bac94fa8779f6`；12/13，28 PNG，正常 exit 0；六页为 `pageNotPresented` | 该次暂停/隐藏、collector 停止/恢复通过；最后成功页图为深色位置页 | 缺少失败瞬间的实际页/可见性，own-window mouseDown 的来源与因果未确定；负 eventNumber 不证明物理输入或工具来源 |
| [run11](../beta2-product-20261106/evidence/native-run-11-owned-page-trace.json) | `f0e5b99c0945c59652559501585b87aacb3203dc`；13/13，33 PNG，正常 exit 0；同包自动重启 6/6 | 该次完整隔离原生流程与重启 scoped PASS；相对 run10 只增加 driver 页状态/hit trace | 不倒推 run09/run10 的原因；不是本轮改动后的执行或用户外观决定 |
| 本轮新 before | `689259532c07e556de844887dc6e99130fc1e6ef`；实际报告 `0cd0038c…`，**12 PASS / 2 FAIL，共 14 项**，30 帧记录，报告 completed，runner 正常 exit 0、未超时 | 增加了明确的已接受收录命令与后台检查交错实验；暂停、恢复两个方向均复现未完成保存 | 不能写成 12/13；正常退出不等于整轮通过；新复现不填补旧历史 trace |

本轮 before 报告的六页 case 是 PASS，`orthogonal-pause-hidden-sqlite` 仍是 `conditionTimedOut`。这些是独立结果，不能把新竞态实验的已知因果扩写为另一失败或旧轮次的确定原因。

## 本轮 before 的不可混用绑定

| 项目 | SHA-256 / 实际值 |
| --- | --- |
| 原始 driver 报告 | `0cd0038cfc27c2b6ac2a6fe3c3a4cb78a43ce02727c5ed6510223f94dfad8eec` |
| runner 记录 | `4e3480d2bf588614708b31a26529a69731ab5d15c229e9858c345475e8ffee8b` |
| 可执行文件 | `ce47be4fdee8424d0e892121b5f8ae37bf600c8339abe7c966aae6071245331b` |
| 报告/runner 时长 | 22.130 s / 22.739 s |
| 总体结果 | `FAIL`；12/14；两个失败 case 如上 |
| 环境 | UUID 隔离根；同 App 的真实 host/model/SQLite/collector 与 AppKit 窗口 |
| 输入方式 | 原生 NSControl action 与 NSTextView 输入；不是物理鼠标或系统 IME 验证 |
| 浏览器 / 网络上传 / 生产数据访问 | 三者均为 false；没有将本轮隔离根当成普通数据根升级 |
| before 源码 / tree | `689259532c07e556de844887dc6e99130fc1e6ef` / `49c8659aa17e68d9255b8d41db163fced29bfb24` |
| before 构建清单 SHA-256 | `cb99d0f19ec3456cdc4c6b25d7047f9046464291308732143ecf2e3b6d824a43`；产品基线为旧 H `d1f4bef…`，增量只有 review 专用同步 recheck 回调及 driver 回归，没有产品修复；不是与 H 字节相同的原包 |

新增 `accepted-collection-during-recheck` case 的两条真实观察：

| 已接受目标 | 后台检查先持有执行入口 | owner / SQLite 前后 | 原 pending | 保存结果 | 无第二次用户操作自行完成 |
| --- | --- | --- | --- | --- | --- |
| 暂停 `true` | 是 | `false → false` | `collectionPaused(true)` | `writeUnconfirmed` | 否 |
| 恢复 `false` | 是 | `true → true` | `collectionPaused(false)` | `writeUnconfirmed` | 否 |

原方向仍被保留，但“记住 pending”不等于执行成功。after 分别检查原明确目标、owner 与 SQLite，不能只看到错误提示消失就判通过。最新两条真实结果均为 accepted=true、recheck 先持有入口，暂停 `false → true`、恢复 `true → false`，owner 同步到目标，pending/failure 为 none，`sameDirectionCompletedWithoutRetry=true`。它证明这两次受控交错完成了原请求，不是随机并发的穷尽证明。

## 本轮 after 的完整顺序

| 运行 | 源码 / 二进制 | 实际结果 | 保留的失败与修正范围 |
| --- | --- | --- | --- |
| after-01 | `c5dbc48f3e5e4156996a07841a7d7e30601bcfe9` / `044c33bb6e1e27cedc7091008fb6ab91d2a8f18809b8ccb2264ebccd021657d0` | 13/14 FAIL，30 帧；正常 exit 0，25.081 s | 新双向竞态已 PASS；`orthogonal-pause-hidden-sqlite` 的 driver 在状态栏动作前等待 foreground 超时，当时 owner 已暂停、无 pending/failure。随后只修 driver 在早先激活已失效时重新展示自己的设置窗口，再保持原等待/稳定断言；不加产品焦点门槛 |
| after-02 | `108a709a7e5b44746946546a78f3af1b3b9d78ff` / `13a6b17e6191c01a9f096cbd13a030f15267ae0337e749deffbdd80511f849c8` | 13/14 FAIL，38 帧；正常 exit 0，25.996 s | 暂停/隐藏已 PASS；新增最小窗检查在 `resizing-and-reopen` 查找了错误 ID `settings.center.display.details`。实际既有 ID 为 `settings.center.disclosure.display.details`；只纠正 driver 的三处引用，未删除可达性断言 |
| after-03 | `a5aefd3d166156c74399b700fa9f167e6bc2408d` / `e0505af18b2828c3acf88477e6fbb382c975c9097b1de1a222a19e5383e36c39` | **14/14 PASS，39 PNG；正常 exit 0，26.785 s；自动重启 6/6、exit 0，0.457 s** | 两个受控方向、暂停/隐藏、六页、归档、编辑、关闭、失败/重试、预览、引导、最小窗、历史与媒体边界全部到达；仍不唯一解释旧 run09/run10 |

从 after-01 到 after-03 的差异只有 `SettingsReviewDriver.swift` 和 `SettingsStateModelTests.swift`；后两次没有再改变产品实现、原等待阈值或放松原验收断言。新增最小窗覆盖是额外检查，最初错误定位器的 FAIL 也按原结果保留。

| 证据 | SHA-256 |
| --- | --- |
| after-01 runner / 原始报告 | `951b90a22befa506eb2a9c9beeb2784801d4ce1927840213290dbeb22024dda0` / `4c891e3ddade94c4030fe2e35a2e92477d38ad3f738a306d3540e1b9bae7e6e9` |
| after-02 runner / 原始报告 | `cfe5df92451494ea53feb0ef64681b361d13322d8872042a3204571688d60210` / `ab75b01ab375c1458da5188fd16df26e2e849ecf88095fa7699694737783c8b9` |
| after-03 runner / 原始报告 | `c52c768164816209ffe1a3bbb901c2a3e17935be8ed6f0a415e4564fec7b3ec4` / `a73b9285402a30bbb312d533b03f1d60ad9c59d0b48c28844c042b8e833432e9` |
| after-03 构建清单 | `da770ecc84168a66685baebab15e1879ee7d0198070538b9940c59168498ed09`；tree `240ccc5f5192c3d6f2ac22192a5343f7ac4fb2e6` |
| after-03 restart runner / 原始报告 | `f28bf66a9aa023f42e6745be669872b13bd9ac4288c665ddbd820e992121f060` / `40021f34a5e53418e1c62cf2780346d2be2451b30ae0c8ad90e83bf0b42f875e` |

已核对三个 after 的 runner、原始报告、build identity 与实际可执行文件 hash 相符；最终 39 PNG 全部逐文件重算 hash、读取 PNG 像素尺寸，与报告一致。文件与身份核验之外，非作者已逐张查看正常 39 原图；报告 `c22b83c7bce5dd834f8a8e40ccc8129106643f8c6a64f963a3ad775ae1721bcc` 为 `PASS_SCOPED_NATIVE_AND_ORIGINAL_IMAGE_REVIEW`，无阻断视觉发现，不等同最终 G 准入或用户外观批准。

同包重启是同一隔离根的新进程：5 个配置 JSON 字节相同且加载 owner 一致；SQLite 暂停/隐藏状态一致；已有首次使用记录未再弹出；3 资产/媒体对应及内容 hash 一致；operations/START 均为 0；重启检查未改这 5 个配置文件。独立只读数据库快照在子进程退出后取得，前后相等；不是普通根升级或真实截图迁移验收。

## 视觉 before 依据

本轮作者实际查看并逐一对 hash 的 13 张六页浅/深及最小窗原图均属于旧 run11。位置页预览与选择器分散、详细入口偏下、默认 `3.0 张`、重复正常说明是精修依据；旧图不覆盖。代表绑定：

| 原图名称 | SHA-256 |
| --- | --- |
| `settings-light-display` | `b688f71130acbeca864ce5205c30e1f5254c98c44a5a9641ca7b6053bd003a31` |
| `settings-dark-display` | `d972ed1df89553abcabfed183e69507dd120e571b10afcb9c99006e4dca4006a` |
| `settings-minimum-size` | `11b590e5ecde0afe8228615effeef9ebce907fefcbcfd5a38ccc80c162a28dd6` |

旧最小窗图记录的是外框 760×540 pt、内容 760×512 pt；不要与 XCTest 中主动设置内容 760×540 pt 的几何检查混称为同一尺寸。最新 after 同时记录真实 frame/contentRect，最小窗的六页没有横向溢出；展开位置页详细项后，document 高 971 pt、viewport 高 459 pt、滚动偏移 512 pt，应用按钮完全可见。

## 最新 39 图的实际尺寸

以下取自 after-03 的 AppKit frame/contentRect 与 PNG 文件，单位分别为 pt 和 px。未公开屏幕坐标、机器标识或原图。

| 画面 | 内容 | 外框 | PNG |
| --- | --- | --- | --- |
| 设置默认六页（含浅/深） | 960×684 | 960×712 | 1920×1424 |
| 设置最小六页及展开滚动 | 760×512 | 760×540 | 1520×1080 |
| 控制中心正常、浅/深、暂停/隐藏四态 | 336×450 | 362×476 | 724×952 |
| 控制中心保存失败 | 336×475 | 362×501 | 724×1002 |
| 三步引导浅/深 | 652×580 | 652×608 | 1304×1216 |
| 关闭草稿 sheet | 260×223 | 260×223 | 520×446 |

39 张包含浅/深六页、七张最小窗图、控制中心四态/失败、六张引导、编辑/关闭/预览和历史。正常 39 图的非作者逐图检查确认文字、选中态、控件与滚动入口无阻断问题；权限页相对更密、深色装饰性流程符号较弱的观察保留。它不认证全部可访问性、动效流畅度或最终用户外观。

## 真实系统提高对比度与 CUA

同一 `a5aefd3…` / `e0505af…` 二进制在实际系统提高对比度开关读回 on 的环境下完成 **14/14、39 PNG、重启 6/6**，两次 exit 0；runner 时长 26.414 s、重启 0.616 s。操作者随后将提高对比度还原为 off 并读回。普通/HC 两组独立记录，没有覆盖旧图。

| HC 绑定 | SHA-256 |
| --- | --- |
| runner / 原始报告 | `6dd1527e36c77709eb961d84e8204582675386937410be48ef7c9b9448a14dec` / `0605b6179135cee8a4497800db3e0ed07c8f0beb134de4f64c6286941398ccf3` |
| restart runner / 原始报告 | `66222be99737aeb8fea72ec12ad3fabd758dd01b988d5c3178c877d0c8be5b6d` / `ab3d44222c2fa6ff96cb5b97204746bcbe21f571f4c54f5efe3577643046ebcf` |
| 非作者 HC/CUA 证据审查 | `a2c240c180a83a29467fac02d371a16496acc0ea91adc740c0b5e7c7441a336c` |

HC 的 39 PNG 均重算 hash/尺寸，非作者实际查看其中 **24 张**，没有阻断视觉发现；不能写成独立查看全部 39 张 HC 图。报告中的 `effectiveAppearance.name` 不是 cached color provider 的 `bestMatch`，普通名称不能单独证明 HC 分支未执行，也不能证明全部 token 分支覆盖。本轮不宣称逐 token 分支采样、对比度数值测量或完整可访问性认证。

CUA 原始操作者记录 SHA-256 `ea9e5647b6ac876e704de3f4a3d553338bfe84b5e3c18ac2b2140e775be6c684`，脱敏结果见 [cua-acceptance.json](cua-acceptance.json)。它绑定精确 source/binary，非作者核查记录与读回；没有独立重放 CUA。实际范围：

- 开启系统键盘导航后，归档输入框 Tab 依次到 Save、Discard、Storage Check、原生 scrollbar；这是焦点序列，不冒充执行检查用量。测试后键盘导航还原 off。
- 2.25 小时草稿经过 ⌘W→Escape、⌘W→Return 均保留；Return 为继续编辑。没有认证精确选区范围。
- 活动输入框改为 1.75 后，不先失焦而首击 Save；草稿清除，保存/放弃禁用，私有配置读回 6300 秒。配置 hash 为 `b7df334d4601fa87b3688cf2d6b4c194aeee5985cbfc1bf748ced7f0b04719a3`。
- 保存后普通关闭、⌘, 重开干净通用页，⌘Q 后目标进程不存在；CUA 退出码未捕获，与 driver 的 exit 0 分开。
- 物理状态栏操作面不可用，系统表面查询超时；没有用另一输入工具冒充该项通过。实际 IME 尝试没有可观察组字/候选，不用粘贴替代；不公开个人输入源信息。VoiceOver 虽一次读回 on，未取得可靠持续导航/音频，随后独立读回 off，其原因未确定。三项仍 NOT_RUN。

最终实际读回：提高对比度 off、减少透明度 off、键盘导航 off、VoiceOver off。提高对比度与键盘导航记录为主动还原；减少透明度记录最终 off；不把 VoiceOver 后续 off 归因于未发生的还原动作。

## 生产只读保护

报告 SHA-256 `ff5cdb6713b165e26177d5e40a800161a3ee193b873936059fc1fa8ed6024b21` 使用只读 SQLite URI、query_only 和单读事务，另核媒体/配置/已安装二进制 hash。94 个资产/媒体逐 ID 详情、状态与 operation 关联和内容 hash/大小保持；4 份现有配置 hash 与 1 份原本缺失配置状态保持；已安装 Beta 1 二进制 `c0ca439023a2fa92fd1cc08d4acff79dd780dc559d8a4c579af76d6fd5a76ea4` 未变。operations 计数 44，当前实际 `upload_starts` 表计数 18。旧报告 START 计数使用 checkpoint 名称代理，不能据此宣称此前完整 START 行身份相同。公开 [results.json](results.json)只保留摘要/hash，不复制资产标识或数据行。

## 当前验收范围

| 场景 | 保留/增强的断言 | 当前状态与结果来源 |
| --- | --- | --- |
| 六页浅/深及最小窗 | 不裁字、不横向溢出；所有详细/精细项和错误重试仍可达；真实窗口尺寸单独记录 | 六页/resize 原生组 PASS；正常 39 图非作者 scoped PASS，无阻断；不是用户最终外观决定 |
| 位置选择与预览 | 2×3 文字、唯一选中、AX 名称保持；六按钮至少 62×32 pt；caption 不与图重叠；标准窗详细入口可见 | 既有 `LayoutCaptionStaysOutsideDrawing…` 增强，XCTest 待 CI；after 布局图已取得 |
| 保存失败中的位置 | 预览与控件显示已确认 owner；同向 retry 后共同更新，不把 pending 当作已生效 | 既有 `PlacementHasOneVisibleCheckmark…` 增强；精确 XCTest 待 CI，driver 失败/重试组不能替代这项断言 |
| 整数与编辑稳定性 | 默认整数没有 `.0`，小数/本地小数符正常；原始草稿、选区、marked text 和控件 identity 保留 | 新包归档/编辑/defaults 组 PASS；精确模型与 marked-text XCTest 待 CI，真实 OS IME NOT_RUN |
| 正常提示压缩后的异常 | 外观失败/读取不明、归档草稿/保存中/失败、显示器断开/未知仍显示完整提示与对应动作 | 新包独立失败/重试组 PASS；对应正常原图检查无阻断；所有组合单测待 CI |
| 控制中心 | 四态及长错误；开关方向不变；关闭入口/不可用/隐藏/隔离模式组合提示准确；次级按钮实际可达 | 四态/保存失败原生组 PASS，实际浅/深及错误图已取得；正常 7 张控制中心原图检查无阻断；组合 XCTest 待 CI |
| 三步引导 | review 能力说明与操作示意分开；第三步六位置在默认外框首屏完整可见；原显示器身份/失败/legacy 行为保留 | 浅/深三步原生组 PASS，实际 frame 已记录；正常 6 张原图首屏检查无阻断；viewport XCTest 待 CI；CUA 已做 Escape/设置快捷键，不冒充完整引导键盘覆盖 |
| 已接受命令与后台检查 | 暂停、恢复分别完成原请求；SQLite/owner 一致；未重发用户动作；原失败保留 | before 双向 FAIL；after-01/02/03 两方向均 scoped PASS |
| 关闭、退出与主动预览 | Escape/Return 安全继续；应用失败保留草稿；预览只在主动操作后播放，导航停止 | driver 原生按钮关闭、失败保存与主动预览组 PASS；两个最终进程正常退出；CUA Escape/Return 与首次保存已有 scoped PASS；新 XCTest 待 CI |
| 同包重启与数据边界 | 新进程读取同隔离根真实配置、媒体映射、SQLite；operations/START 不新增 | 最新同包 restart 6/6 PASS，前后只读快照相等；不借用旧 run11 |
| source admission、正式 CI、App/ZIP | 新精确 G、非作者审查、H 与实际运行源码/工件绑定 | PENDING，由集成负责人补充，不猜测 SHA |

本轮候选已实际构建并执行上述原生流程；Swift parser、App 可运行和程序化 driver 均不等于 XCTest 执行。正式 CI 仍待收口，不会删除旧失败来获得全绿。

物理鼠标、真实系统输入法、VoiceOver、实际登录项注册、真实 TCC 提示、多屏热拔、真实 ChatGPT 附件和普通根升级均不能由本轮隔离程序化运行推导为 PASS。用户最终外观决定仍待定；本轮未授权合并、生产替换或公开发布。
