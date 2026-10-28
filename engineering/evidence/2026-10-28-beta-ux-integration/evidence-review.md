# Beta 体验修复：非作者源码与交接证据审查

日期：2026-10-28（北京时间）。审查者：`beta_ux_evidence_review`，未编写本次产品源码、证据或集成补丁。

## 结论

**PASS，无阻断合流的问题。** 可将 Codex 已交付的 8 个 App/UI/helper/测试文件和 8 份脱敏证据按真实祖先合入现有统一 Beta。必须保留正式 Feedback 接线，并以组合后的正式 HEAD 运行 Native 与 Feedback CI。此结论不是新组合 App 的物理鼠标、冷首击或真实上传验收。

审查对象：

- 原正式截图基础：`e421e6687651c2fac1441410c1af2bd5b8151e55`。
- 体验修复源码：`fa74f3c68f05ab4eaccfc24e2f39c0177289ddb3`，唯一父节点为 e421。
- 最终交接：`8e1a1688e75db8c18965e073ae357010e7397a3a`，唯一父节点为 fa74，仅增加本轮证据并修改执行板。
- 合流前正式统一 Beta：`b4bcfa41e8e237723b975d2a9a0059e955fa0c1f`，已包含 Feedback v0.1。

## 源码复核

独立读取 e421→fa74 全部差异，确认只有 8 个文件、230 行新增、10 行删除：ProductStatus、Main、SelectionSubmissionQueue、GUI helper 指引、RiftPanelController 和三份测试。Core、Capture、Adapters、CSQLite、Resources、第三方声明、Package 均为原对象；没有修改 SQLite v3、完整目标校验、dispatchIntent、唯一输入、uploadStarted/完成准入、严格 sRGB、UNKNOWN 锁或重试策略。

1. `ProductStatus.operationFeedback` 只匹配代码持有的精确取消原因。未知、输入后或任意字符串降级为中性未确认说明，不展示原始错误文本、不宣称未上传、不授予再输入。逐一对照 Core `cancelIfPrepared`/`QueueStore.cancelPrepared`：这些取消分支只能在 prepared 阶段修改状态，非 prepared 不能被文案路径取消。
2. 无点击时目标的说明只识别精确的 typed `RiftletError.adapterUnavailable`；普通 `NSError`、字符串变体及其他错误不能冒充此条件。缺 ACK 仍保留图片并拒绝输入，没有晚到 ACK 补签、延迟重放或强制聚焦。
3. Main 的选择反馈闭包在每次写入前复核原 selection owner 与 visibilityRevision。App FIFO 尚未开始提交时才显示“本次尚未上传”，进入提交即按匹配文案清除。队列新增属性只是只读 `active || !pending.isEmpty`，原 FIFO、expiry、取消和 consumer 行为不变。
4. prepared 快照可能已经在后台推进，因此改为中性“附加处理中，结果尚待确认”。取消展示绑定旧原 operation 与当前资产 activeOperationID/failed/visible；原 `refreshRequested` 过期快照边界仍保留。清理 preparing 只匹配旧文字，不能抹掉较新的 waiting/cancelled 提示。
5. UI 通过统一 `setFeedback` 同步 tooltip、可访问 label/help 及输入岛 tooltip；mouseDown/AXPress 清除旧提示也走此路径。新增展示函数不调用选择回调、不改变几何、窗口排序、点击命中或吞噬状态机。
6. GUI helper 仅补 NUMBER 和普通双击/补位后双击的区分指引，没有改变验收动作或将 helper 通过变成上传准入。

已交付测试覆盖精确原因、未知/输入后错误、私有文本不泄漏、typed no-ACK 识别、prepared 中性文本、FIFO pending/active、陈旧清理不覆盖取消、AX/tooltip 同步以及不分发输入。没有要求额外重写或扩大本轮测试。

## 原独立 CI 的实际核验

[Native foundation 40693945938](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40693945938)，job `122835634479`：completed/success，18 个实际步骤全部 success。读取完整日志后独立统计：

- 463 个唯一原生测试：Core 138、Adapters 150、Capture 65、UI 57、App 53。相对 e421 新增 ProductStatus 5 项及 UI 1 项。
- 详细逐项结果 121 passed / 0 failed / 0 skipped，属于 463 的子集；不是额外 121 项。ProductStatus 5 项在完整原生运行中执行；不要把它们说成已有独立详细逐项输出。
- 当前页面 86、legacy 61；七组 TAP 总数 19+86+61+9+4+2+12=193，全部通过。
- 原包装 12 项、Release 构建、实际 bundle 校验、五项 packaged executable self-check 和 synthetic GUI helper 打包均通过；self-check 明确 CHROME/GUI/真实截图 NOT_RUN。
- 这是 fa74 的独立源 CI，**不覆盖正式 Feedback 组合后的新 HEAD**。

本审查下载的完整日志保存在 `/tmp/riftlet-beta-ux-original-native-40693945938.log`：260,172 bytes、2,609 行、SHA-256 `374930cdf9b46dcb9fef51fc3c45580c98d256009ab53cd6d66e4a87bde068cd`。该 connector 解码日志与 Codex 私有 `gh` 导出日志不是同一包装字节流，不能混用其摘要。

## 真实证据边界与保留事项

独立阅读本轮全部 8 份公开证据，JSON 可解析，26 个私有摘要索引标签唯一、长度/哈希格式有效。**本审查没有访问私有原图、完整 trace 或数据库，不能声称重新核对这 26 份私有原件的字节。** 原作者侧非作者已核对私有材料的声明保留原归属；这里核验公开记录与源码、来源和时序的一致性。

- e421 的 synthetic helper：用户回复完成且执行者声明该阶段无软件鼠标；事件自身为 `unattributedNSEvent`，因此只称“用户报告物理操作并有原生事件记录”。IMAGE/NUMBER/GAP/原图按住释放与 helper 键盘资格限定 PASS。不是 Chrome 物理上传。
- 指定 CLEAR 靶点和补位后双击未命中指定操作，继续 NOT_RUN。极窄 0.0234375 pt 透明边缘和补位前三组普通双击不替代这些项目。
- b4bc 的 Feedback 窗口通过 CUA/AX/Apple Events 检查，两次保存/关闭/重开保留实际 ASCII 草稿；reports/submissions/credential intents 为 0，诊断未勾选，未发送。非 ASCII CUA 输入不等于 IME 失败或通过。不是 fa74 与 Feedback 的新组合真机验收。
- H 延迟是既有 e421 上传的重分析：input→start 1995.7 ms，动画段约126.964 ms，原窗口首次缺席约2.72 s；本轮没有上传或性能优化结论。页面/host 两套时钟没有直接混算。
- 三个 UNKNOWN 身份、attempt、target、phase、锁与媒体保留；8 个系统原件、19 个既有候选文件内容保留。SQLite 仍8 assets/5 operations/20 checkpoints/1 upload_start/0 compensations；3 行 updated_at 与1行 receipt_json 允许只读观察更新，不能说所有旧数据库字节不变。
- 一次来源未归属的旧 UNKNOWN 选择已诚实披露，未新增 operation/begin/chunk/commit，没有认作物理上传 PASS。暂时隐藏并恢复仅新增显示元数据，不清理历史。
- 旋转副屏探针未能获得前台键窗口，0 对软件点击，继续 NOT_RUN；不是产品路由 FAIL。

## 合流与交付必须保留

selection catch 同时保留 owner/revision 反馈闭包、`ProductStatus.clickFeedback(error)` 和正式 `self.feedback.diagnostics.record(.selectionRejected)`；render 后同时保留 prepared/cancelled 展示与 Feedback assets/operations/uiProjectionDeferred 投影。不能整文件覆盖 Main。固定来源审计应精确授权这 8 个路径并继续固定其余原来源，不能禁用检查。

普通生产上传、安全失败/重试保持关闭；旧 H/F/UNKNOWN 不重输。反馈 endpoint 仍 nil，没有部署。新 App 应直接沿用明确内部候选 launcher 和候选数据根，交付后优先创始人体验；无 ACK 冷首击、系统截图自包含、中文 IME/VoiceOver、全屏/Spaces/多屏、首次安装/Gatekeeper 与权限恢复的未验收范围继续记录，不能借本轮 CI 推导通过。
