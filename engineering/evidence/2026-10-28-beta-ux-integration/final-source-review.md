# Beta 体验修复：最终说明与固定来源审计的非作者复核

审查角色：`/root/beta_ux_feedback_review`。日期：2026-10-28（北京时间）。

## 结论

**PASS，无源码或文案阻断项。** 这是对负责人编写的当前交接文档/包装说明、以及另一位作者更新的固定来源审计与 10 项 Git fixtures 的静态非作者复核。本次没有编辑产品文件、没有重复运行测试、没有操作真实 Mac 或远端引用。此前 Main/Feedback 审查继续有效，合流 Main blob 为 `05fe28ec734ba0d8c040810c737b26715a33d5de`。

## 当前说明与创始人入口

已读当前 `AGENTS.md`、`docs/INTERNAL_BETA.md`、`docs/INTEGRATION_HANDOFF.md`、`docs/VERIFICATION.md`、`docs/EXECUTION_BOARD.md` 和 `packaging/internal-beta/README-zh-CN.txt` 的本次改动，并对照原始 UX 的 `human-gui.md`、`combined-beta.md`、`latency.md`。

- 明确本轮以正式 b4bc 为基础合入 fa74 的证据后继 8e1，原 Feedback/H 已集成，不重复合历史；Main 的两处合流与 20 行新增/1 行替换说明正确。
- 提示改善限定为已接受 FIFO 等待、prepared 中性处理中、明确取消/过期/目标变化和点击时未验证。说明明确主要通过 tooltip 与辅助功能 label/help 呈现，**没有新增常驻排队徽标**。
- 未宣称上传或动画提速。旧 H 的约 2.72 秒点击至原窗口消失，与约 127 ms 动画段分别说明；无 ACK 冷首击仍安全拒绝，没有将新文案当作该问题已解决。
- e421 的本地 synthetic helper、b4bc 的软件反馈窗口检查、fa74 的独立源码 CI，均未当作新版组合 App 的物理点击或真实上传验收。真实 Chrome 物理上传、指定 CLEAR、补位后双击、真实 IME/Keychain/VoiceOver 等剩余项明确保留。
- 启动入口准确为同目录 `Start-Riftlet-Internal-Beta.command`，唯一候选参数 `--system-screenshot-candidate`；菜单核对 `Riftlet REAL TEST`。默认 App 双击仍普通收录模式，备用菜单入口有说明。
- 整包相邻存放、旧实例正常退出、原候选数据根保留、首用和 Chrome 权限引导、无扩展/无自动发送说明与现有实现相符。
- Feedback endpoint=nil、本机保存/待服务接收、不是开发者已收到的说明准确；没有部署云端或扩大隐私采集声明。普通生产、安全失败/重试、旧 UNKNOWN 和已输入图禁重传边界保持。
- 最终 SHA、两项新 CI、制品身份固定在 PR #1 的交接方式避免把来源 CI 冒充组合 CI。交付后优先创始人体验，未新增常规验收任务。

归档补核：负责人已补齐并再次读取确认 `engineering/evidence/2026-10-28-beta-ux-integration/README.md` 链接目标；README 正确区分原 fa74 CI 与待取得的最终组合 CI，并指向本轮报告、固定来源和入口。此前链接目标尚在创建的问题已消除。

## 固定来源审计：没有通过豁免目录放松保护

已逐行审阅 `scripts/verify-internal-beta-integration.py` 的新版策略和实现。

1. 六个完整 SHA 固定在代码内：e421 截图基础、c177 H 证据、f195 Feedback、b4bc 已统一 Beta、fa74 UX 源码和 8e1 UX 证据。六者都必须是实际被审提交的祖先。CLI 无来源覆盖参数，不使用 branch/event/环境变量或工作树文件作为期望来源，`git --no-replace-objects` 和修订解析防参数混入仍在，缺对象 fail closed。
2. 原 Core/Capture/Adapters/CSQLite/Resources/第三方声明/相关测试与 Web 共 10 个完整路径仍精确等于 e421 的 mode/type/OID。Feedback 共 11 个路径仍精确等于 f195，Package 与 Host 仍受此检查。
3. 只有明确列出的 **7 个非 Main UX 文件**切换为 fa74 精确 mode/type/OID；其中包含旧基线不存在的新 ProductStatusTests。Main 独立检查已审组合 blob `05fe28e…`，不能用 fa74 的无 Feedback Main 或旧 b4bc Main 代替。
4. 从旧完整 tree 检查拆出的 UI、GUIAcceptance、UITests、AppTests 共 4 个目录，并没有被豁免：递归比较每个剩余文件，排除项仅为上述明确批准路径；未批准的新增、删除、改动、类型或权限变化都会失败。App 仍递归检查原文件，仅排除分别精确检查的两个 UX 文件、Main 与 FeedbackHost。
5. H 与 UX 两个证据目录分别完整锁定 c177 与 8e1。祖先仍在但证据被删或重写的情况不会通过。
6. 预期 **42 项检查**：6 祖先 + 10 原截图路径 + 7 UX 文件 + 11 Feedback 路径 + 2 证据目录 + 4 UX 目录未变部分 + 1 原 App 集合 + 1 Main。schemaVersion=2 准确反映更新。
7. Native/Feedback 工作流、候选 launcher、packager、包验证器相对 b4bc 无差异；原 Feedback 工作流中的固定组合审计仍无条件实际执行。旧 PR #7 专用条件步骤是否跳过不能替代此固定审计。

## 10 项真实 Git fixtures 静态复核

fixture 使用独立临时 Git 库，真实创建反馈分叉、正式基础、H 证据、统一 Beta、从旧正式基础分出的 UX 源码与证据，再真实合并 Main 冲突。测试路径独立列出，不从审计允许列表自动生成。

十项测试分别覆盖：正确已提交组合（忽略不属于提交的 dirty/untracked 文件）；旧截图覆盖；反馈修改；七个批准文件分别被回退；同目录未批准邻接修改/新增；两个证据目录丢文件；同树但压平历史；同树复制 UX 而非保留 UX 祖先；Main 及其他 App 的错误组合；CLI 不接受 pin 覆盖并对缺固定来源输出结构化 FAIL。

这些是防集成覆盖/审计放宽的有意义 Git 回归。此次仅静态审阅，没有将 10 项再次执行或把静态审阅写成 macOS 测试结果。正式检查点还应以本轮实际 CI 报告这 10 项、42 项固定审计、32 项 Feedback 原生/UI、服务与包装结果。完成必要验证和 App 交付后应结束常规验证，转入创始人的真实使用反馈。
