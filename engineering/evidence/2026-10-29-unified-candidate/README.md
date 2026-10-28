# Riftlet「薄界」统一内部候选 · 独立质量交接

状态：源码审查检查点；本文件将在实际 Native / Feedback CI 与独立原像素复审后更新。当前不声称新 App 视觉或真实操作通过。

## 正式合流

正式 `0e7ea8be` 与原生 `443d21d` 的共同祖先为 `1920e056`。按真实双亲合流，保留最新 Feedback 可靠性修复与全部截图生命周期。预测入口 `5d6a683`、磁力基础 `d552a738` 已为候选祖先，零重复 cherry-pick。远端合流对象 `0c13806e` 与独立初审的本地 `8dae90d` 双亲和 tree 精确相同，只有 GitHub 提交身份/日期元数据不同。

## 本轮主动收口

- 在同一设置窗口中嵌入入口启用、下次默认模式、入缝动效原生预览、稳定显示器选择、闲置归档小时数；保存失败恢复原选项，旧偏好向后兼容；后台刷新及同尺寸布局不打断手动动效预览。
- 修复末页重叠；固定容量分页，保留滚轮逐行与原指针/选择安全边界。
- 精简历史日期与空详情操作；保留完整状态、UNKNOWN限制、Finder/归档恢复资格。
- Feedback 顶对齐、保留合法重开位置，私有目的地告知与草稿/IME/删除/重试修复全部保留。
- 原生侧栏图标、可达标题栏恢复、物理像素编号垫片与减少透明度父表面修正。
- 明确打开辅助窗口前结束截图会话，防止活动选择层覆盖窗口或把操作误当截图。

## 独立性

产品修复作者为正式集成负责人；design_review 与 engineering_review 均非产品实现作者。新的统一固定审计由 engineering_review 编写，集成负责人独立逐行审查该审计；原生视觉取证 helper 由 acceptance_audit 编写，另由负责人与两位非作者复查。初审报告与原始文件对象记录同目录保留；其对象清单只证明记录时的源码状态，不冒充最终源。

新 gate 固定执行两份旧审计的原始 blob，再逐对象固定新组合。旧审计不改，不加入目录级白名单。PR main 测试 merge 仅允许精确双亲和 15 个固定网站对象，main 本身不合并。

## 原尺寸证据与真实验收边界

旧 15 张原生 PNG / 5 段 MOV 保留各自来源，20/20 manifest 校验完成；不是新组合截图。新 CI helper 只捕获本进程实际 AppKit / WindowServer 窗口，使用隔离合成 fixture；新截图与原生 MOV 将记录 source、checkout、像素/点尺寸、capture 时钟和文件 SHA-256。截图采集与审美结论分开。无真实截图、旧数据库、浏览器或云端操作。

已登记 Mac 在本轮开头离线。物理鼠标、真实截图文件、多显示器拔插/旋转、Spaces/全屏、跨应用焦点、系统辅助选项真人切换和 Feedback 真云端均 NOT_RUN，不能由 CI/CGEvent/合成 AppKit 代替。旧 H 不复测，旧 UNKNOWN/原图/数据库/审计保留。

## 三类问题的交付结构

1. 实质修复并验证：仅在 CI/证据确认后列入，当前修复等待新验证。
2. 有明确方案值得继续自主打磨：由新原尺寸视觉审查提出具体问题，能修复的本轮继续完成。
3. 平台或缺少真人操作限制：逐项见 acceptance-matrix.md，正式交付时记录准确缺口及恢复条件。

普通生产上传、安全失败/安全重试保持关闭。Feedback endpoint=nil；本机“保存待发送”不表示开发者已收到。PR #1 保持 Draft，main 不合并，不公开发行，也不要求创始人立即体验。

## 精确源码复核

非作者 engineering_review 已只读批准固定源码 `dd0d80b5b6e3836da4fd3627866beba6a18cc6d5`，tree `3d1a33f657d365fb47a6bc741cd96749ec8889a7`。确认两条正式祖先、干净树、所有最终产品/CI/helper对象；设置示意预览仅在有效模式、实际尺寸、原生 backing 属性或辅助选项变化时重排。这里的源码批准不代表创始人批准视觉参数；新 macOS CI 与图/MOV审查仍 pending。

## 首轮 CI 修正记录

Feedback run `40754551166`（head `d909ecc`，checkout `10850947666b8b047bb357cb618ab48acaf8fa5a`）通过 88 项隔离审计、20 项服务测试后，在新视觉 helper 的 Swift Quartz API 桥接处编译失败；原生测试未执行。已改用 SDK 明确推荐的公开 `CGImage` Swift overlay，并把本进程的正数窗口 ID 按 Quartz 要求编码为 nil-callback CFArray，不捕获其他进程、不申请权限、无动态符号替代。非作者工程复核批准新 source `7bdd46362b71229c29d65f0554d526c0b09e79dc` / tree `8494f8fdae3ccf33ab0016a8db47ffdb3bfaaeba`；仅 helper 10+/8-，产品源码未变。新组合 CI 与实际图/MOV仍等待执行，不继承为通过。

## 原生交互回归修复

第二轮 head `8db2ec`：Feedback `40756079028` 通过40项唯一原生/UI测试、20项服务测试、88项隔离审计（均0 skip）；关闭回归额外重复3轮不重复计数。Native `40756079761` 实际调度637项，新增归档 Return 测试发现一次输入导致两次保存，打包/视觉步骤尚未运行。已修复为仅Return或保存按钮主动提交、失去焦点不保存、同值幂等，并按Host秒/小时roundtrip规范小数比较；原测试未放宽，另覆盖blur及0.011连点。非作者确认新source `cba039bae3fb976295d00869d5117fbaab50a26d` / tree `413ab447aa47f26ab2c27737ec7db887307163cd` 可固定；新完整CI与视觉仍待验证。

## 已通过 CI 后被独立视觉审查驳回的取证

第三轮 head `fea485ce5226ab519af8f5325412b2ef43ba4a5a` 的 Native `40757263054` 与 Feedback `40757262980` 均成功。Native 调度637项，已知手动预览详细测试因真实系统 Reduce Motion 跳过；Feedback40项唯一原生/UI、20项服务、88项隔离测试通过且无跳过。独立包检查确认14个构建输入对象、资源签名哈希、实际arm64二进制与精确源码一致。这不等于视觉通过。

独立设计审查实际查看37张静态原图，并解码5份MOV，发现多窗取证使用 NSApp.orderedWindows 漏掉 NSPanel。24张辅助窗口图有效；13张边缘静态图、76张运动PNG和5MOV只显示自有背景，不得证明边缘或动效。原始文件及审查报告保留，见 independent-design-native-attempt3.md 和 attempt3-visual-integrity.json。真实 Reduce Motion 还使所有动效走none/fallback；无正常磁力或中断的视觉证明。

本轮修正取证为NSApp.windows自有可见集合与AppKit真实前后排序，并验证合成原像素确实不同于同一自有背板；空白取证失败关闭。CI临时机器恢复普通Motion/Transparency设置后，由全新AppKit进程读取真实属性；helper另记录起止系统状态。产品辅助功能guard保持。GitHub官方runner配置解释了原默认：<https://github.com/actions/runner-images/blob/main/images/macos/scripts/build/configure-system.sh>。新素材仍须非作者审美判断。

## 当前自主修复范围

- 固定设置/首用页脚安全说明；关于页Feedback按钮自然宽；补齐批准首用静态截图到边缘示意；首用和关于说明按真实运行模式显示，普通模式明确仅本地收录。
- 历史详情仅说明实际允许的放回/移出动作，UNKNOWN不出现不适用提示。
- 新自有截图原件和编辑派生件采用共享隐藏文件名，避免系统截图目录重叠时被active/retired watcher重复收录。保留所有旧文件；真实系统元数据原图仍沿既有来源/预检规则，编辑派生图仍为applicationScreenshot。未采用同期候选分支的全面来源重标策略。
- 权限提示的嵌套事件循环中，取消/禁用/新的启动会撤销旧启动token，迟到的授权不重新打开选择层。
- Feedback计数与既有Envelope的Unicode scalar/UTF-8/空白规则一致，保持本机保存和无云端送达声明。

以上最新改动正在等待精确组合CI和新原尺寸复审，不能继承旧通过结论。真实Mac仍离线；旧H、旧UNKNOWN、系统原图、数据库与审计未动。

## 第四轮准确源码固定

非作者 engineering_review 已确认 `49735b821bf8aae8f8327048a3c0ba159e1963d1` / tree `e3c9ebe8340852ab89e269d194d8cdc7c11dfac2`，工作树干净；所有产品/helper/CI对象与逐项复审一致，最新独立报告字节一致。统一gate现在仅将REVIEWED_SOURCE指向该检查点；没有新增路径豁免或改变旧审计。44个普通真实AppKit场景与3个实际系统辅助组合场景将分别取证，额外原生回归由下一轮CI验证。该确认仅为SOURCE_REVIEW_PASS；Native/Feedback、原尺寸图与MOV仍待当前提交实际执行。

## 普通动态环境揭示的预览回归

第四轮 c8c92f 的 Native `40761070646` 在实际AppKit三项辅助功能均false的基线下编译成功并调度645个唯一测试；过去因ReduceMotion跳过的统一设置手动预览测试现在执行，在动画存在性两处失败。打包与新视觉未执行，未放宽门禁。已保留原performClick与所有既有断言，并增加可见/有效几何诊断及同倍率backing回调不取消动画断言。

源码可明确确认的缺陷是backing属性回调不论真实倍率有无变化都会停止预览；AppKit的颜色空间/重复通知不应中断主动预览。修补仅在实际bounds或backing倍率变化时静态重建，其余只更新颜色；主动播放前完成待布局。它是针对性修补，此次CI的最终因果和视觉结论仍须下一准确提交实际验证，不在此提前宣布解决。

非作者已精确批准预览修补源码 `9a06e1e1a89fababd95cb892a662cbbf63e5c0c9` / tree `bd0663096e3b8510045ee05bf52710137e6e7b80`；仅3个预览源码/测试文件及两份元数据变化。原断言保留且新增回调诊断；统一gate只更新该source pin，下一准确CI仍待运行。

## 原像素复审推动的追加产品收口

第五轮 `5a9979693ac1bb28fa898d23c60bc791c2c7ec4d`：push Native `40762471599` 的645项全量调度、详细回归及打包成功，243个去重详细原生结果明确PASS且0 skip；先前手动预览回归明确PASS。PR Native `40762482432` 则在原有偏好目录替换测试的3秒删除观察等待失败，失败保留。Feedback push/PR `40762471635` / `40762482456` 均通过43项唯一原生/UI、20项服务、88项隔离，均无跳过；关闭测试额外重复不计新项目。

push视觉原始制品含118 PNG/5 MOV，39静态原图已逐张独立审查；driver仅接受102 PNG/4 MOV，正常磁力以timedOut收口而非finished，余16 PNG/1 MOV保留为诊断。非作者逐帧审查发现竖长预览遮挡相邻编号，以及两部吞噬片首帧全空后再现。新辅助系统三项共同开启的取证尚未运行，不能用helper override替代。完整独立报告见 independent-design-5a997969.md；哈希/原尺寸/PTS核验见 attempt5-visual-integrity.json；实现作者磁力诊断单列 attempt5-magnet-diagnosis.md。

当前追加修复包括：Feedback同窗逐条完整正文/状态/生命周期动作与绑定单条ID的原生sheet、100pt有界可滚动正文、后台刷新及折叠保留草稿/IME；原偏好事件去重补记消费者实际成功读取的文件签名，修复absent→实际读B→absent可能漏删，原3秒测试不改；预览避让所有可见输入岛且按剩余空间等比fit；吞噬最终model与显式动画同事务；原始CA delegate时间/flag仅作诊断，PNG比较/编码/hash改为一个等待完成的后台任务，释放主循环。没有放宽磁力自然finished、上传开始或完成要求。原尺寸新素材及这些新增测试仍须准确源码CI与非作者复审，不能从5a继承通过。

非作者已独立核准追加源码 `5d9ef9dc646361b736ef2f624a1674413c67a19e` / tree `16936100cac9b345fcc650afe4965172e2dbbdc7`，父源5a997969，22文件与冻结审查一致、工作树干净。这里只将统一gate的既有固定来源更新到该检查点；未增加豁免或改变历史审计。下一准确 Native/Feedback、普通46场景、实际三项共同开启的3场景及原尺寸影片复审仍待执行。
