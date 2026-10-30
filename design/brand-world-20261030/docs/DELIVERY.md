# Riftlet｜候选交付清单

交付整理日期：2026-10-30。状态：**独立品牌与官网候选，待正式决定。** 本文件索引已经存在的成果，明确研究、设计、网页验证和原生验收之间的边界。

## 1. 直接体验

可以直接下载并用浏览器打开[单文件完整评审](../site/downloads/Riftlet-Review.html)，也可以完整保留候选目录后打开 [根入口](../index.html)或 [品牌评审页](../site/review.html)。无需构建、账号、字体下载或 ChatGPT 连接。

| 成果 | 入口 |
| --- | --- |
| 单文件完整评审 · 约 1.05 MB | [Riftlet-Review.html](../site/downloads/Riftlet-Review.html)，包含主要品牌预览、SVG 下载与内嵌中英文完整网站 |
| 单文件中文官网 · 约 84 KB | [Riftlet-Website-ZH.html](../site/downloads/Riftlet-Website-ZH.html) |
| 单文件英文官网 · 约 85 KB | [Riftlet-Website-EN.html](../site/downloads/Riftlet-Website-EN.html) |
| 完整品牌比较与推荐 | [site/review.html](../site/review.html) |
| 中文完整官网 | [site/zh/index.html](../site/zh/index.html) |
| 英文完整官网 | [site/index.html](../site/index.html) |
| 原官网对照 | [baseline/index.html](../baseline/index.html) |
| 中英文分享卡设计 | [site/og-preview.html](../site/og-preview.html) |
| 英文桌面截图 | [website-en-desktop.jpg](../previews/website-en-desktop.jpg) |
| 中文桌面审查轮次截图 | [website-zh-desktop-v1.jpg](../previews/website-zh-desktop-v1.jpg) |
| 中文移动端截图 | [website-zh-mobile.jpg](../previews/website-zh-mobile.jpg) |
| 开始后未知状态截图 | [website-unknown.jpg](../previews/website-unknown.jpg) |

单文件已经生成于 [site/downloads/](../site/downloads/)，图片、样式和脚本均已内嵌。主负责人已在真实浏览器中实测单文件评审入口及其中的中英文整站。评审文件本身即可完成品牌浏览、SVG 下载和中英文网站体验；详细文档与完整源码通过 GitHub 查阅。单独的中英文官网文件各自可运行，如需页面之间切换语言及返回评审，将三个 HTML 放在同一目录。外部仓库链接仍需联网。

截图是各自捕获时的视觉证据，其中带 `v1` 的文件保留审查前状态；它们不代替当前可操作页面，也不自动证明全部行为或兼容性通过。单文件浏览器实测不扩展为所有平台、浏览器或原生产品验收。

## 2. 用户目标与实际成果的对应

| 目标 | 实际交付与判断 |
| --- | --- |
| A · 现状审查 | [current-site-audit.md](current-site-audit.md)：保留暖纸、青绿、安静语气与已有可操作性；修正 R 标识的机制联系不足、重复演示和旧 READY 才退出的时序。实际浏览器观察标明由主负责人提供。 |
| B · 竞品与品牌研究 | [brand-references.md](brand-references.md)：五个品质参考与主要替代工具的官方来源、设计机制和竞争表达边界；不宣传直接附加或临时边缘收纳为首创。 |
| C · 三个实际视觉方向 | [三方向 SVG](../brand/directions-board.svg)、[PNG](../brand/directions-board.png)及[评审页](../site/review.html)：Split R、Passage、Inflection，各有可查看作品。 |
| D · 最终推荐与精修 | [REVIEW-SUMMARY.md](REVIEW-SUMMARY.md)、[passage-preview.png](../brand/passage-preview.png)：选择 Passage；修正概念阶段的喇叭感、刀刃感与小尺寸缝隙。 |
| E · 可编辑完整资产 | [brand/](../brand/)：SVG 母版、字标、组合标、光学小尺寸、明暗与单色、菜单栏、favicon、PNG、ICNS/iconset，以及[规范](brand-guidelines.md)。 |
| F · 完整高保真网站 | [中文](../site/zh/index.html)与[英文](../site/index.html)：完整长页、响应式样式、主题、机制交互、异常状态、范围/隐私/FAQ；不限于 Hero 效果图。 |
| G · 官网源码与核查 | [website.js](../site/website.js)、[demo-engine.js](../site/demo-engine.js)、[brand.css](../site/brand.css)、生成器与测试；[源码报告](qa-source-report.md)记录真实执行结果。 |
| H · 系统说明与接入 | [brand-strategy-and-copy.md](brand-strategy-and-copy.md)、[brand-guidelines.md](brand-guidelines.md)、[adoption-and-scope.md](adoption-and-scope.md)：解释设计关系、中英文表达、采用步骤与未完成门槛。 |

这是一套可以评审、体验和继续整合的候选。它没有被认证为“世界级”、没有真实用户记忆或转化研究，也没有以设计交付替代原生发布验收。

## 3. 品牌资产目录

| 类别 | 主要文件 |
| --- | --- |
| 主标识 | [mark.svg](../brand/mark.svg)、[mark-light.svg](../brand/mark-light.svg)、[mark-mono.svg](../brand/mark-mono.svg) |
| 小尺寸 | [mark-small.svg](../brand/mark-small.svg)；标识 PNG 16/32/64/128/256/512/1024 均在 [brand/](../brand/) |
| 字标 | [wordmark.svg](../brand/wordmark.svg)、[wordmark-light.svg](../brand/wordmark-light.svg)；轮廓路径可独立编辑 |
| 网站横向标识 | [lockup.svg](../brand/lockup.svg)、[lockup-light.svg](../brand/lockup-light.svg) |
| App Icon | [app-icon.svg](../brand/app-icon.svg)、[app-icon-forest.svg](../brand/app-icon-forest.svg)；同样七种像素尺寸的 PNG |
| macOS 接入格式 | [app-icon.icns](../brand/app-icon.icns)、[AppIcon.iconset/](../brand/AppIcon.iconset/)；尚未接入正式 App |
| 菜单栏 | [menu-bar.svg](../brand/menu-bar.svg)、[menu-bar-light.svg](../brand/menu-bar-light.svg)；黑白 16/32 PNG |
| 浏览器标签 | [favicon.svg](../brand/favicon.svg)、[favicon.ico](../brand/favicon.ico)；ICO 含 16/32/48 |
| 方向 A / C | [direction-a.svg](../brand/direction-a.svg)、[direction-c.svg](../brand/direction-c.svg)；分别保留对照和淘汰主方案，不作为同等正式推荐 |
| 尺度证据 | [scale-check.png](../brand/scale-check.png)、[scale-512.png](../brand/scale-512.png)；配合各单张尺寸按 100% 查看 |
| 分享预览 | [og-en.png](../site/assets/og-en.png)、[og-zh.png](../site/assets/og-zh.png)；正式采用仍需检查绝对 URL 与线上抓取 |
| 资产说明与许可 | [brand/README.md](../brand/README.md)、[FONT-LICENSE.txt](../brand/FONT-LICENSE.txt) |

标志的两个命名路径是 `content-plane` 与 `screen-edge`，可以用于受控动效。App Icon 的轻微材质只出现在容器；单色标识与菜单栏不附加材质。16/32px 有专门光学调整，64–1024px 使用标准轮廓。

生成的概念图在 [site/assets/](../site/assets/) 中独立保留，名称为 `concept-01-split-r.webp`、`concept-02-passage.webp`、`concept-03-inflection.webp`。它们是探索证据，最终几何以可编辑矢量为准。字标基于有许可的 DejaVu Sans 轮廓，并非宣称原创专用字体；没有打包字体二进制或竞品素材。

## 4. 网站叙事与交互交付

H1 为中文“**把眼前的，带进对话。**”与英文“**Show what you mean.**”。页面依次说明截图之后的搬运问题、边缘位置、一次完整动作、草稿控制权、恰到好处的配套功能、当前发布范围与常见问题。完整独立中英文文案见[策略与文案](brand-strategy-and-copy.md)。

可操作演示使用同一状态模型，支持以下体验：

1. 合成截图在边缘等候，可添加不同宽高比样例；没有凭计时自动附加。
2. 用户点击后先进入检查，取得模拟的 `positive_start` 后才开始 120ms 离场，最终 `ready` 在其后发生。数值是演示时序，不是性能承诺。
3. 追加模拟附件时，用户输入的文字和明确标识的原有附件保持不变；发送指示不执行发送。
4. 明确失败恢复同一源图，重派需要新点击；这是条件模拟，原生安全失败恢复准入仍关闭。
5. 开始后不确定仍保持隐藏，历史显示待核实，不伪装成功、不允许盲目再次上传；没有开始信号则保留源图。
6. 入场可选择“无”或“磁力吸引”；网站默认“无”，不代替原生默认方式的产品决定。磁力在本页是说明性动画，不能充当原生四阶段轨迹验收。

正文明确本地模拟、无屏幕读取、无真实 ChatGPT 连接、无自动发送。输入与状态由本页内存处理；不上传、不主动写持久存储。`pagehide` 和 BFCache 路径有清理/重建处理，但不对浏览器自身缓存或表单恢复作绝对擦除保证。

## 5. 实现与重建

| 文件 | 责任 |
| --- | --- |
| [tools/build-brand.cjs](../tools/build-brand.cjs) | 构造 SVG，导出各尺寸 PNG、favicon、ICNS/iconset 与比较/尺度图 |
| [tools/build-wordmark.py](../tools/build-wordmark.py) | 从有许可字体提取七个轮廓字形与字距，由品牌生成器调用 |
| [tools/build-site.py](../tools/build-site.py) | 生成中英文 HTML、合成样例、manifest 与 robots |
| [tools/build-review.py](../tools/build-review.py) | 生成评审页面、分享卡版式，并同步指定品牌/基线资源 |
| [tools/export-portable.py](../tools/export-portable.py) | 以 Python 标准库内嵌素材、样式和脚本，导出评审及中英文官网三个单文件；无额外依赖 |
| [site/brand.css](../site/brand.css) | 版式、响应式、主题、微图与动效样式 |
| [site/website.js](../site/website.js) | 页面交互、文字、渲染、焦点与生命周期 |
| [site/demo-engine.js](../site/demo-engine.js) | 可独立测试的模拟状态模型 |
| [tests/demo-engine.test.cjs](../tests/demo-engine.test.cjs) | 确定性事件顺序、未知、恢复、重复点击和迟到任务隔离 |
| [tests/site-static.py](../tests/site-static.py) | 中英文语义、标签、本地资源、API 与源码边界检查 |

网站运行不依赖 npm、Python、框架、外部字体或服务。重建资产才需要 Node + `sharp`，Python 3 + `fontTools`，以及 DejaVu Sans。默认字体路径是 `/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf`；在其他环境将 `RIFTLET_WORDMARK_FONT` 指向相同许可源字体，并保留许可文件。

在候选根目录顺序运行：

```sh
node tools/build-brand.cjs
python3 tools/build-site.py
python3 tools/build-review.py
python3 tools/export-portable.py
node tests/demo-engine.test.cjs
python3 tests/site-static.py --strict-assets --json
```

`sharp` 可通过环境已有模块解析或 `NODE_PATH` 提供；本交付不要求给网站增加运行时包管理。单文件导出器只需要 Python 3 标准库；修改网站或评审内容后应重新运行导出。探索位图、浏览器截图、现有 OG PNG 保留为交付素材，不由上述构建/导出脚本重新绘制。

## 6. 已有验证与证据边界

| 证据 | 能说明什么 | 不能替代什么 |
| --- | --- | --- |
| [独立 Logo 审查](independent-logo-review.md)与[资产说明](../brand/README.md) | 三方向取舍、实际矢量与七档尺寸的图像检查、修订理由 | 商标检索结论、真实 Dock 集成、用户记忆测试 |
| [独立网站视觉审查](independent-website-review.md)与[预览目录](../previews/) | 已捕获视口中的实际构图、可读性问题与演变 | 所有浏览器/尺寸、动画和完整键盘验证 |
| 主负责人对 [单文件评审](../site/downloads/Riftlet-Review.html)的实际浏览器操作 | 单文件入口能打开，其中中英文整站可体验 | 全平台离线、所有浏览器、屏幕阅读器或原生客户端验收 |
| [契约审查](site-contract-review.md) | 可宣称范围、开始/完成分离、未知与恢复语义、隐私约束 | 原生适配器和真实 Mac 结果 |
| [源码测试报告](qa-source-report.md)与[固定哈希记录](qa-source-result.json) | 记录版本中 10/10 引擎场景与严格依赖/结构检查通过 | 网络实测、VoiceOver、BFCache 实际返回操作、平台发行门禁 |

源码报告记录的是特定哈希；后续代码修订需按影响重跑。不能把内部逐元素断言数量转写成浏览器验收项数。最终浏览器行为结论应以实际执行者的记录为准，本索引不补造未执行的项目。

## 7. 工程隔离、提交位置与采用

远端候选统一放 `design/brand-world-20261030/`；独立分支名为 `design/brand-passage-20261030`。Draft PR 编号尚未在本索引编写时确认，应由主交付真实创建后补入，不推测编号。

只读基线核对日期为 2026-10-30；最近产品源复核记录为 06:46 UTC / 14:46 北京时间：

| 基线 | HEAD |
| --- | --- |
| main | `eba1a4fc77648a665e1d5c1f2609df1314c3b079` |
| 原生 PR #1 | `98e66a956d55b5fac71718bc627dd89705b2a506` |
| 交接 PR #15 | `623d3725d0b3096f1dc7332e6cae11f47f7002c2` |
| 自然首击分支 | `fcfd86780d1fe3e993caa23ad02d2fceeadf8954` |

完整事实及链接见[产品核查](product-truth.md)。旧官网与 Logo 保存在 [baseline/](../baseline/)；上述产品分支、原生代码、真实 Mac 工作、main、生产网站、DNS、GitHub Pages 和 Cloudflare 均未由本专项修改。

最小采用顺序是：品牌方确认主方案与文案 → 官网负责人基于届时最新 main 独立整合、核对路径/SEO/CTA → 原生唯一负责人另行接入已批准图标并做 macOS 实景检查 → 经确认后合并与上线。详细边界见[采用步骤](adoption-and-scope.md)。品牌采用不解除生产附件、安全失败恢复、自然物理首击、签名公证等原生门槛。
