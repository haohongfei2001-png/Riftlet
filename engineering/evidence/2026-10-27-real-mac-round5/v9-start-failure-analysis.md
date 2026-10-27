# v9 两轮真实软件 AX 输入：最终成功，开始证据未取得

日期：2026-10-27。配套脱敏记录：[v9-start-failure-evidence.json](v9-start-failure-evidence.json)。两轮均使用生成图片、现有 helper 的单次 AXPress，以及只增加 synthetic AX identifier/enabled 元数据的临时 App。运行源码为 `1f9dec2dec9cf6ef61f36776a6e4f7c3439f4f8a`，页面程序为 `chatgpt-web-zh-20261027-integrated-v9`；没有启用 synthetic upload-start grant，也没有应用吞噬时序诊断 overlay。这里记录的是软件 AX 输入，**不是物理鼠标、人类操作或 v10 验收**。

## 直接可复核的两轮结果

| 项目 | 首轮 | 次轮 |
| --- | --- | --- |
| assetID | `029C66A3-178B-4184-8A0E-3060AA8C83C7` | `51847933-268A-4BCD-B708-2EB6FACBA5F0` |
| operationID | `239F2076-9DCB-4BE0-93E8-4D924CB6877F` | `06102CDE-BD1F-45EE-8091-C02C07F2381D` |
| attempt / inputCount | 1 / 1 | 1 / 1 |
| helper 动作 | 单次 AXPress 返回 success，前台 PID 未变 | 单次 AXPress 返回 success，前台 PID 未变 |
| App 原选择边界 | accessibility；已有 ACK 早于边界；freeze accepted | accessibility；已有 ACK 早于边界；freeze accepted |
| v9 页面开始证据 | start=null，startDisqualified=true | start=null，startDisqualified=true |
| 页面最终事实 | hasProof=true，无 error/invalid/uploading | hasProof=true，无 error/invalid/uploading |
| Core 最终事实 | verifiedReady；used / succeeded | verifiedReady；used / succeeded |
| 可见性退出原因 | swallowed / legacyCompletion | swallowed / legacyCompletion |

两图都是独立生成资产，内容 SHA256 同为 `494d7d015dc1a91073b356e1d6d64a546497aab37f8c47c4f82c630d7033f5bb`；不同 asset/op 没有被当成同一次点击。各自页面最终快照直接给出 inputCount=1，原生 trace 各有一个 begin 和一个 commit 完成记录。两个 Core receipt 的 operation/asset/attempt/hash 均与各自页面快照相符，完整 target 的规范 JSON 摘要也分别匹配 App selection 的 targetDigest。公开文件只保存 digest，不复制完整 target、会话/标签标识、页面地址、聊天、图片内容或本机路径。

两轮最终页面快照均报告 textPreserved、oldCardsPreserved，输入时 selectionPreserved；最终 editorFocused=true。因此本批不能额外宣称“始终未聚焦编辑器”的独立体验验收。helper 的 attachmentResultVerified=false 是正确边界：它只确认动作返回，最终附件证据来自页面原操作和 Core receipt。

## 根因：初始缺数值被永久取消资格

次轮在同一原操作上安装的只读 progress probe 记录了以下顺序；时间为该页面原 input 诊断后的相对毫秒，不与 native uptime 混减：

| 相对时间 | 原节点观察 | v9 状态 |
| --- | --- | --- |
| 0 ms | 输入已发生，inputCount=1，尚无 progress 节点 | 无 start |
| 13.6 ms | 唯一原 card / progress 节点出现，label 精确匹配，aria-valuenow 缺失 | startDisqualified 已为 true |
| 2207.2 ms | 同一原节点，hashVerified=true，值 4.5378966329499795 | 仍 disqualified，无 start |
| 2419.8 ms | 同一原节点，hashVerified=true，值增长为 9.075793265899959 | 仍 disqualified，无 start |
| 后续 | 同一节点继续到 100，随后节点移除；最终图片 proof 成立 | 最终成功仍未补造 start |

基线 v9 的 `Sources/RiftletAdapters/Resources/chatgpt-web-20261027.js:377–392` 将缺失 aria-valuenow 解析为 NaN，并在首次 `sampleStart` 置 `startDisqualified=true`；同函数入口第 382 行使所有以后样本直接返回。这样，即使原节点在哈希验证后发生合法数值增长，也无法再产生 uploadStart。第二轮上述原节点证据与源码路径直接对应。

缺失初值不等于回退、换节点或错误数值。可研究的最小修复方向是：仅允许原节点的初始缺值保持等待，首个有限数值只建基线，后续严格增长才申请开始证据；既有节点替换、已出现数值后丢值、回退、中间 mutation oldValue、身份/哈希/单输入等保护不能一并放宽。**本报告不宣称该修复或 v10 已经真机通过。** 首轮只有最终 start=null/disqualified 与成功快照，没有同样的初始进度 probe，不能把第二轮的缺初值时间线说成两轮都直接观察到。

开始证据与开始准入是两道独立门：本批 v9 没有产出候选 start；即使将来产出，App 的 start registry 仍需独立审查。最终 READY 成功不能倒填一次早于 READY 的 start，更不能把 legacyCompletion 记为快速吞噬通过。

## 时序与 AppKit 测量盲区

首轮从 helper AXAction 到 store 轮询看到 used/succeeded 的间隔约 10.143 秒；这是持久状态的**观察上界**，不是准确 commit、网络上传或动画耗时。页面最终 proof 相对其输入观察约 7.033 秒；次轮 proof 相对 progress probe 的 original_input 约 7.521 秒，两者起点不同，不作速度比较。

本批没有 swallowScheduled / swallowActualStart / swallowClose 遥测，不能通过 swallowed 状态、默认动画时长或截图推算实际 UI 退出时点。后续若已有真实开始证据获准，仅在临时 synthetic 构建启用独立 AppKit overlay，记录 snapshot commit 上界及真实代码边界；同步日志有测量开销，close 回调不是屏幕像素显示完成。若 hide/reflow/日志限额造成 close 缺失，不能补造完成。真实物理点击、同草稿未决时连续第二图、系统截图生产链路与 v10 均不由本报告关闭。

本次整理只新增本报告及配套 JSON；原始记录留在本地。JSON 列出九份来源的文件名与读取时字节快照哈希；仍在运行的 trace 后续追加会改变整文件哈希，不能把本次读取范围扩大为后来日志。所选原操作证据供本地审计关联，不公开原始私有 store/target。
