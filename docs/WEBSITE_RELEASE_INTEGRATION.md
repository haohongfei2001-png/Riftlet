# 官网发行接入规格（仅工程准备）

本文件不修改已批准的站点视觉，不上线下载、不新增商业定价或订阅。当前站点的演示不等于实际附件能力验证。

公开下载入口启用前必须有：批准的发布版本和更新说明、公开支持范围、已验收的Developer ID/公证产物、匹配源码/架构/完整包SHA-256、可信下载位置、隐私及支持链接、明确回退与旧数据库兼容边界。所有链接以最终审核产物为准，不猜测URL或把CI临时artifact当长期发行源。

建议下载元数据由发行清单导出：version、build、sourceCommit、architecture、minimumOS、archiveSHA256、archiveBytes、releaseNotesURL、downloadURL、publishedAt。静态页面显示实际可用架构；没有合格包时保持“尚未公开发行”，不放空链接或模拟下载成功。

版本文案优先说明正常截图→一次点击→附件接收开始收起→继续附加；不承诺所有AI网站、无限文件大小、永不失败、自动发送或自动清理。链接到 USER_GUIDE / PRIVACY_AND_DATA / SUPPORT 的正式发布副本。

发布前仅在已批准的preview/候选环境合并验证下载HTTP状态、内容长度/哈希、错误反馈、键盘操作及窄屏文案；不为普通中间commit重复部署。上线和商业决策单独批准。
