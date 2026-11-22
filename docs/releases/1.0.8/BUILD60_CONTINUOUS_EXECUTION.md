# Build 60 持续验收记录

## 2026-11-23 · 恢复现场工作

产品源码为 `711cee3a1c7033ce4925082a83099b00da7087c6`，本轮起点为 `921c1a676b83d5a4585b9d643be300592cfb2ee3`。重新计算私有 DMG SHA-256 得到 `5a934119d6e65cbe82a62f5f208a2b95a200fa0cf170225ccd4e9016b1c0b54e`，独立安装回执 SHA-256 为 `6dd1c3b09e02b307862cc5759d83ea25f539bcf55cace1090e3539c46b775736`。ARM64 / Intel 同源 CI 均成功。PR #124 为 Draft，Issue #120 打开，公开版本为 1.0.5（31）。[签名与同包实站基线](RIFTLET_1.0.8_FINAL_RELEASE_REPORT.md) · [最终源码 CI](https://github.com/haohongfei2001-png/Riftlet/actions/runs/45045026977)

| 工作 | 已取得的证据与当前执行 |
| --- | --- |
| 原始 GUI 回执 | 已重读七次环境准备的逐次结果和独立裁决。两次 Edge 到达已登录草稿，七次都停在文件输入前。 |
| 当前环境 | 新读数显示系统前台已从 UserNotificationCenter 移到 Codex。显示器已醒、会话已解锁，验收宿主位于当前控制台用户的 Aqua 会话。只读取原生界面元数据。 |
| 浏览器验证 | 一名 GUI 执行者负责 Chrome、Edge 和专用草稿。验证正常激活与 AX/WindowServer 边界，维护唯一专窗和创建回执，等待与实站投递分别记账。 |
| 持续监督 | 在独立检出开发只读监督器、状态变化记录、持久化任务状态和对实际验收入口的串行调度。 |
| 恢复审计 | 复核原生点击、持久化记录、页面、界面和双快照验证，三个真实故障库各自复制后验证。 |
| 发行准备 | 在独立分支演练合并树，核对官网、签名更新源和应用内更新流程，准备双语发行说明。 |

当前没有需要用户执行的操作。状态变化后只在 PID、原窗、原标签、可见性、前台、登录、编辑器及上传入口同时得到实证时开始对应站点验收。待完成的发行门槛为同包 G1/G2、G4-C、G4-A 或经独立裁决的 G4-B、正式准入、合并、公开分发及升级验证。

## 05:56（上海）· 封存库和恢复链

三份独立的 build 59 故障库副本均完成了输入前取消、进程重启、显式新选取、一次受控附加、唯一 START 和迟到回执检查。每份原库重新计算的 SHA-256 都与封存值一致。已检查七个组件和十五项断言，逐项标明源码、SQLite 或无界面网页证据。签名 App 的实站 G4-C 仍待执行。[逐项审计](evidence/build60/recovery-architecture-audit.md) · [三组双快照哈希](evidence/build60/recovery-architecture-audit.json)

Edge 两次只读观察读到同一已登录专用草稿可见并聚焦。紧接投递前，前台回到 UserNotificationCenter，当前 Space 两款浏览器的可见 WindowServer 窗口均为零。对话框的用途未得到确认。验收尚未因此产生产品点击或文件输入。QA 监督器已由当前 Aqua 会话的 launchd 启动，初始状态只读。恢复后继续使用原创建回执、相同原草稿和独占 GUI 锁。目前无用户操作。

## 05:58（上海）· HTTP、系统大图与正式发行准备

C2 已从自有的非激活窗口取得 macOS 系统 PNG。它带有系统截图标记，2880 × 2816 像素、23,233,638 字节，九个中心像素样本相符。捕获前后的前台 PID 一致，原图保存于私有验收库。后续由同包实站测试记录实际输入字节、唯一请求、HTTP 状态和原卡变化。C1 的本地原生 XHR 对照观察到未过期时 201、自然过期后 403，并核对服务器收到的全文件。历史网站回执仅有上传地址摘要，仍没有当前上游授权期限。[C2 原图收据](evidence/build60/large-system-screenshot.json) · [五组 HTTP 对照](evidence/build60/http-expiry-control.json) · [OpenAI 单图限制](https://help.openai.com/en/articles/8555545-uploading-files-and-audio-to-chatgpt)

发行预备分支已从实际 main 核对至冻结产品源码。预演合并树与签名源码树完全一致。对当前公开更新源与 1.0.5（31）下载包分别复验 Ed25519，官网两处下载入口指向该包。独立签名更新工具回归 11/11。正式放行依赖 G1、G2、G4-C、G4-A 或取得独立裁决的 G4-B，以及适用于该主线差异的非作者准入。当前不需要用户动作。[发行树和签名检查](evidence/build60/release-preparation.json) · [双语说明草稿](RELEASE_NOTES_DRAFT.md) · [预备分支](https://github.com/haohongfei2001-png/Riftlet/tree/codex/release-1.0.8-build60-staging)

### 门槛通过后的发布次序

1. 在预备分支复核实际 main、冻结源码和候选树，取得非作者原文审查，用直接子提交仅写入准入文件。运行 `python3 -B scripts/verify-mainline-composition.py HEAD`，在正式 PR 上核对原生、双架构及反馈检查和两父合并树。合并后再核对真实 main 的父提交和 push CI。[正式主线规约](../../MAINLINE_GOVERNANCE.md)
2. 对已进入 main 的受审发行提交创建正式标签。发行归档采用签名公证回执中的原 DMG 和同包 SHA-256。发布前先用 `gh release create v1.0.8 --verify-tag --draft --notes-file "$notes" "$archive" "$checksums"` 准备完整草稿，核对附件后将其发布为不可变 stable Release。用于对外的双语正文取自审定后的说明。
3. 在冻结签名工作区运行 `RIFTLET_APPCAST_GH_AUTH=1 python3 -B scripts/release-appcast.py prepare --tools "$sparkle_bin" --workspace "$signed_workspace" --output "$new_feed"`。更新源要求标签位于 main，且相对已签名源码只容许准入文件差异。官网和生成的完整签名 XML 走常规 PR，复核 Pages 实际字节与现行支持矩阵。[Sparkle 发行流程](../../release/IN_APP_UPDATES.md)
4. 在官网和 stable feed 生效后，运行 `python3 -B scripts/release-appcast.py verify-public --receipt "$signed_workspace/formal-dmg/dmg-receipt.json"`。独立下载、安装并验签，另用隔离的 1.0.5（31）副本操作实际应用内更新并核对库与版本。
