# 1.0.7 原目标身份与真实站点准入 · 2026-11-21

**结论为 PARTIAL。** build 53 收回实站准入。基于同一 #119 源码的独立修复候选 build 54 已签名、公证。其安装包内页面程序在 Chrome 和 Edge 各通过 15 个受控场景。两个浏览器的登录草稿与真实失败恢复均为 `NOT_RUN`。#120 保持打开，公开版本为 1.0.5。

## 原操作实际在哪一步可以写入

原生执行器在点击时取得进程出生身份、窗口及标签。已有点击绑定的写操作只能使用原路由和原 relay。重启后恢复的操作允许按原目标只读查询；恢复路径不能取得一次新的写许可。SQLite 保存 dispatch intent 与 invocation，已进入输入后结果不确定的原操作保持 UNKNOWN。[冻结的原生执行器](https://github.com/haohongfei2001-png/Riftlet/blob/c764246410c2c0c225ac4bb8688c2ae5179f27e9/Sources/RiftletAdapters/ChromeAppleEventsExecutor.swift) · [冻结的 QueueStore](https://github.com/haohongfei2001-png/Riftlet/blob/c764246410c2c0c225ac4bb8688c2ae5179f27e9/Sources/RiftletCore/QueueStore.swift)

页面见证记录原文档、导航代次、表单、编辑器及点击。blur、隐藏、pagehide、导航或原表单/编辑器被移除时，旧点击丧失写权。动态 locator 再次匹配成功不能建立该见证。13 项套件在 build 53 每款浏览器均通过 10 项，复现以下三项缺陷。[原始对照结果](../../../../Tests/Build53TargetSafety/build53-results.json)

| 发现 | build 53 实测 | build 54 实测 |
| --- | --- | --- |
| 已打开附件菜单，在等待选项时 A→B→A | 旧操作仍激活选项、发出 Escape 并恢复选区，各一次。四个文件/发送计数均为零 | 三项后续操作均停止，四项计数均为零 |
| 站点处理 input 时同步重建编辑器 | 旧动作继续触发 change | 已进入的 setter/input 各一次；change、send 均为零，原操作只读 UNKNOWN |
| 站点处理 input 时移动文件输入的整个父容器 | 直接父节点和表单碰巧相同，旧动作继续触发 change | 同样停止在 1/1/0/0，重复提交未进入输入 |

修复限于附件菜单和最后一次文件交付。在每个可能同步调用站点代码的步骤之间检查点击见证、原文档、原编辑器及文件输入的归属链。最后的检查与 setter 在同一段同步执行中相邻，期间没有异步跳转。站点处理 input 后须重新核对才能触发 change。分支未修改队列数据库。产品非作者复核确认源码树 `024a15e932bbf7ec7e1551dd39003ef77a5eb95e`，该树对应已公开的修复提交 `95d8cf80`。[独立修复 PR #123](https://github.com/haohongfei2001-png/Riftlet/pull/123)

## 同包结果与边界

| 项目 | 实测与范围 |
| --- | --- |
| 封装来源 | #119 build 53 DMG 的 SHA-256 复算为 `9458479641bde6147de37fda8b873507b2a312a153a76c08e166e50903583dee`。build 54 是单独的 arm64/x86_64 Developer ID 候选，其 DMG SHA-256 为 `22e5557bc2a80864263e4e8d9e08a4aef29f81afc088b18a2a6ccf26c2857c5c`。App 与 DMG 的公证票据有效，Gatekeeper 接受。 |
| 安装修复候选 | 从正式 DMG 只读挂载并复制到独立 QA 目录，验证全部架构签名、票据，并执行安装 App 的截图候选和 Web 启动自检。页面资源 SHA-256 为 `9b9a1ecd12b8433c7a9243ebedb72fefcc7dc8d69fd2602e4caf895c89b7ab36`。[包回执](package.json) |
| 同包页面程序 | Chrome 157.0.8103.79、Edge 157.0.4341.60 均实际执行安装 App 中的上述资源。覆盖离开标签、标签 ABA、同 URL 替换/reload、Navigation API A→B→A、真实 pagehide/BFCache、编辑器替换、关标签、关整窗与重启。见证已失效的提交均为 0/0/0/0。原稿未变时为 1/1/1/0，文字、选区及旧附件节点保留。只读观察和重复提交没有增加输入。[页面 26 项](installed-54-page.json) · [关窗与重启 4 项](installed-54-host-lifetime.json) |
| 原生与 SQLite | 用候选对应源码的实际 Core/Adapters、独立数据库及原生 Apple Events 运行旧操作。最终一轮分别发出一次定向关窗请求，两款浏览器应答后均以只读查询确认原窗口消失，原操作提交/观察被拒。先期未取到窗口或无法确认的轮次分别保留。进程重启后，提交、只读观察、再提交均未进入页面派发。原 operation、invocation、UNKNOWN 与原图保留。记录中的 DOM 计数为 null；上行浏览器实测有独立四项计数。[原生及持久化收据](native-result.json) |
| 身份复用边界 | 使用同一组传入的窗口/标签身份测试替换文档，构造同 PID 不同出生时间的反例。真实重启前后 PID 不同。系统自然复用全部数字 ID、前台已缓存点击路由关窗、鼠标按下至首个页面见证建立之前的完整 ABA 均无端到端实测。L2 页面套件通过，完整原生到网站准入仍为 PARTIAL。 |

## 正式浏览器控制与网站验收

验收器分别保存 `nativeWindowID`、`nativeTabID`、`browserReferenceID`、`providerTabID`、`claimedTabHandleID`。给唯一新普通 QA 标签建立一次性命名组，核对原生窗口/选中标签、组成员，再认领唯一引用，并核对受控 handle 及 provider 的原值。若已观察到身份丢失，旧 guard 永久退休。五项身份能核对到原标签，真实键盘的投递目的地仍需要文档和编辑器保证。[身份映射及测试入口](../../../../Tests/LiveDraftAcceptance/README.md)

| 浏览器 | 正式控制的实测结果 | build 54 登录 ChatGPT |
| --- | --- | --- |
| Chrome | 本轮按官方 `chrome` 选择器取得 Owl；创建普通窗口返回 `Creating browser windows from extensions is not supported in Owl.` 先前普通 Chrome 观察另计。本轮五域独立窗口复验受阻。 | G1 冷/暖首击及三组两秒双图 `NOT_RUN` |
| Edge | 已登录配置的独立普通窗口通过原生及五域只读核验。在两个自建网页中，旧标签的同一真实按键入口先向 A 输入 `q`，同标签切为 B 并聚焦其编辑框后向 B 输入 `z`。这次操作针对验收键盘，未调用 Riftlet 附件接口。 | G2 冷/暖首击及三组两秒双图 `NOT_RUN` |
| G4 | 当前候选没有在 ChatGPT 观察到原卡服务失败、找回、用户明确重试及成功附加的连续实证。 | `NOT_RUN` |

索引式 AX 按键的接口说明只承诺尝试先聚焦相应元素。当前已核验的官方接口缺少在实际按键投递时原子限定原文档和编辑器的能力。正式验收入口在开窗前报告 `ORIGINAL_DOCUMENT_KEYBOARD_UNAVAILABLE`。非作者复跑验收器 34/34 项，通过。恢复条件是取得可验证的正式定向输入能力，先在自建页面通过原稿、替换、ABA 及一次性操作对照，再在同一 build 54 上执行登录草稿。未触碰个人会话；本轮自建可见窗口和本地服务已清理。[正式控制实测时间与收据摘要](official-control.json)
