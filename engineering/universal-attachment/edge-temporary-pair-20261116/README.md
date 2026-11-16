# Microsoft Edge × ChatGPT Temporary 草稿双图实测 · 2026-11-16

普通签名 Riftlet App 在同一个隔离、已登录的 Temporary 草稿中分别输入两张真实系统截图。两次均从实际微图进入，各有匹配的鼠标按下、抬起、输入窗口及产品选择回执。第二张输入后，03:39:34Z 的独立 AX 读回确认原正文、14 字符选区、原附件和两张新增图片全部保留。两张图的产品 START 均未确认，最终结果均为 UNKNOWN。[逐项结果](acceptance.json) · [延迟 AX 原件](pair-late-preservation.json)

运行源码 `285389696de110f076ba60d2e8a1a6fbe98c6b3e`，准入提交 `932f278f3412fd3158f01907a5a484ac9c235fa2`。本轮恢复同一个签名包，实际可执行文件 SHA-256 为 `39b9cd983441533a75a171fe56432de903a9c16e93cd4d367577cc4fd9aaa894`。五项必要 CI 的适用源码与当前运行包的来源见上一个检查点。[包身份](../edge-first-input-20261115/signed-package-receipt.json) · [CI 复核](../edge-first-input-20261115/ci-verification.json) · [实际进程与权限](runtime-after-app-authorized.json)

| 原操作 | 第一张 · 602 | 第二张 · 603 |
| --- | --- | --- |
| 系统截图 SHA-256 | `408c21d6637a02579d1aa71ef77a0c1f643a07313be04f715ff73754718ae1e9` | `ecc9f3ffac8751da85415d55da84d1388ff07cbc092a1b06d835fa2dfb1ad115` |
| 原图字节 | 4,512,568 | 4,515,606 |
| Riftlet 输入窗／事件号 | 816／9629 | 819／27943 |
| 绑定用时 | 88.461042 ms | 78.561250 ms |
| 保留的原操作观察／中间进度样本 | 170／35，2%–95% | 34／24，2%–96% |
| 产品 START／最终完成 | 0／UNKNOWN | 0／UNKNOWN |

两个操作的进程启动身份、窗口、标签、文档、composer 与 draftGeneration 完全相同，每次点击都有独立的 clickBindingID。每图 18 个 chunk 组成一次文件输入，captureTarget、validate、begin 和 commit 各完成一次。每图有 2 条 App、7 条原生边界和 1 条产品选择回执。两次实际鼠标 down 相隔 85.677551 秒，快速连续点击仍待运行。[独立核对](independent-audit.json) · [首图回执](temporary-01-1-receipt.json) · [第二图回执](temporary-01-2-receipt.json)

两张图都在第 2 个样本出现已加载预览。第一张中间进度最高观测至 95%，两次采样窗口间有缺口。第二张可见 96% 后的 100% 及进度消失。两个操作全部保留为 `inputTriggered`，每图 `attempt=1`、`dispatch_exclusive=0`。首图观测曾在序号 67 记下 `observe / invalidTarget`，随后继续观察原操作。旧 UNKNOWN 的目标、次数及状态与恢复前相同。隔离库在这两次输入后有 8 个资产、3 个操作、0 条 START。[原操作状态](readonly-operation-state.json) · [完整去重 trace](deduplicated-product-trace.jsonl.gz)

四次 AX 前后检查都保留正文、选区和基线。第二张的 34 个观察样本全部保留原来的 4 个基线 DOM 节点，包含原附件和首图。延迟 AX 检查时编辑器没有焦点，原附件、602、603 的对应图片各有 1 个，界面上可见进度数为 0。服务端字节和最终完成仍缺独立回执。11 月 15 日普通草稿配额弹窗后取消选区的失败继续单列，当前 Temporary 场景的保留结果只对该场景成立。[延迟 AX 原件](pair-late-preservation.json) · [普通草稿历史失败](../edge-first-input-20261115/README.md)

基线首次截图的元数据解析失败，随后从同一原文件复核了截图属性，原窗口回执缺失。用官方预览下载的基线 PNG 与原图大小和哈希不同，网络来源未确认。默认 sandbox 的一次运行列表返回空且 AX 权限不可见，正常宿主上下文随后读到精确的 Edge 与 Riftlet 进程、二进制哈希及已授权状态。[基线恢复](capture-baseline-recovered.json) · [下载比对](baseline-download-file.json) · [默认环境](runtime-after-app.json) · [正常环境](runtime-after-app-authorized.json)

独审逐一核对 188 份累计快照，按诊断 session 与 sequence 合并成 501 行，无冲突。序号 138–296、首图样本 44–121 在两个采样窗口之间缺失。公开 trace 可用 `gzip -dc` 解压后核对 SHA-256。原始索引含 211 份记录的名称、字节数和哈希。另存的延迟 AX 读回晚于独审报告，原件 SHA-256 为 `12d24398a19f5e99d7a9e4c1c609ea24f05bc315d1a6f440ccd742a441de93e6`。[原始索引](source-manifest.json) · [公开副本与脱敏清单](raw-evidence-manifest.json)
