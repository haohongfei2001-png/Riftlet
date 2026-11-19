# Edge × ChatGPT · 两笔真实存储写入

2026-11-16，隔离的普通签名 Riftlet App 在同一已登录的 ChatGPT 临时草稿中输入了系统截图 605 和 606。两张图均取得独立的服务端存储回执，606 还取得了 ChatGPT 对同一文件的最终处理回执。被测包的两条本地操作均为 UNKNOWN，数据库中各有 0 条 START。商业组合验收保持 INCOMPLETE。[网络证据](service.json) · [产品回执](pair-audit.json) · [持久状态](durable-state.json)

| 证据 | 605 | 606 |
| --- | --- | --- |
| Riftlet 原 PNG（字节） | 4,514,903 | 4,512,373 |
| 原 PNG SHA-256 | `d172158b5725f6a1df58a840d594f58fb10fa25c0cbd606a81127824e715f691` | `6b363c8891603ce479e98055c71f3e40d797f024d09166687c6d818122a16306` |
| 同一次文件创建声明与实际 PUT Content-Length（字节） | 4,449,773 | 4,449,635 |
| 实际发送时间（UTC） | 13:07:27.183–13:07:48.942 | 13:14:44.352–13:14:53.527 |
| 原操作的中间进度样本落在对应发送区间 | 24 / 24 | 30 / 30 |
| 存储写入 | HTTP 201，响应含 ETag | HTTP 201，响应含 ETag |
| 同文件处理响应 | HTTP 200，缺响应正文，终态 UNKNOWN | HTTP 200，逐文件 `started` → `file_ready` → `completed` |
| App 自身 START / 最终完成 | 0 / 0 | 0 / 0 |

每张图的系统来源、SHA、资产、操作和单次文件输入都经产品记录核对。两次创建请求各带原操作的唯一文件名。创建响应分配的存储地址在去除查询参数后，与各自的 PUT 唯一匹配。处理请求分别带回同一服务文件 ID 和同一文件名。服务实际传输的内容长度比原 PNG 分别小 65,130 和 62,738 字节，原 PNG 在服务端的逐字节往返尚未得到验证。[逐项关联与时间](service.json)

两次实际鼠标事件相隔 439.076 秒，各在自己的输入窗上收到 10 条原生与产品回执。两次操作的进程、窗口、标签、文档、编辑器和草稿代次相同。606 输入后，原正文、14 个 UTF-16 单元的选区、3 个原有附件和两张新图片仍在，五个图片标签各出现一次。编辑器未聚焦，草稿未发送。[605 点击](605-first-post.json) · [606 点击](606-first-post.json) · [最后一次草稿读回](606-after.json)

快速测试中两个发送器相隔 271.363 ms 启动。第二个在投递前返回 `unexpectedMapAssets`。该时点没有保存命中区域快照，无法进一步判断哪一项校验失败。确认没有投递保留标记或数据库操作后，606 才收到首次真实鼠标点击。保留 trace 的两个窗口之间缺 2,330 个序号，605 的样本 36–410 缺失，两笔操作的尝试次数均为 1。[投递前停止](606-rapid-prepost-stop.json) · [原生 trace 哈希](app-source-hashes.json)

该次签名包来自 `285389696de110f076ba60d2e8a1a6fbe98c6b3e`，可执行文件 SHA-256 为 `39b9cd983441533a75a171fe56432de903a9c16e93cd4d367577cc4fd9aaa894`。Edge DevTools 仅用于事后验收。完整原始导出限本机专用目录保存，共 498 条记录，31,611,003 字节，SHA-256 为 `4fddbe800991bb3f68ef632b08085f7175344d0aaca47e8d8bda2e37a0a99372`。两次另存副本都截断于首个 PUT，均未用于最终统计。公开材料只提供脱敏投影、哈希与复算器。[离线复算器](verify-service.py) · [运行包](../edge-first-input-20261115/signed-package-receipt.json)

原始测试材料的保管者可在本机运行 `python3 -B verify-service.py /path/to/complete-network.har /path/to/pr69-network-20261116`，输出应与 `service.json` 逐字节一致。两份公开的 App trace 可分别用 `gzip -dc` 解压并交给仓库原有的回执核验器。[605 trace](605-trace.jsonl.gz) · [606 trace](606-trace.jsonl.gz) · [回执核验器](../edge-native-receipts-20261115/tool-sources/receipt.py)
