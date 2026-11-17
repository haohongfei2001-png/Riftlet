# Riftlet 1.0.4 私有发行候选

**版本 1.0.4，build 26。** 新用户从三张截图的托盘起步。通用、外观、截图、帮助共用一个设置窗口。托盘玻璃透明度与相机机身颜色可独立调整。截图仓库先按全库元数据搜索，再分页显示，翻页与切换列表／网格沿用原记录 UUID。首次引导可以延期，本地截图可独立使用。

实施基线为 main `3f8149e2313fd81bbaee5a7bbbdbb1efca2fc81b`。[规划 PR #109](https://github.com/haohongfei2001-png/Riftlet/pull/109) 五项检查通过；规划 G 为 `9f10bb1795c6296e94e071bafe4e60a9bb606954`，开发分支 `dev/1.0.4-consumer` 从其直接准入提交 `2aec10334f16dcc9b57809bd7ba956d03f1565d8` 派生。正式产品源码为 `f7407cdae28b4d63e20cf7c3972f4f131ec9e33e`，tree `0daf0a5a47f89da7d2a36597f949e7ad5f66c557`。安装包、源码审查和实测可分别追到对应回执。

## 旧用户与实际缺陷

- 保留旧配置缺字段、未知值、坏文件及现有用户的形态偏好。在独立审查中发现，一次无关的外观编辑能把未来版本保存的原值换成回退显示值。`529f805` 修复了现场状态与下一次保存两条路径。
- 用户仍可按带重音的旧文件名、图像尺寸和失败原因查找。`e9c4bdf` 修复全库搜索对这些旧行为的遗漏。独立复核在真实 SQLite fixture 上用 `resume`、`Résumé`、`1920×1080` 分别找到预期记录。
- 英文设置在切页时曾自行撑宽。`f7407cd` 修正了内容与窗口的尺寸约束。英文实际窗口四页均能维持最小 600×460pt；900pt 窗口内的正文宽 720pt。
- 原公开 1.0.3 托盘报告有一项在点击前判定相机受遮挡。首次失败原件保留；后续 1.0.3 独立档案复测未重现。1.0.4 开发包 43 项桌面测试通过，包含两次确认命中本窗口的 CGEvent 点击。回归脚本要求完整用例名、每项结果以及每张图的散列。见[原始 1.0.3 证据](evidence/native-runs.json)与[1.0.4 开发包桌面证据](evidence/tray-development-review.json)。

## 可复验范围

下列索引对应[逐项验收规范](ACCEPTANCE.md)。受控、原生 GUI、真实服务及签名安装单列。相邻格不能互相代证。

| 用例 | 已取得的证据与边界 |
|---|---|
| BASE-01、02、04 | 已核对规划祖先、公开 ZIP、稳定 feed 和独立源码。12 次隔离子进程的正常退出、SIGTERM、SIGKILL、锁恢复保留原数据。|
| SET-01–04、07–08 | 实际设置窗口检查四页、读写、现场预览、独立保存失败、重试方向、控件与历史。登录项与更新服务状态有受控覆盖；普通用户实际注册及管理员授权另计。|
| SET-05、06；COPY-03 | 普通编辑、刷新、返回／失焦以及原生控件存在相关回归。完整系统中文组字和 VoiceOver 连续操作、物理拔插多屏未验收。|
| MIG-01–06 | 普通隔离新用户首次启动实际选择托盘；缺失、未知、损坏、外部改变、旧自定义及只改一项的回归覆盖见 `RecoverablePreferencesTests`、`ApplicationInstanceOwnershipTests` 与 `RiftSettingsCenterTests`。实际旧数据升级见安装记录。|
| TRAY-01–04、07–09 | 原生变色像素对照、两行四槽与顺序、开合路径、真实窗口命中、滚轮和 Escape。开发包 18 组机身对比每组有 946–953 个像素随颜色变化，镜头、键帽与缩略图对照区未改变。|
| TRAY-05、06、10 | 有 AppKit 高对比覆盖、屏幕锚点、比例和命中测试。现场切换所有系统辅助功能组合、物理双屏热插拔、跨 Space 及两种真实硬件缩放的完整组合未验证。|
| ONB-01–06 | 普通隔离账户首次启动并拒绝桌面访问后出现恢复入口。四个普通隔离档案的红关闭、Cmd-W、Esc、“稍后”均写入延期，退出后重新打开保持选择。VZ 按键注入未能发送 Command；切换到客体 macOS 自带辅助功能键盘，独立 AppKit 窗口确认收到标准关闭快捷键，再执行同一个真实操作成功。该组证据来自开发包。真实 Chrome 服务路径见下。|
| HIST-01–05 | 200、2,000、10,000 行 SQLite fixture；分页边界、字面量与 Unicode 查询，稳定时间戳排序和 UUID，合资格归档恢复。原生仓库在含 401 条的库中跨页找回原 UUID，切列表／网格仍可预览原图与 200% 缩放，原生重启检查通过。|
| COPY-01、02 | 界面投影区分已交给 ChatGPT、输入前失败和结果待核实；写盘失败可以就地重试。受控 Chrome 与容量故障回执见下。完整外部服务异常组合未验证。|
| CORE-01、02 | **NOT_RUN / REAL_SERVICE**。隔离 Chrome 的专用新草稿连接超时，一次正式 TLS 恢复检查返回 `NSURLErrorDomain -1200`。无法稳定读取编辑器，未追加、未发送。无该包首次冷点击或三组 ≤2 秒双图证据。|
| CORE-03–08 | 126 项页面程序、61 项旧操作观察、31 组原生 headless Chrome 回归均通过。包含目标冻结、异步 input 归属、setter 至多一次、丢回执与旧 UNKNOWN 观察。测试来源为专用 fixture，不能证明服务端接收。|
| CORE-09 | 原附件适配器与 150ms 有界 pin 未变；真实服务点击耗时分位数未采集。|
| PERF-01–05 | 见下列三组实测。全程 GUI 休眠／唤醒、真实显示器切换、真实跨会话 RSS 与完整唤醒／读盘剖面仍缺独立观测；受控较长运行仅覆盖数据通路。|

## 性能、故障恢复与数据

[同一批 SQLite fixture 的 A/B 数据](evidence/history-query-20261117.json)保留了首轮对比、冷热连接条件和应用程序哈希。补回 Unicode／尺寸行为后的 10,000 行测试中，三次字面量 `%_needle` 查询耗时 8.40–16.66ms，中文子串 7.84–13.75ms，无命中的尺寸查询 18.17–24.47ms。操作系统文件缓存未强制清空。这些是查询时间，不能当作用户点击到完整窗口绘制的时间。

[收录、浏览器与两小时数据回执](evidence/native-storage-and-browser.json)记录 100 张真实编码的合成 PNG，原件和私有媒体各 1,106,442,800 字节。三次重开校验逐图身份均保留。另一次实际运行 7,200 秒，收录 420 张合成截图，独立进程重开通过。128MiB 独立磁盘的真实磁盘满回归通过，卸载前 SQLite `quick_check=ok`、外键错误 0，旧 UNKNOWN 仍在。

## 同包签名、实机窗口与安装

| 项目 | 同一候选的结果 |
|---|---|
| REL-01 包身份 | PASS。`com.riftlet.app`，最低 macOS 13.0，arm64 与 x86_64，Developer ID Team `ZB9D4T66QB`；私有 `Riftlet-1.0.4.dmg` 为 12,716,281 字节。SHA-256 `044e44dbc77831d45de2a56fad602039243147810c1fa1c1b36892ab641f8f1f`。主程序 SHA-256 `2a76ad89e9501edecec02bafef203dadadf6c6b2a36f3d055011095fad3fecb4`。|
| REL-02 签名与票据 | PASS。App `eb4a3edb-4ab2-4b37-94fa-256eff3a91cd`，DMG `090c6f04-88ff-422f-b07d-095b8d356344`，Apple 两份原始回执均 Accepted。两层票据及 Gatekeeper 均通过，只读挂载后逐文件核对，含所有嵌套 Sparkle 组件。一次 Apple 票据服务 TLS 中断后用同一提交与同一签名恢复验证。|
| 签名 App 实际界面 | PASS。中文设置 15/15、英文 15/15，各 38 个真实窗口帧，两种语言均通过同包新进程重启。仓库 8/8、20 帧；桌面形态 43/43、73 帧，两者重启通过；托盘全部 24 组图像对照通过。早期菜单超时保留，时间线显示其他窗口实际收到左键，触发了原生弹窗的正常外部点击关闭。|

[设置和首用的实际窗口、测试与原始失败记录](evidence/settings-candidate/report.json) · [历史与三形态、包身份和公证记录](evidence/signed-rc/receipt.json) · [托盘](evidence/signed-rc/tray-3.png) · [风铃](evidence/signed-rc/light-leftMiddle-windChime.png) · [微缝](evidence/signed-rc/dark-rightMiddle-microSlit.png) · [401 条记录中跨页找回原 UUID](evidence/signed-rc/history-library-cross-page-uuid.png)。全部图像来自独立生成的样本和应用自有窗口。

## 旧版本升级与准入裁决

- **REL-03、04，PASS（独立 macOS 27.2，个人 Applications）**。普通图形会话中分别打开真实 1.0.3（25）和 1.0.2（24），使用各版本自带“检查更新”、Sparkle 的安装和重新启动动作。两次均重启到上述 build 26 的同一二进制，Gatekeeper 给出 Notarized Developer ID。每次升级前后的六张表、12 个旧文件、反馈草稿和目录书签的完整对比摘要均为 `db5b24492eecb77a3bcf333b6a97aa103ce83b2346e5e93c85b5cdd0817704d2`。样本有 5 个资产、1 个 UNKNOWN、3 个 checkpoint、0 条 START。未覆盖非空 START 的实际升级和共享 Applications 中的管理员挑战。
- **直接安装，PASS（同一普通图形会话）**。实际从公证 DMG 复制、推出后启动，Gatekeeper 接受，读出的旧数据与之前一致。随后操作系统截图，收录稳定后资产从 5 增至 6，UNKNOWN 仍为 1，START 仍为 0。打开的可执行文件与签名包 SHA 相同。
- REL-05 有版本、签名与拒绝分支的发行回归；未在这次客体实际复现每一种下载中断和错签。REL-06 的 post-upgrade 真实附加仍 **NOT_RUN**。实际可执行与 Appcast 由同一既有正式公钥核验，稳定 feed 公网回读 SHA `8d08d90e7877d5701f863c66f4c7bb50eb2993076bfd1e9b3d29e81239776b1e`（1.0.2）。个人 `/Applications` 安装仍为公开 1.0.3 的原始可执行散列。
- [所有验收项目按执行方式及证据范围逐项列出](evidence/signed-rc/cases.json)。发布准入 **BLOCKED**，当前专用测试机无法通过正常 TLS 连接 ChatGPT；因此没有最终包冷点击和三组 ≤2 秒双图的真实记录。macOS 13 原生启动、完整 VoiceOver／系统中文组字、实体多屏切换仍未完整实测。Ventura 恢复介质 94 块中仅有 26 块验证通过；不能用最低部署目标或 CI 机器代替实际 Ventura 运行。
- 独立源码审查的字面报告与散列记录在本开发 PR 的直接准入提交 `engineering/mainline/source-admission.json`；五项检查以该 PR 的 **Checks** 为准。规划 PR 的绿灯单独保留。GitHub 主线的分支保护状态应从远端核对；本次没有提交至 main。关联工作 [#106](https://github.com/haohongfei2001-png/Riftlet/issues/106)、[#107](https://github.com/haohongfei2001-png/Riftlet/issues/107)、[#108](https://github.com/haohongfei2001-png/Riftlet/issues/108)、[#82](https://github.com/haohongfei2001-png/Riftlet/issues/82)、[#97](https://github.com/haohongfei2001-png/Riftlet/issues/97)。

两次应用内升级、直接安装和其后截图的原始回执散列见[隔离 Mac 升级与安装记录](evidence/signed-rc/upgrade.json)。独立查看 GUI、时间线和原文件时可使用相同散列定位私有材料。
