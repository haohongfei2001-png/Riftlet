# Edge × ChatGPT 普通 App 连续双图验收

2026 年 11 月 17 日，在同一个已登录的隔离 Edge 临时草稿中，普通签名 Riftlet App 收到了间隔 **398.130 毫秒**的两次微图点击。每张截图各产生十条可归属到自身输入窗口的原生和产品回执，各执行一次文件输入，分别取得持久 START。原位置的 14 字符选区、原正文和预置图 614 完整保留。两张新图在原草稿各出现一次。商业组合仍是 **INCOMPLETE**，两笔上传的最终业务处理状态均为 UNKNOWN。[产品独审](independent-product.json) · [逐文件服务独审](independent-service.json)

| 实测项目 | 612 | 613 |
| --- | ---: | ---: |
| macOS 系统截图原件 | 1,405,603 字节 | 1,406,330 字节 |
| 原件 SHA-256 | `2c2dccd0092652a9cb39a7d5b0601d076192547c4a46dc214a1b20b9d3decdce` | `046cba3f086c25a8bd7fcc1e7ec4d1e11e7c9f480ba7ce11349d0df790b1b410` |
| 同文件进度触发产品 START | 10.630% → 11.811% | 5.906% → 15.354% |
| START 至产品记录吞噬开始 | 4.429 毫秒 | 3.730 毫秒 |
| 创建声明与实际存储 PUT 长度 | 1,386,370 字节 | 1,386,418 字节 |
| 存储回执 | HTTP 201，含 ETag | HTTP 201，含 ETag |
| 落在该文件实际发送时段内的正数进度样本 | 3 / 3 | 7 / 7 |
| 服务处理响应 | HTTP 200，DevTools 记录 576 字节 | HTTP 200，DevTools 记录 576 字节 |
| 产品最终完成记录 | 0 | 0 |

源 PNG 与 Riftlet 私有导入副本逐字节相同。每次输入的唯一操作文件名出现在对应的服务创建请求里，分配的地址与后续 PUT 一一匹配。ChatGPT 实际发送的图片表示小于原 PNG。两个 PUT 的发送时段重叠了 9.632 秒。App 在第一笔文件输入返回后执行第二笔，第二笔 commit 发生在两笔 START 之前。[产品与网络投影](product-and-network.json) · [116 条连续 App 事件](pair-trace.jsonl.gz)

两份处理响应的浏览器记录均带 `net::ERR_ABORTED`。已清理 HAR 中没有响应正文，DevTools 的响应页也没有可读数据，EventStream 表未显示逐文件帧。后续两个会话准备请求各带原文件 ID，回应只有会话级 `ok`。此前的 606 才有独立的 `file.processing.completed` 原响应。完整 68 条 HAR 及其本机保全副本 SHA-256 均为 `1b0974cb48d123c0f13d2b76acaea951d02988a4693d66f63e1abed7f3596097`。[后续响应核验](terminal-projection.json) · [可复算的离线核验器](verify_terminal.py) · [606 原证据](../edge-service-pair-20261116/README.md)

本次点击前后读回同一进程、原生窗口、标签、文档、编辑器和草稿代次。选区起点为 61，长度为 14 个 UTF-16 单元，前后均未聚焦编辑器。独立核验覆盖全部 16 份隔离媒体、14 条既有资产在冻结列上的值、7 条既有操作及原 START。两笔新操作各有一次尝试。App 操作与完整 HAR 均没有聊天消息提交。上述证据使用软件投递的真实 AppKit 微图输入，[原始测试包](tested-package.json) 来自 `62ab4b2638f78926a92dd01a0942aa98e72a7614`，可执行 SHA-256 为 `31613ef46bd7551b14a808c03d2aba2f50a9b6c29d8ca6a9dda7d0bc47370a37`。

包含这份产品代码的 PR 提交 `514f7199ba988d634dc81a079b7dc7a27ab1b663` 首次执行的五项 CI 全部通过。ARM64 和 Intel 各实际执行 1,484 个 Swift 用例，受控浏览器与商业草稿的实测范围分别记录在原始报告中。[CI 独核](tested-514f719-ci.json)
