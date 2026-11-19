# Edge 只读诊断增量 — 2026-11-15

本目录记录受控页面、Swift 诊断读取器和独立源码审查。它不证明普通 Riftlet 双图进入商业 ChatGPT，也不开放 Edge 上传开始、最终完成或自动重传。当前真实运行包仍来自 `c3278c0bea1c03dc8cfc445fd7678a3de3467ae1`；这些新增文件尚未进入该包。[真实运行与重启证据](../edge-double-image-20261115/resumption.json)

新增 sidecar 在 `captureTarget` 时保留原编辑器、容器、文档、目标、文字和选区，只向原生侧输出固定的数字/布尔字段。这个快照不构成物理 mouseDown 时正文及选区的独立证据。Swift 只在可选诊断中读取它，拒绝未知字段、错误类型和超界值；不写入附件回执、持久化操作或输入决策。

独审发现的 P2 是真实缺陷：`composerForm` 的合法 fallback 可返回 `body`，诊断因此误读历史附件；候选内部的再次 DOM 查询也能绕过遍历预算。修复只接受明确声明的 form/composer，拒绝 body/html、历史祖先和无声明 fallback，进入子树前剪除历史、辅助区域及嵌套编辑器/容器。候选、预览和指标共用一次每遍 2,048 元素、512 候选的有界遍历；无法采样时返回诊断不可用，负责原文件的输入仍可独立执行。移入历史子树的旧节点不再被计作原附件保留。

| 检查 | 结果与范围 |
| --- | --- |
| 修复前定向回归 | 18 项中 4 项失败；[原始受控失败日志](before-scope-fix.log)保留，仅去除本机绝对路径前缀 |
| 修复后 Edge | [18/18](edge-final.log)，包括缺少诊断根时不阻断一次负责输入 |
| 普通页面及 Chrome 语义 | [159/159](page-regression.log)，受控 DOM 命令测试 |
| 历史原操作观察 | [61/61](legacy-regression.log)，不重放旧操作 |
| 实际 JS JSON → 编译 Swift 读取器 | [9/9](swift-reader.log)，4 种实际 sidecar 与 5 种畸形数据；不是 XCTest |
| 独立审查 | [无阻塞发现](independent-review.md)，[4 个独立探针](independent-probes.json)通过，包括 13 类被排除子树零新增内容读取、零诊断 DOM 改写 |
| 本机 XCTest | [NOT_RUN](xctest-availability.log)：Command Line Tools 无 XCTest；新增 5 个 XCTest 已进入原 adapter target，待最终 checkpoint 的托管 CI |
| 商业 ChatGPT / 普通 App 鼠标入口 | 本增量验证未运行；另见真实运行记录，不借用上表结果 |

五文件诊断增量独审时，整个 JavaScript `sample(op)`、Edge 原生归一化、历史 v17 观察资源、Chrome 执行器/路由、TransferCoordinator、App main 与 panel 均保持基线原字节。ready、100% DOM 进度或图片加载只作为未校准属性，仍不能产生 START/完成。五个源码文件的精确 SHA-256、原始/公开日志 SHA 和测试顺序见 [summary.json](summary.json) 与 [reviewed-source-hashes.json](reviewed-source-hashes.json)。独立源码 checkpoint 的最终准入仍由集成负责人在形成不可变 SHA 后记录；旧 `c3278c0` 的绿色 CI 不覆盖本增量。

其后另增 App main、panel 与 UI 测试的三文件[鼠标诊断可见性修复](mouse-diagnostic-visibility-followup.json)。旧运行包只有正数探针标记时才记录这些边界；新源码在显式启用开发诊断后保留无标记事件，并将缺失标记保持为 `nil`。严格发送端匹配未放宽。[独立追加审查](mouse-diagnostics-independent-review.md)无阻塞，六种无效标记仍被拒绝，额外无标记边界不能供给有效回执；[整个 App 构建](native-build.log)在临时目录通过（27.09 秒）。新 AppKit XCTest、真实原生投递及最终 CI 仍未运行/待记录。这不等于原始投递根因已经解决；上述两次真实投递仍观察各自原记录，不重发。

从仓库根目录可复现受控检查：

```sh
node --test Tests/WebPageProgram/edge-calibration-diagnostics.test.cjs
node --test Tests/WebPageProgram/acceptance-program.test.cjs Tests/WebPageProgram/legacy-web-observe.test.cjs
node engineering/universal-attachment/edge-calibration-20261115/independent-probes.cjs
```

读取器的生成器和编译源码也随目录保存。输出到私有临时目录，不读取用户图片、浏览器 Profile、聊天内容或账号凭据：

```sh
verification_dir=$(mktemp -d)
node engineering/universal-attachment/edge-calibration-20261115/generate-reader-fixtures.cjs > "$verification_dir/fixtures.json"
swiftc Sources/RiftletAdapters/AttachmentEntryDiagnostics.swift engineering/universal-attachment/edge-calibration-20261115/DiagnosticsScopeProbe.swift -o "$verification_dir/reader"
"$verification_dir/reader" "$verification_dir/fixtures.json"
```

此前本地 `implementation-report-final.json` 声称未增加历史扫描，该表述已被 P2 复现推翻；旧原件保留，本文与新结果记录修复后的范围。该范围只限定新增诊断，不表示原有应用代码从不执行更广的 DOM 查询。所有测试素材都是受控合成数据，公开记录不含真实截图、草稿原文或会话凭据。
