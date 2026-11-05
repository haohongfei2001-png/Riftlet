# 菜单栏承载方式裁决

2026-11-06｜设计决策，尚未实施为 AppKit 界面。

## 结论

左键使用一个紧凑的 `NSPopover` 控制中心；右键/Control-click 保留同一命令源生成的 `NSMenu`。完整设置继续使用独立、可调整尺寸的 `NSWindow`。不新增 SwiftUI 应用生命周期，不改截图面板或附件输入架构。

这里的控制中心只负责三个问题：Riftlet 是否在工作、现在要做什么、出现明确问题后到哪里处理。它不是缩小版设置中心，也不是截图图库。

## 先比较任务，再选容器

| 比较项 | NSMenu | NSPopover | 本次取舍 |
| --- | --- | --- | --- |
| 快速启动截图/历史/设置/退出 | 原生键盘导航与菜单行为，成本低 | 需要保持清晰命令行与键盘顺序 | 单看这些命令，NSMenu 已足够 |
| 暂停收录和隐藏裂缝 | 两条切换命令可以完成，但选一条后菜单会退出 | 两个独立开关可在同一表面呈现、确认并连续调整 | 选择持续可见的正交控制 |
| “暂停但仍显示旧图”“隐藏但继续收录” | 可以用准确文字表达；加说明后菜单较长 | 两条短说明和即时状态能保持稳定空间关系 | 这是使用浮层的实际理由 |
| 可恢复故障 | 可提供一条定向命令 | 一段短原因与一项恢复动作，不挤占其余操作 | 恢复只指向具体页面，不在浮层展开诊断 |
| 设置/数值/图库 | 不适合把表单塞进菜单 | 技术上能容纳，但会扩大浮层复杂度 | 两者都不承载，进入独立窗口 |
| 系统无障碍、焦点、材质与外部点击关闭 | AppKit 提供成熟默认 | 需要实现并真机核对 | 承认额外成本，原生验收未完成 |

采用 Popover 不是因为它看起来更新。若产品最终删去持续状态、独立开关说明和定向恢复，仅剩一列命令，应回到 NSMenu；不保留一个没有任务价值的自绘壳。

## 原生规则

- 复用现有 `NSStatusItem`。模板图形随系统菜单栏明暗变化；不显示长状态文字、不闪烁。可访问名称为“Riftlet”，状态通过 accessibility value 提供。
- 左键/键盘激活打开控制中心；再次激活关闭。右键/Control-click 打开 NSMenu。右键菜单中的所有操作也能从左键界面或设置到达。
- Popover 采用 `.transient` 作为基础，Escape 关闭。Apple 明确说明 transient 对某些菜单/按需成为 key 的 panel 有例外；必须实测焦点行为，不能将 `.transient` 当作所有外部点击都关闭的保证。
- 同一时间只有一个 Popover。打开设置、历史、反馈或系统权限面板前关闭它；不要从中叠开另一层 Popover。
- 点击暂停/隐藏后保持浮层打开，以显示动作结果。输入事件完成前不把状态先标成保存成功；写入失败保留原状态并提供重试/详情。
- 普通关闭不回滚已成功生效的开关。浮层没有未提交的数字表单，因此无需“保存/取消”页脚。
- 不从此浮层点击缩略图附加，不创建新的目标选择器、不恢复 Chrome 焦点、不刷新附件 relay。不改已验证输入路径。
- 命令与状态从同一状态快照派生；NSMenu、Popover、设置窗口之间不各存一份业务布尔值。
- 尺寸以内容为准，目标宽336pt；高度随入口可用性和状态短说明自适应，不锁死为某一张截图的高度。异常提示最多增加两行。小屏按visibleFrame调整位置，不能覆盖自身状态栏按钮或越过可用屏幕。精细参数、历史内容和诊断不得继续增加浮层高度。

## 依据及边界

Apple 的 MenuBarExtra 文档区分默认菜单和适合更复杂/数据更丰富内容的 window 样式；本次以该任务边界为设计参考，但在现有 AppKit 工程中用 NSStatusItem/NSPopover，不为外观重写框架。

Apple 的 Popovers 指南要求内容少、任务相关、不层叠、自动关闭时保留工作；本次浮层据此约束。以下为外部一手依据，本次访问日期为 2026-11-06：

- [MenuBarExtra](https://developer.apple.com/documentation/swiftui/menubarextra)
- [Popovers](https://developer.apple.com/design/human-interface-guidelines/popovers)
- [NSPopover](https://developer.apple.com/documentation/appkit/nspopover)
- [NSPopover.Behavior.transient](https://developer.apple.com/documentation/appkit/nspopover/behavior-swift.enum/transient)
- [NSMenuDelegate](https://developer.apple.com/documentation/appkit/nsmenudelegate)

网页原型只验证信息结构、状态投影和合成交互。真实菜单跟踪循环、焦点、TCC、Spaces、全屏、多显示器、VoiceOver 仍为 NOT_RUN。
