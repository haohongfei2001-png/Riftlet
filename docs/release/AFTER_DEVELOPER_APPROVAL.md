# 开发者账号获批后的发行接管清单

当前个人安装是 ARM64 的 0.3.0 (3)。截至本次准备，发布身份与公证凭据尚未配置，正式签名、公证、装订和 Gatekeeper 首启均待实测。以下步骤在独立发行工作区和干净测试 Mac 执行。已有用户的工作安装继续保留。首个可用的正式容器是 **ZIP**。

### 1. 固定候选与凭据

- 从正式 PR 和 CI 记录取得已独立审核、与拟分发内容一致的完整源码提交。对外发行时使用完成正式集成和必需检查的 main。记录提交与树、正式检查、发行工具和打包资源的版本。选择此次版本号、全局递增的构建号、显示标签和实际测试的架构。个人 0.3.0 (3)、维护 0.3.1 (4)、换签演练 0.3.2 (5) 均不作为新发行编号。
- 在发行 Mac 的钥匙串配置 **Developer ID Application** 证书及配套私钥，确认团队、证书有效期和签名身份的 40 位指纹。用 `xcrun notarytool store-credentials "$PROFILE"` 交互建立并验证钥匙串配置。只把配置名传给发行脚本，`preflight` 的证书检查在本地执行。[Apple 公证流程](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)
- 下文使用 shell 变量。将 `SOURCE`、`VERSION`、`BUILD`、`LABEL`、`TEAM`、`CERT_SHA1`、`PROFILE` 替换为上述记录，`WS` 为全新的私有绝对路径。选择用户控制的非符号链接目录，避开安装目录。命令按阶段单独执行，当前阶段失败时保留现场。

```sh
python3 -B scripts/release-tool.py preflight \
  --identity "$CERT_SHA1" --team "$TEAM" --profile "$PROFILE"
python3 -B scripts/release-tool.py build \
  --source "$SOURCE" --version "$VERSION" --build "$BUILD" --label "$LABEL" \
  --arch arm64 --workspace "$WS"
```

按实际支持范围构建。需要 universal 时在同一次 build 添加 `--arch x86_64` 并在对应架构上验证。记录 `PREPARED` manifest 的 SHA-256、由 Git 对象标识绑定的输入清单、实际 Mach-O 架构、版本与 bundle ID。保留各阶段 manifest 的独立副本和散列，下一步会更新工作区中的 manifest。

### 2. 签名、一次提交、装订、封装

```sh
python3 -B scripts/release-tool.py sign --workspace "$WS" \
  --identity "$CERT_SHA1" --team "$TEAM" --execute --allow-network
python3 -B scripts/release-tool.py notary-submit --workspace "$WS" \
  --profile "$PROFILE" --execute --allow-network
python3 -B scripts/release-tool.py notary-status --workspace "$WS" \
  --profile "$PROFILE" --execute --allow-network
```

- `SIGNED` 时核对团队、每个架构的 CDHash、secure timestamp、hardened runtime 和 Apple Events entitlement。留存签前及签后身份、提交 ZIP 的 SHA-256 和 Apple 原任务 ID。
- `In Progress` 只查询已提交的任务。如果提交回执丢失，先从同一账号的 notarytool history 和原提交证据定位原 ID，再以 `notary-status --submission-id "$ORIGINAL_ID"` 携带上面相同参数查询。终态日志的任务 ID、提交文件 SHA-256 与结果必须匹配。无法关联时保留原任务。`Invalid` 保留日志，修复后从新候选开始。
- 仅在工具记录 `NOTARIZED` 且对应 Apple 结果为 `Accepted` 后运行下一组命令。装订对象是 App。核对装订前后代码身份一致、恢复出来的 App 签名和票据均通过，再封装最终 ZIP。[Apple 的公证与票据说明](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)

```sh
python3 -B scripts/release-tool.py staple --workspace "$WS" --execute --allow-network
python3 -B scripts/release-tool.py package --workspace "$WS"
```

保存 `distribution/release-artifact.json` 中的 ZIP 文件名、大小、SHA-256、STAPLED manifest SHA-256、源码及团队。从独立可信交付记录取得 `ZIP_SHA256` 和 `MANIFEST_SHA256`。以 `ZIP` 指向待测试的实际下载并核验。

```sh
python3 -B scripts/release-tool.py verify-archive --archive "$ZIP" \
  --sha256 "$ZIP_SHA256" --manifest-sha256 "$MANIFEST_SHA256"
```

### 3. 在干净 Mac 验收实际下载

1. 从受限测试分发位置通过普通浏览器下载同一 ZIP，保留系统 quarantine，使用系统归档工具展开。在测试机用 `PAYLOAD` 指向解出的 `Riftlet-Release`，`APP="$PAYLOAD/Riftlet.app"`。核对归档散列、解出内容、团队和票据。访问凭据和带令牌的下载地址只保留在私有交付记录。

   ```sh
   python3 -B scripts/release-tool.py verify --package "$PAYLOAD" \
     --manifest-sha256 "$MANIFEST_SHA256" --team "$TEAM"
   xcrun stapler validate -v "$APP"
   syspolicy_check distribution "$APP"
   ```

   `syspolicy_check` 用于 macOS 14 及以上；在 macOS 13 使用 `spctl -a -t exec -vvv "$APP"`。另在未运行过该候选的干净快照上离线，通过 Finder 正常打开从隔离下载展开放置的 App。记录系统提示、是否能启动、版本、架构、首次向导和一张测试截图的实际收录。命令行评估和真实首启分别留证。[Apple 的干净机器测试方法](https://developer.apple.com/forums/thread/130560)

2. 在另一个隔离账户测试 **ad-hoc → 第一次 Developer ID**、**同团队 Developer ID A → B**。用合成原图与已有记录建基线，保留旧 App、完整一致的数据及书签条件。正常退出，用 `swift scripts/check-update-identity.swift --installed "$OLD_APP" --candidate "$APP"` 记录指定代码要求是否匹配。再用 `python3 -B scripts/release-tool.py update-plan --package "$PAYLOAD" --manifest-sha256 "$MANIFEST_SHA256" --team "$TEAM" --current-app "$OLD_APP"` 检查方向和架构。两条命令均不替换 App。

3. 在隔离账户同一路径仅替换 App。分别记录新进程能否直接读取受保护测试目录、原书签是否解析、首次实际收录和抵达历史的字节。若确实出现系统授权提示，分别测试拒绝、恢复，以及在「允许访问此位置…」重新选择同一截图目录后重启收录。Automation 与 Chrome JavaScript 另行记录。系统没弹窗就记录未观察；如果读取失败，不能凭相同 bundle ID、团队或书签存在推断权限连续。[身份交接细则](IDENTITY_TRANSITION.md)

4. 测损坏包被拒、更新中断和回退。保留刚产生的最新记录，只在旧 App 能读取这些数据时换回旧 App；逐项比较原图、私有媒体、日志、资产及操作、UNKNOWN、反馈和偏好。旧数据不覆盖新历史。开发者身份交接通过后，再用合法的 Chrome 接口验证两张不同截图在同一专用草稿连续附加、保留正文和附件、只在真实 START 后收起。[手动更新与回退](MANUAL_UPDATE_AND_RECOVERY.md)

### 4. DMG 与公开下载的界限

当前 `package-review` 仅制作带 `REVIEW-NOT-NOTARIZED` 标记的私有 ZIP/DMG，并只读挂载核对内容。正式 `package` 输出 ZIP。若选择 DMG 发行，需要从核验过的已签名 App 构造只读镜像，以 Developer ID Application 签名最外层 DMG；记录提交前容器散列和原任务 ID，对最外层执行公证并验证对应日志，随后装订、验证 DMG 自身。只读挂载核对内层 App 身份，记录装订后的最终镜像散列。在干净机额外执行 `spctl -a -t open -vvv --context context:primary-signature "$DMG"` 并做实际下载、挂载和正常首启。此容器路线仍待准入和实测。[Apple 容器分发说明](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution)

以下为 DMG 另行准入后的操作顺序。用已核验的正式 `Riftlet-Release` 作输入，在新目录执行；每一步成功才继续。

```sh
DMG="$WS/Riftlet-$VERSION-$BUILD.dmg"
mkdir "$WS/dmg-input"
ditto --rsrc --extattr "$PAYLOAD" "$WS/dmg-input/Riftlet-Release"
python3 -B scripts/release-tool.py verify --package "$WS/dmg-input/Riftlet-Release" \
  --manifest-sha256 "$MANIFEST_SHA256" --team "$TEAM"
hdiutil create -srcfolder "$WS/dmg-input" -fs HFS+ -format UDZO -volname Riftlet "$DMG"
codesign --sign "$CERT_SHA1" --timestamp --identifier com.riftlet.distribution "$DMG"
codesign --verify --strict "$DMG"
hdiutil verify "$DMG"
shasum -a 256 "$DMG"
```

保存签名者团队、只读挂载的内容比对结果和上面的散列。用 `xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --output-format json` 提交这一份镜像一次。用返回的原 ID 执行 `notarytool info` 和 `notarytool log`，核对 Accepted、jobId 和提交前记录的**已签名、装订前**镜像 SHA-256；回执丢失时只核对原任务。随后执行 `xcrun stapler staple "$DMG"`、`xcrun stapler validate "$DMG"`，重新记录最终 SHA-256。用 `hdiutil attach -readonly -nobrowse -noautoopen` 挂载到新建的专用挂载点，在卷内对 `Riftlet-Release` 重跑带原 manifest pin 与团队的 `verify`，核验 App 票据，正常卸载该卷，再做上文 Gatekeeper 和实际下载首启。

所有结果通过后，将真实支持的系统与架构、版本说明、网站下载元数据、隐私与反馈联系渠道交给发行负责人。只有单独获得公开发行授权，才从可信来源公布最终文件和散列、启用官网下载或联系封闭测试参与者。
