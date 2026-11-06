# Riftlet｜完整产品体验设计

**最终推荐：让截图属于边缘，让工作继续。**

这里是可操作的统一高保真方案，覆盖桌面微图与动态、菜单栏控制中心、六页设置、截图历史、首次使用、错误恢复、浅深模式与关键辅助功能。基于正式 main `71d726c5d6416346b84e1ac93047af5bb321d925` / 个人 Beta 2 `0.2.0 (2)`，全部工作位于独立设计目录，未修改生产App。

## 直接查看

**下载并双击 [Riftlet-Experience-Prototype.html](exports/Riftlet-Experience-Prototype.html)**。单文件包含全部界面、合成图片和真实前后对照，可断网使用，不需要构建或安装依赖。

开发源码入口：[prototype/index.html](prototype/index.html)。直接打开或使用任意静态文件服务。没有网络API、真实截图、数据库或聊天连接；所有操作只改变示例内存状态。

1. 桌面体验：直接点微图；也可“添加截图”“连续两张”。选择正常/无目标/明确失败/结果不明，观察不同状态。右键、悬停、零遮挡、四种壁纸和减少动态均可试。
2. 控制中心：两项开关独立；主截图入口、历史、最新截图、收起全部、更多和错误恢复均可操作。
3. 设置：六页完整，参数改变驱动预览，需应用的编辑保留预览/应用/放弃流程；可模拟保存失败与显示器断开。
4. 历史：六筛选、搜索、选择详情、原图缩放和可恢复记录。待核实记录不会自动再次附加。
5. 首次使用：介绍、权限、位置与完成状态；权限仅演示，不请求真实授权。
6. 前后对照：原生Before + 实际渲染After。统一逻辑比例，图片不裁切；来源与边界直接标注。
7. 右上角切换浅深；“设计系统”查看界面中的统一规则。

可播放动态：[MP4](exports/Riftlet-Motion.mp4) / [WebM](exports/Riftlet-Motion.webm)。录像由最终原型的真实帧按时间戳制作，非原生生产录屏。微图完整连续体验以可运行原型为准。

## 设计与交接

| 文件 | 作用 |
|---|---|
| [DESIGN-DECISION.md](DESIGN-DECISION.md) | 独立产品判断、最终方案、必改/推荐/审美备选 |
| [IMPLEMENTATION-SPEC.md](IMPLEMENTATION-SPEC.md) | P0状态、几何、动效、原生组件映射、全部界面规格 |
| [TOKENS.json](TOKENS.json) | 可读机器格式的颜色、排版、几何与动效角色 |
| [SETTINGS-MAP.md](SETTINGS-MAP.md) | 16项参数、六页控件、默认与兼容关系 |
| [SETTINGS-HANDOFF.md](SETTINGS-HANDOFF.md) | 原生owner、保存、权限、焦点与兼容实施细则 |
| [VALIDATION.md](VALIDATION.md) | 已完成检查、证据身份、未声称通过的原生范围 |
| [INDEPENDENT-REVIEW.md](review/INDEPENDENT-REVIEW.md) | 非作者独立复核、初审问题与修复闭环 |
| [REFERENCES.md](REFERENCES.md) | 成熟产品的具体细节→Riftlet设计变化，不含市场研究 |
| [evidence/](evidence/) | 原生基线原图、网页实际渲染、检查报告与复现脚本 |

## 品牌与历史显示方式

交互原型顶部新增「历史双样式」审阅页，可同时查看两种完整窗口布局；历史页本身仍可通过设置即时切换并沿用同一份示例状态。

正式 Logo 原样复用 `website-assets/riftlet.svg`；品牌主色 `#19B7A4`、深色辅助 `#087C70` 冻结不变。原型提供「当前视图」（默认，保留 Beta 2 历史样式）与「图像网格」两种历史呈现，可在设置「历史与存储」切换，也可在历史窗口直接切换。两种样式共用同一历史数据、搜索、筛选、分页、预览和恢复，不创建第二套历史系统。

## 保持的核心契约

无截图无裂缝；默认三张、可调1–10；支持静止零遮挡；位置由用户掌控；入缝只提供无/磁力；真实START后快速吞噬；不自动发送；不改变已有附件；无成功Toast；明确失败恢复可点；UNKNOWN不自动重生或重试；收起/归档不等于永久删除。

原型推荐行距68pt，生产基线默认60pt；其余用户个性化不被迁移。网页命中范围、模拟权限、样例存储值与事务等待时间不能照搬进生产。原生实现以契约和现有状态模型为准。

## 检查点与复现

- 独立远程分支：`codex/design-experience-20261107`。
- `9991dfef…`：完整主要界面原型首个远程检查点。
- `251ee3e…`：统一视觉、状态与16项设置完成；32帧实际渲染。
- `7d19037…`：最终Fit落位、焦点/系统偏好与历史修复；动态和定向验证。
- 后续提交：真实对照、完整规格、独立复核、离线导出和交付检查。最终hash以分支HEAD为准。

离线导出的生成与验证已统一到 [tools/build_delivery.py](tools/build_delivery.py)。2026-11-07 的原始导出曾因 `$$` 被变为 `$` 而无法初始化，现已修复；保留的真实错误、原始 HTML、13 项无界面交互回归与新浅深截图见 [导出修复证据](evidence/export-repair-20261107/README.md)。该 604d5f4 修复阶段的原型界面源码、品牌 SVG 与颜色未改。

在仓库根目录执行（虚拟环境放在设计目录外）：

```sh
python3 -m venv /tmp/riftlet-design-export-venv
/tmp/riftlet-design-export-venv/bin/python -m pip install -r design/experience-20261107/tools/requirements.txt
/tmp/riftlet-design-export-venv/bin/python design/experience-20261107/tools/build_delivery.py
/tmp/riftlet-design-export-venv/bin/python design/experience-20261107/tools/test_delivery_validation.py
```

需要 Node.js 执行强制语法检查；中文图版默认使用 macOS 系统黑体或 Linux Noto CJK，也可显式传入 `--font /path/to/CJK-font`。缺少 Node 或中文字体会报错，不静默输出坏文件。构建记录依赖、字体及导出 hash 到 `exports/build-report.json`；相同源码、依赖与字体环境下重复构建的 HTML、PNG、MANIFEST 和 ZIP 应完全一致。不同平台字体不承诺图版逐字节一致。

实际浏览器回归使用独立安装的 Playwright 与其 **chrome-headless-shell**，只创建临时测试上下文；不连接用户浏览器。设置 `PLAYWRIGHT_MODULE` 为该依赖的模块路径、`HEADLESS_BROWSER` 为其 headless-shell 可执行文件后，运行：

```sh
node design/experience-20261107/tools/test_delivery.cjs --out /tmp/riftlet-design-export-headless-new-run
```

脚本拒绝覆盖已有结果。验证/文档完成后再运行一次生成脚本，使 MANIFEST/交付 ZIP 包含最终证据。总览/Before-After 图版仅重排已保留的历史截图，当前品牌与双样式的新截图在本轮证据目录；不重绘原生 Before，也不把旧录像当作新验收。

这是一份可以直接移交Codex的设计候选。物理菜单栏、真实附件、原生动画、多屏和长期体验需要在独立原生实现中验收；本轮没有用网页检查提前代替这些结论。


### 并发修复的合并交付

本地导出修复与远端七个修复/CI 提交按双亲历史合并，旧失败说明和原始证据保留。仅把「设计系统」里两处品牌色说明同步到 canonical `prototype/app.js`，再由正式管线生成 HTML，不手工修补产物。合并状态重新执行 13 项 headless 交互和 5 项生成门禁均通过；详见 [合并复验](evidence/export-merge-20261107/README.md)。正式合并提交与远端 workflow 结论以实际 Git/GitHub 记录为准。
