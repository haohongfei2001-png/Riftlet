# Riftlet｜品牌策略与中英文文案

候选版本：2026-10-30。品牌方向：**Passage / 隙入**。本文是独立品牌候选的表达依据和可直接使用的文案，不代表创始人已采纳，也不改变产品准入或发布状态。网站当前文字由 `tools/build-site.py` 生成；具体支持事实以 [产品事实核查](product-truth.md) 为准，参考研究见 [brand-references.md](brand-references.md)。

## 一、最终品牌判断

**Riftlet 是让屏幕内容更自然地进入对话的原生 Mac 工具。** 它最值得被记住的，不是“还有一个截图工具”，而是截图之后的那次轻量交接：图片在边缘等你选择，你点一下，它进入正在使用的受支持草稿；写好的文字留下，最终发送仍由你完成。

独立软件存在的理由是重复使用中的认知成本。一次复制粘贴本身很短，但找到刚截下的文件、离开正在组织的表达、确认放入哪个草稿，都可能打断思路。Riftlet 把暂存位置固定下来，让选择图片和表达意图发生在同一次点击中。这个价值属于设计目标和产品机制；本候选不把它转成未经测量的节省秒数或效率倍数。

边缘因此具有功能含义：它让内容可见而不占据工作中心，让截图待用而不要求维护另一个文件库。边缘、遮挡、点击与离场组成一套能反复出现的品牌语法。仅有一条裂缝还不足以构成竞争优势；真实的机会是把整个流程做得克制、可靠、容易理解。

这也是为什么不使用“首创截图进入 AI”“替代所有截图工具”或“自动理解屏幕”的叙事。同类已经覆盖临时文件架、截图分享以及进入 AI 对话的不同路径；官方案例和能力边界见参考研究中的 [Dropover](https://dropoverapp.com/)、[CleanShot X](https://cleanshot.com/) 与相关直接替代品。本轮选择的是可自证的机制与体验，而不是夸大的新类别。

### 品牌气质

**安静而可感知，精密而不冷峻，轻巧但不玩具化。** 页面和标志允许温度与少量艺术感；涉及当前目标、附件、已有文字和发送控制时，表达必须清楚。产品的未来感来自空间处理和连续动作，不来自星芒、光效或虚构 AI 能力。

## 二、三个方向为何收敛到 Passage

| 方向 | 主要联系 | 值得保留的长处 | 取舍 |
| --- | --- | --- | --- |
| Split R / 分界 R | 名称首字母与分割边缘 | 名称关联直接，保留原青绿的连续性 | 作为备用。字母优先，用户仍需从演示理解截图交接；R类标志的区分空间较拥挤。 |
| **Passage / 隙入** | 一个内容平面面对稳定边界，之间留出可感知的空隙 | 符号、页面边缘和真实交互可以使用同一空间关系 | **主推荐。** 以机制为起点，能从16px轮廓扩展到品牌画面；不声称单看符号即可猜出全部功能。 |
| Inflection / 转折 | 折叠与空间方向变化 | 艺术性更强，适合大画面 | 淘汰为主标识。折叠可能被读成通用空间、建筑或开发工具，对Riftlet的特定机制解释更远。 |

实际矢量与比较图位于 `brand/directions-board.svg`、`brand/directions-board.png`；推荐主标志位于 `brand/mark.svg`。三套是可比较的实物探索，不构成三个同时生效的品牌。

Passage 的两个路径分别命名为 `content-plane` 与 `screen-edge`。它是内容越过边界的抽象，不是示意原生截图会变形。生成概念用于创意探索，最终几何以独立构造的矢量为准。符号的小尺寸版扩大间隙、增强边界，避免把细部复杂度带进favicon；真实Dock效果仍留给采用阶段核对，不能用导出的PNG替代实机结论。

## 三、统一的视觉语言

| 角色 | 候选规范 | 目的 |
| --- | --- | --- |
| 主色 | Forest ink `#123E38` | 提供稳定、清楚的文字与图形骨架。 |
| 识别色 | Mint `#46D1B1` | 保留已有青绿的可识别方向，提高图标在桌面中的存在感。 |
| 浅底 | Warm paper `#F4F1E8` | 为真实内容和较大标题提供温暖的阅读环境。 |
| 辅助色 | Sand `#D7A482` | 少量用于图像和局部温度，避免整页只有同一绿色。 |
| 英文标题 | Iowan Old Style / Baskerville / Georgia 等本地衬线回退 | 标题传达“表达与思考”，正文保持清楚可读。 |
| 中文标题 | 可用的本地宋体／Noto Serif CJK SC回退 | 中文独立分行，不照搬英文行长和斜体。 |
| 正文与控件 | macOS/Windows系统无衬线与中文系统回退 | 降低加载依赖，维持原生工具的清晰度。 |
| 字标 | 有许可的 DejaVu Sans 轮廓与显式字距 | 可编辑SVG，不要求浏览器加载字体；保留 `FONT-LICENSE.txt`。 |

网页不分发系统字体文件。不同设备的字体回退可能改变字面宽度，排版因此采用响应式字号、独立中文行高和有限文字宽度；最终采用时仍应检查实际Safari与Chrome。

图形规则是“一处稳定边界，内容与它形成关系”。品牌画面可以放大、分解或裁切这个关系；实际产品示意应保持等比例微图，不能扩张成大型悬浮图库。圆角、阴影和材质只服务层级：App Icon 的承载底板可有克制材质，网页平面标志、菜单栏符号保持单色。截图内容不套品牌滤镜。

动效说明因果：出现提示内容到来，按压提示点击已被接收，模拟正向开始之后才离场，最终完成不再补演吞噬。网页计时只是演示安排，不是性能数字。默认演示选“无”只是页面初态，不裁决原生产品默认；用户已批准的入场选项仍只有“无”和“磁力吸引”。

## 四、完整中英文核心文案

两种语言共享产品事实，各自寻找自然表达。英文H1侧重“把意思表达出来”，中文H1侧重“把看到的内容带入对话”，无需逐词对齐。

| 用途 | 中文 | English |
| --- | --- | --- |
| 一句话产品定位 | 把截图带进当前受支持 ChatGPT 草稿的原生 Mac 工具。 | A native Mac companion for bringing screenshots into your current supported ChatGPT draft. |
| 品牌主张 | 少些搬运，让思路继续。 | Less handling. More conversation. |
| 官网H1 | **把眼前的，带进对话。** | **Show what you mean.** |
| 首屏上方短句 | 从屏幕上的这一刻，到对话中的下一句。 | From your screen. Into the conversation. |
| 首屏副标题 | 截图轻驻 Mac 屏幕边缘。点一下，附加到当前受支持的 ChatGPT 对话草稿。写好的话保留，何时发送由你。 | Screenshots, waiting at the edge of your Mac. One click into your current supported ChatGPT draft. Your words stay. You choose when to send. |
| 演示引导 | 点一下右侧边缘的小图。 | Click the small image at the right edge. |
| 演示标签 | 本地模拟 | Local simulation |
| 演示范围 | 放大的机制示意；不读取屏幕，不连接真实 ChatGPT。 | Illustrated interaction, enlarged for clarity. No screen access or connection to ChatGPT. |
| 主CTA | 亲手试一试 | Try the interaction |
| 首屏次CTA | 为什么在边缘？ | Why the edge? |
| 进展CTA | 查看开发进展 | Follow the development |
| 范围CTA | 查看当前测试范围 | Current test scope |
| 当前状态 | macOS 原生工具 · 正在内部测试。公开版本尚未发布。 | Native macOS · Internal testing. A public release isn’t available yet. |
| 页尾品牌句 | 让内容轻轻进入，让思路继续。 | A quiet way into the conversation. |

“Your words stay”对应保留已有草稿的产品机制，不暗示版权、模型训练政策或跨平台普遍可靠。网站在控制模块使用“交接的目标／designed to”并在范围区说明测试阶段，避免把目标承诺与全部平台已验证混同。

## 五、主要模块的标题与正文

### 1. 截图之后 / The handoff

**中文标题：** 眼前这一刻，正好成为下一句的上下文。

一个布局，一张图表，一处难以用文字说清的细节。你想问的问题，就在屏幕上。Riftlet 给刚截下的内容留一个位置。照常截图，继续思考；需要时，轻点边缘的那张图。

**English heading:** A screenshot is the start of a conversation.

You see something worth asking about. A layout, a chart, a detail you can’t quite put into words. Riftlet gives that moment a place to wait. Take your screenshot as usual. When you’re ready, click it at the edge. Stay with the thought.

### 2. 恰好够用的空间 / A little space

**中文标题：** 只露一点，始终在手边。

刚刚的画面，露出一点就能认出。固定的位置，让取用不再需要寻找。宽图、竖图各自保留比例；没有待用图片时，连边界也一起隐去，把屏幕还给你。

**English heading:** Only a sliver. Still within reach.

A small glimpse is enough to recognise what you just captured. A consistent place is enough to find it again. Wide, tall, or somewhere between, each image keeps its proportions. When nothing is waiting, the edge disappears.

### 3. 思路不必绕路 / One continuous thought

**中文标题：** 截下来。点一下。继续说。

保留原来的 macOS 系统截图习惯。在受支持的 ChatGPT 对话中，点击要用的那张图。确认已经开始附加后，小图快速进入边界；最终完成稍后到来，草稿始终不会自动发送。

**English heading:** Capture. Click. Carry on.

Keep your existing macOS screenshot habit. Choose an image at the edge while you’re in a supported ChatGPT conversation. Once attachment start is confirmed, the thumbnail slips into the edge. Completion comes afterwards. Your draft stays unsent.

### 4. 保留你的表达 / Your intent, intact

**中文标题：** 图片加进来。写好的话，留下来。

交接的目标是追加图片，同时保护草稿中已有的文字与附件。说什么、何时发送，都由你决定。

**English heading:** The image comes in. Your words stay yours.

The handoff is designed to append an image while protecting the draft’s existing words and attachments. Sending the message is always your decision.

### 5. 恰到好处的配套 / Quietly useful

**中文标题：** 需要时有，工作时安静。

内置截图、轻量历史、两种入场方式，以及设置与反馈，围绕这次交接展开。状态标签分别说明已实现、实机验证中或已集成；内置截图的存在不等于其附加链路已准入，反馈服务上线也不等于所有原生窗口流程已完成验收。

**English heading:** Enough around it. Nothing in the way.

Built-in capture, a light history, two entrance motions, and deliberate settings and feedback support the main handoff. The page labels implementation and verification separately. Built-in capture is not yet admitted to the attachment path, and the complete Mac feedback flow remains under verification.

最后一段是供写作者保持准确性的说明；页面实际每项各用较短正文，不把工程术语堆进主视觉。

## 六、演示微文案与边界

| 事实 | 中文 | English |
| --- | --- | --- |
| 目标检查中 | 正在检查目标草稿；图片仍在原位。 | Checking the target draft. The image stays at the edge. |
| 模拟开始信号 | 模拟确认：已经开始附加，小图现在离场。 | Simulated start confirmed. The thumbnail can now leave. |
| 稍后完成 | 图片已在示例草稿中。原文字与附件保留，未发送。 | The image is in the sample draft. Your words and existing attachment stay. Nothing is sent. |
| 无开始信号 | 没有取得开始信号。图片留在原位。 | No attachment start was confirmed. The image stays at the edge. |
| 开始后未知 | 结果尚不确定。记录留在历史中，不重复附加。 | The result is uncertain. It stays in history, without another upload. |
| 条件失败模拟 | 模拟明确失败：同一张图已回到原位。你可以再次点击。 | Simulated confirmed failure. The same image is back and can be clicked again. |

失败演示旁必须保持“交互契约的条件模拟；原生产品的安全失败恢复准入仍关闭”。不能把“先看一眼草稿”当成解锁UNKNOWN的证据；单纯超时、失焦、导航、观察器丢失都不能自动触发重生。

重开演示只清空合成新增附件与状态，保留访客输入和固定旧附件。它不是原生“清空可见队列”操作。语言切换使用独立页面，不承诺跨页保留。示例文字与附件状态在本页内存中处理；本页不上传，也不主动写入持久存储。页面在收到pagehide时恢复默认示例文字并销毁模型，从BFCache恢复时重建模型；这不保证浏览器自身的表单恢复、缓存或扩展绝不保留内容。

## 七、简短品牌介绍

### 中文

Riftlet 让屏幕里的内容更容易进入对话。刚截下的图片轻驻 Mac 屏幕边缘，等你点选，再附加到当前受支持的 ChatGPT 草稿。写好的文字留下，最后的发送由你完成。产品正在受限内部测试，公开版本尚未发布。

### English

Riftlet is a small Mac utility for bringing visual context into a conversation. Screenshots wait at the edge until you choose one for your current supported ChatGPT draft. Your existing words stay in place, and the final send stays with you. Riftlet is in restricted internal testing; a public release is not available yet.

## 八、首次公开介绍稿：当前可用版本

本节用于**首次向公众介绍正在开发的产品**。它不宣布App已公开发行，也不邀请公众下载安装内部制品。发布行为仍由创始人另行决定。

### 中文完整稿

**Riftlet：把眼前的，带进对话。**

有时，你想问的不是一句话，而是屏幕上的一个细节：一个布局、一张图表，或某个难以描述的地方。

Riftlet 正在把这个瞬间变得简单一点。它是一款原生 Mac 工具，让刚截下的图片轻驻屏幕边缘。需要时点选一张，把它附加到当前受支持的 ChatGPT 对话草稿；写好的文字与原有附件受到保护，消息仍由你决定何时发送。

我们希望保留你熟悉的截图习惯，让截图之后的搬运更少、表达更连贯。边缘只为眼前要用的内容留一点位置，不把工作桌面变成另一座图库。

Riftlet 目前处于**受限内部 Beta**。附件流程仅在限定的 Chrome／中文 ChatGPT 普通已有对话及PNG条件下取得验证；普通启动的生产附件能力仍未开放，公开下载与公证发行尚未提供。官网中的演示使用本地合成内容，不会读取你的屏幕或连接真实 ChatGPT。

现在可以先体验这次交接的设计，也可以查看项目的实际进展。公开测试就绪后，我们会提供准确的支持范围和安装说明。

**亲手试一试，看看截图到对话之间，能不能少一点绕路。**

### English complete draft

**Meet Riftlet. Show what you mean.**

Sometimes the thing you want to ask about is already on your screen: a layout, a chart, or a detail that is easier to show than describe.

Riftlet is a native Mac utility being built around that moment. Your latest screenshots wait at the screen’s edge. Choose one to bring it into your current supported ChatGPT draft, alongside the words and attachments already there. You decide when to send.

The idea is to keep your familiar screenshot habit and make what comes next feel lighter. A small place for the image, a deliberate click, and a little less handling between seeing something and talking about it.

Riftlet is currently in a **restricted internal beta**. Attachment verification covers limited Chrome and Chinese-language ChatGPT conditions with constrained PNG inputs. Production attachment is disabled in the regular app mode, and no public, notarised download is available yet. The website’s interactive demo uses local sample content; it does not read your screen or connect to ChatGPT.

You can try the interaction and follow the development now. Public testing will come with its own verified compatibility details and installation guide.

**Try the handoff. Stay with the thought.**

## 九、后续文案更新规则

品牌主张可以保持稳定，能力与发布状态必须随真实证据更新。只有公开发行包、准确兼容矩阵和相应安装说明已经存在，才将CTA改为“下载 Mac 版 / Download for Mac”。新的平台、文件格式、首击可靠性或失败恢复准入都应单独核实，不能随视觉升级一并扩大。

不使用未测性能数值、虚构评价、用户数量、首创或官方合作措辞。新图标和官网提升的是品牌完成度，不能作为原生可靠性已完成的证据。
