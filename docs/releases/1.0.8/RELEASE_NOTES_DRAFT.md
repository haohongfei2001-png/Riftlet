# Riftlet 1.0.8（build 62）发行说明草稿

## 中文

- 点击桌面边缘的截图时，Riftlet 会核对原来的浏览器窗口、标签和 ChatGPT 草稿。连续点击两张截图时，每张图片分别核对和附加。
- 上传结果尚未确认时，可以在截图仓库查看原图、返回原草稿或选择「重新附加」。如果草稿中可能已有这张图片，Riftlet 会提示重复风险。只有确认后再次点击桌面的原图，才会发起新的附加。原窗口或草稿已关闭时，仍可在仓库查看原图。
- 如果原草稿明确报告这张截图上传失败，Riftlet 会让已收起的截图重新出现。关掉并重新打开 Riftlet 后，原图和原操作记录依然保留。
- 改进了 ChatGPT 将预览显示为 WebP 时对原截图的识别。消息仍由你在 ChatGPT 中发送。

适用于 macOS 13 或更高版本的 Apple 芯片和 Intel Mac，网页附加面向普通 Google Chrome 和 Microsoft Edge 中可编辑的 ChatGPT 草稿。可从 Riftlet 菜单选择「检查更新…」。

## English

- Clicking a screenshot at the desktop edge checks its original browser window, tab, and ChatGPT draft. When you select two screenshots in succession, Riftlet checks and attaches each one separately.
- When an upload result is uncertain, your library lets you view the original, return to the draft or choose **Attach Again**. If the image may already be there, Riftlet warns about a duplicate. Confirm and click the desktop screenshot to attach it again. The original remains available after you close the draft.
- A screenshot reappears when the original draft reports an identifiable failure for that image. Its saved copy and transfer record survive an app restart.
- Riftlet recognizes the original screenshot when ChatGPT displays its preview as WebP. You send the message from ChatGPT.

Requires macOS 13 or later on Apple silicon or Intel. Web attachment is for editable ChatGPT drafts in ordinary Google Chrome and Microsoft Edge. Use **Check for Updates…** in the Riftlet menu to update.

## 候选核验记录

产品提交为 `871187f2be5eada68fccf2adcc07d120991e1c15`。DMG 为 `Riftlet-1.0.8.dmg`，14,225,854 字节，SHA-256 为 `66dedf34e9e224e2ba4ff18823e6b274434c205e3ad5f787990404e3859aec49`。ARM64 和 Intel 各 1,436 项 Swift 用例、408 项网页回归、Developer ID、公证、staple、Gatekeeper 与独立安装通过。[工程与安装回执](RIFTLET_1.0.8_FINAL_RELEASE_REPORT.md)

产品级 A–H 与三份历史数据库副本通过。实际 ChatGPT 上游具名失败卡及 HTTP 4xx 缺少实站证据。Edge 双图及 Chrome 非空选区已有同包记录。Chrome 双图、Edge 非空选区及发布前隔离 31→62 升级正在验收。正式发行范围以发行报告为准。[浏览器和升级状态](RIFTLET_1.0.8_FINAL_RELEASE_REPORT.md) · [恢复行为](G4_FINAL_ACCEPTANCE.md)
