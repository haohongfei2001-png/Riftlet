# Feedback 源码与实际部署核对表

云端事实截止2026-10-29T15:39:38.614578Z。已验证服务脚本→Receiver/D1→唯一私有Issue及远端删除链路，**不是实际原生窗口E2E**。[完整证据](README.md) · [终态JSON](delivery-checkpoint.json)。

| 对象 | 已有实际事实 | 最终工程仍需固定 |
|---|---|---|
| Receiver | 最终39f6277e-11f2-455b-be27-8f0b6a795685；持久接收/503/429/原ID重试；100/20 | 最终源blob与实际saved配置引用，之后变更需另记录 |
| Delivery源码 | 两处manual；旧21PASS+新3FAIL，修复后24本地PASS；非作者审查 | 精确C2 source/tree/blob，H2原门禁与完整CI |
| Delivery部署 | `3c749b91-ace3-45d9-86e5-62e2dab06c35`；bundle`0236e5582362b1f74d21aad2ab04ef0d3333fed75f3e49fd7d924ccbef8ce7db`，6356bytesUI逐字/独立重建一致；无临时变量/逻辑 | 最终原始平台读回引用；不拿本地构建代替平台 |
| 私有投递 | 3/3原ID、marker、正文/诊断唯一且准确；正常cron已认回原Issue2保留删除意图 | 诊断201/丢响应分支未直接捕获限制须保留 |
| GitHub永久删除 | owner三条永久Delete；同授权仓库读取成功、三条精确GET410deleted、完整stateall空；独审通过 | 不写404、不把任意错误当删除、不清历史证据 |
| D1/协议清理 | 8deleted/body0/pendingDelete0/probe0；新3保留原Issue身份；原凭证GET3/3精确deleted | 临时私有状态文件处置另记；真实Mac本地清理NOT_RUN |
| 运维 | D1TimeTravel7天未restore；Actions14:50禁用保存reload；token11-28到期 | 有权维护者轮换；恢复前冻结投递并核对墓碑/Issue；无即时物理备份清除保证 |
| Host/manifest | 最终云独审已通过，root已仅将nil一行改为固定真实HTTPS URL，其他Host字节未改；配置不代表单条已送达 | 新包manifest按实际最终source绑定；历史H包不能改贴新能力 |
| 正式CI/Beta | H完整ARM/Intel/Feedback成功，H服务21；新服务24本地 | 新H2完整Native/Feedback及实际统一App ZIP/签名/资源/许可证/source核验 |
| 真实Mac | 全部NOT_RUN，准备交Codex，无执行器 | 原生窗口→云、真实IME/VoiceOver/Keychain、正常退出/网络恢复、截图隔离 |

最终全差异审查与reviewed-source定值以[正式工程metadata](../2026-10-29-final-product/results.json)及[PR #1最终交接](https://github.com/haohongfei2001-png/Riftlet/pull/1)为准，按既有流程更新literal与既定metadata，保留原规则/历史/工作流、不扩大例外；不以旧H或本地24冒充新CI。Host不得覆盖Main/截图模块、改ReceiptPolicy、放开截图准入或引入环境override。最终包必须以--repository绑定manifest到committed Host；H旧包不追溯改变能力。

早期断连、空Issue、待删、404准备与实际失败保持原始字节和时间；最终入口只保留一份current状态，旧证据明确历史。真实cloud PASS只适用于这里逐项记录的服务操作，不能用于原生Mac或正式公证声明。
