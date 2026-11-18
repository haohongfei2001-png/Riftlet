# 默认 Edge 与 Riftlet 1.0.5（30）实机验收

默认账户的 619、620 已通过普通微图进入同一原草稿。两笔存储写入成功，产品 START 均缺失，ChatGPT 处理终态均为 UNKNOWN。[双图实测](PAIR-619-620.md)

下表保留点击前封存的源码、包、页面与早期 CI 证据。

| 文件 | 范围与边界 |
| --- | --- |
| [edge-signature.json](edge-signature.json) | 官方包克隆演练、实际 516 项 FinderInfo 修复回执、默认 Edge 当前原严格验签成功。演练与实际安装修复是不同阶段。 |
| [default-temporary-page.json](default-temporary-page.json) | 保留旧目标原生 -1728；新默认配置独立临时窗口的常量脚本、账户菜单/登录按钮及编辑器/入口结构投影。原 prompt-textarea 负例保留；四个隐藏 input 不授权任意选取。 |
| [source-review-and-repair.json](source-review-and-repair.json) | G1 两个 P1、G2 修复、独审及 24+4 离线用例。审查者也是本证据编写者，未实现产品。 |
| [signed-package.json](signed-package.json) | G2 1.0.5（30）隔离 ARM64 Developer ID 包、源树、原件哈希与 11 份签名日志。原签名路径当前严格验签成功；staged 副本因 Finder 元数据失败，不能混算。未公证、未运行 Gatekeeper。 |
| [ci-f823bcd-snapshot.json](ci-f823bcd-snapshot.json) | f823bcd 准入子提交、实际测试合并父/树与一次五任务状态快照：两项准入成功，其余三项运行中。不是终态报告。 |

原件保存在本机受限目录，公开内容只有必要投影、长度和哈希。未复制账户名、私聊、原图、数据库、进程/窗口/标签原 ID、Cookie、令牌或 FinderInfo 原值。Default 仅表示已有配置参数；用户提供的“已登录”背景与账户菜单/未见登录按钮的实际观察分开记录。

G2 为 8ac2bf1c7129763fce3a1d3ccd1a581e08848df2，树 ba57293b4c9e8d00dd95f9f4636f467bca24c6a3。H 为 f823bcde3923aaf170a6844d7a027793747a9c29，只改准入 JSON。实际 PR 测试合并 5b6e3c663b827a4ad234840564ac8b64c82771ab 的有序父为基线 3f8149e2313fd81bbaee5a7bbbdbb1efca2fc81b 与 H，树与 H 相同。来源关联不能替代实际 XCTest、产品点击或商业服务终态。

## 普通 App 启动及点击前读回

同目录换入的 Current 安装副本通过 Developer ID 及严格验签。LaunchServices 启动了对应进程，隔离队列中的 13 笔历史操作与 22 张原图完整。临时草稿已接受中性基线图 621，并读回一张命名附件、完整正文以及从第 61 个 UTF-16 单元开始的 14 单元选区。编辑器未持有键盘焦点。这份读回在 619、620 两次产品点击之前取得。[运行包与升级](installed-runtime.json) · [草稿读回](prepared-draft.json)

准入提交 f823bcd 的四项检查通过。ARM64 的前序测试将鼠标留在微图上，正好触发后续场景的悬停保护，五个动画场景中四个失败。4206ac1 修正托管测试的指针清理，保留产品悬停逻辑和五个场景的断言。[五项 CI 终态](ci-f823bcd-final.json) · [鼠标位置与失败场景](hosted-cursor-fix.json)
