# Riftlet 薄界统一候选：独立验收范围与制品审查准备

审查角色：`acceptance_audit`，非原实现作者。审查日期：2026-10-29（北京时间）。本文件是本轮初始独立审查，不是未来正式合流 App 的通过证明。

## 已直接核对的来源

- 原生交接 `443d21da1a55c0061eafced823b5406879b96024`；实际 CI 源码 `00dedc7f8164643c3435e3f87aa462e28af0b1c8`。
- Native run **40742061755** / job **123005982942**。通过 GitHub API 直接读取完整 10,021 行日志及 artifact 元数据。
- 日志有 **620 个互不重复的原生测试调度记录**。详细选择的 Feedback suite 为 33 项，capture-entry suite 为 45 项；它们属于 620，不重复加总。全量并行输出不逐项报告 `XCTSkip`，因此不可仅靠调度记录宣称每项都有实际 GUI 运行。
- Release 构建、严格 ad-hoc codesign、4 个包内自检、Beta 完整包装、GUI helper 的 `--self-check` 均通过。GUI helper 输出明确为 `GUI_NOT_RUN`。
- 原生 CI artifact **12839423795**：5,004,797 bytes；SHA-256 `5a23577b54fd165786c5b649b4ad914f0599204aac6e0edbc07d5655ae101d43`。source/checkout 都为 `00dedc7`。到期 2026-11-12 02:10:38 北京时间。
- `00dedc7..443d21d` 仅改旧候选 evidence README/results，产品、测试、打包输入未改变。
- `engineering/evidence/2026-10-29-thin-edge-native/asset-manifest.json` 的 **20 个文件（15 PNG、5 MOV）**逐一检查 hash/字节全部吻合；15 PNG 的原像素宽高全部吻合。

## 旧视觉证据能证明什么

| 证据 | 实际来源 | 有效范围 | 不能据此声明 |
| --- | --- | --- | --- |
| 10 张 setup/settings/history/feedback/motion 浅深图，竖屏图 | `46a909a` | macOS 27、2x、实际 WindowServer 绘制，原图未缩放 | 最新 Feedback 或本轮合流 App 已截图 |
| queue-light16、queue-dark16-entry、extreme-hover、pager-last-page | `ad4854c` | 该源的浅深队列、入口、预览/分页 | 不同桌面背景、1x、新设置页已验收 |
| 5 段 magnet/none/reduce-motion/interrupt/missing-source | `888a4b0` | 真实 WindowServer/AppKit 动画；业务是 helper 合成状态投影 | 真实捕获来源、真实 uploadStarted、物理手感 |
| software-routing.json | `46a909a` | helper 自身窗口 CGEvent 路由、按住补位、显式 clickState=2 | 真实硬件鼠标、系统双击自动分类、跨应用焦点 |

`--visual-clean` 的不透明 floating 背板和辅助窗口升层是取证隔离措施。它防止其他应用像素进入公开证据，同时使该模式不能用来验证产品正常窗口层级或跨应用焦点。新取证必须继续明确这一边界。

## 本轮最小必要验证

1. 合流后跑新的完整 Native 与独立 Feedback workflow；保留正式 `macos-15` runner 更新。旧薄界候选没有新跑独立 Feedback workflow。
2. 全新组合来源 gate：旧三份历史 audit 在原 blob/原 SHA 执行；最新 Feedback 的正式固定来源修复也需独立纳入；新组合树只固定经非作者审查的对象，不以目录豁免接受任意源码。
3. 使用现有产品 controller 的 helper，在同一最终产品源码的 macOS CI 生成全新原像素原生图。优先采集新改动设置五区、Feedback、setup/history；补充队列/入口/极端/分页。每图记录截图方法、source/checkout、点尺寸、像素尺寸、backing scale、SHA-256。没有真实 WindowServer 输出即不得标 WindowServer PASS。
4. 对新统一 App 实包检查 source/checkout 关系、App/executable/资源/许可/launcher/README/build-info 完整性与 hash；不将旧候选包改名作为本轮交付。
5. 保存原始失败/跳过/平台限制。原生 UI 软件测试及截图不冒充人工物理验收，不重跑旧 H 上传。

## 全部用户要求的验收矩阵（初始状态）

| 项目 | 现有有效证据 | 本轮可自主推进 | 本轮真实产品验收初始状态 |
| --- | --- | --- | --- |
| 新截图入口与裂缝并存 | 原 helper 2x 深色入口队列图；源码/模型 suite | 新组合 controller 图及回归 | NOT_RUN：已登记 Mac 离线 |
| 完成后保持模式、取消后收回 | Capture/Entry 模型/控制器 suite | 新组合 Native 详细 suite | NOT_RUN：没有本轮真实截图操作 |
| 窗口/区域/全屏及实际输出文件 | CLI 参数与导入测试 | 不扩大准入的组合回归 | NOT_RUN |
| 非激活点击、透明间隙、底层焦点 | 旧 helper CGEvent；同进程焦点 | 新软件回归，明确范围 | NOT_RUN：跨应用和物理操作 |
| 物理鼠标、补位后双击 | 旧显式 clickState=2 软件证据 | 产品保护回归 | NOT_RUN：缺真人操作 |
| 1x/2x、旋转屏、多屏、显示器变化 | 旧 2x 横/旋转竖屏；几何单测 | CI实际scale图、显示变更单测 | NOT_RUN：本轮真实拓扑操作 |
| Spaces/全屏/窗口层级 | 源码与部分软件生命周期 | 检查正常层级未被fixture修改 | NOT_RUN |
| 减少动态效果 | 旧合成 native 录屏及单测 | 新合成原生投影帧 | 系统设置实时切换 NOT_RUN |
| 增加对比度、减少透明度 | 系统值读取和视觉实现 | 新AppKit自有窗口图；测试可模拟策略 | 系统设置实时切换 NOT_RUN |
| 辅助窗口/Feedback 关闭重开 | 旧软件 AppKit suite；正式可靠性修复 | 新组合完整 Feedback suite +重复close三轮 | 真人 IME/Keychain/VoiceOver NOT_RUN |
| 新截图收录/附加/吞噬/后台完成 | 历史 H/F 与受限准入；新入口来源安全拒绝 | 新组合 Native 与包内自检 | 真实端到端 NOT_RUN；不重复旧 H |
| 浅深、不同桌面视觉 | 旧浅深合成纯色背板 | 新浅深+合成复杂/亮色背景 | 真实用户桌面 NOT_RUN |
| 统一设置、首次使用、历史、Feedback | 原主设置页及其余窗口图；独立motion仍有差异 | 新统一设置修复及全页图 | 新组合图待执行 |
| 磁力/中断/吞噬/补位 | 旧5段native合成录屏/时钟 | 新组合少量native真实呈现取帧 | 真实来源与上传手感 NOT_RUN |

## 可行的新原生视觉采集方案

现有 `RiftletGUIAcceptance` 已有清晰合成隔离：临时 synthetic PNG、临时 Feedback sidecar、MemorySecrets、DisabledTransport；没有 CaptureService、浏览器或生产数据库。现有 `record()` 已 fflush，脚本可同步读取窗口创建与动画事件。

建议增加 helper-only 导出选项：仅以 `NSApp` 自有可见窗口的 WindowServer ID 捕获，不取整张用户桌面；单窗口及多窗口组成场景都记明方法。静态图用本机真实 backing pixels，不借 Retina 倍数上采样。动画只记录实际捕获时间戳，不以固定帧数声称稳定帧率。捕获不可用时报告 NOT_RUN，不偷偷改用 AppKit cacheDisplay 后继续标 WindowServer。

Apple 文档依据：Quartz Window Services 提供原生窗口图像；Apple WWDC19 的安全说明明确自有窗口可被应用记录，其他应用窗口受屏幕录制授权限制。macOS 15 对旧捕获 API 可能提示用户；故代码只选本进程窗口，且不主动请求 TCC、不调用系统权限修改。若当前 SDK/API 或 runner 拒绝，可将输出限定为独立标识的 AppKit 视图渲染，不能用于窗口合成/材质/动作验收。

参考：

- https://developer.apple.com/documentation/coregraphics/quartz-window-services
- https://developer.apple.com/videos/play/wwdc2019/701/
- https://developer.apple.com/documentation/macos-release-notes/macos-15-release-notes

后续状态：父负责人已授权本角色新增 helper-only 取证实现；产品 UI/Main/CI/Package 由负责人修改。本报告不包含尚未运行的实现结果。
