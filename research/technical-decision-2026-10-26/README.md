# Riftlet｜关键技术裁决与真实验证包

日期：2026-10-26  
研究基准：haohongfei2001-png/Riftlet main **3c988ddaff2922594fa6c6ed7d0fe24bad9d7ada**。交付前复查 main 仍为此提交。

本包是对上一轮研究的增量裁决，不是正式 App、浏览器扩展或产品决策变更。未修改 GitHub，未接触私人聊天，未发送消息，未改变系统设置，未运行 macOS GUI。

## 建议阅读顺序

1. **01_TECHNICAL_DECISION.md**：上传路线、严格回执、推荐架构、真正的交付障碍和独立裁决。
2. **02_REUSE_MAP.md**：完整固定提交、模块路径、复用边界、许可和适配成本。
3. **03_MAC_VALIDATION.md**：下一轮一次准备、一次 Mac 会话的验证规程及准入条件。
4. **04_EVIDENCE.md**：本轮真正运行的四项离线反例、证明范围和复现方法。
5. **SOURCE_MANIFEST.json**：固定源码及官方资料索引；evidence/oracle/source-index.json 含实际打包源码的 Git blob SHA 与 SHA-256。

## 本轮最重要的变化

- **纯原生网页版路线不能排除。** Chromium 源码确认：AppleScript 可以针对固定标签页，在独立 JavaScript world 中执行代码。这给“原生传文件＋DOM 观察”提供了具体路径，不必先退化成盲目模拟粘贴。
- **Oracle 不能直接充当严格成功判据。** 本轮实际执行其固定源码及上游 FakeDOM，复现一项身份关联反例和三项完成判据反例。它也明确拒绝 Work composer。
- **浏览器扩展有工程优势，但必要性尚未证明。** 两条网页路线应共享附件 adapter，并使用同一组真实测试决胜；扩展并不会自动获得 ChatGPT 的正式 READY API。
- **找到更具体的 READY 调查目标。** OpenAI Codex 源码把存储 PUT、file_id 最终确认分开。可以调查网页自己的上传是否存在可关联的最终确认，但存储成功还必须关联回原草稿；不能直接照搬私有接口。
- **官方草稿追加能力确实存在，目标绑定仍不满足本产品。** MCP App 的 send:false 有草稿语义；global entrypoint 的 active 指它自己的 thread，并非任意当前聊天。没有从此推出无界面原生注入能力。
- **可复用代码应大幅缩小。** 优先目录 watcher、图片完整性小函数、非激活窗口骨架；排除大图库、私有 CGS、持续指针轮询及通用自动发消息逻辑。
- **透明像素值得重新验证。** Apple 的窗口命中规则明确跳过给定点透明的窗口；单透明画布可能省去逐图窗口或全局指针轮询。实际图层、阴影和动画仍须真机验证。

## 证据状态

| 状态 | 本包中的使用方式 |
| --- | --- |
| VERIFIED | 本轮实际运行所得结果；目前仅限 Linux/Node 离线 Oracle fixture，绝不表示 ChatGPT 上传已通过 |
| SOURCE-VERIFIED | 固定真实源码中的具体实现已读到；官方接口文档另明确标注，不冒充目标运行测试 |
| INFERRED | 从源码／接口得到的候选实现或架构建议 |
| NOT_TESTED | 当前 ChatGPT 页面、新版／Classic Mac 的具体输入、关联、READY 等尚无真机证据 |
| BLOCKED | 本轮缺少真实 Mac GUI 条件，不能取得该平台运行证据；不等于产品不可实现 |

## 离线实验

在支持 node:module.stripTypeScriptTypes 的 Node 环境，从本目录运行：

~~~sh
node evidence/oracle/offline-adversarial.mjs
~~~

本轮运行环境是 Node v24.22.1 / Linux。无需 npm install、浏览器、网络、凭据或 ChatGPT。脚本读取随包的原始 Oracle 源码，将结果写到同目录 offline-adversarial-results.json。上游源码保留 MIT LICENSE；打包的七个源文件已校验与固定提交字节一致。

这个实验只能证明那些判断条件不够严格，不能证明真实 ChatGPT 当前会生成同样的 DOM，也不能代表整个 Oracle 上传管线在生产中发生这些错误。
