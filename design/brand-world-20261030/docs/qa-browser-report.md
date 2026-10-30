# 官网实际浏览器验收

2026-10-30。主执行者使用隔离的云端 Chrome 实际打开候选页面、点击与键盘操作，并读取渲染后的 DOM 与截图。不是根据源码推测视觉，也不是原生 Mac 或真实 ChatGPT 验收。

## 环境与证据边界

- 开发预览由本地静态预览服务提供，独立于 riftlet.com。
- 桌面截图画面约 1349 × 926。响应式检查通过真实 iframe 改变布局宽度；不模拟真实手机硬件、触摸性能、DPR 或网络。
- 框体设置 375 / 768 / 1024 / 1440px 时，当前浏览器内滚动条与边框占用后，测得文档 clientWidth 为 358 / 751 / 1007 / 1423px。中英文均检查；scrollWidth 均等于 clientWidth，无横向页面溢出。390px 中文框体实测 clientWidth 373px，已查看首屏、成功态、发布说明与 FAQ 开始部分。
- 已实际滚动查看英文完整叙事各段，查看浅色首屏、深色首屏与中段、中文桌面与移动端。英文末轮 Latin-first 字体已实际读回并保存新首屏；控制标题将 comes in. 作为不可拆词组。
- 云端整页截图 API 两次超时，未伪造整页长截图；交付的是实际视口截图，以及可完整滚动的网页和单文件体验。网站本身不受这个截图限制影响。

## 交互结果

| 路径 | 实际观察 |
| --- | --- |
| 初始状态 | 只有一张待用图，不自动上传、不自动成功；访客主动点击才能交接 |
| 三张图 / 中间图 | 填入测试草稿，添加两张新样例，使用 Enter 附加第二张；第一张和第三张保留，第三张从 122px 槽位补到 61px；文字和原附件保留 |
| 正常附加 | checking 时图仍可见；事件序列为 positive_start → swallow_start → swallowed → ready；开始先于退出，最终就绪在后 |
| 空队列 | 已用图隐藏后，队列为空；边界 opacity 实测为 0 |
| 确认失败 | 模拟 positive_start 与吞噬后 definitive_failure；同一 shot-1 回到 available / visible，原附件仍在、新增附件清除、测试文字保留 |
| 不确定结果 | unknown_after_start 后 shot-1 隐藏且禁用；步骤显示“待核实”，展开历史显示“截图 1 — 待核实”；不重派、不改成成功 |
| 无开始信号 | 事件为 click → no_start；图片仍可见，无新增附件，草稿保留 |
| 键盘 | Enter 触发附加。禁用前若焦点仍在源图，焦点交给稳定的历史按钮；实测 focus=history-toggle，边缘容器 scrollLeft=0 |
| 语言往返 | 中文→英文→浏览器 Back 后回到中文，模型可继续处理点击，文字恢复默认；不据此声称强制验证了所有浏览器 BFCache 分支 |
| 减少动态效果 | 强制 reduced QA 模式下，磁力入场的 animationName=none、transitionDuration=0s，根 scrollBehavior=auto；模型状态逻辑保留 |
| 单文件交付 | Riftlet-Review.html 实际打开；内嵌中英整站可操作，中文和英文附加都到达完成态；返回品牌评审、手动标志动作可用 |
| 隐私说明 | 页面声明本地模拟、无屏幕或真实 ChatGPT 连接。网络/持久存储 API 缺席由独立源码检查支持，不扩大为浏览器本身的隐私保证 |

## 本轮由实际渲染发现并修复

1. 中文提示“片”孤字换行：缩短为“点一下小图”，保持一行并贴近目标。
2. “缩小示意”与“放大机制”口径冲突：改为“桌面局部 · 机制演示”。
3. 本地模拟、状态与说明可读性偏弱：提高字号与对比。
4. hidden 属性被 display:flex 覆盖：加入明确 hidden 规则，避免隐藏的提示重新出现。
5. 键盘聚焦部分遮挡按钮使轨道 scrollLeft=18：改为 overflow:clip，实际回读为 0。
6. 图被禁用后键盘焦点丢到 body：禁用前条件接续到历史按钮；不抢走已转移到输入框的焦点。
7. 笔记本宽度添加按钮被草稿覆盖：缩小该断点的示例窗口；1024px 框体复测按钮下缘 459.22、草稿上缘 485.20，留出约26px。
8. 深色介绍标题强调色过暗：改用青绿。
9. 英文弯引号受 CJK 字体回退影响：英文页面采用 Latin-first 字体栈；控制标题避免 in. 单独成行。

## 截图索引

- [中文最终首屏](../previews/website-zh-desktop.jpg)
- [英文最终首屏](../previews/website-en-desktop.jpg)
- [英文深色主题](../previews/website-en-dark.jpg)
- [中文移动端成功态](../previews/website-zh-mobile.jpg)
- [中文移动端发布说明](../previews/website-zh-mobile-release.jpg)
- [不确定状态](../previews/website-unknown.jpg)
- [操作与控制章节](../previews/website-en-control.jpg)

`website-zh-desktop-v1.jpg` 为第一轮审查证据，不是最终推荐版本。所有截图中的图像、草稿文字和附件都是本专项制作的合成示例，不含私人截图或真实聊天记录。

## 尚未验证

没有执行 Safari / Firefox / VoiceOver、实际触屏设备、真实 Mac Dock/菜单栏、Lighthouse 或受控网络性能基准；没有测试任何真实 ChatGPT 附件操作。完整屏幕阅读器审计和浏览器矩阵应在正式采用阶段进行。开发浏览器日志出现扩展自身的 metadata 错误，未把这些计为网站脚本错误，也不把有限日志检查包装成全站零错误证明。

实际网页源文件体积可由仓库直接核对；未将字节数换算为未经测量的加载时间或转化率。
