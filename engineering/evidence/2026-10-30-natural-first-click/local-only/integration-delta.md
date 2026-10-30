# 冷首击与自然时间链：正式工程的最小集成差异

2026-10-30 实时读取 GitHub PR metadata 及 `ls-remote`，二者一致：

- 正式产品 PR #1 / `codex/engineering-foundation-20261027`：**`98e66a956d55b5fac71718bc627dd89705b2a506`**，Draft、未合并。
- 统一交接 PR #15：**`623d3725d0b3096f1dc7332e6cae11f47f7002c2`**。
- 本次差异审查起点：自然专项 **`db10d806d026ee38ecbe568b6860c5f5555a1f63`**；其原生源码仍等同 `e5d77d3c82bf2769387049e533e93073d36ee6fb` / `a1df3d9242d4a38e42ccb37124d0dd98d761d5c2`。

本审查没有修改正式分支、真实浏览器、运行环境或任何业务数据库。真实 ChatGPT 首次附加为 **BLOCKED（测试资源占用）**，不作为本地工作继续的前提。

## 应取的两层变更

### 1. 已审冷首击修复：6 文件

取 `c15fd4b4a27659946ef49280131e875f4d5ab9d1` → **`c308d46c1412a56e90d665972c0bc8f6ad1511a3`** 中以下路径的差异，不整体 cherry-pick 该提交：

| 路径 | 作用 |
|---|---|
| `Sources/RiftletAdapters/Resources/chatgpt-web-20261027.js` | 仅对零操作、连续性仍可证明的已撤销空 lease 发新 target；旧 target 仍失效，有操作/UNKNOWN 的状态不回收。 |
| `Sources/RiftletApp/AutomationPermissionPublication.swift` | 将实际权限结果绑定原 epoch、前台、明确接收者，拒绝乱序结果越权发布或撤销新 ACK。 |
| `Sources/RiftletApp/RiftletMain.swift` | 接入上述权限发布；区分没有进行页面捕获与真实捕获失败，持久截图到达后提前请求预绑定。 |
| `Tests/RiftletAppTests/AutomationPermissionPublicationTests.swift` | 权限乱序、旧 grant、新 denial、接收者/前台/epoch 等反例。 |
| `Tests/RiftletAppTests/ColdClickBoundaryTests.swift` | 原事件早于 ACK、按住期间 ACK、目标更换等反例。 |
| `Tests/WebPageProgram/acceptance-program.test.cjs` | 空 lease 恢复及旧目标/已有操作/不连续业务身份拒绝。 |

可重建的最小 patch 命令（输出写入集成人自己的临时文件）：

```sh
git diff --binary c15fd4b4a27659946ef49280131e875f4d5ab9d1 c308d46c1412a56e90d665972c0bc8f6ad1511a3 -- Sources Tests/RiftletAppTests Tests/WebPageProgram
```

本次生成的 patch SHA-256：`bcaac25bdce81e962deb157c35b87bde98a82331b4db3adb52e60b2545905ab9`。以上固定范围在该固定提交间恰为表内 6 文件。

### 2. 可选、但本地验收有用的诊断：9 文件

第一层之后应用已交付的 [native-diagnostics.patch](../native-diagnostics.patch)，SHA-256：`9824759ab45028e83c87fac6e5ab7ebadcbc93784083c7fdbc7cd2fe1c6af0f6`。

源码为 Main、CaptureService、PrivateAssetImporter、ScreenshotSourceGeometry、RiftPanelController；测试为 CaptureArrivalObservationTests、CaptureSourceBindingTests、ImportFaultTests、RiftInputIslandTests。合计 5 源码 + 4 测试，Main 与第一层重叠，因此两层共 **14 个唯一路径**。

它提供原生单次完整日志写入、收录/复制/持久回调、实际输入窗口、原事件 token 与时间记录；不授予点击资格，不补写历史 ACK，不持久伪造 T0/T2。离线 `timeline.py` 及其 21 条反例可保留为专项验收工具，无需进入产品构建。

## 本次实际应用与冲突检查

在独立临时 `GIT_INDEX_FILE` 中 `read-tree` 正式 `98e66a9`，依次 `git apply --cached --3way` 两层 patch：**均成功，0 未合并条目**。只生成临时 index / Git tree 对象，未写真实工作树、正式 index 或 refs。

- 得到的候选 tree：`97344dd7c4a464cc5630ca598dcb29e64c181c2c`，**不是正式提交，也未在此树构建 App**。
- 相对正式源仅改变上述 14 路径；其余 **973 个原有 Git 对象逐一不变**。
- 正式 `FeedbackHost.swift` 保留 blob `e5490af012930da90e732d386836aeca641293d7`，真实已启用 endpoint 未被专项旧配置覆盖。
- Core、SQLite、准入、安全重试、Feedback、Package、工作流、网站与既有证据均未被这两层 patch 改动。
- 当前正式 Main 与 c15 起点相同，因此没有文本冲突；这只适用于上述正式 SHA，后续若 Pro 又修改 Main 必须重新核对，不能据此整文件覆盖。

## 不应一并引入

不整体合入专项 `.github/workflows/cold-click-reliability.yml` / `natural-first-click.yml`、来源审计脚本、架构实验、页面内点击入口或研究交接元数据。`Tests/ColdClickBrowser` 是已有离线受控 Chromium 回归，可由正式负责人按需要独立执行，不是默认安装依赖或新浏览器产品路线。

正式 fixed source gate 会涉及变更对象，须由唯一集成人在组合源码独立审查后按正式流程更新；不能拿专项 gate 替代、跳过，或将本次临时 index 检查称为 source admission。

## 验证与下一步

已审 c308 与 e5 的旧源码/测试证据保留；e5 的完整 macOS CI [40914439852](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40914439852) 已成功，**不是本次正式组合树的新 CI**。本次仅执行准确差异、干净应用与保护对象检查，不重复旧 UI/上传实验。

唯一正式负责人可取第一层修复及第二层有用诊断，保留最新 Feedback/App 接线，完成组合构建、相关页面/原生回归与非作者审查。真实首次附加待测试资源空闲后恢复；真正无点击前证明的事件仍须拒绝，不能把上述可靠性修复宣布成零 ACK 首击已解决。
