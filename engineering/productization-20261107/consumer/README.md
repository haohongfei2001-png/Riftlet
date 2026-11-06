# 消费者资料与封闭测试准备

状态：**DOCS_PREPARED / CLOSED_BETA_PLAN_PREPARED**。尚未邀请参与者、发送反馈、发布下载或执行新的真实 ChatGPT 验收；不是 `CLOSED_BETA_READY` / `PUBLIC_BETA_READY`。

源码基线：`2e779f646ac4874344fac94f79103e8ddf9b02c8`。本 lane 仅新增消费者资料及本目录，不修改产品、权限、遥测、云服务、数据保留或删除策略。此前的个人 Beta 3 升级接受范围保持原样，本轮新增附件要求仍需单独验收。

## 可交付内容

- [消费者入口](../../../docs/consumer/README.md)：中文/英文首用，安装及分项权限，支持矩阵，恢复/更新/卸载，隐私及反馈模板。
- [源码与文案对应](SOURCE-AUDIT.md)：具体能力、避免的误导和既有证据归属。
- [START 专项审计](START-SEMANTICS-AUDIT.md)：普通路径的实际终点、历史状态与后续研究边界。
- [10–20 人封闭测试方案](CLOSED-BETA-PLAN.md)：入组条件、四周节奏、停止条件与数据最小化。
- [参与者任务卡与自愿记录](PARTICIPANT-PACKET.md)：准备给获准参与者使用，尚未发送。
- [文案检查脚本](check_consumer_docs.py)、[固定源文件绑定](source-bindings.json)；本轮最终检查结果为本目录 `validation-result-02.json`。

## 检查范围

`python3 engineering/productization-20261107/consumer/check_consumer_docs.py` 只检查本地 Markdown 链接、约定关键表述、敏感路径/占位联系地址及所引用源码的散列。它不会联网、运行 App、操作浏览器、打开生产数据或发反馈；它不是新用户可用性测试或独立技术审查。它忽略文档之外的仓库历史，不重写旧记录。

官方说明于 2026-11-07 通过只读网页检索核对。引用只支持对应 OS/Chrome 机制，不用官方文档证明 Riftlet 当前包已经通过真实测试。UI 字符串取自该源码；消费者英文路径是说明性翻译，不声称 App 已完整英文国际化。

首次检查的 `validation-result.json` 保留 90/91：唯一失败是 README 链接了检查结束时才创建的结果文件。去掉这个自引用链接后重新生成独立的 `validation-result-02.json`；没有覆盖首轮记录或改动源文件绑定，也没有将该文档生成顺序问题记成产品失败。

## 集成时需要的最后核对

登录启动/发行 lane 可能改变同一 sprint 的源文件与包状态。统一集成后，应运行检查并重新核对实际变更影响的句子，保留本轮源绑定和结果作为历史，不把失败覆盖为通过。当前工具策略阻止真实 ChatGPT 服务操作；START 源审不替代这项验收。最终版本、签名、公证、安装包及支持责任方由正式交付清单绑定，本文不猜测新 G/H、产物名或分发 URL。
