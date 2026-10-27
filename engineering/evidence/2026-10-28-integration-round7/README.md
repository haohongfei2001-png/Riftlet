# 第七轮正式集成：原点击顺序等待与透明区域防误选

2026-10-28（北京时间）。唯一正式工程仍为 `codex/engineering-foundation-20261027` / [Draft PR #1](https://github.com/haohongfei2001-png/Riftlet/pull/1)。本轮实际合流、修复、测试、非作者审查；没有重新开发顺序调度，没有访问本地 Codex 的 Mac，没有合并 main、发布、修改网站/设计或启用生产上传/重试。

## 不可变来源与历史

| 项目 | 精确提交与范围 |
| --- | --- |
| 正式基础 | `e3175f30fb9b92cd12a7c670febbbe3296657da1` |
| 第七轮继承合流 | `336ecce8714981d967f50fcdaf62de44f0979660`；Sources/Tests/Resources/Package/scripts 与正式第六轮81b6a61相同 |
| 真实双图、冷边界运行源码 | `f6417c6faaf8aa21ac587b07f25ea2a159af021f`；完整App、无临时overlay |
| 最终来源源码与GUI复测 | `9de6a85b0161713833dc25e3b3eb1e1a2f81a558` |
| 固定原始证据交接 | `3b089b22449742fe7d9a76e74aa7ac99be37ba8e` |
| 正式历史合流 | `2aaaadb1c3461f93f268f1f93b0b08854745aa5f`，双亲e3175f3 / 3b089b2 |
| 追加权限接收进程保护、最终测试源码 | **`595142d0345adc0d06f54371f50406879310610d`** |

GitHub读取和fetch时第七轮分支仍为固定交接；未观察到更新的已推送工作，不能据此判断本地未推送状态。本会话不写其分支。两个共同祖先为caa6a65 / 65f7d54；保留继承merge及两项源码、一项证据提交，没有重新cherry-pick第五、六轮。唯一文本冲突在INTEGRATION_HANDOFF，已保留双方来源并增加当前状态。

全部15份原始证据与3b089b2逐字节/hash/blob一致，目录tree为 `6d9a155348cce46014ad407d6d3bda04ed5ed214`。之前15个证据目录未变；v12 Adapters、Capture、schema/Models/ReceiptPolicy、PassivePermissionResume、Web验收策略、资源、打包、设计和研究等16个对象与正式基础一致。完整清单见[verification.json](verification.json)。

## 实际代码与修复

- Core接入原 `AcceptedSelection`、有界prepared等待、实际到期取消、精确token收尾、丢唤醒补偿和原SQLite最终intent门。token不持久化，旧UNKNOWN与跨profile锁不放宽；同图无intent取消后允许新的真实点击。
- App在任何异步权限之前同步分配原点击ordinal，仅按序提交既有Coordinator。保留原target/ACK/epoch/revision；权限按实际原Chrome进程检查，不缓存grant。旧异步结束不能释放新选择。
- 启动先做本地恢复与原ID快照；首轮预绑定**尝试结束**后才做旧ID远程只读恢复，不再reset新prepared。真实样本中首ACK先于观察，但源码不保证首尝试一定成功发布ACK。
- UI仅将row的mouseDown/up选择区域收窄到截图可见区与数字区。CLEAR误选被修复，未实现底层窗口穿透。helper的显式有界CGEvent诊断和原真实失败都保留。
- 合流非作者发现：accepted再点击可见UNKNOWN/compensated时，旧分支先reconcile而跳过新权限validator。负责人将检查前移；随后补齐adapter/application/session接收进程一致性，拒绝借当前进程的权限读取另一活跃进程旧操作。两项回归验证拒绝时原记录不变、零观察/输入/捕获，以及获准新点击只读原操作。后台generic预检接口未改，不宣称其真实多进程权限矩阵通过。
- 两组新App测试改为方法级MainActor隔离，并等待实际entered/finished/expired事件；没有以固定yield次数或固定sleep推断调度完成。CI增加三个现有选择suite详细输出，不增加重复测试计数。

相对9de6a85，产品源码只有上述Core权限修复；其他差异是3份测试与workflow/正式文档。没有改Web页面、桥、start profile或建立第二套Coordinator。实际公共接口见[ADAPTER_CONTRACT](../../../docs/ADAPTER_CONTRACT.md#第七轮已集成的原选择等待)。

## 本次组合验证

最终源码 **`595142d0345adc0d06f54371f50406879310610d`** 的 [macOS CI40543025253](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40543025253) / job122326159138 于 **2026-10-28 00:41:17北京时间** completed/success，17个步骤全部成功：

- **410项原生**：Core134 / Adapters121 / Capture63 / UI53 / App39。
- 十个详细suite13/3/15/4/5/8/5/17/4/3均passed、0skip，合计77项已包含在410中。新增两项权限回归明确执行。
- 页面VM72、legacy54；回放55文件/19case/89prefix及2项明确SIMULATED迟到错误；故障夹具8、probe12、第五轮helper9/4/2、包装12全部通过。
- 实际SQLite v1→v2→v3/v2→v3、迁移回滚/未来版本拒绝、UNKNOWN/重启/首start/补偿与旧nil/跨profile锁回归通过。
- Release、bundle/ad-hoc签名及四项App/helper自检通过，保留CHROME_NOT_RUN / GUI_NOT_RUN / PERMISSIONS_NOT_REQUESTED / NOT_NOTARIZED。

运行环境macOS14.8.9/23J631/arm64/Swift5.10。实际临时checkout `1965e22a0f0b845489f9a8c72c90e692802ae027`，双亲main eba1a4f和595142d。root核对13组构建/测试/回放输入相同；非作者另核对9个完整目录/文件根。整个tree含main的网站差异，不能说整个tree相同，也没有合并main。完整日志209,434字符。

[实际日志摘录](ci-excerpt.txt)来自本次GitHub日志；[非作者审查](review.json)区分源码审查、负责人修复和独立CI复核。CI只运行合成图片、假桥与临时数据库；没有真实Chrome/TCC/物理鼠标或网络故障操作。

来源独立 [CI40525056642](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40525056642) 已单独核对exact9de6a85、408原生和完整日志，不替代本次组合运行。原作者首次CI40520227401的重入测试固定yield失败和最终修复记录保留。本次2aaaadb的CI40542404369在后续接收进程修复推送后被concurrency取消，不能计为通过。

本地Linux另实际执行72当前页面、54旧观察、55文件/19case/89prefix回放和12包装校验，均通过。未在本机执行Swift/AppKit或访问真实Mac；macOS结果来自以上实际CI。

## 可以继承的真实结果

| 项目 | 准确结论 |
| --- | --- |
| 同草稿A/B顺序等待 | **PASS_SCOPED**，f6417c6的一组生成PNG/software AX。A inputTriggered时B原op仍prepared；A持久succeeded观测后约65.065ms才begin B。A/B均attempt1、input1，分别有start和最终成功。不是start后并行。 |
| 未聚焦editor的非空草稿 | 同一组样本的文字、非折叠选区和3旧附件保留断言通过；不推广到任意富文本或业务转换。 |
| 时延 | A点击→AppKit close **2816.959ms**；B **12212.578ms**，包含等待与较慢页面开始。动画配置0.24s，close非像素观测；不能把这些值写成修复后正式二进制的新测量。 |
| 冷首击 | **产品FAIL，安全拒绝正确**。有效Chrome样本native完整验证晚26.323250ms，App ACK晚26.742000ms；后续ACK不重放原点击。Finder前台样本不作Chrome通过依据。 |
| CLEAR | 9de6a85软件实击**防误选通过、底层穿透FAIL**：row仍收到down/up，但不再选择图片，下层仍0次。 |
| GAP / IMAGE / NUMBER | 仅最终有前提的CGEvent批次 **PASS_SOFTWARE_ROUTING**；首批GAP guard失效未投递，仍NOT_RUN。 |
| 物理GUI /完整两操作闭环 | **NOT_RUN/未完整验收**；软件AX、CGEvent和CI不能代替物理鼠标、跨应用持续焦点、按住补位、双击、屏幕/Spaces。 |

原始来源：[双图](../2026-10-27-real-mac-round7/queue-analysis.md)、[冷边界](../2026-10-27-real-mac-round7/cold-analysis.md)、[GUI](../2026-10-27-real-mac-round7/gui-results.md)、[性能](../2026-10-27-real-mac-round7/performance-analysis.md)。没有新上传样本，也没有重复旧未决图片。

## 私有数据与准入

公开保留记录报告schema3/quick_check=ok，旧22媒体、14其他私有文件、25操作、6 UNKNOWN/compensated、3补偿及4开始审计保留；新增3生成图、2实际操作/开始。独立审查的是这些脱敏断言及一致性，**没有重新读取私有媒体、数据库或原始日志**。private-manifest的19文件/2,382,605bytes是证据清单，不是DB/媒体库存。后续本地执行继续保留其原备份，不上传私有内容。

生产start/completion/retry和Web synthetic retry继续为空；普通capture仍不上传；显式Web验收仅隔离生成图片。UNKNOWN、补偿、原图/私有媒体、首份开始证据和原始审计不清理。main保持原SHA，PR #1保持Draft，无Send、发布、网站或品牌变更。

## 下一次真实Mac直接入口

从PR #1本轮最终交接SHA建新worktree；不重置原round7/旧验收目录，不重复开发FIFO，也不重传已输入或UNKNOWN图片。该最终文档检查点与595142d保持相同原生/测试/构建输入，精确SHA由PR最终交接给出。

[开发App/helper/日志制品12751661331](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40543025253/artifacts/12751661331)：1,800,286bytes，GitHub元数据SHA-256 `7c490ad62ebdbe588ff16862bd1d5a1a8f7fff92aecab3d0603a36e67ab5fb0e`，保存至 **2026-11-11 00:41:12北京时间**。没有声称本地下载重算hash；ARM64/ad-hoc开发版本，不是公证发行。

沿用 `scripts/build-macos.sh`、四自检和 `Riftlet --web-acceptance --acceptance-trace`。优先处理：无ACK冷首击的真实连续性；CLEAR真实底层穿透及物理按住补位/双击/多屏；真实业务A→B→A/同URL；原权限撤销/恢复及多Chrome接收进程；MID真实请求命中；安全失败终止与普通可点击重生；系统截图自包含和T0/T1/T2。第七轮已有双图样本不必为演示重做，任何新操作只使用新生成图与新的真实选择。全部未决准入保持独立。
