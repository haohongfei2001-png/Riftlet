# 开发者账号获批后的发行接管清单

正式工具已随 [PR #49](https://github.com/haohongfei2001-png/Riftlet/pull/49) 合入 `4908dc7`，包括 SwiftPM 构建、钥匙串证书请求和双层公证的 DMG 流程。个人安装仍为 ARM64 的 0.3.0 (3)。截至本次复核，本机尚无可用 Developer ID Application 身份。以下操作在签名机和隔离测试 Mac 上执行，成功结果随包记录，官网上线另行批准。[正式发行手册](DIRECT_DOWNLOAD.md)

### 1. 用既有请求接入证书和公证

1. Account Holder 确认会员已激活并取得团队 ID。在 Apple 的 Certificates 页面选择 **Developer ID Application**，按 Apple 当期要求选择证书链，上传既有的 `Riftlet-Developer-ID-Application.certSigningRequest`，保管下载的公开 `.cer`。该公有 CSR 的自签名在本次只读核查中通过，SHA-256 为 `1cead0f0d653a4867c34d7aa1c2b88e839168cb2e0a12276c2778d578893eb8b`，与原请求记录一致。保留原签名 Mac、同一钥匙串、请求状态和原辅助程序。[Apple 证书签发说明](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/)
2. 在本地终端设置 `REQ` 为**这份原请求**的私有目录，`CER` 为下载的证书路径，`TEAM` 为预期的 10 位团队 ID。在签名机验证并安装证书。

   ```sh
   "$REQ/developer-id-request" verify-certificate --directory "$REQ" --certificate "$CER" --team "$TEAM"
   "$REQ/developer-id-request" install-certificate --directory "$REQ" --certificate "$CER" --team "$TEAM"
   security find-identity -v -p codesigning
   ```

   核对 `INSTALLED_DEVELOPER_ID_APPLICATION`、证书团队与可用身份，将对应的 40 位 SHA-1 指纹记为 `CERT_SHA1`。若报告身份未确认，保留原请求与钥匙串并定位证书链或配对问题。
3. 取配置名 `PROFILE=Riftlet-Notary`。已有配置会先验证；仅在确认缺项时，Apple 的本地交互提示才会要求账户信息和应用专用密码。已验证的 API 公证配置也可复用。凭据只在签名机配置。[Apple 公证流程](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)

   ```sh
   python3 -B scripts/configure-notary-profile.py --profile "$PROFILE" --team "$TEAM" --identity "$CERT_SHA1"
   ```

### 2. 固定输入，构建并生成正式 DMG

从获准分发的正式 main 和通过的 CI 取得完整提交 `SOURCE`。登记该提交、树、版本 `VERSION`、递增的构建号 `BUILD`、显示标签 `LABEL` 和新私有绝对路径 `WS`。0.3.2 (5) 在既有记录中用于演练，其编号本身不代表一个获准的公开版本。

```sh
python3 -B scripts/release-macos.py --prepare-only --source "$SOURCE" \
  --version "$VERSION" --build "$BUILD" --label "$LABEL" --workspace "$WS"
```

保存 `PREPARATION_VERIFIED`、此阶段 manifest 及其散列，核对源码和准备工具的输入、bundle ID、版本与实际 Mach-O 架构。默认构建 arm64 与 x86_64；若只为一种架构交付，两次运行都使用相同的 `--arch`。在同一工作区使用相同参数继续。

```sh
python3 -B scripts/release-macos.py --source "$SOURCE" \
  --version "$VERSION" --build "$BUILD" --label "$LABEL" --workspace "$WS" \
  --identity "$CERT_SHA1" --team "$TEAM" --profile "$PROFILE"
```

| 阶段 | 需要留存并核对的结果 |
| --- | --- |
| App 签名前后 | 准备 manifest、Team ID、各架构 CDHash 和证书指纹、secure timestamp、hardened runtime、实际 entitlements。 |
| App 公证 | 原提交 ZIP 的 SHA-256、App Submission ID、Apple Accepted 终态日志和对应摘要；装订后 App 票据验证与代码身份。 |
| DMG | 只读挂载确认根目录里的 `Riftlet.app` 和指向 `/Applications` 的安装链接。外层独立签名与公证，使用自己的提交 SHA-256、Submission ID 和 Accepted 日志。核对装订后的 DMG、内外签名和票据、Gatekeeper 评估、最终大小及 SHA-256。 |
| 私有交付 | 仅在工具返回 `VERIFIED_FOR_PUBLICATION_REVIEW` 后，保存 `formal-dmg/dmg-receipt.json` 与 `website-release.json`。核对路径、两个独立公证任务、团队、每架构 App 与外层 DMG 的证书指纹、最终散列以及 `published: false`。 |

默认等待最多 30 分钟。返回 `PENDING_NOTARIZATION` 时在**原工作区**重跑相同命令查询。提交回执丢失时从原账号历史和上传摘要定位原任务，在同一命令补 `--app-submission-id "$ORIGINAL_APP_ID"` 或 `--dmg-submission-id "$ORIGINAL_DMG_ID"`。Invalid 保留 Apple 日志，修复后从新候选开始；Accepted 后的装订中断从原工作区续作。[Apple 容器分发说明](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution)

`release-tool.py package` 的可选正式 ZIP 使用已经装订的 App。`package-review` 的 ZIP/DMG 带有 `REVIEW-NOT-NOTARIZED`，仅供私有评审。官网直接下载使用上表核验过的正式 DMG。

### 3. 干净测试 Mac 正常安装、授权及回退

1. 从受限分发位置，用普通浏览器下载最终 DMG。以独立交付记录的 SHA-256 验证下载，保留 quarantine。在未运行过该候选的 Mac 或干净 VM 快照上，离线挂载、用 Finder 拖到 Applications，再正常打开。记录 Gatekeeper、首次向导和首张无隐私测试截图的实际收录。命令行预检可用 `spctl -a -t open -vvv --context context:primary-signature "$DMG"`；对安装的 App，macOS 14 及以上可用 `syspolicy_check distribution "$APP"`，macOS 13 使用 `spctl -a -t exec -vvv "$APP"`。[Apple 的干净机器测试方法](https://developer.apple.com/forums/thread/130560)
2. 在隔离账户分别试 **ad-hoc → 首次 Developer ID** 和 **同团队已公证 A → B**。保留旧 App、最新的一致数据备份、测试目录书签和受保护目录中的测试图片。用 `swift scripts/check-update-identity.swift --installed "$OLD_APP" --candidate "$APP"` 记录指定代码要求。正常退出和核对所有权后只替换 App。
3. 在新进程内验证受保护目录实际读取、原书签、首张收录、Chrome 自动化与 JavaScript、可选录屏和测试反馈凭据。实际出现系统提示时观察拒绝和恢复，记录从 Riftlet 选择正确截图目录并重启后的读取。即使身份要求匹配，也要实际测权限连续性；没有弹窗就记录未观察。用合法接口在专用 Chrome 草稿验证连续两张截图、旧正文和旧附件、真实 START 与不自动发送。[换签与权限验证](IDENTITY_TRANSITION.md)
4. 演练损坏更新被拒和安装失败回退。保留含更新后新资产及操作的快照，确认旧 App 能读取当前状态后只换回 App；核对原图、私有媒体、日志、UNKNOWN、反馈、偏好、目录恢复和再次收录。兼容性未确认时保留两份 App，用向前修复保住新历史。[手动更新与回退](MANUAL_UPDATE_AND_RECOVERY.md)

若候选已写入带卷 UUID 的截图来源标识，只读取旧设备号的 App 在同一个 v3 数据库上会把已收录的原图再次放回边缘；隔离实测中原记录带有 UNKNOWN。此时保留最新的完整数据和两份 App，使用可读取新标识的修复版本。回到升级前的备份会缺少此后新增的截图和操作。

### 4. 公开发行准入

将实际支持的系统与架构、正式 DMG 的独立散列、版本说明、更新及卸载指引、可联系的支持与隐私渠道交给发行负责人。取得对**具体产物**的批准后才开放官网下载或邀请封闭测试参与者。

`riftlet.com` 直接发布公开仓库的 `main` 根目录。待审 DMG、签名工作区、受限链接、邀请名单不得放进仓库；未链接的路径和带 `noindex` 的页面也能被访问。官网草案须与原生合并分开，在确认哪些页面和入口可公开之后再推进。
