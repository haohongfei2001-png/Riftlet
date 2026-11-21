# W3/W4 独立 Provider 探查

2026-11-20，Chrome 157.0.8103.79。八个官方网页入口使用全新的匿名浏览器上下文顺序访问。已确认 Gemini 的公开落地页可以只读定位一个主编辑器和上传菜单。八个平台的已登录草稿、真实文件事件、原图接收和原卡失败都待验，当前均未开放正式写入。

| 平台 | 匿名 Chrome 看到的内容 | 尚缺的证据 |
|---|---|---|
| Claude | `claude.ai/new` 返回 403，没有可见编辑器或文件输入。 | 允许访问的普通登录会话，以及对话草稿与 Project Files 的区分。 |
| Gemini | `gemini.google.com/app` 有两个可见可编辑 div。主 textbox 是 `rich-textarea` 的 `.ql-editor` 直接子元素。主编辑器最近的 fieldset 内有一个带上传含义的可用菜单按钮，且归属同一 form 或双方均无 form；初始页面没有原生 file input。真实页面执行只读检查返回 `editor_and_upload_action`。 | 登录后普通草稿、动态菜单实际绑定的输入、模式变化、文件事件与回执。 |
| DeepSeek | `chat.deepseek.com/` 最终落在账号页面，出现登录控件，未见编辑器。 | 当前登录模式的图片或文字识别能力及原卡处理语义，均为 unknown。 |
| Kimi | 根页显示可编辑 div、上传及研究入口。有一个隐藏的多文件 input。与上传入口的最近公共 div 中可见一个编辑器和这个 input。 | 共同容器和 accept 提示不足以证明哪种模式、哪个输入能接收当前图片。 |
| 国内千问 | `www.qianwen.com` 根页出现可编辑 div 和附件按钮，初始 DOM 没有 file input。 | 动态挂载后的归属，普通、研究及文件处理模式。 |
| 豆包 | `www.doubao.com/chat/` 首次观察有可编辑 div 和含图片字样的控件；第二次观察只得到首屏内容，未再见到编辑器。 | 真实编辑器、图片入口与模式，不能从首次出现的图片文字推定。 |
| Perplexity | 根页有可编辑 div、附件按钮和隐藏多文件 input。input 的 accept 含图片提示，但最近的按钮/编辑器公共容器里没有这个 input。 | 动态或跨容器输入的责任归属，首页与 follow-up 的身份和卡片。 |
| 国际 Qwen | `chat.qwen.ai` 根页有 textarea 和一个隐藏多文件 input，未找到已知文字的具名上传入口。 | 直接输入归属、模式、事件及原稿回执。与国内千问分别登记。 |

[逐次脱敏观察](anonymous-observations.json) 记录实际时间、最终 origin、路由类别、文件输入属性、可见控件及局部关系。控件文字只保存预定义分类。未点击登录、验证页或网站上传入口。每次运行结束会关闭自有无界面浏览器并清除临时配置。

## 可以复用的隔离产物

- [GeminiLandingProvider.swift](GeminiLandingProvider.swift) 对接已冻结的 `ConversationProvider`。已观察的精确 `/app` URL 只提名公开落地页。未验证的 query、子路径、片段、其他 origin 和私有模式没有路由。profile digest 来自 [只读页面程序](gemini-surface.mjs) 的实际字节。
- [受控附件流程](fixture/synthetic-handoff.mjs) 只在本机回环地址及显式合成 profile 上运行。站点样例声明自己的文件 label、成员区与文件事件。读者保留原 invocation、原稿及原成员，调用方只能再次观察。夹具使用与原操作相同的文件名和逐字节 PNG 摘要验证新成员，独立判断同卡错误。内联预览、失败 output 以及 input + change 的组合均是该本地样例的合同。
- [浏览器反例](fixture/cases.mjs) 在真实 FileList 上覆盖同操作重复 pin、重复 invocation、重复点击身份、关闭句柄及标量身份记录到达上限、并发重复、丢失回执后重查、同名错图、srcset 呈现另一张图、异步摘要期间隐藏或换掉预览或出现错误、原稿外卡、重复成员、相邻错误、原壳替换、移除后重新接回、输入前已有预览、旧预览换壳、change 抛错后保持 UNKNOWN、同 URL 新历史项、模式切走再切回、文件 label 改投和原编辑器拆除。两张不同 PNG 可以先后附加；输入框原文、选区、既有卡片仍在。实际执行产生 5 次明确指令对应的 setter，其中 4 次收到 change，另 1 次在 change 调度时受控中断并保持 UNKNOWN，0 次错投、0 次提交、0 个外部网络请求。

[受控执行回执](fixture/controlled-chrome-receipt.json) 保存实际文件事件计数、Chrome 版本和脚本摘要。

## 重跑

Swift 检查链接真实的 RiftletCore 和冻结接口。在 macOS 从仓库根目录运行：

```sh
engineering/preintegration/issue-120/providers/check-swift.sh
```

浏览器检查使用本机已安装的 `puppeteer-core` 和 Chrome。若模块不在 Node 的默认解析路径，可用 `RIFTLET_PUPPETEER` 指向其已安装目录。Linux 或自定义 Chrome 路径可设 `RIFTLET_CHROME_BIN`。

```sh
d=engineering/preintegration/issue-120/providers
node "$d/run-fixture.cjs"
node "$d/probe-anonymous.cjs" gemini
```

省略平台参数会顺序探查登记的八个公开入口，一行 JSON 对应一次观察。后续应在允许使用的正式登录草稿上先绑定原点击，再验证实际文件入口、事件配方、接受、失败与读回。真实正面附件出现前，保留用户截图及 UNKNOWN。
