# 点击前取得原始文档凭据

1.0.8 私有候选采用路线 A。普通 Chrome 和 Edge 均已让原始网页先向原生进程确认接收器，随后在原生测试视图收到定向鼠标事件。路线 B 在正常安装的 Edge 引擎中也可行，但对普通 Chrome 还需要正式分发扩展，在 Safari 还需要独立的 App Extension。首次点击的消费级可靠性以真实聊天验收为准。

| 验证项 | A · 无扩展 Apple Events | B · document_start 和 Native Messaging |
|---|---|---|
| 冷、暖首个事件 | 两款正常浏览器均在专有测试页确认。Chrome 首个 ACK 至事件 55.431 ms，Edge 35.585 ms。软件产生的事件由测试进程的 AppKit 视图接收。 | 在正式 Edge 158 和 Chrome for Testing 156 的独立配置中，原生 ACK 前的事件被拒绝，ACK 后的冷、暖操作各自完成一次。事件由 AppKit 构造，未投递到桌面。 |
| 原始文档、编辑器和附件入口 | 接收器保留真实对象及编辑器、草稿、模式的代际。替换文件输入、移出并放回原控件或切换标签后退休。 | 浏览器签发 documentId。文档启动脚本还保留原对象及代际，在编辑器 A→B→A、草稿替换及同 URL 新文档时拒绝旧操作。另以真实两个标签切换，在 B 与返回原 A 时都拒绝旧票。 |
| 原窗口、标签与两次独立输入 | 原生签名、进程出生时间、窗口 ID 和标签 ID 验证通过；两个独立凭据可并存。原生测试的两次按下相隔 Chrome 116.210 ms、Edge 102.158 ms。页面用例另行校验两份真实 File 字节。 | 收件地址含浏览器实例、原生消息连接、tabId、documentId 和代际；原生 SQLite 先认领，丢失回复不再写入。 |
| 安装与受测范围 | 继承 build 56 既有 Apple Events 路径。普通 Chrome 与 Edge 已测本地页。Chrome 官方控制器按名称分配时选到 Owl；产品按签名和进程识别普通 Chrome。 | Edge 正式引擎与 Chrome for Testing 跑通原生消息。普通 Chrome 157 打开了测试页，未加载未上架扩展。没有更改浏览器配置或安装策略。 |
| Safari | 当前脚本字典提供页签对象和 WebContent PID。尚无实机证据把它们与固定文档和编辑器绑定。 | Safari Web Extensions 提供文档身份和原生消息，需签名的包含 App、扩展启用和站点授权；尚未实测。 |

[普通浏览器的原生回执](../../../Tests/PreClickLease/native/receipt.json) · [页面对象与字节证据](../../../Tests/PreClickLease/page/source-results.json) · [扩展的标签 A→B→A 和原生宿主重启回执](../../../Experiments/PreClickDocumentStart/tab-restart-receipt.json) · [扩展实验与浏览器厂商文档](../../../Experiments/PreClickDocumentStart/README.md)

## 一次点击的权限边界

1. 浏览器激活、窗口或标签变化、截图到达及指针进入托盘，可以触发准备。Mac 只认可已签名厂商进程和当前原生窗口、标签。一次准备返回原始 Document、编辑器、附件入口、草稿代际和独立的 clickBindingID。
2. Mac 在获得整份回执后用本机单调时钟记录 ACK。托盘 mouseDown 读取 AppKit 事件自带的原始 timestamp，并核验相同接收进程和窗口、标签。只有 ACK 严格早于按下，本次操作才可冻结一份凭据。没有凭据时截图留在托盘。
3. 冻结后，原接收器处理这一张 PNG、这一份已持久化的 operation 及 invocation。commit 紧邻 setter 检查原始网页对象及代际。另一张图需要另一个点击和凭据。正面附件证据控制收起，旧操作只能按原身份观察。
4. 可见截图长时间闲置时，每四分钟仅向持有的原接收器续期。Mac 的九分钟有效期早于网页的十分钟上限。过期、失焦、文档或编辑器退休会拒绝输入。后来的网页发现不能挽救早已发生的点击。

生命周期为 CREATED → ACKNOWLEDGED → ARMED → FROZEN → CONSUMED。任一原对象失效会退休其凭据。已进入投递而结果不明时，SQLite 保留原 UNKNOWN 和 PNG。原操作的观察没有写权限。
