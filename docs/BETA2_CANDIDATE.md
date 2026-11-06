# Beta 2 原生设置候选

本轮把已保存的 V2 设置设计接入同一 Riftlet 原生产品：六页设置、菜单栏控制中心与三步引导已经有实际 AppKit 实现和真实 owner 接线。当前交付阶段是**独立候选审核**，不是已安装 Beta 1 的替换，也不是公开发行。重大 UI PR 合并与普通数据根升级仍等待本轮最终外观决定；这不阻止工程侧完成回归、独立审查、候选打包和隔离验收。

范围与来源见 [本轮交接](../engineering/beta2-product-20261106/HANDOFF.md)、[状态记录](../engineering/beta2-product-20261106/STATUS.md)、[原生验收矩阵](../engineering/beta2-product-20261106/NATIVE-ACCEPTANCE-MATRIX.md)。这些记录保留中间失败；最终结果必须绑定下表的同一源码与工件，不能把旧原型浏览器测试或中间版截图当作最终候选通过。

## 最终交付身份

`PENDING` 是尚未完成或尚未填入经过复核的结果，不代表通过。源码 `Resources/Info.plist` 已分配版本身份 **Beta 2 · 0.2.0（2）**；最终产物文件名与哈希仍待核对。

最终 G / tree、直接 H、正式 PR 链接和 App / ZIP 身份由仓库外的私有 `final-manifest` 与正式 PR 交付记录绑定。本文件属于源码的一部分，不预填自身将来提交的 SHA；下表缺项由该交付记录收口。

| 项目 | 最终值 / 状态 |
| --- | --- |
| 完整源码 G / tree、非作者独立审查 | PENDING；以私有 final-manifest 和正式 PR 交付记录为准 |
| 直接 admission-only 子提交 H、实际 PR checkout / base | PENDING |
| 五项正式 CI | PENDING：Native source admission、Native ARM64、Native Intel、Feedback source admission、Feedback native and service |
| 候选 version / build、实际架构 | 已分配 Beta 2 · 0.2.0（2）；最终架构 PENDING；macOS 13 是部署下限声明，不是已完成最低系统验收 |
| App 路径、可执行文件 SHA-256、内含资源核对 | PENDING |
| ZIP 路径 / SHA-256、独立身份清单 | PENDING；不把 App hash 当成 ZIP hash |
| 精确候选原生报告、截图清单、恢复结果 | PENDING；逐项依据验收矩阵判定 |
| Developer ID / 公证 / staple / Gatekeeper | 本轮最终候选尚无完成证据，NOT_RUN / PENDING |
| 最终外观决定、正式 UI PR 合并、生产原位替换 | PENDING；不能由本表或构建工具自动批准 |
| 已安装 Beta 1 与回退保留位置 / 身份 | 保持现状；实际路径、完整 App 及清单由最终升级记录补齐 |

## 已取得的原生证据与待复验项

首轮运行 `run01` 绑定源码 `45418bba9fb05e5c2649473c8c1f26a460fb54c5`。真实 AppKit 控件、既有 owner、文件和 SQLite 共 13 组功能检查通过，独立根有 3 张 fixture 图片、0 个附件操作、0 个 upload start，恢复失败列表为空。设置首次展示实际内容为 960×684 pt，六页浅/深原图未发现横向裁字。可分享的原始绑定见 [run01 证据](../engineering/beta2-product-20261106/evidence/native-run-01.json)。

这次运行仍是 **PARTIAL_NATIVE_REVIEW / INCOMPLETE_TIMEOUT**：33 张预期窗口图只取得 30 张，`control-light`、`control-normal`、`control-paused-hidden` 明确为 `NOT_RUN`；报告生成后进程未正常退出，180 秒期限后 runner 只终止了其子进程。功能组通过没有覆盖这两个缺口。原报告、原图与超时结果全部保留。

独立目视审查发现四项局部差异：控制中心说明过窄换行、布局说明压到左中示意卡、六位置当前选中不明显、引导初次窗口宽度不足。修复候选已分别调整说明列可用宽度、把布局说明移到画布外、加入勾选与强调色、在约束建立后恢复引导初始尺寸。原发现继续保留，各项修复按之后的原图与结果分别复核。

退出生命周期也已形成修复候选：先询问设置草稿，保存失败保留原面板，继续编辑取消退出；设置获准关闭后，在 Feedback 异步清理期间阻止新设置命令和窗口，取消退出再恢复。原 AppKit 退出探针复现了旧路径挂起，修改后的独立探针正常结束。

[run02](../engineering/beta2-product-20261106/evidence/native-run-02.json) 对应 `bc903f7`：完整进程 20.16 秒正常退出，功能 12/13 通过，唯一失败为 `onboardingOuterSizeMismatch`。27 个 PNG 文件中，7 张控制中心图被独立审查判定裁切/黑色或透明空区，不能作为布局通过证据；引导在尺寸断言失败后没有取得新图。布局说明与六位置勾选在这一二进制的浅/深/紧凑图中已获独立目视确认，另外两项仍需复验。因首轮功能失败，同包重启阶段正确保持 `NOT_RUN`。

同一运行二进制的 [额外 CUA 原生记录](../engineering/beta2-product-20261106/evidence/cua-native-bc903f7.json) 单独证明 Return 推进引导、明确选右下、⌘, 打开设置、键入 6.25、⌘Q 后继续编辑保留草稿，以及再次 ⌘Q 应用后退出并读回 22500 秒归档值。同时保留 ⌘W 无 Close 菜单而未响应、引导尺寸仍不符这两项失败。

[run03](../engineering/beta2-product-20261106/evidence/native-run-03.json) 对应 `ea312a6`，进程 14.99 秒正常退出，引导功能及六张浅/深窗口的 652×608 pt 外框已得到实际记录。本轮仍为 12/13 功能通过：暂停/隐藏序列在 driver 提前点击暂时禁用的控件时失败；控制中心捕获虽然已采用正确范围，部分帧还处于出现缩放阶段，尚不足以验证完整布局。原失败、29 张原图哈希与不同的 WindowServer/AppKit 尺寸均保留。随后 driver 增加实际可用与完整稳定窗口等待，结果继续按下列新运行单独记录。

`ea312a6` 的 [单独 CUA 键盘记录](../engineering/beta2-product-20261106/evidence/cua-native-ea312a6.json) 已在**先独立观察到草稿存在**后，证实 ⌘W 打开原生关闭面板、继续编辑保留草稿；随后 ⌘Q 选择不保存，进程退出且已确认的 24 小时归档值仍为 86400 秒。快速连批预设点击后立刻 ⌘W 因未先确认草稿而保留 `INCONCLUSIVE`；失效 AX 索引和一次审计预期纠正也单列，不追加为产品失败或通过。当前不声明 `PRODUCT_READY`，已安装 Beta 1 保持不变。

[run04](../engineering/beta2-product-20261106/evidence/native-run-04.json) 对应 `4174a04`，进程 29.65 秒正常退出，功能 11 PASS / 2 FAIL；六页浅深与暂停/隐藏两个完整 case 均在控制中心打开路径超时。25 条窗口记录中有 23 个实际 PNG 和 2 个 `NOT_RUN`。独立审查确认 `control-normal`、`control-paused`、`control-save-failure` 三张完整原图的说明宽度和捕获范围已改善；这个局部视觉结论不覆盖缺失的深色、仅隐藏、暂停且隐藏正常状态图，也不改变整轮 FAIL。

[run05](../engineering/beta2-product-20261106/evidence/native-run-05.json) 对应 `64ac68b`，磁盘报告已完成，功能为 9 PASS / 4 FAIL，22 条窗口记录中有 19 个 PNG 和 3 个 `NOT_RUN`。runner 仍是 180 秒超时、exit -15、`INCOMPLETE`；SIGTERM 后空日志没有 stdout 报告路径，实际报告从同一 review 根读取，并核对了相同进程身份与可执行文件，不能补成 runner 已返回报告。集成侧观察到失败保存 case 遗留草稿，退出正在等待原生确认；这不构成无草稿正常退出倒退的证据。

run05 的通知时序与源码指向控制中心额外的 `didResignActive` 无条件关闭路径：状态栏展示后发生原生激活交回时，它会与既有 transient 关闭机制重叠。独立审查只批准移除该 observer 并保留既有关闭路径、添加窄回归；通知先后不是调用栈，仍需 `run06` 实际复验。当前不新增产品焦点门槛，不把修复计划写成通过；完整功能、稳定状态图、正常退出和同包同根新进程重启均待新结果。

## 已实现的界面与状态边界

| 原生表面 | 本轮实现 |
| --- | --- |
| 通用 | 暂停收录、隐藏裂缝、登录启动、外观；相关开关使用原生 switch，暂停为 `true` 就是暂停、隐藏为 `true` 就是隐藏。运行状态与保存结果分开显示 |
| 位置与显示 | 具体显示器身份、临时回退说明、左右两列六点位置、基本 / 详细 / 精细参数；兼容字段保留，不因本页恢复默认被清掉 |
| 截图 | 系统截图习惯、实际来源位置与访问入口、独立内置入口开关、下一次截图的默认方式；屏幕录制只对应内置截图 |
| 动效 | 原有入缝偏好、主动绘制示意预览、按毫秒编辑有效参数；选择偏好不自动播放，减少动态不延长原本更短的时长 |
| 历史与存储 | 原有真实历史入口、归档预设与小数小时草稿、实际存储测量；收起全部由 Main 统一确认，不删除原图、本地历史或聊天附件 |
| 权限与帮助 | 来源访问、Chrome 自动化、Chrome JavaScript 选项、内置截图录屏权限分开说明；现有反馈、引导、配置入口和实际版本信息 |
| 菜单栏 | 原生 `NSPopover` 与右键 `NSMenu`，共用快照和命令；暂停、隐藏、可截图能力与保存异常各自投影 |
| 三步引导 | 认识产品、连接工具、选择位置；可稍后完成，沿用已有首次展示键，不把完成引导当成授权或截图成功 |

快照来自 `SettingsProductHost` 与既有持久化 owners。有效状态、参数原始文本草稿、已确认值、待重试意图分开维护；独立域保存成功不会清除另一域错误。重试保存原目标，不通过反转开关猜测意图。布局和动效参数共用配置草稿，归档独立提交；部分成功后不重复写已经成功的域。

后台更新保留六页控件实例、编辑文本与 field editor；显式恢复默认/放弃才结束或取消对应编辑。用户关闭或退出时有草稿，会显示“继续编辑 / 不保存 / 应用并关闭”，默认继续编辑。保存失败保留同一个面板；迟到保存回执不能把已取消的退出重新批准。原生 marked-text 对象测试与真正系统中文输入法验收是不同证据。外观只影响 Riftlet；登录状态回读自系统，`requiresApproval` 明确仍在等待批准，系统异常与实际状态并存。

## 隔离审核入口

使用**同一个候选 App 二进制**的显式 review 参数，不另装一个竞争产品。以下路径是占位符，须替换为最终记录中已核验的候选；不得省略 `--settings-review` 后直接双击候选进入普通根。

```sh
RIFTLET_CANDIDATE_APP='/absolute/path/to/verified/Riftlet.app'
RIFTLET_REVIEW_ID="$(uuidgen)"
"$RIFTLET_CANDIDATE_APP/Contents/MacOS/Riftlet" --settings-review "$RIFTLET_REVIEW_ID"
```

入口要求恰好一个有效 UUID，不能与模拟、Web 验收或系统截图候选模式并用。它在当前用户 Application Support 下建立 `Riftlet-Settings-Review-<小写 UUID>`，使用独立 defaults suite、身份 marker、应用独占锁和 `fixture-source`。已存在的非本次身份目录或符号链接会被拒绝；只有赢得应用锁后才准备 fixture 配置。缺失来源配置仅回退本 fixture 目录，损坏配置报错，不改用真实 Desktop。

该环境运行真实设置 owners、SQLite、历史与文件收录，但来源仅是独立 fixture。Web adapter 与附件观察关闭；Feedback 使用禁用 transport 和内存 secret；系统截图抓取、系统权限请求与真实登录项注册不可执行。它不会借用普通 Beta 1 的图片、UNKNOWN、操作记录或反馈凭据。可以与普通根进程并存，但同一个 review UUID 只允许一个实例。

显式自动原生验收使用现有 driver；它会操作自己的原生窗口、写入独立测试偏好、制造并恢复受控写失败、绘制合成图片。它会占用本轮审核窗口，应合并执行，不在用户正常工作中反复启动：

```sh
"$RIFTLET_CANDIDATE_APP/Contents/MacOS/Riftlet" \
  --settings-review "$RIFTLET_REVIEW_ID" --settings-review-run
```

driver 写入位于该 review 根 `evidence/run-<UUID>/report.json` 的报告，并打印 `RIFTLET_SETTINGS_REVIEW_REPORT=<实际路径>`；Main 随后请求正常退出，失败后仍有草稿时可能等待关闭确认。stdout 在异常终止时可能未刷新，实际文件与进程身份核对须单独记录，不能把找到文件等同于进程正常退出。保存完整报告、每个 case 的状态、原始窗口 PNG 与哈希、恢复失败列表。合成 collector 输入带明确测试标记，不是真实系统截图验收。`PASS_SCOPED_NATIVE_REVIEW` 只覆盖报告内实际执行的 native action / SQLite 场景；缺图、物理鼠标、OS IME、VoiceOver、多屏热拔、真实登录项等不能借用这个总状态。

完整候选验收使用 [原生 runner](SETTINGS_REVIEW_DRIVER.md)：

```sh
sh scripts/run-settings-review.sh "$RIFTLET_CANDIDATE_APP" \
  '/absolute/existing-private-parent/new-native-review-output'
```

runner 创建新 UUID，只在首次完整运行成功并正常退出后，使用**同一 App、同一 UUID 根、不同进程**做只读重启核对。报告通过、进程退出和重启数据相等分别判定；首次失败不会通过第二次启动掩盖。实际结果仍须绑定本轮最终候选。

## 候选构建与包核对

在最终已审查的干净源码检出目录执行既有开发包流程：

```sh
./scripts/build-macos.sh
python3 -B scripts/verify-app-bundle.py build/Riftlet.app \
  --repository . --channel development
codesign --verify --strict build/Riftlet.app
shasum -a 256 build/Riftlet.app/Contents/MacOS/Riftlet
```

`build/Riftlet.app` 是脚本规定的输出位置，不表示本文件发布时那里已经有最终候选。脚本编译、校验资源与普通早退身份，并做 ad-hoc 签名；只替换生成的 build 输出，不安装到 Applications。首次审核时记录实际源 SHA、tree、架构、App / 资源 / ZIP 身份，不把工作树未提交字节或测试 runner 的旧 App 混入候选。

正式发行准备工具从明确完整的源码 SHA 导出到**全新** workspace；本轮使用已分配的版本/build：

```sh
python3 -B scripts/release-tool.py build \
  --source '<reviewed-full-40-character-commit>' \
  --version 0.2.0 --build 2 \
  --arch arm64 --workspace '/absolute/new/release-workspace'
```

这只产生 `PREPARED`，不会自动 Developer ID 签名、上传或安装。需要 Intel 时按真实范围追加 `--arch x86_64`；真正双 slice 也不等于两种机器都实测。`release-tool.py package` **要求 STAPLED**，不能用它把 ad-hoc 私人候选冒充公证分发包。若本轮交付私人 ad-hoc ZIP，记录实际打包方式与独立 hash，身份字段仍如实标明未 Developer ID 签名、未公证；不要借用历史包名或改写历史证据。

## 最后审核、备份与标准升级

此流程仅在最终外观决定与具体升级授权成立后执行。当前候选审核不替换已安装 Beta 1。

1. 先完成同一 G / H 的独立审查、实际 PR checkout 与五项 CI，核对包来源、架构、资源、运行报告和已知未验收项。标准两父提交合并后再核对实际 main tree 与 main-push CI；遵守 [主线治理](MAINLINE_GOVERNANCE.md)，不直接推 main 或用构建通过代替源码审查。
2. 保留 Beta 1 的完整 App、已有原始 ZIP 与身份清单到新的私有位置；不改名混用为 Beta 2。通过**已核对路径的旧 App 自身“退出”菜单**正常结束。用 `ps -p <已核对 PID> -o pid=,command=` 检查确切进程是否仍在；不要用 `killall Riftlet` 杀掉另一审核实例。存储工具不停止进程，被占用的锁会明确拒绝备份。
3. 旧 App 及 sidecar 停止后，对实际普通根做健康检查、完整备份与外部摘要复核。下面源与目标均为占位符，目标父目录需已存在、目标本身需不存在：

```sh
python3 -B scripts/storage-recovery.py health \
  --source '/absolute/path/to/offline-ordinary-root'
python3 -B scripts/storage-recovery.py backup \
  --source '/absolute/path/to/offline-ordinary-root' \
  --destination '/absolute/existing-private-parent/new-backup'
python3 -B scripts/storage-recovery.py verify \
  --source '/absolute/existing-private-parent/new-backup' \
  --expected-manifest-sha256 '<manifestSHA256-returned-by-backup>'
```

备份保留 DB 及仍存在的 WAL/SHM/journal、全部媒体、配置与 Feedback 数据。退出码 `2` 是健康状态需要处理，不是全绿；`1` 是拒绝或未完成。不能使用 `--detached-source` 绕过运行中普通根锁。UserDefaults / 来源书签、Keychain、TCC、Chrome 设置和系统原截图在目录备份之外；保持原状，另行记录实际覆盖范围，不导出私钥或反馈 secret。

4. 在新解包目录核验候选后才进行标准 App 替换。对**真正 STAPLED 的发行包**，使用可信的独立 ZIP / manifest pin 与团队：

```sh
python3 -B scripts/release-tool.py verify-archive \
  --archive '/absolute/path/to/final.zip' --sha256 '<trusted-zip-sha256>'
python3 -B scripts/release-tool.py verify \
  --package '/absolute/new/extracted/Riftlet-Release' \
  --manifest-sha256 '<trusted-manifest-sha256>' --team '<trusted-team-id>'
python3 -B scripts/release-tool.py update-plan \
  --package '/absolute/new/extracted/Riftlet-Release' \
  --manifest-sha256 '<trusted-manifest-sha256>' --team '<trusted-team-id>' \
  --current-app '/absolute/path/to/installed/Riftlet.app'
```

`update-plan` 只读并返回计划，不替换 App，不证明数据兼容，也不适用于无 Developer ID / staple 的 ad-hoc Beta。私人候选使用其实际 App/资源/ZIP 清单与标准开发包 verifier；不得为获得 update-plan 成功伪造 team 或阶段。经最终批准后由安装流程/Finder替换 App，再启动**唯一**普通实例；不让新旧 App 同时进入同一根。

5. 升级后核对原媒体、历史、UNKNOWN、配置与 Feedback 记录，实际启动、退出及恢复路径。不能以清队列、重置偏好、删除锁文件或重发图片解决升级问题。这里没有自动更新器，也没有“文件复制成功即升级成功”的结论。

回退保留 Beta 1 App；是否能读取升级后当前数据需要独立证明。需要检查旧备份时只恢复到新的私有目录：

```sh
python3 -B scripts/storage-recovery.py restore \
  --source '/absolute/existing-private-parent/new-backup' \
  --destination '/absolute/existing-recovery-parent/new-recovery' \
  --expected-manifest-sha256 '<trusted-backup-manifest-sha256>'
```

恢复不切换正式根、不启动 App、不降级 schema。无法证明回退兼容时保留当前数据和旧包，修复或用隔离副本诊断；不把旧备份覆盖升级后的新数据。详见 [离线恢复工具](STORAGE_RECOVERY.md)。

## 签名、公证与 V2 的原生差异

本轮尚未取得最终候选的真实 Developer ID / Apple Accepted / staple / 干净设备 Gatekeeper 证据。历史 `preflight` 缺少输入凭据时返回 `BLOCKED_CREDENTIALS`，并不说明机器上绝对没有证书。`codesign --verify` 对 ad-hoc 包成功也不代表可信外部分发。按 [发行工程](RELEASE_ENGINEERING.md) 绑定同一包执行显式签名、公证查询与装订；失回执保留原任务，不盲目重传。当前不公开发布、不接 Sparkle、不修改付费方案或系统安全设置。

V2 的六页、状态方向、三级参数、关闭选择和三步引导保留；以下是应在最终视觉审核中核对的原生表现：

- `NSWindow` 使用 macOS 标题栏；内容目标为 960×684 pt，外框高度随系统装饰增加。小屏按可用区域收纳，内容滚动；后续刷新不把用户 resize 重置。
- 开关、下拉、文本编辑器、原生菜单、popover 与 sheet 由 AppKit 绘制，聚焦框、字体度量、菜单宽度和换行不逐像素复制 HTML。它们仍需实际键盘、VoiceOver 与 IME 验收。
- 布局/动效预览使用绘制示意，不读取用户截图。历史复用真实历史窗口与统计，不搬用原型的虚构近期记录或固定容量数字。
- 深浅色与系统动态辅助功能走原生状态；截图中一帧正确不等于运行时切换、所有屏幕或最旧系统都已通过。以逐场景矩阵和精确候选证据为准。
