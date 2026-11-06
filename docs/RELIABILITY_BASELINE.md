# 可靠性与性能基线 — 2026-11-06

本轮不改已验证的文件输入架构。三个不同层面的证据分别保存：个人Beta既有真实聊天记录、本轮隔离原生文件/SQLite/进程验证、本轮本地受控Chrome。不存在新的私人聊天上传或自动发送。

## 复验入口

```sh
node Tests/WebPageProgram/acceptance-program.test.cjs
node Tests/WebPageProgram/legacy-web-observe.test.cjs
RIFTLET_REQUIRE_CHROME=1 node --test Tests/WebPageProgram/chrome-input-resource.test.cjs
bash scripts/run-readiness-ownership.sh
bash scripts/run-readiness-soak.sh
RIFTLET_SOAK_CAPTURES=1200 RIFTLET_SOAK_INTERVAL_MS=500 bash scripts/run-readiness-soak.sh
```

浏览器脚本原有实现即以 `--headless=new`、临时profile、loopback-only服务运行，不连接真实ChatGPT或用户profile、不用CDP/Apple Events、不创建可见Chrome窗口。跨标签焦点用例需要完整Chrome的headless模式；本机headless-shell在该断言上失败，保留失败日志。完整Chrome同组和全套通过，没有改断言或产品代码。

原生soak从真实源码编译Core/Capture，生成小PNG和系统截图元数据到独立临时目录。验证160图的四次40图burst、暂停收录器期间到达的文件、重启不重复，持续收录/重复通知/每8图清空可见队列/每40图重开SQLite和恢复journal/保留第一条UNKNOWN/最后逐文件字节核对。默认160张，扩展1,200张以500ms间隔持续约十分钟。它不启动产品UI，不连接浏览器；不把生成小图结果当大截图或整机长期可靠性证明。

单实例探针直接编译实际 `ApplicationInstanceOwnership.swift`，12次独立子进程生命周期验证正常退出、终止时保持锁、SIGTERM、SIGKILL后锁释放与历史保留。它不是完整App的强杀/重启视觉验收。

`sample-process-resources.py --pid <已核对PID> --output <新文件>`只读采样已运行进程，核对进程创建时间和程序身份，不启动/停止程序、不读App数据。系统负载和用户活动不受控，报告不能称严格空闲CPU或内存泄漏认证。

## 覆盖和真实边界

| 场景 | 使用已有覆盖/本轮补充 | 范围 |
|---|---|---|
| 1/2/3/5张、START后新图、旧UNKNOWN | 原生Chrome输入资源、IndependentAttachmentLifecycle、AcceptedAttachmentHistoryIsolation | 原生浏览器primitive+受控应用/本地SQLite；历史个人Beta真实五图另列 |
| picker重建、隐藏/动态菜单、未聚焦、标签切换、正文/选区/旧附件、错误目标、无重复/发送 | 既有 `chrome-input-resource.test.cjs` 与 page VM | 本地控制页面，不代表ChatGPT所有版本 |
| source目录变更/拒绝/暂不可用/恢复 | CaptureSourceBinding、ReleaseCapture、CapturePreferenceObservation | 原生临时文件+注入状态，不改生产截图位置 |
| 容量不足/持久边界中断 | ImportFault、ReleaseCapture + StorageReadiness | 真SQLite写锁/hot journal、确定性ENOSPC注入；不是填满用户磁盘 |
| v1/v2迁移、UNKNOWN/receipt恢复 | LifecycleMigration、ChromeSessionMigration、RecoveryBoundary | 隔离DB；不运行生产迁移 |
| wake/浏览器会话变化 | TargetArmPermissionWake、ChromeActivityInvalidation、PassivePermissionResume | 状态/时序回归；不是让用户Mac实际睡眠或退出其Chrome |
| 显示器断开/重接/Spaces | RiftReconfiguration及既有几何测试 | 模型/布局回归；物理热插拔/Spaces外部验收保留 |
| 退出、重启、重复启动 | 原有单实例测试 + 新12次子进程探针 + soak重开 | 核心锁/存储；完整AppUI长期会话仍单独验收 |

完整Swift XCTest由现有macOS CI执行。本机CommandLineTools 6.4缺XCTest，两个本地build-system尝试都在测试加载前失败并保留日志；没有称XCTest通过。可执行原生探针和产品build继续独立完成。

## 计时如何解释

- `stable_file_to_durable_asset`：已完整生成且稳定的文件到正式importer返回；**不含**collector稳定窗口、UI展示或网络。
- `batch_first_write_to_40_collected`：从该批首次文件写入前到40张全部进入资产表，包含文件生成、稳定等待和重启启动；不是微图像素展示。初次及1,200长跑中的旧`burst_40_to_collected`起点在生成和service.start完成之后，只能表示剩余rescan收敛时间，不能当完整收录延迟。两种记录不混合统计。
- `visible_queue_after_history_growth`：已有历史增长时可见队列SQL读取。
- `history_page_40`：40条历史状态的事务读取；本轮small PNG/数千记录不能外推无限历史。
- `READINESS_RESOURCE`：测试进程自身RSS、峰值RSS和进程累计CPU（旧字段cpuSeconds，修正名称processCPUSeconds）；并非安装App的UI/Web进程占用。CPU比例只能使用同一采样区间首末CPU差分除以elapsed差分，不能拿进程累计量除以第二阶段时长。

既有最终冷启动双图记录的重新计算见 `engineering/autonomous-readiness-20261106/evidence/accepted-beta-timing-summary.json`：点击到收到setter/change/START观察报告约367.47/195.42ms，报告到吞噬开始约11.55/4.63ms，点击到吞噬开始约379.01/200.05ms。第一张缺少swallowClose事件，不能补造；两张样本不是P95。START是聊天开始接收，不是服务器READY，不把网络传输时间计为Riftlet执行时间。

文件产生到真实微图像素、精确setter时刻、物理队列补位及长期生产运行仍没有本轮完整测量。保留这些具体缺口，不用更多合成PASS替代实际观察。最终跑完的统计、原始日志hash和CI身份在工程索引EVIDENCE中记录。
