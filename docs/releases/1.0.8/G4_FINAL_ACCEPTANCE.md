# Riftlet 1.0.8 · G4 最终实站验收

**Build 61 当前结论为 PARTIAL。** G4-C 为 **BLOCKED_TECHNICAL**。G4-A、G4-B 为 **NOT_RUN**。真实站点缺少可归属于原操作的 PUT 请求和终态，也未取得故障后显式重新选择的成功记录。非作者已认可在特定条件下通过请求元数据归属一次 PUT。浏览器无法提供正文时，使用 `payloadHashUnavailable`，实际上传字节摘要保持未知。[当前独立归属标准](evidence/build61/native-network-attribution-criteria.json)

先前的小图在普通 Edge 已产生一条 START，取消次数为零。另一张 23,233,638 字节系统截图留下原 UNKNOWN、完整 PNG 和同名预览，两次备份相同，重选和后继 START 均为零。这两份历史原件继续封存。[先前普通双浏览器验收](evidence/build61/release-gate-after-both-selections.json) · [大图恢复裁决](evidence/build61/size-boundary-independent.json)

## Build 61 · 浏览器原生 Network 归属与故障范围

| 测量 | 结果 |
| --- | --- |
| Chrome 157，自有无登录页面 | 一个 PNG、一次 input/change、一次创建 POST 200。创建响应中的完整目的地址与随后唯一 PUT 地址一致。原 target、frame、loader、Document 均已核对。请求长度为 110,882 字节，PUT 得到 201；收件端收齐后逐字节核对。浏览器对原 PUT 的单次查询返回 `NO_POST_DATA`。[原始回执](evidence/build61/native-network-association.json) · [非作者复算](evidence/build61/native-network-association-independent.json) |
| 两款浏览器，自有页目标级 Offline | 服务器已对 Chrome / Edge 分别读入 64,840 / 16,332 字节时启用 Offline。两次 6 MiB 的请求仍在恢复在线前收齐并返回 201。其后仅目标标签的新请求报网络断开。同浏览器另一标签和独立客户端均返回 201。[原始事件日志及作用范围](../../../Tests/PreClickLease/g4/browser-native-network/scope/README.md) |
| 两款浏览器，精确本地 URL 阻止 | 两个目标均产生请求 ID，随后 `loadingFailed`、`blockedReason=inspector`。服务器没有收到目标请求。对照标签、独立客户端访问同一 URL 均为 201。归类为 `CLIENT_REQUEST_BLOCKED_BEFORE_BODY`。撤销后各方均成功，退出时无待处理服务器请求或连接。[非作者逐事件复核](evidence/build61/native-network-scope-independent.json) |
| Edge 158，本机安装检查 | Edge 的外层安装包在 macOS 静态验签中报告缺少 `Contents/PlugIns/MicrosoftEdgeWidgets.appex`。本轮额外的正常关联测试在启动 Edge 前结束。先前两款浏览器的目标作用域测试单独列账。Chrome 通过外层签名和厂商要求验证。[静态验签回执](evidence/build61/native-network-installed-signatures.json) |
| 普通浏览器可见面板，首七个自有窗口 | Chrome 从原标签的具名按钮打开 Inspect，原 Document 保留。原窗出现 DevTools 区，未能读取 Target ID、Frame ID 或请求行。Edge 的已运行进程通过动态厂商校验，并获得独立的工具区裁剪。七扇窗口均在复核原身份后关闭，初始窗口集合复原。精确窗口与原文档的证明和网络请求归属分别记账。[七窗清理与动作计数](evidence/build61/native-network-ordinary-admission.json) · [首四窗独立审计](evidence/build61/native-network-ordinary-independent.json) |
| 普通 Edge，可见 Network 面板 | 隔离原窗的私有裁剪清楚显示「网络」、唯一的本地随机样式表和 200/66 B，其名称与原文档匹配。两人分别读图并核对原件。66 B 是该样式的响应大小。此帧未显示协议 Target ID、Frame ID 或上传请求 ID。[原窗可见行与来源](evidence/build61/native-network-visible-row.json) |
| 历史 Edge 23,233,638 字节实站大图 | 37 份原文档样本记录一次 input、一次 change、零发送与提交。文件创建端点的资源计时有 200，稍后的处理端点有计时但无状态。无创建响应正文、存储 PUT ID 或上游 413。原图为 2880×2816，最后可读样本仍显示 2048×2002 同名预览。四份私有数据库备份一致，保留原 UNKNOWN，重选和 START 均为零。[原图、卡片和四份快照独立复核](evidence/build61/native-network-size-independent.json) |

网页产生卡片、浏览器给创建端点返回 200 和存储 PUT 的终态分别判断。实站归属需要同一原操作的一次文件输入、唯一创建响应、完整目的地址相等、唯一 PUT requestId、匹配的请求长度、原目标与时序及真实终态。声明请求长度不证明失败前传出了多少字节。公开记录只保留允许的目的地址摘要。本地实验和独立复核的 13 份私有原件清单 SHA-256 为 `1ee2b560e6568e26d1629c995352c4abe59da4089198894f5740def6a0f0f84e`。[归属及数据范围裁决](evidence/build61/native-network-attribution-criteria.json)

Chrome 157 自带的表格支持单独添加请求头列。默认的 Content-Length 列读取响应头，Size 读取响应传输量。只有实际请求的 Content-Length 可用于本次归属。该版本 Fetch 协议的两个阶段分别位于请求发出前与取得响应后；它们本身不计量已发出的正文前缀。[安装版本与官方字段定义](evidence/build61/native-network-panel-fields.json)

### 普通浏览器准入与当前实站结果

普通 Edge 内置 Network 与原 QA 文档的对应已获独立读图确认。随后在一扇新的同类专窗中，验收器预先编译，进入原窗时保存真实 CGWindowID。三处工具栏图案与已审阅图像像素一致。定点按下与抬起命中该签名进程的 DevTools 区域。450 毫秒后原窗裁剪逐字节相同，未能确认菜单已展开。没有取得协议 Target ID、Frame ID、Loader ID 或请求 ID，未对未知视图输入命令。此次共创建四扇 Chrome、五扇 Edge 的本地专窗，全部按原身份关闭。原窗口集合已恢复。[可审阅图像的独立结果](evidence/build61/native-network-visible-independent.json) · [原窗状态及精确收尾](evidence/build61/native-network-visible-window.json) · [连续动作与九窗总账](evidence/build61/native-network-ordinary-consecutive.json)

| 实站步骤 | 本轮结果 |
| --- | --- |
| B · 正常单图校准 | **NOT_RUN**。真实 Temporary Chat 的唯一创建响应、PUT requestId、请求长度和终态均未取得。没有重复空稿预绑定。 |
| C · G4-C 故障与知情恢复 | **BLOCKED_TECHNICAL**。真实站点的原 PUT 尚未归属，站点故障注入和显式重选均为零。恢复前和成功后的 SQLite 快照均为 **NOT_RUN**，散列均为 `null`。 |
| D · G4-A / G4-B | 均为 **NOT_RUN**。缺少新操作对应的具名原卡失败，或真实上游 4xx、原卡消失及完整恢复。非作者未签发 G4-B 的等价放行。 |
| 站点操作与发布 | 本轮发起的真实站点访问、文件输入、发送和表单提交均为 0。现有个人浏览器的后台流量未采集。公开站点及 stable appcast 继续提供 1.0.5（31）。 |

当前复核要求在原 QA 窗内取得确切协议身份和允许读取的字段，再通过正常产品输入进行实站校准。面板显示的一条本地资源已取得原文档归属；其 66 B 响应大小与原 PNG 的上传请求长度属于不同读数。[非作者 G4 分项裁决](evidence/build61/native-network-independent-final.json) · [正式 PR、公开版本和 DMG](evidence/build61/native-network-release-state.json)

私有总清单覆盖 29 个文件，含三份分批封存的 GUI 原件归档，清单 SHA-256 为 `cc45611a8b4c256b5b1bf159e18826af4b6aa202b303e1968b8f2652745c5b78`。最终非作者裁决 SHA-256 为 `3a7a48816e28f2329c8fce020badfe1a1a755fa35d95f4e6fd6911fbd9e406e1`。[私有归档与候选指纹](evidence/build61/native-network-release-state.json)

## Build 61 · 原生提交后的双世界回读

**普通 Chrome 157.0.8103.79 和 Edge 158.0.4370.33 的自有本地页均通过。** QA 可执行文件从 `49b92049` 的 Core 和 Adapters 编译。原生执行器原文件作为编译输入前缀，SHA-256 为 `00b1f7b637aad2ce00cc9b766c923ad5c4f25c3d0d08e8cf7306983ddb386140`。运行器新建浏览器专窗，通过现有 `ChromePIDEvents.submitMainWorld` 调用该本地文件预置的固定函数。每步同时留存原生返回和独立的页面读数。[逐浏览器回执与源指纹](evidence/build61/native-bootstrap-local.json)

| 直接测量 | Chrome | Edge |
| --- | --- | --- |
| 安装随机标记、再次主世界回读、清除标记、撤销回执 | 四次原生返回，四步页内效果 | 四次原生返回，四步页内效果 |
| 主世界读到原全局对象、原 XHR 原型，新的未打开 XHR 继承该标记 | 通过 | 通过 |
| 普通 Apple Event 能读到共享回执，在自己的全局对象及 XHR 原型中查找同名标记 | 两个私有标记均不可见 | 两个私有标记均不可见 |
| 原窗、原标签、Document、URL、导航条目与 `timeOrigin` | 全部一致 | 全部一致 |
| 本文档 HTTP(S) 资源、CSP 违规、资源缓冲区满事件 | 0 / 0 / 0 | 0 / 0 / 0 |
| 收尾 | 原型与描述符复原，监听器、临时节点及 DOM 回执移除，原窗口集合复原 | 同项通过 |

两个页面的静态回执节点始终隐藏，页面文字始终为空。本地测试独立封存 39 项原件，归档 SHA-256 为 `bc3359cabe81517bdceb42908e37450713c9661b66eb46457d0cf6f8d13a92e4`。该归档另含一次发生在创建窗口前的准备停止。修正 macOS 临时目录的规范路径比较后才进入本次两项测量。[固定夹具、可执行回执判据及复算说明](../../../Tests/PreClickLease/g4/main-world-bootstrap/README.md)

## Build 61 · 签名候选在两个全新 Temporary Chat 的结果

普通 Chrome 和 Edge 各新建一份专用、已登录的空草稿，分别启动同一签名候选一次。进入空稿、凭据就绪和关闭前的三次读取中，原窗和标签、导航条目、`timeOrigin`、编辑器及上传入口均符合预期。独立的普通 Apple Events 观察器读不到产品私有的 `documentID`、`composerID` 与 `draftEpoch`。两款浏览器的完整产品追踪各有两次成功的 `captureTarget` 和两枚不同的 ARMED 凭据。每个候选的可执行签名均已现场核对。[两个实站样本及原件摘要](evidence/build61/signed-site-empty-prebind.json)

两次运行的凭据消费和 commit 均为零，两份现场 SQLite 的 assets、operations、upload_starts、attachment_reselections 也均为零。执行器发出的文件输入、发送和表单提交动作为零。本站点步骤沿用既有身份观察器，没有安装额外的网页事件计数器或网络包装器。两扇新空窗均已按原身份关闭。原有窗口集合均已恢复，候选进程及本地监听器均已退出。95 项私有原件及内嵌清单的归档 SHA-256 为 `90e54e93acb59ab0f43abec0b44831002e7ff18f08cfcc17e1486f92726f8129`。[本次签名实站独立复核](evidence/build61/signed-site-empty-independent.json)

原生提交已经能在自有页进入主世界。在真实站点，签名产品的回执证明了草稿预绑定；回执没有实际上传请求的发起环境、所属对象、完整请求体、进度和响应。以往中图的原 PNG 与网页 File 匹配，无法由此还原站点 PUT 的字节或唯一可取消的请求。此次没有上传新图或中断请求，也没有显式重选、后继 START 或恢复前后的两份 SQLite 快照。最后一次旧稿观察仍显示原卡。[原实站上传的采集范围](evidence/build61/recorded-observer-coverage.json) · [原始签名运行的逐事件审计](evidence/build61/recorded-product-command-review.json)

## Build 61 · 此前执行世界和实际 PUT 的归属

| 核验对象 | 直接取得的结果 |
| --- | --- |
| 普通 Chrome 157 与 Edge 158 的 Apple Events | 在各自新建、已核实身份的本地专窗中，连续两次读到同一原文档的 DOM 标记。页面自己创建的 XHR 能从原型读到标记，Apple Events 所见的 XHR 原型没有该标记。两款浏览器都关闭了本轮专窗并恢复原窗口集合。[普通浏览器原生回执](evidence/build61/world-local-native.json) |
| 本地页面自带的固定脚本链接 | 在此前独立的无界面对照中，浏览器报告该链接在原页面的默认环境执行。两个环境的底层 DOM 节点相同，私有对象和原型标记各自独立。替换无行为标记与重新加载分别使旧标记、旧环境失效。原生 URL 属性提交的后续实测见上节。ChatGPT 实际上传请求的执行环境仍缺直接证据。[页面自带链接的回执](../../../Tests/PreClickLease/g4/main-world-observer/receipt.json) |
| 冻结产品入口 | 已核对七个指定入口。原生提交返回后，产品另外核验原始命令的回执及草稿身份。Edge 的凭据把两个 JavaScript 环境关联到原文档。两条产品路径的回执均无站点 PUT 实例、请求体或终态。[逐入口源码复核](evidence/build61/world-source-and-history.json) |
| 已封存的 Chrome 实站中图 | 原采集器只查询精确文件创建端点。条目从 0 增到 1，返回 HTTP 200。原图的 7,921,752 字节在 input 与 change 时两次匹配，SQLite 留有原操作唯一 START。采集器未记录上传 PUT，也无法区分上传来自页面、子框架或工作线程。[原运行清单、采集范围及回执](evidence/build61/recorded-observer-coverage.json) |

该轮本地链接对照的实站新增访问、文件输入、中断、显式重选、发送和表单提交均为零。已封存的普通浏览器对照共 19 份私有原件，逐件重算一致，归档 SHA-256 为 `7d3180a10edf9e6c23478acd06b7ee16d31ecd8015122689d423a43035da1503`。[清理与分项读数](evidence/build61/world-local-native.json) · [该轮非作者判定](evidence/build61/world-independent-verdict.json)

## Build 61 · 中等大小截图

本轮新图是 macOS 对专用图案窗口的系统截图，1920×1440，7,921,752 字节，SHA-256 为 `66057577de807a2d2a266360b59efdfb80e6301a158d9eb1bd2bf028757dd3a7`。非作者重新读取原 PNG，核验系统截图标记及全部 492 个 PNG 数据块的 CRC。原图保存在私有验收档案。这个样本低于 ChatGPT 公布的单图 20 MB 限制。[原件与传输独立复核](evidence/build61/medium-loopback-independent.json) · [官方上传限额](https://help.openai.com/en/articles/8555545-uploading-files-and-audio-to-chatgpt)

| 同一张图在自有回环端点的两次测量 | 浏览器 | 收件服务 |
| --- | --- | --- |
| 完整上传 | 一次 PUT，收到 HTTP 201 | 完整读取 7,921,752 字节，SHA-256 匹配原图 |
| 单次中断 | 上传进度事件报告 1,425,408 字节（17.9936%），随后原 XHR 各产生一次 abort 和 loadend | 实收前 1,376,256 字节，逐字节匹配原图前缀，随后 ECONNRESET，无 HTTP 响应 |

两个用例使用独立请求，结束时在途请求为零。实站 G4 的裁决另需签名产品、原卡、原草稿和用户显式恢复。[浏览器与收件服务原始回执](../../../Tests/PreClickLease/g4/owned-transfer/system-result.json) · [离线复算](../../../Tests/PreClickLease/g4/owned-transfer/offline-result.json)

### 同一原图在普通 Chrome Temporary Chat 的结果

签名 build 61 在专用草稿收到一次真实 AppKit mouseDown。网页随后记录一次 input、一次 change，各自读取到完整的 7,921,752 字节，两个 SHA-256 均匹配原 PNG。原 Document 和编辑器继续有效，网站显示一张以原操作命名的已解码 1920×1440 预览。发送按钮点击和表单提交均为零。[同包现场回执](evidence/build61/medium-chrome-normal.json) · [11:59 原件的非作者复算](evidence/build61/medium-chrome-independent.json) · [24 项私有原件指纹](evidence/build61/medium-chrome-original-fingerprints.json)

12:01:42（北京时间），清理观察器之前，原页面完成了全幅像素核对。File 与预览均为 1920×1440，中心 RGBA 都是 `[206,58,9,255]`。两者的完整 RGBA SHA-256 分别为 `388de40ed2c3f4df79b6edf02ca6318baff2737dc69126ae841b3508e6d0eb9f` 和 `5fe929839e4a7b006456295bfe4919c86b0cde1c4a60804ecf96c339da9c45b8`，全幅像素不同。未取得预览编码的字节，差异来源未知。原文件输入的两次完整字节核对均通过。[非作者对两次网页读数及完整归档的复核](evidence/build61/medium-final-g4-independent.json)

点击后约 3.67 秒取到的第一份 SQLite 后备份仍是 `dispatchIntent`，没有 START。晚期备份已持久化一条 `attachmentAccepted` START，原操作 phase 为 `unknown`，最新收据为 `uploadStarted`。晚期备份 SHA-256 为 `3727e8b9e0994bca07146004c8d22ce6c32d39eb824f1ee609e911fd2a8dd831`。三份快照覆盖正常校准的点击前、点击后早期和晚期。显式重选的前后快照尚缺。

精确同源 `/backend-api/files` 的 Resource Timing 条目在输入前为零，之后出现一条 fetch，耗时 424 ms，返回 HTTP 200。该接口记录了文件创建端点的响应。实际上传地址、PUT 请求体、进度、线路字节及上传响应状态仍未知。已知原卡仍在，现场取消、具名错误及显式重新附加的次数均为零。[浏览器接口与网络证据边界](evidence/build61/g4-site-observability-review.json) · [Resource Timing](https://www.w3.org/TR/resource-timing/)

Chrome 157 对应版本的实现将 Apple Events 的 JavaScript 放在独立脚本环境。此通道能读取原始 DOM File 和草稿状态，本轮无法从中识别并取消网站持有的唯一 XHR。另在一个本地空白专窗调用官方开发者工具菜单后，能看到新面板，但原标签的选中状态与原 AX 窗复核都未通过。执行器在读取网络行前停止。[已安装版本的 Chromium 实现](https://github.com/chromium/chromium/blob/157.0.8103.79/chrome/browser/ui/cocoa/applescript/tab_applescript.mm#L397-L398)

独立的回环对照在选择文件前已启用 Chrome 157 随附 Network 面板使用的数据源。自有服务端收齐另一张 7,563,763 字节的合成 PNG 并返回 201。该数据源能读出同一次测试的 97 字节创建请求、PUT 的请求类型与响应状态，但在原 PUT 开始和结束后按同一请求 ID 读取正文，均得到 `NO_POST_DATA`。这次测量用的是面板的数据源，实际可见面板的占位文字没有采集。再新建实站草稿重复同一读法，仍缺少本次要求的完整请求体归属证据。[对照与所用版本](evidence/build61/medium-chrome-panel-capability.json) · [收件端和浏览器原始记录](evidence/build61/medium-chrome-panel-loopback.json)

| 独立放行项目 | Build 61 结果 |
| --- | --- |
| G4-C 用户知情恢复 | **BLOCKED_TECHNICAL**。实站唯一可取消 PUT 的原图归属和正字节进度均未取得。原卡在最后一次原草稿读取时仍可见，故障、显式重选和恢复 START 均为零。 |
| G4-A 具名失败卡 | **NOT_RUN**。本次无网站原卡错误、对应的错误收据及后继成功操作。 |
| G4-B 上游拒绝 | **NOT_RUN**。缺少归属于完整原 PNG 的真实上游 4xx、原卡消失和恢复。非作者没有签发等价放行。 |

本轮创建的三扇 QA 窗口中，本地面板窗和 Edge 零输入空窗均在重验原身份后关闭。带有原附件的 Chrome Temporary Chat 保留。两份 DOM 观察器、两个签名 QA 进程和三个本地监听器均已退出。私有 GUI 档案含 263 个有指纹的文件及内嵌清单，归档 SHA-256 为 `3cb2b916ef120781e34f8644b320eb4c9d367987b9af92191a9ec88473b4d60c`。原 PNG、三份正常校准 SQLite 备份和原草稿证据均已封存。[签名运行与清理](evidence/build61/medium-site-cleanup.json) · [两个面板环境的独立判定](evidence/build61/medium-panel-independent.json)

## Build 59 · 历史验收

本文下方保留 build 59 的历史证据。[build 61 实站原操作](evidence/build61/g4c-original-live.json) · [当前发行报告](RIFTLET_1.0.8_FINAL_RELEASE_REPORT.md)

**放行结论为 PARTIAL。** 已在已登录的普通 Edge Temporary Chat 中中断唯一一条发送原 PNG 的真实 XHR。ChatGPT 随后移除了原进度卡。观察期内没有出现属于该操作的明确失败卡，Riftlet 也没有记录原卡错误收据。因此 G4 的原卡失败及显式恢复保留为 **NOT_RUN**。

本轮使用签名产品提交 `69b76cb025ab552b3480e3af095b627891874712`，验收起点为 `77044e526864f93da2827257a0e9a5a6c7bb6797`。实际运行器校验安装副本、产品资源及最终镜像。DMG SHA-256 为 `666324176aadc4ffb9fd6fbfd0ca38772a169eb06394401f7abede374f7d3ee6`。改动仅涉及 QA 工具和验收记录。

| 现场步骤 | 实际结果 |
| --- | --- |
| 正常上传校准 | 专用原窗、原标签、原编辑器及登录态通过身份核验。签名 App 的一次 AppKit 按下产生一次 input、一次 change、一个持久化 START。唯一的创建请求通过 `file_name` 对应原操作 UUID，返回唯一的 `upload_url`。XHR 以该地址 PUT 同一 File，全部 5,516 字节匹配原 PNG，HTTP 201。 |
| 单次传输故障 | 在另一专用草稿，以新系统截图重建全部关联。文件为 5,513 字节，完整 SHA-256 为 `fa734c39ae34bca70281f0f67439349402d7e9099465c6f7010148af77a1b469`。创建请求 HTTP 200，目标 PUT 有一次受信 loadstart。原生 send 返回后，在响应可见前调用一次 abort，浏览器回报一次受信 abort、一次 loadend，status 为 0。未观测到正上传进度，线上实际传出字节数未知。此项只证实客户端传输取消。 |
| 网站原卡 | 点击前绑定的具名原卡观察器记录到新进度卡。取消后约 12 ms，观察器记录到该原卡节点被移除。自点击意图起观察 54.549 秒，原 Document 和编辑器有效，未观察到属于该操作的具名失败卡。故障草稿有一次 input、一次 change、零发送点击、零表单提交。 |
| Riftlet 原状态 | 原 asset、operation 与 invocation 仍可查。数据库有 1 个 asset、1 个 operation、0 个 START。操作 phase 为 `unknown`，收据 outcome 为 `inputTriggered`，`hasError=false`、`safeToRetry=false`。原图仍为 visible，磁盘源 PNG 和保留媒体的完整哈希均匹配。 |
| 显式重选与双快照 | 明确原卡错误的前提未满足。新操作、新 invocation、新 START 均为零。未执行 beforeSTART 或 afterSTART 的失败恢复。两份规定时点的恢复快照均为 NOT_RUN，哈希均为 null。 |
| 清理 | 终态事件之后约 0.1 ms 自动移除故障监听，恢复原 fetch/XHR 函数；待处理观察任务为零，目标 XHR 已结束。两扇专用窗口均按创建身份关闭，浏览器原窗口集合复原。所有本轮私有 Riftlet 进程及临时本地监听器已退出。 |

原故障操作为 `4F739270-3638-4598-BBAE-C2AFBC37980E`，invocation 为 `5CB048BB-88D0-4F93-93EC-B612ED70C3C7`。网络观察器撤除后，仍持续观察 Riftlet 文件输入、原卡和操作账本。此次只能证实观察期内没有 Riftlet 自动重投。故障轮终态 SQLite 一致性备份 SHA-256 为 `3f1176fe3da464277c4ae2552c9a4ecee799b8d7aa4d1b5b7337b5b097c1e926`，采集时点为退出私有候选之后。原始 PNG、媒体及数据库均保留在私有验收档案。公开收据仅保留上传地址的散列。

非作者独立读取浏览器、AppKit 和 SQLite 原始记录，并独立创建了终态数据库备份。两份终态备份的 SHA-256 相同。非作者确认此次客户端中断成立，原卡错误和恢复均未通过。被动校准与一次性故障工具分别通过 39 项和 35 项离线控制；非作者另以四种 XHR 复用情形验证了对后续请求的保护。

[网络回执](evidence/build59/g4-final-network-receipt.json) · [原卡回执](evidence/build59/g4-final-card-observation.json) · [恢复及快照审计](evidence/build59/g4-final-recovery.json) · [窗口与进程清理](evidence/build59/g4-final-cleanup.json) · [校准非作者复核](evidence/build59/g4-live-passive-audit.json) · [最终非作者复核](evidence/build59/g4-final-independent.json)

## 后续两种真实传输中断

前台恢复后，签名 build 59 在新的已登录 Edge 临时草稿完成另外两种实站中断。一次在受信部分进度 81,875 / 188,726 字节处取消；另一次在受信上传 load 读到 5,516 / 5,516 字节、尚未观察到响应时取消。两次均产生一次 input、一次 change，保留完整 PNG 与原 UNKNOWN。两次均未取得属于原操作的明确错误卡，也未进行显式重选。另一次大图身份比对不符，取消数为零。合计三种真实中断，G4 为 **BLOCKED_TECHNICAL — G4 NOT PROVEN**。逐轮结果见[最终发行报告](RIFTLET_1.0.8_FINAL_RELEASE_REPORT.md)和[三种策略总账](evidence/build59/g4-final-strategies.json)。
