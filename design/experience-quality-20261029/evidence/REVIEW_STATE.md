# 独立状态审查：Riftlet Experience Prototype

审查者：state_audit（非HTML作者）。日期：2026-10-29。范围：`Riftlet-Experience-Prototype.html` 对照 `STATE_TRANSITIONS.md` 的 Q03/Q04/Q05/Q10。只读检查HTML，没有改动原型或原生工程。

## 结论与证据边界

原型明确标识为模拟，并保持真实开始须单独注入、UNKNOWN隐藏、成功无Toast等主要原则。下列剩余问题需要在交付前修正，避免原型教给实现者错误的状态关系。它们是**交互原型问题**，不能转写为候选 App 的已知运行缺陷。

本次进行了静态阅读和 Node VM 中的原型JS状态执行。VM只提供假DOM与可控制定时器，不执行浏览器布局/命中/像素渲染，没有macOS、真实权限、上传或物理输入。运行读取的HTML SHA-256为：

`9baed92b7c00f9b7cbe0f8197c24d15ecc90cfdb8dac962c0d718dbc51cee50a`

作者正在并行修复。以下结果只针对该快照及本次所述片段；最终修改后的文件须另做一次限定复核，不能沿用该hash宣称新文件通过。

作者已自行认领的三项不重复计入本审查新增问题：captureDone只能在capturing接纳；captureCancel在已captured后承认原图已保存；mouseleave不能清掉业务吞噬计时器。

## 最小必修

### RS-01 · 点击资产与变化的行不一致

**位置：** `action('shot:n')`、`queueHTML`、`renderAttach`。

所有shot按钮使用同一global attachment状态，`queueHTML`却只把状态应用在 `i===0`；点击第二/第三图或其编号仍会把第一图显示为queued，后续吞掉第一图。输入岛和asset身份的核心契约在原型中被破坏。

VM复现：`selectScene('attach','idle'); action('shot:2')` 后输出 `class="queue-item queued" data-row="0"`，没有active row身份。

**最小修复：** 给演示对象稳定assetID/activeRow，把图片和编号都绑定同一资产，状态说明、吞噬与剩余队列都使用该身份。若原型只演示第一图，应明确把其他两行改为非演示/只读而不是让点击它们操作第一图。不得用数组当前索引充当跨补位资产身份。

**验收：** 点第2图的图片或编号，只有第2图受理/吞噬；第1/3图保留。补位后旧回调不能处理新占位图。

### RS-02 · 重置未让旧业务定时器失效

**位置：** `resetAttach`、`uploadStarted`尾部timer。

VM复现：`shot:0 → uploadStarted → resetAttach → 130ms`，最后 `state.attachment === 'started'`。刚重置的可点击样本被旧吞噬completion改成隐藏。

**最小修复：** 每个演示操作/fixture有独立generation或token；重置使旧操作定时器失效。Inspector按钮宜称“载入新的独立样本”，并明确创建新合成身份，不表现为给旧UNKNOWN解锁。计时器仅更新它所属的视觉状态，不能改动新样本。

**验收：** 上述序列最终仍为新样本idle；reset与scene切换期间无旧状态回填。旧UNKNOWN在语义上不被重置为可上传。

### RS-03 · 视觉吞噬阶段阻止接纳独立结果

**位置：** `unknown`/`complete`仅接受started/unknown；uploadStarted timer无条件写started。

VM复现：`shot:0 → uploadStarted → complete` 在120ms内执行时，完成被拒绝；130ms后只有started。当前实现将视觉动画进度作为后端结果接纳条件，与“开始/完成事实独立”冲突。

**最小修复：** 分离已观察开始、业务结果和视觉phase。开始已注入后，吞噬进行中同样可以收到UNKNOWN/独立完成；动画尾部只完成可见性退出，不覆盖更晚业务事实。可用 `operationResult` 和 `visualPhase` 两个字段，也可用等价的显式状态组合。

**验收：** uploadStarted后0/40/119ms注入complete或unknown，吞噬只执行一次；结束后分别保留complete/unknown；无成功Toast、UNKNOWN无重生/重试。130ms以后同样成立。

### RS-04 · 轻反馈的同岛条件与展示期限未实现

**位置：** `shot:n`250ms回调、`bindProduct`hover、initialize的callout。

VM在无任何hover事件的条件下，点击后260ms `callout=true`，再过3000ms仍true。代码没有原指针仍位于同asset输入岛的检查，没有2400ms退出，主动hover450ms再读也只实现了idle peek。

**最小修复：** 绑定实际hover asset与当前owner/generation。250ms触发必须核实原指针仍在同图的图片/编号输入岛；显示最长2400ms。退出后状态记号、tooltip/AX保留；同图新hover450ms可重读。状态说明优先于peek，退出不可清业务timer。静态情境若为了审阅而冻结说明，必须明确标“冻结画面”，不能混作真实时序演示。

**验收：** 249ms离岛不显示；同岛250ms显示且≤2400ms退出；新hover450ms可重读；从图片到同资产编号不会误判换资产；旧owner的显示/关闭timer不影响新状态。

### RS-05 · 屏幕变化错误文案声称了未经证明的“未拍摄”

**位置：** `renderCapture` changed情境。

现文案“屏幕布局已变化，本次未拍摄”不能概括原生错误：原生 `validateTarget` 也在系统捕获返回之后执行（InteractiveScreenshotController 279–282），此时原文件可能已生成，只是不能被接纳为原请求的有效交付。

**最小修复：** 使用“屏幕布局已变化，请重新选择目标”，配“原有截图保留”。若要说明未拍摄，必须另设明确只发生于曝光前的有证据情境；不要把generic topology error等同没有文件。

**验收：** 取消/目标变化/权限错误不统称没有拍摄；已完成原图保留。仅真实无副作用的输入前边界可以使用确定否定文案。

### RS-06 · 装饰容器仍覆盖透明输入缝隙

**位置：** `.queue`、`.queue-item`、`.entry`的CSS命中策略。

callout、peek、rift-line已经使用`pointer-events:none`，应保留。但queue/row默认pointer-events:auto，透明number/image间隙和行内余白仍先命中整个容器。没有触发上传并不等同于点击交给底层元素；该原型目前不能示意原生输入岛穿透。

**最小修复：** 装饰wrapper使用pointer-events:none，只有确切图片、编号和模式按钮恢复pointer-events:auto。需要hover身份时从这两个按钮计算union，不给整行增加透明接收面。父容器事件委托仍可使用，但不能成为命中面。

**验收：** 浏览器真实`elementFromPoint`或点击靶标检查图片/编号/透明gap/行间gap：前两者是对应button，后两者进入底层示意面；callout/peek与X盖片不拦截事件。此测试只证明网页原型命中，不能写成macOS物理穿透通过。

### RS-07 · 拒绝/安全失败的AX label误说“附加处理中”

**位置：** `queueHTML`图片button的aria-label。

任何非idle的第一图均被标为“附加处理中”，因此拒绝态、条件safe failure可再次点击态也说处理中。用户看到的原因与AX语义不一致。

**最小修复：** 使用闭集label映射：idle可附加；queued等待附加；prepared附加处理中；rejected未附加/图片保留；safe上传失败/可重新选择（标注条件演示）；视觉吞噬期间按已开始事实描述。编号按钮与图片按钮包含同一资产及同一状态语义。

**验收：** 逐场景读取两个button的accessible name，与视觉消息和可用动作一致；没有网络错误被标作可安全重试。

## 并行修复中已经观察到的更正

初读时renderCapture把“下一张：窗口截图”和“选择窗口”写死；最新VM快照中，全屏切换后误写窗口的检查已经为false，表明作者正在修复。仍建议最终复核：

- selecting阶段切区域/窗口/全屏，立即描述当前选择，而不是“下一张”。
- countdown阶段才有frozenMode/nextMode区分。
- 未确认目标时的日志不声称“已确认区域目标冻结”。

该项不计为当前仍未修复的第八项问题。

## 保留通过的方向

- 左侧审阅事件有明确“模拟”说明；原型不进行网络/系统权限动作。
- 点击缩略图不按时间制造uploadStarted；开始必须由独立事件注入。
- started后UNKNOWN保持隐藏；历史中不提供UNKNOWN恢复重输。
- 独立完成后不添加成功Toast，用户仍在草稿决定是否发送。
- callout与peek已经不接鼠标；移动X盖片本身不改变命中槽。
- safe failure明确写成未来准入条件演示，没有借此开放真实安全重试。
- 使用系统设置/权限的演示没有自动切换真实聊天或发送消息。

## 最终复核建议

只需复核本报告RS-01至RS-07与作者已认领三项，不扩大为新一轮原生全套测试。将最终HTML SHA-256、检查方式和结果追加到此文件即可。原型完成后依然不能替代候选/正式组合的macOS原生验收。

## 冻结版本限定复核 · 2026-10-29

本轮只复核 RS-01 至 RS-07，没有修改 HTML，也没有扩展原生测试范围。实际读取的 HTML SHA-256 与作者提供值一致：

`cbf84113ce5153441726908764e20593c1bed17878f88724d35dd7905d6235d7`

证据分开记录：作者提供的 `prototype-checks.json` 报告真实 Chromium 离线检查 **31 PASS / 0 FAIL**、网络请求 0、页面错误 0；本审查者另做源代码阅读和 Node VM 状态／计时器复现。VM 使用假 DOM，不证明浏览器布局命中。以上均不代表 AppKit、系统权限、真实上传或物理点击通过。

已确认“选择情境固定展示；操作图片后按事件演示”在评审控制区明示。因此仅从左侧选择的固定画面保留说明，不按 2400ms 自灭，作为明确的评审功能接受；下列残留均在点击图片后的实时路径复现。

| 原问题 | 限定复核结果 | 本轮证据 |
| --- | --- | --- |
| RS-01 资产身份 | 核心问题已修复；说明身份的一个分支并入下述 RS-04 残留 | `assets{id,phase,visual}` 保留稳定身份；第 3 图点击并开始后仅 id=2 变为 hidden，其余保持 idle／stable；`hoverAsset` 不修改 `activeAsset`。 |
| RS-02 旧计时器 | 已修复 | 开始→新建独立样本→130ms 后仍为 idle／stable；initialize 同时清 timer、更新 epoch，文案明确新合成样本，不解锁 UNKNOWN。 |
| RS-03 动画与结果竞争 | 已修复 | 开始后分别在 0／40／119／130ms 注入 UNKNOWN 和 complete，8 个序列最终均保留各自业务 phase、visual=hidden；动画尾帧只写视觉状态。 |
| RS-04 说明的时限与身份 | 主路径已修复，尚有两处小分支需要收口 | 无同岛 hover 时 260ms 不显示；同岛 250ms 显示且 2400ms 后消失；prepared 直接赋值与同态 owner 重用仍有下述问题。 |
| RS-05 屏幕变化文案 | 已修复 | 当前为“屏幕布局已变化，请重新选择”，未再声称“本次未拍摄”。 |
| RS-06 透明容器 | 静态修正已确认；作者浏览器证据支持 gap 检查通过 | entry／queue／queue-item 均 `pointer-events:none`，确切图片、编号和模式按钮恢复 auto；callout／peek／盖片仍不命中。这里没有增加 macOS 穿透结论。 |
| RS-07 AX 闭集映射 | 已修复 | 图片和编号均使用 `assetSuffix`；idle／queued／prepared／rejected／safe 的两端 accessible name 一致，与相应状态语义相符。safe 的条件演示说明仍保留。 |

### RS-04 剩余的两个最小修复

**A. prepared 应复用同一个带身份与到期逻辑的说明入口。** `case 'prepared'` 当前直接设置 `state.callout = state.hoverAsset === state.activeAsset`，没有更新 `calloutAsset` 或创建关闭 timer。复现一：idle→指针在图 1→点图 1→立即注入 prepared→3001ms，`fixedReview=false`、`phase=prepared`、`callout=true`；这不是左侧固定画面。复现二：相同流程改为图 2，`activeAsset=1`、`calloutAsset=0`，说明内容仍从图 1 取，故渲染不出 prepared 说明。

最小修复：状态确实属于当前资产后，同岛条件成立时调用统一的 `showCallout(asset.id)`；不成立时只保留状态记号／AX，不主动展示。该入口负责更新说明所属资产和关闭期限。验收只需上述两个序列：第 2 图出现自己的 prepared 说明，说明在 2400ms 内退出，不影响 phase 或上传计时器。

**B. 同一状态的两次说明应有不同的呈现 revision。** `showCallout` 当前 owner 为 `epoch:id:phase`，所以同一 queued 状态的主动再读会沿用 owner，第一次的关闭 timer 可提前关闭第二次说明。复现：首次说明在 250ms 出现，500ms 后离岛并重新显示同态说明，再经过 1901ms，第二次说明被第一个 timer 关闭。

最小修复：每次显示分配递增的 callout revision（或等价唯一 token），关闭只匹配该 revision 和资产身份；也可显式取消上一条纯呈现 timer。不得清除业务或吞噬 timer。验收只需同态再读一次，旧期限不能关闭新说明；新说明依其自己的 2400ms 上限退出。

本快照可确认大多数原问题已解决，但不能将 RS-04 标为全部通过。以上两个分支已经反馈给作者；它们仍仅为原型实现问题，不是原生候选已知缺陷。修复后的限定复核只需更新哈希并重跑这两个序列。

## 最终两项限定复核 · 2026-10-29

**最终结论：上轮 RS-04 剩余的两个分支均已修复。结合前轮限定复核，本审查列出的 RS-01 至 RS-07 已完成修正闭环；没有尚未解决的已列原型问题。** 前文问题及旧哈希结论保留为审阅历史，不代表最终文件仍存在这些问题。本轮严格只重查这两项，没有修改 HTML，没有扩展测试范围。

最终实际读取的 HTML SHA-256：

`4691dca065b25c203533a93d05a76486fad25d6b4e9e927cbbde96e5378826e6`

| 最后两个分支 | 独立限定复核 | 结果 |
| --- | --- | --- |
| prepared 的说明身份与期限 | 源代码确认同岛时统一调用 `showCallout(state.activeAsset)`。Node VM 分别对第 1／2 张执行“实时点击后立即注入 prepared”：`fixedReview=false`，说明绑定各自资产并显示“附加处理中”；2399ms 时仍可见，2400ms 时退出，业务 phase 仍为 prepared。 | PASS（原型状态／计时器） |
| 同态再读的旧 timer 隔离 | 源代码确认每次显示递增 `calloutSequence` 并纳入 owner。Node VM 在同一 queued 状态第二次显示说明：两次 owner 不同；第一次期限过后新说明仍可见；到第二次自己的 2400ms 期限才退出，queued 事实未被修改。 | PASS（原型状态／计时器） |

同时读取最终 `prototype-checks.json`：作者的 Chromium 离线检查记录为 **33 PASS／0 FAIL**，网络请求 0，页面错误 0，`sourceSHA256` 与上述最终文件一致，其中包含本轮两个分支的浏览器检查。本审查者的独立复核依旧是源代码与假 DOM 的 Node VM 状态执行；没有将作者浏览器记录混写为本审查者独立完成的浏览器命中测试。

**证据边界不变：这份最终结论仅关闭已列出的 HTML 设计原型问题，不是 AppKit、系统权限、真实上传、物理输入、Spaces 或多显示器验收通过。** 固定情境展示继续作为明确标示的评审功能；原生实施仍须等待正式集成完成并按 `STATE_TRANSITIONS.md` 的相应验收执行。
