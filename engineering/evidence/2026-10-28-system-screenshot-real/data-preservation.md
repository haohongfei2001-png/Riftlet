# 数据与运行保留报告

- 新建独立工作树/分支，正式分支及此前验收工作树均未reset、clean、覆盖或删除。
- 显式candidate使用既定独立数据根；本轮开始时不存在该根，启动后创建SQLite v3。普通App和Web-Acceptance数据库未被本轮二进制打开。
- baseline运行收录1张systemScreenshot，第一次实验6次选择全部拒绝；只读一致性backup确认0 operations后，才停止旧候选并替换为修复二进制。没有迁移回v2或重建队列。
- 修复进程继续同一数据根：保留A，收录B；最终A unknown/visible、B failed/visible，attempt均1。A历史attached和随后invalidated首次观察均保留。
- 最终确认没有prepared/dispatching阶段后，停止本轮候选实例，保留数据库/WAL、原件、私有媒体及两次只读SQLite backup；integrity_check=ok、schema3。没有操作其他Chrome进程或普通App。
- 未删除UNKNOWN/操作/补偿；既有补偿和原图所在旧数据根未修改。该“未修改”依据本轮操作范围，并非声称对所有历史数据库完成前后字节级校验。
- 私有证据目录限制为0700，日志/backup等为0600。公开只提交脱敏摘要及私有证据SHA-256，不提交图片、数据库、完整目标、聊天正文、私有路径或凭据。
- 默认生产、candidate start/completion/safeFailure maps均未改。没有自动ChatGPT send；唯一输入由人鼠标事件走现有正式桥，未使用文件picker替代。
