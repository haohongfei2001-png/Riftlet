# Codex 自主开工指令

你是 Riftlet 本轮唯一实施集成负责人。按 [Issue #120](https://github.com/haohongfei2001-png/Riftlet/issues/120) 及本目录完成一个后续版本的跨浏览器、跨AI开发、测试、修复和交付。用户不继续做跨窗口协调或手动验收。自主做常规工程选择、分包、提交和纠错，不把实施重新抛回Pro。

## 先做

1. 读取 [README](README.md)、[实际基线](BASELINE_AUDIT.md)、[架构契约](ARCHITECTURE.md)、[工作包](WORK_PACKAGES.md)、[验收](ACCEPTANCE.md)，再按需读浏览器/Provider研究，勿一口气重读全部历史。
2. 重新获取main、#117、#118、#119及最新评论/真实RC报告。规划基线main仍为1.0.5；本轮已从初审f27补审到#119最新 **e852af3 / build49**（产品b431931），已实现轻量pin/异步回执/原进程缓存和原附件归属修复，必须继承。**实现从包含最终1.0.7收口成果的实际main开始**，不要以本规划分支的旧main做代码基线，不覆盖或改写#119。
3. 1.0.7尚未收口时，推进隔离的能力探查/fixture/接口准备；不改其正在验收的源码。基线具备后接续，一个实现PR，不另拆Safari版和多AI版。
4. 清点已授权macOS、实际浏览器、签名和合法登录测试会话。先找现有执行环境，不能把Linux fixture冒充macOS产品验证；缺环境只阻塞对应测试，其余继续。

## 施工约束

- 你亲自负责W1共用契约和共享代码。保留最终1.0.7的coordinator/store、原图、once fence、START/UNKNOWN、失败恢复。加入最小AdapterResolver、BrowserHost、ConversationProvider及版本化profile；不重造事务框架或复制16套实现。
- 冻结实际可编译接口及其commit后，并行W2浏览器、W3/W4 Provider、W5 QA，W6有限预研。其他worker只改独占目录/独立worktree；共享文件/CI/准入/版本/refs由你统一整合。
- 四核心浏览器：Chrome、Edge、Safari、Brave。Safari先做实际sdef/执行world/冷首次绑定/原稿身份验证；初始Safari26.2+并检查所需Navigation API。不能用Automation隔离窗口、Playwright WebKit或事后nonce自证原点击对象。Brave默认Shields和真实receiver须验证。
- 四核心AI：ChatGPT、Claude、Gemini、DeepSeek。同轮争取Kimi、国内千问、豆包、Perplexity，国际Qwen分开；Grok余量扩展。先一个新Provider在Chrome完整走通，再复用各Host；不能从API或帮助页臆造live selector。
- Firefox同轮有边界原型，仅在无扩展、无调试端口、原稿准确、一次输入和正面证据全部成立时升级正式第五Host。旧Safari epoch替代也单独验证；这些障碍不停止其他包。

## 不可退化的行为

系统截图→托盘→单击→点击时原浏览器原AI原草稿；不预选、不手工粘贴/拖拽/快捷键、不装扩展、不发消息。保留文字、富文本、用户新输入/IME、选区和旧附件。

每operation进入文件输入至多一次。输入前重新核验进程出生、窗口/tab、document/composer/draftEpoch、route/surface/mode及上传能力。固定一种已验证事件配方；一旦可能输入，不能换selector/事件/transport/浏览器重传。只观察原operation。正面START/原图接受才收起，服务ready另证；同卡明确失败恢复原图，用户决定是否新操作再次附加；旧UNKNOWN不重放。

## 自动验收与完成

- 用一个Browser×Provider×Case runner；L1模拟、L2真实浏览器fixture、L3正式网站登录实测分开。真正输入走普通签名Riftlet产品路径，禁止测试工具直接添文件替代。
- 每个核心格执行冷/暖首图、至少3组<2秒双图、原文选区旧图保留、新/保存草稿和切目标反例；独立oracle核对各图各一次及零发送。完整异常和性能门槛按ACCEPTANCE执行，失败样本不得删除。
- 在同一个最终签名候选完成核心16格和共享安全/恢复/升级门槛。使用既有B→G→H与五项CI；由非作者做真实独立审查，不伪造审批，不降低gate。Developer ID、公证、staple、安装/升级、ARM64/Intel及包hash事实分开记录。
- 有已获授权的发行步骤则按既有流程完成；没有公开发布授权则交付可安装可评审候选和最后具体发行动作。不要直接merge本规划PR或修改#119。
- 个别格技术或账号受阻继续其他任务；记录BLOCKED原因与最小复现。仅已通过组合可启用。核心16格没全通过就报告PARTIAL并保持#120打开，不能称全部支持；不隐式改为跨多个版本的计划。

## 持续交付与最终答复

每个有效工作包及时commit/push并更新精简PROGRESS：基线/接口/实现SHA、实际结果级别、下一项。源冻结后同包测试集中记录，避免每个状态又打包。上下文剩余约20%前保存复现命令、worktree与待办，续接按文件继续，不让用户重复交接。

最终给出：实现PR、实际支持表、同包逐格结果及缺口、独立审查结论、可安装包和hash、发布状态。不要只交代码或说“请你手动试试”。
