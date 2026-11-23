# 小红书图文与双语分享封面

前四张图讲同一份周报的补图过程，第五张展示可选外观。暖橙柱图代表已在草稿里的总览，青绿折线代表准备补上的截图；陶红色周三低点在资料图、边缘微图与最终附件中重复出现。所有图均使用原创虚构周报数据。周一到周五依次为 86、91、54、78、95。图内「场景示意」标示排版还原。完整操作片的素材来源与验证范围另见其制作记录。

## 小红书发布顺序

[可发布的标题与正文](NOTE.md)

1. [主张](xiaohongshu/01-claim.jpg)先告诉读者在 Mac 上刚截的图可以点进 ChatGPT，并点明是当前草稿。
2. [系统截屏](xiaohongshu/02-capture.jpg)以「为什么周三下滑？」给出补图理由，展示系统选区与快捷键。
3. [点击边缘缩略图](xiaohongshu/03-click.jpg)用局部放大和简化的微缝示意指出准确点击位置，保留图片右缘遮挡与序号。
4. [原草稿续写](xiaohongshu/04-draft.jpg)将原附件和新截图并列，问题保持，新增一句追问，发送按钮处于未触发状态。

5. [托盘与微缝](xiaohongshu/05-appearances.jpg)展示两种可选外观并说明补位。第五页可作为独立附页。

## 官网及社交分享

[中文分享图](share/zh-CN.jpg) · [英文分享图](share/en.jpg)

两种语言均单独排版，供相应语言页面的 Open Graph 和社交分享卡片使用。中文替代文本为「Riftlet，刚截的图，点一下就进 ChatGPT。点击 Mac 屏幕边缘的截图可附加到当前草稿。」英文替代文本为 “Riftlet. Just took a screenshot? One click adds it to ChatGPT. Click the thumbnail at the edge of your Mac screen to attach it to your draft in Chrome.”

## 本机重建

在完整仓库的 macOS 环境运行 `python render.py` 重建前四张图文和两张分享卡，再运行 `python render-covers.py` 重建视频封面与第五张图；依赖 Pillow、resvg-py、fontTools、Brotli。脚本向上定位 website-assets，读取正式标识和 Instrument Serif；其余排版使用 macOS 随附字体。支持通过 `--assets` 指定品牌素材目录，或通过 `--output` 选择输出位置。本批图形未采用生成式绘图。

## 稿件复查

五张竖图均为 1440 × 1920，横版分享图为 1200 × 630，全部内嵌 sRGB。逐页查看了两档手机显示宽度（190、345 像素）与双语横图：首屏主张不靠右下小字也可读，第三张指针位于微图内，第四张保留两张附件和发送按钮，第五张对照两种外观。此记录来自内部视觉检查。社交平台实际的裁切、平台压缩和用户理解率需在相应渠道另行验证。
