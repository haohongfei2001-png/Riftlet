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

## 新记录正文组件的编译修正

第六轮 c74eac56 的 Native push/PR `40765889388` / `40765899978` 及 Feedback push `40765889306` 因 `FeedbackRecordBodyView.swift` 的 NSSize 上限 `.greatestFiniteMagnitude` 类型歧义编译失败。原生测试尚未开始，打包/新视觉未运行，不计作654项通过。修补仅将两个NSSize构造中的三个上限参数显式写为 `CGFloat.greatestFiniteMagnitude`；布局、滚动、生命周期断言与取证条件均未放宽。精确修补审查及新组合CI仍待完成。

最小类型修补已由非作者精确核准：`e9fa9c260281a39ac9805a9f0e07f31d9f1f3733` / tree `d86a4e5fd9373a32ff75e3b70806fa5c4433579d` / parent c74eac56，干净树；仅该原生文件两行与README/results。c74的四个Native/Feedback运行最终均为同一编译失败，原生0开始；两Feedback的20项服务和88项隔离通过。新pin只引用该已审source，待下一准确组合CI。

## 保留重复出现的预览失败并增加可归因观测

第七轮27db81fb的Native push/PR `40766737184` / `40766744451` 编译通过并调度654个唯一测试，但同一手动预览存在性测试再次失败。相同四个preview相关blob在5a详细串行0.063秒通过，这次并行测试整体1.034/1.717秒；整体时长不能说明动画已自然完成。当前仍不能区分动画被显式取消、自然结束或测试按sublayer索引取得错误图层。

Feedback push/PR `40766737084` / `40766744482` 成功：46项唯一原生（新增长文实际尾字滚动、单条目标sheet、IME折叠/刷新保持均明确PASS）、20项服务、88项隔离，均0 skip；52次原生执行含关闭重复6次不重复计数。新App和原尺寸视觉仍未执行。完整source.tar的853对象与Git blob/mode匹配27db。

追加只读内部诊断记录preview实际/被断言图层identity与父链、keys、uptime与CA本地时钟、布局/backing/辅助通知、action起止及原始delegate flag。生产默认不安装observer、不写日志或文件。原performClick及全部断言原样保留，没有延长产品时长、暂停动画时钟或接受nil；诊断用于归因，不作为修复通过。

非作者已精确核准诊断源码 `1c6ca389c6e3e9154d84757c32ef22ba4c0683ec` / tree `85a489c52b6db66b8248dce68658a90419e7784a` / parent 27db81fb，五个文件限三份诊断实现/测试及README/results。原时长、时钟、performClick、全部断言与CI门禁保持。当前仅更新三个既有允许元数据路径；诊断批准不代表修复、原生或视觉PASS，下一实际事件链将用于归因。

## 预览失败已定位为真实后到布局取消

第八轮260a4d7的Native PR/push `40768864109` / `40768855641` 均失败，654唯一调度；唯一失败仍为手动预览三条原断言。两份完整17事件链且dropped=0，证明真正imageLayer安装后88.550/104.634毫秒，bounds宽从444变429，随后layout.boundsChanged→show(false)→stop→static；既不是错误图层，也未到560毫秒自然结束。UTC打印时间不能作为事件发生时间，归因使用记录中的单调uptime。Feedback PR/push `40768864043` / `40768855467` 均46唯一原生PASS、52调用含6重复、0skip；服务20/隔离88PASS。新包装和视觉仍未执行。

设置页文档宽绑定clip，自动隐藏传统滚动条可在文档高度确定后占用15点，符合实际轨迹；具体style会由下一日志实读。局部修补只让RiftSetupController页scroll保留原生竖条槽位，保持系统scrollerStyle，overlay仍由AppKit自动隐藏；不改公共scroll工厂、动画时钟或真实缩放/尺寸变化时的静态重排。原performClick及全部原断言保留，并加强点击前后bounds稳定断言；新增单窗口legacy/overlay在实际需要/无需滚动的两种高度间转换回归。新的修补尚待非作者精确审查及下一CI，不能先宣布PASS。

Apple原始依据：<https://developer.apple.com/documentation/appkit/nsscrollview/autohidesscrollers>；自动隐藏会移除不需要的传统滚动条以释放空间，overlay忽略此属性。

非作者已精确核准局部滚动布局修补 `8d59ffacfdb1e647c118c98a29336c98f95b82e4` / tree `47d382d899cead08a41cd2d891d81ff133feb364` / parent260a4d7，干净树且五个文件与约定相符。原断言、动画时钟和真实几何变更重排保持；当前只更新既定三条pin元数据，等待下一准确Native/Feedback与原尺寸复审。444/429是preview view的bounds宽，图层身份一致不表示imageLayer本身具有该宽度。

## 第九轮：预览真实修复，磁力仍有两项可自主收口

2c8cd037的Native PR/push `40770139026` / `40770128579` 全量步骤均成功，各655唯一调度；详细结果各268唯一PASS（270调用包含2重复、0skip），包装及自检通过。手动预览两份完整13事件/dropped0证明真实legacy style=0、autohides=false、预览429点始终稳定，原断言以及legacy/overlay实际溢出/适合高度回归通过，先前后到gutter布局中断可限定关闭。Feedback两运行 `40770138950` / `40770128612` 均46唯一原生、20服务、88隔离PASS，0skip。

push原尺寸证据135 PNG/6 MOV（普通46场景，加真实三项辅助组合3场景）；非实现作者完整检查43静态原图与912解码帧，限定关闭D11 Feedback完整记录、D16邻项预览避让、D17吞噬闪回。PR普通组45/46接受，其失败magnet的16 PNG/1 MOV另保留；真实辅助组合因此NOT_RUN。两运行均见D18：目标微图先闪现，随后源端装饰才出现；两份frame-02原PNG SHA256相同4a56f645235d20d47dabd4d5171f4af2319249399f4d36028950a2ab543aa5ed。push自然finished，PR先watchdog timedOut、随后原delegate false；不是成功回调丢失。原始失败不能因push成功覆盖。

本轮修补在同一事务中设置行图像与隐藏状态，先展示无像素透明原生宿主，再以原assetReady时钟提交clip、模型终态和显式动画；backwards防止未来local起点前暴露终态，失败立即静态恢复。原560ms时长与assetReady+560ms+100ms清理截止保持；新增submitted与原始delegate时钟实读，不把timeout改成finished。增加正常计划、80ms已有elapsed、原时钟映射、自然finished/raw true的严格原生回归；原50ms清理测试不变。点击回归在submitted时断言图像已经隐藏且两块真实输入窗仍可见。原XCTest使用CATransaction.flush驱动提交，仍不能代替新MOV自然完成门禁。

MOV编码、像素复制、等待和hash移入独立actor；MainActor只负责原窗口采集，以单个await保留背压，原PTS、帧上限、缓冲和无插值约束不变。新movieProcessingOnMainThread必须实读false，true/缺失/非布尔全部拒绝；19项Python manifest测试通过，但实际macOS编译和新原尺寸效果仍待CI。入口提示缩短以消除末行孤字。产品时钟假说仍待新日志验证，不作已证明根因。

环境恢复时本地未上传的ae07e3b checkpoint丢失，已据前次已审差异恢复；原2c8制品、完整报告与D18原始图像未丢失，D18设计补充报告逐字节恢复，独立工程报告依据保留证据重建。新checkpoint必须再次取得非作者精确核准，不能沿用已丢失提交号作来源。正式分支、main、生产与安全重试边界不变。

## 最新远端内置截图修补的局部吸收（待本统一源实际验证）

2026-10-29重新核对时，正式0e7、Feedback7ef6、批准设计7e03与main eba1未变，独立内置截图分支已前移至`6b60f67f6d35272eecff901c507bd75a77874ed6`。它与本候选共同祖先为443d，不能整支覆盖正式工程。该分支的双架构region组件证据确认两个与当前源码实际相关的问题：系统CLI不能直接使用隐藏叶名；由应用发起的真实PNG同样可含系统截图xattr，不能由此升级其来源资格。旧分支日志只作缺陷归因，不借作本统一App通过。

局部修补保持最终隐藏文件名，改在新建私有隐藏目录中向系统命令提供普通PNG叶名，以目录描述符、身份核验和linkat排他发布；不替换已有目的地，取消/失败不删除非空输出。Host改用专用built-in导入API，原件和编辑件都记applicationScreenshot；去重遇到其他历史origin拒绝，不重新标记原记录。外部系统截图观察/准入、Core、Adapter与原上传证明不变。该分支的设置key迁移不适用于本候选现有isEnabled，因此未引入。

Native PR新增单独串行、显式opt-in的自有不透明合成窗口region组件探针，每次至多一次实际命令，不补拍、不上传；全量并行与push不会开启此probe。权限/拓扑/遮挡前提不满足保留NOT_RUN；实际命令、发布、导入、持久化或输出图案校验失败记FAIL，不放宽成环境跳过。通过完整隐私守卫及原字节核验后才可归档原PNG，结果和次数另存capture.json。其范围限真实Apple CLI→安全发布→私有导入/SQLite，不能替代入口三模式、物理选择、底层焦点或端到端上传。实际次数和结果以新run为准。

恢复后的测试实参顺序错误已由独立工程审查在CI前拦下并局部修正；旧8969d93b/cee67树不作为已批准来源。此轮完整修补需重新固定source SHA/tree、非作者批准与准确Native/Feedback CI，然后以新原尺寸影片确认D18及自然完成。

非作者已精确核准最终源码 `49f1f706fcaa34f3f1ee95bc6c46f0c97d0b03c6` / tree `bd3568d7cce5724596fa90a571f99233acde462b` / parent fa863572，工作树干净。完整19路径恢复/磁力/MOV/截图发布及来源修补和所有新增回归均经过独立静审；最后三文件取证残留记账修补也已核准。Core、Feedback、服务、Adapters、CSQLite、Package、Main与Feedback workflow相对2c8保持。本次仅更新既有三条允许元数据路径及REVIEWED_SOURCE，准确组合CI、单次真实区域组件与D18/自然完成原尺寸复审仍待实际运行，不能先标PASS。

## 第十轮：保留准确失败，修正运行中原生滚动样式与回调交付

隔离源 `5edb27ba875a4fc772161d44a3bb91ff71d6e73d` 已在新 Draft PR #16 运行。原PR #15并发新增仅旧2c8诊断workflow，全部原样保留，未吸收其500ms实验清理宽限或借用诊断绿灯。三条准确运行均通过固定来源审计。Native PR `40820773407` / push `40820741329` 编译成功并各调度666唯一原生测试，但两者均失败；新App、原尺寸视觉与opt-in实际截图组件均未运行，实际新Apple命令调用0。Feedback PR `40820773403` 成功，46唯一原生PASS、52调用含重复、0skip；服务20、隔离88通过。

两Native的新截图publication回归在同两处URL列表断言失败：Foundation枚举返回/private/var路径，fixture从/var别名派生。仅将整个测试fixture临时根预先canonicalize，原排他、目录身份、非空保留、原字节及列表断言均不放宽，产品截图路径不因此修改。

push另暴露两项实质UI问题。设置preview完整17事件/dropped0证明：动画安装时原生style=overlay、clip476、preview444；75.09ms后AppKit自动改为legacy、clip461、preview429，触发布局静态重绘。上轮在实际legacy下的限定通过仍保留，但不能代表动态style切换已修复。现在仅在统一设置页按NSScroller提供的原生legacy宽保留固定gutter，文档宽绑定scroll外框减去gutter；两种系统滚动样式均可正常使用且保持列宽/位置。原所有失败断言保留，新增播放中overlay↔legacy的frame、横向可见原点、document/clip约束、动画持续与真实滚动必要性检查，不强制系统style、不改全局偏好。

push严格正常磁力测试得到timedOut；其raw stopped=true断言未失败，但旧日志没有完整raw/交付时间，不能由此确定本次唯一根因。移除native delegate已在main时的额外dispatch，主线程真实flag在当前执行轮交付；非主线程仍原队列转发，false不变、generation清权及原assetReady+560ms+100ms清理截止不变。新增确定性主线程交付/原flag回归；原正常计划仍严格要求finished/raw true，并输出有界submitted/原raw时间/交付时间/完成时钟以核因果。此修改不能借旧2c8诊断对照五次成功宣称有效，仍需准确新CI与原尺寸MOV。

原始依据：Apple [preferredScrollerStyle](https://developer.apple.com/documentation/appkit/nsscroller/preferredscrollerstyle) 明确系统可在运行中自动更新所有scroll view并retile；[scrollerWidth(for:scrollerStyle:)](https://developer.apple.com/documentation/appkit/nsscroller/scrollerwidth(for:scrollerstyle:)) 提供对应原生宽度。本轮不以加等待、延长动效或接受nil/timeout来收口。

非作者已精确核准本轮七路径修补tree `eaffe8ad665cb56ba4c403ab665ca15543d913e0`，canonical源码 `ee6149bad38b5ed0fbc2b803c8891df909d6940e`、parent5ed与冻结本地检查点完全同tree，工作树干净。当前仅更新既定三条来源元数据，历史审计、CI顺序、原所有失败断言及原磁力时长/100ms清理上限不变。新准确Native/Feedback、单次受控组件和原尺寸影片仍待运行，不能继承先前通过。

## 第十一轮：验证夹具按真实文件身份与持久化事件判断

`2265afc9` 的 Native PR `40821858383` / push `40821851037` 编译成功并各调度667项，PR两项、push三项失败。两份完整日志没有磁力/设置的新失败，但成功的并行stdout被抑制，详细suite和新MOV尚未执行，不能宣布视觉或时序稳定。Feedback PR `40821858400` 为46唯一原生PASS、52调用、0skip，服务20/隔离88；完整source.tar855对象与2265精确匹配。新App、视觉及真实组件仍NOT_RUN，实际Apple命令调用0。

上一轮仅对fixture根调用resolvingSymlinksInPath不足：Foundation目录枚举仍返回/private/var而派生URL使用/var。两个原列表断言改为严格完整目录必须恰含1项、basename一致、lstat不跟随链接且双方均regular，并比较dev/inode/birth/UID/size/权限。它仍拒绝多余文件、符号链接、错误身份和残留stage，原字节、排他、取消和替换目录保护断言不变；不再拿URL字符串形式当文件身份。

push既有AcceptedSelectionQueue测试在固定150ms休眠后读到B仍prepared。原生产和该测试之前都未改，日志不足以证明永久漏清理。生产的绝对deadline授权、输入前后复核和UNKNOWN锁定独立于异步清理是否已落库。仅该测试改为通过既有onChange只读核同一B已durably failed后单次通知、在5秒有界失败窗口内等待真实事件；B的50ms有效期保持，测试不主动触发取消或drain。原B failed、A unresolved、inputs只有A、A完成后也不发B的断言全部保留，并校验观察时间不早于原deadline及原token失效。输出计划/观察时钟用于后续审查。这是异步测试完成同步修正，不改变生产deadline或安全条件，也不是把prepared作为通过。

本轮只改变两个测试文件和本目录两份事实记录；所有产品、helper、CI顺序、来源政策均保持。需要新的非作者精确源码审查、固定pin和准确CI，尚无新的通过结论。
