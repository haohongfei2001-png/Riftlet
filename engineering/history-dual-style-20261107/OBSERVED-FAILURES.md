# 历史双样式：已观察失败与修复记录

本记录保留失败，不把已写入的修复或语法检查当作最终候选通过。
截至此记录，三个问题均已定位并完成局部源码修复；最终原生窗口、外部 AX、
完整 XCTest 与正式 CI 回归仍为 **PENDING**。原始失败报告不被后续结果覆盖。

首个完整候选 C01 的来源是 `28aca618e459bb80e586fcea63d6409caeca2a5a`，
二进制 SHA-256 为
`34f0474182bf668698a19c3bd859dd8cc1cc706a31f9e31f94a6489e2cc30d32`。
运行使用隔离 settings-review 根和六条合成截图记录，未操作已安装 App 或生产数据。
原始文件的身份、哈希和经过筛选的几何事实见
[observed-failures.json](evidence/observed-failures.json)。

## H01：详情图 intrinsic size 撑大真实窗口

C01 初次打开的窗口是 760 × 560 点；选择并加载截图后，后续原生 AX / WindowServer
记录为 1101 × 560 点。该宽度与旧布局的 `152 + 260 + 1 + 640 + 48` 相符。
这项实际尺寸变化不能归咎于截图工具。

随后 v04 / run-02 私有探针链接相同检查点的真实 UI/Core/Capture 对象，用合成图片
进一步记录了确定的因果链：设定最小窗口 680 × 480，图片加载后 detail image 的
intrinsic size 成为 480 × 300，content fitting width 成为 941，窗口稳定增宽到
941 × 480。`152 + 260 + 1 + 480 + 48 = 941`。五秒内尺寸没有回到期望值，
`wait_window_bounds` 失败；进程 exit 0 只表示正常写报告和退出。

[失败窗口图公开副本](evidence/hc-light-current-minimum-wait_window_bounds-timeout.png)
为 1882 × 960 像素，已逐张查看确认仅含本进程窗口与合成条形图。
原字节永久保留在私有证据包。公开副本仅移除含硬件标识的 PNG 元数据，像素流不变；映射见 `evidence/public-derivatives.json`。原始 SHA-256：
`bec8ba73dab50a33ca79de5eda3b87efa8bd62629ddf46468f8dfdd7e83804bd`。
原始报告 SHA-256：
`9619931628b1a361c87ec9bb9d8f083871fac62f749de2ef16de26f3c3b1da58`。

**已实现修复：**详情图复用现有 `HistoryPreviewImageView` 的 `noIntrinsicMetric`，
由原有约束决定尺寸；Fit、图片、列宽和窗口最小尺寸不变。新增回归加载 1200 × 750
真实临时图片，再检查最小窗口及 current → imageGrid → current 不增长，并保留同一
bitmap 与选中 UUID。该回归尚未运行完整 XCTest。

探针虽使用 `hc-` 文件前缀，该失败帧实际 `appearance` 和 `bestMatch` 均为 Aqua，
系统 Increase Contrast 为 false。它证明窗口几何缺陷，不构成实际系统高对比度验收。

## H02：网格单元的 AX 身份未实际暴露

C01 外部 AX 记录只有 collection 下的容器、image 和 text，未暴露预期的逐项 UUID、
聚合标签和 selected 状态。原代码把 identifier/label 放在普通 `NSView` 根上，
没有让该根明确参与 AX；`isSelected` 也只更新选中边框。

**已实现修复：**真实 item 根视图使用 cell 语义，明确暴露 AXIdentifier、标签和
选中状态。AX 选择依当前 UUID 映射到原生 collection，再回到同一 controller；
选择不执行放回、移除或上传。隐藏、已移除及复用后的旧元素不能借旧行号选中新记录。
新增原生属性与 UUID 操作目标回归；最终候选的外部 AX 暴露/操作验证仍待完成，
不据进程内属性测试宣称完整 VoiceOver 通过。

## H03：原图可见时首次网格一直显示加载占位

C01 的完整网格画面保留了选中 UUID 和详情，但六张卡片都显示“正在加载预览…”。
原图窗口仍打开时，旧 `mayLoad` 条件明确拒绝所有网格缩略图请求；这不是网络等待。

**已实现修复：**网格创建现有 `HistoryPreviewLoader` 的独立实例，隔离 owner、
cancellation 和 pending 状态；原图仍使用 `.shared`。所有实例继续共用原有
`private static` 串行解码队列和严格文件校验，未新增并发 ImageIO lane，也未改
Core、原图请求或文件导入逻辑。删除原图可见 veto 和显式暂停；每个网格仍最多一个
未完成请求，已排入的原图先于下一张小图执行。

新增回归覆盖原图仍打开且保持 200%/同一 bitmap 时，首次网格的其他 UUID 真正出现
缩略图，以及两个 loader 实例的真实解码入口最大并行数为 1。原有刻意注入同一
loader 的 owner 抢占测试及其断言保留。最终候选运行结果仍待完成。

## CUA 文件命名与实际内容的修正

原文件不改名、不覆盖；按画面和 AX 内容解释，不能把保存时的工具标签当作事实。

| 原始 basename | 实际内容与范围 |
| --- | --- |
| `03-current-selected-cua.png` | 旧三列 current 视图，只有左上部分画面，其余白色；不是网格。该局部图本身不能证明网格裁切，也不能单独解释部分像素缺失。 |
| `05-settings-grid.png` | 完整网格窗口，六张加载占位、选中详情与样式选择器；不是设置窗口。 |
| `06-grid-first-observed-incomplete.png` | 设置的“历史与存储”页面；不是网格窗口。 |

这三个 CUA 文件虽以 `.png` 命名，实际编码均为 JPEG。原始字节和各自 AX 文本的
SHA-256 保留在绑定 JSON 中，原图与 AX 全文保持私有；没有将其重编码来制造新原件。

当前新增历史样式 XCTest 共 16 项；本地 parser 与 diff 检查通过，完整 XCTest
未运行。最终通过证据应另行绑定准确候选来源和二进制，不修改本记录中的原始 FAIL。
