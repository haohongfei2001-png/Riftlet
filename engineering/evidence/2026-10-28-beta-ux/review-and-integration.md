# 审查与 Pro 合流提示

源码 `fa74f3c68f05ab4eaccfc24e2f39c0177289ddb3` 在独立分支，仅八个 App/UI/helper/测试文件。非作者 web_safety 对最终 diff 静态复审 PASS；它没有编写这些产品源码。ProductStatus 实现由 native_gui 独占，App/UI 接线由 root 完成。

复审曾发现并修复：

1. prepared 快照可能在真正输入后才被替换；不能持续宣称“尚未上传”。最终改中性 preparing，只有未开始提交的 FIFO 项用 waiting。
2. 跨 await 迟到反馈可能覆盖同图的新选择；最终以 selection owner 与 visibilityRevision 复核后写入。
3. 清旧 prepared 状态不能删除新 FIFO waiting；最终按不同文案精确清理。
4. mouseDown / AXPress 清反馈必须同时清 input island tooltip 和 AX；最终经 setFeedback 统一更新。

没有修改 Core 锁、dispatchIntent、唯一输入、开始/完成、安全失败准入、浏览器程序或几何命中。静态审查不替代 GUI；CI 成功与人工日志范围分别列出。

## 与最新正式 Beta 的冲突

只读 `git merge-tree` 比较 fa74f3c 与 b4bcfa41，发现 **一个文件、两个冲突块**，均在 `Sources/RiftletApp/RiftletMain.swift`。没有修改工作树或正式 ref，也没有将冲突树当作可运行版本。

- selection catch：保留本补丁的 owner/revision 保护 `feedback(...)` 及 `ProductStatus.clickFeedback(error)`；随后保留正式 Beta 的 `self.feedback.diagnostics.record(.selectionRejected)`。不能退回不带原选择校验的 setFeedback，也不能删除 Feedback 诊断。
- refresh 的 render(snapshot) 后：保留本补丁完整 prepared/cancelled 展示投影；同时保留正式 Beta 的 `feedback.assets(snapshot)`、`feedback.operations(successful + unresolved)` 和 uiProjectionDeferred 记录。按原 refreshRequested 防旧快照边界执行。

其他正式 Feedback 初始化、菜单、退出和错误诊断保持。不要整文件覆盖。正式工程固定来源审计会因获授权 App/UI 改动而需要新的来源/审核记录，由 Pro 在组合中处理；本轮不删除审计或代改其基准。

本轮 CI 只认证 fa74f3c；b4bcfa41 窗口实测只认证未加入本补丁的正式组合。**两者合流后的完整 CI 仍由 Pro 执行**。

## 未作为本轮修复的静态风险

native_gui 对 b4bcfa41 Feedback 接线只读复审：正常开关不修改截图队列或复用旧 ACK。极快启动后立即退出可能在 initialization 未完成时跳过 clean marker；主 Feedback 关闭也不会连带关闭独立预览窗。两项未现场复现，不记作 FAIL，不扩展本轮代码范围；交反馈负责人后续有界核实。

## 最终公开证据复核

web_safety 对本目录八份文件与执行板入口完成只读复核，**PASS，无必须修正项**。三组源码、人工/软件来源与计时边界一致；26 项私有证据的字节数及 SHA-256 逐项匹配。JSON、链接与差异格式检查通过；公开内容没有原始图片、正文、目标/会话、私有路径或数据库。原始素材仍只在本机保留。
