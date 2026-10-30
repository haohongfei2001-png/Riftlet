# 本地验收专用隔离构建

本文件记录构建者的交付时点。随后现场执行者已经启动、验收、重启并退出隔离 App；实际结果见 [README.md](README.md)，不能将下文“交付时未启动”理解为最终状态。

这是临时 TEST-ONLY overlay，不是生产补丁，也不是原样正式 PR #1 App。仓库生产 Sources 未修改；构建、私有源目录与待创建的数据根都在同一个全新私有测试目录。没有改 HOME、系统截图保存配置、TCC 或历史数据。

构建基线：`db10d806d026ee38ecbe568b6860c5f5555a1f63`；原生源等同 `e5d77d3c82bf2769387049e533e93073d36ee6fb`。完整临时源码、精确补丁与构建 receipt 留在私有测试目录，不提交含本机路径的补丁。

## 明确的测试差异

| 临时文件 | 差异及边界 |
|---|---|
| ApplicationMode.swift | 普通 capture 的目录/菜单使用唯一测试命名；拒绝 simulate、web-acceptance、system-screenshot-candidate 启动模式。原 `usesWebAdapter`、普通模式 UnavailableAdapter 与全部准入逻辑不改。 |
| RiftletMain.swift | 本地数据根改为私有测试目录；现成 SystemCaptureLocationProvider 的 preferencesFile 和 fallback 指向该目录内的测试 plist/源目录，CaptureSourceBinding 复用同一 provider；不能回到真实 Downloads。仅将已有 acceptance trace 输出开放到普通模式。为避免初始化抢焦点，抑制首次自动 onboarding，手动设置/首次使用窗口仍为原实现。 |
| FeedbackHost.swift | Feedback 根同样置于本次私有根；原 endpoint=nil 与 DisabledFeedbackTransport 不改。 |
| Info.plist | 独立测试 bundle ID、名称，隔离 UserDefaults 身份；保留权限说明，不申请或扩展权限。 |

内置截图仍使用原 ScreenshotEntryHost、InteractiveScreenshotController 与真实系统引擎，输出到隔离根的 captures；没有自动截图/自动点击钩子。新 bundle ID 可能没有系统捕获权限，必须准确记录拒绝，不借此改 TCC。

## 构建验证

- release 编译 **PASS**；最终增量构建 7.29 秒。CLI 工具链存在 linker search-path warnings，但无编译/链接失败。
- 完整 App 包含现有页面资源 bundle 和第三方声明；ad-hoc 签名 strict verify **PASS**，未公证、未发行。
- 已签名可执行 SHA-256：`2f7889e1dc40aaceb6d8a2dce75d7d73d538758f51368a4ee08d924360215d79`。
- 私有精确 overlay SHA-256：`342af462beef218ab22aa4b65afd420bde5df9c5e9d009d1f77237604176e33a`。
- 构建者 **没有启动 App、打开业务数据库、执行 UI、操作 Chrome 或发网络上传**；交付时数据根不存在。运行证据由唯一现场执行者单独记录。

后续将已保留的真实系统 PNG 以保留 metadata 的复制方式送入私有源目录，属于真实文件的隔离交付/监听/导入验收；不能冒称新系统快捷键的 T0 链，不能把该测试构建视为正式组合 App 的完整验收或开启上传准入的依据。
