# Riftlet 1.0.3 产品审计与 1.0.4 范围裁决

审计日期：2026-11-17（Asia/Shanghai）。**本次交付是已决策的开发与验收工作包，不是1.0.4已实现或发布的声明。** 总任务：[Issue #106](https://github.com/haohongfei2001-png/Riftlet/issues/106)。精确身份见[BASELINE](BASELINE.md)，实际界面见[VISUAL_EVIDENCE](VISUAL_EVIDENCE.md)。

## 1. 结论与推广判断

1.0.3已经有完整的核心产品骨架：安全收录、准确绑定草稿的一次点击附加、START后收起、历史恢复、四页设置、真实保存、Sparkle及签名发行。PR #101、[#103](https://github.com/haohongfei2001-png/Riftlet/pull/103)、[#105](https://github.com/haohongfei2001-png/Riftlet/pull/105)有实质成果，不能因为旧Issue仍开着便重做旧修复。

主要差距是**消费级信息组织、外观控制的粒度、默认体验与最终候选的端到端证据**。设置中并排暴露工程参数和存储诊断；外观样例无法判断真正的托盘材质；现有色调同时影响整盘而非相机实体；归档后的搜索只查当前200条；关闭首用窗口与“稍后”的语义不一致。此次真实托盘检查还留下一个点击前命中所有权失败，不能用其他41项通过掩盖。

**目前不判定已具备扩大推广的完整证据。** 这不是断言核心附件已损坏：现有真实三图附件证据有效，但来源、时间间隔、包和环境有边界。1.0.4应完成设计整合，并让同一最终签名候选通过首用、连续两图、升级、恢复及真实原生操作。安装、首次成功、错误恢复和更新是发布门；新增功能数量不是门。

## 2. 实际源、构建与分发

| 对象 | 实际核实结果 | 含义 |
|---|---|---|
| 当前main | `3f8149e2313fd81bbaee5a7bbbdbb1efca2fc81b`，PR105合并 | 1.0.4规划基线B；PR105主要为ZIP官网分发收尾 |
| 公开1.0.3 | 不可变Release `v1.0.3-zip`，1.0.3(25)，macOS13+，universal | ZIP已实际下载并校验；不是计划中的DMG |
| 应用代码 | B与PR103发行源的Sources/Resources子树相同 | 后续文档和站点变化不能被误读为新的应用功能 |
| 签名/公证 | 本轮对公开ZIP内App运行codesign、Gatekeeper、stapler，三项退出0；Developer ID团队`ZB9D4T66QB` | 这是当前包验证，不等于已执行升级矩阵 |
| 官网 | 本轮读取的riftlet.com首页与B文件相同；下载为1.0.3 ZIP | 官网已承接ZIP安装 |
| 稳定更新源 | 本轮读取stable.xml最新仍1.0.2(24) | 不能写成“所有已有用户已可自动更新至1.0.3” |
| 外层DMG | 2026-11-16T18:26:49Z记录：两次提交仍In Progress；无公开1.0.3 DMG | App已接受与DMG仍等待是不同事实；不是Mac App Store审核 |
| PR评审 | PR103自动Codex review因额度用尽未完成；另有源码独立审查记录 | 不把额度失败解释成代码缺陷，也不算自动审查通过 |
| 远程保护 | 本轮API回读main protected=false、rulesets=[] | 五项CI及B→G→H约束仍执行；它们不等于远程保护已开启 |

公证记录：App `963c318c-7b96-4ca9-92a1-4b94615c4ca2` Accepted；DMG `20e69573-4eeb-4641-b8e4-7482f37af11f`、`4fbeac49-d9dd-4686-8a76-56df05498d8d`在上述快照仍处理中。状态只对记录时间成立；1.0.4开发不得等待、替换或再次提交1.0.3来“修整”本工作区。

## 3. 证据分层与本轮真实运行

| 证据层 | 已做 | 明确不能推出 |
|---|---|---|
| SOURCE | 固定B审查设置、托盘、Main、capture、queue、web桥、权限、更新、测试及历史审计 | 静态代码不能证明像素、真实网页或最低系统可用 |
| 既有CONTROLLED | 现有单元、Node/Chrome fixture、存储/布局反例及CI | 模拟input并非真实ChatGPT；绿色数量不代表消费体验 |
| 本轮NATIVE_SETTINGS | 公开ZIP原二进制；macOS27.0(26A428)、arm64、Mac17,3、单显示器2×；14/14 PASS、37张WindowServer帧；同包隔离数据重启一致 | review模式禁用真实登录项注册、更新、浏览器/TCC与真实采集；“不可用”是隔离环境，不直接报产品缺陷 |
| 本轮NATIVE_DESKTOP | 同包独立隔离profile；42项，41 PASS、1 FAIL；45帧；0/1/2/3/4/5/10图、三形态、浅深、位置和滚轮 | `tray-owned-button-and-escape`在点击前报`trayCameraObscured`；该用例尚未验证实际展开/Esc。进程退出0不能覆盖报告FAIL |
| 既有REAL_SERVICE | 源`624e1b5edc55aac2afb3ca588c5384b644736500`、隔离ARM/macOS27.2/Chrome156、匿名草稿真实三图、3 START、第三图双击仅一op、原文保留、0 send | 图间约2–3分钟，不证明快速双图；positiveReady=false；不能升级为1.0.4最终包通过 |
| 既有RELEASE | 真实1.0.1→签名公证1.0.2私有Sparkle升级，旧资产/START/UNKNOWN保存 | 非公开feed交付，不替代25→1.0.4与24→1.0.4 |
| 未覆盖 | 本轮物理鼠标、实际VoiceOver听读、系统IME、真实TCC、快速真实双图、多屏热插拔、macOS13与完整硬件矩阵 | 每项保留NOT_RUN；不把控制测试或历史旁证改写成这些格的PASS |

原生摘要、逐项case及发布帧hash见[evidence/native-runs.json](evidence/native-runs.json)。本轮只使用隔离合成素材，没有替换用户安装、访问个人截图数据库或向真实聊天发送内容。旧证据永久保留其来源；本轮发现的FAIL也保留，不删失败记录来制造全绿。

## 4. 功能实际完成度

| 产品能力 | 1.0.3状态 | 依据与1.0.4约束 |
|---|---|---|
| 系统截图收录、私有副本、journal恢复 | 已实现；当前collector隔离实跑 | `PrivateAssetImporter`、`CaptureService`；原件只读，身份/hash必须保留 |
| 一次点击附加、不发送、不扰草稿 | 已实现，有同源历史真实证据；当前最终包压力矩阵未齐 | `ChromeAppleEventsExecutor`、`WebAttachmentAdapter`、web JS、`TransferCoordinator`；不重写为剪贴板或拖拽替代 |
| 无归属picker拒绝、prepared安全恢复、坏偏好隔离 | PR101已实现 | 旧#78/#79/#80归入回归；不再无证据称当前P0仍未修 |
| 原生同步目标pin延迟 | 由旧多次5秒等待改为总150ms有界pin，页面工作后台执行 | 不是完全异步；测冷路径、卡住Chrome和可见点击响应 |
| 三种桌面形态、双列托盘与路径相关展开 | 已实现；本轮形态矩阵部分真实通过 | `RiftTrayLayout`/`RiftTrayMenuState`；保持已定行为，相机命中FAIL另查 |
| 四页设置、原生按钮、owner保存、中文/英文 | 已实现；本轮14项通过 | 继续组织与视觉精修；不恢复旧拉伸按钮或另建状态层 |
| 背景透明度、相机实体独立色 | 未实现 | 现有custom tint并不等价；新增两个正交控制 |
| 归档、仓库、恢复、列表/网格 | 已实现；默认闲置2分钟归档 | 归档只改可见性，不删除、不释放空间 |
| 全库搜索/筛选 | 部分：只查当前页 | `refreshHistory`201取200→UI本页筛选，需先查询再分页 |
| 本机空间统计 | 已实现只读用量 | 永久删除/自动清理尚未实现，本次明确延后 |
| 首用/权限 | 有3步引导、显式稍后、上下文状态；关闭语义存在缺口 | `recordPresentation`留下started；红关闭/Cmd-W未走deferred；普通重启需补实证 |
| Sparkle/退出/单实例 | 已实现；有历史签名升级 | 同营销版本RC迭代不可直接走现有isUpgrade；私有RC手动替换隔离App |
| 多屏/辅助功能/长期能耗 | 有实现和局部证据；覆盖不全 | 当前单屏、override高对比不代替真实系统切换、多屏及VO |

源码索引：[Main](../../../Sources/RiftletApp/RiftletMain.swift)、[QueueStore](../../../Sources/RiftletCore/QueueStore.swift)、[PrivateAssetImporter](../../../Sources/RiftletCapture/PrivateAssetImporter.swift)、[web脚本](../../../Sources/RiftletAdapters/Resources/chatgpt-web-20261027.js)、[支持矩阵](../../consumer/SUPPORT-MATRIX.md)。设置逐项证据与全部字段见[SETTINGS_INVENTORY](SETTINGS_INVENTORY.md)。

## 5. 设计历史与偏差裁决

| 原定义/已有决策 | 当前偏差或容易误判之处 | 1.0.4裁决 |
|---|---|---|
| 普通用户几乎不需理解内部实现 | 设置把目录全路径、磁盘字节细节、重检、pt/色相/百分比一起暴露 | 普通层保留目的明确的控制；低频诊断和旧参数渐进显示 |
| 视觉精致且自然原生 | 172pt品牌侧栏占814pt窗口；通用空、截图拥挤；92pt预览很宽但主体很小 | 紧凑顶部四页；统一行高/字体/间距；真实材质样例与位置示意分开 |
| 托盘有辨识度、2×2和独特展开 | 历史参考图是设计参考，旧debug截图不能当1.0.3；新安装默认仍microSlit | 保留几何/展开；仅真正新档案采用托盘3图，旧档案完全保留 |
| 相机实体可个性化且有体积 | 当前相机是线框，立体感主要来自外键帽；custom tint影响整盘 | 用原轮廓做克制浅浮雕实体，分开body/镜片/轮廓/键帽，不假称已有3D实体 |
| 点击完成自然收起 | START与READY曾被混淆；当前已按matching START投影 | 保留“已交给ChatGPT”，不引入“上传完成”、自动重试或常驻进度轮询 |
| 首用可稍后 | 稍后已修，红关闭未等价；review重启特判会遮蔽普通模式问题 | 三种退出方式统一延期；已成功授权不丢，不反复弹引导 |
| 一套当前任务入口 | AGENTS仍指PR101、质量状态仍描述1.0.2 | 增加当前1.0.4入口，保留旧记录为历史，不重写证据 |

没有证据证明PR103之后有人又删除了双列托盘、自然按钮或START规则。因此这些是**应保留的已实现契约**；不是虚构“被回退”来扩大版本。确实遗留的是旧工作入口、普通关闭语义与未完成的消费级组织。

## 6. 当前问题台账与范围

P0表示必须完成的风险修复或发布门，**不自动意味着已证实数据损坏**。P1全部列入本版计划；只有产生新的重大风险或实测收益不足的条件项才可按下述规则降级。P2明确延后。

| ID | 优先级/类型 | 当前证据与用户问题 | 最终决定、任务/Issue |
|---|---|---|---|
| A01 | P1 设计 | 设置混合日常选择和工程诊断，页间密度失衡 | 四顶部页、渐进高级、原owner；T01/T02，[#88](https://github.com/haohongfei2001-png/Riftlet/issues/88) |
| A02 | P1 缺能力 | 无背景透明度、独立相机实体色，预览非同renderer | 两个控制及共享渲染；固定外框；T03，[#107](https://github.com/haohongfei2001-png/Riftlet/issues/107) |
| A03 | P0 首用缺口 | 红关闭/Cmd-W没写deferred，started下次普通启动仍需呈现 | 等价稍后并普通模式复测；T04，[#86](https://github.com/haohongfei2001-png/Riftlet/issues/86) |
| A04 | P0 验收失败待归因 | 真实包`trayCameraObscured`，发送点击前检查失败 | 记录最上层窗口/坐标/scale，查环境或产品原因并自然输入复测；T03/T10，#92/#107 |
| A05 | P1 产品局限 | 搜索/筛选只在当前200条，默认归档后找回困难 | 全库元数据查询先于分页；T05，[#108](https://github.com/haohongfei2001-png/Riftlet/issues/108) |
| A06 | P1 体验/源码 | 权限/连接多入口；少数错误仅tooltip且硬编码语言 | 一个当前下一步；就地可见错误/恢复；T04/T06，#86/#96 |
| A07 | P0 发行门 | 旧真实三图相隔2–3分钟；不等于新包快速连续附加 | 同一最终候选快速两图/草稿/UNKNOWN完整回归；T07，#82 |
| A08 | P0 升级门 | 24/25→1.0.4、配置新字段、停止与恢复未验证 | 私有签名升级/崩溃恢复；禁止同版本RC强行走Sparkle；T09，#97 |
| A09 | P1 性能测量 | 启动先hash全部非used媒体；旧1万图共248MB代表性有限 | 1–2GB真实字节分布、3次A/B、30min空闲/2h混用后实测修复；T08，#93 |
| A10 | P1 无障碍 | 通知仅motion/延迟刷新路径，静止托盘未证明重绘；完整VO未验证 | 系统变化直接失效外观缓存；真实键盘/VO/浅深/对比度；T03/T10，#92 |
| A11 | P0 流程门 | review wrapper可能退出0但内部FAIL；源码、模拟、GUI、真实服务边界易混 | 解析case状态和覆盖；独立源审+同包证据；T10，#92/#106 |
| A12 | P1 治理 | main未受保护、入口过期 | 本包修入口，继续已有保护Issue；不改计费/账号、不弱化准入；T00，#83/#91 |
| A13 | P1 验证/P2条件实现 | routes/relays无retire，按不同draft/document增长；非每点击泄漏证据 | soak量测；只有真实损失才做安全释放；不得LRU清once-only墓碑；T08，#93 |
| A14 | P2 | 永久删除/空间回收没有实现，安全语义代价高 | 保持只读用量，明确归档不删；#95后续另作删除/tombstone设计 |

**REMOVE/REPLACE清单：** 品牌占位侧栏；设置中重复列表/网格选择；正常状态的文件全路径与存储长解释；正常状态重检按钮；普通层pt/色相/遮挡率数值；新用户自由输入归档小数；重复Chrome检查按钮；为展示外观另画的假托盘。移除的是普通入口，**不是删旧配置、删用户能力或删历史记录**。已有特殊值通过“旧版自定义”保留/调整；常用键、数量、三形态、动效和真实高级控制继续可达。

**不纳入：** Edge/Safari扩张、云同步/OCR、快捷键系统、全局主题编辑器、第三种动效、重写附件引擎/SQLite、1.0.3 DMG收尾、网站宣传、共享反馈系统重构。它们会增加验证面并稀释首用与核心可靠性；已有候选PR69/77及#104保持独立，不顺便合入。

## 7. 采用依据与独立判断

[Apple Settings](https://developer.apple.com/design/human-interface-guidelines/settings)支持减少无必要设置、选择可靠默认；[Materials](https://developer.apple.com/design/human-interface-guidelines/materials)、[Dark Mode](https://developer.apple.com/design/human-interface-guidelines/dark-mode)及[Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)用于语义材质、对比和系统偏好；[Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons)、[Layout](https://developer.apple.com/design/human-interface-guidelines/layout)、[Writing](https://developer.apple.com/design/human-interface-guidelines/writing)用于控件/布局与简洁文案。它们不规定Riftlet必须复制系统设置侧栏；四顶部页、托盘3图新默认、两个外观控制是本次产品裁决。

[Apple公证文档](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)区分Developer ID公证与App Review；[Sparkle文档](https://sparkle-project.org/documentation/)及[发布指南](https://sparkle-project.org/documentation/publishing/)支持签名/版本/私有更新验证的要求。Linear、Craft、Arc仅作为克制、连贯、反馈完成度的质量参照，不据其品牌外观推导本应用布局。

## 8. 推广就绪门

用专用新用户环境完成“安装→看懂→首张系统截图→出现→自然点击附加→默认归档→全库找回→恢复”，记录成功/失败与介入次数；使用说明必须来自App自身必要提示，不由执行者口头补齐。至少5位未用过Riftlet的试用者（或有证据的等价外部可用性评估）验证首次发现与权限文案，目标≥4位不经讲解完成主路径；这是一轮形成性检验，不宣称具有统计代表性。执行环境无法招募时标NOT_RUN，继续工程与RC交付，推广准备度保留未验收；不得由同一开发者自称模拟5位新用户。

所有技术门、可观察标准、测试档案及阻断规则见[ACCEPTANCE](ACCEPTANCE.md)。Codex依[IMPLEMENTATION_PLAN](IMPLEMENTATION_PLAN.md)推进；普通设计选择已在[DESIGN_SPEC](DESIGN_SPEC.md)裁决，无须逐项回问用户。
