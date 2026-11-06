# 六页设置：设计、字段与原生实现映射

基线：`71d726c5d6416346b84e1ac93047af5bb321d925`，个人 Beta 2 `0.2.0 (2)`。本目录只包含设计原型。下面的“保存”“权限”和截图样本均为原型内存状态，不代表操作过系统偏好、生产配置或用户图片。

## 最终设计判断

保留六页结构，保留全部已有效的设置能力。把重复的白卡片和说明块，改成同一内容面上的对齐行与浅分隔线。空间主要留给位置示意、外观选择和动效预览；普通开关不再单独套卡片。

设置窗口由父原型统一为 `780 × 584 pt`、导航 `176 pt`、内容边距 `32 pt`。这是推荐的新窗口比例；基线 `SettingsNativeStyle` 的初始窗口为 `960 × 684 pt`、导航 `184 pt`、最小窗口 `760 × 540 pt`。窗口可滚动，低频选项仍可展开；不通过删除设置来压缩尺寸。

| 页面 | 首层内容 | 收纳但保留的内容 | 与现有原生代码的关系 |
| --- | --- | --- | --- |
| 通用 | 当前收录状态、外观小样、暂停收录、隐藏裂缝、登录项状态 | 使用引导、反馈 | 原有独立域与动作，不合并暂停和隐藏 |
| 位置与显示 | 显示器、六位置、实时示意、数量、藏入比例 | 尺寸与留白、精细参数、旧版位置 | 保留显示器身份与断开后的临时回退，不写回成新偏好 |
| 截图 | macOS 三种熟悉入口、系统截图位置、内置入口、默认方式 | 跳转截图权限 | 延迟和指针继续属于每次截图会话，不新增全局偏好 |
| 动效 | 无/磁力吸引、同一舞台主动预览到达与吞噬 | 四个独立时长 | 不把“无入缝”误解释为取消 START 后的反馈 |
| 历史与存储 | 历史入口、归档时限、存储、收起全部 | 小数小时自定义 | 收起和归档不删除文件；不新增保留期限 |
| 权限与帮助 | 截图位置、Chrome 自动化、屏幕录制用途与状态 | Chrome JavaScript 说明、诊断与配置 | 三项权限独立；不把自动化授权当成当前聊天可用 |

### 必须提升

1. 消除重复卡片产生的视觉切割；普通设置同列对齐，以间距而不是反复框选表达层级。
2. 用一个可点击的屏幕示意明确六位置的空间关系。位置选择不影响用户的显示器偏好。
3. 统一字段编辑语义：开关/枚举立即提交；数字保留草稿，应用/放弃只作用于当前页；保存失败在原位置恢复。
4. 登录项不可用时明确禁用，保留简短原因，不画出已经可工作的开关。
5. 深色强调色按钮使用深墨字。`#92cbb4` 上白字对比仅 `1.84:1`；原型使用 `#162c23`，计算对比 `8.05:1`。

### 明显提高品质的推荐改动

外观使用三个精简窗口小样；动效合并到一个舞台主动播放；历史入口采用三张纸片的空间关系，与主微图呼应。全页少用边框，数值/单位采用等宽数字与柔和的输入面，所有页面共享同一强调色和文字层级。

### 纯审美备选

仅包括侧栏具体暖度、示意图壁纸、外观小样的画面内容。它们不是功能或架构改动，不应延缓整体设计的采用。

## 完整字段表

原型以 `state.settings` 保存偏好，`state.settings.layout` 保存已应用数值，`state.settings.draft` 保存未应用原始字符串。未选择/不适用与“值为 0”分别处理。

| 原生字段/动作 | 原型字段 | 单位与范围 | 显示位置 |
| --- | --- | --- | --- |
| `setCollectionPaused` | `paused` | Bool | 通用 |
| `setHidden` | `hidden` | Bool | 通用 |
| `appearance` | `appearance` | system / light / dark | 通用 |
| `loginEnabled` | 不创建虚假可用状态 | 当前候选不可用、禁用 | 通用 |
| `selectDisplay` | `display`，另保留 `displayDisconnected` | 原生实现使用实际 ID / UUID | 位置与显示 |
| `selectPlacement` | `placement` | leftTop / leftMiddle / leftBottom / rightTop / rightMiddle / rightBottom；null 为旧版 | 位置与显示 |
| `visibleCountPreference` | `layout.visibleCountPreference` | 1–10，整数 | 位置与显示 |
| `hiddenFraction` | `layout.hiddenFraction` | UI 0–90%，原生值 0–0.9 | 位置与显示 |
| `outerInset` | 同名 | 0–256 pt | 尺寸与留白 |
| `fitWidth` / `fitHeight` | 同名 | >0 且 ≤256 pt | 尺寸与留白 |
| `rowPitch` | 同名 | >0 pt，保留原生无额外上限的语义 | 尺寸与留白 |
| `numberFontSize` | 同名 | >0 且 ≤32 pt | 尺寸与留白 |
| `numberGap` / `leftPadding` | 同名 | ≥0 pt，不新增上限 | 精细参数 |
| `minimumHitWidth` / `minimumHitHeight` | 同名 | >0 且 ≤256 pt | 精细参数 |
| `firstCenterFromTop` | 同名 | ≥0 pt；只在 placement 为 null 时可编辑 | 精细参数 |
| `setEntryEnabled` | `entryEnabled` | Bool | 截图 |
| `setCaptureMode` | `captureMode` | window / region / fullScreen | 截图 |
| `setArrival` | `arrival` | none / magnet | 动效 |
| `pressDuration` | `layout.pressDuration` | UI 0–3000 ms，原生秒 | 动效精细参数 |
| `swallowDuration` | `layout.swallowDuration` | UI 0–3000 ms，原生秒 | 动效精细参数 |
| `shiftDuration` | `layout.shiftDuration` | UI 0–3000 ms，原生秒 | 动效精细参数 |
| `returnDuration` | `layout.returnDuration` | UI 0–3000 ms，原生秒 | 动效精细参数 |
| `archiveHours` | `archiveHours` / `archiveDraft` | ≥0，支持小数；0 对应关闭/null | 历史与存储 |
| `historyDisplayStyle` | `historyDisplayStyle` | `current`（默认）/ `imageGrid`；独立展示偏好 | 历史与存储 |

`historyDisplayStyle` 不属于 `SettingsField` 或 layout patch，不参与布局草稿/恢复默认/归档保存。建议由 `RiftHistoryController` 与设置页共用一个轻量 UserDefaults key；读取缺省值为 `current`。它只控制同一页历史数据的 renderer，不得触发刷新数据源、清空筛选、重置分页或更改选中 UUID。

所有显示器、权限、存储读数与截图均为演示样本。原型不读取用户电脑。

### 默认值与兼容值

设计模块自身继承 `72 × 56 pt`、藏入 `25%`、rowPitch `60 pt`、内缩 `6 pt`、编号 `11 pt`、numberGap `8 pt`、leftPadding `4 pt`、最小行 `44 × 44 pt`、旧版 firstCenter `202 pt`，以及轻按/吞噬/补位/回归 `60/120/160/180 ms`。父原型可在新方案中展示 rowPitch `68 pt`，但不得因此迁移或覆盖已有用户偏好。

归档默认显示“不自动归档”，避免把未确认的 24 小时建议写成正式默认。演示选择磁力吸引以便观察方案；原生未选偏好仍保留未选状态及现有 `none` fallback，不能因设计演示改写。

`lineWidth`、`lineExtension`、`emptyTraceLength`、`screenPadding`、旧 `arrivalDuration`、`inwardDistance`、旧 `reducedMotionDuration` 是兼容字段，不进入本次新的 patch vocabulary、不被恢复默认值重置。没有可见截图时不能因兼容 `emptyTraceLength` 又画出空缝。

## 动效原型

只由点击“预览入缝/预览吞噬”触发，不循环、不自动播放。

| 演示 | 视觉顺序 | 时间 |
| --- | --- | --- |
| 磁力入缝 | 系统截图位置 → 有弧度的平移与轻微尺度收敛 → 边缘停稳 | 560 ms |
| 无入缝 | 立即出现 | 0 ms |
| 点击后吞噬 | 轻按 → START 示意 → 同一静止裁切平面后退入 → 其他纸片补位 | 60 / 120 / 160 ms，可自定义 |
| 减少动态效果 | 无飞行/空间位移；最多 80 ms 淡出；静态补位 | ≤80 ms |

设置内示意不产生上传，不宣称完成。原生实施必须由已确认的开始附加信号驱动吞噬，不能用动画开始替代后端状态。

## 模块接入

```js
content.innerHTML = RiftSettings.render(page, state);
const dispose = RiftSettings.bind(content, state, patch => {
  Object.assign(state, patch);
  // appearance 用于父壳主题；settingsAction 用于跨界面动作。
});
```

`bind` 自身更新可见控件与预览，避免父壳为每个键入字符重建设置窗口。父壳可以只消费回调，切换页面时重新 `render/bind`。重复绑定会清除旧监听器与运行中的示意动画。

回调 `settingsAction` 可取：`history`、`onboarding`、`capture`、`feedback`、`help`、`clearVisible`，以及不产生系统副作用的权限/配置入口说明动作。`appearance` 另行发出 system/light/dark，父壳按系统外观解析。数值编辑、未保存页切换和当前页的应用/放弃都不丢弃其他页的草稿。

供父壳关闭确认使用的纯函数：

```js
RiftSettings.validateDrafts(state, 'all'); // { ok, errors, values, archiveHours }
RiftSettings.applyDrafts(state, 'all');    // 上述结果 + settings；无效时不应用
RiftSettings.discardDrafts(state, 'all');  // 返回新 settings，不修改原对象
```

scope 支持 `display` / `motion` / `history` / `all`。页面内只提交或丢弃本页字段；退出确认中的“应用全部”才合并全部页与归档时限。原生现有 `applyLayout` 共享数值域，落地时需由现有 field patch 词表明确选择本页字段，不可把一次页面保存意外升级为另一页的提交；保留同一个 owner 与配置文件，不另建持久化架构。

关闭窗口前检查 `Object.keys(settings.draft).length > 0` 或 `settings.archiveDraft !== null`，沿用原生“应用/放弃/取消”确认。原型不是新的设置持久化架构；移交时继续使用 `SettingsProductSnapshot`、`SettingsProductAction`、`SettingsStateModel` 和现有 owner。

### 交互检查点

- [x] JS 语法检查通过。
- [x] 全部 16 个当前有效数值字段映射完整；旧版字段仅在适用时出现。
- [x] 不新增行距/间距等原生没有的范围限制。
- [x] 无网络调用、系统截图、文件写入或浏览器自动化。
- [x] 数字原始草稿、分域动作、显式应用与放弃保留。
- [x] 纯函数行为检查：显示页只应用显示草稿；动效页放弃保留显示与归档草稿；退出应用全部保留合法 0 ms 与 1.5 小时；0 尺寸被拒绝；没有原生上限的参数不被原型限制；原始调用对象不被改写；六页均成功渲染。
- [x] `prefers-reduced-motion`、标签、焦点轮廓、文字状态和禁用状态已有实现。
- [ ] 父原型最终截图与真实 AppKit 实施视觉复核另记录；本清单不代替 Mac 验收。

## 主要源码依据

- `Sources/RiftletUI/RiftSettingsCenterPages.swift`
- `Sources/RiftletUI/RiftSettingsCenterRendering.swift`
- `Sources/RiftletUI/RiftSettingsCenterController.swift`
- `Sources/RiftletUI/SettingsProductPresentation.swift`
- `Sources/RiftletUI/SettingsStateModel.swift`
- `Sources/RiftletUI/SettingsNativeStyle.swift`
- `Sources/RiftletUI/RiftConfiguration.swift`
- `Sources/RiftletUI/ArrivalMotionMode.swift`

本次没有修改上述生产文件、权限、上传流程或数据规则。
