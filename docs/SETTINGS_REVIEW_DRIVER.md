# Isolated native settings review

`SettingsReviewDriver` exercises the real AppKit settings, control center and
onboarding, the shared settings model, the existing preference owners, SQLite,
and the actual local collector in the same App executable. It is invoked only
by `--settings-review <UUID> --settings-review-run`; ordinary review mode remains
a manual native workbench. This is a local review tool, not a second UI model.

Build/package the current App using the normal repository workflow first. The
runner does not build, install, replace or restart the installed Riftlet:

```sh
sh scripts/run-settings-review.sh /absolute/path/to/built/Riftlet.app
```

An optional second argument names a **new** private directory for the runner log
and result. Each invocation creates a fresh UUID. The App uses its existing
single-instance ownership lock on
`Application Support/Riftlet-Settings-Review-<UUID>` and an isolated UserDefaults
suite. The runner verifies the required review entry-point strings before
launching the supplied executable, verifies report UUID and executable hash,
and prints the exact result/report paths. It opens only the supplied App's
native windows. On timeout it signals only its own child process, preserves
the logs and data, and reports `INCOMPLETE`.

The driver checks native control actions and real file/SQLite readback:

- Initial settings content size, six pages in light and dark, control center
  states with independent pause/visibility, and all three onboarding steps.
- Custom archive editing through the actual field editor, first Save action,
  background refresh preserving the editor and selection, explicit discard,
  display parameter application and restoring defaults while editing.
- Close with a draft: continue, discard, and failed Apply. Successful saves in
  another domain cannot clear a layout or appearance failure; retries use the
  original target.
- Explicit motion preview, no automatic playback after a mode selection,
  navigation stopping playback, resizing and reopening, and local history.
- A generated PNG is written **only** to `fixture-source` and explicitly tagged
  with test screenshot metadata. The real collector imports it. It is not a
  system screenshot or evidence of screen-capture permission. Window evidence
  is written under `evidence` and cannot become a collector input.
- Existing isolated records remain and all private media hashes match their
  records. Existing QueueStore reads check unresolved/successful operations and
  asset operation identities; this does not replace an independent exact SQL
  operation-table count.

Fault injection is limited to an allowlist of JSON files in the validated UUID
root. The original bytes are copied into the run evidence and moved aside; a
directory at that exact file path causes a real write failure. After the action,
the driver removes only its own marker and verified otherwise-empty directory
and restores the original file byte-for-byte. Unexpected contents or restoration
failure stop subsequent mutations and preserve the held original for review.
It never makes a production file unwritable or changes a production database.

Each run checkpoints `evidence/run-<UUID>/report.json` after every case. Raw PNGs
use WindowServer capture of exactly one verified `NSApp`-owned window ID, with no
desktop/display capture or replacement view raster. Each records the process and
frontmost PIDs, window frame, content rectangle/bounds, actual screen frame and
visible frame, backing scale, appearance, pixel dimensions and SHA-256. The
960×684 default is the settings **content** size; the title bar adds outer height.
If the actual available screen is smaller, the App's clamped dimensions are
recorded. `NOT_RUN` capture is not a passing visual result.

`PASS_SCOPED_NATIVE_REVIEW` requires all executed cases and requested native
window captures to succeed. `PARTIAL_NATIVE_REVIEW` records unavailable native
captures or skipped cases; case/capture/restoration failures produce `FAIL`.
The driver does not claim physical mouse input, operating-system IME, VoiceOver,
multi-display hotplug, real permission prompts, login registration, browser
attachment acceptance, or production-data verification. Those remain separately
scoped acceptance work. The driver does not fabricate an upload receipt or START.

Raw screenshots and logs stay private: the capture/help pages can include this
machine's isolated source path. Public evidence should contain only hashes and
non-sensitive results. Do not commit the generated UI images or data roots.
The run returns its report path; Main owns normal shutdown for the explicit
automatic-run flag. Neither the driver nor runner changes system appearance,
system login items, macOS permissions, browser state, or the installed App.
