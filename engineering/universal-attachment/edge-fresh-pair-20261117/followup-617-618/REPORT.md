# Edge 普通 App 冷启动后的 617、618

普通签名 App 在已登录的原 Edge 临时草稿接收两次微图点击，两次应用内 down 相隔 **426.847 毫秒**。每张图各有十条匹配自身输入窗口的原生和产品回执，各执行一次 begin、六个分块和一次 commit。两张图的文件 setter 和 change 都已返回。两笔各创建一个实际操作，均未记录 START，均保持 UNKNOWN 并保留可见微图。[原始 App 事件](pair-trace.jsonl.gz) · [操作、账本及稍后草稿读回](product.json)

| 项目 | 617 | 618 |
| --- | ---: | ---: |
| 系统截图原件字节 | 1,406,130 | 1,407,109 |
| 原件 SHA-256 | `b998c430aae7abd8bbf73e0abe5a3648184cdbbb4300345f304f9661a0257b64` | `139cb2688a344296fcf70654a1e457a56759415c8bbd8816ac9cafa5818543d4` |
| 原操作的页面观察次数 | 76 | 69 |
| 首末观察间隔 | 41.700 秒 | 32.964 秒 |
| 与新图文件名、预览或进度匹配的节点 | 0 | 0 |
| 草稿中新图数量 | 0 | 0 |

两次点击保有独立绑定，均指向原进程、窗口、标签、文档、编辑器和草稿代次。原正文及 UTF-16 选区 [61,14] 仍在原位置。前后及独立读回时，614、612、613、615 四个原附件分别各有一份。每图均无吞噬和重传。隔离库由 20 项资产、11 项操作、4 条 START 变为 22 项资产、13 项操作、4 条 START。核验覆盖全部既有资产、操作、START 和 20 份原媒体。[逐文件页面观察投影](ordinary-observer.json)

新签名包来自产品源码 `0e0ae7fa0b17a72190b8ad08f995048148f31d39`。此次通过 Launch Services 冷启动了隔离安装的普通应用。试验前确认浏览器实际页面和 Apple Events 执行脚本处在两个独立的 JS 环境，并验证同一原文档的一次性回执。仅该测试标签的观察器附在页面实际使用的 JS 环境。它确认两份原输入的文件名摘要与 PNG 字节，未观察到关联的 create JSON 或处理响应。到期后原属性描述符已恢复。[签名包和实际启动证据](tested-package.json) · [页面观察器原始脱敏状态](page-observer.json)

归档包含 347 条连续 App 事件。复算器接受该归档、在私有测试目录封存的 `observations/outcome.json` 和本目录的页面观察状态。公开包不含截图、授权信息或原始网络导出。[离线复算器](verify_trace.py)

完成导出的常规 DevTools HAR 共 200 项。617、618 均没有匹配原操作名称的创建请求、存储 PUT 或处理请求。点击窗口内唯一的请求返回 HTTP 202，路径属于其他功能。随后在原草稿同一提示内读到“你已达到文件附件数量限制”和“请于 11月18日 21:33 后重试”。该提示没有逐文件归属、限额范围或时区。两笔原操作继续保留 UNKNOWN。新的附件测试已停在服务提示处，未另建账户或发送聊天消息。[服务与时间提示](service-limit.json)

对连续保存的 68、191、200 项网络导出另做了逐文件交叉核验。612、613、615 的原处理请求后来仍无响应正文，均未取得新终态。615 的创建声明和实际存储写入均为 1,386,385 字节，有 HTTP 201 及 ETag。[三份导出交叉核验](three-export-crosscheck.json) · [615 的原始服务投影](../followup-615-616/service.json)

在持有原件的机器上，可以从仓库根目录执行以下核验。环境变量 `RIFTLET_PRIVATE_BUILD` 指向隔离测试材料根目录。命令读取已封存的文件。

```sh
evidence=engineering/universal-attachment/edge-fresh-pair-20261117/followup-617-618
python3 -B "$evidence/verify_trace.py" --gzip "$evidence/pair-trace.jsonl.gz" --outcome "$RIFTLET_PRIVATE_BUILD/pr69-pair-617-618-20261117/observations/outcome.json" --reader "$evidence/page-observer.json" --expect "$evidence/ordinary-observer.json"
python3 -B "$evidence/verify_later_files.py" --private-build "$RIFTLET_PRIVATE_BUILD" --new-har "$RIFTLET_PRIVATE_BUILD/pr69-har-617-20261117/original-617-618.har.devtools" --sha 535a8db87bd87725f9234e78da8fbe6e54c40df2820856b81818a6500fddf693 --expect "$evidence/three-export-crosscheck.json"
```

准入提交 `4a493e950285a10d0362077ff501f149c1cc330c` 首次托管运行中，Intel、Feedback 和两项源码准入都已成功。ARM64 等待 19 分 42 秒后由 GitHub 取消，未获得托管 runner，执行步骤为 0。[官方运行元数据与取消注解](ci-4a493e9.json)

最后在原 DevTools 行分别核对了 612、613 的操作文件名和服务文件 ID，各执行一次“复制响应”。两次系统剪贴板版本均前进一代，工具均返回 `UNATTRIBUTED_CLIPBOARD / NEW_OWNER_PRESERVED`。未能取得可归属的原响应实体，也未判断实体是否为空。助手未清空或写回内容；原剪贴板仅在进程内暂存，进程退出后没有可恢复副本。原内容恢复未获确认。此项取证已结束，两个原业务终态均保持 UNKNOWN。[执行范围与剪贴板结果](original-response-copy.json)
