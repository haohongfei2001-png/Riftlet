# PR #69 · Edge × ChatGPT 双图专项

本轮继续现有 Draft PR #69，基线为 `315978ed843ea7a0b4cc8b22fc19adcfba48c955`，main 为 `44f745a15ecb3682a9da0bda17f17a5d9fc1f07e`。没有合并 PR、改动公开安装包、更新源或用户生产数据。

## 当前结论

**商业双图验收仍未完成。** 已在实际 macOS 上用独立微软签名 Edge 副本和新空 Profile 打开 ChatGPT；页面显示登录按钮，并说明上传文件需要登录。已登录的专用草稿尚未建立，结果为 `BLOCKED_LOGIN / NOT_RUN`。未发送消息，商业文件输入、START 和完成均为零。所有商业矩阵格继续保留未执行状态。[现场脱敏记录](../engineering/universal-attachment/edge-double-image-20261114/isolated-login.json)

## 点击回执：新证据与旧失败分开

第一次托管诊断使用源码 `275012e547c2a3f0f6dd98626b47c67a72767011`、准入头 `c9127d52d8febd1a5a567a8d95e2d98b77c65ab8`、实际合并对象 `82c6ed99850cae80b1c8a5808f6c26f4735ce8c8`。普通 App 可执行文件 SHA256 为 `3a1ab253373f5fca8759637887a9c5b6494c15eecaf8909e3d111f94b7604eeb`。

两张不同系统截图分别经过 application down/up、原输入窗口、inputDown、onDown、gate accepted、inputUp、release selected，并各自得到匹配资产、窗口、事件标记的选择与 `browserNotFrontmost` 拒绝。该源码尚未注册 Edge，因此两次明确拒绝符合当时产品范围；队列两图仍可见，操作、文件输入和 POST 均为零。

原 ARM64 作业仍是 **failure**。汇总器额外要求不同 NSEvent.eventNumber，但软件发送器没有设置 CGEvent.mouseEventNumber。本机公开 API 的无投递分配实验确认两组默认值均为 0，显式 101/102 会原样出现在 NSEvent。发送器现为每张图指定独立正编号，接收端还必须精确匹配该发送值，保留原资产、窗口、tag、session、顺序及一次投递要求；没有删除断言或增加重试。

云端该次未导出编号的原始值，因此编号相等是源码及本机实验支持的解释，不能冒充已读取的云端数值。旧头 `315978e` 的第二张没有匹配选择回执，原因仍未确认，不追认旧运行成功。[原始失败 JSON](../engineering/universal-attachment/edge-double-image-20261114/phase1-hosted-original.json) · [SHA 与原始产物索引](../engineering/universal-attachment/edge-double-image-20261114/phase1-index.json)

## 普通 App 的 Edge 路径

`RiftletMain → ConversationClickRouter → ApplicationWebExecutor → EdgeAppleEventsExecutor → WebAttachmentAdapter / TransferCoordinator` 复用既有一次性输入及持久化状态机。Edge 后端独立依据安装的 Edge scripting.sdef，不把 Chrome 的 Apple Events 实现当作兼容证明。

- 按下时冻结原应用、PID/内核启动时间；路由交回的应用和 session 必须与最早快照相等。宿主选定后，所有命令仅依据原 TargetLease 路由。
- 原窗口、稳定 tab ID、文档、导航、编辑器和容器绑定均保留。Chrome 与 Edge 同步读取共享 150 ms 截止时间；后续脚本、权限检查及签名读取在后台执行。
- Edge 在实际 capture 现场验证 Apple Events realm 与 MAIN realm 的隔离及原文档；失败就拒绝。没有备用输入、任意 picker 或随后活动标签回退。
- 同一 operation 的 commit 只能进入一次。队列取消在派发前拒绝；一旦进入提交，丢失回复或取消只观察原 nonce，不重新提交。另一个图片有自己的输入身份。
- Edge 尚无实际商业上传状态校准。其预览不会产生 START，原生归一化也拒绝把 Chrome 的 START、attached、ready、failed 回执借给 Edge。当前这条路径有明确的工程限制，不能宣称已经具备商业上传完成能力。
- 原图元数据、私有文件 SHA、输入原图验证、SQLite 登记及 Chrome 历史观察资源继续使用既有实现。未清理历史 UNKNOWN 或生产队列。

## 权限与实际发行身份

`-1744` 是被动 Automation 检查要求用户授权的状态，不能据此推断 JavaScript 接口不支持，也不等于 `-1743` 的拒绝授权。新的诊断关联实际发送方签名身份、原 Edge 接收方签名与系统返回码；CLI/旧独立原型的授权状态不能移植到普通 App。

显式点击可请求一次 macOS 同意，但该次已拒绝的点击不会因授权后来获准而自动恢复。后台观察只检查原 session，不要求其前台，也不请求授权。浏览器自身 JavaScript 设置与 Automation、AX、登录是独立条件。没有修改 TCC、复制 Cookie/令牌、使用未公开上传接口或安装扩展。

`bash scripts/build-macos.sh --isolated-product-acceptance` 生成唯一的 `Riftlet Product Test.app`：固定独立 bundle ID 和隔离的 `Riftlet-Isolated-Product-Acceptance` 数据目录（后续运行保留该测试目录已有数据，不自动清空），附件策略与普通产品相同，登录项及自动更新关闭；不会覆盖普通 App 或旧内部候选。它是 ad-hoc 签名、未公证的工程包，不代表公开 Developer ID/Mac App Store 发行。旧 `--ordinary-acceptance` 的历史范围保持原样。正式商店权限结论仍待沙箱包验证。

## 与质量分支共存

只读核对了 PR #100 `b2291b97758413a5fa366040b1cf5db9c79faef0`、PR #101 `2048b32a7e7daf70c23f91576e335298a742c864`、PR #77 `d78baef554eed1a9cc66a2632e6322dff401c8de`。本轮按局部差异移入 #101 的正归属 picker 和发现截止时间修复、对应四个页面测试文件，并把同步读取总预算收紧到 150 ms，保留 #69 v18 原文档 witness。冻结 `chatgpt-web-observe-v17.js` 未改。

没有整文件覆盖或合并 #101。其 prepared-only 恢复、偏好原字节保护、媒体复检、历史只读投影及设置事务仍属于该分支，后续合并需保留这些成果。#77 安装引导未合并，公开 1.0.1 包及更新源保持不变。

## 验证范围

- 页面程序：141 项 Node 行为测试通过，含新 Edge 双输入、禁止借用预览 START、原草稿和 picker 归属回归。属于受控程序验证。
- 原生代码：本机完整 Riftlet 编译通过；本机只有 CLT，XCTest SDK 不可用。同源 Swift 断言运行器执行真实适配器对象、临时 SQLite、ImageIO PNG 和 JavaScriptCore realm，结果不冒充 XCTest runner。
- XCTest、ARM64/Intel、Chrome 原功能、打包及原生 WindowServer 双点击由 PR Actions 的精确合并对象执行。最终结论以对应作业和原始产物为准，不能用上述本地验证替代。
- 冷首击、快速连续点击、点击后切标签、Edge 无响应/退出、已有附件和选区保留的**商业草稿验收全部 NOT_RUN**；软件回归的同名场景不改变这个结论。

## 直接续工条件

独立工程继续提交、审查并运行 CI；无需账号权限的工作不因登录缺失而等待。商业验收需要账号持有人在已准备的隔离 Edge Profile 完成登录，并由系统为实际隔离 Riftlet App 授权。之后先采集原草稿的实际上传进展和完成证据，标定独立 Edge profile，再从普通微图入口用两张新系统截图执行全流程。保持原文、非空选区、原附件及未发送状态；未知结果只观察原操作。全部最终条件满足前保留 Draft，不合并、不发行。
