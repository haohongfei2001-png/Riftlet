# Riftlet

macOS 正常截图，图片停在桌面边缘；点一下微图，附加到当前 Chrome 的 ChatGPT 聊天。聊天开始接收图片时微图收起，可以继续附加下一张。Riftlet 不发送聊天消息。

当前为个人 Beta，尚未公开发行。正式基线 `b61fc46cf931bdbd14deec1b47d077e92db61e16`，已验证安装身份 `personal-beta.1+004741f`。后续开发分支、设计候选或 CI 产物不自动成为已验证安装版。

## 使用与支持

- [使用、安装及权限](docs/USER_GUIDE.md)
- [隐私、截图历史及卸载](docs/PRIVACY_AND_DATA.md)
- [问题排查与兼容范围](docs/SUPPORT.md)
- [备份与恢复](docs/STORAGE_RECOVERY.md)
- [发行构建、版本与手动更新](docs/RELEASE_ENGINEERING.md)

收录单帧 PNG、JPEG、HEIC/HEIF、TIFF。原系统截图保留；PNG/JPEG 原样附加，其他支持格式通常生成等分辨率 PNG；派生 PNG 超出预算时会单次尝试原文件，接收仍取决于页面兼容性。空队列不显示裂缝。暂停收录、隐藏微图和关闭内置截图各自独立。清空可见队列不删除截图文件、历史或聊天附件。

个人 Beta 已取得真实 ChatGPT 五张连续附加及最终版冷启动两张成功证据。动态菜单备用分支有受控浏览器验证，尚无当前个人 Beta 的真实页面触发证据。冷启动 MAIN 交接可能将 Chrome 窗口前置。具体范围及外部验收缺口见 [支持说明](docs/SUPPORT.md)。

## 开发

正式产品源码只来自 main。构建要求 macOS 13+；完整 XCTest 需要含 XCTest 的 Xcode 开发环境。开发构建使用 ad-hoc 签名，不能作为已公证公开安装包。

```sh
swift test --parallel
bash scripts/build-macos.sh
build/Riftlet.app/Contents/MacOS/Riftlet --self-check
```

[自动工程推进索引](engineering/autonomous-readiness-20261106/ROADMAP.md)记录当前专项状态、证据和接管入口；[mainline 治理](docs/MAINLINE_GOVERNANCE.md)规定独立源码审查及准入。设置与控制中心修正版在独立设计分支，尚未接入当前安装 App。

[保留的早期 README](docs/history/README-20261028.md)及 `docs/`、`engineering/evidence/` 中带日期的工程记录描述当时事实；其中旧候选、上传关闭和 8 MiB 限制不能用于说明当前普通入口。

官网目录是独立受审视觉成果，本轮只准备发行接入规范，不发布下载。请勿向公开仓库提交真实截图、私人聊天、诊断原始数据、凭据或浏览器 profile。
