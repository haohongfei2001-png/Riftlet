# 离线存储检查、备份与恢复

`scripts/storage-recovery.py` 检查和保存一个 Riftlet 数据目录，并把已校验的备份恢复到**新建的空目录**。它不启动 Riftlet、不操作浏览器、不修改源数据库、不迁移 schema、不清理文件，也不把旧 UNKNOWN 改成可重试。

这是独立的维护工具，不是应用内自动备份或自动恢复功能。备份与恢复都需要明确的源和目标路径，没有生产目录默认值。Python 3.8+、标准库及 POSIX 文件锁即可运行；不需要联网、安装第三方包或访问钥匙串。

## 已核对的存储边界

本包按 main `b61fc46cf931bdbd14deec1b47d077e92db61e16` 的实际源码审计：

| 数据 | 现有实现 | 工具处理 |
| --- | --- | --- |
| `instance.lock` | [ApplicationInstanceOwnership](../Sources/RiftletApp/ApplicationInstanceOwnership.swift) 在启动数据库和 sidecar 前获取模式目录的独占 `flock`，直到进程退出 | 只读打开已存在的锁文件，非阻塞获取同一独占锁。锁被占用就退出，不停 App、不等待、不创建源锁文件 |
| `queue.sqlite` 及 `-wal/-shm/-journal` | [SQLiteDatabase](../Sources/RiftletCore/SQLiteDatabase.swift)：WAL、`synchronous=FULL`；保留 v1 至 v3 的迁移和派发槽，普通截图库在同一事务内升至 v4 | 全部按原始字节保存；SQLite 只打开临时副本。报告完整表行数、schema/行内容摘要、UNKNOWN sequence，绝不调用正式迁移器 |
| `assets/operations/checkpoints/metadata/compensations/upload_starts` 和其他表 | [QueueStore](../Sources/RiftletCore/QueueStore.swift) 保留历史、偏好、原操作与观察记录 | 不筛选状态，不只备份可见队列；包括 `sqlite_sequence`、未知表和未知列。所有行均参与逻辑摘要 |
| `media/`、`staging/`、`journal/` | [PrivateAssetImporter](../Sources/RiftletCapture/PrivateAssetImporter.swift)：持久 staging→manifest→media rename→DB insert；未完成导入不等于垃圾 | 全保留。检查每条已知图片元数据的文件名、长度、SHA-256；journal UUID 文件名大小写按原恢复契约接受；合法待恢复 staging 和无主片段分别提示，不提升、不采用、不删除 |
| `captures/`、配置 JSON、诊断及未知目录/文件 | 截图原始输出、独立设置与诊断 | 全部普通文件和空目录进入清单。配置只检查 JSON 可读性；不改默认、不解释未实现的字段、不清诊断 |
| `Feedback-v01/feedback.sqlite`、`feedback.lock` 及 sidecars | [FeedbackStore](../Sources/RiftletFeedback/FeedbackStore.swift)：独立 DELETE-journal SQLite、独立锁、v1 schema | 同时检查已有 Feedback 锁；完整保留草稿、报告、提交映射、凭据意图与其他表。不会 pump 网络队列或发送反馈 |

目录外还有以下状态，**不在这个目录备份内**：

- macOS 原始截图保存位置及其原文件；本工具只覆盖明确选择的数据目录内的文件。
- `UserDefaults` 中 `Riftlet.firstUse.presented.v1.<mode>` 和 `Riftlet.sourceAccess.v1.<mode>` 的首次展示标记、截图目录书签，见 [FirstUsePreferences](../Sources/RiftletApp/FirstUsePreferences.swift)。
- Feedback 钥匙串凭据、系统权限、Chrome 设置、其他模式目录，以及若启用相应原生适配器时位于外部稳定作用域的 clipboard coordination journal。
- 应用二进制、代码签名、系统账户和桌面/窗口状态。

因此，目录恢复不代表系统权限、书签或反馈凭据恢复完成，也不代表已经恢复成可运行的安装。工具不会读取这些外部域来补齐它们。

## 使用方式

下面都是命令示例。`--source` 和目标父目录必须真实存在；`--destination` 本身必须尚不存在。先正常退出拥有该源目录的 Riftlet。工具不会代替用户退出或重启应用。

```sh
python3 -B scripts/storage-recovery.py health \
  --source /absolute/path/to/offline-mode-root

python3 -B scripts/storage-recovery.py backup \
  --source /absolute/path/to/offline-mode-root \
  --destination /absolute/path/to/existing-backups/new-backup
```

将输出中的 `manifestSHA256` 单独记录，再校验备份：

```sh
python3 -B scripts/storage-recovery.py verify \
  --source /absolute/path/to/existing-backups/new-backup \
  --expected-manifest-sha256 <recorded-64-character-sha256>

python3 -B scripts/storage-recovery.py restore \
  --source /absolute/path/to/existing-backups/new-backup \
  --destination /absolute/path/to/existing-recovery-parent/new-recovery \
  --expected-manifest-sha256 <recorded-64-character-sha256>
```

恢复仅生成供核对的新目录，不自动替换正式数据根、不切换 App 数据路径、不启动任何进程。不要在恢复进行中把 App 指向这个目录。成功后先查看恢复报告、数据库与媒体健康结果、版本兼容性，再在另一个明确的集成步骤中决定如何使用它。

旧的离线副本可能没有 `instance.lock` 或 Feedback 锁。只有在输入已经是与运行中应用分离的副本时，才使用：

```sh
python3 -B scripts/storage-recovery.py health \
  --source /absolute/path/to/detached-old-copy --detached-source
```

`backup` 也接受 `--detached-source`。报告会明确记为 `detached-source-declaration`，而不是取得当前 App 离线锁的证明。它仍然拒绝任何**已被占用**的现有锁。这个选项不能把任意热拷贝变成一致备份，也不能补证原始拷贝发生时的完整性。

## 一致性、可追溯性与健康状态

备份期间持有现有的 App/Feedback 协作锁，防止相应 App 重新进入源目录；文件以 `O_NOFOLLOW` 及 descriptor-relative 路径逐个读取。复制后再次核对完整清单、字节摘要、inode/大小/mtime/ctime，拒绝本次观察到的非协作改写。它不是 APFS 或多进程通用事务快照；不宣称可以约束任意第三方进程。

SQLite **从不打开源文件**。检查先把数据库和全部既有 sidecar 复制到临时私有目录，SQLite 在那里读取 WAL，必要时恢复 hot rollback journal，并执行 `integrity_check`、`foreign_key_check`。临时检查文件可以发生恢复或 checkpoint；备份中的原始数据库、WAL、SHM 和回滚日志仍与源字节相同，不被规范化或移除。

备份目录结构：

```text
new-backup/
  capture.json       # 开始时间、capture ID、工具源码 SHA、运行时、离线锁证据
  data/              # 源目录全部普通文件和空目录
  manifest.json      # 文件长度/SHA、逻辑健康报告、明确的覆盖范围
  COMPLETE.json      # 最后写入并同步的完成标志，绑定 manifest SHA
```

中断或容量不足时，已经复制的数据原样保留；能够写入时再记录 `failure.json`。没有完整完成标志，或存在失败/额外控制文件的目录，不能通过 `verify`。不要把它当作完成备份，也不要为重试而清掉它；下一次选择另一个新目标即可。

成功恢复后会额外写入一个唯一命名的 `.storage-restore-<UUID>.json`，绑定原 manifest SHA、恢复时间、工具 SHA、数据清单摘要及健康结果。原数据没有被覆盖；这是新目标内唯一新增的成功收据。恢复失败时尽量写 `.storage-restore-failed-<UUID>.json`，保留不完整目标；不会继续在这个目标上补写或覆盖重试。

三个结果需要分别理解：

| 结果 | 意义 |
| --- | --- |
| `byteIntegrity: verified` | 文件清单、长度和字节摘要吻合；完整数据库表逻辑摘要与捕获时一致 |
| `health.status: ok` | 本工具已执行的 SQLite、引用文件长度/哈希和有限 JSON 检查没有发现错误；仍可能有明确列出的待恢复/未理解警告 |
| `health.status: attention` | 发现损坏、缺文件或不可读数据。备份仍可完整保存这些原始字节，恢复到新目录也可保留它们以便后续诊断；不能把它称为健康、可直接运行的数据 |

图片检查不解码像素，不代替原生 ImageIO 格式校验；配置检查不代替所有原生字段范围校验；未知 schema 保留并标注，不迁移或猜测其语义。反馈状态和 UNKNOWN 只是保留、计数与校验，不代表远端收到附件/反馈，更不产生再次输入的权限。

退出码：`0` 表示操作完成且已执行的健康检查未发现错误；`2` 表示操作完成但健康状态需要处理；`1` 表示拒绝执行、校验失败或未完成。`2` 不会为了制造成功而修复或隐藏错误。输出为 JSON，失败摘要写 stderr。

自带 checksum 只能发现未同时重写清单的变化，不是数字签名。使用单独保管的 `--expected-manifest-sha256`，才能核对这个包是否仍是先前记录的清单；仍不由此证明 App 版本、备份来源授权或密码学签发身份。

## 路径和数据保护

- 新目标原子创建，已存在的目标即便为空也拒绝；源与目标不能相同、互为祖先或后代。
- 拒绝路径穿越、重复/冲突清单项、缺失父目录、符号链接及 FIFO/socket/device 等非普通文件；包括输入、输出路径中的符号链接祖先。macOS 上 `/tmp`、`/var` 可能是系统链接，需要使用实际路径，如 `/private/tmp`。
- 所有输出目录为 `0700`，普通文件为 `0600`；文件和目录完成相应 `fsync`。保存的是文件字节和空目录，不复制 ACL、扩展属性、资源分支、原权限或所有权，不能代替系统级备份。
- 整个备份含截图、Feedback 草稿和其他私有数据。保持私有，不提交到 Git、公有 Issue 或公共云路径；工具不上传任何内容。摘要报告不打印图片、聊天文本、Feedback 正文或原始数据库行。
- 所有删除仅限工具自建的临时 SQLite 检查副本生命周期；不删除源数据、损坏文件、旧记录、UNKNOWN、部分备份或恢复目标。

## 隔离回归

```sh
python3 -B -m unittest discover -s Tests/StorageReadiness -v
```

测试只创建临时合成目录。覆盖完整目录往返、UNKNOWN `1/8/14` 与所有历史表/Feedback 保留、真实 WAL 已提交行、子进程 `os._exit` 留下的 hot rollback journal、v1/v2/未来 schema 不迁移、大小写 UUID journal、部分导入及无主 staging、损坏/缺媒体、锁冲突、路径和清单攻击、磁盘不足、源变化、恢复中断和 CLI 退出码。

这些是隔离的文件系统与 SQLite 验证，不是生产数据恢复演练、硬件断电实验、磁盘损坏修复成功或正式 App 数据切换验收。当前工具也不修改既有 Swift 的 migration/recovery 测试及实现。
