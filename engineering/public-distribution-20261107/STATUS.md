# 官网直接分发工作记录

正式产品基线为 `05abf6c2404055b0135e77585a10a47deea33a95`。本机使用 macOS 27.0、Swift 6.4 和 Command Line Tools。正式安装仍是 `com.riftlet.app` 的 0.3.0 (3) ARM64。源码中的属性表为 0.3.1 (4)，发行工具在单独的暂存 App 内写入候选版本。仓库使用 SwiftPM 和 AppKit，更新方式为手动替换 App。

| 检查 | 现场记录 |
| --- | --- |
| 通用 Release 构建 | 已从产品基线构建隔离候选 0.3.2 (5)。Mach-O 含 arm64 和 x86_64，两片最低系统均为 13.0。本机通过 ARM64 原生和 Rosetta x86_64 的普通 build-info 检查。 |
| 签名与公证 | 环境检查发现 0 个有效代码签名身份。Apple Developer Program 会员、Team ID 及可用公证配置尚待账户所有者的真实记录。可用工具包括 codesign、notarytool、stapler、spctl 和 hdiutil。 |
| 包内代码 | 正式安装仅包含一个 Mach-O 主程序。SwiftPM adapter .bundle 仅含资源，没有独立可执行文件。发行 entitlements 仅启用 Apple Events，普通代码要求保持 bundle ID。 |
| 既有升级证据 | 前次全新 macOS 账户实测首次启动、两张合成截图收录、损坏更新拒绝与只回退 App 后的数据保留。此前 ad-hoc 身份实验观察到书签读取，但未获得首次系统“允许／拒绝”的证据。正式证书签发后仍需走两次真正的签名身份过渡。 |
| 官网与更新 | 官网由 Pages 提供，当前无正式下载包。没有 Sparkle 或 appcast，签名身份不会自行增加自动更新功能。首次上架官网另需所有者批准。 |

原始私有工件、CSR 和本机身份记录分别保存。提交源码仅包含可复验工具、测试和发行说明。本轮PR记录正式源码审查、CI和合并状态。发行者取得真正的 App 与 DMG 公证回执、Gatekeeper 结果及最终归档摘要后，才可进入官网发布审批。

本次已实际创建一份登录钥匙串支持的 RSA-2048 CSR，通过 OpenSSL 验签；同一请求重复执行没有生成第二把私钥。指定的公证配置在本机未找到。一键入口已构建并验证通用包，它停在 Developer ID 身份检查。正式证书、Team ID、公证任务 ID 与正式安装包由实际签发、提交和最终收据提供。[直接发行命令](../../docs/release/DIRECT_DOWNLOAD.md)

本轮验证使用真实 macOS 的 ditto、hdiutil、stapler、spctl 和 Security.framework。实际通用构建成功；DMG 组件在私有测试包上完成只读挂载、App 清单与拖动安装链接核对、正常卸载，并在缺少 Developer ID 时正确拒绝。已保留的负向反例还覆盖 App 装订时中断和 Apple Accepted 日志被替换。完整发行测试 114 项通过，消费者说明与源码核对 90 项通过。这些结果支持工具交付；正式 App 与 DMG 的两个 Apple Submission ID 和最终官网 SHA-256 仍取决于真实账户授权。
