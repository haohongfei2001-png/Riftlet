# Riftlet 交互原型 · 源码对应 / Source mapping

本原型还原工程检查点 **`485fa87a31140f9d2e428db69ec5e0599b1f96ae`** 的界面和状态逻辑。读取时 PR #1 为 Draft。它不是原生 App，也不代表最终视觉批准。第一轮 A 只保留研究价值；B/C 已淘汰；R2 01「直截」只是可调实现起点。

## A｜当前工程还原

| 参数 | 原生默认值 |
| --- | --- |
| 保持原比例拟合包络 / Fit box | 72 × 56 pt |
| 右侧遮挡 / Occlusion | 图像宽度的 25% |
| 裂缝 / Line | 0.7 pt；距可用屏幕右边 8 pt；超出首末**命中行**各 8 pt |
| 数字 / Ordinal | 11 pt；与图像间隔 6 pt；宽度 = 位数 × 11 × 0.65 |
| 排布 / Rows | 首中心距 `visibleFrame` 顶部优先 180 pt；行距 60 pt；上下留 12 pt |
| 点击矩形 / Hit rectangle | 最小 44 × 44 pt，包含数字、留白和可见图片；左留白 4 pt |
| 空队列 / Empty | 24 pt 静止细线 |
| 动画 / Timing | 收录 220 ms；按下 80 ms / 2.5 pt；吞噬 240 ms；补位及回退 180 ms |
| 减少动态 / Reduced motion | 各时长取正常值与 100 ms 的较小值 |

图片没有额外圆角、边框、投影。数字使用系统次级文字色；裂缝使用该颜色、透明度 0.48。浏览器字体、系统动态色和亚像素抗锯齿是近似值；**1 CSS px 对应 1 模型逻辑 pt**，不能代替真实屏幕物理测量。适应窗口缩览须明确显示缩放比例；判断尺寸请用 100% 和沉浸视图。

### 与 R2 图稿不同的实际实现

收录只有整行淡入，没有向外滑出的运动。图片平移一律采用 `easeOut`，包括吞噬；不采用 R2 JSON 的 smoothstep。等待仅在数字下显示单下划线，UNKNOWN 显示双下划线，均保留 2.5 pt 浅入；R2 所述接触边缘活动未实现。吞噬同时淡出整行，随后补位，运动结束才统一改号及行宽。长队列先将首行向上调整，超过容量再按行滚动；新增图片使最新条目可见。

### 几何校验例 / Geometry fixtures

| 合成原图 | 完整拟合 | 实际露出 | 单位数字时命中框 |
| --- | --- | --- | --- |
| 1920 × 1080 | 72 × 40.5 | 54 × 40.5 | 71.15 × 44 |
| 1080 × 1920 | 31.5 × 56 | 23.625 × 56 | 44 × 56 |
| 2400 × 400 | 72 × 12 | 54 × 12 | 71.15 × 44 |

均为 pt。本原型采用**顶部菜单栏 25 pt、底部 Dock 保留 76 pt**的明确建模假设。1440 × 900 场景对应原生坐标 `visibleFrame=(0,76,1440,799)`：容量为 12；2–3 张的首中心距整屏顶部 205 pt，12 张时上移至 124 pt。具体 Mac 的缩放、菜单栏和 Dock 设置会改变结果；这些不是用户 Mac 的实测值。1470 × 956 仅为 13 英寸 Air 的逻辑画布参考，不是硬件检测结果。

## B｜评审层合成模拟

普通工程模式使用 `UnavailableAdapter`：点击保留 pending，不产生附件。原生 `--simulate` 固定单一草稿，450 ms 后依次演示成功、失败、UNKNOWN，核对仍返回 UNKNOWN。本原型可选择结果、延时、线程及注入回执，是独立评审能力；模拟 ChatGPT 和附件均为本地合成内容。

连续点击按顺序派发，已准备条目立即显示 transferring；同草稿 UNKNOWN 会使后续未派发操作失败回退，不会自动重传。提交输入意图前的目标校验失败可安全回退；提交意图之后失去可靠证据则 UNKNOWN，即使不能确定图片是否已经输入。点击 UNKNOWN 只核对原操作。附件占位不算成功；只有明确注入正确原草稿完成回执才吞噬。切换回原对话本身不解除 UNKNOWN。此过程不会发送消息。

浏览器运行检查只证明本原型可操作。AppKit 首击、非激活、跨应用焦点、透明窗口穿透、Spaces、物理多屏、系统截图捕获/排除及真实 ChatGPT 上传，均仍由真机工程验收负责。

本轮交互检查在托管 Chrome 中完成。独立 HTML 已构建，但本地 `file://` 启动为 **NOT_RUN**：执行浏览器的 URL 策略不允许该协议，未重试或绕过。未宣称 Safari 或真实 Mac 本地打开通过；自包含、无运行依赖是文件结构属性，不能替代跨浏览器实测。详见 [原型运行检查](../qa/VERIFICATION.md)。

## 固定来源 / Pinned sources

- [RiftConfiguration.swift：参数](https://github.com/haohongfei2001-png/Riftlet/blob/485fa87a31140f9d2e428db69ec5e0599b1f96ae/Sources/RiftletUI/RiftConfiguration.swift)
- [RiftLayout.swift：几何、容量、点击身份](https://github.com/haohongfei2001-png/Riftlet/blob/485fa87a31140f9d2e428db69ec5e0599b1f96ae/Sources/RiftletUI/RiftLayout.swift)
- [RiftPanelController.swift：绘制、动画、滚动](https://github.com/haohongfei2001-png/Riftlet/blob/485fa87a31140f9d2e428db69ec5e0599b1f96ae/Sources/RiftletUI/RiftPanelController.swift)
- [TransferCoordinator.swift：选择、串行派发、UNKNOWN](https://github.com/haohongfei2001-png/Riftlet/blob/485fa87a31140f9d2e428db69ec5e0599b1f96ae/Sources/RiftletCore/TransferCoordinator.swift) · [QueueStore.swift：持久状态契约](https://github.com/haohongfei2001-png/Riftlet/blob/485fa87a31140f9d2e428db69ec5e0599b1f96ae/Sources/RiftletCore/QueueStore.swift)
- [PRODUCT.md：产品要求](https://github.com/haohongfei2001-png/Riftlet/blob/485fa87a31140f9d2e428db69ec5e0599b1f96ae/docs/PRODUCT.md) · [DECISIONS.md：批准状态](https://github.com/haohongfei2001-png/Riftlet/blob/485fa87a31140f9d2e428db69ec5e0599b1f96ae/docs/DECISIONS.md)
- [R2 JSON：历史候选](https://github.com/haohongfei2001-png/Riftlet/blob/485fa87a31140f9d2e428db69ec5e0599b1f96ae/design/explorations/round-02/Riftlet_R2_Spec.json) · [MAC_ACCEPTANCE.md：真机验收边界](https://github.com/haohongfei2001-png/Riftlet/blob/485fa87a31140f9d2e428db69ec5e0599b1f96ae/docs/MAC_ACCEPTANCE.md)
