# G4 原草稿恢复验收

1. 读回 PR #124、Issue #120、冻结产品提交、DMG 和实际 CI。在独立检出中实施，保留用户工作树。变更产品源码时提升构建号，并将旧候选成绩留在原版本名下。
2. 在私有资料库用 SQLite 的一致性只读备份，核对原图、asset、operation、invocation、输入次数、START 和目标。网站失去原 Document 后，只能独立审计该历史样本。
3. 实站仅使用经签名、进程出生身份、原窗、原标签、原文档、编辑器和已登录状态共同确认的专用 Temporary Chat。对合法文件使用正常产品入口。若出现真实响应，结合原文件全字节和原操作归因。仅有文件名、status 0、移除节点或全局提示时分别记录可观察事实。
4. G4-A 保存原卡的具名失败和带错误收据的旧操作。G4-B 需要真实服务器 4xx、原卡消失及独立书面等价性裁决。受控服务器的响应只能记录为 CONTROLLED_GATEWAY_RESPONSE。G4-C 需要在结果未知时明确提示潜在重复，并在新的用户选择前保存原状态。
5. 已有原卡、身份不匹配、只读检查不确定或未完成明确确认时，在文件输入前停止。记录原草稿、原文件及受控新选择的 AppKit mouseDown、clickBindingID、operation、invocation 和独立 START。保持已存在的附件，发送和表单提交计数均须为零。
6. 对比两个合格时点的独立备份。审计旧操作和收据内容、新增操作数、attempt、原图像素、实际网页 input/change。关闭专窗时使用创建记录，核对原窗口清单，结束私有进程与监听器。
7. 正式发布需要同一候选 G4-A 或经认可的 G4-B，以及 G4-C。主线、堆叠 PR、双架构 CI、Developer ID、公证、staple、独立安装和升级渠道分别核验。任何必需证据缺失则继续保留 Draft 和公开稳定版本。

## 在同一份 build 60 上恢复验收

先核对构建号 60、产品 `711cee3a`、私有 DMG 摘要 `5a934119d6e65cbe82a62f5f208a2b95a200fa0cf170225ccd4e9016b1c0b54e` 与独立安装回执。新的专窗需要创建回执、唯一原标签、浏览器出生身份、准确的 Temporary Chat 和原编辑器。普通浏览器的窗口、系统前台以及 DOM 可见性应在同一时段相符。原生窗口仅标记 visible、DOM 只有焦点，或后台能读到账户，均不足以开始投递。

取得可用会话后，按同包批量路径完成两款浏览器的冷暖、双图 3/3 和原文选区。G4 分别记录输入、请求体全字节、唯一请求、原卡、重新选择的 AppKit 事件及两次一致性备份。使用专用画像的 SQLite backup API 生成两份独立文件，并把原图、原始日志和全部签名 URL 留在私有资料库。具名错误用 `verify_recovery.py`；无明确错误的 UNKNOWN 用下列只读命令。网页事件和真实用户选择由独立观察回执提供。

```sh
python3 -B Tests/PreClickLease/g4/verify_unknown_recovery.py BEFORE.sqlite AFTER.sqlite ORIGINAL.png OLD_OPERATION_UUID NEW_OPERATION_UUID
```

G4-B 的上游 4xx 需要独立于网站提示和创建请求的证据。其正式等价裁决与 G4-C 的知情恢复分别签收。候选通过后才按正式主线治理流程整合 #119、#123、#124 的已审范围，重新核验整合树与已测试产品源，并以最终镜像更新 GitHub Release、官网和稳定更新源。
