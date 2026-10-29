# 自然原生首击时间链专项 — 2026-10-30

本轮**没有取得新的自然首击成功率或完整系统截图闭环**。恢复了固定 Chrome 接收者的原生只读诊断，交付可运行的时间链补充，并修复现场实际复现的日志交错。一次软件系统截图尝试未在配置的保存目录观察到新文件；没有点击旧图或新图，没有上传、重放或发送消息。

## 准确来源与交接边界

- 起点：`21a6be430f75848cf5efe5cc5c97ce6fd6b492f9`，保留已审原生 `c308d46c1412a56e90d665972c0bc8f6ad1511a3` 及独立架构实验历史。
- 原生诊断源码：`a1df3d9242d4a38e42ccb37124d0dd98d761d5c2`。
- 最终完整源码/归并器：`e5d77d3c82bf2769387049e533e93073d36ee6fb`；后者只修正两个离线脚本，不改变前者的原生程序。
- 分支：`codex/riftlet-natural-first-click-20261030`。原工作树、三个数据根和原始证据保留。
- 本轮先核对 PR #15 为 `c15fd4b…`；结束前重新读取实际 head 为 `53ea3a1de76a30ab0d8cb221ff7e4e4fa2bce83f`，仍 Draft/未合并。新正式增量是 Feedback 云交付与元数据；本地运行不是该最新统一 App 的组合验收。
- 本轮没有修改 PR #15、PR #1、main、正式工作树、Core、Adapters、准入表或历史证据。页面内点击实验保持独立历史，未进入原生入口。

Pro 集成时只取 [native-diagnostics.patch](native-diagnostics.patch) 的 **5 个原生源码 + 4 个对应测试文件**。该 patch 相对上述起点，前置是已审 `c308d46` 原生修复；不要重复导入它，也不要把本专项 workflow、架构实验及来源审计整体合到正式工程。保留当前正式 FeedbackHost/endpoint 和正式门禁，再由唯一集成人执行组合测试。

## 实际结果

| 项目 | 结果与适用范围 |
| --- | --- |
| 现有 Chrome 原生 AE/AX | **PASS，控制诊断**：固定 PID/session/tab 的只读 DOM 查询及 AX 窗口读取可完成；实际 App 曾发布完整目标。不是点击授权/附加成功率。 |
| CUA 专用验收标签 | **NOT_RUN**：能列出标签，但 DOM 读取 12 秒超时。不能由此断言原生 AE 也不可用。 |
| 第二 Chrome 实例 | **FAIL，接收者能力诊断**：JS AE 返回状态 12；它曾成为前台。没有改其权限、配置、资料或终止该进程；不能据此归因主实例。 |
| 新系统截图样本 | **FAIL（软件取样尝试），后续点击 NOT_RUN**：一次 CGEvent ⌘⇧4 观察到系统截屏 UI；区域释放后有界检查以及结束前复核均无新文件。只读偏好显示 file/Downloads；没有改截图设置。尚不能确定未在配置目录观察到新文件的原因。 |
| 自然物理首次点击 | **NOT_RUN**：0 次可信人工操作。软件快捷键不计物理输入，`mouse` 也不等于硬件。 |
| 新微图第一次点击/附加 | **NOT_RUN**：0 次原生微图鼠标/AX 点击、0 次新上传。成功率、延迟分布均为 null，不能报告 0% 或 100%。 |
| 已打开聊天/启动/切换/正文/侧栏/未聚焦 | 部分只读环境与启动诊断可执行；**各场景完整点击试验均 NOT_RUN**，见 JSON。未重复旧 R6/R7/R9 无 ACK AX 试验。 |
| 日常原生可靠性 | **尚不能判定**。本轮没有新的自然点击分母，不能证明大量拒绝，也不能证明日常已可靠；不启动新的点击保留/传输方案。 |

生成的彩色图只是 Preview 内的安全显示素材，未作为上传文件、未添加截图 metadata。没有以 CLI/内置 applicationScreenshot 代替正常系统截图来源，也没有借旧图片补足样本。

## 已实现的最小观测与现场修复

1. Capture 可选、默认关闭的非持久化 uptime：本进程首次候选观察、完整复制/哈希/签名/元数据与图像验证完成的观测上界、原数据库导入返回时间。既存资产、journal 恢复和去重返回均不制造新时间；跨重启 handoff 不补原 firstObserved。
2. Main 分开 import-ready 与实际 MainActor 回调，记录原预绑定 invocation 的开始；App trace 带独立 runID/统一 `hostSystemUptime`。私有 sidecar 保存原 boot 与进程绑定。
3. UI 分开初次窗口 order、图像交付与进入原生选择 gate 的 down。记录 asset、窗口、原 NSEvent 时间/编号、软件 token、gate 结果。它们不产生目标证明；AppKit isVisible/order 不冒称 WindowServer 像素或精确首次可点 T2。事件在输入 view 更早 guard 被拒时可能没有 receipt，应保留未路由/未证明。
4. **现场日志缺陷修复**：原 stdout `print` 与 stderr 合并时产生 8 条损坏行；改为单次 stderr 写整行。修后现场 998 条记录、0 条损坏。原有损日志仍保留，不能作为完整可导入时间链。
5. 离线归并只连接原 request/attempt/host epoch/target digest/原事件；拒绝迟到、混 run/boot、重复点击或旧操作样本。独立审查修正了过强的总序假设：导入返回→Main 与 source→窗口观察是不同分支，原事件可以早于 order 后观测，保留有符号偏移而非虚构负“延迟”。

**仍缺的时间事实**：T0 实际系统捕获完成未被直接观测；文件日期、复制结束或 capture UI 退出不替代 T0。没有新源文件，故本轮无新样本 T1。AppKit 观测上界不填精确 WindowServer T2。禁止用缺失链条做自然延迟分布。

## 验证、隐私与保留

- 本机 macOS 27.0 / arm64 / Swift 6.4，完整 App 构建及受限候选自检通过；仅有 CommandLineTools，XCTest 未运行，明确交由 macOS CI。
- 精确 `e5d77d3` 已完成非作者源码审查与 21 条独立离线反例复验。macOS CI 与原始制品状态见 [validation.json](validation.json)。旧中间 CI `40912738802` 为主动取消，不标失败或通过；最终仅需一套完整源码验证。
- [runtime-results.json](runtime-results.json) 给出实际操作、场景边界和私有原始文件的 SHA-256；[retention.json](retention.json) 给出三数据根的保留与变化。
- 旧 50 份媒体逐字节保留；32 个操作无新增/删除，7 条 upload-start 与补偿、metadata/checkpoints 表保持精确一致；准入源码保持原 Git 对象，未单独对运行时准入 sidecar 作前后哈希比较。候选启动自然收录此前 backlog 3 张（不是本次截图样本）；3 个旧 UNKNOWN 在原后台观察失败路径更新 reason/updated_at。操作表哈希因此变化，**不声称整库或整操作表字节不变**。UNKNOWN/failed/succeeded 的原阶段分布保持；没有盲重试或解锁。
- 公共仓库不包含实际截图、正文、完整目标、私有路径、浏览器会话、数据库、原始日志或凭据。原件、所有新收录、私有日志与哈希均留在本机。

## 恢复条件与最小下一步

保留本诊断 App/同数据根；由可控的真实系统截图输入取得一个新 PNG，且有单一明确的 Chrome 前台接收者，才能继续各场景的原生首次微图点击。若没有可信人工操作，仍只能给 CGEvent 控制样本，不能替代自然物理成功率。不要求创始人体验 Beta，不因这次未产出文件而重做架构或降低任何准入。

可复用命令（输出写入私有目录）：

```sh
bash scripts/build-macos.sh
./build/Riftlet.app/Contents/MacOS/Riftlet --system-screenshot-candidate --acceptance-trace --arrival-trace
python3 -B engineering/experiments/natural-first-click-20261030/timeline.py /private/session-manifest.json
```

已在临时 Git index 对正式 `53ea3a1` 依次检查 c308 原生前置及本次 patch：干净应用、无冲突项、正式 FeedbackHost 原对象不变；未写正式 refs/工作树，未把它标为组合 App 已编译。

运行者需记录独立原事件来源与真实 boot/run；不能等到 ACK 成功再制造“自然首次点击”，也不能把被拒点击存下来重放。
