# Your first screenshot with Riftlet

Use a build explicitly supplied by the maintainer and read [Installation and permissions](INSTALL-AND-PERMISSIONS.md). The current personal build is not a notarized public release.

1. **Open Riftlet.** Use its menu bar icon. You can reopen the guide from Settings → Permissions & Help (`权限与帮助`) → `使用引导…`.
2. **Check the screenshot folder.** Settings shows the detected macOS screenshot location. If access is needed, choose `允许访问此位置…` and grant access to that displayed folder. Riftlet does not change the macOS save location or import every old image in it.
3. **Take a non-sensitive screenshot.** Use your normal macOS shortcut and save a file. After it is saved, a thumbnail appears at the screen edge. Clipboard-only captures are not collected. See [Apple’s screenshot guide](https://support.apple.com/en-au/guide/mac-help/mh26782/27/mac/27).
4. **Open the intended ChatGPT draft in Chrome.** Wait for the new or existing chat to load and allow image attachments. The text editor does not need keyboard focus. For the first connection, follow the separate Automation and Chrome JavaScript steps in the [permissions guide](INSTALL-AND-PERMISSIONS.md).
5. **Click the thumbnail once.** Riftlet binds the Chrome window and tab at click time. When the draft starts accepting the new image, the thumbnail retracts. You can then click a different screenshot. Riftlet does not send the message; check ChatGPT before sending it yourself.

**Retraction means START: the draft has begun accepting the image. It does not certify final network upload or message delivery.** The ordinary handoff stops tracking that upload after START. The local image and history record remain available.

## Controls and recovery

- **Pause collection (`暂停收录`)** stops collection while paused and keeps existing images. When you resume, eligible files still in the screenshot folder may be collected, including screenshots saved during the pause.
- **Hide rift (`隐藏裂缝`)** hides edge thumbnails without changing collection.
- **Enable built-in capture (`启用内置截图`)** controls Riftlet’s own capture entry, independently of macOS screenshots and file collection.
- **History & Storage (`历史与存储`)** opens local history. `当前视图` is the default list; `图像网格` is the optional image grid. Both show the same records and preserve the selected image, search and filter when switching.
- Save layout or archive edits before closing. If you close with edits, choose continue editing, discard, or apply and close. A failed save keeps the draft.

If a message explicitly says no attachment occurred, fix the stated issue and click again. If the result is **unconfirmed / needs review**, check the original chat first. Do not force a resend by clearing data or reimporting the image. Use [Recovery and FAQ](RECOVERY-AND-FAQ.md) and the [privacy-safe feedback template](FEEDBACK-TEMPLATE.md).

The native interface currently contains Chinese labels and some English history states. This guide provides English navigation; it does not claim complete English localization.
