# Riftlet · 一只托盘，一道微缝

同样的系统截屏，两种边缘外观。调试 JavaScript 时，三张线索先后进入截图托盘。读微积分时，切线、读书摘记和展开式从微缝依次出现。鼠标点走一张，剩余截图补位，原来的 ChatGPT 问题还在，用户接着写。

| 语言 | 24 秒主片 · 1920 × 1080 | 15 秒竖剪 · 1080 × 1920 | 配套封面 |
|---|---|---|---|
| 简体中文 | [播放](films/zh-CN/master.mp4) · [描述字幕](captions/zh-CN/master.srt) | [播放](films/zh-CN/vertical.mp4) · [描述字幕](captions/zh-CN/vertical.srt) | [横屏](covers/zh-CN/master.jpg) · [竖屏](covers/zh-CN/vertical.jpg) · [B 站列表](covers/zh-CN/bilibili-feed.jpg) · [小红书](covers/zh-CN/xiaohongshu.jpg) |
| English | [Play](films/en/master.mp4) · [Descriptive captions](captions/en/master.srt) | [Play](films/en/vertical.mp4) · [Descriptive captions](captions/en/vertical.srt) | [Landscape](covers/en/master.jpg) · [Portrait](covers/en/vertical.jpg) |

## 分镜与剪辑

| 主片时间 | 发生的动作 |
|---|---|
| 0.00–2.29 | 官网报错图和切线图引出两种外观。切入松绿色调试桌面，右边缘空白，草稿里已有问题。 |
| 2.30–6.59 | 在源码、控制台与报错处分别划出截屏选区。首张截图带出托盘，第二张到达时托盘展开，第三张进入下一行。镜头从手记移到点选处。 |
| 6.60–8.72 | 点第一张，原图进入 Chrome 里的草稿。后两张依序前移，用户追问 items 的值。 |
| 8.73–14.99 | 换到纸色的微积分手记和空边缘。三次截屏后，横图、竖图与展开式沿微缝排列。 |
| 15.00–21.22 | 连续选中两张。镜头保留第一次退出及后图上移，再跟到两个附件和原问题上。用户继续输入「请从展开式讲起。」 |
| 21.23–24.00 | 三个动词依次收拢到品牌和下载地址。 |

竖剪从空桌面直接开场。两次截三张、三次主动点击与最后续写都按竖屏重新安排取景与声点。采用连续操作和同图匹配衔接，省去额外的拖放对照段。

## 美术、来源与核验

官网的报错图、阅读图、正式字标素材与 Instrument Serif 进入画面。原创建立的调试和数学手记提供六个可以实际框选的像素区域。同一份裁片同时供托盘、微缝、附加动效与草稿缩略图使用。桌面、鼠标、边缘和网页草稿为离线设计动画，本片未使用用户桌面录屏或新生成的 AI 画面。音轨由原创合成乐器和交互拟音组成。

片中选取 1.0.5（31）的截图托盘和微缝。空队列特写采用关闭内建截图键的配置；产品另有风铃外观。真实产品在观测到附加开始后隐藏选中的图，画面上的同图衔接是剪辑表达，草稿保持未发送。

- [官网美术与两份手记](studio/MATERIALS.md) · [声音设计](studio/sound/SOUND.md) · [无损音乐与拟音母带](audio/)
- [原生空态、几何与队列核验](review/PRODUCT-EVIDENCE.md) · [正式安装包与受控 Chrome 验证](review/product-verification.md)
- [播放审片](review/PLAYBACK.md) · [逐文件解码、声轨、峰值与哈希](review/technical.json)

## 复现

从完整仓库进入本目录。制作环境为 macOS、Python 3.14，使用仓库内官网字体和本机 Heiti SC、Songti SC、Helvetica Neue、Georgia 及 Menlo。

```sh
python3 -m venv /tmp/riftlet-flow-render
source /tmp/riftlet-flow-render/bin/activate
python -m pip install -r studio/requirements.txt
python studio/sound/score.py audio
for lang in zh-CN en
do
  python studio/film.py master "$lang" --audio audio
  python studio/film.py vertical "$lang" --audio audio
done
python studio/covers.py
python studio/check.py
swiftc studio/Playback.swift -o /tmp/riftlet-flow-watch
/tmp/riftlet-flow-watch films/zh-CN/master.mp4 /tmp/riftlet-flow-view
```
