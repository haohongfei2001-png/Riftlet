# 继承原型的实际失败与实施裁定

证据来自 [82项最终浏览器运行](evidence/20261106-browser-02/RESULTS.md)。保留用户指定的最终HTML原件和源文件，不覆盖原型、不修改Sources。以下13条失败必须与界面一起交付，不能把原型内存状态当真实配置保存成功。

这里是**原型及其与main的差异**，不代表在已安装App中发现同样缺陷。原生实现以 [CONFIGURATION-MAP](CONFIGURATION-MAP.md) 的源码事实和 [IMPLEMENTATION-HANDOFF](IMPLEMENTATION-HANDOFF.md) 的明确合同为准，不需要后继自行重新设计。

| 用例 | 实际证据 | 后续AppKit必须采用的行为 |
| --- | --- | --- |
| X1 | 暂停ON写失败后，运行paused=true、最后确认persistedPaused=false；外观成功却令issue=null。 | 按收录偏好域保留保存未确认事实；无关外观成功不清错。当前已暂停与保存失败同时可见。 |
| X2 | 隐藏ON写失败后，hidden=true/persistedHidden=false；外观成功同样清错。 | 可见性运行态、最后确认保存意图和该域错误独立保留。当前隐藏不意味着已保存，系统收录不受影响。 |
| X3 | 入口关闭失败后有效entryEnabled=false，但没有已确认的持久意图/未确认域可独立观察。 | 保留最后确认状态和保存未确认结果；不要因有效OFF推断磁盘OFF。当前main保存的chmod后置失败使“磁盘必旧”也不成立。 |
| X4 | 文件读取授权成功清除仍未保存的暂停错误。 | 权限恢复只更新来源/权限域；保存错误保留。错误显示可以聚合，底层不能共用一个可任意清空的issue。 |
| X5 | 布局草稿保存失败，外观成功后config仍72/draft96但issue消失。 | 布局域错误与草稿保留，直到该域成功或用户明确放弃；其他偏好不能清除它。 |
| X6 | 失败后前往处理只有开关，没有保留停止方向的“重试保存”动作。 | 使用同方向幂等命令重试当前意图；不能要求先恢复收录/显示/启用再停止。正常成功状态不额外增添按钮。 |
| X7 | 5个原型高级旋钮对应main不生效的兼容字段：lineWidth/lineExtension/screenPadding/inwardDistance/reducedMotionDuration。 | 数据原样保留，移至只读兼容说明，不显示会“生效”的旋钮；其余有效个性化全部保留。另2个兼容字段已无原型控件，仍不可删除。 |
| X8 | 清空后出现撤销toast，可在网页恢复样本；main.clearVisible没有批量撤销命令。 | 按已定清空范围收起可见队列、保留文件/历史/附件；不承诺或临时新增成组恢复后端，不开放UNKNOWN重传。 |
| X9 | 原型“使用主显示器”写ID/UUID=null；main会解析并保存选择当时具体屏幕身份。 | 显示器选项保存真实NSScreen ID/UUID；不是新增永久follow-main策略。断开只回退运行落点。 |
| X10 | 放弃失败布局草稿后draft=config，write issue仍残留。 | 用户明确放弃该草稿时清除此域错误；其他未解决错误不得一起清掉。 |
| X11 | 历史sheet初始焦点在原图按钮；Shift+Tab直接到末按钮，跳过前方两个select。 | 使用原生key-view链，所有可交互控件均可到达，sheet焦点不逃逸；不是只列button/input/textarea。 |
| X12 | 自定义归档输入2.5h后直接单击保存，仍24h；change重绘替换目标，使首次click丢失。 | 编辑期间稳定保留控件与first responder；失焦只结束编辑，不提交/全量重建视图；首击保存必须提交当前文本。 |
| X13 | 自定义归档输入后直接点击关闭，没有出现未保存sheet。 | 关闭动作先结束编辑并读取草稿，再在同次动作中显示确认；不可要求点第二次。 |

每项原始状态见 `evidence/20261106-browser-02/X<ID>-failure.json`，原始截图见同目录 `screenshots/X<ID>-FAIL.png`；精确链接均在 [RESULTS.md](evidence/20261106-browser-02/RESULTS.md)。X1/X2/X4/X5/X10属于同一错误域建模根因，X12/X13属于同一失焦重绘根因，不能把13个用例说成13个独立产品事故。

## 不靠浏览器模拟抹平的差异

- minimumHitWidth/Height 在main是行布局尺寸，不保证整个空白矩形都可点击。后续控件应准确说明行尺寸，保留数值而不改鼠标命中架构。
- CONTROL-CENTER-DECISION的“失败保留原状态”概述不适用于三个停止方向；以INTERACTION-SPEC §3.1、CONFIGURATION-MAP §4的细分行为为准。
- 外观覆盖、登录启动是既有设计中的待实施能力，main没有对应后端；具体实施规则见handoff。不会因为缺后端而偷偷删除个性化，也不会把HTML模拟成功当完成。
- 引导的onboardingCompleted只用于演示；真实升级判断仍兼容现有presented标记，不能强制升级用户重复引导。
- 独立视觉复核C5还发现：暂停与隐藏同时开启时，隐藏行仍写“收录继续进行”，与暂停事实冲突。这是额外视觉文案发现，不追改82项结果；原生该行固定使用“只隐藏边缘微图，不改变收录设置”，实际是否收录由主状态准确说明。
- Chrome授权/脚本禁用、用量检查失败、IME、VoiceOver等没有在这份HTML中完整可触发；必须在原生阶段验证，不追加合成PASS补数。

本轮结论：**可供用户最终评审的完整设计候选，带明确已知原型差异；不是全绿交互原型或原生产品验收完成。**
