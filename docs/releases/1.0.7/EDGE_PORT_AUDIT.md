# 1.0.7 的 Edge 代码筛选与验收入口

[Issue #118](https://github.com/haohongfei2001-png/Riftlet/issues/118) 是本次开发与验收规范。#119 原基线为 42。实际接续的 #117 head 是 `cf697d7`，含 44 的同卡错误修复；44 的真实服务验收保留原状态。以下按 #69（`a14344c`）相对共同祖先 `9fd8ad1` 的生产文件逐项归组。表内为筛选依据，实际纳入范围以 #119 diff 为准。

| 审查范围 | 移植裁决与逐文件索引 |
| --- | --- |
| 原生浏览器接收端 | 核对并选择性移植进程出生身份、窗口和标签的精确 Apple Event、首次授权与显式检查、脚本开关以及有界执行。传输服务于现有的一次输入。<br>`ApplicationHostAdapter.swift`, `ApplicationWebExecutor.swift`, `ChromeActiveTabDescriptor.swift`, `ChromeAppleEventsExecutor.swift`, `ChromeApplicationHost.swift`, `ChromeClickDocumentWitness.swift`, `ChromeCommandRouting.swift`, `ConversationClickRouter.swift`, `EdgeAppleEventsExecutor.swift`, `EdgeApplicationHost.swift`, `EdgeAutomationPermission.swift`, `EdgeClickAppleEvent.swift`, `EdgeJavaScriptEvent.swift`, `EdgeProcessIdentity.swift`, `EdgeWebExecutionDriver.swift` |
| 正式网页及回执 | 在 44 的单一网页程序上逐项核对。正式内容证明需要原操作、原图、原草稿、可见成员与实际输入；旧分支只为临时草稿给出的回执不可直接登记到普通草稿。逐版本实验脚本不装入产品。<br>`AttachmentEntryDiagnostics.swift`, `AttachmentObservation.swift`, `BoundedDiagnosticTrace.swift`, `ChatGPTWebPageProgram.swift`, `EdgeDraftAttachmentAcceptance.swift`, `MainWorldCommandEnvelope.swift`, `MainWorldCommandRelay.swift`, `NativeMacAttachmentExecutor.swift`, `ObservationNormalizer.swift`, `OrdinarySystemScreenshotScope.swift`, `chatgpt-web-20261027.js`, `edge-draft-content-owner-v28.js`, `edge-encoded-preview.js`, `SystemScreenshotCandidateAdmission.swift`, `SystemScreenshotObservationJournal.swift`, `WebAttachmentAdapter.swift` |
| 现行产品契约 | 以 44 保留的事实、局部处置和数据兼容为准。需要交换的只有接收端身份、权限和原操作续查路径；不能导入另一套生命周期。<br>`OrdinaryCaptureConfiguration.swift`, `ProductStatus.swift`, `RiftletMain.swift`, `SystemScreenshotCandidateConfiguration.swift`, `Models.swift`, `ReceiptPolicy.swift`, `TransferCoordinator.swift` |
| 旁路与测试控制 | 独立评估用途。通用网站、辅助功能文件选择器、托盘布局及历史验收 hit map 均超出普通 Chrome/Edge × ChatGPT 点击入口；留在 #69 供历史取证。<br>`AXPickerFileHandoff.swift`, `AXPickerInspection.swift`, `AttachmentTransport.swift`, `ConversationSurfaceAdapter.swift`, `ConversationSurfacePageProgram.swift`, `EdgeConversationInspection.swift`, `EdgeConversationPicker.swift`, `EdgeNativeDraftProbe.swift`, `EdgeOwnedFilePanel.swift`, `NativePickerFileDelivery.swift`, `NativePickerVerifiedFile.swift`, `ConversationSurfaceProbe.js`, `AcceptanceHitMap.swift`, `IsolatedProductCaptureLocation.swift`, `RiftPanelController.swift` |
| 历史程序副本 | 历史 #69 的试验或兼容资源保留在原提交；没有 1.0.6 原登记依赖这些 Edge 历史文件。继续支持 1.0.6 的原登记和只读检查。<br>`chatgpt-web-edge-v24.js`, `chatgpt-web-edge-v26.js`, `chatgpt-web-edge-v27.js`, `chatgpt-web-observe-product-v18.js`, `chatgpt-web-observe-product-v19.js`, `chatgpt-web-observe-v17-main.js`, `chatgpt-web-observe-v17.js`, `chatgpt-web-observe-v18.js`, `chatgpt-web-observe-v19.js`, `chatgpt-web-observe-v20.js`, `chatgpt-web-observe-v21.js`, `chatgpt-web-observe-v22.js`, `chatgpt-web-observe-v23.js`, `edge-encoded-preview-v26.js`, `edge-encoded-preview-v27.js` |

#69 另改了 Info.plist 与中英文 InfoPlist.strings；应逐条合并权限理由与版本，保留 1.0.6 的签名和产品配置。#69 与共同祖先之间 Package.swift 和 packaging 无变更；最终资源、双架构依赖和内嵌二进制的审计必须以实际 1.0.7 App 为准。

## 实机记录口径

- G1/G2 使用最终签名包和独立资料目录。对 Chrome 和 Edge 分别在登录会话做冷、暖单击及三组双击。每轮使用原生系统截图的独立编号和 SHA-256，每图只点一次。记录鼠标按下、原操作创建、可见回执、退场时间；核对原草稿文字和选区摘要、先前及新增附件数、未发送状态。以鼠标按下间隔判断两秒，以每图点击至接收的毫秒数算中位数、nearest-rank p95 和最大值。Edge 必须覆盖临时及普通已保存聊天。没有服务端终态时记录 UNKNOWN。
- G3 在隔离用户中使用两个浏览器、两个窗口和独立无个人内容的草稿；在绑定后切换、重建页面或关闭原实例。记录是否落到其他目标及文件输入次数。正常系统权限界面能完成的拒绝/再允许在同期测试；保持正式用户的现有授权。
- G4 用已注明历史状态的隔离库，记录操作、公证前后的源文件 SHA-256、唯一副本、文件移动与废纸篓找回；新明确点击单列为新操作。断开测试客机网络可制造真实服务失败，必须看到正面回执后同卡明确失败及本地找回，才能对该路径作判断。
- G5 用同包记录双语、外观及最小窗口；一千张已知 PNG 在普通 App 中核验及并发收录时，记录收录数量及耗时、CPU、RSS 和文件增量。受控组件基准单列。
- G6 从公开 31 建独立升级前快照；真实 Sparkle 私有签名清单升级与手动替换分别使用可恢复的基线，比较运行中 executable 与最终 DMG、资料、旧回执和偏好。公开通道只读核验。CI 的 ARM64 和 Intel 结果绑定实际 PR head。

#69 对默认 Edge 临时草稿的真实双图记载鼠标间隔 517.873 ms，产品回调间隔 505.033 ms。逐图 receipt 的含义是该草稿接收本次图像，最终状态为 UNKNOWN。旧 QA 脚本固定了旧版本、特定草稿与孤立测试库，不能用重放或复用旧结果取得 1.0.7 验收。[历史逐图记录](https://github.com/haohongfei2001-png/Riftlet/blob/a14344cb9ae9d29c94a94aa4eac341eca4dc269c/engineering/universal-attachment/edge-unified-default-20261118/build31/draft-handoff-v29/REPORT.md)
