# 独立发行准备流程

下文保留早期离线发行工具的设计与当时验收结果。1.0.1 的正式发行、双层公证及应用内更新由[直接分发手册](release/DIRECT_DOWNLOAD.md)和[签名更新流程](release/IN_APP_UPDATES.md)说明。

本工作包只建立可审阅的发行工具和离线身份校验。它不批准公开发行，不承认任何新 source gate，不改变 mainline admission，不安装或覆盖现有 App，也不连接 Sparkle。当前签名、公证、装订和真实下载首启仍是 **BLOCKED_CREDENTIALS / NOT_RUN**；本机测试与合成签名回执不能替代 Developer ID 或 Gatekeeper 验收。

工具：[`scripts/release-tool.py`](../scripts/release-tool.py)。权限文件：[`packaging/release/Entitlements.plist`](../packaging/release/Entitlements.plist)。离线回归：[`Tests/ReleaseReadiness/test_release_tool.py`](../Tests/ReleaseReadiness/test_release_tool.py)。源审查与合并仍遵循 [`MAINLINE_GOVERNANCE.md`](MAINLINE_GOVERNANCE.md)，发行准备不改写原始工程证据。

个人 ad-hoc 安装首次更换签名，以及同一 Developer ID 后续版本的升级，使用[身份过渡与授权验证流程](release/IDENTITY_TRANSITION.md)。

官网正式 DMG、钥匙串 CSR、公证及断点恢复使用[直接分发手册](release/DIRECT_DOWNLOAD.md)。

## 现有能力与缺口

| 项目 | 现有实现 | 本工作包 / 仍需条件 |
| --- | --- | --- |
| App 构建 | `build-macos.sh` 可构建正式普通入口；旧 `verify-app-bundle.py` 核对资源、用途说明、第三方声明、普通 build-info | 保持旧脚本原样。新增独立 staging 构建；先调用旧 verifier 核对开发包，再修改 staging 的发行元数据 |
| 签名 | 旧脚本使用 ad-hoc；Info.plist 为 development、签名/公证 false | Developer ID Application、hardened runtime、secure timestamp、严格团队与逐架构验证流程已实现；真实身份尚未提供 |
| 打包身份 | internal-beta 清单面向历史显式 candidate，架构取自打包机器，只覆盖部分文件 | 新清单记录实际 Mach-O 架构、完整文件/模式/扩展属性清单、源对象及准备工具哈希；最终 ZIP 另有 SHA-256 |
| 公证 | 现有构建无 submit / 查询 / staple | 显式独立命令，记录原提交 ID 与上传 ZIP 哈希。失回执保留 UNKNOWN，只查询原任务；本轮无上传 |
| 首次使用 | 源已含 Apple Events 等用途说明、设置/权限入口 | Developer ID 版本的 TCC 身份延续、实际权限路径、带 quarantine 的干净 Mac 首启仍需真实包验收；不以说明文本代替运行证据 |
| 更新 | 没有自动升级框架 | 仅手动更新身份核验与计划。数据兼容审查独立于包身份；不提供自动替换/回滚脚本 |
| 自动更新 | 未集成 Sparkle | 下文限定未来接口、密钥与发布顺序；本轮无框架、feed、网络任务、生产私钥 |

Apple 要求发行前使用 Developer ID、启用 hardened runtime、使用 secure timestamp，并避免调试 entitlement；公证只是分发链的一环，仍需真实 Gatekeeper 测试。[Apple 公证说明](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)、[Xcode 外部分发说明](https://help.apple.com/xcode/mac/current/en.lproj/dev033e997ca.html)。

## 输出与身份契约

每次从一个**明确完整的 40 位 commit**导出 `Package.swift`、`Sources`、`Tests`、`Resources`、`ThirdPartyNotices`，写入一个此前不存在的 workspace。不会从工作树未提交修改组装候选，不接受 `HEAD`、缩写 SHA 或源准入自动 pin。`Tests` 导出仅为保留 SwiftPM 目标目录；`build` 只构建产品，不运行 XCTest。

```text
<new-workspace>/
  source/                          指定 commit 的导出，不修改原仓库
  swift-build/                     单独构建输出
  package-inspection.log
  build.log                       失败/超时也保留
  Riftlet-Release/
    Riftlet.app/
      Contents/Resources/release-build.json
    INSTALL-zh-CN.txt
    release-manifest.json
  notary-upload.zip               首次提交的固定文件，禁止覆盖后重传
  notary-submit.log / .json
  notary-query-<unique>/            每次查询独立留存，不覆盖此前失败证据
    info.json / info-command.log
    <submission-id>.notary-log.json / log-command.log
  staple.log / staple-validate.log
  distribution/
    Riftlet-<version>-<build>-<arch>.zip
    release-artifact.json
```

`release-build.json` 在签名前放入 App，随后被代码签名封装。它记录：

- `source.commit`、完整 `source.tree`、五个输入路径的 Git 对象 ID；这是代码来源，不是独立审查结论。
- 明确 `version`（三段数值）、正整数 `build`（更新时须全局递增）、固定 bundle ID `com.riftlet.app`。
- 从可执行文件 header 和每个 fat slice 解析的 `architectures`，不能用打包主机的 CPU 冒充 universal。架构只允许 arm64/x86_64；`minimumMacOS=13.0` 是 Package/Info 声明，不等于在 macOS 13 上实测。
- `ordinaryBuildInfo`、执行该无 UI 早退探针的主机架构、Swift 版本。该探针不会进入截图收录/上传运行模式。
- staging `Info.plist` 哈希，以及 release 工具、沿用的旧 verifier、entitlements、随包安装说明四个 `preparationInputs` 哈希。源码 commit 与本次准备工具来源分开记录，不声称可重现二进制。
- `dataCompatibility=NOT_ASSERTED`。任何 schema 版本号或构建成功都不能把该字段改成数据回退承诺。

staging Info.plist 仍保留原 bundle ID、用途说明、LSUIElement、最低系统等。仅写入明确 version/build 和 `release-candidate` channel，并移除旧 `RiftletDeveloperIDSigned` / `RiftletNotarized` 自声明键；签后不再改 Info。实际签名、公证与装订结果归外部 manifest，不能用 boolean 代替验证。

外部 manifest 包含以上签名内 receipt、阶段、每个实际架构的 CDHash/时间戳、团队、entitlements、公证原 ID/上传哈希/终态日志哈希，以及除 manifest 自己之外的**整个 payload**清单。文件记录大小、SHA-256、mode；目录和所有文件记录扩展属性哈希。符号链接、硬链接、特殊文件和大小写冲突一律拒绝。下载引入的 quarantine / provenance / where-from / last-used / macl 不作为稳定包身份，不会删除这些属性。其他属性（含需要保留的签名/票据载体）在清单内。

最终 `release-artifact.json` 记录 ZIP 哈希/大小、manifest 哈希、version/build/source/arch/team；它明确保留 `gatekeeper=NOT_RUN`、`publicReleaseApproval=NOT_GRANTED_BY_TOOL`。从同一个未知 ZIP 内取到的哈希不能证明可信；接收者必须从独立、可信的发布记录取得 ZIP / manifest pin 和团队 ID。

## 维护者命令

以下仅为维护手册；签名、联网公证与发行仍须当前轮次的明确授权和真实凭据。本次工程执行不运行这些命令。不要把证书密码、Apple ID 密码、API 私钥或 EdDSA 私钥作为参数、源码、CI artifact 或诊断记录。

### 本地准备（不签名、不上传）

```sh
python3 -B scripts/release-tool.py preflight
# 未配置证书指纹、团队、已有 notary Keychain profile 时：BLOCKED_CREDENTIALS，exit 3。

python3 -B scripts/release-tool.py build \
  --source '<reviewed-full-40-character-commit>' \
  --version '0.1.0' --build '1' --label 'Release rehearsal' --arch arm64 --arch x86_64 \
  --workspace '/absolute/new/release-workspace'
```

`build` 在 macOS 上执行已审阅源的 SwiftPM manifest 与编译，只接受当前无外部 package dependencies 的结构；未来新增依赖必须另行确定离线供应策略。工具使用独立 scratch、禁用自动 resolution/update；不会调用 Developer ID codesign。编译器/链接器自带的 ad-hoc 签名不代表 Developer ID。新目录失败后保留现场，重新准备使用新路径，不强行覆盖。

可只构建一个架构，必须据实分发对应架构包。universal 构建必须输出两个实际 slice；某一架构能编译/能运行早退探针，不等于另一架构或最低 macOS 已实测。发布的版本/build 由正式发行记录分配；示例的 `0.1.0/1` 不是新版本授权。

### 需要凭据与网络的独立阶段

```sh
python3 -B scripts/release-tool.py preflight \
  --identity '<40-hex-Developer-ID-Application-certificate-fingerprint>' \
  --team '<10-character-team-id>' --profile '<existing-notary-keychain-profile>'

python3 -B scripts/release-tool.py sign --workspace '<workspace>' \
  --identity '<fingerprint>' --team '<team-id>' --execute --allow-network

python3 -B scripts/release-tool.py notary-submit --workspace '<workspace>' \
  --profile '<existing-profile>' --execute --allow-network

python3 -B scripts/release-tool.py notary-status --workspace '<workspace>' \
  --profile '<existing-profile>' --execute --allow-network

python3 -B scripts/release-tool.py staple --workspace '<workspace>' --execute --allow-network
python3 -B scripts/release-tool.py package --workspace '<workspace>'
```

`preflight` 只检查本地工具和指定的有效 Developer ID 身份；不打印全部证书列表，不导出 key，不联网确认 notary profile。存在 profile 名称不证明 Apple 端凭据有效。没有提供或本机找不到指定签名身份，停在 `BLOCKED_CREDENTIALS`，不生成“已签名”候选。

签名命令使用 `--options runtime --timestamp`，只使用最小 `com.apple.security.automation.apple-events=true`。这是现有 Chrome Apple Events 能力所需 hardened runtime entitlement；保留正常 TCC 授权，不增加 sandbox、`get-task-allow`、JIT、unsigned executable memory 或禁用 library validation。未使用 `--deep` 隐式递归签名；未来增加嵌套代码时必须显式扩展审核与签名顺序。[Apple entitlement 目录](https://developer.apple.com/documentation/bundleresources/security-entitlements)、[Hardened runtime 配置](https://help.apple.com/xcode/mac/current/en.lproj/devf87a2ac8f.html)。

签后先 `codesign --verify --strict --all-architectures` 验证 Apple 链、固定 bundle ID 与指定团队，再逐 slice 检查 Developer ID Application、runtime、时间戳、CDHash 和准确 entitlement 集合。签名或验证失败落 `SIGN_FAILED`；不自动换身份重签。网络标志是命令的执行开关，不能替代源审查或发行授权。

公证状态严格区分：

| 状态 | 允许的后续动作 |
| --- | --- |
| `PREPARED` | 一次显式签名；无公证/安装资格 |
| `SIGNED` | 一次显式提交；先核对本地签名与 manifest |
| `NOTARY_SUBMITTING` / `NOTARY_SUBMISSION_UNKNOWN` | 保留原 ZIP 与 hash；只查询原任务，不自动 resubmit |
| `NOTARY_IN_PROGRESS` | 查询已绑定的相同 ID |
| `NOTARY_REJECTED` | 保留 Apple 原日志；修复后以新 workspace 准备新候选 |
| `NOTARIZED` | 仅当 info 与原 ID、终态 log 的 jobId / archive sha256 / status 全部一致才进入；尚未装订 |
| `STAPLE_FAILED` | 保留可能已经变化的 App 与日志，人工核对；无自动重签/重提交/发行 |
| `STAPLED` | 票据装订和 validate 成功且 CDHash 未变；可产生本地 ZIP，仍未公开发布或完成 Gatekeeper 验收 |

提交超时、非 JSON 回执或进程中断都不能解释为“未提交”。工具不会轮询、循环重试或自动下载其他任务。若原回执丢失，可由维护者通过正常 Apple 记录找回 ID，再用 `notary-status --submission-id '<original-id>'` 查询；终态必须用原上传 ZIP 哈希绑定。只有 In Progress 时不会把一个新猜测 ID 固化为本包身份。工具不列出账号全部历史。

Apple 不支持直接 staple ZIP；流程对 App 装订后再重新生成最终 ZIP。最终 ZIP 与首次 notary ZIP 是不同工件，二者分别记录哈希。[Apple 自定义公证流程](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)。

## 离线接收、手动更新与回退

先在独立新目录保存 ZIP，使用来自可信发布记录的 SHA-256：

```sh
python3 -B scripts/release-tool.py verify-archive \
  --archive '/path/to/new/candidate.zip' --sha256 '<trusted-zip-sha256>'
```

此命令只读取，不解压、不执行、不写文件。它检查完整 ZIP pin、规范路径、重复/大小写冲突、文件类型、大小上限，以及 manifest 与每个普通文件的 mode/hash、版本、源、架构一致性。AppleDouble 元数据由整个 ZIP pin 绑定，不在校验时应用。`OFFLINE_ARCHIVE_IDENTITY_MATCH` 明确不表示原生签名、票据或 Gatekeeper 检查已经运行。

在一个新的接收目录使用系统 Archive Utility 或 `ditto -x -k` 解压后，再核对 manifest 与原生签名；不要先覆盖 `/Applications/Riftlet.app`：

```sh
python3 -B scripts/release-tool.py verify \
  --package '/new/extracted/Riftlet-Release' \
  --manifest-sha256 '<trusted-manifest-sha256>' --team '<trusted-team-id>'

python3 -B scripts/release-tool.py update-plan \
  --package '/new/extracted/Riftlet-Release' \
  --manifest-sha256 '<trusted-manifest-sha256>' --team '<trusted-team-id>' \
  --current-app '/Applications/Riftlet.app'
```

不带 pin 的 `verify` 只适用于维护者发现内容损坏，会输出 `NOT_PROVIDED_NOT_AUTHENTICATED`，不能用于信任未知下载。`--team` 才做 macOS 原生签名核对；本地静态代码检查不是最新撤销状态、首次运行或 Gatekeeper 验收。工具不会运行 `spctl`、启动 App、清除 quarantine、重置 TCC 或修改系统设置。

`update-plan` 要求可信 manifest pin、指定团队、完整签名校验、`STAPLED`、相同 bundle ID，以及候选包含当前主机原生架构。当前 App 只读其版本/架构，明确不因其 plist 就宣称它可信。候选数字 build 必须大于当前 build 才标为 upgrade；相同或更低版本返回受阻回退计划。任何方向都保留 `dataCompatibility=REVIEW_REQUIRED`，`actionsPerformed=[]`。

手动更新的最小顺序是：

1. 完成独立 source/release 审查和目标系统验收。在退出 Riftlet、确认所有数据库写入者停止后，保留当前 App，以及一致的完整应用数据副本。备份须包含 DB 与仍存在的 WAL/SHM、媒体、Feedback outbox 与必要 sidecar；不能只复制一个正在运行的 SQLite 主文件。不要导出 Keychain secret。
2. 对新目录包完成上述身份检查；保留旧 App 的确切版本与哈希。只在明确批准后由用户用 Finder 替换 App。本工具没有复制到 Applications、覆盖 App、启动应用、launchd 或管理员提权能力。
3. 使用当前数据启动新版本，确认迁移和待处理状态未丢失。不能让新旧两个 App 同时使用同一数据目录。升级不删除系统原截图、旧 UNKNOWN、目标锁、历史、反馈草稿或待投递项，也不重新执行上传。
4. 回退需要证明旧版本可以读取**升级后当前数据**，包括 Core/Feedback schema 和状态语义、媒体引用与 Keychain 身份。仅有“旧 App 还在”或 schema 数字相同不够。验证应针对脱敏/隔离副本，不在生产数据上试错。
5. 无法证明向后兼容时保留当前 App/数据/旧包，采用后续修复版本。不能把旧备份覆盖当前数据、降级数据库、清空 UNKNOWN 或重放外部动作来伪造成功回退。完整灾难恢复是另一个有明确数据范围的操作，不由更新工具自动完成。

## 真正外部分发之前的剩余项

按先后顺序处理，当前无一项可由离线合成测试冒充完成：

1. **凭据**：Apple Developer Program 权限、Developer ID Application 证书与匹配私钥、团队 ID、可用 notary 身份/受限 Keychain profile。账号/证书获取与付费均不在本工作包授权内。[Apple Developer ID](https://developer.apple.com/developer-id/)。
2. **具体候选**：明确已独立审查/准入的 commit、版本/build 分配、架构范围；在相同工件上顺序签名、提交、接收 Accepted、staple、生成最终 ZIP 与独立可信发布身份记录。不是给旧 ad-hoc ZIP 改名。
3. **真实下载与首次使用**：在有 Gatekeeper/quarantine 的干净受支持 Mac 上，从最终 ZIP 测试首次启动、签名身份下的 Apple Events 与文件来源授权、TCC 拒绝/撤销后恢复、App 重启与普通截图入口；同时保留数据。最低 macOS、Apple Silicon 与 Intel 未实测的格子明确标 NOT_RUN，按真实支持范围发布。
4. **更新/恢复**：真实签名旧包→新包、权限与本机数据保持、明确升级错误恢复；能证明数据兼容才允许旧包回退。不把成功文件 copy 当作更新成功。
5. **最终发布授权与交付**：审阅安装说明、支持边界、第三方声明、已知限制和精确工件 identity 后，另行执行获准的发布动作。本工具不上传 artifact、不创建 Release、不修改付费方案。

## Sparkle 的接口边界（本轮不集成）

未来若批准自动更新，只新增一个与截图/上传状态隔离的更新协调器：查询可用版本、显示 release notes、下载并验证具体包、在用户允许并安全退出后交给系统替换。更新器不能操作媒体/队列、清空 UNKNOWN、选择 ChatGPT 目标、发送内容或偷偷恢复历史动作；下载失败继续使用现有 App。

最小发布契约为 HTTPS appcast/feed + HTTPS 下载地址、单调递增 `CFBundleVersion`、与正式包一致的 version/build/架构/最低系统、包大小、EdDSA 签名与独立 Developer ID 公证链。客户端仅嵌入验证公钥（`SUPublicEDKey`）和 HTTPS feed 地址；EdDSA 私钥归受控离线/发行签名环境，**本轮不生成、不导出、不接入生产或通用 CI**。不能把同源下载的未验证哈希当作 EdDSA 签名。

将来实现时应选择当时受支持版本，按官方当前要求启用包签名验证并在解压前验证，测试伪造 feed、包篡改、错误公钥、错误架构、旧版本、证书/公钥轮换及失败后原 App 可用。EdDSA 与 Developer ID 是不同验证层；轮换不能随意同时失去旧客户端的两个信任锚。Updater/framework/XPC helper 的嵌套签名、资源 layout、sandbox/entitlement、数据迁移、退出时机和错误状态均须届时独立审查，不能直接复用当前“单一主可执行”假设。[Sparkle 官方起步文档](https://sparkle-project.github.io/documentation/)、[发布流程](https://sparkle-project.org/documentation/publishing/)、[升级与版本规则](https://sparkle-project.org/documentation/upgrading/)、[安全配置](https://sparkle-project.org/documentation/customization/)。

## 当前验证范围

`python3 -B -m unittest discover -s Tests/ReleaseReadiness -v` 覆盖离线真实文件/ZIP 与临时 Git 导出；所有 Developer ID / notary / staple 调用使用模拟回执，断言参数、失败状态、单次提交和固定 artifact 绑定。它不访问真实证书私钥、不联网、不安装，也不宣称模拟回执等于真实 Apple Accepted。

正式运行结果、构建输入 pin 与新准备脚本自身 hash 应记在本轮工程交付中。独立 PREPARED 冒烟仅验证 builder 和包身份；不得替代当前源的全部回归、正式 source gate、Developer ID runtime、真实数据更新和外部发行验收。

2026-11-06 本工作包实际记录：

| 检查 | 结果与范围 |
| --- | --- |
| 新 `ReleaseReadiness` | 41/41，通过；含本机真实 `ditto` ZIP、实际扩展属性篡改/保留 quarantine，签名/公证调用均模拟，无跳过项 |
| 原 `Tests/Packaging` | 17/17，通过；原 verifier / build 脚本未改 |
| 原 `Tests/InternalBetaPackaging` | 17/17，通过；不代表历史 candidate 重新真实上传或成为发行包 |
| 缺凭据真实 CLI | `preflight` → `BLOCKED_CREDENTIALS` / exit 3；未提供身份，未检索私钥或联系 Apple，不据此断言机器上绝对没有证书 |
| 一次真实 PREPARED 冒烟 | 源 `b61fc46cf931bdbd14deec1b47d077e92db61e16`、version `0.1.0` / build `1`、实际 `arm64`；编译、旧 bundle 检查、普通早退探针与新 receipt 成功；没有 Developer ID 签名或安装 |
| 冒烟身份 | manifest SHA-256 `0d72e42846806fdc7f47062f7e43f1bcdb0ebf1d0bffb5b61813d1444eee9e62`；当时工具 SHA-256 `5f2b961be05e9d84396ab5e3f473eeaefe3f22647955fa63773efefeb2248d0f`。后续只读验证覆盖完整 22 项文件/目录清单；该包仍保留原 receipt，不伪装成后续工具字节构建 |
| 最终工具回归 pin | `release-tool.py` SHA-256 `3e4a1d50a8fb3b14c7200c1b93f29ba9f099cede4da8d71b2f114c4d81da612a`；回归脚本 SHA-256 `c6d88f4416a38afac2498475b9faecc51f339a82e482fb3993f06ba2b1802e8b`。比冒烟工具多了失败日志保留、ZIP 完整校验和 macOS xattr 兼容，未重标原构建 |
| 尚未验证 | universal/Intel 真正构建与运行、最低 macOS、真实 Developer ID/hardened runtime、Apple Accepted/staple、真实下载 Gatekeeper/TCC、生产数据升级或回退、Sparkle；一律不据本表宣称通过 |

原生 xattr 回归暴露了本机 CPython 不提供 `os.listxattr/getxattr` 的差异。最终工具使用系统 `xattr` 的只读列表/十六进制读取接口作为 macOS 回退，参数以 `--` 隔离；无可用属性读取能力时明确阻断，不静默忽略签名/票据相关元数据。
