# 修正版复验

最终 HTML `c58e4c7a3fa717a2fc5f68e8aaaf90e7950363a52c4047be182f9cb81fd67b58`；Node 26.8.2、Playwright 1.58.2、Chromium headless 156.0.8078.4、macOS arm64、1440×1100、zh-CN / Asia/Shanghai。使用独立 headless profile，不接管用户 Chrome、不访问 ChatGPT。

从仓库根目录运行（每次 RUN_ID 使用新目录；PLAYWRIGHT_MODULE 可指向已安装模块，BROWSER_EXECUTABLE 可指定 headless shell）：

```sh
python3 design/settings-center-20261106/revision-2/prototype/build.py
RUN_ID=review-82-new node design/settings-center-20261106/revision-2/tests/browser-regression.cjs
RUN_ID=review-editing-new node design/settings-center-20261106/revision-2/tests/editing-stability.cjs
RUN_ID=review-visual-new node design/settings-center-20261106/revision-2/tests/visual-evidence.cjs
```

| 记录 | 实际结果 | 地位 |
|---|---|---|
| 上级 evidence/20261106-browser-02 | 69 PASS / 13 FAIL | v1 不可改写基线 |
| evidence/20261106-v2-browser-01 | 82/82 PASS，较早 HTML 76bf354b… | 迭代证据；含 HTML/build 快照 |
| evidence/20261106-v2-editing-01 | 20 行为断言 PASS，脚本在运行间变化，scriptUnchanged=false / success=false | 保留失败，不用于最终准入 |
| evidence/20261106-v2-browser-final | 82/82 PASS，无基础设施错误/外部请求 | 最终原用例 |
| evidence/20261106-v2-editing-final | 21/21 PASS，success=true，输入/脚本/v1不变 | 最终补充用例 |
| evidence/20261106-v2-visual-final | 18 张原始 PNG，errors=[] | 视觉材料与有限 DOM 检查，不称18项完整交互用例 |

最终三组共 76 张原始 PNG，逐图 SHA 在各截图索引/visual-results.json。原 82 用例主体 SHA-256 `b86d9a576b3915c84e068dcedb993540ca3a6ebf687951ff80fd0a374dc40f60`，与 v1逐字节一致；runner仅变更输入身份和结果目录/守卫，不放宽断言。

所有模拟重置仅用于准备；交互通过浏览器 DOM 点击/键盘输入，状态读取不替代动作。补充归档案例只执行一次 mouse down/up，不靠失焦预操作或点击重放；刷新稳定性等待真实 toast/动画计时。截图未经编辑。

范围：浏览器设计原型，不写配置文件、不调系统权限/登录项、不调用原生上传。A3不证明真实裂缝隐藏；DOM composition不是物理输入法；显示器/旧配置均为合成模型。AppKit、VoiceOver、TCC、磁盘写后故障、物理多屏和最终截图附件仍须原生阶段验证。
