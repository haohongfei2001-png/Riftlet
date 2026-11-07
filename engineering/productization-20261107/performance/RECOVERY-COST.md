# 历史媒体恢复成本与有限修复对照

候选 `b1fa4329d66dcd632291c4d8bb7b18b5ec5ffbbc` 在同一份 340 条合成历史的独立副本上，实际 importer 恢复由 **11,764ms 降至 158ms**；包含第二次恢复及目录扫描的 `CaptureService.start` 由 **10,722ms 降至 116ms**。前后使用相同探针源代码，全部七张表的 typed rows、schema、完整 UNKNOWN、340 份媒体和 340 份 journal 均保持一致。精确来源、数值及私有原件 hash 见 [recovery-comparison-evidence.json](recovery-comparison-evidence.json)。

## 原始长尾及计时范围

[原一小时报告](long-run-evidence.json) 的 12 次重开不是固定 340 条记录的重复：实际数量依次为 100、124、144、164、184、204、224、244、264、284、304、324。中位 7.60 秒，最大 25.61 秒发生在 284 条时；结束后的独立新进程在 340 条上恢复用时 10.48 秒。这些旧结果及对应源码、二进制保持原样。

`NativeHighResolutionSoak.reopenPreservingUnknown` 在停止 collector、清掉旧引用之后才开始计时，包含 `QueueStore.init`、`recoverInterruptedOperations` 和实际 `CaptureService.start`，没有把固定睡眠计入其中。`CaptureService` 是 actor；恢复完成后才结束初始化并扫描来源目录。已知 source key 不进入新文件稳定性等待。

普通 App 源码启动路径先调用 importer 恢复，后续 collector 启动又恢复一次；菜单和设置入口在 await 启动前已经安装。这里确认的是源码调用链，不是实测完整 App 启动时间，不能将 CLI 最大值乘二当作用户等待时间。

原冷缩略图最大 2,404ms 是 284 条那一轮第 2 个可见请求，合成记录序号 276，尺寸 7680×4320。每轮新建 `ThumbnailCache`，冷请求后立即检查应用缓存 warm 命中；未控制系统文件缓存。解码在 utility 队列，主队列负责缓存和回调；指标从请求到回调，不能当作主线程解码冻结。没有逐请求精确 UTC，未将这次长尾归因于某个并发进程，也没有通过恢复优化宣称已修复缩略图长尾。

## 实际分解与最小改动

旧源码对 existing row 与完整 journal 一致、私有媒体存在的记录先检查尺寸、完整 SHA，再执行 `ValidatedImage.inspect`。除了 `used`，已移出队列的记录和 UNKNOWN 也走这条路径。固定语料包含 pending 339、UNKNOWN 1，removed 330、visible 10；四种分辨率各 85 张。

在两次实际恢复之后，探针另外做一次较暖的逐项分解，总计 10,120.781ms：

| 原语 | 340 条合计 |
| --- | ---: |
| journal 读取和 JSON 解码 | 59.903ms |
| store 查找，包含 actor 切换 | 16.210ms |
| 私有文件 signature | 6.635ms |
| 全文件 SHA-256 | 77.006ms |
| `ValidatedImage.inspect` | 9,952.576ms |

最后一项占分解总时长 **98.34%**，包含格式、帧数、完整性、尺寸及当前限额检查，以及强制 64px 像素解码；不是纯 decoder 计时。8K 的 85 张在这项内合计 5,618ms。各原语之和与总墙钟之间仍有循环、条件和记录开销。

候选只改两个 Capture 文件：已提交记录与完整 journal tuple 一致后，仍检查尺寸、每个字节的 SHA、全部共享元数据和当前限额；省去已验证且内容相同媒体的重复 64px 解码。元数据检查结束后再次读取路径 signature，与哈希前的 signature 比较，拒绝期间原子替换。新导入、staging、未提交 journal 的收养仍执行原完整解码。没有 mtime 缓存、跳过哈希、改 UNKNOWN、清理媒体或数据库迁移。

## 同探针前后结果

两个进程依次运行，各自复制同一份已完成小时语料，使用完全相同的私有 `RecoveryPrimitiveProbe.swift`（SHA-256 `0f838dc7cccc40bfbf6c1c144e75488256cdb3c3b361ea72b7ebbcd36be6d051`）。候选重用已完成的 release `-enable-testing` Core/Capture 模块，重新链接探针；全部产品输入、26 个对象和模块文件与候选构建身份逐项一致，没有重复构建 App。

| 实际步骤 | 旧产品源 `2e779f6` | 候选 `b1fa432` |
| --- | ---: | ---: |
| 第一次 `PrivateAssetImporter.recover` | 11,764.494ms | 157.682ms |
| `CaptureService.start`，含第二次恢复和扫描 | 10,722.304ms | 115.823ms |
| 已知来源单独 rescan | 5.411ms | 6.378ms |
| 后续全 `inspect` 分解控制项 | 9,952.576ms | 10,996.150ms |

恢复步骤分别约快 74.6 倍、92.6 倍，仅适用于这个固定语料及测量边界。未修改的完整 `inspect` 控制项仍耗时约 10 秒，支持收益来自恢复路径省去重复像素解码；不能将它概括成全部解码或全部 App 操作变快。

原小时语料 1,034 个文件在两次探针后分别重新校验，hash、尺寸、模式全部相同。数据库只在额外临时副本上读取；original、before、after 全七表 typed rows 和 schema 相等。assets 340、operations 1、upload_starts 0；原 UNKNOWN 整行未变，导入回调为 0。

这是按先后顺序运行的两个新副本，不是随机顺序或独占硬件基准。复制和 hash 检查会预热文件缓存，未清空系统缓存。CLI MainActor 心跳只观察这个命令行进程的调度，不证明 AppKit 可见响应。没有 App 窗口、已安装 App、真实截图、生产数据、浏览器或网络；没有重跑一小时，也不据此宣称 UI 或数周稳定性通过。

## 失败保留及复验

第一版私有分解探针编译失败：`CaptureService` 参数顺序错误，并有 async 上下文使用 `Thread.isMainThread` 的警告。该次没有运行原生探针，不能算产品恢复失败或通过。只修探针参数顺序及线程观测 API 后，第二次才得到旧产品基线，第三次得到候选对照；三次原件和 hash 均保留。候选的本机完整 `swift test` 因 CLT 无 XCTest 模块未执行，不把本 CLI 结果等同 XCTest 或正式 macOS CI。

私有探针用于本次有限诊断，不引入第二套公开测试框架。已有高分辨率 runner 可以在含候选的 checkout 上用新输出目录复验实际收录、恢复、预览和数据不变量：

```bash
scripts/run-high-resolution-soak.sh /private/new-candidate-smoke 0 100 60
```

这条命令会新建合成语料，不是复用本报告固定 340 条的精确计时。更长持续运行仍可按 runner 参数显式请求；本次没有为重复确认而再跑一小时。复用旧 prepared build 会因产品源码 hash 不同被拒绝，应先对候选新建一次准备目录。私有分解探针源码、前后报告、构建和数据证明的准确 hash 均在公开 JSON 中；原始文件不入仓，公开投影不含用户路径。
