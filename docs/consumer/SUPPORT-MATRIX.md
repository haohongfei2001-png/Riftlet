# 支持范围 / Support matrix

审计基线：main `2e779f6`，2026-11-07。**实现了某条路径、受控测试通过、真实平台验收通过是三件不同的事。** 此表没有新增真实 ChatGPT 验收；当前服务复验受工具策略限制，后续正式交付应附该版本的实际结果。

| 范围 | 当前能力 | 验证边界与限制 |
| --- | --- | --- |
| macOS | 部署目标 macOS 13+ | 不是每个 macOS 版本都经过实机验收；以具体包说明为准 |
| Apple silicon | 已有个人 ARM64 安装及原生交互、数据升级证据 | 不等于陌生用户干净下载、Gatekeeper 和首次授权全部通过 |
| Intel | 有 Intel 构建及 macOS CI | 未据此声称真实 Intel 硬件验收；架构包不可互相假定 |
| Google Chrome + ChatGPT 网页 | 点击时的可编辑新聊天或已有聊天，使用当前附件入口 | 页面、账号功能、语言和聊天模式可能变化；不承诺所有模式。首次冷连接可能把原 Chrome 窗口前置 |
| 已有文件输入 / 动态附件菜单 | 代码支持直接输入及打开属于当前草稿的附件菜单 | 旧真实五张连续和冷双图证据属于其记录版本；动态菜单有受控测试，不冒充当前服务自然触发的证明 |
| 非 Chrome 浏览器、ChatGPT Mac、其他 AI 服务 | 无本轮支持承诺 | 不建议用另一个浏览器的成功推定 Chrome 路径，反之亦然 |
| 临时聊天、Projects、组织工作区、特殊编辑器 | 不仅凭 URL 判断可用；仍需当前可用草稿和附件入口 | 未逐一做本轮真实服务认证；不能承诺特殊账号或只读页面可附加 |
| 系统截图文件 | 新保存的单帧 PNG、JPEG、HEIC/HEIF、TIFF | 收录上限 128 MiB、1.6 亿像素、单边 50,000 像素；这些是本地保护上限，不是 ChatGPT 上传额度承诺 |
| 输入的图像 | PNG/JPEG 按原文件交给网页；其余支持格式通常生成等分辨率 PNG | 派生 PNG 超预算时只尝试一次原文件；网页是否接收由其格式能力决定。保留原始截图；HDR 显示效果无完整保证 |
| 仅剪贴板截图、PDF、动图、多页图像 | 不在当前文件收录范围 | 不是剪贴板管理器或任意文件上传器 |
| 内置截图 | 窗口、区域、全屏，按次选项与可选编辑 | 需要对应屏幕权限；取消不应产生新的收录记录。不能保证所有系统截图都排除 Riftlet 自身 |
| 本地历史 | 默认「当前视图」，可切换「图像网格」；同一查询、筛选、分页、选择、预览和恢复资格 | 原生界面及同包重启有独立证据；双样式不会赋予 UNKNOWN 重传资格 |
| 视觉与辅助功能 | 原生控件、浅深色、减少动态效果及提高对比度的相应实现 | 指定版本有受控/原生证据；完整物理 IME、持续 VoiceOver、多屏热拔及睡眠唤醒不能由这些结果代替 |
| 登录启动 | 系统 SMAppService 状态回读和明确用户动作 | 尚有本轮系统兼容性专项；“待批准”“未找到”均不是已验证成功 |
| 外部分发 | 当前个人包为 ad-hoc | Developer ID、公证、stapling、干净 Gatekeeper 下载链及外部首用未完成，不是公开 Beta |

页面加载、网络和 ChatGPT 自身的限额/错误仍由 ChatGPT 处理。微图收起仅说明草稿开始接收，并不消除这些限制。若结果不明，保留本地记录并检查原聊天；不要用相同图片反复试探。

**English:** The supported product target is Google Chrome with an editable ChatGPT web draft. Local format limits are not service upload limits. Safari, Edge, Firefox, ChatGPT for Mac and other services are outside the current support commitment. Apple silicon installation evidence and Intel CI are distinct. Accessibility features and controlled tests are not a full assistive-technology certification. This table is source-based and version-scoped, not a promise that every account, page variant or operating-system version works.

证据归属见[源码与文案审计](../../engineering/productization-20261107/consumer/SOURCE-AUDIT.md)；历史双样式的既有结果见[原交付记录](../../engineering/history-dual-style-20261107/README.md)。
