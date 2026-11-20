# #120 规划进度

2026-11-20（北京时间）。本目录只交付研究/架构/任务，不是新能力已经开发完成。

| 项目 | 状态 | 证据/下一步 |
|---|---|---|
| GitHub基线 | 已读并跟进更新 | main `9fd8ad15`；#117 `cf697d7e`；#119从`f27c2473`更新至 **`e852af39` / build49**，产品`b431931e`已可读 |
| 核心源码审查 | 完成 | C01–C12及f27→e852的23文件增量；49轻量pin/原进程缓存/原卡修复已纳入；最终1.0.7仍需W0复核 |
| 浏览器官方研究 | 完成 | BROWSER_SPIKES；Safari26.2 Navigation API、world与冷绑定gate；Firefox有限原型 |
| Provider研究 | 完成 | PROVIDERS；四核心+四扩展+国内/国际Qwen分开；真实DOM全部待测 |
| 已有网页回归 | L1 PASS | 最新e852：263/263，51.84s，Node24.22.3/Linux；初审f27：263/263，60.79s；独立202为重叠子集，次数不相加 |
| 新Host/真实登录AI | NOT_RUN | 本研究无macOS/登录执行；不能宣传通过 |
| 架构研究checkpoint | 已存独立分支 | `ebff85bef20844c83e6bc0e8c608615a5d402efb`；后续完整文档及独立审查见本分支最新提交/PR |
| 实施/验收工作包 | 已定义 | WORK_PACKAGES W0–W8、ACCEPTANCE、CODEX_HANDOFF |
| 实现启动 | 尚未启动 | 本轮授权是规划；1.0.7收口后由接收交接的Codex执行 |

## 下一实际动作

规划交付完成后，实施Codex执行W0，核对最终1.0.7基线；接着W1冻结实际接口，再并行Host/Provider/QA。不要重开架构研究或读取全部历史，更不要从本规划main快照开发产品。

## 本轮独立挑错已落实

- 删除重复同名ConversationProvider协议，公共接口只以ARCHITECTURE为准。
- commit最终守卫明确draftEpoch/surface/mode/当前上传能力，防同URL切模式。
- 增Safari冷首次nonce建立前的身份gate；事后nonce自洽不能证明点击原对象。
- 同一未明托盘项连击不产生第二次输入；不同图片继续独立处理。

精确规划源码提交、独立review与准入提交由Git历史/PR绑定，避免把本文件自引用SHA当产品验收事实。
