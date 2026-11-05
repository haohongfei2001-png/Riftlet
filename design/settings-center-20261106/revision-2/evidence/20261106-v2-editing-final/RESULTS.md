# 编辑稳定性与独立错误域补充回归

运行：`20261106-v2-editing-final`。
结果：21 PASS / 0 FAIL / 21 已执行（计划 21）。

Actual headless Chromium DOM actions on revision-2 standalone HTML, using synthetic prototype data. Composition events are simulated DOM events, not a real OS input method. Native AppKit, disk persistence, permissions, displays, user Chrome and uploads NOT_RUN.

HTML SHA-256：`c58e4c7a3fa717a2fc5f68e8aaaf90e7950363a52c4047be182f9cb81fd67b58`。
脚本 SHA-256：`c630fa6eb3a2a3f2f1579c77c652d6c12b79e73c7a7a3b32b8f7025b9c53d01b`。

| ID | 结果 | 目标 | 实际操作 |
| --- | --- | --- | --- |
| E1 | PASS | 布局输入保留原节点、精确文本和选区 | 正常保存反馈产生提示→编辑宽度96.250并选择末两位→等待真实提示到期 |
| E2 | PASS | 未完成数字不被刷新归零或规范化 | 宽度仅输入小数点→保持焦点等待真实提示到期→检查原节点/文本 |
| E3 | PASS | 归档文本及选区跨后台刷新不变 | 自定义归档输入2.750并选区→等待提示到期→尚未保存 |
| E4 | PASS | 反馈textarea跨后台刷新保持原节点 | 正常保存产生提示→重开反馈→编辑合成文字并选区→等待提示到期 |
| E5 | PASS | 布局 composition期间刷新和Enter不提前保存 | 准备合法数字草稿→DOM compositionstart/update→组合态Enter→真实提示到期→compositionend→普通Enter |
| E6 | PASS | 归档 composition期间刷新和Enter不提前保存 | 准备合法数字草稿→DOM compositionstart/update→组合态Enter→真实提示到期→compositionend→普通Enter |
| E7 | PASS | 动画结束刷新不替换正在输入的节点 | 选择磁力并预览→编辑按下时长→等待现有动画定时器结束 |
| E8 | PASS | 减少动态不延长合法短时长 | 实际保存40ms及0ms吞噬时长→开启减少动态→预览并读取计算后时长 |
| R1 | PASS | 三停止域失败并存且无关成功不清错 | 同时暂停/隐藏/关闭入口写失败→解除注入→外观与登录偏好成功 |
| R2 | PASS | 逐域同方向重试确实保存并依次清错 | 三域失败→解除注入→依次重试collection/visibility/entry，每次检查确认值与剩余错误 |
| R3 | PASS | 仍有故障时重试不伪造确认或反转目标 | 三域失败→保持注入重试暂停→错误与确认值不变→解除注入再重试暂停 |
| R4 | PASS | 权限恢复不清三域保存错误 | 先令文件夹未授权→三停止域失败→正常许可对话框恢复文件夹 |
| R5 | PASS | 放弃失败布局只清本域不清三停止错误 | 三域失败→宽度96保存失败→关闭并放弃→重新打开 |
| R6 | PASS | 清一个错误后其余重试仍可见并可执行 | 三域失败→先重试入口→页面切换→再重试隐藏及暂停 |
| A1 | PASS | 归档首个物理单击即保存当前文本 | 输入2.500后不预先失焦，只发送一次鼠标down/up到保存按钮 |
| A2 | PASS | 归档首个物理关闭单击立即询问 | 输入2.500后不预先失焦，只发送一次鼠标down/up到关闭按钮 |
| K1 | PASS | 历史sheet正反Tab包含两个下拉框 | 从初始原图按钮反向经过时间/状态/关闭，再正向完整返回 |
| K2 | PASS | 反馈sheet焦点循环包括textarea与checkbox | 从实际初始焦点正反各循环一周，四个控件均可达且不逃出sheet |
| L1 | PASS | 七个非默认兼容字段跨实际应用保留 | 读取legacyPersonalized合成旧配置→改宽96和返回240ms→统一应用 |
| L2 | PASS | 恢复两页不会重置七个非默认兼容值 | 旧配置→选择屏幕/位置→修改并应用有效字段→两页分别恢复本页并应用 |
| Z1 | PASS | 无页面异常及外部请求 | 检查全部独立用例运行期间的浏览器错误与网络拦截记录 |


HTML保持：true；脚本保持：true；v1原件保持：true。
所有已执行用例均记录终态；不以未执行项充当通过。
