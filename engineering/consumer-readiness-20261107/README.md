# 消费者体验与发行准备 · 2026-11-07

此次工作的正式起点为 `05abf6c2404055b0135e77585a10a47deea33a95`。本机只读核对正在使用的 Personal Beta 3，版本为 0.3.0 (3)、ARM64，可执行文件 SHA-256 为 `fe5b09c4146a363e45685f8441d081fbd62a3238ed83b115287882b9158e29f3`。本次候选仅用于隔离验证。

| 验收项 | 可查证的范围 |
| --- | --- |
| 真实 ChatGPT | **REAL_ACCEPTANCE_NOT_RUN**。内置 Chrome 接口创建专用草稿、查询浏览器连接都超时，未取得可操作的标签页。没有进入私人历史、执行附件输入或发送消息。正确聊天、首张与连续第二张、原正文与旧附件、真实 START、失败和 UNKNOWN 均无本轮线上结果。恢复条件是正常可用的 Chrome 接口及可确认的专用可编辑草稿。 |
| 首用、目录与无目标 | 本地完整 App 使用独立测试目录和偏好，见[原生实测](native/README.md)。托管账户按正常入口首启本次候选，另以独立目录演练旧版升级和回退。具体运行结果随本 PR 的 Actions 原始 JSON 记录，系统已有读取权限和出现过真实授权弹窗分别判断。 |
| 官网 | GitHub Pages 来源为 main 根目录。官网首页返回 HTTP 200，内容与正式首页字节相同。新增[下载状态](../../download/index.html)、[使用指南](../../guide/index.html)与[隐私](../../privacy/index.html)的中英文页面，仅作分支预览。 |
| 存储 | 设置中的用量检查按已实现的五项范围统计；用户可显式在 Finder 定位当前数据根。卸载后的残留、备份覆盖范围和[单张私有副本删除提案](../../docs/PRIVACY_AND_DATA.md)都有明确说明。没有启用永久删除或保留期限。 |
| 发行 | `preflight` 在未配置参数时以 `BLOCKED_CREDENTIALS` / exit 3 结束。本机可用 Developer ID Application 身份数为 0，notarytool 与 stapler 已安装。正式 ZIP、私有评审 DMG 和真实 Gatekeeper 各有独立条件。见[获批后的执行清单](../../docs/release/AFTER_DEVELOPER_APPROVAL.md)。 |

原生、Feedback 的正式 CI 继续构建并验证工程包，制品上传只包括报告和包的散列。公开下载、邀请和安装均未执行。完整 Xcode 的原生 XCTest 在正式 macOS CI 执行；本机仅有 Command Line Tools，本地 XCTest 尝试缺少 XCTest 模块。离线发行、备份恢复和主线隔离套件在本机分别通过 74、25、34 项。

消费者资料绑定到功能提交 `153e77bf83366b96789b23fe4b48a1fe644ca42c`。旧绑定在本次内容上得到 87/93，差异均来自 6 个已修改的源文件。上一份清单逐字保存在 [source-bindings-04.json](../productization-20261107/consumer/source-bindings-04.json)。核对这些内容并加入 5 个引导、设置与目录选择源码后，现有检查器通过 99/99 项文案、文件与链接检查。官网另外在 320、390、768、1360 像素宽度检查了双语导航、键盘、FAQ、首页弹窗和返回链接。

真实验收恢复时，在可确认的专用草稿中先留一句无隐私正文和一个可辨认的测试附件。分别截取两张内容不同的测试图，用正常点击依次附加；逐张核实原草稿、原附件、选区、新增图片及对应 START，观察消息仍未发送。若结果不明，只核对原操作，不重新提交该图。受控样例、官网演示和上一次构建的历史点击均不能填入此次线上结果。

在已正常退出的一份隔离 App 测试目录中运行了现有 `storage-recovery.py` 的备份、独立 manifest 核验和恢复到新目录。三步均 exit 0、byteIntegrity=verified。恢复目录有 1 个资产、0 个附加操作、0 个 START；本次专用截图、私有媒体和收录日志与来源逐项同字节。备份 manifest SHA-256 为 `fcbe799ed44b657fd6f3a02ad553fb35dccb8d77501ca69caf5d4c81de41181e`。本次截图位于测试目录内；普通用户的外部系统截图目录需另行备份。
