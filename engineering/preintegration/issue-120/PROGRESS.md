# Issue #120 · 隔离准备

正式产品基线为 WAITING_FOR_107_BASELINE。远端 main 为 9fd8ad15（公开 1.0.5 build 31）。#119 仍是 Draft，已继承 #117 的 cf697d7 和规划审查的 e852af3，现产品 0dc6780、独立审查 f7287e0、准入 c764246。RC 53 的 DMG SHA-256 为 9458479641bde6147de37fda8b873507b2a312a153a76c08e166e50903583dee。五项 CI 通过；登录草稿 G1、G2 及 G4 真实失败恢复仍缺同包实测。详见 [上游验收记录](https://github.com/haohongfei2001-png/Riftlet/pull/119#issuecomment-7028325810)。

此分支从 c764246 建立独立临时工作树，仅供 #121 明确允许的接口验证、夹具与能力探查。contract/check.sh 从该树原有 RiftletCore 源码编译并链接，独立 JS 测试运行在 Node。候选资源身份、同步发送轻量 pin 与异步接收的接口边界、按历史原操作只读定位在此验证。App 接线、旧数据库迁移和新版签名须在实际主线纳入 1.0.7 后做。未拷贝规划准入文件。

宿主、Provider、验收夹具分别写入此目录下 hosts、providers、matrix。生产代码、分支准入与发布渠道仍由正式集成处理。新候选同包 L3 核心 0/16，暂为 PARTIAL。

- d9af149 已链接真实 build 53 的 Core。独立审查指出旧 pin 回包、能力全未知及伪散列仍可通过夹具边界。本次加入发前能力检查、原回执的 native generation/出生身份/ProviderRoute 比对及缺字段反例；设置授权检查仅用于显式设置。读者固定持久操作、原 invocation、原图哈希，只暴露 observe。Swift 与 JS 专项均通过，属于隔离验证。

- eed8c99 之后加入可重跑的实库专项：在独立临时目录通过原 QueueStore 的一次性 dispatch 和 checkpoint 接口登记一条模拟操作。重新打开 SQLite 后，原 reader 只进行一次核对，结果保持 UNKNOWN；错 invocation、未要求原稿核对及同 revision 不同资源均被拒。源程序与生产 SQLite 布局未改。baseline.py 只读复查远端祖先、签名候选所属 PR 检查及公开版本。

- 8f674c3 的 SQLite 重开与原目标正反例经非作者实际复跑。另在同一台 arm64 Mac 上以 x86_64 编译并通过 Rosetta 执行同一专项；CLT 链接时报告兼容性静态库缺 Intel 切片，测试程序仍成功链接和执行。物理 Intel 及新产品双架构 CI 未运行。macOS 27 上可用 Developer ID Application 身份 1 个，已找到官方 notarytool 和 stapler；此阶段没有新产品包。
- 从 #121 仅移入原始规划矩阵供无网络、浅克隆重放。该 JSON SHA-256 为 35318faf7eacecf80972a7e47eaca173af15682f7ead047198e79da44cc30658，仍是规划输入。实测结果由 matrix 单独生成。

- W5 已加入 40 格矩阵、逐格 case 查询及同包记录核验。3 个网页模拟子项及 Chrome/Edge 各 1 个真实二进制的受控页面子项留存原始 TAP。两个环境各自确认 31 次 setter、31 次 change、零发送；都没有签名产品入口，不能计 L2/L3。集成人重跑 7 组回放正反例，生成的矩阵与提交内容逐字节一致。

- W3/W4 隔离准备已覆盖 8 个新 Provider 的匿名入口。Claude 返回 403，DeepSeek 转至账号页；Gemini 的只读探针在正式匿名 /app 识别到原编辑区和同属的上传入口，未见可归属文件输入。国内千问与国际 Qwen 分开记录。受控站点独立复核修复了响应式图片错认、摘要等待中换卡、非原表单控件，以及重复 pin 再次进入 setter。最终本地运行 4 次完整 setter/change、另 1 次中断后保持未知，零发送、零外部请求。具体见 providers/README.md 与受控回执；后续真实站点写入仍待同包。

- W2/W6 的首批能力收据覆盖实际 Chrome、Edge、Brave、Safari、Firefox 的本地页面。Chrome/Edge 独立进程可按 PID 核对窗口数量；Safari 普通客机验证了同 URL 的导航反例。Brave 的默认 Shields/原稿写入与 Firefox 的无扩展目标、原卡证明未通过产品验收。客机 A 首次脚本权限请求未获得可验证结果，已正常关机。Host 字典、签名、探针身份与证据等级分别记录在 hosts/。

- [Draft PR #122](https://github.com/haohongfei2001-png/Riftlet/pull/122) 已建立，比较分支固定到 #119 准入 c764246，差异只含本轮准备材料。合格 main 到位后在同一 PR 切换基准与产品接线，无需另开实施 PR。
- 独立 C 客机经正常 Apple Events 授权实测，Safari 27.2 冷捕获的原 tab 描述符是可变索引；关掉原标签后该引用命中另一张同 URL 的页面。共用契约现对单靠索引或已有网页见证的冷点击在 capture/enqueue 前拒绝。这个结论针对所测定位方式，其余 Safari 绑定策略仍需证明。

- C 还独立验证了 Brave 在系统正常授权后可读取原生窗口/标签 ID，默认的页面只读 JS 返回错误 12；Safari 正常开启脚本时能读页面标记，恢复默认后再次返回错误 8。Safari 原索引错投的负例在三种状态均复现。两项 Safari 设置已还原，两个临时探针授权均已撤回，客机正常关机，测试展示窗为零。[C 收据](hosts/guest-c)
