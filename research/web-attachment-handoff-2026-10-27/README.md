# ChatGPT Web 附件技术交接 · 2026-10-27

本目录把已完成的真机实验移交给 Riftlet 正式工程，**没有开发生产适配器、重新上传图片或寻找内部 READY**。只新增本目录；不改 main、PR #1 的代码、收据注册表、CI 或网站。

**裁决：已有证据允许进入网页版正式开发，并支持保留原图、可撤销的产品级 ATTACHED。严格内部 READY 未证明；不是发布验收或自动启用生产 profile 的补丁。**

先读 [工程复用说明](INTEGRATION.md)，再读 [风险与恢复](LIMITATIONS.md)。完整文件清单见 [FILES.md](FILES.md)，逐文件校验见 [MANIFEST.json](MANIFEST.json)，原始来源及变更见 [PROVENANCE.json](PROVENANCE.json)。

## 一条命令离线复现

在仓库根目录运行，要求 Python 3.10+、Node 18+，没有第三方依赖：

```sh
python3 research/web-attachment-handoff-2026-10-27/replay.py
```

此命令只读本目录并运行离线测试，不会启动浏览器、请求网络、上传文件或发送消息。不要求 Mac，不需要登录或凭据。它验证：

- 最初三次真实 Apple Events 输入、不同操作 ID、既有草稿文字与附件保留，以及刷新后的 UNKNOWN。
- 正常手动上传的历史判定：19 个测试（3 个真实轨迹/前缀，16 个模拟反例）。
- 真实并发上传和打字：两图各自 ATTACHED；另一图完成时，本图仍为 UPLOADING。
- 两种真实中断：MID、POST100 均 UNKNOWN；40 + 49 个事件前缀无误报。
- 真实临时聊天切换：旧目标 UNKNOWN。
- 原生 XHR 中断链路、原图保留、防重复拒绝与故障钩子清理的历史回执。
- 另外两个模拟迟到错误否决检查。**没有真实“最终预览之后失败”的样本。**

运行记录见 [OFFLINE_RESULTS.md](OFFLINE_RESULTS.md)。这些是本轮重新执行的离线回放，不冒充新增真机验证。

## 已交付内容

| 需求 | 直接入口 |
|---|---|
| 已通过真实自动插入的代码 | [shared-adapter.js](src/input/shared-adapter.js)、[AppleScript](src/input/web-evaluate.applescript)、[持久化分派器](src/input/dispatch_fixture.py) |
| 图片/目标/composer/草稿关联 | [正常绑定探针](src/observers/normal-bound-observer.template.js)、[并发异常探针](src/observers/exception-observer.template.js)、[字段映射](INTEGRATION.md) |
| ATTACHED 源码 | [历史 v1](src/attached/attached-verdict-v1.cjs)、[异常轨迹审计实现](src/attached/attached_exception_audit.py)；二者用途不同，不直接复制为生产策略 |
| 真机异常证据 | [cases.csv](cases.csv)、[异常主测试证据](evidence/exceptions/main/)、[切换证据](evidence/exceptions/transition/) |
| 离线回放/合成图 | [replay.py](replay.py)、[fixtures 清单](fixtures/manifest.json) |
| UNKNOWN/防重复/迟到错误 | [风险与恢复](LIMITATIONS.md)、[recovery-query.js](src/input/recovery-query.js)、[重复拒绝回执](evidence/exceptions/main/recovery-verification.json) |
| 未通过的场景 | [LIMITATIONS.md](LIMITATIONS.md)、[环境与适用范围](environment.json) |

## 关键实测事实

真实故障通过精确关联自有创建请求及其实际返回的上传地址，对 ChatGPT 自己发起的 XHR 调用原生 abort；没有伪造服务器回应，没有调用猜测的私有上传 API。

- MID：真实字节进度 81875/5506018、abort、loadend status 0，无最终 data 预览。
- POST100：自有 UI100 触发中断，同一请求原生 progress 载荷 25265/25265，status 0，无最终 data 预览。这是客户端中断，不等于服务器最终化拒绝。
- 同页两图各有独立 card/image 节点，逐附件完成。合成文字长度 52 在并发上传及故障后保留。
- 切换“临时聊天”实际使路由变为 `?temporary-chat=true`，旧绑定失效。文件标签 `TAB_SWITCH` 是准备时的历史名字，**本例不是浏览器活动标签切换**。
- 大 PNG 被应用重编码，最终文件字节不同，但原图/预览解码后的 RGBA SHA-256 完全相同；不能要求每个合法 PNG 的最终文件字节都不变。

## 发布安全与来源

公开资料已去敏：真实 window/tab/document/session 标识一致匿名化；不收录账户/profile 名称、用户路径、Cookie、Token、请求/响应体、签名 URL、真实截图、私人聊天、浏览器清单或 Console 转储。仅保留测试有关的 DOM 属性，删除 UI 文本载荷和完整 HTML。单调时间保留用于事件顺序，不是成功阈值。

三张图片均为生成的蓝色/橙色文字图或随机噪声图，经过视觉检查、字节校验和 PNG 元数据检查。小图唯一 EXIF 是像素尺寸，没有作者、设备或位置数据。原始 SHA-256 保持不变，保证可核对实测文件；多个操作复用同一字节源时仍保留各自独立身份。

源代码是本次 Riftlet 隔离实验的自编诊断代码，未新增上游依赖或复制 ChatGPT 应用源码。`src/lab-only/` 是历史故障诊断实现，**不能加入生产上传路径**。发布版模板移除了活跃实例绑定；归档脚本不是可直接操作当前浏览器的一键工具。原始本地日志和代码仍保留，没有覆盖。
