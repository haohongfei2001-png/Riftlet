# Issue #120 · 隔离准备

正式产品基线为 WAITING_FOR_107_BASELINE。远端 main 为 9fd8ad15（公开 1.0.5 build 31）。#119 仍是 Draft，已继承 #117 的 cf697d7 和规划审查的 e852af3，现产品 0dc6780、独立审查 f7287e0、准入 c764246。RC 53 的 DMG SHA-256 为 9458479641bde6147de37fda8b873507b2a312a153a76c08e166e50903583dee。五项 CI 通过；登录草稿 G1、G2 及 G4 真实失败恢复仍缺同包实测。详见 [上游验收记录](https://github.com/haohongfei2001-png/Riftlet/pull/119#issuecomment-7028325810)。

此分支从 c764246 建立独立临时工作树，仅供 #121 明确允许的接口验证、夹具与能力探查。contract/check.sh 从该树原有 RiftletCore 源码编译并链接，独立 JS 测试运行在 Node。候选资源身份、同步发送轻量 pin 与异步接收的接口边界、按历史原操作只读定位在此验证。App 接线、旧数据库迁移和新版签名须在实际主线纳入 1.0.7 后做。未拷贝规划准入文件。

宿主、Provider、验收夹具分别写入此目录下 hosts、providers、matrix。生产代码、分支准入与发布渠道仍由正式集成处理。新候选同包 L3 核心 0/16，暂为 PARTIAL。
