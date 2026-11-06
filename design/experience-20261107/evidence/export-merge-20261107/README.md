# 并发设计导出修复的合并复验

合并输入为 `604d5f4530690d534c975fd0a83759648a7c7f04` 与 `ada4ade59b0d934e85a7f2ea373e46cb278ce855`；共同基线为 `276574a`。远端七个提交完整列表及源文件 hash 在 [merge-inputs.json](merge-inputs.json)。本轮仅处理文件；没有 stage、commit、push、改 refs 或自行触发 CI，最终双亲合并由主代理执行。

四处冲突按以下规则处理：

- builder 保留 604d5f4 的字面 payload、逐字一致性、Node、资源内嵌和唯一模板门禁。远端四条 replacement 在双方相同的正确原源上是 no-op，无需引入。
- VALIDATION 保留双方全部原失败描述，并明确区分各阶段的实现方式。
- HTML 与 MANIFEST 由正式 builder 生成。
- 远端独立 workflow 原逻辑保留；它是 cloud smoke，本轮不扩大它。

两侧原型 JS 相同，但远端导出中额外修正的色值说明尚未进 canonical 源。现在只把 `prototype/app.js` 的「强调色」显示文本 `#367B6B / #92CBB4` 改为 `#19B7A4 / #087C70`。不改变 CSS 配色、品牌 SVG、数据状态或交互逻辑。604d5f4 之前原源未改的报告仍然成立，其 evidence 目录未改字节。

| 本轮实际检查 | 结果 | 记录 |
|---|---|---|
| 合并 HTML 真实隔离 headless | 13/13 PASS，0 pageerror，0外网请求 | [results.json](headless-01/results.json) |
| 当前浅深截图 | 8 张新 PNG | 同一 results 中尺寸与 hash |
| 生成门禁与原坏 HTML 回归 | 5/5 PASS，原断言未改 | [validation-tests.json](validation-tests.json)、[原日志](validation-tests.log) |
| 最终 MANIFEST / ZIP | 同一生成器重建；文件集合、每个文件字节、固定 ZIP 模式逐项核对 | 交付根 MANIFEST；最终包装 hash 由主代理交付记录承载 |

本轮 HTML SHA-256：`4fe1a371bf50cbeafd59a97aef26fb6b81bc4462ee9fb9ca284346750815c512`。浏览器仍为隔离 Chromium headless-shell 156.0.8078.4 / Playwright 1.65.0，临时上下文；无用户 profile、可见浏览器、既有浏览器连接、生产 App 或真实附件输入。

此前 blank HTML 真失败、headless-01 的 10 PASS/3 FAIL 及解释、headless-02 的 13 PASS 均留在旧 evidence/export-repair-20261107；这些结果不被本轮覆盖或改称本轮执行。原生双样式实现/GUI 与网页导出是独立验收，本目录不为它们提前给出 PASS。
