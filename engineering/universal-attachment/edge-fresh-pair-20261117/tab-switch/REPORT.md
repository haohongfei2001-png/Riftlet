# G7 切换标签后的两次实际拒绝

G7 普通签名 App 来源为 `62ab4b2638f78926a92dd01a0942aa98e72a7614`。本轮在已获授权的隔离 Edge 新 Temporary 草稿上使用两张新的系统截图。两次都是带独立标记的软件原生鼠标事件。原 App trace 第 157–187 条连续，两个输入各有十条匹配的系统及应用鼠标记录。没有重发。

| 新图 | 实际操作 | App 明确拒绝 | 持久化与队列 |
|---|---|---|---|
| 610 | 原草稿接收点击并选中，随后请求切到本次自建空标签 | 第 172 条在 `resolveSelection` 记录 `nativeSelectionChanged` | 0 新 operation、0 START，仍为 pending/visible |
| 611 | 空标签独立核准后点击另一张原图 | 第 187 条在 `resolveSelection` 记录 `pageRejected(PAGE_ROUTE_UNSUPPORTED)` | 0 新 operation、0 START，仍为 pending/visible |

两次 App 收到的 down 相隔 677.143 ms。610 的切换请求发生于原 down 后 104.422 ms、选择 callback 后 12.434 ms。请求到空标签核准为 89.556 ms。610 在请求之后、空标签核准之前 29.965 ms 拒绝。611 的 down 在独立空标签复核后 133.233 ms 到达。两图均有逐资产的显式拒绝，各自没有 setter、START 或吞没的记录。

冻结的原资产 16 项、操作 9 条、START 3 条和 16 份私有原图的字节均逐项一致。测试后资产增至 18，操作仍为 9，START 仍为 3。

## 原运行与后续草稿读回

原运行的恢复器报告已返回最初绑定的 native tab。随后组合检查返回 `boundFreshComposerChanged`，当时没有保存逐项草稿属性。原运行退出码为 3，原组合判定为 false，原始 outcome SHA-256 为 `8c432630e0e98bb4241a671c78524caac5d014247eafc8cbb0ab839595b3389c`。

操作者恢复同一窗口后，2026-11-17 08:46:10 UTC 的独立 AX 只读检查确认了以下四项。此次快照 SHA-256 为 `15f12b7257660d8064f42d3cae77097404be0e332a6644206373823b6bf449a3`。

- 原 Edge 进程、窗口、标签在前台，Temporary 草稿的唯一正文摘要与输入前一致。
- 614 基线图各项计数为 1，612 和 613 的实名操作附件各出现一次，总计 3 张，陌生附件为 0。
- 选中文字与原 `selected words` 相符，UTF-16 选区从第 61 个单元开始，长度为 14。
- 当时的完整草稿状态得到确认。两次观察之间相隔约 4 分 45 秒；早期组合检查的逐项状态仍未测得。

## 早期版本的两次 Apple Event 超时

`historical-timeouts.json` 单独记录来源为 `57d8f0dc` 的两次实测。两次均在原选择最后一次复核时出现 `nativeEventFailed(-1712)`，分别耗时 101.245 和 116.096 ms。各有十条匹配的 native 数据，前后始终为 5 张原图、0 操作、0 START，基线、正文和 14 字选区保存。G7 这次的两笔拒绝均未出现 `-1712`。没有记录能独立证明整个 Edge 进程发生过无响应。

## 复核

`verify_refusals.py` 仅读私有原始回执、试验前快照、指定 SQLite 与媒体目录，并依照输入事件号、标记、窗口、原资产及诊断序号重新配对。输出只含公开字段和摘要。运行后可逐字节与公开文件比对。

```sh
python3 -B verify_refusals.py --run "$PRIVATE_G7_RUN" --database "$AFTER_SQLITE" --media-dir "$ISOLATED_MEDIA" --draft "$LATE_READ_ONLY_AX" > reproduced.json
cmp actual-refusals.json reproduced.json
shasum -a 256 -c SHA256SUMS
```
