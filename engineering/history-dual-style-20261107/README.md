# 历史双样式原生候选

正式基线为 `41217b2dfb5feb0a0d609b7b369d448d8eb5a344`（PR #44 后的实际 main）。
本轮保留 Beta 2 默认列表，新增可选图像网格。没有安装、合并 main、访问生产数据库或更改截图附件实现。

## 直接查看

- [原生截图总览](evidence/native-candidate/index.html)：18 张公开副本，来自完整 ARM64 App 的实际 WindowServer 窗口。
- [逐项原生控件和重启结果](evidence/native-candidate/acceptance.json)。
- [外部鼠标、键盘与 AX 结果](evidence/software-gui-acceptance.json)。
- [实现及偏好所有权](IMPLEMENTATION.md)、[原始失败记录](OBSERVED-FAILURES.md)。

截图全部使用隔离环境的合成图。私有原件保留完整 ICC；公开副本去除含显示器序列号的 ICC/EXIF 元数据，IHDR 和 IDAT 原样保留，没有重绘或生成图片。颜色审查以私有原件和实际 App 为准。原始失败、原始分支检查点和工具失败记录都完整保留，不推送含设备标识的旧本地图片对象。

## 已执行的原生检查

候选源码：`a94fc6aea99455291bb85af16f1470c1517cb4e7`。
ARM64 App 二进制 SHA-256：`ded6da169ed4bacd0ca5eefec9f42c29f108c5ea08882ade58cc70bd47c21c4c`。
完整 App 是 0.2.0 (2) development/ad-hoc 候选，未公证。公开审查分支从正式 main 新建，运行源码和资源逐对象继承该候选；原本地实施历史保留，不进行 rebase、squash 或 force-push。

| 范围 | 实际结果与证据等级 |
| --- | --- |
| 首次默认列表；设置与历史两入口即时同步 | 完整隔离 App 原生控件 PASS |
| 搜索、筛选、第一页、选中 UUID、详情、原图 200% | 原生控件 PASS；第二页状态由 AppKit XCTest 覆盖，三个实际收录样本没有伪造第二页 |
| 原图打开时网格缩略图继续加载 | 实际解码和 WindowServer 截图 PASS |
| 两样式的查看原图、移出、恢复 | 同一数据 owner 的真实控件与存储动作 PASS；只有本次合成样本执行移出和恢复 |
| 浅色、深色、标准与最小窗口、滚动到操作区 | 19 张原始窗口截图；15 项按钮滚动可达检查 PASS |
| 重启保留 imageGrid | 同一二进制、新进程、同一隔离根；全部 SQLite 表、媒体、配置和偏好快照相等 |
| 外部鼠标点击、方向键选图、空格预览、Escape、两向样式菜单 | 9 项 CGEvent + 外部 AX 检查 PASS；这是系统接收的软件 GUI 事件，不是物理硬件输入 |
| 键盘焦点 | 修复切换后首个方向键无效；实际 Down 移动到第三个 UUID，Space 打开对应原图。Tab/Shift+Tab 原始观察保留，未宣称完整全键盘导航认证 |
| VoiceOver 标签 | 外部 AX 确认 cell 角色、完整 UUID identifier、时间/尺寸/状态标签、selected；未宣称完整语音朗读验收 |
| 高对比度 | 新增实际 AppKit 条件测试，由既有一次性 CI 高对比度阶段执行；不可用时明确 XCTSkip，本机系统设置未改变 |
| 正式五项 CI | 在独立 PR 的实际 merge ref 执行；此源码记录不预填尚未发生的 CI 结果 |

7 项原生控件用例全部通过，运行与重启日志均无已知 FlowLayout 警告。外部 GUI 操作后再次调用同一只读快照逻辑，全部 SQLite 表、媒体和偏好与重启后完全一致，operation / START 均为 0。正式 App 二进制仍为 `e0505af18b2828c3acf88477e6fbb382c975c9097b1de1a222a19e5383e36c39`。

首次 PR CI 在 ARM64 和 Intel 上均记录了一个几何测试失败，原记录保留于 [CI 失败与原生探针证据](evidence/ci-layout-fixture-correction.json)。测试把 clip 固定为 533 点，却要求缩窄的 document 包含全部 FlowLayout 排列；无窗口 AppKit 探针精确复现四个失败数值。修正仅限测试：瞬态检查单项尺寸及边距安全，一致视口下继续检查全部真实 frame 包含、非重叠和 UUID 选择。没有放宽容差、删除断言或改产品布局；最终 CI 结果以 PR 的具体运行记录为准。此测试修正之后，候选 App 的全部源码、资源和构建脚本仍逐对象相同，无需重建或重新制作已验收窗口截图。

## 实际失败和有限修复

保留旧候选的失败和仅限控件通过的结果，没有将通过范围扩大。

- 详情图固有宽度把 680 点最小窗口撑到 941：复用现有无固有尺寸的预览视图。
- 网格 AX 单元身份和选中态缺失：补 cell 语义及同 UUID 选择。
- 原图可见时缩略图一直占位：独立取消状态，继续共享现有单一串行解码队列。
- 只调整 item 尺寸仍有布局警告：[原始诊断](evidence/layout-transition-diagnosis.json) 记录旧 200 点卡片在 194 点塌缩视口仍参与布局。把隐藏旧网格提前到约束切换之前，最终运行警告为 0。
- 切换后方向键退回搜索框：仅将旧 renderer 的 first responder 交给新 renderer，保留实际搜索编辑器。外部键盘结果已验证；菜单返回后即时 AX 焦点快照可能滞后，原工具断言保留，最终以实际下一次按键和对应 UUID 为准。

最小窗口初始截图中，详情底部位于可视区域之外；实际滚动验证证明操作可达，因此没有重复创建滚动容器或改变原布局。

## 复验入口与保护范围

在 macOS 上构建后执行 `scripts/run-history-review.sh /absolute/Riftlet.app /new/private/result-directory`。
脚本只建立新 UUID 隔离根，先执行真实 AppKit 控件，再正常退出并以同二进制新进程核对持久化；遇到真实布局警告即失败，不用旧 PASS 代替。原生 XCTest 在既有 App/UI targets；CI 输出正常及实际高对比度的独立日志。

`historyDisplayStyle` 在普通使用中只写 `UserDefaults.standard` 的独立键，合法值 `current` / `imageGrid`，缺失或无效读取 `current` 且不改旧值。仍只有一个 `RiftHistoryController`，无新数据库、迁移、导入或历史删除机制。

`Sources/RiftletAdapters`、`Sources/RiftletCapture`、`Sources/RiftletCore`、`Resources` 和 `website-assets/riftlet.svg` 与正式基线逐 Git 对象相同。正式品牌 `#19B7A4` / `#087C70` 保留。

## 设计导出收口

独立设计分支已推送 `6f377510f8813025a6744d672730d919bdb8e9d7`，原始 `276574a` 和失败记录保留。
修复可复现构建及导出校验，Chrome-headless-shell 的真实 Chromium 运行 13/13、构建故障注入 5/5 通过，最终独立 HTML SHA-256 为 `4fe1a371bf50cbeafd59a97aef26fb6b81bc4462ee9fb9ca284346750815c512`。
[设计分支与导出文件](https://github.com/haohongfei2001-png/Riftlet/tree/6f377510f8813025a6744d672730d919bdb8e9d7/design/experience-20261107)。这些浏览器证据不充当原生 AppKit 证据。
