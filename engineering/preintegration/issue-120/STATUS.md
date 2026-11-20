# Issue #120 预集成验收

**PARTIAL · 新版登录草稿验收 0/16。** 当前没有 #120 签名候选。#119 的 1.0.7 build 53 仍是独立的上游候选。正式产品接线须从包含最终 1.0.7 的实际 main 起步。现有 [Draft PR #122](https://github.com/haohongfei2001-png/Riftlet/pull/122) 以固定的 build 53 比较分支承载准备材料。[执行规范](https://github.com/haohongfei2001-png/Riftlet/issues/120) · [规划交接](https://github.com/haohongfei2001-png/Riftlet/blob/a18ef269b63d1682384531a155c425d856b37e5d/docs/plans/issue-120/CODEX_HANDOFF.md) · [上游候选验收](https://github.com/haohongfei2001-png/Riftlet/pull/119#issuecomment-7028325810)

| 新版核心组合 | ChatGPT | Claude | Gemini | DeepSeek |
| --- | --- | --- | --- | --- |
| Chrome | NOT_RUN | NOT_RUN | NOT_RUN | NOT_RUN |
| Edge | NOT_RUN | NOT_RUN | NOT_RUN | NOT_RUN |
| Safari | NOT_RUN | NOT_RUN | NOT_RUN | NOT_RUN |
| Brave | NOT_RUN | NOT_RUN | NOT_RUN | NOT_RUN |

此表指同一最终签名 App 在登录草稿中的 L3。Kimi、国内千问、豆包、Perplexity 及独立的国际 Qwen 变体也尚无已验收组合。[逐格结果及逐项查询](matrix/README.md) · [机器矩阵](matrix/results.json)

| 阶段 | 本轮可复核的交付 | 尚缺 |
| --- | --- | --- |
| W0 | 远端 main、#119、公开版本与实际包字节已核对。临时工作树从 #119 c764246 读取，保留 build 49 至 53 的所有变化。macOS 27 上可找到 Developer ID Application 身份与公证工具。 | 实际 main 仍在 1.0.5。#119 的收口由 #118/#119 管理。 |
| W1 | 原 RiftletCore、TargetLease、TransferRequest 和 QueueStore 上编译契约；轻量 pin 与异步原回执分离。拒绝跨进程、跨点击或模式的回包。新开 SQLite 连接后只允许原 invocation、原图与资源摘要一致的续查。 | 正式 coordinator/adapter 接线、旧用户数据迁移、签名 manifest 和普通 App 路径。 |
| W2、W6 | 官方浏览器本地能力实测、原生接收方及字典检查见 [Host 记录](hosts/README.md)。Safari 27.2 实测：关闭原标签后，原索引命中另一张同 URL 页面。默认、正常开启脚本和恢复默认三次结果一致，已把这条路径挡在冷点击输入之前。Brave 获探针授权后可读取原生窗口及标签 ID；默认配置的页面只读 JS 返回错误 12。 | Safari 可证明的替代冷绑定及跨世界原稿身份、Brave 默认保护下的正式登录会话、Firefox 普通窗口的无扩展执行路径、旧 Safari 实机验证。 |
| W3、W4 | 八个新站点匿名只读探查。Gemini 主编辑器及对应上传菜单可定位；未取得其文件输入归属。独立复核的合成网页修正了错图、相邻控件、异步换卡和重复输入许可。[逐站记录及夹具](providers/README.md) | 各站真实账户、原稿的动态附件入口和接收证据；先做普通 Chrome × Claude，受阻时用 Gemini。 |
| W5 | 机器矩阵将模拟、真实浏览器页面夹具、安装 App 和登录站点的证据分开；逐图交叉核验候选、草稿、操作与时序。已有 7 组验收记录验证测试。 | 通过同一签名 App 调用的正式 L2、登录网站 L3、性能与升级放行。 |
| W7、W8 | 共用契约和隔离夹具已有非作者复核；未改变产品源码、CI 或准入。 | 从纳入 1.0.7 的实际 main 接入产品并将同一个 #122 改以 main 为基准，再做独立源码准入、双架构 CI、签名公证、安装和同包验收。 |

## 重放

从仓库根目录执行下列命令。矩阵重放不启动浏览器。宿主与 Provider 目录各自说明了真实浏览器隔离验证的条件。

```sh
python3 -B engineering/preintegration/issue-120/baseline.py
engineering/preintegration/issue-120/contract/check.sh
node --test engineering/preintegration/issue-120/contract/observation.test.mjs
(cd engineering/preintegration/issue-120/matrix && python3 -B -m unittest -q test_matrix.py && python3 -B matrix.py --provider gemini --browser safari --level L3 --case F01)
```

基线探查返回 WAITING_FOR_107_BASELINE 时，这些文件依然是预集成材料。基线具备后，从新的 main 创建实施工作树，将通过复核的增量按职责接入，沿用原库和原操作的单次输入约束。[短进度](PROGRESS.md)

[独立复核全文](INDEPENDENT_REVIEW.md)记录了问题、修复、复测和最终结论。复核通过范围是共用契约、Provider 隔离夹具和宿主探查。复核者编写的 W5 矩阵由集成人另行检查。
