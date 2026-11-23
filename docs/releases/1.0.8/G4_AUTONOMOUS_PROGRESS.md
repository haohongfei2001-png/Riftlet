# G4 恢复与发行进度

## 2026-11-23 · 签名候选的原生提交回执

非作者重新读取 build 61 的 11 份既有浏览器运行记录。Edge 共记录 40 次成功的 `captureTarget`，其中原 G4 专窗有 5 次。冻结的 Edge 代码只有在原生提交后通过执行世界确认和后续校验，且收到原命令回执，才记录成功。日志单独保留的一个反例在完成世界确认后收到了 `CLICK_PIN_REFUSED`。Chrome 的中图亦有对应的 commit 回执、一次 input 和一条持久 START。两款浏览器的实站记录都缺少原 PNG 对应的 PUT 对象及终态。世界确认属于代码与实测事件联合推定，日志没有单独保存浏览器的执行环境编号或确认字符串。[原始运行逐事件独立审计](evidence/build61/recorded-product-command-review.json)

## 2026-11-23 · Build 61 执行世界核验

两款浏览器分别在自有本地文件页验证了同一底层 DOM 节点能被两个 JavaScript 环境读取。两边各自创建的 XHR 使用各自的原型。页面预置的固定链接在原页面环境执行。替换页面自己的无行为标记后，旧标记校验立即失败；重载后，原文档身份和隔离环境均失效。每款浏览器的测试标签都记录到零 HTTP 请求。非作者另核对了冻结源码的七个指定入口及其回执范围。[双浏览器回执](../../../Tests/PreClickLease/g4/main-world-observer/receipt.json) · [冻结源码审计](evidence/build61/world-source-and-history.json)

已将上轮 Chrome 验收器源码、二进制指纹与实站运行清单对齐。它只采集精确文件创建端点的 Resource Timing，输入前为零条，随后为一条 HTTP 200。原 PNG 在 input、change 的两次哈希都一致。实际 PUT 的请求体、进度和终态均未采集。本轮没有重新投递原图。[原验收器覆盖范围](evidence/build61/recorded-observer-coverage.json)

另在普通 Chrome 和 Edge 上各创建一扇有创建回执的本地 QA 窗。Apple Events 连续两次读取原文档，两款浏览器都只在页面自有 XHR 上看到原型标记。两个新窗均已关闭，各自原窗口集合已复核。实站中断和原图显式重选仍为零。恢复测试需要先把真实 PUT 的完整请求体、进度和终态归属到本次原图；发布还需 G4-C 以及 G4-A 或经独立认可的 G4-B。[原生测试与历史运行分项回执](evidence/build61/world-local-native.json) · [本轮非作者裁决](evidence/build61/world-independent-verdict.json)

## 2026-11-23 · Build 61 中等大小截图

新系统截图为 7,921,752 字节。普通 Chrome 的隔离回环用例先完整上传并取得 HTTP 201，再在独立请求的 17.9936% 进度中止一次。非作者从私有原图和收件服务记录重算了整图及实际读到的前缀。此项完成了工作包 A 的回环对照。当前实站放行条件仍为 G4-C，加 G4-A 或经独立书面认可的 G4-B。[本轮原图与网络审计](evidence/build61/medium-loopback-independent.json) · [G4 最终验收](G4_FINAL_ACCEPTANCE.md)

首笔显式重选提交时，build 61 才将现场数据库从 v4 升至 v7。两个快照核验命令现可核对这个过渡及已在 v7 上继续的重选，逐项比对原操作、原调用、原 START、补偿记录及新旧卡身份。14 项针对性测试通过。非作者以真实表结构和独立数据运行了 22 项命令行对照，并重算三组既有的受控恢复归档。实站故障及重选的两份快照另须从同一次现场恢复取得。[非作者 SQLite 工具复核](evidence/build61/recovery-snapshot-verifier-independent.json)

Edge 在首批目录扫描把新截图收入启动基线，验收器在产品输入前停止。修正后的准备先验证初始清单为空，随后在普通 Chrome 的新 QA 草稿取得一次真实点击、一次完整的原图输入和一条晚到的 START。原卡可见，操作 history 为 UNKNOWN。精确文件创建端点在该草稿新增一条 HTTP 200 的 fetch。实际 PUT 的归属和状态尚缺。[实站回执](evidence/build61/medium-chrome-normal.json)

收尾时网页还返回了原 File 和预览的全幅 RGBA。两者尺寸与中心像素相同，完整像素摘要不同；原 PNG 交付字节一致。Chrome 的原卡及原草稿已保留，本轮的两个产品进程和两个网页观察器已退出。[实站像素与独立裁决](G4_FINAL_ACCEPTANCE.md) · [清理凭据](evidence/build61/medium-site-cleanup.json)

非作者逐项验证 263 个归档载荷、内嵌清单、8 个主文件及 17 个补充文件。G4-C 的实站中断和知情重选仍缺证据，G4-A 的具名错误和 G4-B 的上游拒绝也未成立。正式 PR #125 保持 Draft，公开 stable feed 返回 1.0.5（31）。[本轮独立发行裁决](evidence/build61/medium-final-g4-independent.json) · [公开更新源](https://riftlet.com/updates/stable.xml)

## 2026-11-23 · 起点

PR #124 仍为 Draft，提交 `1c83ca91e6dd26cb064627adc59167fdccb6a38c`。Issue #120 打开。main 为 `9fd8ad15fca043915069904113e5fb67d82b4948`。冻结 build 59 的双架构 CI 成功，公开版本为 1.0.5（31）。[既有同包报告](RIFTLET_1.0.8_FINAL_RELEASE_REPORT.md)

| 路径 | 现有证据 | 未完成的验收 |
| --- | --- | --- |
| G4-A · 网站原卡失败 | 三种客户端故障均保留原文件和原操作；没有取得具名错误卡。 | 原卡错误、带错误收据的 UNKNOWN、知情重选、唯一新 START。 |
| G4-B · 服务器拒绝并移除原卡 | 已有正常上传返回 HTTP 201；故障轮记录的是客户端取消。 | 原 PNG 对应的服务器真实 4xx、原卡行为、新旧操作和独立等价性裁决。 |
| G4-C · 上传结果未知 | 三个真实 UNKNOWN 的私有备份存在，原有 QA 标签均已关闭。历史库可核对字节和账本；原标签关闭后无法恢复同一 Document。 | 审计原产品入口、重复附件保护和原草稿身份。以新鲜且可持续观察的原始草稿验证明确重新选择。 |

本轮同时开展页面状态机审计、独立 HTTP 对照、产品恢复路径检查。真实服务响应只采信可归属到本次文件且来自服务端的记录。签名链接、私有画像、原图及数据库仅保存在私有验收存档。

## 2026-11-23 · build 60 产品恢复复核

build 59 的截图仓库允许在其他草稿再次附加，显式重选还会修改旧操作行。build 60 实现原草稿复核、提前显示重复风险和独立后继操作。受控浏览器已验证旧卡重新出现或旧附件被替换时拒绝输入，SQLite 对照覆盖先恢复原 head 再重新选择。复核还发现两个边界：已在输入前退休的后继占用一个 attempt，旧 head 被恢复后又可能收到迟来的写入。只有最终修正过的源码才能用于签名包和双架构验收。中间检查点未进入实站或正式发行。[恢复状态机](G4_PROTOCOL_AND_STATE_MACHINE.md)

## 2026-11-23 · 同包核验与现场

最终产品源码为 `711cee3a1c7033ce4925082a83099b00da7087c6`。独立源码审查、v4→v7 真实历史副本验证、双架构 CI、私有签名公证、staple、Gatekeeper 和独立安装均已完成。两款普通浏览器分别经过独立专窗与多种普通呈现方式检查。最终签名包的现场文件输入数为零，G1/G2 的首图、双图与选区及 G4 三条恢复路径均未取得同包实站通过。已识别的恢复条件为可证明是原始目标的已登录、前台、可见浏览器会话。[发行报告与当前放行条件](RIFTLET_1.0.8_FINAL_RELEASE_REPORT.md)
