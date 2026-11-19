# 原处理响应的离线诊断

606 的完整普通 DevTools HAR 中，同原操作文件名 → create 的文件 ID → 唯一分配地址上的 PUT 201 → process 的文件 ID/文件名相符。process 第 174 行保存了完整 576 字节正文（SHA-256 `4d24602342422c30df68389bc2fa06d19891589a93e84c27d0a4ac1a2c275744`），是三行**裸 NDJSON**：`file.processing.started`、`file.processing.file_ready`、`file.processing.completed`，各为同一文件。它没有 SSE `data:` 行，尽管 MIME 是 `text/event-stream`、类型是 `fetch`。原始正文及文件 ID 不在此目录。[实际投影](original-606.json)

使用下附官方 DevTools 解析器文本，在 Node 中将这份原正文按整段、逐字符、两段输入，均得到 **0 个 SSE 事件**；独立中性 SSE 正例正常产生事件。此为公开解析代码的离线执行，不是当前安装 Edge 的二进制回放。正常 EventStream 视图因此不是这种裸 NDJSON 响应的可靠读回方式。这个结论解释的是可复现的格式限制，不能证明其他缺正文响应具有同样内容。[复现结果](validation.json) · [来源及采集界线](source-pins.json)

612/613 与 625 的原 HAR 均能重新验证同文件 create/PUT/process 链，MIME 相同、各声明 576 字节，但原文未保存，并有 `net::ERR_ABORTED`。它们的格式和处理终态保持 UNKNOWN；不能按长度补出 606 的事件，也不能将 606 的服务器事件写进任何其他操作或产品完成回执。[612/613](original-612-613.json) · [625](original-625.json)

[Edge 官方文档](https://learn.microsoft.com/en-us/microsoft-edge/devtools/network/reference#analyze-events-in-a-stream)提供正常 Network 的 EventStream 与 Response 视图。后续仅在另获授权的新原操作中，已绑定原文件名和文件 ID 的请求应优先被动读取 **Response** 原文，再以正常导出的同 ID HAR 交叉核对。未捕捉时仍是 UNKNOWN。当前公开 [RequestResponseView 源码](https://github.com/ChromeDevTools/devtools-frontend/blob/main/front_end/panels/network/RequestResponseView.ts)对 failed 请求显示无响应数据；因此早读仅是有限的观察机会，不保证事后恢复已丢失正文。没有标准公开页面 API 能无中生有地恢复这份历史 fetch 响应。本次没有重新调用端点、读取 Cookie、刷新页面、修改 fetch/响应、启用远程调试或操作浏览器。

复算器只支持已封存的三组原件哈希，采用既有已提交的结构化偏移解析器；无关正文不解码，允许字段外不输出。文件名、文件 ID 与完整分配地址仅在内存中核对，不打印。不得将此诊断工具接入产品作为完成准入。

```sh
python3 -B verify.py --case 606 --har /path/to/complete-network.har
python3 -B verify.py --case 612-613 --har /path/to/fresh-612-613.har.devtools
python3 -B verify.py --case 625 --har /path/to/original-624-625.har.devtools
python3 -B -m unittest discover -s . -p test_verify.py -v
```

25 个离线正反回归涵盖错误文件、重复键/事件、冲突终态、截断、非有限值、仅进度 100、缺 SSE 空行及裸 NDJSON 对比。正式的三个原件复算结果均与保存的脱敏输出逐字节相同。Node 需支持 TypeScript 类型擦除；本机使用 v26.8.2。第三方解析器保留 BSD 许可证，来源主分支版本未冒充安装版 Edge。

另见 [d3f096a 产品路径诊断](source-diagnosis.json)：JS、Edge 状态映射、专属 start-only profile/policy 和 Core 已 START 后的过滤分别限制 completion。App 的定时观察和 SQLite `verifiedReady` 持久化实现本身存在。该诊断没有修改产品源码、生产 profile、准入、历史 UNKNOWN 或本机数据库。
