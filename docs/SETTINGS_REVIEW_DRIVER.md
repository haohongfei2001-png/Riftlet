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
launching the supplied executable, verifies report UUID, child PID and executable
hash, and prints the exact result/report paths. It opens only the supplied App's
native windows. The complete run has a 180-second deadline. On timeout the runner
signals only its own child process, preserves the logs and data, and reports
`INCOMPLETE`.

Only after a complete `PASS_SCOPED_NATIVE_REVIEW` and normal process exit does the
runner launch the same immutable executable with the same review UUID in a new
process, passing `--settings-review-restart-check`. That check has a 30-second
deadline and does not repeat the UI suite or create any fixture. A failed,
partial, timed-out, or non-exiting first run does not start a restart check.

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
- While paused, another distinct synthetic image is created and actual asset
  counts are observed for a fixed two seconds, including a final read. After
  resuming, a new image with distinct pixels must be imported by its exact SHA.
  This proves the bounded observations recorded in the report, not a policy
  about handling files created during the pause on a later resume.
- Existing isolated records remain and all private media hashes match their
  records. Existing QueueStore reads check unresolved/successful operations and
  asset operation identities. The runner additionally reads the complete SQL
  `operations` and `upload_starts` counts after normal process exit.

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

The restart driver writes a separate
`evidence/restart-<UUID>/restart-report.json`. It requires a completed ordinary
run from the same executable and a different process PID; compares all loaded
configuration fields, lifecycle, arrival, screenshot entry and appearance with
their five actual JSON documents; compares loaded pause/visibility with SQLite;
checks that the existing first-use preference did not present onboarding again;
and verifies media against stored hashes. It does not show a window, submit a
preference action, or apply an appearance. Its byte comparison covers the driver
check itself; the runner supplies the cross-process comparison below.

After the first process exits and again after the restart process exits, the
runner opens **only the validated UUID root's** `queue.sqlite` using SQLite URI
`mode=ro`, `query_only`, and a read transaction. It records an aggregate SHA of
the complete asset-ID-to-media mapping (without dumping database rows), exact
`operations`/`upload_starts` counts, all five JSON byte hashes, and every media
file's hash. Each asset must match its referenced media bytes and size. The
`before`, `after`, and `equal` fields in `restart-runner-result.json` bind these
observations. Any asset addition/loss, identity mapping change, media change or
JSON rewrite fails the comparison. Operation and START counts must remain zero.
Neither this snapshot nor the restart driver changes production data.

The original `application.log`, `runner-result.json`, and App `report.json`
remain intact. The second process has its own `restart-application.log` and
`restart-runner-result.json`, including hashes of the original result/report and
the new restart report. The runner verifies that the restart report references
that exact original report and PID. Exit status zero requires both the original
run and `PASS_SCOPED_NATIVE_RESTART`, normal exits, matching package/UUID/PID
identities, and an equal cross-process data snapshot. A native restart readback
alone does not override a failing data comparison.

Raw screenshots and logs stay private: the capture/help pages can include this
machine's isolated source path. Public evidence should contain only hashes and
non-sensitive results. Do not commit the generated UI images or data roots.
The run returns its report path; Main owns normal shutdown for the explicit
automatic-run flag. Neither the driver nor runner changes system appearance,
system login items, macOS permissions, browser state, or the installed App.
