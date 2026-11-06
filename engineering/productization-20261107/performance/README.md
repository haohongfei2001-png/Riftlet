# 高分辨率收录、缓存、预览与持续运行

本专项补充旧 `NativeSoak.swift` 的 64×40 小图证据，不替换旧工具或改写原始结果。新增 [原生执行程序](../../../Tests/Readiness/NativeHighResolutionSoak.swift) 和 [有界 runner](../../../scripts/run-high-resolution-soak.sh)；产品 Core、Capture、UI 源码保持基线 `2e779f6` 不变。

## 实际执行范围

- 用 CoreGraphics/ImageIO 生成 3840×2160、2160×3840、5120×1440、7680×4320 四种真实像素尺寸 PNG。图案是有限线条和色块，不是随机巨型噪声，也不是用户截图。每次只生成一个大位图；原件和样本全部保留。
- 在新 `riftlet-hires-UUID` 根内，给合成文件添加截图元数据，走实际 `CaptureService` watcher、稳定性观察、`PrivateAssetImporter`、SQLite 和 journal。此处 `.production` 是 collector 要求的存储模式，目录仍完全隔离；不调用已安装 App。
- 初始建立 100 条历史、最多每批 10 张可见队列，逐文件检查同 source key 导入幂等；分页不丢失或重复 UUID。随后维持 10 张可见记录，持续阶段默认每 60 秒新写 4 张。
- 显式建立一个仅用于恢复测试的 UNKNOWN operation。它没有 adapter、浏览器调用、setter、网络或 START；重开 store 及全新探针进程恢复后，旧资产完整字段、UNKNOWN 完整 operation、全部七张表的 typed rows 和 schema 均须不变。
- 调用实际 `ThumbnailCache` 测量 128px 应用缓存 cold/warm；记录同步返回同一 CGImage 的 warm 命中。没有清空或控制操作系统文件缓存。
- 使用实际 `HistoryPreviewLoader` 和严格 `HistoryPreviewDecode`：四种尺寸各测 Retina Fit 和大 viewport。检查返回图像的真实 stride×height、像素数及文件 identity，受现有 64 MiB / 16,000,000 像素显示预算约束。
- collector 停止期间写 4 张、至少观察 400ms 未导入，再启动检查补收。只对自己的一个私有样本暂时改名，验证解码拒绝缺失文件，原样移回后恢复。全部原件、私有副本 SHA/尺寸在结束时逐项验证。

## 时钟、资源与安全边界

原生模块按 release 优化编译，仅增加 `-enable-testing` 供探针访问现有内部 API；harness 使用 `swiftc -O`。这不是完整 App 的运行或渲染性能测试。

持续时间从维护阶段开始按单调时钟实际计算，初始化、生成和基线测试另算。runner 给主进程“请求秒数 + 600 秒”的总上限，超时只终止自己持有的子进程并保留日志；后续同二进制的新进程恢复有独立 60 秒上限。持续阶段每 30 秒采样本进程 CPU 累计、RSS、峰值 RSS 和样本逻辑字节数。报告使用 CPU 首末差，不把进程累计值当区间增量。峰值 RSS 包含 8K 图像生成，不等同于产品常驻内存。

文件写入前按所有已预约原件和私有副本预留空间，连同固定数据库余量限制在 2 GiB 内。构建产物和日志不属于该“样本字节”指标。磁盘数值是逻辑文件字节，不是 APFS 实际分配或可释放空间。本工具没有模拟 ENOSPC，不能用配额检查冒充磁盘已满测试。

输出目录必须全新，运行根必须是 UUID 名称；重启入口还核对专用 marker。默认不接受已有 root，不删除失败样本。数据库复核只打开退出后复制出的 DB/WAL/SHM，避免改动原始证据。已知准备目录可复用二进制，但必须同时匹配 runner SHA 和全部相关产品/探针源码 SHA，不重复构建。

`file_write_to_durable_import_callback` 包含全部文件，包括 4 张故意在 collector 停止时写入的恢复样本；其最大值不能称作正常收录时延。`batch_first_write_to_durable_callbacks` 只统计正常运行中十张/四张批次，从首写开始到所有实际 durable callbacks。预览耗时包含核验读取、解码和回到调用线程，没有伪称纯 ImageIO 耗时。

本轮机器同时可能有 root 的 GUI 验收与发行容器检查，runner 会保存该并发背景；不能当作无干扰基准。没有创建 App 窗口、系统截图、网络请求或生产数据访问，不测微图可见延迟、点击动画、真实系统睡眠、完整 App 重启或上传吞吐。新进程恢复仅指这个实际模块探针。

## 运行与证据

在已有的私有证据父目录下选择不存在的输出目录：

```bash
scripts/run-high-resolution-soak.sh /private/new-smoke 0 100 60
RIFTLET_HIRES_CONCURRENT_WORK='Concurrent GUI/release checks; hardware not isolated' \
  scripts/run-high-resolution-soak.sh /private/new-hour 3600 100 60 /private/new-smoke
```

以上路径为示例。首轮保留 `build.log`、`harness-build.log`、实际模块/runner hash 和源码 hash。每轮保留 `process.json`、完整 runtime log、逐样本资源 JSONL、原图、完整资产记录、fresh-process report、七表 typed-row digest、全文件清单及 `runner-result.json`。

当前短跑结果与原始失败绑定见 [smoke-evidence.json](smoke-evidence.json)。首次短跑在创建 UNKNOWN fixture 时因使用 `.simulation` target 而触发实际 `.production` store 的 `modeMismatch`，原报告保留。修正的是测试 fixture：使用明确合成的浏览器 target，仅创建本地意图和 UNKNOWN，不执行外部输入；没有放宽产品模式隔离。

100 条初始历史的短跑通过，结束时有 104 条资产，全部媒体和原件相符；同一原生二进制在新进程完成恢复，七表 typed rows/schema 完全一致。持续分支另用短时钟验证。正式 3,600 秒结果只能在实际结束后记录；短跑不能标记为一小时稳定性通过。
