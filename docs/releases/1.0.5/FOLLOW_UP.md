# 1.0.5 真实附加与托盘交互复验

本轮从 PR #113 已通过五项检查的 `d6248d5` 继续。build 30 的签名主程序 SHA-256 为 `c1474953ca02d19c21f773ef1847b1507792cbe2284ae30d30f3e34b69fac3e6`。[前次验收](RC_REPORT.md)

| 流程 | 普通签名 build 30 的观察 |
|---|---|
| 真实冷首击、正确草稿 | 隔离 macOS 的普通 Chrome 打开新的 ChatGPT 临时聊天，页面返回 `ERR_CONNECTION_REFUSED`。未取得可用编辑器，未执行附件输入、发送或改动既有草稿。 |
| 两秒内连续双图 | 同一真实草稿前置条件未满足。三组两次独立点击的间隔、两次实际 START、草稿保留和真实发送计数均未测得。 |
| 接收后明确失败 | 未取得真实服务的接收及终止事件。无法验证真实失败后的找回及再次点击。 |
| 托盘滚轮 | 在有 5 张可见截图的隔离档案上，通过虚拟 Mac 的指针向托盘发出滚轮输入。可见图组发生变化，反向滚动后恢复原组。 |
| 相机和 Escape | 通过虚拟 Mac 的普通指针点击相机，观察到横排 4 个按钮，再以键盘 Escape 收回为单相机。在同一会话完整重复两次。 |

[普通应用回执](evidence/acceptance-followup/build30.json) · [滚轮翻页](evidence/acceptance-followup/tray-wheel-page.png) · [反向恢复](evidence/acceptance-followup/tray-wheel-return.png) · [相机展开](evidence/acceptance-followup/tray-camera-expanded1.png) · [Escape 收回](evidence/acceptance-followup/tray-camera-escaped1.png)

## 原生检查为何超时

build 30 旧检查用应用进程合成并投递 Quartz 事件。滚轮部分已确认落点，但进程本地监听器收到 0 个滚轮事件，截图页未改变。相机部分命中托盘自己的窗口，随后在等待首次展开时超时，尚未发出 Escape。build 30 的这两条自动检查仍记为失败。build 31 用同一投递方式复查。系统事件发布权限预检 `CGPreflightPostEventAccess()` 返回 false。滚轮事件提交后，本地监听收到 0 个事件，页码仍为 [1,2,3]；相机命中本进程的目标窗口，鼠标按下和抬起均已提交，本地监听收到 0 个事件，首次展开超时，`escapePosted=false`。这定位了自动检查中断的环节。普通应用接收来宾指针/键盘的结果单列；本轮未调整系统权限。

## 接收后错误的识别

build 30 可以看见带有原文件名属性的卡片自身变为失败。在本机隔离 Chrome 的两图用例中，以无障碍标签标识同一文件、由原预览自身呈现错误时，build 30 仍报告已交接。修复在首次接收时记录对应卡片的弱引用，后续只读核对原草稿、原预览和文件身份。同一节点被另一张截图复用、标签出现矛盾、移入另一个编辑器或跨导航时，放弃这次错误归属。对旧版已打开页面也用原操作身份做只读核对。在原操作有限的只读观察期间（最多 8 次），匹配到局部错误后，仓库会显示「需要处理」；持有有效旧会话标识时可打开原对话核对。超出观察期的错误、已更换身份的卡片及无法核实的服务状态，均不能据此触发重试。服务端永久终止和可重试仍需独立证据。UNKNOWN 不自动重传，程序不发送消息。

原生集成回归另以合成页面回执驱动实际 Swift 适配器、协调器、SQLite 和仓库呈现：原卡 START 后报错，只有原图出现在「需要处理」，显示「需要检查原对话」，链接指向原会话 UUID。操作保留 UNKNOWN，再次选择未产生第二次 begin/commit；本地副本字节和旁图均保留。[原生回归](../../../Tests/RiftletAppTests/WebAcceptanceIntegrationTests.swift)

本地 Chrome 在 loopback 测试应用中运行，真实草稿与真实服务端失败仍以上表为准。公开下载和 stable feed 沿用原版本。

## 后续签名候选

build 31 的产品源码为 `fe9c227a3b89a082b9da39dc5bb1f5c0b955c2ee`。相同两图回归在 build 30 的页面程序上漏报原预览失败，修复后在隔离 Chrome 通过；另一图保持原 START，原草稿内容、选区和既有附件均被核对。原生事件诊断只读检查权限，不弹出授权请求。

App 与 DMG 均已完成 Developer ID 签名、Apple 公证、装订及验证。DMG 大小为 12,686,160 字节，SHA-256 为 `99276347932e231adf743664a54cfc782d8e345d89221587d54b7299a5c9f315`。主程序 SHA-256 为 `9408b891e805c141108b64019e523a45e30221a03a10c2b91ae97bb16cb66207`。同包 arm64 和 x86_64 切片均运行了离线自检，后者在 Rosetta 上执行。[包身份与公证回执](evidence/rc31/package.json) · [架构自检](evidence/rc31/package-selfchecks.json) · [两份签名包内实际页面程序的 Chrome 对照](evidence/rc31/signed-chrome-comparison.json)

普通安装的 build 30 与 build 31 均标为 1.0.5，现有 Sparkle 宿主要求营销版本、构建号同时递增，实测会拒绝这一候选间的更新。通过只读挂载最终 DMG 原位替换、弹出磁盘后启动 build 31，Gatekeeper 验证通过。原档案 29 个旧文件和原数据库行逐一核对一致，目录书签、反馈草稿均保留。

build 31 普通应用中，使用系统截图工具生成不同颜色的测试图。在 6 张可见图中正向翻到另一组三张，反向翻页返回原三张。两次普通相机点击均展开四键，各按一次 Escape 后恢复为单相机。操作数一直为 2，旧 UNKNOWN 和旧 START 各 1。
