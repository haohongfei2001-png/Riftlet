# 原型回归与视觉证据

本次测试直接打开已经保存的 `Riftlet-Settings-Prototype.html`，未重建或替换它。最新运行 [20261106-browser-02](evidence/20261106-browser-02/RESULTS.md)：**82 项，69 PASS、13 FAIL**；50 张未经编辑的原始 PNG。13 项失败按独立断言计数，不代表13个独立根因；见 [FAILURES.md](FAILURES.md)。没有使用遗失的旧41项PASS。

## 可复验环境

- Node `v26.8.2`，macOS arm64，Playwright `1.58.2`。
- 实际浏览器：隔离的 Chromium headless shell `156.0.8078.4`；可执行文件 SHA-256 `77d8278b1ac9d0687fad4e817ea83023ede09b1deef36e1864b49ba194ac9634`。
- 1440×1100 CSS px、deviceScaleFactor=1、zh-CN、Asia/Shanghai；浅色为每项初态，深色由真实按钮切换。
- Playwright 只启动自己拥有的 headless 进程和临时 profile。没有连接正在使用的 Chrome、CDP 用户会话、Apple Events 或生产 App。
- HTML 通过 `file:` 读取，所有 HTTP(S) 请求被拦截并计入错误；本轮无外部请求、无脚本异常。浏览器关闭在脚本 `finally` 中完成。

测试脚本：[browser-regression.cjs](tests/browser-regression.cjs)。依赖单独安装，不在 Riftlet 产品包引入测试依赖。以下在仓库根执行，浏览器可以用自己准备的 Chromium 可执行文件；使用不同版本必须以新 run ID 保留结果，不能冒充本轮运行：

```sh
export RIFTLET_DESIGN_TOOLS="$(mktemp -d)"
npm install --prefix "$RIFTLET_DESIGN_TOOLS" playwright@1.58.2 --ignore-scripts --no-audit --no-fund
export PLAYWRIGHT_MODULE="$RIFTLET_DESIGN_TOOLS/node_modules/playwright"
export BROWSER_EXECUTABLE="/absolute/path/to/chrome-headless-shell"
RUN_ID=independent-review-001 node design/settings-center-20261106/tests/browser-regression.cjs
```

脚本以状态码1退出是因为13条实际断言失败，并非全绿。不要改为允许失败后宣称PASS。每次运行拒绝覆盖已有目录；源码HTML哈希不匹配则拒绝运行。可用 `node "$PLAYWRIGHT_MODULE/cli.js" install chromium` 准备隔离浏览器，然后不设置 `BROWSER_EXECUTABLE`；这一环境与本次浏览器版本可能不同，结果会记录实际版本。

## 证据结构和验证方式

- `results.json`：时间、运行环境、HTML/脚本哈希、16个继承文件的运行前哈希、逐项步骤、实际PASS/FAIL及断言；运行前后HTML与16文件都未改变。
- `RESULTS.md`：82项人可读清单，直接链接每项失败的原始状态和PNG。
- `runner-snapshot.cjs`：本次实际执行的脚本副本，其SHA必须等于results里的script.sha256。要复跑旧脚本，在隔离副本中把它放回 `tests/browser-regression.cjs`，使用新run ID；快照本身不直接从evidence目录运行。
- `screenshots.json`：每张原始PNG的SHA、view/page/theme/fixture/错误/引导步数；未裁剪、重绘或做图像美化。
- `X*-failure.json`：失败当时完整合成状态、可见文案与错误。所有记录/文件/聊天附件均为原型内置样本。

除 `RiftletDesign.reset` 用于独立用例准备、`getState` 用于只读对照外，测试通过真实 DOM 按钮、输入框、下拉框、鼠标与键盘操作，不直接调用导航/保存/权限函数实现PASS。浏览器内存态仅佐证可见行为，不是磁盘真实保存证明。`X3`是原型缺少独立状态的模型契约检查；`X7/X8/X9`是浏览器可见行为与main源码映射的兼容性对照，不是原生运行测试。

## 首轮记录也保留

[20261106-browser-01](evidence/20261106-browser-01/RESULTS.md)实际跑了78项，60 PASS / 18 FAIL，未删除或改写。它不是最终验收记录：

| 首轮项 | 结论与下一轮处理 |
| --- | --- |
| F3 | 选择器同时命中预览div与按钮；脚本限定button。 |
| F11 | 无变化时原型不渲染应用按钮，脚本错误地等禁用按钮；改为验证动作不可触发，不改变要求。 |
| S3/S4/S5 | 预期反向请求被拒绝，却用了必须切换成功的setChecked；改为真实单击一次并断言保留旧有效状态。 |
| A5 | 脚本用了不存在的1天选项；改为原型真实支持的3天并按真实时间戳计算四条记录。 |
| W3/A1/A2 | 确认归档输入失焦重绘吞掉第一次click；第二轮基础路径显式Tab后测试，并另加X12/X13直接首击的失败断言，未掩盖问题。首轮assert helper传undefined的Node错误也已纠正。 |
| X1–X9 | 首轮发现的真实状态/源码差异，第二轮独立重现，仍保留FAIL。 |
| 继承文件清单 | 首轮git相对子目录导致清单为空；不能据其布尔值证明16文件完整。第二轮从repo根枚举，强制数量16并比对；HTML单独哈希两轮都正确。 |

## 覆盖边界

已覆盖六页浅/深色、四种控制中心状态、暂停隐藏组合、右键菜单、全局草稿和应用、数字范围与空串、三个停止方向的写失败、反向请求失败、关闭确认、显示器身份与回退、归档、历史筛选、清空保留、反馈草稿、减少动态、按需模拟权限、三步引导。

独立核查补充：A3有效断言是visibleCount/records/files/attachments的合成状态不变量；其中`.desktop-rift`原型本来就没有这个元素，count=0不能证明裂缝从非空到消失的视觉变化。因此A3不作为空队列原生/桌面裂缝视觉验收；原始结果未覆写，按此范围解读。

没有运行：AppKit窗口/材质/真实菜单循环、VoiceOver、中文IME组字、真机拔插屏与UUID、TCC、磁盘权限及chmod失败、系统登录项、新外观持久化、真实截图/附加/START。原型没有独立的Chrome未授权、Chrome脚本禁用、存储检查失败评审入口；这些不能由folder失败替代，在交接列为原生验收项。页面截图不能证明所有小屏尺寸、字体缩放或辅助技术都已合格。

原型保留的失败行为不应被照搬到AppKit。设计可以交付用户评审；它没有达到“所有交互回归通过”，也不是新原生设置已可发布。
