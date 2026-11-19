# 平台文案与校对

先选平台和语言，再复制对应文本块。标题、主文、替换配文和评论区回复可独立使用。X 的每一个文本框是一条帖子。Product Hunt 的网站字段可直接粘贴网址。Reddit 留了给社区讨论的提问，小红书用图文笔记和找回技巧，Bilibili 把第一次安装的说明放在置顶评论里。

| 平台 | 简体中文 | English | 各自重点 |
| --- | --- | --- | --- |
| Product Hunt | [产品页与开发者首评](zh-CN/product-hunt.md) | [Listing and maker comment](en-US/product-hunt.md) | 在列表和一段简介里说明用途，首评解释为什么要按图样选截图 |
| Reddit | [帖子与跟帖](zh-CN/reddit.md) | [Post and replies](en-US/reddit.md) | 开发者身份、具体问题、慢速网络、Chrome 权限和双图测试版本 |
| X | [主帖、配文与回复](zh-CN/x.md) | [Posts and replies](en-US/x.md) | 一条主帖可单独发布，另备两种素材配文与短回复 |
| 小红书 | [图文笔记](zh-CN/xiaohongshu.md) | [Photo note](en-US/xiaohongshu.md) | 两张图怎么认、微图归档后怎么找回 |
| Bilibili | [稿件简介与置顶评论](zh-CN/bilibili.md) | [Video description and pinned comment](en-US/bilibili.md) | 看桌面边缘发生什么、区别收录和网页接收、首次设置 |

## 双语核对

逐份检查了两种语言的标题、一句话、正文、平台特有的卖点与使用场景、视频文案、图文配文、下载入口和常见问题。中文保留 macOS 菜单名称，英文采用 Chrome 的 “Allow JavaScript from Apple Events”。Chrome 中当前可编辑的 ChatGPT 草稿是唯一推广的一键附加目标。提到收起时，正文将其解释为页面开始接收图片。提到真实双图测试时，明确标有 build 18 和未发送。build 20 影片配文描述桌面端的公开版画面。[正式版支持范围](../../../docs/consumer/SUPPORT-MATRIX.md) · [发布说明](https://github.com/haohongfei2001-png/Riftlet/releases/tag/v0.3.5-beta.1)

2026 年 11 月 14 日核对了十份文案中的全部下载目的地。唯一的目的地为官网首页。官网中文导航的「下载 Mac Beta」和页底下载按钮均指向 `Riftlet-0.3.5-20-universal.dmg`。正式发布当天须复核官网这两个入口仍对应当时的公开版本。[官网](https://riftlet.com/)

## 字段检查

Product Hunt 的 Launch Guide 写有 60 字符标语、260 字符简介；详细建页文档列出相同的标语长度和更长的简介上限。两版均在较短的范围内。按 Unicode 码点计算，中文的产品名、标语、简介分别为 7、29、81，英文分别为 7、54、221。发布人可直接采用现有字段。[Launch Guide](https://help.producthunt.com/en/articles/17350772-launch-guide) · [Build your product page](https://help.producthunt.com/en/articles/17834537-4-build-your-product-page)

X 采用官方 `twitter-text` 3.1.0 的 `parseTweet` 逐条检查。两个文件各八段正文均通过 280 加权字符校验，链接按 23 计。按文件顺序，中文长度为 190、90、94、129、100、91、71、93，英文为 254、127、165、162、128、100、122、136。复制文本框中的文字即可，标题和问题用于选稿。[X 字符规则](https://docs.x.com/fundamentals/counting-characters) · [twitter-text](https://github.com/twitter/twitter-text)
