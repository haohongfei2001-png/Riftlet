# 独立证据审查

- Reviewer：非作者 agent `unified_live_evidence_review`，只读私有原件、当前正式源码及本目录；未操作Chrome、未输入图片、未修改产品。
- Reviewed source：`edbdc7aae45c35878694e9fa376757dac7b630a8`；本交付没有新增产品代码。
- 结论：**限定真机证据可交付；产品全量验收／普通开放不通过。**

确认两次原系统PNG/私有副本身份、原事件前ACK、唯一begin/commit及inputCount、关联递增进度、独立attached、最终succeeded/used、快吞噬callback时间和原操作保留。确认trial3正文/旧附件保留、选区折叠FAIL；当前数据不能唯一定位选区改变的触发环节，不能批准无条件异步选区恢复。

确认独立浏览器sRGB脚本仅解码原图data URI和现有预览到OffscreenCanvas，不设置文件input、不派发change、不调用网络API；两份严格hash相同。ImageIO解码不一致保留，不宣称服务端原文件字节保真。

作者已按审查修正：

1. 将原点击边界明确为mouseDown，区分mouseUp；close callback不等于精确像素消失时刻。
2. 不声称trial2焦点全过程不变或包含旧附件；不声称trial3选区保留。
3. 补齐点击前基线、截图手势、第一张失败/日志截断、独立像素脚本及cleanup的私有哈希。仅发布摘要，私有内容不入库。
4. 文件延迟改为“约60秒后观察到完整文件及导入”，不将观察上界当作精确创建时刻或watcher根因。

审查已逐项核对原manifest哈希；新增条目由作者直接从保留原件重新计算，JSON解析及公开隐私扫描通过。复用准确原源码的完整macOS CI合理；不为文档归档重复CI。
