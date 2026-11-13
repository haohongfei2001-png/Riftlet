# Sparkle update acceptance

This is a private integration for the first updater-enabled release, provisionally Riftlet 1.0.1 (internal build 23). Version 1.0.0 remains a manual install. The stable channel in this change is empty and signed. The production download continues to serve 1.0.0.

## Native install exercise

A separate Apple Silicon macOS virtual machine ran the AppKit menu-bar app under a real Finder login. The isolated app used the bundle ID `com.riftlet.updaterqa.app`, a separate Keychain signing account, Developer ID signatures and a loopback feed. Versions A and B have synthetic version identities. Their check, download, installation, termination and relaunch paths use Sparkle. These are product-path exercises on a test identity. The fixture binaries predate the final refinements to the markup and capture shutdown guards.

| Exercise | Observed result |
| --- | --- |
| No available item | The manual check displayed Sparkle's up-to-date panel. |
| Valid offer | A displayed B's release notes. “Remind Me Later” closed the offer and left A running. |
| Invalid feed signature | Modifying the signed feed prevented the offer. |
| Invalid archive signature or changed archive bytes | Both downloads failed validation before installation. A was still usable. |
| Server disconnect during download | Sparkle displayed its download error. Another manual check could install the intact update. |
| Successful install in the user's Applications folder | The explicit install action downloaded the archive and displayed “Install and Relaunch”. After confirmation a different process ran build 102 at A's exact path. |
| Data continuity | SQLite quick_check returned ok before and after. Ordered hashes matched for assets (2), operations (1, UNKNOWN), checkpoints (3), compensations (0) and upload starts (0). Both media, three settings files, the stored folder bookmark and a nonempty feedback draft were byte-identical. |
| LSUIElement | The user-facing check, offer, download errors and relaunch confirmation were visible and operable in the guest's actual GUI. |

A ZIP SHA-256 was `be8683263b26c394c299ac7b389b9e929fec776ffd8073e28697006d95ec364c`. B ZIP SHA-256 was `296e4fb2c96dc2a0e532f53ddc001e003d49de38708d452c106f3ea2eb47d32b`. These identify the exercise only.

## Shared Applications and fresh captures

The same isolated administrator account also updated A in a dedicated folder under /Applications. The signed downgrade (0.0.99) was not offered. A then downloaded a signed 7,049,608-byte DMG, displayed the release notes and installation confirmation, and relaunched B at A’s original path. Its SHA-256 was `35237f660231c81b0ded5ac52567d7790c7b2eef02d4d2d64b0224f6cb698264`. The loopback server recorded a complete response for B.dmg. This exercised a user-writable shared location. An authorization challenge for a different standard account remains untested.

Desktop access was approved through the normal folder chooser. Real system screenshots taken before and after updating were collected, growing the synthetic library from two to three to four assets and media. The existing folder bookmark, settings, feedback and original operation were preserved. One previously visible asset reached its normal auto-archive time; applying just that state transition explains the entire difference in the asset-table hash. SQLite integrity remained intact.

The test Mac ran arm64 macOS 27.2. Chrome was installed but had no profile, running process, or authorized ChatGPT test draft. Post-update live ChatGPT attachment is **NOT_RUN**.

## Reproduce in a disposable Mac account

1. Build the App with `bash scripts/build-macos.sh`. Use the resulting app under the build directory and the official tool binaries documented in [the release guide](IN_APP_UPDATES.md). Use a dedicated VM with Finder, synthetic screenshots, a known history database, and no production account or data.
2. On the signing Mac, provision a dedicated QA identity with the official `generate_keys --account com.riftlet.updaterqa.app.fixtures`. Run the command below with a valid Developer ID fingerprint and a new output directory. The fixture builder requires a QA public key distinct from the release key and never exports a private key.

   ```sh
   python3 -B Tests/UpdaterAcceptance/make-fixtures.py \
     --app "$QA_SOURCE_APP" --tools "$RIFTLET_SPARKLE_BIN" \
     --identity "$DEVELOPER_ID_FINGERPRINT" --output "$QA_FIXTURES"
   ```

3. In the guest, install A.zip in an empty application folder. Run `ruby Tests/UpdaterAcceptance/serve.rb "$QA_FIXTURES"` inside the guest. Only the guest's loopback interface serves this fixture. Copy each named scenario XML to stable.xml atomically before each manual check, starting with none.xml. Check both the visible outcome and the installed version/process. Confirm the offer can be dismissed. For an interrupted or invalid download, verify the original installation is intact.
4. Before accepting the valid update, snapshot the queue through SQLite's read transaction, hash media, read the saved settings and folder bookmark, and create a nonempty feedback draft. After relaunch compare these fields and the absolute installation path. Check collection of a new system screenshot separately so the expected change in asset count does not invalidate the before/after comparison.

## Independent checks and boundaries

- The release validator rejects an incorrect bundle ID, a missing Developer Team and a real signed executable from a different team. Release metadata and the signed item bind the verified DMG to the published update. Sparkle's EdDSA identity can authorize an Apple code-signing identity rotation. The release process enforces the designated team before it signs the feed.
- The offline appcast tests include the official Sparkle tools, a generated signed QA DMG, tampering, version/build rollback and use of draft or prerelease GitHub assets. These tests run on both native CI jobs.
- Intel/ARM64 compilation and architecture inspection establish binary compatibility. Hardware coverage on each supported macOS release, day-long scheduling, and a new live ChatGPT attachment after this update require independent evidence. A local feed cannot validate the future public GitHub-to-website rollout.
- See the Draft PR for exact-source CI, subsequent isolated verification, signed release artifacts and admission status. The [update instructions](IN_APP_UPDATES.md) describe the publication order and the manual first install.
