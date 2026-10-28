# 受限真实截图首次快吞噬完整验收 · 2026-10-28

**限定 PASS：一张新的 macOS 系统截图，经一次 Riftlet 原生软件鼠标点击，取得真实上传开始、快速吞噬与后台独立成功。到此结束本轮，无第二次截图上传。**

实际运行源码为 `e421e6687651c2fac1441410c1af2bd5b8151e55`，独立分支 `codex/riftlet-real-mac-acceptance-sc-swallow-20261028`。产品源码、准入表、Core/UI/App 均未修改。本交接只增加脱敏证据；正式分支、PR #1、main、反馈分支和旧工作树未写入。

## 结果与范围

| 验收 | 结果与证据 |
| --- | --- |
| SC-INPUT | **PASS**。新图H为真实系统 selection PNG，1652×1010，1,789,589字节，8-bit RGBA、非交错。原件与私有副本SHA-256一致。一次CGEvent down/up命中H，1 begin／7 chunks／1 commit，页面inputCount与独立change计数各1。 |
| 原点击目标 | **PASS，预绑定场景**。中文ChatGPT普通已有聊天、持久业务草稿身份与所有旧操作不同。原effective完整ACK早于点击35,635.339ms（MainActor发布早35,635.338ms）；点击freeze accepted，原host/session/target一致。点击时另有刷新在途，不使用晚到ACK补签。编辑器未聚焦。 |
| SC-START | **PASS**。原附件同一进度节点4.7100724%→9.4201448%，input→严格start为1,995.7ms；原identity与新v2资格、候选journal及唯一upload_starts一致。文件设置、占位图或isUploading单值不是本次开始依据。 |
| SC-UX快速吞噬 | **PASS，软件原生窗口范围**。点击后2,559.649ms实际进入AppKit吞噬，2,686.613ms完成关闭调用；实际动画段126.964ms。WindowServer三个原窗口最后存在样本为2,700.388ms，首缺席样本2,720.581ms，后续未重现。2,315次查询全部有效。 |
| SC-COMPLETE | **PASS**。原附件100%→原进度结束→最终load→独立严格proof，input→proof为7,345ms。最终原节点、source与完整identity一致，未invalid/error。后台成功持久观察上界为点击后8,105.598ms。 |
| 内容对应 | **PASS**。独立普通显式sRGB解码，原图与预览全部6,674,080个RGBA通道零差异、完整digest相同。没有声称服务端原文件字节完全保真。 |
| 草稿保留 | **PASS，记录的检查点**。48字符正文、原editor内8..11非折叠选区、1张稳定旧附件保留，附件1→2；24个后续快照及最终快照均一致，旧附件准备文件与最终预览逐字节相等，message节点未变、未Send。 |
| 本地终态 | **PASS**。操作`succeeded`、资产`used`、可见性`swallowed/reason=uploadStarted`、revision=1，upload_starts仅新增1条；完成没有第二轮动画。 |
| 人工物理鼠标 | **NOT_RUN**。原生trace的`source=mouse`来源是有标记的CGEvent软件输入，不能冒称人工。系统截图由用户实际操作后保存并通过原生metadata核验。 |

这不是无ACK冷首击、多屏/全屏/Spaces、网络异常或安全重试矩阵。普通生产、安全失败和安全重试继续关闭。本次只验证已经由正式工程分别准入的内部候选v2开始与完成，不扩大支持范围。

## 三层对应

- **页面**：同一原操作input sequence 2；start sequence 16；100% sequence 30；progress结束41；最终load42；proof44。原节点和source未替换。严格start早于最终proof。
- **候选持久观察**：保留原unknown、input、start、attached首观察与新操作的v2登记。资格不是开始证明；start与attached各自有原观察。`integratedDevelopment`来源未改写。
- **SQLite v3**：输入中`transferring/visible`且无start；取得严格start后`transferring/swallowed`及唯一start；后台独立完成后`succeeded/used`。所有读样本采用只读事务，不把轮询结束时间当精确commit。

完整脱敏数值见 [result.json](result.json) 与 [timeline.json](timeline.json)。两个时钟分开：页面performance给出input→start/proof；原生uptime给出点击、AppKit和窗口列表。WindowServer采样是实际窗口存在性证据，**不是逐帧像素呈现或精确合成器时刻**。AppKit参数0.120s没有被当作测得耗时，126.964ms来自ActualStart与Close真实时间差。

原生窗口轮询期间Chrome PID保持前台。页面首次被观察到失焦在input后12,537ms，晚于7,345ms最终proof；后续仍保留正文、选区和附件。不把晚些时候的失焦状态写成“全过程页面一直聚焦”。

## 单次操作与数据保留

候选沿用原`Riftlet-System-Screenshot-Candidate`数据根，未清库、迁移回旧schema、删除媒体或重输任何旧图。启动前、唯一输入前和结束后分别保存一致SQLite备份。现场源/私有副本、完整target/operation、原始日志和预览仅留在权限受限的本机证据目录，不进入公开仓库。

旧6资产/4操作变为8资产/5操作：其中一张先前产生的11,489,808字节截图在启动时自然收录，超过当前准入上限，**未选择、未输入、无operation**；唯一新操作属于H。准备阶段仅在独立草稿预先放入一张新的小生成图作为稳定旧附件，不把它计作真实截图验收输入。新系统图H没有经过文件选择器或替代输入路径。

旧A/D/F仍UNKNOWN、可见、保留原attempt/target与冲突锁；无v2资格、无upload_starts、无重输。旧资产行、14条旧checkpoint、补偿及所有私有媒体hash保留。只读恢复更新了观察字段：A的updated_at/reason，D的updated_at，F的updated_at/receipt/reason。F最新观察变成invalidated，旧历史attached/start首观察仍在，未解锁或补签。详见 [data-preservation.json](data-preservation.json)。

唯一输入前检查新asset不存在于旧备份、pending/visible、原件与私有hash、业务草稿不同；CGEvent前再核Chrome PID、原图序号的AX行与原生输入窗口ID/坐标。DB和WindowServer采集就绪后才发一对事件；没有重放逻辑。App正常退出后，实验自有listener停止，原页面registry未删除或改写。

## 构建、CI、审查与交接

- 当前独立worktree执行`bash scripts/build-macos.sh`：完整Release App构建及bundle检查 **PASS**。运行的是此新构建；页面资源SHA-256仍为`c0afbd8a652c7a0e8fe6875ddbbd54f075e9c60bcda512eeb4df610e72f8948b`。
- [准确源码macOS CI40674197202](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40674197202)：本轮重新读取状态，head为e421e668，completed/success。**复用准确源码的已完成CI，不宣称本轮重新执行457项原生测试**。文档交付不重复消耗CI。
- macOS27.0(26A428) arm64，Chrome156.0.8078.73；详细核验见 [verification.json](verification.json)。
- [非作者复核](review.md)独立读取原始私有证据、数据库快照及实际源码。公开只提交有界布尔值、计数、摘要和时序；原始证据用不暴露路径/身份的哈希索引封存。

**给Pro的结果：已具备第一次实际运行的“真实系统截图→单次点击→严格开始→快速吞噬→后台独立成功”证据。** 可集成本证据包，继续既定内部Beta工作；本轮不重复上传、不改普通生产或安全重试准入，不扩大为全面发行验收。
