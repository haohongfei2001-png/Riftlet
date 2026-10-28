# 第八、九轮与真实系统截图候选正式合流

2026-10-28。已审、已测源码：`e39c30046d2451cee204a5bc2f8fc22f2251da26`；tree `e1d5eec20a267efa9f9dab1ac8dc31c312dd5d95`。最终正式文档检查点及其自动 CI 见 PR #1 最新交接评论，本目录不提前声称后续运行成功。

## 历史与实际实现

合流双亲为正式 `d6a083dec660990bd65124e7acd78f2d900b5013` 与第九轮 `b30bb80d5af5cc12b0640c3609f70292709738a1`，共祖 b839230。第八轮 8914c702 已在第九轮祖先链，无重复 cherry-pick、squash 或改写原分支。32份第八、九轮原证据的字节和 Git blob 保持一致。

- 第八轮 CLEAR：视觉窗口忽略鼠标，图片/编号使用独立非激活输入窗口；外部透明 padding 由 WindowServer 正常路由，而非合成转发。保留原事件/asset、按住延迟吞噬、隐藏、三窗口关闭与补位。
- AX 提示绑定延后到当前捕获尝试之后，不生成 ACK；权限恢复和原点击冻结身份继续有效。
- v13 兼容完整原 v10/v12 同 root 监视器，不停止/替换原 accessor，不重建旧证明；v6–v12 旧操作只读。恶意 MAIN-world registry/真实闭包移植仍为已声明未支持边界，不以源码相等伪称认证。
- 第九轮 helper 等到实际窗口几何及路由后，在原系统双击期限内投递第二对软件事件。它不是物理鼠标双击分类验收。

## 两项必要的组合修正

1. 系统截图候选原来精确固定 v12，直接合入 v13 将拒绝所有候选页面调用。现精确固定已审 v13，并在现有测试中加入旧 sourceID 拒绝；origin/profile/journal、大小、完整目标及三份空准入表不变。
2. 新增的 v12 DOM fixture 的 settle 函数错误读取 v11 registry，造成异步 hash 未完成即断言 attached。最初组合本地回归有两项失败；改为读取 fixture 自身 version，随后三次完整144项回归通过。冻结 v12.js、原成功判据及所有旧操作语义未改。

详细 CI 增加既有 input-island/deferred-binding suites 的零跳过报告，没有为凑数量新增模块。Core、Capture、SQLite v3、preflight、accepted+30期限、真实候选数据根、首观察审计、权限恢复、历史、资源和许可保护按对象核对保留。

## 实际组合 CI

[run 40628705359](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40628705359)，job122619751123，17步骤 completed/success。实际 checkout `e2f4f0cd94a8dfb29bc5462a7d080b7304747098` 的完整 tree 与上述已审 tree 完全相等。这是 PR #5 对正式工程分支的隔离组合，不是 main 合并。

macOS14.8.9(23J631)/arm64/Swift5.10：440唯一原生（Core135/Adapters137/Capture65/UI56/App47）；16组详细106项passed/0skip，已包含440；当前页面83/legacy61；包装12；历史55文件/19用例/89前缀回放及明确模拟边界；fault8/probe12/helper9+4+2；SQLite迁移/回滚/未来版本拒绝、UNKNOWN/重启/迟到补偿/原操作及跨profile锁、原点击/FIFO/权限取消回归；Release/bundle/ad-hoc及五项自检全部通过。

[下载组合开发App/helper/日志](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40628705359/artifacts/12790392670)：1,923,804 bytes，已实际下载并重算SHA256 `39da5e37721f2593f070c4d8070aa1c2991805d54f7522cf101a18784614b451`。保存至2026-11-11T03:50:06Z；ARM64/ad-hoc，未公证。自检仍明确 CHROME_NOT_RUN/SYSTEM_SCREENSHOT_NOT_RUN/GUI_NOT_RUN。

来源CI40555899978已核对success，但不替代上述组合。辅助准备run40628422942通过源树与144VM后，被CI令牌的workflow写权限拒绝推送；正式/main未变。使用现有已授权GitHub连接器创建已上传的隔离commit分支，不提升令牌权限；工作台脚本未进入产品。

## 非作者审查

负责人独立审查传入实现并完成组合修复；本会话没有可用三执行者并发，不冒称平行子代理。另在针对工程分支的临时Draft PR #5请求独立GitHub Codex审查。

[审查回执](https://github.com/haohongfei2001-png/Riftlet/pull/5#issuecomment-6460216499)明确绑定 e39c30046d；[机器状态](https://github.com/haohongfei2001-png/Riftlet/pull/5#issuecomment-6460162971)于2026-10-28T03:52:37.385039Z为completed、has_any_findings=false、has_unresolved_findings=false。结论限于未发现重大代码问题，不等于人类批准或真实GUI通过。日志/下载制品由负责人核对，不宣称审查机器人独立下载校验。

## 下一实际动作：真实系统截图首验

见 [当前交接](../../../docs/INTEGRATION_HANDOFF.md) 和 [候选契约](../../../docs/SYSTEM_SCREENSHOT_WEB_CANDIDATE.md)。本地Codex直接从最终正式SHA新建worktree，用新的系统PNG完成 SC-INPUT、SC-START、SC-COMPLETE。无需先实现失败安全重试。

必须分别记录：(1)真实页面是否唯一输入/正确附加；(2)完整原身份的候选观察；(3)本地UNKNOWN/可见状态。start/complete未准入时“不吞噬”是预期，不是输入失败，不因此第二次上传。

普通生产、真实候选start/complete/safe-failure三表仍关闭。无原事件前完整ACK继续安全拒绝，不能晚到补签；未知只读恢复。物理GUI、业务ABA、MID、安全终止、自包含和完整延迟仍开放。没有新系统截图或浏览器验收；未访问真实Mac/私有数据库/媒体，也未清库、重传、自动Send、合main、发布或安装扩展。
