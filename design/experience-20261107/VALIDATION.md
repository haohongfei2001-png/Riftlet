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


### 双样式并排原型（源码核对）

新增「历史双样式」场景，同屏呈现 Beta 2 列表样式与图像网格样式；两栏共享同一组样例记录与选中记录。历史页内的 `historyDisplayStyle` 切换与设置页的选择均连接同一原型内存偏好。该并排场景是视觉审阅辅助，不是第三种生产历史模式。尚未进行浏览器运行与视觉截图验收。


## 2026-11-07 离线导出修复与实际无界面回归

本节更新上方品牌/双样式修订中“未运行浏览器”的历史状态；旧记录保留。初始 `276574a44485c17821a5ce3e0195116e83e9fad8` 的 HTML 在独立 Chromium headless shell 实际报 `SyntaxError: Identifier '$' has already been declared`，页面未初始化。该文件 4 处 `$$` 已被压为 `$`。未修改的正式 Python 生成脚本能正确保留它们；历史错误文件的具体生成命令未证实，不能归因于 Python `str.replace`。

修复给唯一生成管线增加逐字源码一致性、Node 语法、完整资源内嵌和模板标记检查，固定依赖、记录中文字体身份并稳定 ZIP 元数据。原型 JS/CSS、品牌 SVG、配色和所有旧原生/设计证据未修改。

| 检查 | 本轮实际结果 | 范围 |
|---|---|---|
| 旧单文件故障 | REPRODUCED | 原始 HTML/错误/空白截图均保留 |
| 未改 Python builder | PASS | 恢复 4 处 `$$`，证明旧已提交导出与规范源不一致 |
| 生成门禁故障注入 | 5/5 PASS | 真旧坏导出、`$$` 损坏、源码自身语法坏、遗漏资源、陈旧 CSS 被拒绝；当前文件可通过 |
| headless-01 | 10 PASS / 3 FAIL，保留 | 首项空态断言误计详情空态；后两项因未清搜索连带失败，详见 interpretation |
| headless-02 | 13/13 PASS | 真实 DOM click/select/fill/键盘；页面错误 0，外网请求 0 |
| 当前浅深图 | 8 张新 PNG | 两种历史、双栏审阅、历史设置；合成内容 |
| 原生/真实附件 | NOT_RUN | 网页结果不替代 AppKit、真实数据/附件、IME 或 VoiceOver 验收 |

[证据索引与精确 hash](evidence/export-repair-20261107/README.md)。本轮使用单独的 Playwright 测试引擎与临时上下文，未启动可见浏览器、未使用用户 profile、未连接已有浏览器或访问生产 App。

### 远端并发修复的当时记录（原文保留）

以下两段描述远端当时的排查与规范化方式；合并后的实际生成策略及复验见下一节，不能把历史 no-op 替换视为当前管线。

### 空白 HTML 根因与修复（2026-11-07）

Chromium 实测发现：离线导出文件的 app helper 被错误序列化为 `const $=..., $=...`，造成内联脚本解析错误 `Identifier '$' has already been declared`，因此原型根节点保持空白。已将第二个 helper 标识符恢复为 `$$`，并在构建脚本加入防回归规范化；验证流程增加四个源文件拼接后的 `node --check` 与 Chromium 实际打开/交互检查。此前交付的预览链接不应继续使用，以修复后的新浏览器检查结果为准。


### 第二轮空白/交互故障修复

浏览器堆栈进一步定位到导出文件中的三个 `querySelectorAll` 调用点也被错误写成单元素 `querySelector`：`fit()` 查询 `[data-compare-size]`，以及弹窗 inert 管理中的两组元素遍历。由于桌面场景没有 compare 节点，`fit()` 对 null 读取 `.length`，并中断后续 `bindSettings()`，造成设置选择看似可改但偏好不更新。现已恢复三个 `$$` 调用点；构建脚本对 helper 声明和全部调用点加入防回归规范化。


## 2026-11-07 并发修复合并复验

待合并的两个精确父提交为本地 `604d5f4530690d534c975fd0a83759648a7c7f04` 与远端 `ada4ade59b0d934e85a7f2ea373e46cb278ce855`。远端从共同基线 `276574a` 起的七个修复/CI 提交保留在原历史中，不重写或丢弃；由主代理完成双亲合并。完整提交列表见 [merge-inputs.json](evidence/export-merge-20261107/merge-inputs.json)。

合并前两侧四个 prototype JS 源文件逐字一致；远端四条“规范化” replacement 在这些正确源码上均不匹配。最终 builder 保留本地字面内联、源码一致性/Node/资源门禁，不以事后修改生成 HTML 代替规范源码。远端有效的新增色值说明修正已移入 `prototype/app.js`：「设计系统」中的 `#367B6B / #92CBB4` 改为 `#19B7A4 / #087C70`。本次 canonical 变更仅这两个展示字符串，实际颜色 token、SVG、交互逻辑与其他 prototype 源码保持原字节。

这不修改或否定 604d5f4 阶段“prototype 原源未改”的事实；`evidence/export-repair-20261107/` 的所有记录保持原字节。上方远端两次故障说明也完整保留。远端新增 workflow 原逻辑保留，仍是较小的 cloud smoke；本轮没有扩大它或手动重复触发。

合并文件状态下，隔离 headless **13/13 PASS**，页面错误 0、外网请求 0；原来的 5 项生成门禁测试 **5/5 PASS**，未删改断言。新导出 HTML SHA-256 为 `4fe1a371bf50cbeafd59a97aef26fb6b81bc4462ee9fb9ca284346750815c512`。新 8 张截图和精确 runner/HTML hash 记录在 [本轮结果](evidence/export-merge-20261107/headless-01/results.json)。这是一次新的实际网页检查，不引用先前 13/13 冒充本轮执行，也不声称原生测试。

最终 HTML、MANIFEST、相关图版和 ZIP 由同一正式 builder 重建；清单覆盖当前文件，ZIP 内文件逐字与清单和目录核对。最终 commit/远端 workflow 结果由主代理在真实提交后记录，本文件不猜测未来 SHA 或 CI 结论。
