# 第七轮真实 Mac：原点击顺序等待已实际运行

独立分支：`codex/riftlet-real-mac-round7-20261027`。本轮没有改 main、正式 PR #1、网站或设计成果，没有发送 ChatGPT 消息。

## 源码与范围

- 起点正式 `caa6a65b69c6038154a2fff65f2fb1157125bb7e`；通过有祖先关系的 merge 继承第六轮 `65f7d54121a637e8a97d2f25f8bcd8069393eb4d`，基线 `336ecce8714981d967f50fcdaf62de44f0979660`。第五轮未重复 cherry-pick。
- 最终源码与完整构建检查点：`9de6a85b0161713833dc25e3b3eb1e1a2f81a558`；在下述真机源码之上仅补诊断、测试同步、helper 覆盖和 UI 防误选。
- 真实双图与冷边界运行源码：`f6417c6faaf8aa21ac587b07f25ea2a159af021f`。完整 App 打包，没有临时源码 overlay。可执行文件 SHA-256：`07453578abcdf96256430380ce3bc5ac6120dc586fba9a880954992e2f8e0089`。
- 运行期间正式分支推进到 `81b6a61b4e648a1b8d6ccf4b569fd6d727a0cc76`，已整合第六轮。其 Sources、Tests、Package、Resources、scripts 与本轮基线 `336ecce` 相同；另增文档及一条 CI 明细调用。本分支没有覆盖正在进行的正式集成。
- Mac：macOS 27.0 / 26A428，arm64，Apple Swift 6.4；实际 Chrome 156.0.8078.48，普通线程、中文附件进度结构。仅隔离生成 PNG，生产截图、生产开始证据和安全重试 registry 仍关闭。

## 真实结果

| 项目 | 结果 | 证据与限制 |
| --- | --- | --- |
| 同草稿 B 保留原点击并等待 A | **PASS，限定真实 AX 样本** | A 为 inputTriggered 时 B prepared；A succeeded 后 B 才 dispatchIntent。两张各一次 input、独立 operation/attempt/hash/start/完成。见 [queue-evidence.json](queue-evidence.json)、[queue-analysis.md](queue-analysis.md)。 |
| 未聚焦发言框，文字、选区、旧附件 | **PASS，限定同一双图样本** | 非空文字、非折叠选区、3 个旧附件在两次输入均保留，editorFocused=false；无发送。 |
| 权限路径下的响应速度 | **PASS，测量完成** | A 3,147,775 bytes：点击到 AppKit close 2.817 s；B 1,770,843 bytes：12.213 s，包含排队及自身较慢的开始证据。B 不是速度改善样本。详见 [performance-evidence.json](performance-evidence.json)、[performance-analysis.md](performance-analysis.md)。 |
| 预绑定先于旧远程恢复 | **PASS，源码和实际顺序** | 本地恢复与原 ID 快照先完成；第一 ACK 发布后才观察旧操作，避免旧观察阻塞第一轮预绑定。每次仍检查真实权限和原 Chrome 会话。 |
| 完全没有原 ACK 的冷首击 | **FAIL，产品体验仍未达标** | Chrome 前台样本中 native 完整 ACK 晚于原点击 26.323 ms，App ACK 晚 26.742 ms；不创建操作、不补造时间、不重放。另保留 Finder 前台的不成立样本。见 [cold-analysis.md](cold-analysis.md)。 |
| IMAGE / NUMBER 软件鼠标命中 | **PASS_SOFTWARE_ROUTING** | CGEvent 标记、实际 down/up 窗口和 asset 对应；非人工物理输入。 |
| CLEAR 透明区域 | **防误选修复 PASS；透传 FAIL** | 9de6a85 复测同点不再选择图片；事件仍由 row 接收，底层 0 次。见 [GUI 结果](gui-results.md)。 |
| GAP | **PASS_SOFTWARE_ROUTING，最终批次** | 首批查询变为 0 而未发送；最终批次底层真实 down/up 各 1，零图片选择。未改 GAP 产品实现。 |
| 人工物理、跨应用连续焦点、按住补位、双击、多屏切换/Spaces | **NOT_RUN，本轮缺口保留** | 软件事件和已有纯几何回归不能替代这些现场行为。 |

## 可集成实现

`AcceptedSelection` 是运行期原点击授权，包含原 asset、target、ACK/event/accepted uptime、host epoch、visibilityRevision、capture/arm ID 和最多 30 秒期限。App 在任何异步权限检查之前按原事件顺序入队。Core 复用原 prepared operation、FIFO 和 SQLite dispatchIntent；队列有界，不持久化等待授权。A 的合法终结可唤醒 B，B 再核对原授权、原目标和权限后输入。目标变动、移除、隐藏、失权、关闭或期限到达撤销原 token；已输入/UNKNOWN 不走重新输入。

采用 exact token/UI owner 撤销，避免旧异步任务释放或取消同图的新点击；锁只覆盖 SQLite 最终 intent 写入，避免把等待数据库锁放进同步撤销临界区。原恢复只观察启动时快照 ID，不再次 reset 新 prepared 操作。

**未放宽同草稿输入锁。** A 尚未终结时 B 不实际输入、不假吞噬。真正并行双图输入、UNKNOWN 后安全复生仍未准入。

验收日志补丁只对重复未变化的可见状态和 READY 状态做各 128 条缓存去重，保留真实变化及总 2048 条上限。首个长进程确实耗尽日志；其后无日志的 AX 行为不能倒推拒绝原因。该预试验页面和数据库均无新输入/操作，完整重开进程的正试验另列，未覆盖旧记录。

## 保留与未验项目

[data-preservation.json](data-preservation.json)：schema v3，quick_check=ok；原 22 份媒体哈希、14 份其他私有文件、25 个操作身份、6 个 UNKNOWN/compensated 状态、3 条补偿审计和原 4 条开始证据保留。仅增加 3 张生成图、2 个实际输入操作和 2 条开始证据。原六轮 worktree 均保留。原始日志及 DB 前后备份存于私有备份目录；[private-manifest.json](private-manifest.json) 只发布文件名、长度与哈希，无真实截图或聊天正文。

同 URL 业务 A→B→A、跨版本真实操作只读恢复、MID 真实字节请求中断、安全失败普通可点击重生、系统截图自包含、T0/T1/T2、权限真实拒绝恢复和生产截图端到端继续 **NOT_RUN/此前开放**，没有因为本轮双图成功而关闭。

## 最终验证

最终源码 `9de6a85` 的 [macOS CI 40525056642](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40525056642) **PASS**：408 项原生测试及既有页面/故障工具离线验证、完整 Release App、资源与签名校验和自检通过。这里的故障工具 PASS 是离线夹具，MID 真实请求仍未验。首轮 CI 的重入测试因以固定 yield 次数等待而失败，已改为等待真实 append 事件，完整失败记录保留。

本机最终完整 App 构建、签名及四项自检通过；CLT 无 XCTest，本机独立执行回归没有冒充 XCTest。非作者审查见 [review.json](review.json)，精确验证输入和初次 CI 失败见 [verification.json](verification.json)。

## Pro 集成顺序

以本分支源码提交为增量审查 Core/App/UI 最小变更；正式分支已含第五、六轮，不重复挑选。先核对 [verification.json](verification.json) 的精确源码和 CI，再集成原点击 FIFO、先预绑定后旧观察、真实进程权限选择；诊断及 GUI 防误选修复独立可审。本目录的真机样本绑定 f6417c6，后续源码构建/CI 不冒称重做该样本。

下一次现场输入优先解决无 ACK 的真实冷边界和透明区域底层穿透；不要重复本轮双图成功上传。当前证据不足以启动完整 MV3/Native Messaging 重建或增加发行权限；若选择该路线，最小需求是预先建立、能在原点击时核实的页面/草稿身份通道，并保留所有现有身份与 UNKNOWN 约束。
