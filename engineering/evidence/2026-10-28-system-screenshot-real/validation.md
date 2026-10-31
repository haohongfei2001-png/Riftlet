# 精确构建与 CI

- 实测App源码：`a5db972b7c4da20d30266ec8d1411fff9f434c13`，以正式4b7228为基础。
- CI树：`3f4e18a15d8cc77a367beca30ade338906df9d8d`，生产源码与实测一致，仅工作流增加本分支触发。
- [macOS CI 40647857737](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40647857737)：**completed / success**，读取了完整job/step与日志；没有重跑。
- 原生测试443项，包含3项新增TargetArmPermissionWakeTests；页面/legacy、回放/故障/probe、打包/签名和App/helper自检步骤全部success。合成自检不替代真实Chrome证据。
- 本机修复后完整App构建、bundle校验与candidate self-check PASS。
- 非作者纯Swift复现旧丢wake，并验证消费wake恢复与在途旧ACK拒绝；原始日志和脚本私有保留。
- 公开证据的后续文档提交不改变上述源码树，不伪称重新运行CI。

CI日志SHA-256：`b931157b8a5b1ec2b9dbc06c1fa6a3be139d99fb0a418652d8f72a4d10ff5e93`。

各步骤：

- Set up job: success
- Run actions/checkout@11d5960a326750d5838078e36cf38b85af677262: success
- Record compiler and OS: success
- Replay archived Web evidence offline: success
- Exercise integrated page program with synthetic DOM: success
- Exercise round-two fault harness offline: success
- Exercise round-three diagnostic probe offline: success
- Verify round-five diagnostic evidence helpers offline: success
- Native unit and integration tests: success
- Verify packaging rejection paths offline: success
- Report software panel lifecycle outcomes: success
- Package native application: success
- Run packaged executable with synthetic data: success
- Validate and archive synthetic GUI acceptance helper: success
- Archive evidence: success
- Post Run actions/checkout@11d5960a326750d5838078e36cf38b85af677262: success
- Complete job: success
