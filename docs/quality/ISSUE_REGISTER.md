# 问题台账

基线main `44f745a15ecb3682a9da0bda17f17a5d9fc1f07e`，正式1.0.1（23）；2026-11-14第一版。**22项：P0 1 / P1 4 / P2 15 / P3 2**。下表是综合修复排序；轮次不是只能到那轮才做。P1中的REL001是验收缺口，不宣称为真机复现故障；GOV002单列P2治理债务。

工作量S/M/L为相对范围；风险low/medium/high指回归风险，不是发生概率。未知频率如实标unknown，不编造受影响用户数。各Issue包含位置、条件、证据、建议、风险和验收，重复发现直接补到原Issue。

| 顺序 | ID | 级别 | GitHub | 问题 | 证据类别 | 轮次 | 成本 / 回归风险 | 当前 |
|---|---|---|---|---|---|---|---|---|
| 1 | QA-ATT-001 | P0 | [#78](https://github.com/haohongfei2001-png/Riftlet/issues/78) | 无归属的异步 picker 能收到截图 | CONTROLLED_REPRODUCED | R1 | M / high | OPEN |
| 2 | QA-ATT-002 | P1 | [#79](https://github.com/haohongfei2001-png/Riftlet/issues/79) | 崩溃前已持久化的 prepared 操作重启后滞留 | SOURCE_CONFIRMED | R1 | S-M / medium | OPEN |
| 3 | QA-DAT-001 | P1 | [#80](https://github.com/haohongfei2001-png/Riftlet/issues/80) | 一个非关键配置文件损坏，阻断整个应用且无法从设置恢复 | SOURCE_CONFIRMED | R1 | S-M / medium | OPEN |
| 4 | QA-ATT-004 | P1 | [#81](https://github.com/haohongfei2001-png/Riftlet/issues/81) | 点击回调在主线程同步等待 Chrome Apple Event | SOURCE_CONFIRMED | R1 | M / high | OPEN |
| 5 | QA-REL-001 | P1 | [#82](https://github.com/haohongfei2001-png/Riftlet/issues/82) | 修复候选缺少同一正式包的真实 ChatGPT 冷首图与连续双图验收 | ACCEPTANCE_GAP | R1 | M / high | OPEN |
| 6 | QA-GOV-002 | P2 | [#83](https://github.com/haohongfei2001-png/Riftlet/issues/83) | main 未启用远端保护，源码审查门禁只能事后发现违规 | REMOTE_CONTROL_GAP | R4 | S-M / medium | OPEN |
| 7 | QA-DAT-004 | P2 | [#84](https://github.com/haohongfei2001-png/Riftlet/issues/84) | “重新检查”不重新核对已恢复的私有文件 | SOURCE_CONFIRMED | R1 | S / medium | OPEN |
| 8 | QA-SET-002 | P2 | [#85](https://github.com/haohongfei2001-png/Riftlet/issues/85) | 切换桌面形态后，隐藏的无效参数仍阻断保存 | SOURCE_CONFIRMED | R2 | S / low-medium | OPEN |
| 9 | QA-SET-003 | P2 | [#86](https://github.com/haohongfei2001-png/Riftlet/issues/86) | 「稍后设置」每次重启都会重新弹出引导 | SOURCE_CONFIRMED | R2 | S / low | OPEN |
| 10 | QA-SET-004 | P2 | [#87](https://github.com/haohongfei2001-png/Riftlet/issues/87) | 托盘「可见截图」接受 5–10 张，实际硬上限为 4 张 | SOURCE_CONFIRMED | R2 | S / low | OPEN |
| 11 | QA-SET-001 | P2 | [#88](https://github.com/haohongfei2001-png/Riftlet/issues/88) | 普通设置混用立即保存、布局草稿和归档草稿，公开界面承担过多工程参数 | DESIGN_AND_SOURCE_CONFIRMED | R2 | M / medium | OPEN |
| 12 | QA-SET-006 | P2 | [#89](https://github.com/haohongfei2001-png/Riftlet/issues/89) | 更新和版本被收进「权限与帮助→关于与诊断」，日常偏好也与历史混放 | DESIGN_GAP | R2 | S / low | OPEN |
| 13 | QA-ATT-003 | P2 | [#90](https://github.com/haohongfei2001-png/Riftlet/issues/90) | 正常接收后的历史和设置永久显示“待核实” | SOURCE_CONFIRMED | R2 | S-M / medium | OPEN |
| 14 | QA-GOV-001 | P2 | [#91](https://github.com/haohongfei2001-png/Riftlet/issues/91) | 当前工程入口被旧阶段指令和重复权威污染 | GOVERNANCE_DEFECT | R1 | S / medium | 文档修正已备，待准入 |
| 15 | QA-VIS-001 | P2 | [#92](https://github.com/haohongfei2001-png/Riftlet/issues/92) | 缺少当前正式界面的完整视觉与可访问性验收组 | ACCEPTANCE_GAP | R3 | M / low-medium | OPEN |
| 16 | QA-DAT-002 | P2 | [#93](https://github.com/haohongfei2001-png/Riftlet/issues/93) | 历史增长使启动和每次刷新承担无界工作 | STRUCTURAL_DEBT | R4 | M / medium | OPEN |
| 17 | QA-SET-008 | P2 | [#94](https://github.com/haohongfei2001-png/Riftlet/issues/94) | 旧设置/动效控制器仍作为产品模块和 GUI 验收的一部分，当前界面覆盖需区分 | STRUCTURAL_DEBT | R4 | M / medium | OPEN |
| 18 | QA-DAT-003 | P2 | [#95](https://github.com/haohongfei2001-png/Riftlet/issues/95) | “归档”不回收空间，用户没有安全的本地清理入口 | DESIGN_GAP | R3 | M / high | OPEN |
| 19 | QA-SET-007 | P2 | [#96](https://github.com/haohongfei2001-png/Riftlet/issues/96) | 面向英文官网的首用/权限/设置仍全部硬编码中文 | DESIGN_GAP | R3 | M / medium | OPEN |
| 20 | QA-REL-002 | P2 | [#97](https://github.com/haohongfei2001-png/Riftlet/issues/97) | 公开支持范围与真实安装升级兼容矩阵需要补齐 | ACCEPTANCE_GAP | R4 | M / medium | OPEN |
| 21 | QA-SET-005 | P3 | [#98](https://github.com/haohongfei2001-png/Riftlet/issues/98) | 引导称「选择截图文件夹」，但文件选择器只允许当前系统截图目录 | SOURCE_CONFIRMED | R2 | S / low | OPEN |
| 22 | QA-WEB-001 | P3 | [#99](https://github.com/haohongfei2001-png/Riftlet/issues/99) | 英文官网仍含中文图片替代文本，辅助阅读语言不一致 | LIVE_UI_OBSERVED | R3 | S / low | OPEN |

## 逐项影响与证据入口

### QA-ATT-001

无归属的异步 picker 能收到截图。[GitHub Issue #78](https://github.com/haohongfei2001-png/Riftlet/issues/78)；[具体位置/条件/证据/建议/验收](ATTACHMENT_AUDIT.md)。

影响：all attachment users / conditional async entry；频率：unknown；工作量：M；回归风险：high。

### QA-ATT-002

崩溃前已持久化的 prepared 操作重启后滞留。[GitHub Issue #79](https://github.com/haohongfei2001-png/Riftlet/issues/79)；[具体位置/条件/证据/建议/验收](ATTACHMENT_AUDIT.md)。

影响：users interrupted before dispatch；频率：abnormal exit；工作量：S-M；回归风险：medium。

### QA-DAT-001

一个非关键配置文件损坏，阻断整个应用且无法从设置恢复。[GitHub Issue #80](https://github.com/haohongfei2001-png/Riftlet/issues/80)；[具体位置/条件/证据/建议/验收](STORAGE_AUDIT.md)。

影响：users with corrupt layout/archive preferences；频率：conditional startup；工作量：S-M；回归风险：medium。

### QA-ATT-004

点击回调在主线程同步等待 Chrome Apple Event。[GitHub Issue #81](https://github.com/haohongfei2001-png/Riftlet/issues/81)；[具体位置/条件/证据/建议/验收](ATTACHMENT_AUDIT.md)。

影响：users with slow/unresponsive Chrome；频率：conditional；工作量：M；回归风险：high。

### QA-REL-001

修复候选缺少同一正式包的真实 ChatGPT 冷首图与连续双图验收。[GitHub Issue #82](https://github.com/haohongfei2001-png/Riftlet/issues/82)；[具体位置/条件/证据/建议/验收](AUDIT_REPORT.md)。

影响：all attachment users；频率：release gate；工作量：M；回归风险：high。

### QA-GOV-002

main 未启用远端保护，源码审查门禁只能事后发现违规。[GitHub Issue #83](https://github.com/haohongfei2001-png/Riftlet/issues/83)；[具体位置/条件/证据/建议/验收](AUDIT_REPORT.md)。

影响：all published users indirectly；频率：every main integration；工作量：S-M；回归风险：medium。

### QA-DAT-004

“重新检查”不重新核对已恢复的私有文件。[GitHub Issue #84](https://github.com/haohongfei2001-png/Riftlet/issues/84)；[具体位置/条件/证据/建议/验收](STORAGE_AUDIT.md)。

影响：users restoring exact missing private media while service runs；频率：recovery；工作量：S；回归风险：medium。

### QA-SET-002

切换桌面形态后，隐藏的无效参数仍阻断保存。[GitHub Issue #85](https://github.com/haohongfei2001-png/Riftlet/issues/85)；[具体位置/条件/证据/建议/验收](SETTINGS_REDESIGN.md)。

影响：users changing form with invalid draft fields；频率：conditional；工作量：S；回归风险：low-medium。

### QA-SET-003

「稍后设置」每次重启都会重新弹出引导。[GitHub Issue #86](https://github.com/haohongfei2001-png/Riftlet/issues/86)；[具体位置/条件/证据/建议/验收](SETTINGS_REDESIGN.md)。

影响：new users choosing later / local only；频率：every relaunch；工作量：S；回归风险：low。

### QA-SET-004

托盘「可见截图」接受 5–10 张，实际硬上限为 4 张。[GitHub Issue #87](https://github.com/haohongfei2001-png/Riftlet/issues/87)；[具体位置/条件/证据/建议/验收](SETTINGS_REDESIGN.md)。

影响：tray users changing visible capacity；频率：every affected change；工作量：S；回归风险：low。

### QA-SET-001

普通设置混用立即保存、布局草稿和归档草稿，公开界面承担过多工程参数。[GitHub Issue #88](https://github.com/haohongfei2001-png/Riftlet/issues/88)；[具体位置/条件/证据/建议/验收](SETTINGS_REDESIGN.md)。

影响：all settings users；频率：every settings session；工作量：M；回归风险：medium。

### QA-SET-006

更新和版本被收进「权限与帮助→关于与诊断」，日常偏好也与历史混放。[GitHub Issue #89](https://github.com/haohongfei2001-png/Riftlet/issues/89)；[具体位置/条件/证据/建议/验收](SETTINGS_REDESIGN.md)。

影响：all update/settings users；频率：periodic；工作量：S；回归风险：low。

### QA-ATT-003

正常接收后的历史和设置永久显示“待核实”。[GitHub Issue #90](https://github.com/haohongfei2001-png/Riftlet/issues/90)；[具体位置/条件/证据/建议/验收](ATTACHMENT_AUDIT.md)。

影响：all successful ordinary handoffs；频率：every handoff；工作量：S-M；回归风险：medium。

### QA-GOV-001

当前工程入口被旧阶段指令和重复权威污染。[GitHub Issue #91](https://github.com/haohongfei2001-png/Riftlet/issues/91)；[具体位置/条件/证据/建议/验收](AUDIT_REPORT.md)。

影响：all engineering tasks；频率：every agent session；工作量：S；回归风险：medium。

### QA-VIS-001

缺少当前正式界面的完整视觉与可访问性验收组。[GitHub Issue #92](https://github.com/haohongfei2001-png/Riftlet/issues/92)；[具体位置/条件/证据/建议/验收](AUDIT_REPORT.md)。

影响：all native UI users；频率：daily；工作量：M；回归风险：low-medium。

### QA-DAT-002

历史增长使启动和每次刷新承担无界工作。[GitHub Issue #93](https://github.com/haohongfei2001-png/Riftlet/issues/93)；[具体位置/条件/证据/建议/验收](STORAGE_AUDIT.md)。

影响：long-lived libraries；频率：startup / every refresh；工作量：M；回归风险：medium。

### QA-SET-008

旧设置/动效控制器仍作为产品模块和 GUI 验收的一部分，当前界面覆盖需区分。[GitHub Issue #94](https://github.com/haohongfei2001-png/Riftlet/issues/94)；[具体位置/条件/证据/建议/验收](SETTINGS_REDESIGN.md)。

影响：maintainers and release quality；频率：each change；工作量：M；回归风险：medium。

### QA-DAT-003

“归档”不回收空间，用户没有安全的本地清理入口。[GitHub Issue #95](https://github.com/haohongfei2001-png/Riftlet/issues/95)；[具体位置/条件/证据/建议/验收](STORAGE_AUDIT.md)。

影响：long-lived libraries / local privacy cleanup；频率：growing with use；工作量：M；回归风险：high。

### QA-SET-007

面向英文官网的首用/权限/设置仍全部硬编码中文。[GitHub Issue #96](https://github.com/haohongfei2001-png/Riftlet/issues/96)；[具体位置/条件/证据/建议/验收](SETTINGS_REDESIGN.md)。

影响：users coming from English website；频率：first use / daily；工作量：M；回归风险：medium。

### QA-REL-002

公开支持范围与真实安装升级兼容矩阵需要补齐。[GitHub Issue #97](https://github.com/haohongfei2001-png/Riftlet/issues/97)；[具体位置/条件/证据/建议/验收](AUDIT_REPORT.md)。

影响：macOS13 / Intel / shared-install users；频率：install / upgrade；工作量：M；回归风险：medium。

### QA-SET-005

引导称「选择截图文件夹」，但文件选择器只允许当前系统截图目录。[GitHub Issue #98](https://github.com/haohongfei2001-png/Riftlet/issues/98)；[具体位置/条件/证据/建议/验收](SETTINGS_REDESIGN.md)。

影响：first-use folder authorization；频率：first use / recovery；工作量：S；回归风险：low。

### QA-WEB-001

英文官网仍含中文图片替代文本，辅助阅读语言不一致。[GitHub Issue #99](https://github.com/haohongfei2001-png/Riftlet/issues/99)；[具体位置/条件/证据/建议/验收](AUDIT_REPORT.md)。

影响：English screen-reader users；频率：website discovery；工作量：S；回归风险：low。

## 关闭与去重

只有非作者复核对应Issue全部必要条件后关闭；文档交付、CI变绿或候选提交存在均不自动关闭。无法执行的真实验收保持OPEN并写清单格阻断。QA-GOV-001文档修正可在本审计PR合入并检查实际main后单独关闭，其余无产品修复不得随之关闭。历史Issue #6与现有候选PR保持，不借本轮清理关闭无关工作。

机器可读完整首版事实为[findings.json](findings.json)，进度为[ITERATION_STATUS.json](ITERATION_STATUS.json)，实现分包为[CODEX_HANDOFF.md](CODEX_HANDOFF.md)。若新证据否定一项，写明更正和证据，保留审计轨迹，不反复创建新ID。
