# Riftlet 1.0.8（62）产品收口

普通用户照常截图，在桌面边缘点一下微图，即可将原图附加到点击时的可编辑 ChatGPT 草稿。草稿中的原文、选区和已有附件应保留。用户在 ChatGPT 中自行发送。

本候选的产品源码是 `871187f2be5eada68fccf2adcc07d120991e1c15`，签名 DMG 的 SHA-256 为 `66dedf34e9e224e2ba4ff18823e6b274434c205e3ad5f787990404e3859aec49`。build 62 修复了结果不确定时历史入口可能消失，以及用户知情确认后仍无法对原草稿重新附加的问题。公开放行状态与各项证据见[发行报告](RIFTLET_1.0.8_FINAL_RELEASE_REPORT.md)。

## 图片在何处，用户可以做什么

| 用户实际看到的情况 | Riftlet 的处理 |
| --- | --- |
| 原草稿没有开始接收图片 | 微图留在桌面。原图可查看，用户可以重新点击。 |
| 原草稿产生了可归属的 START | 微图收起，历史显示已交给 ChatGPT。原图留在本地资料库。 |
| 原卡明确报告这张图片失败 | 对应原图重新出现在桌面，下一次明确点击会产生独立操作。 |
| 附加结果尚未确认 | 保留原 PNG、操作和调用。用户可在截图仓库查看原图或返回原草稿检查。若仍要附加，先确认可能重复的提示，再点桌面原图。原目标无法重新核实时，图片继续保留。 |

重新附加前会核对原浏览器出生身份、窗口、标签、Document、Composer 和草稿代际。每次显式恢复使用新的操作、调用和点击绑定。迟到的旧收据只能关联原操作。已有同图附件时，风险提示的默认选项返回原草稿。[非作者恢复复核](evidence/build62/frozen-native-independent.json)

## 放行记录

- **用户恢复与数据。** 受控原生 A–H 和三份历史库副本通过。已核对同一 UNKNOWN 经风险提示、取消、显式新点击到新 START，另有原卡明确失败后恢复微图的用例。[原生 A–H](evidence/build62/frozen-native-recovery.json) · [历史库](evidence/build62/frozen-history-independent.json)
- **实站。** 普通 Chrome 和 Edge 的冷暖首图通过。Edge 三组双图为 568.318、616.109、650.829 ms。Chrome 和 Edge 均保留 64 字符正文、12→40 正向选区及原附件。Chrome 三组双图为 586.197、602.573、599.560 ms。两款浏览器均已由非作者从原始回执复核，零发送、零提交。[浏览器及逐项结果](RIFTLET_1.0.8_FINAL_RELEASE_REPORT.md)
- **工程和安装。** ARM64、Intel 及两项源码准入和 Feedback 检查通过。每种架构各通过 1,436 个 Swift 用例，受控网页回归 408/408。正式 DMG 已签名、公证、staple，独立安装核验的 193 个项目与签名包一致。[网页回归](evidence/build62/controlled-web-final.json) · [签名安装](evidence/build62/signed-package-independent.json)
- **升级。** 隔离 1.0.5（31）已通过正式签名的测试源实际升级至 62，原操作与 UNKNOWN 保留。首份隔离副本准备时重新复制了 32 个桌面文件，31 在下载 62 前已把这批新文件身份登记入库。第二份隔离副本按原 inode 恢复 32 个文件，实际测得 51→51。旧字段、2 条操作、UNKNOWN、START、86 个文件和 3 项设置逐一相同。普通截图入库、托盘点击和受控文件输入已核验，非作者对升级十三项全部判定通过。[升级裁决](evidence/build62/staging-thirteen-requirements-independent.json)
- **公开验证。** 公开后还须从独立 31 副本验证 stable 更新，并从两个正式下载入口复核实际字节。[升级起始快照](evidence/build62/upgrade-31-baseline.json)

历史实验尚未取得真实 ChatGPT 上游具名失败卡或 HTTP 4xx。A–H 验证的是 Riftlet 自身的恢复行为。实站结果另由最终签名包的普通浏览器记录证明。[G4 验收范围及历史](G4_FINAL_ACCEPTANCE.md)
