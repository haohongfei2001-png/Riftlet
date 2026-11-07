# 有限测试卷上的真实空间不足与恢复

本专项用独立 128 MiB HFS+ 稀疏映像验证实际本地写入失败，不向主磁盘写满文件，不读取生产数据，不启动 App 或 GUI。它补充现有容量 seam 单元测试；HFS+ 测试卷不代表已验证生产 APFS 的全部行为，也不是断电测试。

[runner](../../../scripts/run-disk-full-recovery.sh) 只接受新的输出目录。它核对 `hdiutil` plist 中的映像、设备和挂载点，再核对 `diskutil` 的设备、挂载点、文件系统和容量，记录系统返回的 VolumeUUID。挂载使用 `-nobrowse -noautoopen`。原生程序再次核验 marker、设备号与容量（最大 256 MiB），拒绝在证据所在主卷填充文件。所有原件、私有副本、journal、数据库、日志及映像保留。

[原生程序](../../../Tests/Readiness/NativeDiskFullRecovery.swift) 分开记录三种结果：

1. 专属 filler 的实际 `write` 返回 `ENOSPC` 后，正常 importer 以真实 `copyBytes + 4 MiB` 预检拒绝新复制。这是容量保护，不冒称产品写入发生了 `ENOSPC`。
2. 通过已有测试边界 `stageOpened`，在正常容量预检通过后填满同一测试卷，再让未改动的产品 `writeAll` 执行。只有实际取得 `CaptureError.io(..., ENOSPC)` 才通过中途写满用例；hook 本身不伪造 errno。
3. 通过已有 `mediaSynced` 边界，在 durable journal 和私有副本完成后填满卷，再由真实 `QueueStore.importAsset` 尝试提交。提前对自身数据库正常 checkpoint/truncate WAL，确保提交需要真实新增空间。只报告实际捕获的 `RiftletError.database` 文本；当前产品类型不暴露 SQLite 数值错误码，因此不声称已直接采集 `SQLITE_FULL=13`。

每次失败后读取同一一致 SQLite snapshot，比较全部表的带类型完整单元格及 schema；逐字节核验原件、既有 media/journal，保留原 UNKNOWN。只移除以 `O_EXCL` 创建、设备号/inode/所有者仍相符的专属 `disposable-filler-UUID.bin`，然后对原输入进行明确重试。数据库失败的 journal 必须复用原私有副本，不能生成重复资产。测试不执行浏览器、上传、START 或 UNKNOWN 重传。

runner 保留卷内文件清单和可直接读取的数据副本。额外 SQLite 校验只打开另一份副本，以免 SHM 访问改变保留副本。最后仅以刚核验的自身映像设备执行普通 detach；失败明确标记 `OWNED_MOUNT_REMAINS_OR_IDENTITY_UNCONFIRMED`，不能被原生用例 PASS 掩盖，也不使用 force detach。

源码、脚本、`Package.swift` 和 CSQLite 输入在构建前后必须一致；真实 Core/Capture release 模块仅增加测试符号。主原生进程有 180 秒上限，超时只结束自己持有的子进程并保存失败证据。

## 实际结果及保留的失败

[disk-full-evidence.json](disk-full-evidence.json) 记录最终 run-04 的 5 项真实原生验证通过，原生运行 1.69 秒、正常退出和 detach 均为 0。三次填充都逐级从 1 MiB 降至 64 KiB、4 KiB、1 字节，最终取得实际 `ENOSPC` 和可用空间 0，并记录每次写入次数及错误；产品复制本身也确实返回 `write-private-data/ENOSPC`。

数据库阶段实际返回 `database or disk is full`，失败前后七表 typed rows/schema 不变，原 durable journal/media 保留。释放唯一可丢弃的 filler 后，一次明确重试复用原私有副本，最终 4 条资产、1 条原 UNKNOWN、0 START，无重复；原两条资产完整行、所有其他历史表、原件和旧媒体保持一致。测试卷正常卸载，映像和原件均保存。产品 SQLite 错误类型没有数值码，因此这里只记录实际文本，不声称直接捕获了数值 13。

前三次整体 FAIL 均保留：

- run-01：当前系统的 `diskutil` plist 没有 `Mounted` 字段，探针未启动；修正该测试 schema 假设后仍保留设备、挂载点和实际 mount 核验。
- run-02：1 MiB 写入返回 `ENOSPC`，但小 PNG 正常导入。失败映像只读检查证实尚余 835,584 字节，前后映像 hash 相同；因此修正填充粒度，没有把成功导入误报为产品故障。
- run-03：真实预检、产品中途 `ENOSPC` 和一次明确恢复已通过，但 checkpoint helper 返回 OK 后 WAL 未截断，SQL 产品阶段未运行。新 DB 副本复现了新连接的 `nLog/nCkpt=-1`，只读 schema 后才能取得 `0/0` 与零字节 WAL。最终 helper 因此先读取 schema、指定 `main`，并保存和检查全部返回值。

SQLite 的 [checkpoint API 说明](https://www.sqlite.org/c3ref/wal_checkpoint_v2.html) 区分了 `SQLITE_OK` 与实际 WAL checkpoint 结果；本轮“新连接尚未初始化 WAL 状态”的归因还来自同一连接上的真实对照，不能只靠返回 OK 推断已完成。以上修正只属于探针，没有改 Core、跳过完整性验证或改变 UNKNOWN。

```bash
scripts/run-disk-full-recovery.sh /private/new-disk-full-evidence
```
