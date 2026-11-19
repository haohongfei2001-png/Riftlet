# Riftlet 1.0.6（44）候选验收

**推广结论为暂缓。** 43 在真实草稿复现了接收后同卡失败而无法找回。44 已修正原卡识别，真实复测尚待 Apple 公证。当前公开 Release、官网和签名清单提供 1.0.5（31）。[Issue #115](https://github.com/haohongfei2001-png/Riftlet/issues/115) · [42 完整原始报告](https://github.com/haohongfei2001-png/Riftlet/blob/fc0b1935eee0fbfc0c583b38670e3c6bcaa3cf2c/docs/releases/1.0.6/RC_REPORT.md)

在专用客机的一次真实点击中，43 将截图提交至原草稿，写入 START 并收起。约 48 ms 后断开客机链路，原图卡显示“Failed to upload file.”及重试按钮。恢复网络后，Riftlet 主动核对仍显示已交给 ChatGPT。检查网页发现，原图与指向同一文件的重试按钮是同一图片卡的直接子元素；草稿文字及原操作均保留。[43 真实服务记录](evidence/guest-a-build43.json)

44 在接收时记住原图、按钮和图片卡的归属。同卡随后明确显示该文件的重试操作时，Riftlet 可通过原操作只读核对。若首见时已经失败，不产生 START。邻卡、已改名复用的卡和旧记录均无法因此获得重传权限。网页回归 262/262、headless Chrome 37/37 通过，并独立验证了 20 个跨版本及 7 个中文双卡场景。[回归结果](evidence/regressions-build44.json) · [归属反例](evidence/independent-overlay-build44.json)

产品源为 `193009d842b460dbff80ee3416954cb087e4160f`。正式双架构 App 的 Developer ID 签名已核验，包内网页程序与受审文件逐字节一致。两个架构的自检与 11 项 Sparkle 工具测试通过。测试 Mac 锁屏时公证工具报告原配置不可用，尚无 44 的 Apple 提交号。两台隔离 Mac 的 Gatekeeper 均拒绝运行尚未公证的 App。[签名检查点](evidence/signed-app-build44.json)

| 验收项 | build 44 源码及签名 App 检查点 |
| --- | --- |
| V1 一次点击及快速双图 | 正式包的登录 Chrome 真实复测待公证。43 的[逐图记录](evidence/v1-host-build43.json)保留原身份。 |
| V2 异常核对与处置 | 44 受控原卡回归通过；44 真实同卡失败后能否通过仓库找回仍待实测。 |
| V3 整理与重启恢复 | 六个发行组件测试场景和三个独立进程的移出、重启、恢复通过。[组件实测](evidence/v3-source-build44.json) |
| V4 界面及权限 | 44 普通安装后的界面、权限与双语标注待实测。 |
| V5 更新 | 44 版本的正式 DMG、从 31、35 的 Sparkle 升级和从 25 保留资料的手工替换待实测。 |
| V6 长期运行 | 44 发行组件核验一千张图，并发收录二十张；普通 App 同候选结果待实测。[负载记录](evidence/v6-source-build44.json) |

正式 CI 按下列 PR 的具体提交运行。后续安装包、实机验收和推广结论在同一 PR 记录。[实现 PR #117](https://github.com/haohongfei2001-png/Riftlet/pull/117)
