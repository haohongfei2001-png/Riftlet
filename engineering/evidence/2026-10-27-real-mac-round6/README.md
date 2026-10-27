# 第六轮：冷首击边界、实际响应速度与连续点击

本轮从第五轮最终交接 `3bb13999b0f444c7748804eef1976e179a52a85e` 建立独立分支 `codex/riftlet-real-mac-round6-20261027`。启动核对正式分支至 `2449d40a88225acba9d413cc6a4cb5d84fcae6a1`；Pro 安装/权限专项未混入本工作树。Core/UI/App 正式源码零改动。原分支、SQLite v3、原媒体、UNKNOWN、补偿与既有开始审计保留。

## 真实结果

| 项目 | 结果 | 范围 |
| --- | --- | --- |
| 传输优化 | **PASS** | 相同 3,147,775-byte 生成 PNG，从 49 个 64 KiB 分块改为 13 个最多 256 KiB 分块；逐块 ACK、两遍完整哈希、完整身份和一次 commit 保留。 |
| 点击至关闭 | **PASS，有限样本** | 主机同钟 AppKit 关闭：5.510218 → 3.668704 秒，减少 1.841513 秒 / 33.42%。分块窗口 2.770876 → 0.893438 秒。每方案各一次，不是统计保证或像素呈现测量。 |
| 实际开始与最终成功 | **PASS，synthetic-only** | 一次 input、原附件进度 4.0841 → 4.9917、start 早于独立最终 proof；旧卡、原空文字与选区保留。输入到 start 2.2354 秒，没有缩短证据等待来冒充优化。 |
| 有效普通对话、无已发布 ACK 的冷首击 | **FAIL，已复现** | E503… 原点击发生在完整 native 校验前 6.365 ms、App 发布前 7.247 ms；安全拒绝且没有 operation。收到原生字符串早于事件，并不等于完整可用 ACK。 |
| 同草稿连续点击 | **FAIL，已复现并定位** | A 开始后，B 原点击被接受和冻结，但 Core 同草稿未决锁取消 B，原因明确为未发生输入。未放宽 UNKNOWN 或 start 后锁。 |
| 旧 v11 操作恢复 | **PASS，离线兼容范围** | 冻结真实 v11 原程序 fixture，只允许原操作 observe/schema1；不能借新 v12 输入或开始准入。页面消失不补证。 |
| 人工物理鼠标、透明穿透、全屏多屏 | **NOT_RUN** | 本轮点击来自现有 helper 的精确 AXPress，明确 `physical=false`。 |
| 新 A→B→A、安全失败重生、MID、系统截图自包含 | **NOT_RUN** | 未用本轮单图性能或软件点击替代这些验收。生产截图上传、安全重试仍关闭。 |

细节：[性能分段](performance-analysis.md)、[冷首击因果链](cold-click-analysis.md)、[连续点击复现与接口提案](consecutive-click-proposal.md)、[连续点击脱敏原始字段](consecutive-click-evidence.json)、[保留核验](preservation.json)。

## 精确源码与环境

真实输入/性能比较的新源码为 `7878de3138d1c140369c3cfbe69a28dd2770294c`，继承第五轮两份仅验收 overlay：`app-acceptance-overlay.patch` 与 `acceptance-synthetic-identifier-overlay.patch`。只在临时构建副本应用，正式 Core/UI/App 不改。运行 App SHA256：`6119a6fb872f7e5cd380d1d234955d2e14e6e8f48d80bbaaeda35afcd5ea91ee`。旧对照源码为第五轮 `53ebcc4da4b0df508edc11f6ead9ea4d8a843dad`，不是本轮重新执行旧成功上传。

macOS 27.0 (26A428)、arm64、Swift 6.4、Chrome 156.0.8078.48。Chrome 的真实普通对话、MAIN 页程序、原 PID Apple Events、真实 AppKit 面板和现有 GUI helper。没有 ChatGPT send。输入仅生成图片；图片、完整 target、URL、页面内容、SQLite 与原日志只保存在本机私有备份，未进入公共仓库。

`7878de3` 的 [CI 40510840772](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40510840772) **PASS**：320 项原生、72 当前页面、54 legacy、13 生命周期明细（属于原生子集）、既有故障/probe/replay、Release/签名/三个自检。本机 Release 构建/签名和 126 个页面测试通过；本机 CLT 缺 XCTest，因此原生执行以 CI 为准。

最终代码检查点 `c000cc1b930b278ae22b29e6b01941a9faf0a87d` 增加 Chrome 固定 ID 描述符一次读取。相同临时 overlay 构建的 App SHA256 为 `17d89ddcf72d9efa84a826436175843a0401bbfa16136b0afd48c88e527cd89c`。三次真实只读捕获中，六次原选择读取全部命中严格快路径；回复至完整校验 4.38 / 4.78 / 11.91 ms，原样本为 26.79 ms。没有新的选择或输入。见 [只读真机证据](selection-read-evidence.json)；不把 `7878de3` 的上传结果冒充 `c000cc1` 再次上传运行。

最终 [CI 40513086114](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40513086114) 在交接核对时仍为 **NOT_RUN / queued**，没有开始步骤，未重复触发；Pro 集成前须核对该精确源码的结果。最终源码本机 Release/签名、5 组 Foundation 描述符断言和真实只读捕获通过。本机 XCTest 不可用。详见 [verification.json](verification.json) 与 [独立审查](review.json)；源码均在独立分支，未修改 PR #1/main。

## 交给 Pro 的集成边界

先整合第五轮，再按本分支相对于 `3bb1399` 的提交整合；不要重复 cherry-pick 第五轮或回退 SQLite。Web v12 的 256 KiB 容量是代码所有的配置；通用/旧程序默认 64 KiB，总图片上限与页程序一致为 8 MiB。

连续点击第一步提案只停放尚未 input 的原点击 lease，待现有锁合法解除后重新验证同一 lease；没有 capture、目标替换或 UNKNOWN 重传。可执行模型只是提案，不是已交付 Core 实现。start 后立刻输入另一图需要独立不同资产隔离能力及双图准入，不能复用 uploadStart 授权。

无 ACK 冷首击的根本约束仍保留：任何提前读取优化均不能创造事件前不存在的目标证明。不得把事后 ACK、同 URL、收到未验证回复或短动画当作修复。
