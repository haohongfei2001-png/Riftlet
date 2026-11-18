# 两种呈放方式与队列动作

影片取用正式版 **Riftlet 1.0.5（31）** 的截图托盘与微缝。公开版另有风铃。影片选用右侧摆放、关闭内建截图键，依靠 macOS 系统截图。相机键启用时托盘可在空队列显示该键。

| 画面 | 公开实现及核对结果 |
|---|---|
| 等待截图 | 托盘在没有可见项且关闭截图键时返回空外框，微缝没有可见项时返回零长线。 |
| 截图托盘 | 外框宽为显示器的八分之一。在 246 宽参考坐标中，1 张时高 115，放在左下，2 张时向上扩至 212 且两图并列，3 张时第三张处于左下。保留原图比例。 |
| 微缝 | 顺序向下排列，第一张在上。默认缩略图等比适配 72 × 56，右侧遮挡 25%，节距 60。行左侧显示当前序号，细边界贴合图像。影片以近景取出该区域。 |
| 按下、附加 | 按下对应固定位上的图片。草稿既有文本保留。选中图的退出依据是已观察到该次附件开始，默认吞入时长 120ms。没有模拟按发送。 |
| 补位 | 点击后的保护留空覆盖潜在双击及指针停留，指针移出后队列才能收拢。默认移动用时 160ms。微缝后续项向上，托盘后续项按行优先移入空位。 |

产品实现复查使用 [公开标签](https://github.com/haohongfei2001-png/Riftlet/tree/fe9c227a3b89a082b9da39dc5bb1f5c0b955c2ee)，涉及 [托盘布局](https://github.com/haohongfei2001-png/Riftlet/blob/fe9c227a3b89a082b9da39dc5bb1f5c0b955c2ee/Sources/RiftletUI/RiftTrayLayout.swift)、[微缝布局](https://github.com/haohongfei2001-png/Riftlet/blob/fe9c227a3b89a082b9da39dc5bb1f5c0b955c2ee/Sources/RiftletUI/RiftLayout.swift)、[可见性与补位控制](https://github.com/haohongfei2001-png/Riftlet/blob/fe9c227a3b89a082b9da39dc5bb1f5c0b955c2ee/Sources/RiftletUI/RiftPanelController.swift)、[原始文件顺序](https://github.com/haohongfei2001-png/Riftlet/blob/fe9c227a3b89a082b9da39dc5bb1f5c0b955c2ee/Sources/RiftletCore/QueueStore.swift)。官网视觉参考包括舞台的屏幕边缘、代码错误示例与一阶近似阅读示例。[网站页面源码](https://github.com/haohongfei2001-png/Riftlet/blob/314f42e5a682f67085f3c95b87ecaace7b88156c/index.html)

## 独立运行结果

- 已安装签名包的 Info.plist 报告 1.0.5（31），严格验签通过。普通模式报告启用输入、开始和完成观察，自动安全重试关闭。
- 已在本机从发行标签提取未修改的 Core、Capture 和 UI Swift 源码，编译后以三个不同 UUID 的无个人内容夹具调用两个原生布局函数。检查通过空外框、紧凑和展开高度、逐行排列、首项移除后两个剩余 UUID 的位置、右微缝 25% 遮挡和 60 点节距。该检查独立于影片绘图。
- 已安装 App 的网页隔离自检通过。系统截图候选隔离自检以生成夹具完成原始字节导入、两个独立软件输入和各自的 START，保留历史 UNKNOWN。通用自检在受限环境返回 unsupportedImage，同一签名包在主机环境重跑通过，验证持久化可见性、延迟模拟完成与重启。
- 这些检查没有操作登录的 ChatGPT 账户，也没有测量现场物理点击延迟。影片中的托盘、微缝、指针和草稿是设计动画。缩略图从边缘显现是官网式的剪辑表现。实际 App 先创建最终行，单独配置的磁力动效视条件表现，关联输入及队列顺序独立于该动效。
