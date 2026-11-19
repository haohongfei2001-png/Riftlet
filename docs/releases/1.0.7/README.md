# Riftlet 1.0.7 — Chrome / Edge 原生附件整合

> 2026-11-19：这是**集成工作分支的启动说明**，不是完成的 1.0.7 产品、候选验收或发布证明。**唯一任务定义与验收裁决见 [Issue #118](https://github.com/haohongfei2001-png/Riftlet/issues/118)**。

## 基线与出处

- 集成分支创建于 [1.0.6 PR #117](https://github.com/haohongfei2001-png/Riftlet/pull/117) 的 `b40dcb099c69a8c781348a84595c47db76043988`，完整保留 build 42 的截图治理、原操作恢复和防伪 START 语义。后续先确认 #117 变更情况，不要从旧 main 覆盖这里。
- Edge 候选见 [Draft PR #69](https://github.com/haohongfei2001-png/Riftlet/pull/69)，核查时 head `a14344cb9ae9d29c94a94aa4eac341eca4dc269c`。默认 Edge 已登录 ChatGPT 临时草稿的快速两图“实际接收”已通过；最终服务处理仍 UNKNOWN，已保存聊天未同等实测。
- 两套分支存在 17 个重叠修改文件，#69 含大量历史证据。禁止直接合并 537 个变更文件；只移植必要 Edge native host、脚本、权限和对应有效测试，共用核验和数据模型采用 1.0.6 最新契约。
- 截至本分支建立，**公开产品仍为 1.0.5（31）**。不强制先上架 1.0.6：若 1.0.7 先通过独立验收，则执行 1.0.5→1.0.7 的真实升级/回退保护验证并完成统一发行。

## 产品体验不可退化

原生截图 → 托盘微图 → 用户单击 → 点击时前台 Chrome/Edge 的原 ChatGPT 草稿。零自动发送、零重复输入、不改选后来的标签、保留文字/选区/原附件。START、attachmentAccepted、READY/服务处理终态不可混为一谈；UNKNOWN 保持未知。错误只能检查原操作或经用户独立新点击再次附加。

正常使用不添加浏览器选择、扩展、调试模式、额外对话框；必要 Automation/JavaScript 授权按需引导。原媒体、历史、升级、双语和既定托盘 UI 不得退化。

## 执行与交付

按 Issue #118 的 A–E 分包与 G1–G6 验收。Core/Adapter/App 共享文件由一名集成人收口，及时提交 SHA 和有意义的回归证据。只读审计与资料库操作使用隔离数据；不在公开 Issue/PR 写入私有截图、账户 URL、身份令牌或 ChatGPT 草稿正文。

最终提供可审核的实现 PR、完整最小测试矩阵、真实 Edge/Chrome 同包回归、签名公证 universal DMG、SHA-256、明确的通过/NOT_RUN/BLOCKED 与公开发布裁决。在此之前保持 Draft，不修改正式官网、公开 Release 或 stable feed。
