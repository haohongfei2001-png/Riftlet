# W2 / W6 browser host evidence

Observed on 2026-11-20. These probes exercised five actual signed browser applications using a six-byte synthetic file and an empty, isolated profile or disposable guest. The product executable and logged-in provider sites were outside this run. Product L2 and all 16 live host/provider cells remain untested by this packet. No additional host can be admitted on these results.

| Browser | Actual native evidence | Remaining host gate |
| --- | --- | --- |
| Chrome 157.0.8103.79 | Signed bundle declares stable window/tab IDs and tab-scoped `CrSuExJa`. Nonprompting CLI query returned 0. A fresh headless profile accepted the PID-addressed native count and reported one window. | The probe sender does not establish candidate permission, immediate click binding or any provider receipt. Preserve current production integration separately. |
| Edge 157.0.4341.60 | Same declared interface; the distinct Edge receiver in the isolated profile returned one window. | Same product-boundary checks as Chrome, including the original Edge process. |
| Brave 1.100.58 (bundle 158.1.100.58) | Its actual dictionary declares the Chromium command and tab/window IDs. A separate fresh headless profile ran the page fixture. Nonprompting permission on its exact PID returned −1744. | The native command and its realm, ordinary profile/Shields interactions and original return path remain unobserved. The existing headless result cannot qualify Brave for dispatch. |
| Safari 27.0 dictionary, ordinary Safari 27.2 in a macOS 27.2 guest | Native window ID; `sfridojs` declares document or tab. The tab class exposes index, URL and a hidden web-process PID. No public native tab ID was found in its dictionary. Ordinary Safari passed the page fixture. | **S1 BLOCKED_ENV.** The independent CLI sender received −1744. A private test app made a normal first-use request. The guest had no attached view, standard guest screenshot could not create an image, and its System Events UI bridge returned −1743. Neither a grant nor JS via Apple Events nor reassignment of the original specifier was observed. |
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
