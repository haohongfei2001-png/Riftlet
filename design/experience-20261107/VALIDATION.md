# 验证结果与证据边界

## 结论

当前方案可作为统一的高保真设计候选交付。独立审查推荐采用；交互原型、深浅实际渲染、关键状态与最终动态证据已完成。此结论只针对设计候选及网页原型，**不是新原生版本已安装或真实附件链路已经验收**。

## 已完成

| 检查 | 结果 | 证据 |
|---|---|---|
| 正式 main 与版本 | `71d726c5…`，`0.2.0 (2)` | GitHub / 原生被动观察 |
| 原生截图来源 | `a5aefd3d…`隔离native审核；与main UI/App源码无diff | `evidence/native/observations.json` |
| 实际Mac观察 | 进程、AX、窗口信息只读；没有激活或点击生产App | `evidence/native/observations.md` |
| 六页设置字段完整性 | 原生16项全部映射，无缺失/额外 | `SETTINGS-HANDOFF.md`、`SETTINGS-MAP.md` |
| 独立核心状态复核 | 9组PASS | `review/INDEPENDENT-REVIEW.md` |
| 独立设置验证 | 8组PASS | 同上 |
| Mac Chrome实际渲染 | 32种界面/状态，无pageerror | `evidence/prototype/full-report.json` |
| 深浅整体一致性 | 浅10界面、深10界面，双人目视完成 | `evidence/prototype/contact-light.png`、`contact-dark.png` |
| 窄屏阅读 | 390px桌面和设置可读，不把整个桌面无限缩小 | 对应mobile PNG |
| 浏览器核心流程 | 成功、无目标、明确失败恢复、UNKNOWN不重生、连续两张PASS | `full-report.json` |
| 最终定向检查 | 历史浅/深footer、modal进入/关闭/Escape焦点、系统偏好映射6项PASS | `final-report.json` |
| 可播放动态 | CDP实际帧及时间戳，最终53帧约10.27秒 | `motion-manifest.json`、`exports/Riftlet-Motion.webm` |
| 生产范围 | 仅design/experience-20261107新增修改 | Git diff / 独立设计分支 |

### 状态验证实际覆盖

无可用目标时微图不吞噬；模拟START先于出队；原有附件和正文保留；UNKNOWN不自动重生；主动收起后迟到失败不覆盖用户意图；显式恢复后的新失败正常重生；连续演示不偷偷重置队列；0ms合法；重绘不会让异步操作继续引用旧DOM；容量与最小行尺寸一致。测试使用合成记录，不向真实聊天附加图片。

设置验证覆盖当前页应用/放弃保留其他页草稿、小数归档、自定义数值范围、零时长、参数范围和六页生成。保存失败的说明已消除“原设置必然回滚”的不实承诺。原生实际有效状态仍须由现有owner返回。

### 视觉检查修复

首次渲染发现历史窗口body固定高度挤出footer，已改为纵向flex、body占剩余空间，浅深均完成实际截图复核。严格浮点断言曾报出0.0000305 CSS px差异；窗口client/offset/scroll高度均582，0.01px容差验证通过，详见最终report。

入缝初稿使用固定scale与较大尾段位移，最终改成真实paper几何、按原图比例Fit、3pt以内收束。最后录像来自 `7d19037611c1228a2397cf44ed47bddd8f390213`；它包含最终P0动作，不用初稿录像冒充。

弹窗焦点、设置重绘焦点、Reduce Motion/Transparency/Contrast和系统外观均有动态映射。网页以matchMedia演示；原生应接NSWorkspace与NSAppearance，不能以浏览器检查替代VoiceOver。

## 图像与录像身份

- `evidence/native/`：原生应用实际捕获的合成隔离审核图；保留原始PNG。
- `evidence/prototype/`：独立Mac Chrome headless上下文实际渲染的网页。独立临时profile，无用户会话，未激活生产App。
- `contact-*.png`：十界面缩略审查板，生成时为251ee3e。历史footer的后续修复以单独final history crop为准；交付总览采用更新后的图。
- `desktop-light-overview.png`：早期完整桌面构图参考；最终P0局部和动态以7d19037为准。
- `Riftlet-Motion.webm`：真实CDP截图按时间戳重放编码，存在抽帧；MP4是便于播放的30fps容器转码，重复帧不代表实际测得30fps。
- 最准确的连续交互仍是可运行原型。录像用于观察过程，不作为原生掉帧率、端到端延迟或60fps指标证据。

`qa-stable.cjs`、`qa-final.cjs`、`record-final.cjs`保存实际检查方法；脚本中的临时路径是当次环境记录，复现时应换为当前独立checkout。不应对生产App运行这些网页脚本。

## 尚未声称通过

真实物理菜单栏点按、原生动画与高刷帧节奏、全屏/Spaces/Stage Manager、两块真实显示器与断开恢复、Retina混合DPI、VoiceOver、原生中文输入、真实Chrome附件事务以及数小时持续使用。没有当前桌面原生Before录像，也没有臆造一个。

这些是Codex接入本设计后的原生验收项目，不阻碍当前可评审设计的完整交付。当前安装版本、生产偏好、数据与截图链路均未改动。


## 2026-11-07 品牌冻结与历史双样式修订核验

| 项目 | 本轮状态 | 说明 |
|---|---|---|
| 正式 Logo | SOURCE_VERIFIED | `prototype/assets/riftlet.svg` 以正式 `website-assets/riftlet.svg` 原始内容替换；原型品牌、菜单栏与引导标记统一引用该文件。 |
| 品牌色 | SOURCE_VERIFIED | Light/Dark accent 固定 `#19B7A4`；深色辅助 `#087C70` 写入品牌 token；旧 `#367B6B` / `#92CBB4` 不再作为主强调色。 |
| 历史默认 | SOURCE_VERIFIED | `historyDisplayStyle` 默认 `current`；新图像网格为 `imageGrid`。 |
| 设置入口 | SOURCE_VERIFIED | 「历史与存储」新增独立显示方式选择，不进入 layout/archive draft。 |
| 共享数据路径 | SOURCE_DESIGN_SPECIFIED | 原生继续使用 `RiftHistoryController` 的 `entries` / `displayed` / `pageOffset`、`HistoryPresentation` 和 `HistoryPreviewLoader`；本轮未修改 Swift。 |
| 离线高保真原型 | REBUILT | `exports/Riftlet-Experience-Prototype.html` 已从当前 prototype 源码重新内联生成。 |
| 原生交互与截图验收 | NOT_RUN | 本轮未运行浏览器/Chromium QA、未生成新浅深截图或新动效录像；既有 PNG/MP4/WebM 属于前一设计版本，不能当作本轮品牌与双样式的验收证据。 |
| 生产影响 | NONE | 未修改 main、Beta 2、数据库、用户截图或生产偏好。 |

本节是源码与规格核对，不应标记为视觉实机 PASS。下一步由 Codex 在独立实现分支完成 AppKit 双 renderer、偏好同步、浅深截图与交互回归；不得把网页原型测试等同于原生验收。
