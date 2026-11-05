# 修正版 2 独立实现审查

2026-11-06｜审查者 `independent_review`。本人是补充 21 项测试的作者，对 JS、CSS、原 82 项用例及集成运行进行非实现作者审查；不把本人测试称为非作者审查成果。未修改产品源码、v1、refs、用户浏览器或运行中的 App。

**结论：DESIGN_V2_REVIEW_PASS。修正版设计候选可交付，未发现剩余交付阻断。** 这不是原生实施完成、正式产品源码准入或用户最终视觉批准；原生仍为 **NOT_RUN**。

| 最终对象 | SHA-256 |
| --- | --- |
| 单文件 HTML，120030 字节 | `c58e4c7a3fa717a2fc5f68e8aaaf90e7950363a52c4047be182f9cb81fd67b58` |
| `prototype/app.js` | `b0d5f5e4e7b87da68c5791f5e078fcba2b42c126ceff1a6fd8b40ecb7dc0ba34` |
| `prototype/style.css` | `c34b93583a63305152d3cb4088a911fb8eb4963fac514f5046df191867e250c6` |
| 原 82 项 runner | `313493a8ceb2cf24ac30cd912e42da6058f10a469f57a19206d08702b9b33d30` |
| 补充 21 项 runner | `c630fa6eb3a2a3f2f1579c77c652d6c12b79e73c7a7a3b32b8f7025b9c53d01b` |

## 实际核对结果

| 最终运行 | 结果与范围 |
| --- | --- |
| [browser-final](evidence/20261106-v2-browser-final/RESULTS.md) | 82/82 PASS；X1–X13 全部通过，原用例主体逐字节相同，没有删除或放宽断言。 |
| [editing-final](evidence/20261106-v2-editing-final/RESULTS.md) | 21/21 PASS，`success=true`；输入稳定性、多错误与逐域重试、首击、键盘、七个非默认兼容字段及 40/0ms 边界。 |
| [visual-final](evidence/20261106-v2-visual-final/visual-results.json) | 18 张原始截图、无页面错误或外部请求；这是视觉材料及有限 DOM 检查，不额外计为 18 项完整交互测试。 |

三组运行对应同一最终 HTML；脚本快照、当前脚本与记录哈希一致。核对全部 76 张 PNG 的文件哈希，未发现差异。两组回归没有基础设施异常或外部请求；HTML、补充脚本及受保护 v1 文件在最终运行中保持不变。

另以 Git blob 对照 v1 提交 `6372bcf3fbeb71cb7ad2d930cad18528e2d54796` 的全部 164 个文件，无修改。`Sources`、`Tests`、`Package.swift` 与正式 main 基线 `b61fc46cf931bdbd14deec1b47d077e92db61e16` 无差异。v1 的 69 PASS / 13 FAIL 原证据仍在；首轮 v2 的 20 项行为断言通过但脚本变化令整体 `success=false`，只能作为迭代记录。

## 实现与画面判断

按域保存结果和最后确认值已分离；无关成功、权限恢复及放弃布局不会清掉其他域错误。重试携带明确目标，实际确认值逐域更新，不以 toggle 推导目标。失败不冒称磁盘必旧。

同一界面的后台刷新保留原输入节点，独立状态区正常更新；归档 change 不重建点击目标。补充用例记录真实提示/动画定时结束前后的节点身份、文本、焦点和选区，并验证组合态 Enter 不提前提交。归档首击用一次 Playwright mouse down/up 验证，没有预先 Tab 或点击重放；这是 headless 浏览器动作，不是物理鼠标或 WindowServer 验收。

七个兼容字段使用非默认旧值准备，实际应用及两页恢复后仍逐值保留；主屏保存具体合成身份，历史 select 纳入焦点循环。CSS 延续原六页和层级，主要改善字号、对比、目标尺寸和滚动。实施交接明确这些行为仍需接回真实 owner。

人工查看 16 张代表图：browser-final 的 P1–P6、D2、C5、W4、O3-step3；editing-final 的 R1、R3；visual-final 的 light-display-fine、dark-motion-fine、light-layout-save-error、compact-display。确认六页、深色、暂停/隐藏说明、错误与关闭确认可读，详细参数仍可通过滚动到达。未把其余截图都称为人工验收，也未将截图中的滚动位置当作内容缺失。

## 保留边界

- A3 仍只证明合成队列/记录/文件/附件不变量；原本不存在的 `.desktop-rift` 不能证明真实裂缝视觉消失。
- composition 测试是 DOM 合成事件，旧配置 fixture 是模拟读取；不是系统中文输入法或磁盘迁移验证。X3/X9 同样是模型/源码契约检查。
- 真机 AppKit、VoiceOver、TCC、Chrome 权限、磁盘写后故障、系统登录服务、物理多屏、截图/附件/START 均为 NOT_RUN。视觉记录不证明所有窗口尺寸、动画时间轴及辅助技术均已合格。

本报告对应上列固定字节及最终运行；后续实现继续按交接和真实源码治理，不借本设计审查扩大产品能力或已有个人 Beta 的验收范围。
