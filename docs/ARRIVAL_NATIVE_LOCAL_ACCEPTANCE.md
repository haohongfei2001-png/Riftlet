# 双模式原生动效：受控集成与本地 Mac 验收

本页交给正式工程负责人和本地 Codex。正式模式只允许 `none`（无）和 `magnet`（磁力吸引）。默认选择尚未获得用户最终批准；工程中的 `none` 只是保守回退。本文的操作不授权改写上传适配器、生产准入、安全失败／重试准入、SQLite 版本或既有 UNKNOWN。

## 1. 集成身份与工作树隔离

本动效分支以实际核对的 PR #1 工程 HEAD `1920e0562db893a3292af89a89270a26ddb46a5f` 为基线；正式设计依据为 PR #10 的 `0b73291652c11f5cb7b6e2792d001eb3340c988b`。准确动效交付提交和 CI 固定在本分支 Draft PR；集成时重新读取远端，不能把本页的起点当作永远最新的正式 HEAD。

**源坐标生产准入保持关闭。** `ArrivalSourceProfile.admittedOSBuilds` 当前为空，因为本轮没有在真实 macOS 截图上验证该未公开元数据的坐标契约。普通启动即使保存了“磁力吸引”，来源未经验证时仍立即静态呈现；设置预览和可测试的原生运动实现不等于真实截图坐标已经获准。这个范围限制必须随交付保留。

由唯一正式负责人在**新的**工作树中组合，不覆盖正在运行的真机工程、App 或数据目录。下列命令中的分支名均为本次实际工作分支；如果远端已继续推进，保留新的 HEAD 并阅读其差异。

```bash
git fetch origin
git log -1 --format='%H %s' origin/codex/engineering-foundation-20261027
git log -1 --format='%H %s' origin/codex/arrival-none-magnet-native-20261028
git merge-base origin/codex/engineering-foundation-20261027 origin/codex/arrival-none-magnet-native-20261028
git diff --stat origin/codex/engineering-foundation-20261027...origin/codex/arrival-none-magnet-native-20261028
git worktree add -b integration/arrival-native-local ../Riftlet-arrival-integration origin/codex/engineering-foundation-20261027
cd ../Riftlet-arrival-integration
git merge --no-ff --no-commit origin/codex/arrival-none-magnet-native-20261028
```

这是供负责人执行的组合步骤，不表示本交付已经修改 PR #1 或已经合并 main。处理冲突时逐块保留原选择 owner、visibilityRevision、原事件时间／ACK、Feedback hooks、截图收录 epoch 和观察恢复；不要整文件覆盖。先完成以下适用验证，再提交组合并由正式负责人更新正式分支。

另一个并行分支 `codex/predictive-capture-entry-20261028` 在本次读取时修改了 `RiftPanelController`、`RiftletMain` 和 Capture 接口。此处不合入该分支。若负责人后续已将其纳入工程，重点处理：

- `captureSuppressed` 变为 true 时，立即取消源端装饰，不仅隐藏原来的行窗口；解除抑制不回放先前飞行。
- capture header 改变队列位置时，用**新布局实际行的全局 imageFrame／clipFrame**构建目标；不要重新猜屏幕右缘或固定 y。
- `setCaptureHeaderAnchor`、显示器重排、隐藏、关闭和 Space 切换均走统一取消／清理；不能让旧完成回调恢复临时窗口。
- 保留 `onGeometryChange`、截图会话状态及原输入岛。临时动效窗口不得成为 screenshot entry 的输入窗口或改变系统快捷键。
- 该分支自己的 Core／ReceiptPolicy 修改另行审查；动效不需要、也不授予那些权限。

## 2. 构建和软件回归

在有完整 Xcode 命令行工具和 WindowServer 的 Mac 执行，并记录实际 SHA、`sw_vers`、`swift --version`、CPU 架构和显示器拓扑。CI 的软件 AppKit 测试不等于物理鼠标、系统截图或真实浏览器验收。

```bash
git status --short
git rev-parse HEAD
sw_vers
swift --version
uname -m
mkdir -p test-results
set -o pipefail
swift test --parallel 2>&1 | tee test-results/arrival-native-swift.log
swift test --skip-build --filter 'Arrival|Magnet|ScreenshotSource' 2>&1 | tee test-results/arrival-native-targeted.log
swift test --skip-build --filter 'RiftLifecycleTests|RiftInputIslandTests|PresentationBoundaryTests|RiftReconfigurationTests|AcceptedSelectionQueueTests|SelectionAuthorityTests|SelectionSubmissionQueueTests|SystemScreenshotCandidateIntegrationTests' 2>&1 | tee test-results/arrival-native-existing-lifecycle.log
bash scripts/build-macos.sh 2>&1 | tee test-results/arrival-native-build.log
python3 -B -m unittest discover -s Tests/ArrivalIsolation -v 2>&1 | tee test-results/arrival-native-isolation-tests.log
python3 -B scripts/verify-arrival-integration.py origin/codex/arrival-none-magnet-native-20261028 2>&1 | tee test-results/arrival-native-composition.log
```

最后一条固定对象审计验证的是**已提交的动效交付 revision**，不是尚未提交的组合工作树。它先执行基线中原始 42 项审计，再检查完整候选树的精确文件范围；最终还锁定已审查源代码、测试、两个 CI workflow 和只读 probe 的对象。若仍在 `--no-commit` 合并阶段，`git rev-parse HEAD` 只是正式起点，必须同时记录 `git diff --cached --stat`、冲突解决内容和待提交树身份；组合提交后重新记录真正构建 SHA。正式基线若继续推进，组合结果应有新的受控集成审计，不能把该增量审计对新基线的预期拒绝改写成豁免。

验收日志必须区分：实际执行 passed、failed、XCTSkip 和未运行。正则筛选后必须核对列出的用例，不能把“0 tests”或全套发现行当作通过。所有详细复跑属于全量用例集合，不重复累加数量。若合并时存在新增固定对象审计，更新其明确批准的文件／祖先与专用隔离用例，不能禁用审计或豁免整个目录。

### 在候选模式验证真实截图动效

设置入口为菜单 **“截图动效…”**，只显示 **“无”／“磁力吸引”**；选择成功保存后立即应用，并可在同一窗口原生预览。设置保存在既有 App 数据根的 `arrival-motion-settings.json`，不进入队列数据库。不要直接编辑生产设置来绕过验证。

本次两模式均即时补位，不对原生输入窗口执行滑行动画。这避免吞噬后已有输入窗口继续移动或因动画未结束拒绝下一次点击。磁力模式保留独立源端飞行和证据触发的短吞噬；“无”同时取消按压、吞噬和重生装饰位移。

本地坐标试验显式使用下面的**工程候选参数**，仍保持用户原系统截图快捷键。它只开放几何候选解释，不改变 App 运行模式或上传权限。

```bash
./build/Riftlet.app/Contents/MacOS/Riftlet --arrival-metadata-candidate
```

先使用该普通收录模式检查收录、外观与立即可点击场景；在菜单选择“磁力吸引”。AM-06 的回执驱动吞噬及 AM-07 的失败／UNKNOWN 状态使用现成的隔离合成测试；实际上传另按 AM-16 执行。保持显示器／Space 稳定至少两秒后拍摄一张全新截图；其它安全条件仍可能静态降级。`--arrival-metadata-candidate` 不保证每种截图都能播放，也不是最终默认款。完成逐类型、坐标与像素验证后，由正式负责人审查证据，再为精确 OS build 增加来源准入；不要直接改成“所有版本允许”。

上述两秒拓扑静默期和新近 `firstSeen` 都只是保守启发式，**不能证明截图发生时使用的显示器拓扑**。正在进行的截图、系统浮动缩略图或文件延迟落盘可能跨越显示器变化，并在静默期之后被当作新文件收录；元数据没有独立观察到的截图时钟来消除这种歧义。OS build 准入之前必须完成 AM-18，并审查捕获时的真实拓扑证据；当前显示器与矩形／像素一致不能单独代替这项验证。无法确认来源对应关系的样本保持静态降级。

只有 AM-16 的独立真实上传检查需要既有 `--system-screenshot-candidate`。在原允许范围内，单次启动可同时传入 `--arrival-metadata-candidate`；需要保管私有证据时再显式加入原 `--acceptance-trace`。这些参数不能提升 UNKNOWN、安全失败或重试权限。

测量本次新增阶段时，使用 `--arrival-trace`。它记录有类型的本地 JSON 事件：`captureDurableObserved`、`rowAvailable`、`imageDecoded`、`decorationStarted`、`decorationEnded`，通过资产身份与单调 uptime 关联；不含截图、源路径或文件名。`captureDurableObserved` 是收到已提交资产的观察时刻，仍不是精确 COMMIT 或系统截图完成时刻。`rowAvailable` 证明软件输入结构建立，不证明硬件物理点击已经通过。此 trace 与原上传证据 trace 分开解释。

```bash
./build/Riftlet.app/Contents/MacOS/Riftlet --arrival-metadata-candidate --arrival-trace
```

## 3. 验收矩阵

初始状态全部为 **NOT_RUN（本地物理验收）**。执行者在私有验收记录逐项填入结果、精确构建 SHA、证据路径、屏幕与截图类型。软件夹具可单独标 `SOFTWARE_PASS`；不得覆盖物理列。

| ID | 实际操作 | 必须观察的结果 | 尚未执行时 |
| --- | --- | --- | --- |
| AM-01 | 选“无”，区域／窗口／全屏各截图一次 | 收录完成后的图立即在最终队列位置；无源副本、入场淡入、按压位移、吞噬位移、补位滑动或重生位移 | NOT_RUN |
| AM-02 | 选“磁力吸引”，从同一显示器取得可信源矩形 | 小图清晰、方向性轻颤、连续加速与固定直边遮挡；源／目标尺寸及轨迹连续，无回弹、闪光或粒子 | NOT_RUN |
| AM-03 | 在飞行开始后立即点击原行图片，再在另一新图飞行中点击编号 | 原 assetID 当次被选择；装饰立即清理，原选择时刻／目标规则不变，无强制等动画的时间门 | NOT_RUN |
| AM-04 | 磁力飞行时点击其途经的其他 App 区域 | 点击只到下层 App，Riftlet 不激活、不抢键盘焦点、不代发合成输入 | NOT_RUN |
| AM-05 | 连续 3 张，再连续至少 12 张；其间快速点击 | 同时最多一张源端装饰；所有截图仍按实际 FIFO 收录；取消旧飞行不丢图、不改顺序、不重复选择 | NOT_RUN |
| AM-06 | 第一张有真实开始后立即点击补位区域；另测一次双击 | 快吞噬仍由原 `uploadStarted` 证据触发；既有双击后半段／替换行保护不退化 | NOT_RUN |
| AM-07 | 在隔离 synthetic 场景触发已证明安全的失败与 UNKNOWN | 失败恢复**同一 assetID**并可再次点击；UNKNOWN 不因动画完成重生或获得重试资格 | NOT_RUN |
| AM-08 | 磁力播放中切换“无”，退出 App，重启，再切回 | 即刻取消装饰、最终几何准确；设置持久化；重启不回放旧截图动画 | NOT_RUN |
| AM-09 | 开启 macOS Reduce Motion；中途改变此系统设置 | 实际展示遵循“无”；用户保存的磁力选择不被覆盖；关闭 Reduce Motion 后只对未来可信新图恢复 | NOT_RUN |
| AM-10 | 缺源元数据、单值／畸形／越界矩形、像素与比例不一致 | 即刻静态落位；不猜鼠标、窗口或默认中心；收录和点击照常 | NOT_RUN |
| AM-11 | 1×、2×、混合缩放；左右／上下／负坐标多屏；跨屏区域 | 同屏可信转换可审查；不安全跨屏自动静态；无截图源来自错误显示器的飞行 | NOT_RUN |
| AM-12 | 播放中切换 Space、进入全屏、拔掉显示器、改变排列／缩放 | 临时图层／窗口清除；旧完成回调不再显示；现有队列安全重排，原点击身份保护不变 | NOT_RUN |
| AM-13 | 播放时 Hide／重新显示、滚动队列、改变布局参数 | 原装饰取消；不补演陈旧飞行；隐藏意图和正常最终行保持 | NOT_RUN |
| AM-14 | 播放时再次用原 macOS 快捷键截图 | 记录是否把动效浮层截入下一张；不得以 `.sharingType = .none` 推定排除成功 | NOT_RUN |
| AM-15 | 经明确同意关闭系统浮动缩略图后，各截图类型至少 10 次 | 分阶段实测就绪时延与失败／缺元数据率；不宣称“近零”或借用单张最佳值 | NOT_RUN |
| AM-16 | 新系统截图一次实际 ChatGPT 附加，另保留无 ACK 冷首击拒绝 | 上传原一次 input、独立 start／final、正文／选区／旧附件不变；动效零等待不冒充网络零等待 | NOT_RUN |
| AM-17 | 至少 100 次新图＋取消／隐藏／模式切换循环并留空闲期 | 临时窗口和图层回到基线、无后台帧循环；记录 CPU／内存／帧间隔而非凭观感写性能 PASS | NOT_RUN |
| AM-18 | 截图正在进行或已经捕获但文件尚未就绪时改变显示器排列／缩放／连接；系统浮动缩略图开、关分别执行，并包含落盘晚于两秒静默期的样本 | 关联实际捕获时的拓扑与原始元数据；来源对应关系不明时静态降级；不得以新近 `firstSeen` 或静默期推定来源正确；此项为 OS build 准入前置检查 | NOT_RUN |

失败／重生和 UNKNOWN 的软件检查不打开真实安全失败／重试准入。真实异常若证据不足，保持 UNKNOWN 并只读观察原操作；不得为演示重生改库、注入真实成功或重传已经输入的图。

## 4. 文件就绪与端到端时延：测量定义

当前基线的文件监听器是**首事件约 60 ms 的有界合并**；CaptureService 要求相同文件签名稳定至少 **120 ms**，首次重试间隔 **150 ms**，后续为 **350／800／2000／5000 ms**。这些是源码配置，不是测得的系统截图时延。接下来仍有实际图片验证、原字节复制与 SHA-256、fsync、SQLite 收录、MainActor 刷新和有界缩略图解码。某轮扫描可批量收录；不要把“函数返回”当作精确数据库 COMMIT 或可见帧时间。

为同一次**新截图**记录以下时钟，并明确所用观察方法和误差：

| 边界 | 定义 | 不可替代为 |
| --- | --- | --- |
| T0 | 系统截图完成操作的实际边界；区域选择松开／窗口确认／全屏快捷键，分别注明 | App 首次看见文件的时刻 |
| T1 | 实际截图目录的第一次文件事件／文件首次可见 | 文件名中的墙钟时间 |
| T2 | 文件字节及需要的截图元数据完成、读取验证通过 | 浮动缩略图消失或单次 stat 成功 |
| T3 | 本资产收录提交被原队列观察到 | 动画开始或模拟定时器回调 |
| T4 | 原行输入窗口已具有正常交互资格 | 动画结束 |
| T5 | 源端装饰实际首帧；没有播放则记录降级原因 | T0 或捕获事件 |
| T6 | 装饰结束／取消且临时资源清理 | 上传成功 |

只用同一单调时钟比较间隔；若某个系统边界只能由录像确定，报告录像帧率／误差，不与另一时钟无校准相减。`T4−T3` 是需要防止被动画增加的等待，`T3−T0` 是截图收录链耗时，`T6−T5` 是装饰时间。真实点击→input→严格 start→视觉关闭→final 另沿用现有 `--acceptance-trace` 语义，不改证据名称或 READY 判据。

至少分别报告区域／窗口／全屏、单屏／多屏、系统浮动缩略图开／关的样本数、median、P95、最大值、缺失元数据率及降级原因。截图窗口阴影可能使像素包络与源矩形不一致；保守静态是合法结果，不以宽松容差“提高成功率”。源元数据缺失不能推迟已经可用的截图。

系统设置只由用户明确同意后通过系统 Screenshot 的 Options 切换。保持原 macOS 快捷键；不执行 `defaults write`、不杀系统进程、不读取／写入用户不相关偏好。记录原值及最终值，是否恢复由本次授权范围决定。

### 原生元数据探针

只读探针和坐标解释见 [ARRIVAL_SOURCE_GEOMETRY.md](ARRIVAL_SOURCE_GEOMETRY.md)。它不截图、不拦截快捷键、不改系统设置，输出不包含图像、文件路径或窗口标题。它读取的是**原系统截图文件**，不能用缺少原扩展属性的私有字节副本替代。

```bash
swift scripts/arrival-source-probe.swift --file '/absolute/path/to/new-system-screenshot.png'
swift scripts/arrival-source-probe.swift --watch '/absolute/path/to/actual-screenshot-directory' --seconds 30
```

以上两个路径由本地操作者替换为实际新截图／实际目录；输出留在私有环境。`--watch` 是最长 120 秒的诊断采样，默认 30 秒，不是产品收录器。请求轮询间隔 20 ms 不是上界：实际调度、扫描和解码可能更慢，报告使用实际前后采样时钟。探针首次看见文件至完整读取的差值不包含未观察到的系统截图前段，也不包含产品稳定性检查、私有复制、数据库和交互窗口；不能以它宣传总延迟。

四个有限数字及像素／显示器一致性只支持保守候选判断。该扩展属性没有公开的 Apple 稳定契约；必须在实际 OS、截图类型和显示器配置上将原始矩形与真实捕获区域对照。缺失、旧版单值、未知类型、窗口阴影不一致、镜像屏、歧义／跨屏或陈旧来源均按静态降级记录，不伪造来源位置。

## 5. 实际上传、私有数据和证据边界

普通启动仍只收录；显式 `--system-screenshot-candidate` 沿用既有受限能力与原候选数据根。不建立一个“干净数据根”绕过旧 UNKNOWN 或目标锁，不重传 H、F、A、D，也不重导入旧图来凑样本。真实试验只使用愿意附加的另一张全新截图与原规则允许的目标；不自动发送消息。

旧 H 的软件 CGEvent 快吞噬和既有 CI 是继承的限定证据，不是本次磁力／无模式的新物理验收。新记录必须包含本次精确提交，不能把浏览器 Canvas 原型、截图脚本、CA 采样或 NSWindow 属性检查称为实际桌面像素和输入通过。

公开材料只放去隐私的结论、代码身份、数值和必要的测试图案。真实截图、目录路径、完整会话／目标、私有 SQLite／WAL、聊天正文及原 trace 留在用户私有环境。不要为了保存验收而上传这些内容到公共仓库。

## 6. 通过与交接

软件通过与物理通过分别列出。只要有一项未执行，就保留其 `NOT_RUN`，并写明剩余设备／权限／场景和直接续做步骤。没有实际 frame、focus、click 或系统截图证据时，交付结论只能是“原生实现与软件验证已完成，物理品质验收待执行”，不能是成熟产品整体验收通过。

本文件不改变当前正式候选支持范围、生产禁用状态、独立上传证据、安全重试限制或其它已确认的视觉／运行缺陷。
