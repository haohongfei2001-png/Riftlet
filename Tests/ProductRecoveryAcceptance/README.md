# Controlled product recovery acceptance

This macOS test runs a separately launched AppKit application and a separate, local WKWebView. The production application's tray, control center, screenshot library, risk sheet, selection handling, capture service, coordinator, original PNG store, SQLite transactions and web page program all participate. The live DOM receives the actual File. macOS captures only the owned WKWebView window. The document blocks connections and form submission and preserves a pre-existing attachment and a nonempty selected phrase.

The application binary is a test composition of the supplied source revision. Its test transport addresses one local document with a controlled browser-shaped route. This suite measures product recovery. Developer ID, installation and real ChatGPT have separate acceptance records.

## Build

Use macOS with AppKit, WebKit, Swift, Node.js, Python 3.12 or newer, and the project-pinned Sparkle 2.10.1 XCFramework. The build accepts the local path to the previously obtained dependency. Run the commands in this directory. Use a new, private output location and an actual source revision for acceptance.

```sh
umask 077
workspace="$(mktemp -d /private/tmp/riftlet-recovery.XXXXXXXX)"
python3 -B build.py "$SOURCE_REVISION" "$workspace/build" --sparkle "$SPARKLE_XCFRAMEWORK"
```

The builder archives the original Sources and package manifest, copies them into the temporary directory and records the native application composition changes in `composition.diff`. The test-only build uses the private support directory, an owned web transport, the local receiver's permission result and the two test-side UI helpers. Its control-center opener activates the application's status button. The screenshot-library button, original row, risk decisions, return-to-original action and tray selection use AppKit mouseDown/up events in the normal application event queue. These events are software-generated. Fresh user selection and transactional attachment code execute on the actual product path. The local test executor prepares an original binding through the frozen page program before a tray selection.

`manifest.json` identifies the native executables, source archive, page JavaScript and composition changes. The independent browser process survives the application restart in case G. Build input `working` supports diagnosis with a snapshot of the current tracked source files. Reusing an output directory continues to use its existing source snapshot.

## Run and verify

Use an unlocked macOS desktop with existing permission to capture a window. The cases share a process lock. Set `RIFTLET_RECOVERY_GUI_LOCK` to the existing exclusive GUI lock if another acceptance runner uses one. Use a different output directory for every run. The run archives both app lifetimes, source PNG and metadata, product traces, page messages and SQLite online backups privately.

```sh
for gate in A B C E F G rebirth; do
  python3 -B run.py "$workspace/build" "$workspace/$gate" "$gate" || break
done
python3 -B verify.py \
  --A "$workspace/A" --B "$workspace/B" --C "$workspace/C" \
  --E "$workspace/E" --F "$workspace/F" --G "$workspace/G" --rebirth "$workspace/rebirth"
```

| Case | Observed path |
| --- | --- |
| A | The fixture disables the original picker just before commit. The first selection produces durable proof of pre-input refusal. The second selection attaches the same PNG once. |
| B | A real preview yields a unique START and tray exit. The fixture then shows an ambiguous error on the same attachment. The history row reports an unconfirmed result, the original remains saved and input counts stay constant. |
| C | Starting from the same type of original-card uncertainty, opening the real risk sheet and explicitly confirming stages the original PNG. Returning to the original draft and clicking its tray row creates a new operation, invocation and binding. |
| D and H | Case F reads the existing preview, records the original-card risk sheet, clicks Cancel and checks that database and page state preserve the original transaction. It then confirms once via the explicit alternative. |
| E | After preparation, the local fixture replaces the editor and changes its logical draft. A genuine fresh tray selection for that changed document produces zero additional file inputs. |
| F | After the explicit successor START, the fixture renders a named failure on the original File's card. The original read-only watch records the late fact under its original invocation. Both operations and both STARTs remain intact. |
| G | The application quits normally and restarts over the same SQLite database and media directory. The fixture document remains alive. The application recovers the original history without another input, then accepts a fresh explicit selection. |

The additional `rebirth` case renders a named failure on the exact original preview. The test waits for the product to bring the screenshot back, verifies that nothing was reattached automatically, then selects that actual returned row once.

Every reported positive file input must agree with the actual File SHA-256, the source and stored PNG, and one DOM setter, input and change. The verifier independently opens each private database read-only, checks its integrity, hashes source files and cross-checks each event against the captured page state. Only redacted counts and file hashes belong in public reports.
