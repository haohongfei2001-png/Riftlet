## Current receiver checkpoint

Receiver and D1 are deployed. The final service-script snapshot records 36 HTTP checks and five identities reporting deleted after cleanup. Direct D1 cleanup confirmation and private GitHub delivery remain blocked by the disconnected authorized browser; Host remains nil. See [current checkpoint](README.md) before performing any new test. All old synthetic identities are deleted and must never be reset or reused as new submissions. This is a prepared handoff, not a scheduled Mac executor.

# 准备交给 Codex：Feedback v0.1 最小真实 Mac 验收

用户最新决定：连接 Mac 的任务留给 Codex；本轮其它工程、Cloudflare 和 GitHub 工作继续完成。本清单已经准备，供后续实际接手的 Codex 在已获授权的真实 Mac 可达时执行。准备清单不表示任务已投递、执行器已设置或后续执行已安排；不要求用户现在安装、测试或再批准普通实现选择。

## 当前服务阶段：2026-10-29

集成人已实际运行 Receiver：`https://riftlet-feedback-receiver.haohongfei2001.workers.dev/v1/feedback`。已归档的 `engineering/evidence/2026-10-29-feedback-cloud/d1-first-receipts.json` 记录 **2026-10-29T14:00:19.183Z** 对专用 D1 `4167f4a2-5dfd-422d-86ca-077176fc8600` 的真实 Console 查询：两条已提交反馈均为 pending、正文未清空、尚无 issue_number。此前 HelloWorld 骨架状态是更早的检查点，不能再作为当前 Receiver 结论。

该观察只证明本轮真实服务接收阶段，不证明 Delivery 已投递或私有 Issue 唯一形成。集成人正推进 Delivery；最终接手时从正式云端证据读取更新的部署版本、Issue 身份和测试清理结果。这两条服务端合成反馈不算下面 A 场景的原生窗口输入。Host 当前仍保持 nil，实际地址候选只在隔离目录准备；只有真实 Receiver→D1→私有 Issue 链路经审查后才由正式集成人应用并重建 App。

本清单未安排任何执行器。MAC PASS 和真实原生窗口端到端仍为 NOT_RUN。

## 执行前取得最终工程身份

使用正式集成人交付的最新统一 Riftlet App，不能用 Feedback Demo 或旧 Main。记录最终 source head、source-admission checkpoint、CI run、App 包 SHA256、构建架构、OS、签名状态及 `build-info.json` 的公开 endpoint。对照同一部署的 Worker version、D1 和私有 Issue 目的仓库引用；没有确定真实地址或完整构建时，该项为 BLOCKED，不能拿 placeholder 或 mock 运行。

Mac 可达后先只读确认已有 App 实例、工作树和数据目录。使用隔离验收工作树/新交付包，不覆盖用户真实开发树、不清旧数据、不重复 H，不重传/解锁旧 UNKNOWN。统一 App 的截图准入、Chrome 目标绑定和原数据根保持原状。仅创建明确标记的合成测试反馈正文，不主动发送私人内容。

启用地址后的 Host 会按既有逻辑 pump 当前 App 模式中先前已明确入队的待发送反馈，沿用原 UUID/凭证；不会发送未入队草稿。验收前只读确认测试模式与其 outbox，记录既有待发送记录的处理义务，不通过清库、复制旧反馈为新身份或修改自动重试来隔离测试。

每条测试记录一个完整 feedback UUID、UTC 起止时间、本地状态及对应 D1/Issue 身份；可公开证据不包含 per-feedback token、Keychain 内容、真实正文以外的私人数据、截图、聊天、完整本机路径或原始 trace。原始私有证据与公开摘要分开保存。

## A. 从真实窗口正常发送

1. 打开统一 App 菜单的“反馈与建议…”，确认窗口和截图菜单来自同一进程/App 包。
2. 不勾诊断，实际输入含中文、多行且明确标为测试的文字；点击“发送反馈”。保留真实窗口操作证据。
3. 确认先存在本地持久记录，实际 HTTPS 请求由该 App 产生，Worker 在 D1 持久成功后返回同一 UUID 的接收回执；UI 只能此时显示已接收。
4. 等待实际定时 Delivery，将 D1 的该 ID 与独立私有 GitHub 仓库唯一一条 Issue 对上。核对正文一致、诊断缺省、Issue 数量为一，记录 Issue number/node ID 与时间。
5. 实际刷新状态，确认“已收到/已投递/开发者处理”没有混用。通过 API 直接发另一条请求不算本场景通过。

## B. 真实诊断、输入和窗口生命周期

1. 新草稿的诊断默认关闭。在真实本地业务事件后主动勾选，打开预览，保存预览中允许的字段/计数。
2. 勾选后再产生一个普通业务事件，然后发送，确认实际提交诊断等于已冻结预览；禁止直接调用 `diagnostics.record` 或伪造 fixture 作为“真实业务事件”。
3. 检查无媒体、聊天正文、剪贴板、完整路径、认证、原始 trace、媒体哈希或操作内部身份。若真实队列存在 UNKNOWN/吞噬计数，只读验证其保持原语义；没有该真实覆盖时写 NOT_RUN，不能制造上传或重传旧 UNKNOWN 来补覆盖。
4. 用真实中文输入法完成组字，组字阶段 Return/发送/关闭不得误提交；完成组字后正常发送。检查多行回车、Tab、Escape、Return 和 VoiceOver 的控件名称/操作及完整正文可访问性。
5. 编辑→关闭→重开→再编辑诊断与正文→再次关闭→重开，最后一份文字/选择完整。编辑后正常退出 App 再启动，同样保留最新已交给窗口的状态。
6. 在仅 Feedback 的隔离故障条件下测试保存失败：正文留在窗口、重试保存有效、“复制正文”仅由明确点击触发且不附带诊断/凭证，未可靠保存时不得悄悄退出。禁止用清生产库或移除整套 Keychain 制造故障。

## C. 断网、未知结果与重启

| 场景 | 必须观察的结果 |
| --- | --- |
| 真断网后发送，再正常退出/重开/恢复网络 | 原文、UUID、原 per-feedback 凭证、待发送状态不变；只投递一次 |
| 请求超时/Worker 暂不可用 | 本机保留，UI 不将未知远端结果说成失败或成功；后台自动重试后恢复，不停滞 |
| 连续重复点击发送 | 同一已入队正文不产生多个身份或多个 Issues；不同新草稿仍可独立发送 |
| D1 已持久化但 App 丢失回执 | 恢复后同 ID/原凭证重试幂等，D1 一条，GitHub 一条，正文不变 |
| Keychain 单条测试凭证不可用 | 旧反馈不生成新身份或新凭证伪装重试；提示准确，截图流程可用 |

故障仅作用于测试 Feedback 请求、专用服务测试条件或独立验收数据；不能关闭 TLS 校验、改系统安全策略或影响现有截图上传。无法安全制造的一项记录精确 BLOCKED 原因，不用 mock 网络冒充。

GitHub 201 后 Delivery 丢失返回响应，可复用本轮同一实际部署的真实云端故障证据：原 Issue 被核对后唯一恢复，未知状态不盲目再建。该云端证据不替代以上 App 发起路径；若部署版本变更影响投递/删除，应由服务负责人按实际风险补核对。

## D. 删除和测试数据清理

1. 在断网且 `attempts == 0` 的新测试记录上本地取消：该条不创建 D1/Issue，正文和单条凭证按既有策略清理。
2. 对已到云端的另一条实际记录申请删除；只有原 per-feedback 凭证能授权。状态刷新并发、迟到发送回执不能撤销更新的删除意图。
3. 原投递与删除竞态后内容不得复活。分别取得 D1 正文清除和私有 GitHub Issue 永久删除的实际证据；Issue 关闭不能代替删除。
4. 远端尚未完成时 UI 继续表示删除中/需处理；完成后才标记已删除，再确认本地正文和该 Keychain 项清理正确。
5. 所有真实测试反馈逐条清理或登记未完成义务，包含 report UUID、Issue 身份、申请时间、当前远端/本地状态、负责人和剩余条件。备份/Time Travel 残留按真实服务配置及保留期限准确说明，不声称立即物理抹除所有备份。

## E. 截图主功能隔离

分别在反馈关闭、打开、正在保存、等待网络、服务器不可用时执行普通新的截图收录和点击对照，使用现有已准入路径和测试数据。只验证隔离与可用性，不重新验收完整截图协议、不重复 H 或旧 UNKNOWN。

确认截图 SQLite 与 Feedback-v01 SQLite 独立；反馈网络等待不占主线程；窗口异常/SQLite/Keychain 异常不丢截图；反馈不改变 Chrome 的原目标绑定或上传权限；UNKNOWN 不被重传、复位或转换为失败，吞噬不等同完成。记录五种反馈状态下的实际响应与截图记录结果。

## 结果交付

对每个场景分别给 `MAC PASS`、`CLOUD PASS`、`NOT_RUN`、`BLOCKED` 或 `FAIL`，加准确来源。软件 AppKit/CI 不算真实输入验收；Receiver HTTP 200 不自动等于 D1 完整证明；D1 接收不等于 Issue 创建；Issue 创建不等于开发者处理。

交付最小证据包括：统一 App 身份/签名与包校验、真实窗口操作、report→D1→唯一私有 Issue 的对应记录、诊断冻结对照、网络恢复前后身份对照、删除及仍待清理义务、截图隔离矩阵。材料进入正式交接前经脱敏检查。只有真实原生窗口→D1→唯一私有 Issue、基本断网恢复和隐私删除等要求实际通过，才可宣布 Feedback v0.1 真实端到端完成。

当前这份清单本身不证明上述任何 Mac 场景已执行，也没有设置会话后自动继续的执行器。
