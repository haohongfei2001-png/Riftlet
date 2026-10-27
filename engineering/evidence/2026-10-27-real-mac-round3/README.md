# 第三轮真实 Mac 候选交接

**首版日常一次点击尚未准入；生产真实截图输入与安全重传继续关闭。** 本轮交付增量源码、实际运行与明确未完成项，不把 CI 或自动化鼠标当物理验收。正式 PR #1 / main / 网站 / 设计均未修改；由正式 Pro 统一集成。

## 不可变来源

- 正式基线：`7d6bca6010fdd9098aef879d9734497a79403a03`；建立独立第三轮工作树前用远端 HEAD 核对一致。
- 分支：`codex/riftlet-real-mac-round3-20261027`。
- helper 第一提交：`11aec04`；最终源码：`159b3ef3e6c87ea468ba334dff64ad8db640d80c`。
- macOS 27.0 / 26A428，arm64，Command Line Tools SDK 27.0；实际 App 为本地 release / ad-hoc 签名。最终二进制 SHA256：`f52192ebc7a196ab9640c8f21606345b2556b8a3ad544266955c31388285ea82`。
- [CI 40467839636](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40467839636) 精确测试上述最终源码：228 Swift、38 page VM、19 archived replay、8 round2 fault groups、12 round3 probe groups、release 打包与三个自检 PASS；非作者核验见 [review.json](review.json)。
- 本地完整 XCTest **NOT_RUN**：当前 CLT 缺 XCTest module；未安装/切换 Xcode 来掩盖环境，改由一次正式 macOS CI 执行。实际 JavaScriptCore 另验证全部 12 闭集错误、nonce/CFBoolean/私密错误过滤。
- 较早 Web 探索运行来自同一工作树未提交版本，不能冒称最终源码运行；与最终版差异是 trace 字段重命名、三个错误标签及 helper 诊断字段，详见 [native-runtime-summary.json](native-runtime-summary.json)。页面源码与最终版完全相同，SHA256 `f8980e524cc62f4fd913d54e9fbe3855c4112737b7f503f9229f215ccd4dfb9a`。

## 实际修复与边界

1. UX-01：增加 Chrome AX 窗口/焦点/标题变化调度和行区域 mouseEntered 预绑定提示；AX 只用已有权限，不取文本。对象级 50 ms 超时、合并延后刷新、observer/代际检查和停止取消。提示不提供目标身份。捕获 ACK 返回前重新核对原窗口/标签，已变化则拒绝。事件前 ACK、点击冻结、页内最终提交检查保持不变；**没有冷点击后捕获新目标、排队重放或要求用户等待的路径**。
2. 增加封闭错误与排队/执行/ACK日志，整行写入，限制 2048 条，无 URL/正文/令牌。`transportSucceeded` 只代表桥接阶段；真正发布 ACK 以 `arm_completion` 为准。
3. UX-02：v7 对已证明普通线程的 React root `current` 普通赋值做可恢复监视；每 form 每次 commit 检查一次。业务变化、重入、异常或 descriptor 丢失永久撤销旧输入权。保持稳定逻辑草稿与焦点代际分离。Home 不安装该 monitor。
4. **v7 仍是开发候选**：改变属性反射语义，无法覆盖不经过 setter 的原地 props ABA、defineProperty 绕过后恢复或安装前历史。不能由 VM 声称真实 A→B→A、同 URL 替换、移窗/重启全部通过。旧 v6 操作没有搬进 v7 注册表、没有重新输入；版本切换会失去旧页面程序的部分观察能力，保留数据库/私有备份供原版本审计。
5. helper 增加实际行几何、底层靶点、严格焦点条件、按住期间外部补位场景；不产生鼠标事件。用户拒绝代做必要人工动作后，没有再次索要操作；物理来源仍未知。见 [gui-review.md](gui-review.md)。
6. MID 新 probe 仅诊断 fetch/XHR 的生成名称→响应候选→实际 byte body/hash 关联；原 fetch Promise 原样返回，原 XHR 参数同步传递，60 秒恢复。两条同名 JSON 不是 retry。**本轮未在真实上传执行此 probe，没有真实 MID 故障。**

## 验收结果

| 项目 | 状态 | 事实 / 未通过原因 |
| --- | --- | --- |
| 构建、CI、三个自检 | PASS | 上述精确源码与独立日志核验；不等同产品验收 |
| AX 事件唤醒 / 页内普通 commit 监视 | PASS（局部） | 探索运行有 56 chromeFocus、6 windowCreated、3 title、9 activation；92 次 arm 成功，无新 input command / selection boundary |
| 真实普通线程 root monitor | PASS（仅运行/恢复） | 三个 root 分别 474/847/79 次检查，总耗时 132.4/172.4/30 ms；最高 7/11.6/3.6 ms。没有强行改写业务身份；没有新上传。显式停止后三个 descriptor 均恢复 latest current |
| UX-01 冷首击全矩阵 | NOT_RUN / 未准入 | 本轮没有完整事件→冻结→一次输入证据。提示可降低 ACK 落后概率，不能证明任意冷首击可靠；native 最大排队约 199.6 ms、执行约 232.1 ms，非故意延迟实验 |
| UX-02 真实 ABA / 同 URL / 新旧线程 / 移窗 / 重启矩阵 | NOT_RUN / 未准入 | 真 commit 数量不证明业务转换；浏览器控制连接读请求两次超时后停止重试，无假转换或清库解锁 |
| helper AppKit 非激活与重复点击 | PASS（局部观察） | 10 次已接受选择全部图内；5 次 clickCount 2/3 被抑制；来源不能证明是人工，且无替换行双击 |
| CUA 自动化 GAP 底层接收 | PASS（单点） | 精确事件 4 到达 probe，零选择；[gui-automated.json](gui-automated.json)。CLEAR 事件坐标错误，不解读为穿透结果 |
| 物理首击、键盘焦点、透明/GAP、按住补位、Spaces/热插拔/旋转 | NOT_RUN | 没有足够的真实命中/底层接收/事件来源证据；CLEAR 的窗口命中预测不是实击 FAIL 或 PASS |
| 实际 App 十分钟资源测量 | PASS（测量） | 61 个内核样本、约 600 秒，含一次截图收录；CPU 累计约 0.73 秒（约单核 0.12%），299 次 interrupt wakeups；范围见 [capture-resources.json](capture-resources.json)，不代表上传负载或泄漏认证 |
| 系统截图来源识别及自动收录 | PASS（一次 CLI 区域截图） | 实际 capture-only App，系统 `kMDItemIsScreenCapture` 元数据，新增一条 pending；原五条未变；不是快捷键测试，更不是上传闭环 |
| Riftlet 自包含 | FAIL | 只运行实际 App、没有 helper；系统区域截图内可见原五张 Riftlet 微图。私有原图保留且不进公共仓库；不把 sharingType.none 当修复 |
| 完整 T0/T1/T2 延迟 | NOT_RUN（测量不完整） | 采样脚本在完成截图后遇到 os.listxattr 不可用，已读取持久状态确认收录，没有重复截图。单独 T0 与 T2 未观测；mtime→import 约 234 ms、firstSeen→import 约 162 ms 仅局部指标 |
| MID 真字节关联 / 中段故障 | NOT_EXERCISED | 12 组离线 probe 测试不替代真实请求；没有新大图上传、没有abort、没有 retry 结论 |
| 数据保存与防重放 | PASS（本轮范围） | 见 preservation.json：15 个既有私有媒体字节不变、旧资产/操作身份/attempt/target/phase 保留，3 条补偿审计字节不变；恢复只更新旧记录的观察时间/原因/receipt，旧完整备份仍在 |
| 系统截图→一次点击→原草稿→吞噬 | NOT_RUN / 继续关闭 | 来源、目标、完成和原生交互联合准入仍不成立；没有降低生产保护来演示 |

## 下一次直接接续

从上述源码或 Pro 集成后的最新正式 HEAD 继续。先修复可可靠控制的精确 Chrome 测试标签连接，再用已存在事件 trace 做一组冷首击与真实同 tab 业务 A→B→A；不能又用普通成功上传累加数量。root monitor 已显式停止并留下撤销墓碑，旧 v7 lease 不可复活；新的页面生命周期需要重新建立证据，不能删除 UNKNOWN 来重试。性能峰值也需归因与准入，当前监视器不能直接推广生产。

原数据库、截图、历史分支、恢复快照、原始本机日志均保留。验收结束已退出本轮 App/helper；三个已安装 root monitor 的属性均已恢复，撤销墓碑保留。公共目录仅保存无正文/认证数据的投影与合成工具；本轮真实截图只保存在用户本机。没有发送 ChatGPT 消息、没有操作正式 PR 或发布。
