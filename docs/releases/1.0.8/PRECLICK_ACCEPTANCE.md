# 1.0.8 build 57 验收

正式候选的产品提交为 `3a4bf462cb1e02ae305328b0f1f64792ec14adb8`。当前总判定 **PARTIAL**。本记录将签名镜像、普通浏览器的自建页面和已登录真实站点分别核验。

| 已完成的验证 | 结果 |
|---|---|
| 普通 Chrome 和 Edge 的原生身份 | 厂商签名、内核进程出生时间、应用和可执行路径、原生窗口与标签均获确认。Edge 的官方控制器匹配真实进程。Chrome 按名称认领的官方实例返回 Owl，另以独立签名校验确认普通 Google Chrome 的产品原生通道。 |
| 先收回执再按下 | 两款普通浏览器各 4 个独立原页面凭据，4 次定向软件鼠标事件到达本机 AppKit 视图；事件本身时间均晚于 ACK。普通 Chrome 为 55.431、2.970、2.069、1.513 ms。Edge 为 35.585、1.135、1.107、3.020 ms。 |
| 双图前置条件 | ARM64 在 1a3bb03d 复现第二张图无可用凭据；已修复，原生池的两次按下可持有两份独立凭据。页面测试核验两张不同的 PNG 字节、文字、选区及旧附件，真实站点各三组另行判定。 |
| build 56 已有操作 | 在受控页面安装签名 build 56 的原程序。新版的三个新进程按原身份观察，inputTriggered 与 uploadStarted 均保留原状态。错 invocation 返回 invalidated。每组仅最初的 1 次输入及 change，零发送。 |
| 最初的 Edge 站点预检 | 正式控制器打开 Temporary Chat，核对了精确网址、原窗口和标签。该次窗口随后失去前台，局部控件读取超时。专窗已关闭并核对原有窗口集合。 |
| 真实站点上的自动准备与系统截图 | 同一安装副本分别在普通 Chrome、Edge 的 `chatgpt.com` 临时草稿上获得两份原目标回执。两个回执均先于本地首次可见截图记录，随后各有四次原目标续期成功。两次系统截图均来自独立的纯色窗口，私有资料库中的 PNG 与各自原文件逐字节一致。Chrome 首次准备曾收到 `ATTACHMENT_INPUT_UNAVAILABLE`，其后同一标签已自动准备就绪。两次准备实验各有零次托盘单击和零个投递操作。 |

[原生浏览器与完整采样](../../../Tests/PreClickLease/native/receipt.json) · [受控页面结果](../../../Tests/PreClickLease/page/source-results.json) · [跨版本及快速双图原始回执](evidence/compatibility-and-fast-pair.json) · [最初的站点预检](../../../Tests/PreClickLease/native/website-preflight.json) · [同包站点回执、截图原件与 SQLite 核验](evidence/website-preclick.json)

## 独立审查

非实现者复核了产品提交。初轮发现双票相互淘汰、取消按压留票和 QA 历史入口可越出本次专窗。复核修复时又发现，SQLite 已认领的投递可能被晚到的界面回调撤销。最终使用原选择对象的同一把锁区分投递前取消与已认领的原调用。最终结论准予私有签名和内部验收。

若 SQLite 最终提交失败，或在持久化投递意图后读取请求文件失败，尚未进入 begin 的页面凭据可能留至有界过期。原操作不会因此重传，原图继续按既有策略保留。另一位非实现者独立复算 build 56 指纹，并实测单通道、通道替换、不同标签与多个通道的只读行为。

## 最终镜像与安装副本

私有 Riftlet 1.0.8 build 57，DMG 为 13,661,114 字节，SHA-256 为 `be32c977b1dbf24fd90923d8b26329b1a4f65ab63c706ea2702aceb9243e53dd`。Developer ID 团队为 `ZB9D4T66QB`。App 与 DMG 分别通过 Apple 公证、票据装订和 Gatekeeper。只读挂载后复制的安装副本含 arm64、x86_64 可执行文件，SHA-256 为 `0be3aa08d7d597b248428b8abd1fd6adcecf48a1266ddbe53482382aca66eaed`。三个应用自检分别成功。[签名、安装和自检回执](evidence/installation.json)

从这一安装副本读取的页面程序 SHA-256 为 `0ac5c59b4856f26a50f5f22d8142314444db361a69753d0ee32cb767d89be87f`。Chrome、Edge 独立引擎各通过本轮 18 项新场景；双图用例两次按下间隔分别为 27.4 ms 和 10.7 ms，两份交付 File 字节与各原图相同。测试页未连接 ChatGPT 服务。[同包页面原始记录](evidence/installed-page-results.json)

另一位未参与实现的审查人另外挂载同一镜像，复制出第二份 App，独立核对两个架构、签名、硬化运行时、公证票及 Gatekeeper，并运行三个自检。其资源和可执行文件摘要与首次安装一致。受限执行环境起初无法连接系统验证服务，正常 macOS 环境的复核均通过。[独立安装记录](evidence/independent-install.json)

G4 的专用客机 A 在 build 43 曾证明，单独中断该客机的传输可让官方原卡显示失败和 Retry。本次正常启动相同客机且匹配原 SSH 主机密钥，但其专用系统凭据引用已失效，无法进入已登录图形会话或建立只影响该客机的控制链路。此次未造成真实原卡故障。启动器已退出，三台测试客机的磁盘均无占用，未收到客机系统自身的正常关机回执。[当前和历史的 G4 记录](evidence/g4-environment.json)

## 双架构 CI

ARM64 和 Intel 均通过。在测试修订 `1bce2891c510263b5c05dec0857afdea04247f06` 上逐项核对 `Sources`、`Resources`、`Package.swift`、`Package.resolved` 与签名产品提交完全一致。每个架构核对了 1,432 个 Swift 测试的完整分组，另运行本轮 18 项 Chrome 受控页面测试及 8 项离线故障恢复测试。CI 不向真实 ChatGPT 发送图片。[两个 GitHub 作业](https://github.com/haohongfei2001-png/Riftlet/actions/runs/44930670085) · [分组、回归名称和制品哈希](evidence/ci.json)
