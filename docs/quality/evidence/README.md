# 本轮证据索引

日期：2026-11-14（Asia/Shanghai）。源码基线 `44f745a15ecb3682a9da0bda17f17a5d9fc1f07e`；正式版本 `v1.0.1`。本目录保存原始结果、缺陷复现与独立复核，不能把所有文件视作 PASS。

完整范围与后续门槛见[验收矩阵](../ACCEPTANCE_MATRIX.md)；问题状态以 [findings.json](../findings.json) 为准。本目录不维护另一份状态队列。

证据状态按各自范围解释：

- `SOURCE_CONFIRMED` 是已检查生产调用链，不表示已完成原生复现。
- `BLOCKED` 要保留阻断点；这里 Chromium 在启动前失败，产品根本未执行。
- `NOT_RUN` 与“仅历史证据”都是当前候选的验收缺口，不能计作 PASS。

## 文件与证明范围

| 文件 | 内容 | 结论边界 |
| --- | --- | --- |
| [baseline.json](baseline.json) | 公开正式/候选 release、资产摘要、近期 PR、远端保护读取、执行环境 | 固定本轮时间点；未合并 PR 不算已发布功能；没有声明 Mac/Codex 任务已启动 |
| [public-channel-verification.json](public-channel-verification.json) | 线上官网/feed/DMG 字节核验、Ed25519、SHA-256 | feed 与 DMG 验签/下载一致性已验证；Apple codesign、公证、Gatekeeper、Sparkle 替换安装未验证 |
| [website-ui-review.json](website-ui-review.json) | Cloud Browser 真实官网的语言切换、合成 demo、下载与安装弹窗观察 | 不是原生 Riftlet 或真实 ChatGPT；记录了视觉检查但本目录未保存对应 PNG；移动端未测 |
| [attachment-existing-tests.tap](attachment-existing-tests.tap) | 56 个 Node 页面程序测试通过 | 生产 JS 在受控 DOM 中执行；不能证明真实浏览器/ChatGPT 成功 |
| [attachment-foreign-picker-repro.cjs](attachment-foreign-picker-repro.cjs) | QA-ATT-001 的最小可执行反例；直接使用仓库 fixture 与生产 JS | 合成 DOM/图片，无账户/网络；**退出 0 表示缺陷仍可复现** |
| [attachment-foreign-picker-result.json](attachment-foreign-picker-result.json) | 无关异步 picker 被写入一次、收到当前文件与 change 事件 | 实际观察到受控错误目标；没有证明真实 ChatGPT 数据外传或发送消息 |
| [attachment-foreign-picker-native-attempt.json](attachment-foreign-picker-native-attempt.json) | Linux Chromium 夹具因 `socket()` 权限在启动前失败 | `productExecutionOccurred=false`；没有浏览器产品执行结果，也没有 Mac/在线 ChatGPT 结果 |
| [core-independent-review.md](core-independent-review.md) | 非作者复核 QA-ATT-001/002，独立重跑反例与读取 Swift 装配路径 | 缺陷成立及最小修复边界；不是修复 PR 验收通过 |
| [interaction-independent-review.md](interaction-independent-review.md) | 非作者复核 QA-ATT-003 的 START 展示与 QA-ATT-004 的主线程等待 | 源码成立；未实测 AppKit 卡顿时长，不把每次 5 秒事件预算写成整次点击上限 |
| [storage-evidence.json](storage-evidence.json) | 相关源文件 SHA-256、工具执行范围与未执行项 | 绑定本轮来源；坏偏好启动、大历史 App 性能、补图后原生重检未执行 |
| [storage-tests.log](storage-tests.log) | 26 个 Python 离线备份/健康/恢复测试通过 | 真实临时文件/SQLite；不是原生 Swift importer、App 启动、物理断电或附件验证 |
| [storage-independent-review.md](storage-independent-review.md) | 非作者复核 QA-DAT-001/004，补充合法旧值与同源运行条件 | 代码因果链成立；保留原字节/有效偏好，不按损坏偏好的处理方式重建数据库 |
| [feedback-tests.tap](feedback-tests.tap) | 24 个 Node 反馈测试通过 | 本地 SQLite/模拟服务边界；不等于实际 D1/Workers/private Issue 或原生 GUI→云端闭环 |
| [governance-independent-review.md](governance-independent-review.md) | 非作者复核当前治理入口、产品约束与历史归档，结论通过 | 工作区文档审查；仍需最终 G 的完整差异与 reviewedSource/reviewedTree 准入，不是软件验收 |
| [issues-independent-review.md](issues-independent-review.md) | 非作者审查 22 条问题正文及安全边界，给出具体补文要求 | 评估 finding 与工程交接质量；不是修复代码、最终发布的 Issue 正文逐字核验或正式包验收 |

## 复现命令与退出码

在仓库根目录执行；使用支持仓库测试的 Node（本轮 24.22.1）和 Python 3。命令只针对合成夹具/临时库，不需真实截图或 ChatGPT 登录。

```bash
node --test Tests/WebPageProgram/attachment-entry-handoff.test.cjs Tests/WebPageProgram/ordinary-composer.test.cjs
python3 -B -m unittest discover -s Tests/StorageReadiness -p 'test_*.py' -v
node --experimental-sqlite --test services/feedback/feedback.test.mjs services/feedback/retention.test.mjs
```

这三组现有测试在本轮分别为 56/26/24 个 PASS，各自只支持本表范围。数量不相加成产品通过率；其中没有真实 ChatGPT 附件验收。

```bash
env -u RIFTLET_PAGE_PROGRAM_SOURCE node docs/quality/evidence/attachment-foreign-picker-repro.cjs "$PWD"
```

该反例特意断言错误 setter=1、change=1、结果为 `inputTriggered`，所以当前基线**退出 0＝漏洞已重现＝产品此场景 FAIL**。修复后的回归测试应明确要求外来写入/事件为 0，并保留正常动态输入正例。

修复后旧反例退出 1 只说明原断言不再全部成立；也可能是路径错误、夹具异常或程序崩溃，不能单独据此宣称修复成功。读取结构化结果、错误原因，并补独立正常路径和真浏览器/真机证据。`RIFTLET_PAGE_PROGRAM_SOURCE` 被清除，避免环境变量把复现换成别的 JS。

Chromium 失败记录提及的实验脚本不在本目录；该 JSON 只是“启动前受阻”的记录，不提供可复用真实浏览器 PASS。当前环境没有 Swift/macOS，原生测试标记 NOT_RUN。

## 历史材料如何使用

- [PR58 原生画面](../../../engineering/pr58-native-review/visuals/)用于理解旧形态，不是当前设置或 1.0.1 视觉验收。
- [旧有限卷空间不足验证](../../../engineering/productization-20261107/storage/README.md)实际使用自有 128 MiB HFS+ 卷，保存产品写入/SQLite 失败与恢复；不是本轮重跑、APFS 全覆盖或断电测试。
- [旧性能记录](../../../engineering/productization-20261107/performance/README.md)有其自己的构建与样本；不能把修复前数字当作当前 App 全启动时间。
- [旧反馈云端证据](../../../engineering/evidence/2026-10-29-feedback-cloud/README.md)保留源身份与当时闭环；不能覆盖本轮原生反馈界面、IME/VoiceOver、Keychain 或已改动服务。

引用历史证据时保留原日期/SHA/包身份/测试环境；结果不同则并列说明，不替换旧失败或把历史路径改写成本轮 PASS。

## 内容与后续证据要求

本目录使用公开仓库/发行信息、源文件摘要、合成 DOM/图片与临时 SQLite 结果。未收录私人截图、真实 ChatGPT 对话正文、用户数据库、浏览器账户资料、凭证或反馈密钥。

后续原生验收由具备 Mac 的 Codex 执行器和独立验收代理承担，使用专用测试账户、合成图片与隔离库；不要求用户提交日常截图或替工程团队验收。

每次追加结果应记录：源码与包身份、命令/具体动作、环境、退出码、实际断言、证据等级、未执行项。截图/视频应对应当前正式 App 装配和同一候选；分享前检查合成内容与账号隐私。

不要把“能构建”“单元测试通过”“网页演示成功”“下载验签通过”写成真实 ChatGPT 成功，也不要把 finding 的独立确认写成修复的独立批准。
