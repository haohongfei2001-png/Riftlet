# Riftlet 1.0.4：消费级产品重整

**1.0.4（26）私有候选已完成签名、公证和真实隔离升级。** [安装包身份、原生截图、逐项验收与剩余发布阻塞](RC_REPORT.md)。1.0.3 继续作为公开下载版本。

## 开工与跟踪

- [CODEX_HANDOFF.md](CODEX_HANDOFF.md)：直接执行入口、基线、流程及停止点。
- [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md)：T00–T10、依赖、改动位置与逐包完成标准。
- [ACCEPTANCE.md](ACCEPTANCE.md)：自动化、原生GUI、真实服务和签名升级分层验收。
- GitHub：[总任务 #106](https://github.com/haohongfei2001-png/Riftlet/issues/106) · [托盘 #107](https://github.com/haohongfei2001-png/Riftlet/issues/107) · [全库查找 #108](https://github.com/haohongfei2001-png/Riftlet/issues/108)。其余任务关联已有Issue，见实施计划。

## 产品与来源

- [AUDIT.md](AUDIT.md)：实际完成度、问题台账、P0/P1/P2/REMOVE、推广门。
- [DESIGN_SPEC.md](DESIGN_SPEC.md)：最终信息架构、视觉token、托盘材质/机身色、首用与全局规则。
- [SETTINGS_INVENTORY.md](SETTINGS_INVENTORY.md)：所有现有控制与字段的保留/移动/隐藏/移除及迁移。
- [BASELINE.md](BASELINE.md)：准确源码、公开包、官网、feed、公证及冻结状态。
- [VISUAL_EVIDENCE.md](VISUAL_EVIDENCE.md)：12张真实1.0.3窗口图、问题对照、明确标注的设计示意。
- [审计回执](evidence/audit-receipt.json) · [原生case与帧hash](evidence/native-runs.json)。

规划时的 1.0.3 原生设置14/14 PASS；桌面41/42 PASS，另有`trayCameraObscured`点击前命中检查失败。失败保留并纳入必查任务，不把设计图、进程退出0或历史别包证据当作1.0.4完成。对应的 1.0.4 同包结果见[候选验收报告](RC_REPORT.md)。
