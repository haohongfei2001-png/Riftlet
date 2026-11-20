# Issue #120 · 隔离准备

正式产品基线为 WAITING_FOR_107_BASELINE。远端 main 为 9fd8ad15（公开 1.0.5 build 31）。#119 仍是 Draft，已继承 #117 的 cf697d7 和规划审查的 e852af3，现产品 0dc6780、独立审查 f7287e0、准入 c764246。RC 53 的 DMG SHA-256 为 9458479641bde6147de37fda8b873507b2a312a153a76c08e166e50903583dee。五项 CI 通过；登录草稿 G1、G2 及 G4 真实失败恢复仍缺同包实测。详见 [上游验收记录](https://github.com/haohongfei2001-png/Riftlet/pull/119#issuecomment-7028325810)。

此分支从 c764246 建立独立临时工作树，仅供 #121 明确允许的接口验证、夹具与能力探查。contract/check.sh 从该树原有 RiftletCore 源码编译并链接，独立 JS 测试运行在 Node。候选资源身份、同步发送轻量 pin 与异步接收的接口边界、按历史原操作只读定位在此验证。App 接线、旧数据库迁移和新版签名须在实际主线纳入 1.0.7 后做。未拷贝规划准入文件。

宿主、Provider、验收夹具分别写入此目录下 hosts、providers、matrix。生产代码、分支准入与发布渠道仍由正式集成处理。新候选同包 L3 核心 0/16，暂为 PARTIAL。

- d9af149 已链接真实 build 53 的 Core。独立审查指出旧 pin 回包、能力全未知及伪散列仍可通过夹具边界。本次加入发前能力检查、原回执的 native generation/出生身份/ProviderRoute 比对及缺字段反例；设置授权检查仅用于显式设置。读者固定持久操作、原 invocation、原图哈希，只暴露 observe。Swift 与 JS 专项均通过，属于隔离验证。

- eed8c99 之后加入可重跑的实库专项：在独立临时目录通过原 QueueStore 的一次性 dispatch 和 checkpoint 接口登记一条模拟操作。重新打开 SQLite 后，原 reader 只进行一次核对，结果保持 UNKNOWN；错 invocation、未要求原稿核对及同 revision 不同资源均被拒。源程序与生产 SQLite 布局未改。baseline.py 只读复查远端祖先、签名候选所属 PR 检查及公开版本。
