# 存储恢复 findings 独立复核

- 复核人：attachment_audit（不是 `storage.md` 作者）。
- 审查基线：`44f745a15ecb3682a9da0bda17f17a5d9fc1f07e`；日期2026-11-14。
- 方法：逐段读取真实Swift调用链与状态门禁；没有修改源码、库或偏好，没有新原生测试。
- 结论：**两个finding的核心结论通过源码复核；建议方案需保留以下具体边界。** 这不是修复PR或原生GUI验收通过。

## QA-DAT-001：P1成立

已独立确认：

1. `RiftletMain.start:383–404` 的两份纯偏好使用裸 `try`，布局解码/校验或归档解码/校验失败会直接抛出；`rift`始于406，`history`始于525，capture在582之后才构建，因此这条错误会阻断截图、托盘和历史。
2. `RiftConfiguration:280,307,317–327`使`{"fitWidth":0}`必定失败；错误类型/截断JSON同样失败。`LifecycleSettings:17–21`使负值/零失败；缺省/`null`有“关闭归档”合法语义，不应当成坏文件；旧的超出范围的正数按当前代码转换成默认两分钟，这是已兼容的合法路径。
3. 最外层`RiftletMain:250–258`只设置提示，无重入初始化。`initialized=true`在619才设置。
4. `recheckSetup:905–907`、菜单校验`1596–1597`、当前设置保存入口`saveSettings:1627–1628`与旧入口`applySettings:1744–1745`均要求initialized，故设置不能自救。
5. `canOpenHistory`在849只看store，可造成入口看似可点；实际`showHistory:1370–1371`因history=nil直接返回。不是“历史数据没了”，是历史窗口没有构建。

### 最小方案审查

“纯偏好失败→保留原文件→内存默认→继续构建服务”的方向合理，能保留数据库和媒体，并比全局停止更符合公开软件质量。不能把数据库损坏也按同样方式创建空库。

需写入工程任务的限定：

- 保留损坏/无法理解文档的**原始字节**，默认降级不得产生启动时保存、退出时保存或自动格式迁移。
- 当前RiftConfiguration/LifecycleSettings没有显式schemaVersion。不能声称能自动识别所有“未来版本”；应说“当前无法解码/校验的偏好”。
- `RiftConfiguration:61–95,266–279`故意用PresentationValue保留已声明的未知展示值（字符串、对象等）。有效配置中的这些值不能因用户改一个无关设置而被默认值覆盖；整体catch后丢掉这个兼容意图不合格。
- 对语法可读、仅一个几何字段不合法的配置，可在内存中局部采用已验证默认；修复不能把其余合法用户选择一并清空。
- 对完全不可读的原文件，普通保存不得悄悄覆盖；提供明确“恢复默认设置”动作，替换前确保原字节已安全保留。只重置该偏好域，不能触碰queue、source、media、bookmark、UNKNOWN。
- 归档错误建议当前会话关闭自动归档，避免默认两分钟隐藏图；用户明确恢复默认后再采用正式两分钟默认。不要永久改成全用户关闭。
- 读取应先按小偏好文件的合理上限作有界检查；不需要新配置框架。

验收至少覆盖：两份文件单独错误；合法旧正值/关闭语义；当前未识别PresentationValue；只有一个坏字段但其他已选值保留；只读写失败；App原生启动并能看历史/收新图；无隐式输入或UNKNOWN改动。

## QA-DAT-004：P2成立，限定于服务已运行的同源重检

已独立确认：

1. `PrivateAssetImporter.recover:219–227`对已入库副本执行原manifest一致性、大小和完整内容验证后才调用restoreMissingAsset；266–272将不存在副本标missing。
2. `CaptureService.start:139,163`只有从非running启动时执行recover；`recheck:267–275`在running时只attachWatcher/rescan。
3. UI `RiftletMain:920–923`虽然先binding.start/refresh，但`CaptureSourceBinding.start:279–280`幂等；refresh走`reconcile:348`的setSourceDirectory，而`CaptureService.setSourceDirectory:306–308`同源且running直接返回，未recover。
4. rescan中的`CaptureService:473–475`对已存在source key直接continue，不会借扫描新图间接修复原record。
5. 因此“启动确认missing→运行中补回原字节→重新检查”仍missing。**若服务已停止，recheck会start而执行recover；不能泛称所有重新检查永远无法恢复。**报告已给出正常running条件，建议在Issue标题/复现条件保持。
6. `QueueStore.restoreMissingAsset:754–762`根据原operation恢复used/failed/transferring/unknown或pending，不会自行重发；这是应复用的正确边界。

### 最小方案审查

优先为明确的存储恢复重检调用有界的已报告missing/invalid记录验证。不要在每次权限重检、计数刷新或普通目录扫描中全库hash；这会扩大QA-DAT-002成本。恢复必须保留原资产UUID/sequence/source key、原operation及receipt；原bytes不匹配或symlink不得解除missing。

文案证据小调整：`CaptureDiagnostics.missingPrivateCopy:41–42`本身没有承诺“点重新检查修复”，明确“恢复访问后重新检查”的原文位于`recoveryRequired:39–40`、其他存储写失败类别，以及通用故障指南。finding不依赖这条文案承诺也成立，不宜把missing消息引述成它未说的话。

原生仍NOT_RUN；建议保留当前报告的同会话文件补回场景交给Codex，不用额外扩大故障注入范围。
