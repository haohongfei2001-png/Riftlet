# W2 / W6 browser host evidence

Observed on 2026-11-20. These probes exercised five actual signed browser applications using a six-byte synthetic file and an empty, isolated profile or disposable guest. The product executable and logged-in provider sites were outside this run. Product L2 and all 16 live host/provider cells remain untested by this packet. No additional host can be admitted on these results.

| Browser | Actual native evidence | Remaining host gate |
| --- | --- | --- |
| Chrome 157.0.8103.79 | Signed bundle declares stable window/tab IDs and tab-scoped `CrSuExJa`. Nonprompting CLI query returned 0. A fresh headless profile accepted the PID-addressed native count and reported one window. | The probe sender does not establish candidate permission, immediate click binding or any provider receipt. Preserve current production integration separately. |
| Edge 157.0.4341.60 | Same declared interface; the distinct Edge receiver in the isolated profile returned one window. | Same product-boundary checks as Chrome, including the original Edge process. |
| Brave 1.100.58 (bundle 158.1.100.58) | The actual dictionary declares the Chromium command and tab/window IDs. The headless page fixture passed. In a separate normal guest, a dedicated sender received consent and read the native numeric window and tab IDs. | The default browser setting refused JavaScript with error 12. The signed product path, ordinary Shields conditions on a real provider, browser realm and original reply remain unverified. [Guest receipt](guest-c/brave.json) |
| Safari 27.0 dictionary, ordinary Safari 27.2 on two macOS 27.2 guests | Native window ID; a tab has an index and a web-process PID. In guest C, standard consent succeeded and the normal JavaScript setting enabled a read-only page sentinel. | **Mutable cold tab index disproved.** The captured specifier resolved to a different document at the identical URL after its original tab closed. An alternative stable native identity or proven click-boundary snapshot is still needed. |
| Firefox 160.0.1 | Signed bundle sets `NSAppleScriptEnabled`; its inspected resources expose no web JS scripting dictionary. Both a fresh headless process and an ordinary guest Firefox passed the local page fixture. | **W6 AX route BLOCKED_ENV.** The ordinary guest probe confirmed its own Firefox PID and returned `ACCESSIBILITY_NOT_GRANTED`. It opened no picker and entered no path. Draft-specific attachment receipt and chooser cancellation remain unobserved. No equivalent Firefox host has been demonstrated. |

The per-process qualifier is the executable bundle path, PID, and independently reread kernel process birth. Ambient Chrome/Edge processes received only the nonprompting permission query. The second, fixture-only query requires a process owned by the launcher before sending the native window-count event. A CLI sender with status 0 cannot establish authorization for a signed Riftlet candidate. Status −1744 means consent would be needed, and is distinct from explicit denial.

## What the page actually established

Each browser's own fixture script used a file input and DataTransfer to round-trip bytes `52 31 32 30 00 ff` through one `input` followed by one `change`, preserving the textarea value and selection [2,7]. A same-URL, same-state `replaceState` preserved URL, state and history length; both replace and push created a different Navigation API entry ID in each tested binary. Replacing the editor also preserved the URL. Timing, navigation epoch coverage, React acceptance and a durable provider receipt require separate tests. In particular no Safari older than 26.2 was available. The fixture demonstrates why a URL/history-length fallback would be insufficient there. The three executable model counterexamples separately cover reused tab slots, a fresh nonce first installed after a swap, and two distinct payloads with the same accessible filename, size and count.

All five bundle code signatures and Gatekeeper assessments were accepted. An additional strict Finder-metadata signature check failed for Brave on this machine, including the framework on its unmodified mounted official DMG. The standard all-architecture signature/publisher check and Gatekeeper assessment passed independently. The official Brave and Firefox DMG SHA-256 values and vendor checksum sources appear with the raw, redacted native and page observations in [evidence.json](evidence.json).

## Reproduce selectively

Run from this directory on macOS with Command Line Tools. Supply exact signed paths for browsers in optional private installations. The inventory reads bundle metadata and runs a nonprompting permission check on already-running receivers. The headless command starts its own temporary browser profile with a loopback-only fixture server. Neither requires a regular browser window.

```sh
python3 inventory.py --brave "/path/to/Brave Browser.app" --firefox "/path/to/Firefox.app"
scratch=$(mktemp -d)
swiftc -parse-as-library ReceiverProbe.swift -o "$scratch/receiver"
RIFTLET_FIXTURE_RECEIVER="$scratch/receiver" ruby browser-fixture.rb "/Applications/Google Chrome.app"
node --test locator-negatives.test.mjs
```

For the native guest probes, use a disposable macOS guest with an empty browser session. Copy the source fixture (`fixture.html` beside `browser-fixture.rb`) and compiled helpers into the guest. On that guest:

```sh
swiftc -parse-as-library SafariColdProbe.swift -o "$scratch/safari-cold"
swiftc -parse-as-library FirefoxAXProbe.swift -o "$scratch/firefox-ax"
RIFTLET_DISPOSABLE_SAFARI_GUEST=yes ./safari-guest.sh "$scratch/safari-cold"
RIFTLET_DISPOSABLE_SAFARI_GUEST=yes ruby browser-fixture.rb /Applications/Safari.app
RIFTLET_DISPOSABLE_FIREFOX_GUEST=yes RIFTLET_FIREFOX_AX_PROBE="$scratch/firefox-ax" \
  RIFTLET_FIXTURE_RECEIVER="$scratch/receiver" ruby browser-fixture.rb "/path/to/Firefox.app"
```

The Safari cold probe verifies the single local fixture before attempting an original-tab capture, same-URL substitution, and resolution of the original specifier. To exercise a first-use dialog, an appropriately signed test app with `NSAppleEventsUsageDescription` can run the same executable with the original fixture URL, `--request-on-disposable-vm`, and an output file in the fixture directory. This run had no attributable actionable guest display. A guest with a usable display and ordinary explicit consent is required to measure S1. A historical Safari macOS guest is separately needed for the older-Safari matrix. The Firefox AX probe requires its own normally trusted test sender and a dedicated guest Firefox; a visible file picker alone still falls short of an original-draft, exact-file receipt. Both test VM sessions shut down normally, with their stop events recorded in the evidence.

### Independent second guest

On an independent macOS 27.2 guest, the test sender went through the ordinary macOS Automation consent dialog. With exactly one synthetic draft open, Safari returned a tab object specifier with key form `indx`. Closing that tab made the same captured specifier address another document deliberately opened at the identical URL. The documents had distinct randomly generated titles. The result persisted with Safari's JavaScript preference off, normally enabled, and restored. Only the enabled state could read the page sentinel. The probe neither attached a file nor sent a message. A mutable index cannot qualify for the isolated contract's cold-click path. [Sanitized native receipt](guest-c/safari.json)

### C 客机按权限原样查询浏览器 AX 窗口

在 macOS 27.2 的独立 C 客机普通图形登录会话中，依次用 Safari、Firefox 和 Brave 打开同一合成本地页面。客机的虚拟显示器由无宿主窗口的 VZ 进程驱动。系统 Safari 来自系统 Cryptex；另两个普通浏览器由已验证签名与 Gatekeeper 的专用副本启动，使用默认模式。专用探针通过 Launch Services 运行，对唯一浏览器进程调用 AXIsProcessTrusted 和 AXUIElementCopyAttributeValue(kAXWindowsAttribute)。探针只查询窗口，未请求或获授额外权限。源文件 [AXWindowProbe.swift](AXWindowProbe.swift) 的 SHA256 为 0289ec2feadc5937b32787c996324ebda48b3899461839a1df03f2b57ddb210c，客机实测运行文件 SHA256 为 e2bf7c7abca837f60c9a901a08b27c3423f8966943dda68e9f2215719f3af5dd。

[三份原始收据](guest-c/ax-default.ndjson)中，Safari 27.2 返回 -25211，Firefox 160.0.1 与 Brave 158.1.100.58 返回 -25204。三个目标均显示调用方 AXIsProcessTrusted=false；未获取窗口或草稿。现有窗口外远程控制通道仅 SSH；客机 loopback 5900 无监听，终端检查自身 AX 信任亦为 false。Safari 的 AX 标签替换、导航及 ABA，Firefox 的选择器归属及卡片，以及 Brave 经不同执行环境的原稿回执仍未验证。需由能正常操作隐私设置的隔离图形会话为实际测试 sender 授权后再继续。已有 Safari tab 索引错投反例和 Brave 默认 JS 错误 12 的独立收据仍适用。Riftlet 产品权限、浏览器支持与登录站点均未从此次探针推断。

首次读取系统 Safari 时，探针只接受 /Applications/Safari.app，因实际进程使用系统 Cryptex 路径而未留下收据。增加该系统路径后，对三个目标用同一探针全组采集。关闭采集所用的三个浏览器，核对测试进程为零、移除临时页面与应用副本后，客机执行正常关机。

### Same Safari window across draft changes

On an isolated macOS 27.2 guest, ordinary Safari 27.2 opened a loopback page in the existing guest profile. At four checkpoints the native observer saw the same foreground Safari process birth and the same sole visible layer-zero WindowServer window. Within that window, replacing and restoring the exact editor, returning to the original navigation entry at the same URL, and reloading the document each caused the original compiled read-only discovery handle to refuse. The original and each newly bound handle ran their positive callback. The history read finished within the existing pin lifetime. The reload produced a new global and a reload navigation entry. Window identity alone would therefore have missed all three changes. [Sanitized receipt](safari-epoch/receipt.json)

The fixture executes the production `ProviderDiscoveryPin` in a page script. Actual Safari tab-scoped Apple Events addressing, asynchronous native receipt and provider attachment remain unverified. A preliminary native count from the guest shell timed out with −1712. The first visible but unfocused page correctly refused its read. After a normal guest restart the focused fixture completed. The originally stopped Safari exited and the guest shut down normally. The guest's Brave Default profile directory was absent before and after this run. Brave was not started.

To reproduce, build the checkout's debug RiftletAdapters target on a development Mac and link [export.swift](safari-epoch/export.swift) using the module paths and object files from [the compiled provider check](../../../../Tests/WebPageProgram/Issue120/check-compiled.sh). Copy the exporter, [probe.js](safari-epoch/probe.js) and [run.rb](safari-epoch/run.rb) to the same directory on a reserved disposable Mac guest with an existing Safari profile and Safari closed. Run `RIFTLET_DISPOSABLE_SAFARI_GUEST=yes ruby run.rb ./export` there. The runner verifies Safari's signature, serves only the local fixture, compares the native samples in memory and checks that its browser process exits.

### Brave original-tab URL when the optional properties reply is absent

The candidate Brave host now handles a missing `pALL` reply after the absolute window/tab object has arrived. The optional record can exceed the 64 KiB receive buffer or its wait budget. A single `URL` property read targets the captured object and shares the original click deadline. A present record with a mismatched tab or unrecognized structure still retires the capture.

The debug RiftletAdapters target built on arm64 macOS. In an ordinary AppKit process with no windows, [the native receipt probe](BravePinnedURLProbe.swift) received the product's Apple Event addressed to synthetic window 11/tab 22 and returned its URL. The recipient counted one read. An expired second request never arrived. A separate compiled replay observed one original-tab lookup for the absent record and zero for an available valid record, a conflicting ID, a malformed record and a missing absolute identity. The replay also rejected an HTTP URL. The local Command Line Tools installation could not load XCTest to run the repository test target.

This checks native URL property addressing. Brave's page execution world, document epoch and asynchronous JavaScript receipt remain unverified. The C guest's earlier QA sender grants and temporary profiles were removed. This run opened no browser.
