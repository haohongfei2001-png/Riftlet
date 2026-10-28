# 真实系统截图第二阶段：开始通过，完成判据修复待新输入复测

本轮只对一张新系统截图 D 执行一次输入。**SC-INPUT PASS、SC-START PASS；完整 SC-COMPLETE FAIL。** 页面已经展示原附件，正文及非空选区保持；原程序的精确颜色比较拒绝了最终 proof。现已用同一原件/预览的只读单变量对照定位并修复该问题，但没有重输 D、补签历史完成或开启任何准入。

分支 `codex/riftlet-real-mac-acceptance-sc-stage2-20261028`，从首验交接 `5d2994c150646549830746cd83c264c600973689` 续做，包含正式 `4b7228a07a23381d3de467a44dd8490d73e26e7e` 和权限唤醒修复。没有修改正式 PR #1、main、Pro 的工作树或截图候选并行分支。

## 可直接集成的修改

| 提交 | 修改与验证范围 |
|---|---|
| `867d93f797952fd0402d50525f384f2f416c1b93` | 增加完整 v9 root monitor 兼容，实际恢复本页 ACK，并用于本次唯一系统截图输入；修正无 armedTarget 时 foregroundSessionMatches 的 nil==nil 诊断假阳性；有界只读证据工具与 CI 接线 |
| `48574df19f34e5681ee98815750e279540e9eb9b` | 移除像素比较的 willReadFrequently 性能提示，保留显式 sRGB、精确 RGBA digest、原目标/节点/source/最终 load 校验。完整构建与页面回归通过；只读颜色路径实测通过；**没有新的 Web 输入复测** |

v9/v10/v12 的冻结 root monitor、业务身份读取及 binding predicate 逐字相同；现场旧 v9 的 intact/bind/stop/get/set 也逐字匹配。修改仅扩充严格 owner 白名单，不替换 descriptor、清理 registry、抹除 UNKNOWN、回填 ACK 或调用旧输入。原页面先前 v11/v13 的失败空 registry 得以原地继续使用。该修复解决特定旧监视器阻断，**不解决完全无 pre-event ACK 的冷首击结构性缺口**。

## 三层实际证据

| 层 | 实际结果 |
|---|---|
| ChatGPT 页面 | 新 PNG 输入一次；原进度节点从无数值到 10.2964、18.5335，最终 100、移除、原 image 的 data-PNG load；一张附件仍在原 form；48 字符和选区 8..11 保持，编辑器始终未聚焦 |
| 候选 journal | 原操作首次 unknown、input、start、errorOrInvalidated；四条 identity 的 asset/op/attempt/hash/完整 target 逐字段相同；input/start attachmentID 相同；**没有 attached/ready 槽** |
| SQLite v3 | D unknown/visible，upload_starts=0，三份候选准入表仍为空。同草稿保护不解除；不吞噬是当前未准入行为，不能据此判断网页没有收到图片 |

公开可核查标量见 [result.json](result.json)，原件/数据库/原始日志及完整身份仅保存在私有证据目录；[哈希索引](private-evidence-sha256.json) 用于本机复核，不包含这些原件。

### SC-INPUT — PASS（软件鼠标，已有普通线程）

- 用户按原 macOS 截屏流程产生新的 selection PNG，系统 `kMDItemIsScreenCapture=1`；不是给生成文件人工添加 metadata。测试画面虽由程序生成，输入文件确为系统截图。
- 1,630,918 字节、1562×984；系统原件和私有副本 SHA-256 同为 `ef9175271cf36fc572031aa4013a7c529f6a757e15a0323afd7b9713f332df5d`，符合原格式/尺寸限额。
- 使用授权的 CGEvent 单次 down/up，经过实际 Riftlet 图像输入窗口，选择 D；不是文件选择器、AXPress 或人工物理鼠标。
- 完整 App ACK 比原点击早 1967.301 ms；原 selection、host epoch、Chrome session/window/tab/document/composer/draft 与 operation/journal 一致。D 的持久业务草稿身份与旧 A 不同，未清库或仅靠 URL 绕过锁。
- begin=1、chunk=7、commit=1；chunk 是 256 KiB 分块，**不是七次输入**。页面 inputCount=1，独立 change listener=1；没有发送消息或第二份附件。

### SC-START — PASS（严格限定这一原操作）

输入后 1494.4 ms，原附件同一个进度节点由 10.2964044 增至 18.5335279。文件 hash 验证已完成，原 page closure 构造 UploadStartEvidence v1；native 观察到 start 并写入持久候选 journal。之后进度继续到 100，排除单独占位图、change、isUploading 或旧附件冒充开始。

页面相对输入时间：初始进度节点约 +55.2 ms；首个数值 +1291.9 ms；可信开始 +1494.4 ms；100% +2212.5 ms；进度移除 +4784.1 ms；最终 data-PNG load +4919.0 ms。原生 commit 位于点击后 683.731–802.487 ms。两个时钟分开记录，不伪造精确跨时钟时间点。

**上一张 40 KB A 没有历史中间值记录。** 只读可见它曾有进度节点/100%，但不能重建中间采样，也不能将“小图过快”写成已证实根因。当前递增中间值判据不能保证覆盖每个快速上传；最终 READY 不得伪装为历史 start。

### SC-COMPLETE — FAIL；已定位并提交最小修复

原页面 100%→移除→原 image load 已发生，身份、正文、选区没有替换，continuityEvents 的 outsideInteraction/navigate/currententrychange 均为 0。但旧运行代码最终 proof 为空、invalid=true，候选没有 attached/ready。

独立内容对照限定同一个原截图和原预览，不调用生产 sample/validate/drain，不写原操作：

| 对照 | 结果 |
|---|---|
| PNG 文件字节 | 不相等；原件含 ICC/cICP，预览已重编码。不能宣称服务端原文件字节保真 |
| 原程序：显式 sRGB + willReadFrequently=true | 6,148,032 个 RGBA 通道中 108,932 个相差 1；精确 hash 不相等 |
| 仅移除 willReadFrequently，仍显式 sRGB | OffscreenCanvas 与 HTML canvas 均严格 hash 相等：`9f855b0d4afc22c84a1c2be70878195bb224340821c3d5bf203642b5744f9558` |
| 独立 ImageIO→sRGB | 也测得少量 1 级差异；不同解码/颜色路径不能互相冒充同一判据 |

因此已定位到 context 选项相关的颜色舍入不一致，并复现了原严格匹配必然拒绝的条件。原 markBad 没有记录具体分支，不能声称独立捕获了它首次失效的调用栈；点击后10秒内9次预绑定均成功且target digest一致，没有目标变更证据。具体 CPU/GPU 内部机制未直接测量，不作硬件归因。最终源码只删除该性能提示，仍要求精确匹配，**未使用容差、近似相似度或更宽松完成 profile**。

这证明同一原附件预览在普通 sRGB 路径下与本地原图像素一致；它不重建旧操作 proof，也不等于修复后的端到端已通过。D 仍为 UNKNOWN、禁止重输。

### 草稿与 GUI 范围

正文 48 字符、非折叠选区 8..11、原 editor/form 节点均前后相同；上传期间及最后核对均 pageFocused=true、editorFocused=false。消息节点计数不变；本轮没有调用发送动作。**旧附件基线为 0**，只证明 0→1 唯一新附件，不宣称非空旧附件保留矩阵通过。

CGEvent 的实际微图命中、Chrome 前台与未聚焦编辑器保留 PASS。人工物理鼠标、CLEAR/GAP 物理透传、本轮多屏/全屏/Spaces均 NOT_RUN；没有用软件事件冒充物理通过。原系统截图快捷键由用户完成，未记录硬件按键的精确 T0；系统文件时间和自然收录记录不能代替完整 T0/T1/T2 延迟测量。

## 数据保留与停止状态

候选复用同一数据根和 SQLite v3。开始前 2 assets/2 operations，结束后 5 assets/3 operations；D 是唯一新增操作。旧 A、B 原 asset 行及全部旧 checkpoint 不变；B 原操作不变。A 只读恢复更新了 updated_at 和 receipt.belongsToOriginalDraft（true→false），phase、attempt、target/hash未变；旧 receipt 的私有一致性备份保留，未输入。

C 截到了其他桌面内容，未上传；E 在只读分析期间自然收录，未检查也未选择。所有系统原件、5份私有媒体、UNKNOWN、审计、数据库和历史工作树保留。没有转换/删除文件、清库或新数据根绕锁。诊断只停止自身监听，原监视器未停止；取证完成后退出本轮候选 App，避免继续占用桌面，数据库和草稿附件保留。

## 构建、审查与交接

本机 macOS 27.0 (26A428)、arm64、Swift 6.4、Chrome 156.0.8078.73；单一内置屏幕 1470×956 pt、2×缩放。本轮实际输入只有一个执行者；非作者 agent 仅读源码/私有证据并运行无界面测试。

- 最终完整 App 构建、签名/资源检查 PASS（development ad-hoc，非发行签名）。
- 页面 86 + legacy 61、stage2 helper 12 PASS；候选 self-check PASS（生成 fixture，明确不是第二次真实输入）。
- macOS CI：见 [verification.json](verification.json)。
- 非作者已审 v9协议、旧UNKNOWN保留、两个最小源码修改、真实开始因果、颜色单变量对照及公开证据边界；见 [review.json](review.json)。

**Pro 的下一步只需有界补验完成路径：** 集成两个源码提交后，在独立业务草稿使用另一张新的真实系统 PNG 作一次输入，验证最终普通 sRGB 严格 proof 与 attached journal；不要使用 D 或回填它的观察。非空旧附件保留仍需单独限定证据。开始准入可依据本次真实 SC-START 独立审查，但不扩大到快速小图、所有色彩格式或普通生产；完成与安全重试仍分别关闭。本轮不再重复上传、MID或全面发行验收。
