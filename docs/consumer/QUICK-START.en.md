# Your first screenshot with Riftlet

Use a build explicitly supplied by the maintainer and read [Installation and permissions](INSTALL-AND-PERMISSIONS.md). The current personal build is not a notarized public release.

1. **Open Riftlet.** Use its menu bar icon. You can reopen the guide from Settings → Permissions & Help (`权限与帮助`) → `查看引导…`.
2. **Check the screenshot folder.** Open Settings → Capture (`截图`) and look under `截图保存位置`. If access is needed, choose `允许访问此位置…` and grant access to that displayed folder. Riftlet does not change the macOS save location or import every old image in it.
3. **Take a non-sensitive screenshot.** Use your normal macOS shortcut and save a file. After it is saved, a thumbnail appears at the screen edge. Clipboard-only captures are not collected. See [Apple’s screenshot guide](https://support.apple.com/en-au/guide/mac-help/mh26782/27/mac/27).
4. **Open the intended ChatGPT draft in Chrome.** Wait for the new or existing chat to load and allow image attachments. The text editor does not need keyboard focus. For the first connection, follow the separate Automation and Chrome JavaScript steps in the [permissions guide](INSTALL-AND-PERMISSIONS.md).
5. **Click the thumbnail once.** Riftlet binds the Chrome window and tab at click time. When the draft starts accepting the new image, the thumbnail retracts. You can then click a different screenshot. Riftlet does not send the message; check ChatGPT before sending it yourself.

**Retraction means START: the draft has begun accepting the image. It does not certify final network upload or message delivery.** The ordinary handoff stops tracking that upload after START. The local image and history record remain available.

## Controls and recovery

- **Pause collection (`暂停收录`)** stops collection while paused and keeps existing images. When you resume, eligible files still in the screenshot folder may be collected, including screenshots saved during the pause.
- **Hide desktop screenshots (`隐藏桌面截图`)** hides edge thumbnails without changing collection.
- **Show capture entry (Settings → `截图` → `显示截图入口`)** controls Riftlet’s own capture entry, independently of macOS screenshots and file collection.
- Under **Appearance & Layout (`外观与布局`)**, choose the screenshot tray, wind chime or micro slit, a display and an edge position. New wind chime selections use staggered thumbnails. An existing R1 wind chime keeps its aligned arrangement. Switch either way under `风铃排列` or adjust its cord inset under `高级布局与动效 → 详细自定义`. Expand `高级布局与动效` to adjust or preview motion.
- Open **Screenshot History (`截图历史`)** from the menu bar control center or via Settings → `使用与历史` → `打开历史…`. Switch between the default list (`列表`) and the image grid (`图像网格`) while keeping the current page, selected image, search and filter.
- By default, a thumbnail disappears from the desktop after 2 idle minutes. You can still find it in Screenshot History. In Settings → `使用与历史`, choose 1, 2, 5 or 10 minutes, enter a custom duration between 1 and 10 minutes (such as 1.5), or select `关闭` to turn it off. Save to apply. Archiving waits while the pointer hovers over a thumbnail or the mouse button is held on it. The original file and local copy stay available.
- Save layout or archive edits before closing. If you close with edits, choose continue editing, discard, or apply and close. A failed save keeps the draft.

If a message explicitly says no attachment occurred, fix the stated issue and click again. If the result is **unconfirmed / needs review**, check the original chat first. Do not force a resend by clearing data or reimporting the image. Use [Recovery and FAQ](RECOVERY-AND-FAQ.md) and the [privacy-safe feedback template](FEEDBACK-TEMPLATE.md).

The native interface currently contains Chinese labels and some English history states. This guide provides English navigation; it does not claim complete English localization.
