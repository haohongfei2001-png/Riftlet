# 全产品验收矩阵

审计日期：2026-11-14（Asia/Shanghai）。源码基线：`44f745a15ecb3682a9da0bda17f17a5d9fc1f07e`；正式发布基线：`v1.0.1`，发布源 `5da42a221fb3e6496585c127e6cf11b8e836840f`。版本、资产与执行环境见[基线](evidence/baseline.json)。

本矩阵定义证据范围与验收门槛，**不表示下面的真机用例已经执行，也不替代问题台账**。问题状态与工程顺序以 [findings.json](findings.json) 为准；产品边界以[设计裁决](DECISIONS.md)为准。已有缺陷复核不等于修复已通过。

## 证据等级与状态

| 等级 | 能证明的范围 | 不能外推的范围 |
| --- | --- | --- |
| L1 · SOURCE | 已定位生产调用链、条件与状态转换 | 没有证明实际 GUI 表现、时间或在线服务结果 |
| L2 · CONTROLLED | 运行真实代码或工具，但使用受控 DOM、文件、SQLite、模拟服务 | 不等于 AppKit、系统权限、浏览器真实 DOM 或在线附件成功 |
| L3 · REAL_SURFACE | 实际公开下载字节/网站浏览器，或后续实际 Mac 原生界面；必须注明具体 surface | 网站 demo 不能证明 Riftlet；包的摘要/Ed25519 不能证明 Gatekeeper |
| L4 · LIVE_ATTACHMENT | 指定版本 Riftlet、Chrome、真实 ChatGPT 草稿的联合观察 | 只对记录的场景有效；START 不证明最终上传，也不证明用户已发送 |

状态统一为：**本轮执行·PASS / 本轮执行·FAIL**（受测断言的结果）、**SOURCE_CONFIRMED**（仅代码确定）、**仅历史证据**（过去执行，不能替代当前候选）、**BLOCKED**（已尝试但执行环境阻断）、**NOT_RUN**（本轮未执行）。无证据不是 PASS；修复复现脚本退出 0 也未必是 PASS。

## 本轮已取得的证据

| 本轮工作 | 等级与实际状态 | 可核对证据及边界 |
| --- | --- | --- |
| 生产页面程序的现有附件测试 | L2；本轮执行·PASS：56 个 Node 测试 | [TAP](evidence/attachment-existing-tests.tap)；受控 DOM，没有真实 Chrome/ChatGPT |
| 外来异步 picker 反例 | L2；本轮执行·FAIL：错误输入被写入一次 | [结果](evidence/attachment-foreign-picker-result.json)、[独立复核](evidence/core-independent-review.md)；生产 JS，合成图片/DOM；QA-ATT-001 |
| Linux Chromium 原生浏览器夹具尝试 | BLOCKED，产品未执行 | [启动错误](evidence/attachment-foreign-picker-native-attempt.json)；`socket() failed: Operation not permitted`，不是产品失败记录，也不是 Mac Chrome 结果 |
| 离线存储备份/健康/恢复工具 | L2；本轮执行·PASS：26 个 Python 测试 | [日志](evidence/storage-tests.log)、[范围和源码摘要](evidence/storage-evidence.json)；真实临时文件/SQLite，不是原生 importer |
| 反馈服务本地逻辑 | L2；本轮执行·PASS：24 个 Node 测试 | [日志](evidence/feedback-tests.tap)；SQLite 与模拟服务边界，不是原生反馈→云端闭环 |
| 官网中英文切换、演示、安装弹窗 | L3 · WEB；本轮执行，限定操作通过，另有 QA-WEB-001 | [观察记录](evidence/website-ui-review.json)；演示保留文字/已有附件并加入合成图片；没有操作真实 ChatGPT |
| 线上 feed、DMG 与官网内容 | L3 · CHANNEL；本轮执行·PASS | [核验记录](evidence/public-channel-verification.json)；HTTP/内容一致性、feed 与 DMG 的 Ed25519、DMG SHA-256；未运行 Apple 签名/公证/Gatekeeper |
| 原生 App、Swift 测试、系统权限、真实附件 | NOT_RUN：当前 Linux 无 Swift/macOS GUI | [环境](evidence/baseline.json)；QA-REL-001；不能合并前述 56/26/24 项形成“全产品通过率” |

## 真实用户全流程

每行的通过条件用于后续候选验收；本轮状态单独列出，不借历史执行覆盖当前缺口。阶段表示适合开展验收的轮次，不新建工作队列。

| 用户流程 | 本轮等级 / 状态 | 当前证据或问题 | 后续实际通过条件 | 阶段 |
| --- | --- | --- | --- | --- |
| 从官网理解用途与支持范围 | L3 WEB；本轮执行（有限范围） | [网站记录](evidence/website-ui-review.json)、QA-WEB-001 | 中英文核心内容/alt 一致；明确仅加入草稿、用户发送；桌面与移动窄屏可读 | R2/R5 |
| 点击正式下载 | L3 CHANNEL；本轮执行·PASS | 两个入口均为 1.0.1；[发布核验](evidence/public-channel-verification.json) | 链接、版本、资产字节与摘要一致；失效链接有可理解的恢复入口 | R5 |
| 下载后安装、覆盖原 App | 原生 NOT_RUN；文档 L1 | [安装文档](../consumer/INSTALL-AND-PERMISSIONS.md) | Finder 拖入、推出 DMG、从安装位置启动；个人/共享 Applications 均验证 | R5 |
| 首次启动、系统安全检查 | 当前包原生 NOT_RUN | feed/DMG 验签不覆盖本行 | 从真实下载保留 quarantine 的包启动；正确开发者身份；不要求关闭系统保护 | R1/R5 |
| 不读长文完成首次截图 | L1 SOURCE_CONFIRMED；原生 NOT_RUN | [设置方案](SETTINGS_REDESIGN.md) | 普通 Mac 新账户按界面完成；系统截图无需多余录屏权限 | R1/R2 |
| 稍后设置、主动重开引导 | L1 SOURCE_CONFIRMED | QA-SET-003 | 稍后后普通重启不强弹；显式重开可继续；未授予权限仍显示真实状态 | R2 |
| 目录权限拒绝、撤销、重新授权 | 原生 NOT_RUN | 源码与安装文档 | 拒绝时本地历史可用；授权原系统截图目录后新图可收录；无永久死路 | R1/R2 |
| Chrome 自动化/JavaScript 开关 | 原生 NOT_RUN | [安装文档](../consumer/INSTALL-AND-PERMISSIONS.md) | 首次请求、拒绝、系统设置恢复、Chrome 开关关闭/再开均能继续；提示符合实际权限 | R1/R2 |
| 自带截图入口的录屏权限 | 原生 NOT_RUN | 系统截图与自带截图路径需区分 | 仅此功能请求需要的权限；取消无假截图；系统要求重启后可恢复 | R2/R3 |
| 系统截图文件出现→边缘缩略图 | 原生 NOT_RUN | [存储审计](STORAGE_AUDIT.md) | 连续真实截图、文件写完/重命名/重复通知；每张完整图只收录一次，顺序可解释 | R1 |
| 暂停/恢复收录、更改系统截图目录 | 原生 NOT_RUN | 捕获与 source binding 调用链 | 明确停止/恢复；新旧目录不混用；权限错误不删除历史、不重复导入 | R2/R4 |
| 冷启动后第一次点击正确草稿 | L2 相关用例 PASS；L4 NOT_RUN | [附件审计](ATTACHMENT_AUDIT.md) | 无预热/旧 ACK，当前正确 Chrome 草稿出现所选图片；现有文字/附件不变；无发送 | R1 |
| 等待期间切换标签、窗口、导航 | L1/L2；L4 NOT_RUN | QA-ATT-001、QA-ATT-004 | 仍针对点击时身份或安全保留；不得选后来活跃页面/新会话；迟到结果不得注入 | R1 |
| 外来 input 与合法动态 portal | L2；本轮执行·FAIL | QA-ATT-001、[反例](evidence/attachment-foreign-picker-result.json) | 无归属 input 写入/事件均为 0；合法已证明归属的 hidden/detached/重建路径仍可用 | R1 |
| 同图重复点击、连续多图附加 | L2 相关用例 PASS；L4 NOT_RUN | 56 项受控测试只支持各自断言 | 连续至少三张并重复点其中一张；每次明确选择的正确图片一次进入对应草稿，无丢图/串图/自动发送 | R1 |
| Chrome 慢回、无响应、取消 | L1 SOURCE_CONFIRMED；原生 NOT_RUN | QA-ATT-004、[独立复核](evidence/interaction-independent-review.md) | 主线程仍可操作菜单/退出；超预算安全结束；迟到回复不重放；目标绑定不漂移 | R1 |
| 已证明未输入的失败 | 原生/L4 NOT_RUN | D04、D05 | 图仍可找回；用户明确再点才产生新尝试；错误文案只要求必要动作 | R1 |
| 已输入但结果不明 UNKNOWN | L1/L2 相关约束；L4 NOT_RUN | [附件审计](ATTACHMENT_AUDIT.md)、D04 | 保留图和原操作身份；不自动重传、不伪装成功；用户能去原对话检查 | R1/R4 |
| START 后状态与历史筛选 | L1 SOURCE_CONFIRMED | QA-ATT-003 | 正常显示“已交给 ChatGPT”，不算待处理；无匹配 START 的未知单列；关联后发错误/缺媒体优先；重试权限不变 | R2/R3 |
| 点击准备阶段崩溃后重开 | L1 SOURCE_CONFIRMED | QA-ATT-002、[独立复核](evidence/core-independent-review.md) | 旧未 dispatch 的 prepared 可明确再点；dispatchIntent/START/UNKNOWN 保留；启动不自动附件 | R1 |
| 打开历史、预览、恢复边缘显示 | 原生 NOT_RUN | [存储审计](STORAGE_AUDIT.md) | 缩略图/原图身份一致；可恢复记录显式恢复；缺图不崩溃；恢复可见不等于允许再次附加 | R3 |
| 私有图片丢失后补回并重检 | L1 SOURCE_CONFIRMED | QA-DAT-004 | 同源服务运行中补回正确字节即可重检恢复；UUID/操作保留；错误字节不解除 missing | R1 |
| 自动归档、移除、存储占用 | L1 SOURCE_CONFIRMED | QA-DAT-003；当前行为保留私有媒体 | 明确区分隐藏与删除；用量可查；未经新裁决不自动过期或删除原件/UNKNOWN | R2/R3 |
| 保存设置、切形态、重开确认 | L1 SOURCE_CONFIRMED | QA-SET-001/002/004；[处置表](SETTINGS_REDESIGN.md) | 新 IA、有效修改有即时结果；失败保留正确值；隐藏无关字段不阻断；重开与界面一致 | R2 |
| 偏好文件坏 JSON/错误类型/坏值 | L1 SOURCE_CONFIRMED | QA-DAT-001；[独立复核](evidence/storage-independent-review.md) | 安全默认继续收图/历史；保留原字节/其余合法值；不重建 DB 或动媒体/UNKNOWN | R1 |
| 正常退出、重启、睡眠、单实例 | 当前原生 NOT_RUN | 历史实现不能代替本次生命周期观察 | 队列、设置、媒体持久；无旧任务重放；单实例可靠；睡眠唤醒无重复 watcher/图 | R1/R4 |
| 写满、写失败、损坏与离线恢复 | L2 工具 PASS；原生仅历史证据 | [存储日志](evidence/storage-tests.log)、[历史有限卷](../../engineering/productization-20261107/storage/README.md) | 见下方数据保护矩阵；不得把 HFS+ 旧证据当当前 APFS/断电验收 | R4/R5 |
| 大历史持续使用 | L1 SOURCE_CONFIRMED；仅历史性能证据 | QA-DAT-002、[历史性能](../../engineering/productization-20261107/performance/README.md) | 实际 App 量测启动、刷新、读盘、RSS；消除重复全量工作，保留必要完整性验证 | R4 |
| 检查更新、安装、数据迁移/恢复 | CHANNEL 已执行；原生更新 NOT_RUN | QA-SET-006；[发布核验](evidence/public-channel-verification.json) | 见安装更新矩阵；真实 N→N+1 安装与重开，不能只验“已是最新” | R2/R5 |
| 提交反馈、断网与重开恢复 | L2 24 项 PASS；原生 NOT_RUN | [反馈日志](evidence/feedback-tests.tap)、[旧云端证据](../../engineering/evidence/2026-10-29-feedback-cloud/README.md) | 指定测试环境/合成内容完成原生闭环；拒绝/丢回执/重开不重复提交、不公开内容 | R4/R5 |
| 退出并卸载/重装 | 当前原生 NOT_RUN | [隐私说明](../consumer/PRIVACY.md) | 无运行残留/登录项误导；原截图不动；保留库范围与可选清理说明一致；重装能恢复保留库 | R5 |

## R1 最低真机门槛

执行责任：**具备 Mac、实际 Chrome 与专用 ChatGPT 测试账户的 Codex 工程执行器**执行；不同身份的验收代理独立读代码并复测关键路径。不得把例行验收转交给用户。当前没有已连接的 Mac 执行器；状态保持未执行，GitHub 任务交接不代表任务正在运行。

R1 应形成完整可用候选。以下门槛全部有证据，且无已知可复现 P0/P1，才可标记 R1 产品验收通过；后续仍需 R5 安装/更新准入。

| 必测组 | 最小实际动作 | 必需结果与证据 |
| --- | --- | --- |
| 候选身份 | 记录源码 SHA、dirty 状态、包 SHA、版本/build、签名身份、macOS/CPU/Chrome 版本 | 所测代码、页面程序、截图、日志对应同一候选；不可用另一 App 截图替换 |
| 新装首用 | 专用干净用户，保留系统安全检查；一次拒绝后恢复目录/Chrome 权限 | 原生引导截图、真实系统截图入队；首次附件可完成；权限失败不阻断本地历史 |
| 错误 picker 修复 | 重现 QA-ATT-001 的负例并测合法异步 portal/重建路径 | 外来 setter/input/change=0；不靠禁用正常入口达标；浏览器真实 DOM 证据补受控夹具 |
| 正确首击与连续图 | 冷 Chrome/无旧 relay，含文字与已有附件的实际 ChatGPT 草稿；再连续选至少三张 | 前后视频与合成图片标记核对；正文保留、图无错序/遗漏/重复；未触发发送 |
| 目标竞态与慢回 | 按下后换 tab/窗口/导航；让 Chrome 迟回/无应答，再取消 | 原点击身份可追溯；不得换后来目标；菜单可响应；迟到回复无注入；记录实测主线程延迟 |
| 崩溃边界 | 同一隔离库分别在 prepared、dispatchIntent、输入不明、START 后结束进程并重开 | prepared 可明确重试；其他状态不自动重放；原 UUID、attempt、nonce、媒体与 UNKNOWN 保留 |
| 损坏偏好 | 两份偏好各测截断 JSON、错误类型、局部坏几何、合法未知展示值及写失败 | 原生仍收图/开历史；坏文件原始字节保留；有效偏好不无声重置；坏归档先安全暂停 |
| 失败与保存 | 已证明未输入的失败→明确再点；不明输入→查看历史；正常退出重开 | 安全失败可恢复；真 UNKNOWN 不重复；正常 START 事实不被抹掉；无新增 P0/P1 |

真实 ChatGPT 上传完成观察可以补充质量判断，但不把服务端完成确认加入已裁决的 START 后管理边界。不得以测试需要为由执行发送，或把未点击发送的草稿写成“消息已发送”。

## 后续各轮如何关闭

轮次可以按风险合并；只有实际验收结果才能关闭，不以文档写完或任务已派发代替。

| 轮次 | 独立关闭条件 |
| --- | --- |
| R1 核心恢复与附件 | 上述最低真机门槛通过；所有已知 P0/P1 的修复和 QA-REL-001 的候选实际证据得到独立确认 |
| R2 设置与首次使用 | 61 项设置处置按专项方案落地；首启、稍后、权限恢复、保存失败、更新入口在同一原生候选可完成 |
| R3 视觉与历史 | 下方视觉关键组合有当前候选截图；历史各状态与恢复动作一致；主要 P2 逐项按规格验收 |
| R4 工程与兼容 | 精简没有削弱身份/恢复/数据保护；实际热点前后量测；升级/离线恢复与相关回归有执行证据 |
| R5 发行前复核 | 同一最终包全流程抽测与安装更新门槛通过；无可复现 P0/P1；残余 P2/P3 有明确影响、证据与处置状态 |

## 原生视觉与交互截图矩阵

本轮没有当前正式包的完整原生截图。PR58 的 [settings.jpg](../../engineering/pr58-native-review/visuals/settings.jpg) 与 [surfaces.jpg](../../engineering/pr58-native-review/visuals/surfaces.jpg) 仅为历史参考；旧“24 小时归档”等画面不能作为 1.0.1 或新设置验收结果。

以下均为 **L3 NATIVE / NOT_RUN**。不要求穷举无意义的笛卡尔积：六组形态×外观为基础，再以高风险状态覆盖显示器、缩放与辅助功能；缺失组合写明原因。视觉规格以[设置方案](SETTINGS_REDESIGN.md)和既有批准形态为准。

| 截图组 | 必须覆盖的画面/动作 | 可验证判断 |
| --- | --- | --- |
| 托盘 × 浅色/深色 | 空、1/3/4 张、超过可见上限；收起/展开/hover/按下 | 维持 2×2 最大 4 张；没有被裁切可点区域；可见数量与设置一致；图片/编号清晰 |
| 微缝 × 浅色/深色 | 空/多图、到达动画、展开预览、移出收起 | 不误遮挡内容；触发区/视觉一致；展开层不被屏幕裁切；动画前后命中稳定 |
| 风铃 × 浅色/深色 | 空/多图、悬停、点击、预览/收起 | 保留批准形态；阴影、间距、透明、图序与点击反馈连续；不引入候选形态 |
| 设置四页 | 默认窗口与最小窗口；中文/英文；正常/保存失败/权限失败 | 当前 `SettingsProductHost`；控件对齐、文案层级、无需读技术说明；无截断/重复按钮 |
| 首用与权限 | 干净首启、稍后、拒绝后恢复、重新检查 | 当前系统权限名正确；必要操作可见；无成功假状态或每次启动强弹 |
| 历史与状态 | 列表/网格、预览、搜索；交接/未知/失败/缺图并列 | 状态语义一致；异常不被绿色成功盖住；图像保真；长标题不撑坏布局 |
| 多显示器与缩放 | 单屏→双屏→拔外屏；1×/2×混合；主屏切换/负坐标 | 三形态至少各一次；位置回到有效可见区；记忆不丢；无幽灵窗口/重复托盘 |
| 桌面与空间 | Dock 四周可用位置；菜单栏；Spaces/全屏窗口/睡眠唤醒 | 不挡必要系统交互；焦点不被无故抢走；窗口层级与所在空间符合设计 |
| 减少动态效果/透明度 | 到达、展开、收起；浅深各一个关键画面 | 系统辅助功能生效；不靠动画表达唯一状态；透明减少后内容仍可读 |
| 键盘与 VoiceOver | 设置/历史/引导/反馈；Tab、Escape、按钮名称、焦点回归 | 焦点可见与顺序自然；装饰不朗读为动作；关键状态可读；无键盘陷阱 |

每组保存实际 PNG 与短视频（动画/竞态才需要视频），记录点数尺寸、像素缩放、屏幕布局、系统外观/辅助功能设置、来源包。对照图采用同一环境与合成截图；不能用重绘 mockup、网页 demo 或旧 fixture 代替原生结果。

## 安装、兼容、升级与数据保护

支持范围依据 [Package.swift](../../Package.swift) 与[安装说明](../consumer/INSTALL-AND-PERMISSIONS.md)：macOS 13 及以上，Apple Silicon / Intel。不能把 universal 产物同时包含两种架构当成两种机器都已运行。本轮以下原生用例全部 **NOT_RUN**；历史证据只在明确标注处引用。

| 场景 | 执行方式与最低组合 | 验收边界 |
| --- | --- | --- |
| CPU/OS 支持 | Apple Silicon、Intel 各实际启动/截图/附件；覆盖最低 macOS 13 和候选发布时所支持的当前系统 | 记录精确系统/硬件，不用 Rosetta 覆盖代替 Intel 原生；无法取得的组合保持缺口 |
| 新装安全链 | 正式来源下载候选、保留 quarantine，核对 bundle/嵌套组件签名、notary/Gatekeeper，再 Finder 安装 | 摘要、Sparkle Ed25519、Apple codesign、公证、实际启动是不同断言；逐项记录 |
| 安装位置/权限 | `/Applications` 与个人 `~/Applications`；非管理员账户/共享安装 | 无不必要管理员要求；单实例、权限身份、更新可达；不在 DMG 内误运行后声称安装成功 |
| 1.0.0 → 1.0.1 | 依现行说明退出、隔离备份、原位置手工覆盖 | 1.0.0 不被描述为已支持 Sparkle；旧库与偏好可读；不覆盖用户原件 |
| 1.0.1 → 后续候选 | 专用测试更新通道，真实更高 build，完成 Sparkle 下载/验证/替换/重开 | 不改当前正式 feed；“已是最新”不算安装测试；双架构/权限位置按风险覆盖 |
| 更新中断与无效包 | 测试通道断网、取消、坏签名/摘要、替换失败、旧 App 仍在运行 | 不安装未验真包；原可用 App 可恢复；不丢队列/截图；不能依赖手工删库 |
| 升级数据快照 | 升级前后比对隔离库 schema、关键 typed rows、媒体 hash、设置/登录项/权限体验 | pending、prepared、UNKNOWN、START、missing 都有样本；合法迁移外不改语义、无自动重传 |
| 恢复/降级限制 | 保存同版本可恢复备份；候选写过新 schema 后验证明确拒绝不兼容旧版 | 不承诺任意二进制直接降级；在副本上验证恢复，再说明恢复点与数据范围 |
| 空间不足/不可写 | 自有有限测试卷与隔离目录；导入前、写私有副本中、SQLite 提交时失败 | 原件/既有媒体/journal/UNKNOWN 不变；释放自有填充物后一次明确重试不重复；[旧 HFS+ 证据](../../engineering/productization-20261107/storage/README.md)不覆盖全部 APFS |
| 大历史与损坏媒体 | 200/2,000/10,000 条合成历史，少量可见；单个丢失/损坏/符号链接媒体 | 原生量测启动、读盘量、恢复次数、刷新解码量/RSS；目标校验仍在；不能以跳过 hash 换性能 |
| 卸载/重装 | 退出、删除专用测试 App；确认登录项与后台状态；重装并读取保留库 | 原系统截图不删；库保留/用户显式清理的行为与文档一致；未经裁决不加自动删除策略 |

不填满主磁盘，不触碰真实用户库，不伪造断电证据。离线 Python 工具通过仅验证该工具；原生恢复调用链、App 崩溃恢复与硬件断电分别记录，互不替代。

## 证据提交与独立退回条件

每个修复提交给独立验收代理时，附问题 ID、精确源码/包身份、最短复现、前后结果、实际执行命令与退出码、相关截图/视频及已知缺口。记录准备阶段、进程启动阶段和产品执行阶段；失败留存，不因换夹具而抹掉。

验收代理至少重跑与改动直接有关的负例和一个正常真实路径；检查真实装配使用了修复入口。旧 test double、未被 App 使用的恢复方法或未进入的窗口控制器通过，不足以关闭 Issue。

以下任一项成立必须退回，并给最小必要修正要求：

- 仍可向错误/无归属 input 写入；目标可能漂移；重复 setter、自动发送、丢图或 UNKNOWN 被自动重传。
- 把“START 后不继续管理”改成成功/失败伪证明；展示改动扩大 retry/restore 权限；为消除提示而重写旧记录。
- 把坏偏好、迁移失败或 DB 错误统一处理为空库/删图；安全默认暗中覆盖无法读取的原配置。
- 通过禁用合法入口、移除必要 hash/journal/事务、放宽 owner/identity 或重放来让测试变绿。
- 证据不是所审候选，测试只走非生产控制器，截图为旧版/演示，或者 BLOCKED/NOT_RUN 被写成通过。
- P0/P1 只有源码修复和便携测试，缺少本节要求的真实 Mac/Chrome/ChatGPT 路径；继续标记候选待验收，不宣布成熟或发行就绪。
- 设置表面变简洁但保存失败丢选择、重开不一致、关键权限/更新不可找到，或主要 P2 没有按具体规格验证。

最终判断应写“哪些用户流程在何种环境已验证、有哪些剩余风险”，不写“证明软件没有任何问题”。本轮结论：审计与可执行交接已形成；有确定 P0/P1，真实 Mac 与 ChatGPT 验收尚未执行，**不具备质量整顿完成或新候选发行通过的结论**。
