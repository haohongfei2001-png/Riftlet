# 独立单文件导出修复

本轮基于设计分支 `276574a44485c17821a5ce3e0195116e83e9fad8`，只修改交付管线、导出、文档和本目录证据。`prototype/app.js`、`settings.js`、CSS、样例、原 SVG 与全部旧截图/视频保持原字节。

| 身份 | SHA-256 |
|---|---|
| 初始坏 HTML | `54b4dda6630916594a0e4d8e9f7fd08591e0ae1c7bf32f30f4081cddc918d892` |
| 修复后 HTML | `2c4afdf1aa7fb3b926f3060636c84e2c98f04d82ac7abf75c805e96dad2a33c5` |
| 原品牌 SVG | `f31d71318e1aaef2464bbcc25c5a105fa6959d10006eb7c64d30aac42fbb3e90` |

## 诊断与生成修复

[before-standalone.html](before-standalone.html) 是原始坏文件的逐字保留，仅供复现，不能作为交付入口。[before-result.json](before-result.json) 和 [空白图](before-broken-standalone.png) 记录真实浏览器错误：`Identifier '$' has already been declared`，根节点 0 子项、原型 API 不存在。源里 4 处 `$$` 在旧导出中全被变成 `$`。

[original-builder-result.json](original-builder-result.json) 记录未改 Python builder 重建：4 处 `$$` 保留，Node 语法 PASS。这排除了 Python 字面 `str.replace` 自身折叠 `$` 的说法；损坏形式符合 JavaScript replacement string 的 `$$` 处理，但没有证据确认旧产物当时的生成命令。

现在 builder 在写入 HTML 前检查内联 JS/CSS 与源文件的逐字一致性、模板唯一性、Node 语法与资源自包含；不会以“文件生成成功”代替脚本可运行。另固定 Python 依赖、要求可用中文字体、记录构建环境并固定 ZIP 顺序/时间/模式。可复现边界是同一依赖和字体环境，不承诺不同字体或图像编码器跨环境字节相同。

## 实际检查

- [生成门禁测试结果](validation-tests.json)：5 个真实故障注入/基准检查 PASS；脚本与原始 unittest 日志均有 hash。
- [headless-01/results.json](headless-01/results.json)：原始 10 PASS / 3 FAIL；[原 runner](headless-01/runner.cjs) 与错误截图原样保留。[interpretation](headless-01/interpretation.json) 说明空态断言误把详情提示一起计数，后续未清搜索导致两个连带失败。
- [headless-02/results.json](headless-02/results.json)：仅将同一空态断言限定到列表区域，原型/HTML 未改；13/13 PASS，pageerror 0，外网请求 0。
- [构建重复性](reproducibility.json)：记录同一冻结输入下连续两次构建的产物与 ZIP 对照；最终交付清单以根 `MANIFEST.json` 为准。

浏览器真实操作覆盖：默认当前视图，两种样式往返，搜索/状态筛选/选中与记录身份不变，空搜索结果，六页设置导航，设置与历史共享偏好，原图缩放/Escape，反馈 focus trap/Escape，4 个前后对照图适配，以及并排视图共享选择。未直接写业务状态以制造 PASS，只读状态用于断言。

使用 Playwright 1.65.0 的独立 Chromium headless-shell 156.0.8078.4，临时上下文，1200×1000 viewport、DPR 1。无用户 profile、已有浏览器连接、可见窗口、浏览器权限更改、生产 App 或网络业务请求。

## 当前截图与范围

`headless-02/` 的 8 张 PNG 是本轮 HTML 实际渲染；尺寸/hash 记录在结果文件。作者目视抽查当前列表浅色、双栏深色、历史设置浅色与重生成总览图：主界面、品牌与双样式可见，中文图版文字可读。历史设置为可滚动页，截图不声称展示所有滚动内容。未把这些抽查称为独立设计批准或完整辅助功能认证。

原型保留网页模拟语义；本轮没有重新设计、实现原生历史双样式、验证真实附件，也没有执行原生中文输入、VoiceOver 或物理菜单栏。历史总览、Before-After 与录像的原图来源仍属于旧捕获，不因重生成包装或字体而变成本轮实机证据。
