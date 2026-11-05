# 原型源文件

这是对现有 Quiet Edge 窗口语言与当前 main 设置结构的专项补齐。不是上一条中断会话原件的逐字恢复。`inherited-helpers.js` 的 `escape`、`icons`、`button`、`toggle`、`settingRow`、`titlebar`、`frame` 从 main 的 `design/final-system-20261028/prototype/windows.js` 直接提取；原文件保留。

运行 `python3 build.py` 产生根目录单文件 `Riftlet-Settings-Prototype.html`。无需联网或安装，全部为内存中的合成状态。可以直接打开单文件，也可使用本目录 `index.html`。

## 演示入口

- 设置六页：通用、位置与显示、截图、动效、历史与存储、权限与帮助。
- 控制中心四种典型状态：正常、暂停、隐藏、需要处理。暂停与隐藏为两个独立布尔值，可同时打开。
- 首次使用：认识、连接、选择位置。允许稍后配置，未完成时可从原步骤继续，不把模拟授权当真实权限。
- 右键菜单：与控制中心共用同一动作状态。
- 评审工具栏不属于 App。可切浅/深色、新装建议/当前 main/旧版值、断屏/重连、失败、减少动态。断屏先使用临时屏幕，重连后只显示恢复入口，由用户主动回到已选显示器。

## 设置样本

`recommendation`：本轮新装建议，静止遮挡 0%，距边 6pt；不是当前 main 已有默认值的宣称。

`current`：当前 main 的 `RiftConfiguration()`，静止遮挡 25%，距边 6pt。

`legacy`：旧 JSON 缺失布局新键时保留 nil placement / legacy 来源、14pt 缺省距边；其余现有值保留。样例外屏 ID/UUID 是合成标识。

## 可执行检查接口

`window.RiftletDesign` 提供 `getState()`、`reset({fixture,theme})`、`navigate(page)`、`setView(view)`、`setScenario(name)`、`setFixture(name)`、`setTheme(theme)`、`setFailure(bool)`、`setReduceMotion(bool)`、`applyConfig()`、`validateConfig()`。

页面 ID：`general/display/capture/motion/history/permissions`；视图 ID：`settings/control/onboarding/context`；典型状态 ID：`normal/paused/hidden/attention`。

| 控件 | 定位 |
| --- | --- |
| 页面 | `button[data-page="display"]` 等 |
| 视图 | `button[data-view="control"]` 等 |
| 数字字段 | `input[data-config="hiddenFraction"]` 等，显示值为百分比，毫秒字段显示 ms |
| 滑块 | `input[data-range="visibleCountPreference"]` 等 |
| 应用 | `button[data-action="apply-config"]` |
| 关闭草稿 | `close-window` → `cancel-modal`（继续编辑）、`discard-changes`（不保存）、`apply-and-close`；布局与归档草稿都受保护 |
| 原位恢复 | `button[data-action="reset-page"]` → `confirm-reset`，先更新草稿再应用 |
| 放置 | `button[data-placement="rightBottom"]` |
| 显示器 | `select[data-setting="display"]` |
| 暂停、隐藏 | `input[data-setting="paused"]`、`hidden` |
| 截图入口、方式 | `input[data-setting="entryEnabled"]`、`select[data-setting="defaultCaptureMode"]` |
| 入缝动效 | `input[data-setting="arrival"][value="magnet"]` |
| 自定义层 | `details#custom-display`、`details#fine-display`、`details#fine-motion` |
| 归档 | `select[data-setting="archivePreset"]`，自定义时 `input[data-setting="archiveHours"]`，`save-archive` |
| 历史过滤 | `select[data-setting="historyFilter"]`、`historyRange`；行 `data-record-id`，state.records 含 ISO timestamp，state.historyNow 固定演示日期 |
| 模拟权限 | `authorize-folder` → `permit-folder` 或 `cancel-modal`；Chrome 同理 |
| 引导 | `setup-next`、`setup-back`、`setup-later` |

检查应使用实际 DOM 控件并观察呈现与状态，不把仅调用内部模型函数作为浏览器交互验收。原生 Mac 的焦点、菜单、材质、VoiceOver、权限与真实文件持久化均未由此原型验证。

原型 `state.files` 与 `state.attachments` 是独立合成快照；清空队列仅修改 `records[].visible/status`，可通过前后深比较验证。该结果不代表 SQLite 或真实 ChatGPT 的原生验收。

内置截图默认开启，继承当前 main 的 `Sources/RiftletApp/ScreenshotEntryPreferences.swift` 新建与旧字段缺失默认 `builtInScreenshotEnabled=true`。模拟屏幕权限未允许时，首次内置截图先出现说明和主动模拟授权；不会自行授予权限或自动新增截图。
