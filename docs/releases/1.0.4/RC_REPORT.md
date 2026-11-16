# Riftlet 1.0.4 私有候选验收

开发分支为 `dev/1.0.4-consumer`。T00 已核对 [PR #109](https://github.com/haohongfei2001-png/Riftlet/pull/109) 的规划 G `9f10bb1795c6296e94e071bafe4e60a9bb606954` 和 H `2aec10334f16dcc9b57809bd7ba956d03f1565d8`。G 的直接子提交 H 仅更新准入记录。H 与 main `3f8149e2313fd81bbaee5a7bbbdbb1efca2fc81b` 的 Sources、Resources、官网及 stable.xml 一致。公开包为 1.0.3 (25)，其 SHA-256 和二进制身份见 [BASELINE](BASELINE.md)。

1.0.3 旧相机用例保留原始 FAIL（`trayCameraObscured`）。[原始 42 项原生报告及截图散列](evidence/native-runs.json)。普通首次引导的红关闭未写入 deferred；旧版 review 再启动不能验证普通启动行为。候选阶段的源代码、原生 GUI、公证、安装升级及真实服务分别记录。
