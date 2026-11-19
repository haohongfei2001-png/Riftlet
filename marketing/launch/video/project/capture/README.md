# Recording the released Mac app

The tracked edit inputs are [the continuous 24 s RGB recording](../../../source/edit/tray-lossless.mp4) and the two actual macOS window screenshots, [low](../../../source/edit/low-window.png) and [high](../../../source/edit/high-window.png). All three can be edited without another Mac capture. The [take receipt](../../../evidence/native-capture.json) identifies the release executable, source photographs, two collected copies and video. The [shot log](../../capture-log.md) identifies the shots used in the edits.

## Fresh capture

Use the mounted verified public build 20 DMG, a logged-in Mac graphical session, the Swift compiler, and a Python environment containing imageio-ffmpeg and Pillow. The native recorder checks the existing Screen Recording permission and the input helper checks Accessibility. Compile for the host architecture. For this take the Mac was arm64, macOS 27.0 and the primary display was 1920 × 1080 logical points at 2×.

Run from the repository root. Replace the DMG mount and Python path with those for the verified official build and the local tool environment.

```sh
mkdir -p build/launch-capture
swiftc -O -target arm64-apple-macos13 marketing/launch/video/project/capture/Stage.swift -o build/launch-capture/stage
swiftc -O -target arm64-apple-macos13 marketing/launch/video/project/capture/Take.swift -o build/launch-capture/take
python marketing/launch/video/project/capture/record.py /Volumes/Riftlet/Riftlet.app build/launch-capture marketing/launch/source/plates
```

The command prints a new take directory. The helper opens two original chart plates in owned, nonactivating native windows and places a 326 × 304 pt warm paper panel behind the tray. The release uses its real collector, SQLite database, renderer and accessibility actions in its UUID-scoped settings-review mode. The tray is set to the supported right-middle placement with system glass. This is local collection mode. Its web input is disabled.

The camera queries WindowServer each frame, including only the stage's own paper window and the identified release process's onscreen floating layers intersecting the stage. It records the original 2× region. The chart photographs come separately from the macOS `screencapture` command targeting the two chart window IDs. Both original PNGs in this take already carried the macOS screenshot marker. The input helper never moves the system pointer. It addresses the freshly started review process and checks the control label and owned hit window before posting mouse events. The macOS cursor is absent from the shot.

Run the following command with the new take directory only when preparing a new delivery. It refuses a conflicting existing source recording. The publicly tracked source compresses the original losslessly. The script decodes both complete video streams and compares their RGB checksums. For each window PNG it strips file metadata, checks all four unchanged RGBA channels including the corner transparency, and preserves the untouched original in the ignored local raw directory.

```sh
python marketing/launch/video/project/capture/preserve.py build/launch-capture/TAKE-UUID marketing/launch
```

## What the camera recorded

At 30 fps the first duration is measured from frame zero. The source has 720 frames, one actual WindowServer sample for every frame. The medium is silent. The median observed sampling interval was 33.30 ms and the longest was 50.34 ms.

| Film time | Visible event and supporting observation |
| --- | --- |
| 0–2.33 s | Empty tray with the enabled capture-entry button. |
| 2.37–2.53 s | First photograph arrives. The release has imported the low-water image and its private copy matches the original PNG byte for byte. |
| 7.37–7.53 s | The tray makes its second row and displays the high-water image. Both screenshots have distinct hashes and both copies match. |
| 12.07–12.27 s | macOS Accessibility presses the camera button of the shipped app. Four actual menu controls become visible. |
| 15.47–15.63 s | The actual menu closes. It had already dismissed by the time the script checked for Escape. The trigger is undetermined. |
| 18.74–19.14 s | A software left-button down/up pair was posted to the owned input island for the low-water image. No changed pixels were captured. This is not used to establish a successful thumbnail press or attachment. |
| 20.07–20.17 s | macOS Accessibility invokes the high-water thumbnail. The original card border briefly darkens/changes. The strongest source frame differs from the pre-press frame by up to 11 of 255 at that card, with 3,759 pixels changing by more than two levels. The status is still pending. |

No browser, attachment receipt, network response, send, or cursor motion appears in these sources. Historical on-page acceptance belongs to build 18. One technical setup take stopped on a macOS extended attribute API mismatch. A second stopped waiting for a PID-only Escape, and another found the menu had already dismissed. Those local takes were retained separately. The completed recording uses a fresh UUID and continually sampled the whole sequence.
