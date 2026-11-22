# 1.0.8 实现

基线为 #123 的 f126a211，已核对与签名 build 56 的产品源码 2717fa6a 相同。1.0.8 最终候选为 build 58，产品提交 c7ef1027。本轮沿用 TransferCoordinator、QueueStore、PNG 导入、原卡回执和明确失败恢复。

| 位置 | 行为 |
|---|---|
| RiftletMain、ChromeActivityObserver、TargetArmScheduler | 截图入队、浏览器激活、窗口变化和托盘靠近提供准备机会。单次在途任务合并重复通知。环境变化使上一代结果退休。 |
| BrowserSigningIdentity、ChromeProcessIdentity | 校验运行进程的内核出生时间、可执行路径、应用路径、Apple 签名要求、浏览器 bundle 和厂商 Team ID。品牌显示名不参与真正的输入选择。 |
| PreClickLeasePool、ChromeAppleEventsExecutor | 在同一草稿保留至多两个独立的完整 ACK。冻结比较 macOS 同一时间基准上的 ACK 和原始 NSEvent。begin 和 commit 认领相同原目标、operation、invocation。 |
| 页面程序、EdgeExecutionWorldWitness | 直接持有原 Document、editor、附件输入或所属附件入口。显式 release 只释放未消费的原凭据；renew 仅延长尚存的同一对象。Edge 的独立执行环境与该凭据共同保留。 |
| MainWorldCommandRelay、ArchivedObservationCompatibility | 旧版页面指纹只用于在原标签上查找 build 56 或 57 的原操作。发现与执行时均须唯一匹配，历史读取限于原身份和原调用的 observe。 |
| ApplicationInstanceOwnership、退出交接 | 资料根目录和其下排他锁的内核身份共同确定资料库范围。接替同一个锁的进程获得严格递增的代际。正常退出在 AppKit 事件循环中等待有限时间，后继进程只可回收同一资料库死去前任尚未进入投递的原凭据。 |
| 独立 QA 资料目录 | 同一 App 同一普通附件路径可限定为一组私有资料、一个已核实进程和一个临时聊天标签。使用独立截图来源、队列、偏好和本地反馈；普通安装入口继续沿用既有资料。 |

原截图的清理与保留仍由原有策略管理。新版本不建立历史 UNKNOWN 的输入凭据。调试记录仅在显式启用时写入私有目录，记录阶段、随机身份和计时，不记录对话内容、Cookie 或图片。
