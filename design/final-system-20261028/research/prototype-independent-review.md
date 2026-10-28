# 交互原型非作者审查

审查日期：2026-10-28。范围为本次设计目录的 [app.js](../prototype/app.js)、[model.js](../prototype/model.js) 与 [APPKIT_SPEC.md](../APPKIT_SPEC.md)。审查者没有编写或修改 app.js / model.js；`windows.js` / `windows.css` 是审查者负责的窗口稿，不计入本次非作者审查。

**结论：本次发现的四组主要问题已经由原型作者修复。两项原始 VM 复现已在下列最终字节上重跑并通过；其余修复完成定点源码复核，本次范围没有遗留阻断项。** 这是合成设计原型的控制逻辑审查，不是浏览器物理指针、系统输入法、AppKit、真实截图上传、macOS CI 或产品发行验收。

## 1. 版本与方法

| 对象 | SHA-256 |
| --- | --- |
| 初次复现问题时的 app.js | `bcbae8e3c8b823b7f084c3ea1a6c5edf17409a03a09a63998e54e53ef21b5f3b` |
| 修复后复测 app.js（含最终编号AX owner调整） | `21b5868b8acc597bea6a7af2e07f8aa1b540d4e513216427819767423cc57dc4` |
| 修复后复测 model.js | `04f8d69fd775d5e75dbf090bd7473f4b42d7d803e3d1dac75f5526044039cc01` |

两次复现均直接读取实际文件，在 Node VM 中执行 model.js 与 app.js 的控制函数。截取点为首个 `document.addEventListener('click'`；保留其前的真实状态、操作与控制函数，通过临时暴露私有函数驱动场景。定时器、DOM 和纯渲染出口使用内存替身，不修改产品文件；第二项保留真实 `refreshWindow` / `saveDraft`，仅替代窗口 HTML 渲染器和 DOM 写入。没有为此安装浏览器、测试框架或运行正式工程。

若后续修改改变上述控制文件的语义，本记录只证明所列字节，不自动覆盖新的版本。窗口视觉及浏览器操作检查由另一位作者对本审查者的窗口文件另行完成。

## 2. 主要发现与修复结果

### P1：旧选择的定时器能够启动后来的一次选择

原 `queueStart` 仅捕获 asset ID。先接受自动开始的选择 A，立即取消，再对同一图建立手动开始的选择 B；旧 A 的 900ms 定时器仍能启动 B。原完成定时器也只以 asset ID 判断，并在执行时读取可变的场景状态，存在跨 attempt 完成的同类风险。

作者修复：`Model.token` / `matches` 同时绑定 `id + selection + attempts + target`。开始回调捕获原选择 token；`Model.start` 校验后递增 attempts，再为吞噬与完成回调捕获 operation token。完成回调使用开始时确定的 outcome，并要求同一 token 且仍处于 uploading。

**原始复现重跑：通过。**

1. `model.add()` 后 `selectAsset(id)`，得到选择 token：selection=2、attempts=0、target=`SIM-DRAFT-1`。
2. 调用 `cancel-waiting`，将演示结果改为 `manual`，再次 `selectAsset(id)`，得到 selection=5。
3. 只推进已排队定时器至 900ms；没有发送手动开始信号。
4. 修复前实际为 uploading / inputCount=1；修复后实际为 **waiting / inputCount=0**。旧 token 未能授权新选择。

此结果证明本原型不再因该旧定时器路径产生模拟输入，不证明真实浏览器 ACK 的正确性。

### P1：移除 FIFO 队首后后续选择停滞；隐藏后仍可开始

原 `item-remove` 移除正在等待的队首 A 时，模型把 B 提升为 active，控制层却没有为 B 调度，造成队列停滞。隐藏裂缝原先仅改变视图，仍保留等待输入的选择及其定时器。

定点源码复核：

- `item-remove` 在 `model.hide` 后调用 `resumePrepared`；只调度模型已经提升的 active，不重新选图或改变 FIFO。
- `toggleHide` 和设置的 hidden 路径均在隐藏时执行 `cancelPrepared`；等待选择回到未输入状态。
- `beginUpload` 在开始前重新检查 token、原目标、当前上下文、辅助窗口、hidden 与权限。目标或可见性改变时取消原选择，不转投；取消后再处理队列中仍合法的原选择。
- `Model.restore` 仅允许未开始过的 removed / archived 条目；UNKNOWN、succeeded 和已开始操作不通过历史恢复为可输入截图。

状态：**已修复，源码复核通过。** 未把源码阅读记作额外运行测试。

### P1：后台刷新窗口覆盖未保存文字及 IME 组合

原 `refreshWindow` 在收录、开始、完成等后台事件中直接重建窗口。若 120ms 草稿保存尚未执行，或者正在输入法组合中，DOM 内的新文字会被旧 `s.feedbackDraft` 覆盖；原组合节点被移除也可能丢失相应的 compositionend。

作者修复：反馈窗口在 `composing` 时只设置 `pendingWindowRefresh`；非组合状态在替换 DOM 前 `saveDraft`，记录并恢复编辑器焦点与 selection。compositionend 保存后再执行延后的刷新；切换、关闭窗口在组合期间不拆编辑器，正常关闭先保存草稿。

**原始复现重跑：通过。**

| 时点 | 编辑器内容 | 状态内草稿 | DOM 替换次数 |
| --- | --- | --- | ---: |
| 开始，组合输入尚未提交 | `saved + newest IME text` | `saved` | 0 |
| 组合期间调用真实 `refreshWindow` 后 | `saved + newest IME text` | `saved` | 0 |
| 结束组合并再刷新后 | `saved + newest IME text` | `saved + newest IME text` | 1 |

修复前第二行编辑器被替换为 `saved`；修复后组合节点未重建，提交后新文本被保存并用于重建。该 VM 检查没有模拟具体系统输入法、原生焦点或候选词面板。

关闭/重开、主动保存待发送、取消、删除的源路径也已复核：本页状态独立于窗口 DOM；保存后报告状态为 queued、清空当前草稿；取消仅改为 cancelled；删除需要第二次确认。日志明确是本页合成待发送，不显示真实云端成功；无网络发送路径。

### P1：返回同一草稿生成新目标 ID，绕过 UNKNOWN 原目标锁

原上下文切换每次产生新的时间戳目标 ID。ChatGPT → 备忘录 → 相同 ChatGPT 草稿会被原型当成新目标，导致旧 UNKNOWN 不再阻断该草稿；附件投影也没有按目标过滤。

定点源码复核：`contextChanged('chat')` 固定使用 `SIM-DRAFT-1`，其他上下文独立命名；切换只取消尚未输入的选择，已经开始的原操作继续保留。`queueStart`、`beginUpload`、`Model.start` 均检查同一 target 的 UNKNOWN。`renderAttachments` 只投影 `a.target === ui.contextId` 的已开始资产；旧 UNKNOWN 保持 hidden 且不能从历史恢复。

状态：**已修复，源码复核通过。** 原型只包含一个普通聊天上下文；这不是对真实浏览器多对话目标识别的实现或验收。

## 3. 同轮小项的定点复核

| 发现 | 当前修复 |
| --- | --- |
| 预测值只抬升玻璃，没有提前抬升相机线条 | `glyph=Math.max(glyph,ui.prediction)`；玻璃仍独立响应 |
| 展开中打开 Reduce Motion，旧 entry RAF 仍可能继续改位置 | 取消 `ui.entryFrame`，将展开进度和盖片立即放到当前合法端点 |
| 输入事件会重新启用超过4,000字符的保存按钮 | input、compositionend、主动保存均保留4,000字符条件；计数通过 `Array.from` 更新 |
| hover 预览离开立即消失，与约定不符 | 普通离开100ms后开始80ms淡出；原点击等高优先路径立即关闭并取消旧关闭定时器 |

上述四项只复核对应改动，不扩展为新的测试矩阵。

## 4. 约束保留检查

入口展开时冻结 `sessionSlots`；更改当前模式只移动取消盖片，不交换图标。默认模式只在下次会话决定槽位；截图成功收录不会收回选择会话。`None` 只取消 arrival，严格开始后的 swallow 不受其控制；Reduce Motion 阻止磁力空间运动并改用合法端点。源头空间信息不可信时静态到达。

按下保留原 asset ID 与 generation；补位在指针拥有期间延后，释放要求仍是同一资产。原型只是对该约束的合成表达，正式 AppKit 的 selection owner、visibilityRevision、ACK 和 input window 机制仍以现有源码为准。

等待不吞噬；开始与最终完成分离；UNKNOWN 隐藏而不重生、不重传。演示的明确失败被标记为未来条件状态，不能作为正式安全失败／重试准入依据。反馈保存只进入本页模拟待发送记录，不存在 endpoint 或真实提交成功。

## 5. 规格对齐

本审查者同时将 [APPKIT_SPEC.md](../APPKIT_SPEC.md) 的两处编号间距统一为8pt；精确动态以 [MOTION_SPEC.md](../motion/MOTION_SPEC.md) 为唯一数值来源：58×46中间拟合包络、560ms四相、`t²·²⁵`直线吸引、484ms完全遮挡后反向显露；只保证交接处可见面积连续，不宣称轨迹C1速度连续。按下60ms/80ms outCubic、120ms `56×t¹·³⁵` 吞噬、160ms outCubic补位同步统一。

最终规格只保留一设备像素单边，不叠加可选内亮边；浅/深色分别统一为`rgba(24,40,33,.62)`和`rgba(224,237,226,.28)`，高对比为1pt及对应ink实色。首用与窗口稿一致为认识→连接与权限→开始的三屏；Feedback本机记录统一为同窗折叠区；[SOURCE_DELTA.md](../SOURCE_DELTA.md) 的实施顺序已映射到 [HANDOFF.md](../HANDOFF.md) 的五阶段，不再并存四阶段计划。

所有新增尺寸、颜色和运动细节仍属于推荐设计，待创始人确认；此次源码审查不会把它们自动变成已批准的原生实现。正式 App、Core、SQLite、Web适配器、准入与PR #1均未被本审查修改。

## 6. 补充审查：可见 ordinal 呈现

本轮追加只读审查仅覆盖`renderQueue`的编号变化，初次读取 app.js SHA-256：`a8f54c6a71688a3e07a686a7bbb6e62703d72f2a113a056a503eb3dba91028d2`。前文两项VM结论仍对应第1节列出的已复测字节；本次没有扩展或重跑其他测试。

数字现取`ui.page × capacity + index + 1`，资产身份仍取`a.id`；行复用、data-asset、选择token没有改成ordinal。图片与编号仍仅有一项AX入口；Reduce Motion直接呈现最终编号，普通补位尝试延迟160ms更新，按住时延后。这些身份约束保持正确。

**定点发现并已修复：编号延迟原先会被补位期间的重复刷新提前取消。** 第一次render已将`row.style.top`写成终点，但视觉仍在补位。160ms内第二次render（如下一张进入waiting）得到`shifted=false`，随后`clearTimeout(row.ordinalTimer)`并立即`presentNumber(ordinal)`，使数字提前变化。该问题不改变资产、目标或输入次数，但未满足“补位完成后更新数字”的呈现约定。

作者改为每行保存`ordinalTarget`与`ordinalDeadline`；只有新位移才建立`performance.now() + duration(160)`截止时间，无新位移的刷新继续保留旧数字并调度剩余时间。Reduce Motion直接清除截止时间。到期时检查节点仍连接且asset ID相同；若指针仍被持有，则标记pendingReflow，等原指针释放后更新。补位CSS同步使用`160ms × motion-multiplier`，与数字截止时间同源。

**最终函数级只读复核通过，未见本次差异范围内遗留问题。** 最终 app.js SHA-256：`43d4bd6d9a1fc76366b423bf13055191dc7dc308a5b632d8b7d63b605b55078f`。此结论为源码复核，浏览器呈现由原型作者另行验证；不将本次编号改动冒充两项VM或原生验收重跑。
