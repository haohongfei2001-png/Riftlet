# 真实窗口的软件鼠标路由及 CLEAR 防误选

所有本轮鼠标事件都是明确标记的 **CGEvent，physical=false**。Web 双图另为 helper AXPress，不能与这里的鼠标事件混称。没有人工鼠标、CUA 或物理设备验收 PASS。

## 前提修正，不冒充产品缺陷

最初 f641 helper 批次没有投递事件：控制窗右边界 x=1697，实际图片中心 x=1884.15，底层 probe 未覆盖，四项 NOT_RUN。修复仅让已有 helper 控制窗右对齐实际 row 屏幕并记录真实 frame；不改产品窗口排序、坐标缩放或布局。

## 修复前与修复后

| 项目 | 修复前 | 9de6a85 修复后 |
| --- | --- | --- |
| IMAGE | PASS_SOFTWARE_ROUTING，原 asset 一次选择 | PASS_SOFTWARE_ROUTING，原 asset 一次选择 |
| NUMBER | PASS_SOFTWARE_ROUTING，原 asset 一次选择 | PASS_SOFTWARE_ROUTING，原 asset 一次选择 |
| CLEAR | FAIL：row 收到 down/up，错误选择图片，底层 0 次 | **防误选 PASS**：row 收到 down/up，但 accepted/selected 均空；**透传仍 FAIL**，底层 0 次 |
| GAP | NOT_RUN：投递前 own-surface 校验失效，未发事件 | PASS_SOFTWARE_ROUTING：底层窗口 50456 实际 down/up 各 1，无图片选择 |

原始安全筛选前后记录分别在 [gui-software-before.json](gui-software-before.json) 与 [gui-software-after.json](gui-software-after.json)。包括真实 window、asset、原始事件时间、CGEvent tag、local/screen/Quartz 坐标、底层接收及焦点端点。最终 helper SHA-256 为 `e40d2aba69054ae358d111ce9899fe5aa7a49c698951a857d45335efaa87bf03`，由最终源码 `9de6a85b0161713833dc25e3b3eb1e1a2f81a558` 的 Sources 构建；未发布或安装为正式产品。

CLEAR 的 local(1.5,2) 在整块矩形 row panel 的 padding 内，坐标匹配且没有外部输入干扰。原 `mouseDown` 无命中区判断，直接进入选择。补丁只让 `imageClipFrame` 或 `numberFrame` 中的按下/释放满足选择条件，透明 padding 不进入选择 gate；按住图片后在 padding 释放也会取消。没有轮询指针、动态切换 ignoresMouseEvents、重发事件、hitTest 伪透传或窗口重构。AX 路径、生命周期和吞噬状态机未改变。

GAP 首批原查询在 uptime 467488.704 显示底层 50351，至 467489.095 变为 0，所以 guard 没有发送；不知道查询变化的外部原因，不能记为产品缩放缺陷。最终批次前提成立，实际 ClickProbe 收到事件，故仅最终批次可通过。没有根据失败结果自动重新点击；两批之间实际源码变更是 CLEAR 防误选。

## 仍然缺少的证明

- CLEAR 真正向其他应用穿透仍失败；当前矩形原生输入窗口覆盖 padding。需要独立验证更窄的原生输入区域方案，不能把本次不选择当成透传。
- 同进程 helper 文本编辑焦点端点保持，不等于任意其他应用连续焦点保持。
- 本轮记录了现有屏幕 frame/rotation/scale，但没有执行多屏迁移、Spaces 或全屏测试。
- 人工物理单击、按住补位、双击替换保护、外侧区域及实际系统截图完整链路仍 NOT_RUN。相关纯回归仅证明代码条件，不替代物理命中。

所有 helper 进程在单批结束后关闭；无 Web 输入或真实数据库访问。
