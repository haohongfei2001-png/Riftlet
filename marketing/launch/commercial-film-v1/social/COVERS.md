# 视频封面与外观附页

[中文横屏封面](covers/zh-CN.jpg) · [English video cover](covers/en.jpg) · [小红书第五页](xiaohongshu/05-appearances.jpg)

两张 1920 × 1080 视频封面用于 B 站及海外视频平台。大标题在缩图上先交代「点一下就进 ChatGPT」，下方紧接点击对象与草稿，右侧用有周三低点的同一张图串起报告、边缘截图和第二张附件。横版链接分享卡另放在 share 目录。两种横图用途和画幅各异。

第五页为 1440 × 1920。左图保留原生托盘的两列、截图边框、右下相机入口；右图放大微缝的纵向截图、外侧序号与边缘遮挡。图中分栏展示两种可选外观。连续截图进入同一队列，选中图片开始附加后，微缝后项向上补位，托盘后项按格位补齐。风铃是另一种正式外观。签名验收图提供了框体、尺寸关系与序号；框内内容换成当前宣传的虚构周报。[正式版托盘布局](https://github.com/haohongfei2001-png/Riftlet/blob/fe9c227a3b89a082b9da39dc5bb1f5c0b955c2ee/Sources/RiftletUI/RiftTrayLayout.swift) · [微缝布局](https://github.com/haohongfei2001-png/Riftlet/blob/fe9c227a3b89a082b9da39dc5bb1f5c0b955c2ee/Sources/RiftletUI/RiftLayout.swift) · [签名版本外观验收素材](https://github.com/haohongfei2001-png/Riftlet/tree/fe9c227a3b89a082b9da39dc5bb1f5c0b955c2ee/docs/releases/1.0.4/evidence/signed-rc27)

在仓库内运行 `python render-covers.py` 即可重建三张含 sRGB 配置的渐进式 JPEG。依赖和所用字体与同目录的 render.py 一致。默认复用其周报配图、正式字标、字体、光标与颜色。脚本直接读取仓库 docs/releases/1.0.4/evidence/signed-rc27 下的两张原始参考 PNG；封面及第五页为排版合成。重建时可通过 --assets、--style 和 --output 指定源素材、共用渲染脚本和输出位置。
