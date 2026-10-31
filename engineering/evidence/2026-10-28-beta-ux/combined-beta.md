# 统一 Beta 的限定窗口实测

运行 **b4bcfa41e8e237723b975d2a9a0059e955fa0c1f** 的完整 App：独立工作树，本机构建 32.86 秒，bundle 校验 PASS。macOS 27.0 (26A428)、arm64、Chrome 156.0.8078.73。沿用原候选数据根，以 `--system-screenshot-candidate --acceptance-trace` 启动，菜单实际为 `Riftlet REAL TEST`。本轮 fa74f3c 展示补丁尚未加入此组合，两个运行来源不可混称。

## 原生窗口

操作来源为 CUA/AX 与已授权 Apple Events 原生菜单操作，**不是物理鼠标**。

- 从真实候选菜单打开“反馈与建议”，显示服务尚未配置、当前不会上传；诊断默认未勾选。
- 两次编辑后“保存并关闭”→菜单重开，实际窗口文本分别保留。最终独立 Feedback 数据库有 63 个 ASCII 字符的测试草稿；reports / submissions / credential_intents 均为 0。没有按发送按钮。
- CUA 的非 ASCII typeText 和 select-all 未产生预期文字替换；本轮仅以读回的实际文本为基线。不能据此认定产品中文输入失败，也不能声称中文 IME 已验收。
- 反馈窗口打开/关闭前后，菜单仍是“隐藏裂缝”和“暂停收录”，没有因反馈改变开关。主动打开运行状态窗口，再执行隐藏：显示“7 张待显示，隐藏不改变收录”。随后恢复显示；最后正常菜单退出。
- 运行状态仍保留旧的“只有生成图证据/开始完成待准入”支持说明，与同窗口的新候选说明矛盾。本轮 fa74f3c 的 ProductStatus 修复针对这一实际缺陷；没有改正式组合工作树。
- 尚未验证首次安装引导、权限弹窗、IME、VoiceOver 实际朗读、诊断预览关闭和极快启动后退出。源代码非作者审查没有发现反馈主动修改截图队列/权限/隐藏；静态风险不冒充现场 FAIL。

## 目标恢复与安全边界

窗口操作期间有前台离开 Chrome 的 activation 记录，捕获为 `browserNotFrontmost`、armed=false；之后重新捕获。日志没有 Feedback 窗口名称事件，不能把每次 activation 逐一归因到某次反馈开关。

一次有独立命令起止标记的返回 Chrome 操作，后续首次 `publishedNewTarget` 的时序：

| 边界 | 耗时 |
| --- | ---: |
| 操作命令开始 → 返回 | 219.645 ms |
| 操作命令开始 → ACK 发布 | 276.959 ms |
| 操作命令返回 → ACK 发布 | 57.314 ms |
| 该捕获任务启动 → ACK 发布 | 84.051 ms |
| 同 request 的被动权限检查 | 33.951 ms |
| nativeValidated → MainActor 发布 | 1.590 ms |
| adapterValidated → MainActor 发布 | 0.428 ms |

该 ACK 与此前最后发布的 ACK **同 host epoch**，但目标摘要与有效 capture request 不同。不能称作新 epoch，也不回填命令/原点击。当前页独立只读检查存在唯一中文普通线程 editor，documentFocused=true、editorFocused=false；这不是截图点击测试。

最早两份诊断使用旧 `#prompt-textarea` 选择器而得到 0；正式 v13 普通线程使用 contenteditable/role/中文 aria-label，后续对应检查才得到 1。旧探针的 0 不是产品没有 composer 的证据。前后附件计数也不能证明同一原草稿内容保留；本轮未重做上传或正文/选区/附件保留验收。

这些记录只说明组合 App 在本次观察中能够重新得到完整目标，不给出“用户正常操作拒绝率”或 Chrome 冷启动、睡眠/重启、即时切聊天点击的结论。原始点击之前无 ACK 的限制继续保留。

## 没有新增输入

原生桥全程仅 captureTarget 与原操作 observe，未记录 begin/chunk/commit；SQLite operations 始终为 5，upload_starts 始终为 1。一次来源未归属的 mouse selection 命中已有 UNKNOWN，输入阶段未新增，不能把它算作主动上传或物理 PASS。核对后临时隐藏并恢复，未清除历史。

本轮检查结束正常退出，不留新上传任务。原 8 个系统原件与私有文件全部保留。后台原操作的观察字段可更新，这与重新输入不同。详见同目录数据保持摘要。
