# 截图托盘与微缝

两列是同一组虚构数据在两个独立桌面上的同步对照。公开版另有风铃。画面选用右侧摆放并关闭内建截图按钮，因此空队列时可见的只有桌面。两份截图分别来自本片共用的趋势 SVG 和总览 PNG。[正式版](https://github.com/haohongfei2001-png/Riftlet/releases/tag/v1.0.5)

托盘的 246 参考宽、115/212 单张及双张高度、留白、两列及紧凑左位来自正式版布局。微缝按默认框 72 × 56 保留原比例，屏幕端遮挡 25%，节距 60，带队列序号。两种外观具有不同的镜头放大倍率。[托盘源码](https://github.com/haohongfei2001-png/Riftlet/blob/fe9c227a3b89a082b9da39dc5bb1f5c0b955c2ee/Sources/RiftletUI/RiftTrayLayout.swift) · [微缝源码](https://github.com/haohongfei2001-png/Riftlet/blob/fe9c227a3b89a082b9da39dc5bb1f5c0b955c2ee/Sources/RiftletUI/RiftLayout.swift)

product_geometry.py 沿用 #116 的设计重建图层。该轮以发行标签中的原生 Swift 布局函数核对空态、两种几何和移除后的队列位置。这里绘制的是这些参数的画面。图表、指针和桌面均为合成。[早期验证记录](https://github.com/haohongfei2001-png/Riftlet/blob/6dd549d4d5f5f410840c7e1d45d8ac5f855bf79e/marketing/launch/flow-film/review/PRODUCT-EVIDENCE.md) · [图层来源](https://github.com/haohongfei2001-png/Riftlet/blob/6dd549d4d5f5f410840c7e1d45d8ac5f855bf79e/marketing/launch/flow-film/studio/product.py)

两个镜头均选择先到的趋势图。8.97 秒起选中图吞入，指针移开后自 9.53 秒补位。微缝的第二张从下向上，截图托盘的第二张从右侧移入紧凑托盘的左侧。片中 120 ms 吞入和 160 ms 补位沿用产品默认时长。各次截屏、点选、附加开始和指针退出之间的停留时间由剪辑安排。
