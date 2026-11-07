# 官网直接分发

Riftlet 使用 SwiftPM 构建普通 App，通过 Developer ID Application 在 Mac App Store 以外分发。正式 bundle ID 是 `com.riftlet.app`。每个版本的主程序、资源、历史和截图目录使用既有产品布局。当前更新方式是从官网取得新的 DMG，退出旧版并用 Finder 替换 App。项目没有 Sparkle、appcast 或另一套更新签名密钥。

## 首次配置签名机

先运行 `security find-identity -v -p codesigning`。可直接复用已有且可用的 Developer ID Application 私钥和证书。有多个有效身份时，在发布命令中传 `--identity <40位证书指纹> --team <10位团队ID>`。身份名称和团队来自经过验证的证书。

需要申请证书时，在签名机的私有目录编译一次辅助工具，保留同一程序、目录和其中的请求状态。下例的目录由维护者选择，仅当前用户可访问。

```bash
umask 077
request_dir="$HOME/Library/Application Support/Riftlet Release/Developer-ID"
mkdir -p "$request_dir"
chmod 700 "$request_dir"
swiftc scripts/developer-id-request.swift -o "$request_dir/developer-id-request"
"$request_dir/developer-id-request" create --directory "$request_dir"
```

辅助工具在用户正常登录钥匙串生成一把不可导出的 RSA 签名私钥，导出公开的 PKCS#10 CSR 和公钥。同目录重复执行复用同一请求。用 OpenSSL 检查 CSR 后，由 Account Holder 在 Apple 开发者账户确认会员和所属团队，在 Certificates 的「＋」选择 **Developer ID Application**，按当前系统和证书要求选择 G2，上传 `Riftlet-Developer-ID-Application.certSigningRequest`，下载 Apple 签发的公开 `.cer`。[Apple 证书管理](https://developer.apple.com/account/resources/certificates/list) · [Apple 签发说明](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/) · [查找 Team ID](https://developer.apple.com/help/account/manage-your-team/locate-your-team-id/)

```bash
"$request_dir/developer-id-request" verify-certificate --directory "$request_dir" --certificate "$certificate" --team "$team"
"$request_dir/developer-id-request" install-certificate --directory "$request_dir" --certificate "$certificate" --team "$team"
security find-identity -v -p codesigning
python3 -B scripts/configure-notary-profile.py --profile Riftlet-Notary --team "$team"
```

其中 `certificate` 为下载的 DER 证书路径，`team` 为预期团队。有需要时可用 `--issuer <公开的 Apple Developer ID 中间证书.cer>` 辅助验证链。工具在安装前核对请求、公钥、证书类型、Apple 信任链、团队及有效期，并在登录钥匙串读回身份。公证配置工具先验证同名配置。仅当明确不存在该项时才调用 Apple 的交互式密码提示。用自己的本地终端输入应用专用密码。已安全配置的 App Store Connect API 凭据亦可通过现有 notarytool 配置名称复用。[Apple PKI](https://www.apple.com/certificateauthority/) · [Apple 公证说明](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow) · [生成应用专用密码](https://support.apple.com/en-us/102654)

## 每次发行

选择独立审查通过的源码提交和递增的 build number，使用一个新的私有工作区。下例使用仓库核实后的当前 main 构建 0.3.2 (5)。该版本号只有在正式产物获准发布后才用于官网。

```bash
release_sha="$(git rev-parse origin/main)"
python3 -B scripts/release-macos.py \
  --source "$release_sha" --version 0.3.2 --build 5 \
  --workspace "$HOME/Library/Application Support/Riftlet Release/0.3.2-5" \
  --profile Riftlet-Notary
```

默认同时构建 arm64 和 x86_64。命令核对实际 Mach-O slice、源提交、版本、build 和资源清单。仅进行准备时使用 `--prepare-only`。若已有准备好的工作区，以上命令会核对并复用它。同一路径不能混入另一源码、版本、架构或标签。

工具使用安全时间戳、Hardened Runtime 和已审计的 Apple Events entitlement 签名，并逐架构核验。当前 App 只有一个 Mach-O 可执行程序，SwiftPM 资源 bundle 没有独立可执行程序。若将来引入 helper、framework 或扩展，须在对应组件明确其签名顺序和必要 entitlements。签名工具会识别当前布局之外的可执行代码；严格验证使用递归检查。

App 与外层 DMG 各有一个 Apple 公证任务。App 的上传 ZIP 需要实际解包与清单核对，Accepted 后装订并验证 App。工具据此创建含 `Riftlet.app` 和 `Applications` 链接的只读 DMG，对 DMG 签名、提交、核对原任务终态日志和上传摘要，再装订 DMG。它还会核对 Finder 安装内容、实际签名、团队、App 和 DMG 票据、Gatekeeper 执行／打开结果，以及最终字节数和 SHA-256。

默认一次等待最多 30 分钟。Apple 仍在处理时，命令返回 `PENDING_NOTARIZATION` 和原任务 ID，稍后重复同一命令即可。响应丢失时，使用原始 App 或 DMG 的 Submission ID 传给 `--app-submission-id` 或 `--dmg-submission-id`。原始 ID、日志和实际上传 SHA-256 需要匹配。收到 Invalid 时，应保留工作区的 Apple 终态日志，修复实际错误后构建新候选。装订失败时保留原日志；已 Accepted 的任务通过原工作区恢复。构建或签名失败的输出可保留供诊断。

## 审核安装包与手动更新

成功后，`formal-dmg/dmg-receipt.json` 记录双层验证结果，`website-release.json` 给出实际 DMG 绝对路径、版本、源码、两个 Submission ID、证书指纹和 SHA-256。下一步是在独立 macOS 账户中用真实下载得到的隔离包测试 Finder 拖入 Applications、正常首启、按需授权和首张收录。保留原安装和完整数据备份，更新失败时只换回兼容 App。

目录读取、屏幕录制、辅助功能、Chrome 自动化及 Feedback 的钥匙串项需在新进程分别核实。内置截图按需检查屏幕录制；Chrome 前台观察仅在已有 AX 权限时读取相应焦点信息，日常附件操作沿用现有点击逻辑。首次从 ad-hoc 换为 Developer ID 及同一团队后续版本均要在独立账户比较旧代码要求、实际受保护文件读取、书签恢复、系统提示和点击后的实际行为。Feedback 验证限于独立测试项的可访问性；保留既有服务标识和用户数据。[升级与身份过渡](IDENTITY_TRANSITION.md) · [手动更新和恢复](MANUAL_UPDATE_AND_RECOVERY.md)

升级验收中，目录不可读时从「设置 → 截图 → 允许访问此位置」选择 macOS 实际截图目录并正常重启。内置截图需要录屏授权时，使用系统「隐私与安全性」中的屏幕录制设置。用户主动点击微图后，应单独验证「自动化 → Riftlet → Google Chrome」对应的实际授权、草稿附件和 START。AX 属于另一个系统授权，按需核对已有选择。反馈凭据绑定既有钥匙串服务；在隔离账户验证前一版本创建的测试项能否读回，保留真实拒绝原因和新的访问确认，避免删除旧凭据。当前实测没有覆盖真正的 Developer ID 换签，不能承诺这些系统授权自动继承。

官网发布需要对**具体**产物单独批准。审核包应包含版本说明、最终 DMG、独立来源的 SHA-256、架构和最低系统版本、下载地址及更新说明。取得批准之后再公开分发并验证真实下载。GitHub Actions 的 Native ARM64 和 Native Intel 作业会运行发行回归。常规 CI 使用隔离测试材料。本地签名流程可以直接使用钥匙串的不可导出密钥。[官网接入规范](../WEBSITE_RELEASE_INTEGRATION.md)
