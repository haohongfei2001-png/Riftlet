# Final headless visual verification

Source: 7d19037611c1228a2397cf44ed47bddd8f390213, independent design branch. Browser: installed macOS Google Chrome, headless, Playwright ephemeral context. No production app activation, user Chrome profile, real capture or attachment transport.

## Deliverables

- history-light-crop.png / history-dark-crop.png: actual rendered window crops; complete footer verified.
- desktop-edge-2x.png / desktop-edge-hover-2x.png: actual rendered P0 detail at deviceScaleFactor 2.
- riftlet-motion.webm: actual CDP JPEG page frames, re-encoded by browser Canvas + MediaRecorder at their recorded timestamps.
- motion-manifest.json: frame timestamps and event labels for arrival, attachment start/swallow, two concurrent items, failure restoration, no target, reduced motion.
- final-report.json: six checks pass, no page errors. Includes rounding tolerance and asynchronous preference-event notes.
- qa-stable.cjs: 251ee3e full 32 frame/case capture script.
- qa-final.cjs / record-final.cjs: reproduction scripts for final focused checks/media. Temporary paths can be adjusted when replaying. Install playwright-core and point executablePath to the local Chrome binary.

## Scope

This is real browser rendering of the high-fidelity design, not a production-native acceptance test. CDP capture has variable frame cadence; video shows the actual captured frames at their original timestamps and does not establish 60fps native performance. Native Before evidence is separately retained in baseline-native, with captured-source/main UI source parity documented. No standalone safe native desktop microimage Before was available in the inspected archive.
