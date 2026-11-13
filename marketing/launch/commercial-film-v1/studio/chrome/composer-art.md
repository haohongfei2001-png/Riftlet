# 草稿画面

Chrome 窗框和 ChatGPT 草稿采用可编辑的离线重绘。没有访问私人对话或把画面记为在线实录。标签页 15 pt 图标使用 OpenAI 公开静态 CDN 发布的 32×32 favicon，文件原样保存为 `chatgpt-favicon.webp`。其 SHA-256 为 `b26a978934e93c1572c942a3b9cb84e773e3d5aeaa6efe97409f247bb9ba2c3b`。[公开 favicon](https://cdn.oaistatic.com/assets/favicon-32x32-p4ktpm1x.webp)

`composer.draw_window(t, picture, scale=2)` 接收主片秒数和用户本次截取的图片，返回 640 × 560 逻辑点的 RGBA 图层。字体使用 macOS Helvetica Neue。相机坐标按窗内逻辑点计算。草稿框从 (42,282)–(598,375) 扩展至 (42,257)–(598,425)。附件于 13.45 秒出现并在 0.14 秒完成布局，66 × 66 pt 裁切预览位于 (56,270)。初始正文为 “What stands out in this photo?”。17.8–20.65 秒在原问题末尾输入 “ Look at the lean.”。稳定状态正文以 (61,359) 为左侧中线，光标结束在 x≈471。未输入发送键，箭头按钮中心 (566,402)，按钮处于可用而未按状态。15 秒版可使用主时间线重映射，准确继承相同附件与文本态。
