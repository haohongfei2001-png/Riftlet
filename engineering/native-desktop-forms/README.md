# 原生桌面呈放集成

产品基线为 `6179a9dddcfda83513e0aaa6347de0cce8309d6c`。设置在布局页提供互斥选择。微缝沿用 R2.1。截图托盘、折页和口袋均由同一个 RiftPanelController 根据 QueueStore 的可见记录排版，选取、目标冻结、截图 START、失败返回和历史继续使用原有入口。保存桌面形态使用原布局配置文件。旧文件和未识别的形态值读取为微缝，保存其他设置时保留原始形态值。

## 设计依据与差异

- 截图托盘采用 [PR #51 的最终规格及原始参考图](../../design/third-form-screenshot-tray/README.md)，来源提交 `90f0ce4139c792e370f3700d5a868c014080e02d`。原图 SHA-256 为 `65b61d4d7a62e9221b45b8c0c9afff3626b904a242de0d321d9bda5d56887e0b`。截图菜单占满一行。两侧的菜单均从左至右排列常用 1、2、3 和默认键。可绑定窗口、区域、全屏，可以重复或留空。自动配置使用另外两种实际截图方式并留空一位。菜单展开期间，新到图片优先进入另一行，数字身份和持久队列顺序保持一致。
- 折页及口袋采用 [PR 52 的设计规范与原型](https://github.com/haohongfei2001-png/Riftlet/tree/8d65462a0bcf6d9baa60469ffc95d253e3e146c5/design/fourth-fifth-desktop-forms)。两者共享 behindWindow 模式的 NSVisualEffectView 底座。叠放页的点击目标绑定截图 UUID。口袋按首次悬停的页锚定展开位置，指针离开组合后收拢。
- 风铃在两份设计 PR 中被命名。已检索历史分支、原型和决定，尚缺可核实的几何、视觉或交互基准。选择器保留禁用项，进度为 **缺设计依据**。历史值仍可完整往返保存。

## 验收范围

[最终复核记录](FINAL-TRAY-ACCEPTANCE.md)包含玻璃裁切的原生分层对照、展开时被玻璃盖住的真实故障帧，以及冷启动按下事件到达按钮后的故障定位。

桌面用例通过普通 Riftlet 可执行文件的 `--settings-review <UUID>` 隔离入口运行。独立偏好、数据库和合成图片与该 UUID 对应。首次运行使用 `--settings-review-run --desktop-forms-review`，再以同一 UUID 执行 `--settings-review-restart-check --desktop-forms-review`。Software-GUI 事件、WindowServer 实际窗口、布局断言和真实 ChatGPT 草稿分别报告。正式验收不涉及宿主生产截图和私人聊天。

私有候选 0.3.4 (11) 的[菜单操作路径、旧包失败与原生连续帧](TRAY-MENU-TRANSITIONS.md)按 PR #51 修订规格区分「已存在一张」与「打开后才收到首张」。0.3.4 (10) 的[参考图、尺寸和原生对照](TRAY-REFERENCE-REVIEW.md)保留原貌，不能作为这两项状态转移的验收。0.3.4 (9) 属于更早的原生验证；0.3.3 (6) 的公证和安装属于另一条发行流程。
