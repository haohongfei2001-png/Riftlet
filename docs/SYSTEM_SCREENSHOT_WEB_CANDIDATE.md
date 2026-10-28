> **当前候选已进入受限准入阶段。** 请先读 [当前准入、保护和真实 Mac 直接入口](SYSTEM_SCREENSHOT_RESTRICTED_ADMISSION.md)。下面完整保留 `871d825` 时期的输入候选设计与验收边界；其中“SC-COMPLETE 未复测、三份映射为空、不吞噬”仅是旧检查点事实。新版本只为新登记操作开放独立的 v2 开始和完成，旧 v1、F/旧 UNKNOWN、安全失败/重试和普通生产继续关闭。

# 真实系统截图 Web 内部候选：第一、二阶段历史基线

本页为真实系统截图第一、二阶段集成后的当前候选使用／准入交接。正式基础 `4b7228a` 已按真实祖先关系继承第一阶段 `5d2994c` 和第二阶段 `f2ae645`；最终源码为 `48574df19f34e5681ee98815750e279540e9eb9b`，当前交接提交不再修改源码。最终准确正式 HEAD 与实际 CI 见 PR #1 最新交接；[本轮永久对象与非作者审查](../engineering/evidence/2026-10-28-integration-sc-stages1-2/README.md)。原候选、第八／九轮、两阶段提交和原证据全部保留。

## 当前可以运行什么

**普通启动仍只收录，不上传真实截图。** 显式候选已接通系统收录与既有 Web 输入链，供授权 Mac 执行者取得真实证据；尚未批准生产使用或宣称真实两次操作闭环通过。

| 入口 | Application Support 数据目录 | 来源与输入 | 准入 |
| --- | --- | --- | --- |
| 普通 Riftlet.app | Riftlet | 系统截图收录；UnavailableAdapter | 开始／完成／重试关闭，不检查 Chrome 权限 |
| --simulate | Riftlet-Simulation | 生成图，离线演示 | 仅 simulation store/target |
| --web-acceptance | Riftlet-Web-Acceptance | 生成图，真实 Chrome 输入 | 保留已审生成图开始／完成；安全重试关闭 |
| --system-screenshot-candidate | Riftlet-System-Screenshot-Candidate | 原始系统截图，显式内测输入 | 开始／完成／安全失败全部关闭；保存未准入观察 |

普通 App 菜单的“打开真实截图内部候选…”启动独立实例，标识为 `Riftlet REAL TEST`。首用、截图位置访问、暂停、隐藏、历史、Chrome 权限恢复沿用既有原生入口。普通实例继续保留；launch 回调不被误认为初始化成功。执行者确认候选状态后可退出或隐藏普通实例，避免两组微图叠放。真实候选已有第一、二阶段的限定运行记录；完整 TCC／多进程／物理入口矩阵仍未通过，不由 CI 判定通过。

```bash
bash scripts/build-macos.sh
./build/Riftlet.app/Contents/MacOS/Riftlet --system-screenshot-candidate --acceptance-trace
```

首次收录沿用 Capture 持久 epoch／历史基线，只收录之后出现且满足系统 screenshot metadata 的文件。只使用新截图，不能把旧图库导入为新图，也不能删除数据库绕过 UNKNOWN。重开沿用原目录，只读恢复旧操作，不恢复旧点击。无原事件前完整 ACK 仍安全拒绝；第九轮没有修复这一产品限制，禁止晚到 ACK 补签。

## 真实接线与保持的保护

- ApplicationMode 分离系统收录、生成图 seed 与 Web 能力；候选不能 seed 生成图片，全库来源检查在私有导入恢复后、transport 构造前完成。
- App 与自检共用 ApplicationAttachmentComposition，复用 Capture/私有副本、SQLite v3、AcceptedSelection／同步序号、单一 Coordinator、Chrome Apple Events、MAIN 和已审 v13 页面程序。没有第二套上传系统或浏览器扩展。
- `preflight(asset:fileURL:)` 是本地无外部副作用的资格检查。Coordinator 先恢复原操作，只有新输入才 preflight 后 reserve/prepare；不支持格式不会先制造 intent、UNKNOWN 或锁。
- 候选精确限定 `chatgpt-web-zh-20261027-integrated-v13`，仍拒绝旧 sourceID、生成图 profile 或缺失 journal。v13 支持完整原 v9/v10/v12 同 root 监视器共存，v6–v12 旧操作只读；严格 owner／函数／descriptor 检查不变，不恢复被停止的旧证明。
- 256 KiB 分块、逐块 ACK、同一 no-follow descriptor 两遍 SHA256、唯一 commit、完整原目标复核保留。传输名称为 `riftlet-<operation UUID>.png`，不传系统文件名；只读取私有副本，不重编码、缩放、改后缀或修改原件。
- ObservationNormalizer 的原生控制 systemScreenshotCandidate scope 只用于候选 profile；默认仍拒绝真实来源的 development 观察。保留 integratedDevelopment provenance，不伪装 sanitizedReal 或 synthetic。
- SystemScreenshotObservationJournal 在原 v3 checkpoints 原子首次写入最多六类观察：input、start、干净attached、干净ready、error/invalidated、unknown；每条≤64KiB，按原asset/op/attempt/hash/完整target核对。重复或重启不覆盖；不写upload_starts、不生成授权。磁盘失败不能变成安全失败。
- intent后才发现私有损坏或传输不明时，仍保守UNKNOWN；本地文件头检查不是完整SHA校验替代，未看到输入也不能推导安全重传。
- 第八轮视觉窗口忽略鼠标，图片/数字独立输入窗口；外部CLEAR由WindowServer路由。原点击asset、按住时延迟补位、隐藏、归档及历史保护保留。不是图片alpha或圆角逐像素透传承诺。

Capture 的已登记复用、Web 的既有输入／观察实现、版权与许可证保持不变；没有云服务或新增运行时依赖。

完成内容校验仍为原文件字节 SHA-256 相等，或相同尺寸且显式普通 sRGB 的完整 RGBA SHA-256 精确相等；移除 `willReadFrequently` 只统一已观察的颜色路径，不接受一级像素差异、不放宽为近似匹配。修复后新输入完成尚未实测，不能给原 UNKNOWN 重新生成 proof。

## 格式、大小与保真

| 文件 | 本地处理 | 当前候选输入与边界 |
| --- | --- | --- |
| 单帧PNG≤8MiB、≤16,777,216像素 | 完整检查后原字节复制 | 有资格进入内测输入，仍需原目标／权限；输入／开始仅限定 PASS，修复后真实完成待新输入 |
| ICC／高位深PNG | 编码尺寸、ICC／位深保留 | 同一PNG上限，不擅自转8-bit；16-bit/P3本地测试不证明浏览器/服务端HDR与颜色表现 |
| JPEG | 单帧原字节、EXIF方向及颜色信息保留 | 输入前拒绝，不转PNG；ImageIO方向预览的真实外框/遮挡仍待验 |
| HEIC／HEIF | ImageIO可解码、单帧时按原规则保留 | 输入前拒绝，不隐式有损转换；HEIC测试不代表全部HEIF/HDR |
| TIFF | 单页原字节接受，多页拒绝 | 输入前拒绝，不丢页或自动扁平化 |
| 超过8MiB或16,777,216像素的PNG、仍在本地上限内 | 原样保留、可恢复 | 明确拒绝输入，不缩放或压缩；这是v12/v13程序限制，不是ChatGPT通用产品限制 |
| >128MiB、>160,000,000像素或单边>50,000 | 按Capture上限拒绝收录，系统原件保留 | 不输入，准确提示限制 |
| PDF、多帧、不完整或无法解码 | 按原因拒绝或等待完整性恢复 | 不抽帧或改为其他格式 |

拒绝文案区分“已保存在本机、未上传／未转换”和“未收录”。没有转换开关；增加JPEG或更大输入必须扩展实际程序与证据，不可只改Swift上限或MIME。

## 开始、完成、安全失败分别准入

候选 profile 与生成图独立：

- 开始：`chatgpt-web-system-screenshot-start-candidate-20261028-v1`。
- 完成：`chatgpt-web-system-screenshot-attached-candidate-20261028-v1`。
- 安全失败：当前没有启用的failure signal/profile。

SystemScreenshotCandidateConfiguration 的 uploadStartProfiles、completedAttachmentProfiles、safeFailureProfiles **均为空**，由源码持有，不读取环境变量、外部JSON或页面enable。权限获准不等于普通模式切换候选或生产。

准确行为是：允许测试输入，记录原start/attached候选观察，本地仍UNKNOWN且可见，不吞噬、不succeeded、不重传。同草稿下一张仍受原UNKNOWN锁保护。**不吞噬不是上传失败，不因此再次点击或清库。** 页面实际附加、候选观察、本地状态必须分别记录。

第二阶段已取得限定 SC-START 原证据；本轮只集成源码和验证，不登记任何新准入，三份映射继续为空。未来开始、完成、安全失败各自独立审查；普通生产仍另行准入，合成测试、历史生成图或只读颜色对照均不能代签真实完成。

安全失败不是只填映射：当前failureSignal=nil，absence-only路径缺原非空attachmentID的退役身份，仍需独立真实终止与无残留自动retry证明。**第一轮SC-INPUT/START/COMPLETE不以先完成失败安全重试为条件**；附件消失、超时、MID/POST100中断也不能直接授权重传。

## 下一轮直接执行，不重新规划

本地 Codex 从 PR #1 固定的最终正式 SHA 新建独立 worktree，保留原分支、原件、私有副本、同一候选 v3 数据库/WAL、UNKNOWN 和补偿。无需重复第一、二阶段；下一次仅用另一张新系统 PNG，在原规则允许的独立业务草稿取得修复后的完成 proof 和 attached journal。旧 A/D 不重输，不补签历史完成，不清锁或重建数据根。

| 证据 | 实际要求 | 当前状态 |
| --- | --- | --- |
| SC-INPUT | 系统截图metadata、原件与副本hash/编码尺寸、原点击/先行ACK/完整target/asset/op/attempt、begin/chunk/commit及inputCount=1；不Send | 限定 PASS：第二阶段867d93f，真实系统PNG、CGEvent、一次输入；不代替物理／冷首击矩阵 |
| SC-START | 同一真实图/操作/附件的正向进度或请求、先后顺序；排除占位、错图、错目标和迟到事件 | 限定 PASS：第二阶段原进度中间值递增及候选审计；不保证快速小图，开始准入仍关闭 |
| SC-COMPLETE | 原附件ATTACHED及精确内容证明；原正文、选区和旧附件保留，明确Home/既有对话及焦点范围 | 旧运行源码 FAIL；48574df修复后新真实输入 NOT_RUN；完成准入关闭 |
| SC-ANOMALY | 网络/导航/观察丢失/重启/迟到错误下原操作只读，图与首观察保留 | 后续独立验收 |
| SC-FAILURE | 原附件强失败且旧流程安全终止，无迟到成功或自动retry；新尝试仅新点击 | 后续独立验收；不阻塞前三项取证 |
| SC-UX | 受限开始准入后的点击/开始/持久隐藏/AppKit/像素边界；物理GUI和系统截图完整延迟 | 后续真实验收 |

第八轮CLEAR已取得限定WindowServer/CGEvent底层down/up PASS；第九轮补位双击软件样本A一次、B零选择，均不替代物理鼠标。第九轮无ACK冷首击仍FAIL（约209ms），业务ABA、MID、自包含等保持开放。合流二进制未运行真实Chrome/系统截图/物理GUI；来源范围不扩大为本版本真实完成 PASS。第二阶段只证明其48字符、选区8..11和未聚焦editor保留，旧附件基线为0；非空旧附件保留仍需单独限定证据。

审计留在候选私有SQLite；公开交接仅放去隐私身份摘要与必要时序，不上传真实截图内容、完整私有数据库、草稿正文、认证资料或完整浏览器状态。旧UNKNOWN只能观察，不能为制造成功样本重新输入。
