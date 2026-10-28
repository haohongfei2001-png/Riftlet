# Feedback v0.1 · 实施交接（2026-10-28）

## 检查点与准确状态

- 独立 Draft PR：[#7](https://github.com/haohongfei2001-png/Riftlet/pull/7)，目标为 `codex/engineering-foundation-20261027`，不是 main。
- 已实现、已测、非作者审查的源码：`969463da21a89e128fd24cb973423d4a252d4b21`。
- 基线：正式工程 `4b7228a07a23381d3de467a44dd8490d73e26e7e`。本轮没有更新该 ref、PR #1、main、真机工作树或私有截图数据。
- 本文及永久证据属于文档检查点；测试 PASS 绑定上述源码，不把文档提交或临时合并 SHA 当作新真机证据。
- **客户端和云服务代码已交付；服务尚未部署，真实私有 Issues 端到端未验收。** Native endpoint=nil，接收／投递开关均关闭。

[原最小接口契约](FEEDBACK_V01_CONTRACT.md) · [部署规格](../services/feedback/README.md) · [实际验证与独立审查](../engineering/evidence/2026-10-28-feedback-v01/README.md)

## 已有可运行体验

Riftlet 菜单「反馈与建议…」打开独立 AppKit 窗口，选择问题／建议、输入多行文字。技术诊断默认不选，勾选时冻结白名单快照，预览与提交使用同一份数据；后续事件不加入原反馈。普通 Return 留在编辑器，IME 组字时不提交。关闭保存但不发送；发送只在独立 SQLite 持久入队后清空原草稿，新的草稿重新关闭诊断选项。

当前未配置服务时明确显示本机待发送，不显示云端接收成功。原反馈 ID、正文、诊断和秘密在网络故障／重启后不变。用户可查看保存正文、刷新状态、取消未尝试投递的记录或申请云端删除。需要远端删除的记录不能伪装成本机取消。已确认删除／未发送取消后，显式移除本机内容同时移除对应钥匙串凭证。

独立离线 Demo 使用固定的合成诊断与模拟接收器，窗口明确标注离线演示，不能发送到云端。正式 host 不使用 Demo 的伪凭证。

```bash
# 普通工程 App，菜单中打开反馈窗口。当前只持久保存、不上传反馈。
bash scripts/build-macos.sh
open build/Riftlet.app

# 独立离线反馈演示，不接触截图目录或浏览器
bash scripts/build-feedback-demo.sh
# 解压 build/Riftlet-Feedback-Demo.zip 后打开其中的 App
```

开发包 ARM64、ad-hoc，未公证。CI 实际构建与软件窗口验证不等同 Finder/Gatekeeper、物理键盘或 VoiceOver 验收。

## 数据与诊断边界

`FeedbackHost` 只把已有 CaptureDiagnostic 和本地读取结果投影为闭合枚举／有界计数。队列可见性、状态、操作阶段、可见性原因分开记录；吞噬不是完成，UNKNOWN 不是失败。记录是最近 64 条会话采样，不是完整逐操作时间线，也不证明真实网络来源。候选原始观察、acceptance trace、hash、原操作／目标 ID、正文、选区、媒体或剪贴板从不作为诊断输入。

覆盖包括来源／导入／私有存储异常、队列读取失败、选择拒绝、权限状态和已有持久事实投影。仅观察 UI 交互延迟投影，不声称检测了像素级不一致。`previousSessionUnclean` 是异常退出迹象，不是确认崩溃；首版不采集原始 crash report 或所有系统日志。不增加健康摘要、OCR、附件、云同步或 AI 服务。

每个运行模式有独立的 `Feedback-v01/feedback.sqlite`（反馈 schema 1），不打开截图 queue.sqlite，不共享 writer，不改 SQLite v3 或迁移。目录 0700、文件 0600；单进程文件锁、独立 actor、有限 busy timeout。普通关闭／退出会刷新草稿；不对尚未刷盘的最后瞬间输入作断电零损承诺。

正文提交上限为 4,000 Unicode scalars 且 16 KiB；本机编辑草稿可保留到 128 KiB。最多 20 条待处理、200 条本机记录、2 MiB 报告内容；满额拒绝新入队并保留草稿，不驱逐人的文字。报告秘密保存在 Keychain，不放入 SQLite 或 URL。新增 `credential_intents` 只保存最多 32 个随机反馈 ID：先记创建意图，入队事务成功后移除；未提交秘密在失败、并发和重启后安全清理。读库不明时不删除秘密，无法清理时保留意图；不影响截图库。

## 云端实现与剩余责任

接收器严格校验字段与大小、参数化 SQL、同 ID/正文/秘密幂等。D1.batch 持久成功后才给 202。Cron 的 GitHub 创建意图先落库，再最多一次自动 POST；丢失响应仅按原 marker 查找，不因没找到就再建 Issue。这优先避免重复，不承诺分布式 exactly-once 可用性：在 intent 后、真正 POST 前崩溃可能需要维护者处理。

DELETE 若先于原 POST 落库，先原子保存与报告秘密绑定的删除墓碑，迟到 POST 不能复活内容。未知 ID 的墓碑仍经过原 SQL 配额；重复删除不重复计费额。服务端默认每 IP 小时桶 20 次／全服务每天 1,000 份接受上限，IP 只用于轮换 HMAC 桶；这不替代边缘请求限流或费用告警。

正文／诊断最多 90 天；未完成投递到期明确进入 delivery_expired，不说已处理。私有 Issue 已创建或可能已创建时，删除保留 deletion_pending，直至有权维护者完成永久删除并核验。关闭或编辑 Issue 不等于删除。已解决的去内容墓碑最多一年，即使保留了旧 Issue 编号也清理；未解决删除义务不因 TTL 消失。恢复云数据库备份前必须停投递并核对 Issue／删除台账。

## 最小正式工程接入

新增模块和路径：`RiftletFeedback`、`RiftletFeedbackUI`、`RiftletFeedbackDemo`、其测试及 `services/feedback`。共享改动只有 Package targets/dependencies 和 RiftletMain 的菜单、typed hooks、启动与退出接线（20 行新增、1 行替换），新增 FeedbackHost。

对基线的 compare 已确认 **Core、Capture、RiftletUI、Adapters/Web v13、Resources、截图测试与原 CI 均无修改**。没有新第三方 runtime package、没有第二套截图／上传状态机，ReceiptPolicy 与真实截图的三份关闭准入表保持原样。最终集成负责人只需审查该最小 host 差异；若正式 App 同期前进，保留最新业务逻辑并接入这些旁路 hooks，不用反馈分支覆盖整份 Main。

本轮作者实际通过隔离分支/Git 对象和 CI checkout 实施；本地只有测试源码副本，没有宣称建立了可访问用户 Mac 的完整 worktree。独立审查由 GitHub Codex 执行，没有声称三个子代理并行。

## 公开测试前仍须完成

1. 授权 Cloudflare 账户、一个专用 D1／两个最小 Worker，以及独立私有 GitHub Issues 目的地。服务器秘密通过平台秘密配置输入，不进客户端、源码、PR 或对话。没有购买服务、创建资源或改网站/DNS。
2. 在已授权环境部署并填写准确 HTTPS endpoint；先用明确授权的合成文字完成真实 Riftlet 窗口→D1持久回执→私有 Issue。验证超时重复请求、删除先到、Issue POST 丢响应、限流、隐私字段与删除处置。
3. 真实 Mac 的 Keychain 权限与重启、中文 IME、物理关闭/退出/重开、VoiceOver、Finder 首装与正常截图点击资源/延迟对照。当前均 NOT_RUN；不因为 CI AppKit 软件测试通过而扩大范围。

旧 UNKNOWN、原始图片、补偿和截图生产准入不依赖本反馈专项，也不会通过反馈恢复／删除逻辑改变。
