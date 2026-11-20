# Riftlet 跨浏览器 × 跨 AI：统一架构与实施入口

状态：**架构规划；不是已实现或已发布的兼容性声明。** 日期：2026-11-20（北京时间）。

本目录落实 [Issue #120](https://github.com/haohongfei2001-png/Riftlet/issues/120) 的最新用户授权。只增加规划文档与按现有治理要求生成的文档准入记录；不修改 1.0.7 的代码、PR、发行包或验收。

## 执行结论

- 保留 `TransferCoordinator`、`QueueStore`、一次输入许可、原图校验、原操作观察及恢复机制。最小拆分为 **BrowserHost + ConversationProvider + 共用附件运行时**，不开发十六套工具，不重写整套产品。
- 一个后续开发周期、一个实现集成 PR、一套统一验收。先冻结接口，再并行浏览器、Provider 和 QA。集成负责人唯一拥有共享代码。
- 正式目标为 Chrome / Edge / Safari / Brave × ChatGPT / Claude / Gemini / DeepSeek。Brave 保留为第四目标是基于复用成本的工程选择，不是市场份额排名。Safari 是必须实施的核心工作包，其产品可行性仍需实际 Safari 证明。
- Kimi、国内千问、豆包、Perplexity 同轮开发/验证；国际 Qwen 单独作为变体；Grok 为机会扩展。Firefox 同轮做有边界的无扩展原型，符合全部核心约束才提升为正式目标。
- 用户正常操作仍为系统截图 → 单击托盘图片 → 当前 AI 原草稿。无浏览器/AI 预选、扩展、复制粘贴、快捷键或自动发送。
- **文件输入至多一次；不确定时只读核查原操作。** 页面出现图片、交给原草稿、服务处理完成分别取证；不通过超时、重发或假成功把状态“做绿”。

## 阅读顺序与唯一责任

| 文档 | 用途 |
|---|---|
| [BASELINE_AUDIT.md](BASELINE_AUDIT.md) | 已审实际代码、未推送候选与当前 main 的区别；可复用点及必须修改的耦合 |
| [ARCHITECTURE.md](ARCHITECTURE.md) | 接口、依赖、目标身份、证据、持久化、迁移与消费级体验 |
| [BROWSER_SPIKES.md](BROWSER_SPIKES.md) | Safari / Brave / Firefox 官方依据、验证包与停止条件 |
| [PROVIDERS.md](PROVIDERS.md) | 服务能力来源、站点边界与实测要求 |
| [WORK_PACKAGES.md](WORK_PACKAGES.md) | 依赖顺序、并行路径、唯一集成人、完成标准 |
| [ACCEPTANCE.md](ACCEPTANCE.md) | 三层测试、逐格验收、异常、性能和发布门槛 |
| [compatibility-matrix.json](compatibility-matrix.json) | 机器可读初始矩阵；未执行的格全部 NOT_RUN |
| [CODEX_HANDOFF.md](CODEX_HANDOFF.md) | Codex 自主开工指令 |
| [PROGRESS.md](PROGRESS.md) | 短进度、确切 SHA、证据等级及下一步 |

本目录为下一阶段权威设计；既有 `AGENTS.md` 中的历史“仅 Chrome/ChatGPT、不得扩目标”不限制这次用户明确授权的目标。其数据保护、源准入、独立审查和发行要求继续有效。1.0.7 的现行任务仍由 #118 / #119 管理。

## 基线与不确定性

本轮已审 `main=9fd8ad15fca043915069904113e5fb67d82b4948`、PR #117 head `cf697d7ece7e052ccaa2ea5c4bca42a16fd0ebdf`、PR #119 head `f27c2473891bd37ac4227ca424c1bb2c4ce56c41`。PR #119 最新评论还报告 build 49 的本地产品提交；详情及可访问性见基线审查。**本规划分支基于 main，仅承载文档；绝不能把它当后续实现代码基线。**

实施 W0 必须重新读取 #119 头、收口报告、评论、最终产品提交及 main。实现应以包含 1.0.7 收口成果的实际 main 开始；未合并时只推进可隔离的契约、测试和技术验证，不改写 #119，也不从 1.0.5 重做附件链路。

本轮研究环境为 Linux，未运行 macOS 原生 App、Safari/Brave/Firefox 或真实已登录 AI 网站。网页标准和官方文档证明的是能力依据；新矩阵没有任何产品实测 PASS。不能把本文、模拟回归或 CI 视为 Safari/跨 AI 已完成。

## 发布与部分交付

完整目标完成要求 16 个核心格在同一最终签名候选通过真实登录草稿验收。个别障碍不停止其他工作包。若核心格经过明确技术验证仍无法完成，可以交付准确标明缺口的候选和已通过组合；**不得称完成全部核心范围、关闭 #120 或静默缩减目标。** 公开发布必须满足既有发行流程及当前实际授权，规划本身不授权立即发布。
