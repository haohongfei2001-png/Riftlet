# Riftlet 1.0.8 最终候选验收

当前总判定为 **PARTIAL**。唯一待验候选为 **build 58**，产品提交 `c7ef1027f9475d517abbd4d85ae1819b9351a8cf`，源码树 `cb96a4e157eadb5bffd2ab1f79c1b252485dfcbc`。页面程序 SHA-256 为 `43e43df544d4edb6081dfe592b1b18166039f98983ab8f0fac0f31efdf60d166`。1.0.8 用于私有验收。#120 保持打开。

| 同包实站验收 | 状态 | 所需证据 |
|---|---|---|
| G1 普通 Chrome × ChatGPT | **PARTIAL，首次投递为 UNKNOWN** | 真实已登录临时草稿，AppKit 收到一次托盘单击。原目标 ACK 早于按下 2,356.714 毫秒。实际网页只收到一次 file input 和一次 change，发送为零。原图仍在，SQLite 保留唯一操作及调用，尚无本图原卡 START。 |
| G2 普通 Edge × ChatGPT | **PARTIAL，首次投递为 UNKNOWN** | 已登录临时草稿。原目标 ACK 早于托盘按下 1,072.093 毫秒，原表单接收的 File 与本地 PNG 的 SHA-256 一致。网页实际收到一次 input、一次 change，发送为零。Riftlet 未得到本图原卡 START。 |
| G4 真实原卡失败与找回 | NOT_RUN | 同一张原卡明确失败、原 PNG 与 SQLite 原操作保留、显式再次点击产生新调用且新图实际附加。 |

Chrome 首图是来自本机专用纯色窗口的系统截图。实际点击经过正常托盘 AppKit 按下与松开、冻结原凭据和持久化投递。草稿初始为空，原文档、编辑器和空选区得到保留。非空文字、选区、已有附件及每款三组双图需另有正面证据。私有记录保存原图和每次原生事件，公开记录列出原图哈希、原稿身份摘要、operation、invocation、回执及网页计数。[Chrome 实站首图](evidence/build58/chrome-live-candidate.json) · [两种真实窗口大小的定向鼠标校准](evidence/build58/mouse-calibration.json)

Edge 的原表单在输入后 32 毫秒显示一个包含本图完整文件名的移除按钮。2,047 毫秒后，草稿内出现新的内嵌图片，2,281 毫秒时已可见且解码尺寸为 330 × 196。此时图像及其旁边的移除按钮均未给出本次文件的精确名称。现场记录保留两阶段时序与原图哈希；这一轮监听器没有保存跨阶段的卡片对象关系。两款浏览器的原操作均留在 SQLite，本地原图的哈希仍与来源一致。[Edge 首次输入](evidence/build58/edge-live-candidate.json) · [原表单的两阶段时间记录](evidence/build58/edge-original-card-timing.json)

## 已完成的源码与独立复核

Chrome、Edge 的受控页面回归各完成 19 项，包括新进程按原资料库身份接替预备凭据。真实内核文件锁保证同一资料库的持有者互斥。原持有者结束后，新持有者可以取得两份自己的预备凭据。另一资料库仍能持有自己的凭据，已登记的 UNKNOWN 仍可在原操作上只读查询。独立审查还实测了两个资料库通过硬链接共享锁文件的情形，资料库身份仍可区分。[独立进程与文件锁](evidence/build58/lock.json)

正常退出会先停止新准备，再等待已有准备和释放。独立调度实验中，四项释放在约 0.16 秒内完成。故意阻塞传输时，约三秒后正常返回，未确认的四项继续记在途。build 56、57 没有新资料库代际标识的旧预备凭据仍按原对象失效或有界到期。原操作续查需要唯一匹配通道及正确调用身份，多个通道匹配时保留 UNKNOWN。[退出调度与截止时间](evidence/build58/quit.json)

非实现者已对精确源码提交完成独立审查，准予制作私有候选。build 57 的实站预绑定、Chrome 已登录草稿上的一次未确认鼠标投递、正常退出缺陷和历史安装证据均存入独立报告。[build 57 完整验收记录](BUILD57_ACCEPTANCE.md)

## 私有镜像与同包检验

DMG 大小为 13,732,388 字节，SHA-256 为 `0f36dbee6665e5687c6c7722574cdeea708ee56ae0ae07d583652a33204c2f7e`。App 和镜像均由 Developer ID 签名，通过 Apple 公证、票据装订和 Gatekeeper。未参与实现的审查人另行挂载同一镜像、复制出独立 App，核实 arm64、x86_64 两种签名、两份旧页面指纹和当前页面资源，并在 arm64 上运行三项应用自检。[首次安装](evidence/build58/installation.json) · [独立安装](evidence/build58/independent-install.json)

GitHub ARM64、Intel 作业均直接验证了冻结产品提交。每种架构发现的 1,434 个 Swift 测试均在互不重叠的并行、串行两组执行。每种另有 19 项 Chrome 页面回归及 8 项离线恢复测试。将签名 App 的页面资源直接交给本机两款独立引擎复核，各通过 19 项。受控双图间隔分别为 5.5 毫秒和 4.7 毫秒。[GitHub CI](https://github.com/haohongfei2001-png/Riftlet/actions/runs/44985432085) · [完整分组](evidence/build58/ci.json) · [同包浏览器回执](evidence/build58/installed-page-results.json)

冻结的 build 56、57 页面程序分别产生 inputTriggered、uploadStarted，再由独立原生读取进程使用最终 build 58 页面字节识别原通道。四组均读回原状态，错误 invocation 均被拒绝，输入和 change 维持最初的各一次，零发送。[旧操作只读回放](evidence/build58/old-operations.json)
