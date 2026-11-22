# Signed-candidate selection QA

Use this test after a real system screenshot has reached a verified attachment card in a dedicated, authenticated Temporary Chat. It probes the preservation of the fixed 64-character draft and a directed, non-collapsed selection at UTF-16 offsets 12–40. The original-card and per-file input checks come from the candidate's page and SQLite receipts.

## Build and run the controls

These files are intended for `Tests/PreClickLease/selection`. Use the matching PR checkout, which provides `Tests/DerivedPreview/draft-selection.js` and the Swift original-tab observer. The build uses a macOS Debug products directory containing the RiftletAdapters and RiftletCore Swift modules and object files. It writes both test executables and their generated Swift sources to a new private directory.

```sh
qa="$PWD/Tests/PreClickLease/selection"
python3 -B "$qa/build.py" --repo "$PWD" --products "$qaBin" --output "$qaOut"
python3 -B -m unittest discover -s "$qa" -p 'test_*.py'
node --test "$qa/observe.test.cjs"
```

The assembler retains the repository observer's native process, dedicated window/tab, URL and recorded navigation-entry checks. It builds a fixed selection-only page query with the original editor and attachment scope from the signed candidate. The AX executable accepts its fixed sentence and range through its compiled code. The host controls the timing of each write using a purpose-specific handshake.

## Connect the native acceptance driver

1. Set up the candidate, screenshot source, database and owned browser window with the release's private acceptance driver. The driver must have an authenticated read-only admission for that exact window, tab and document, and a working original-page observer. Begin on an empty temporary draft.
2. Use the signed App to attach the seed image. Wait for its original card, decoded pixels and matching durable START. Have the original observer remember the old cards with `draft-mark`. The original observer must expose its existing private QA `state()` closure keyed by the confirmed local challenge document.
3. Make this directory importable by the host. Construct `SelectionStep` with the existing browser state, a fresh per-attempt output directory, the native route, the accepted seed operation, a callable reading the existing page watcher, and the build output directory.
4. Call `prepare()` once. Verify that `selection-before.json` exists before issuing the new click. It records the actual selected text, direction, endpoints, document, composer, epoch, full old-file set and event counters. If the renderer represents an empty editable with an empty line break, preparation also checks that its text content is empty.
5. Use the actual candidate's tray click for the new PNG. Route subsequent acceptance checks through `read_page()`. It retains the original empty-draft flags for diagnosis and supplies the independent nonempty text and selection comparisons. Pass the independently qualified new SQLite operation to `finish(new_operation)`. It writes `selection-final.json` and returns a passing status only after checking the new card and old cards, exact file events, pixel proof, distinct START, original draft, selection and send counters.

```python
from selection_step import SelectionStep

selection = SelectionStep(state_dir, attempt_dir, route, verified_seed, read_original_page, qa_build_dir)
selection.prepare()
# The integrating driver issues the new AppKit click and verifies its original PNG and SQLite START.
selection.read_page()
result = selection.finish(verified_new_operation)
assert result["passed"] is True
```

The two SQLite arguments use the release driver's normalized fields, including `id`, `assetID`, `invocationID`, `startMatchesOriginal`, `startCount`, `startSignal`, `uniqueStartEvidence`, `currentAttachmentID`, `originalDocumentID`, `originalComposerID` and `originalDraftGeneration`. The route contains `applicationID`, `session`, `windowID` and `tabID`. Keep native receipts, actual operation identifiers and screenshot bytes in the private run directory.

## What the checks establish

The native helper verifies the signed browser's recorded kernel lifetime through the caller's scope check, then independently checks the running executable, lifetime and foreground. Two renderer hit points must map to the same editable AX object under the exact web area and focused window. Its measured frame must agree with the DOM. A missing DOM ID can pass these checks. If focus must move, the helper sets focus on that mapped object and requires both AX and the original renderer to confirm the change before insertion. Each text/selection write has a recorded intent. A lost result leaves that attempt consumed.

The offline controls exercise route mismatch, duplicate preparation after a lost result, one insert and one range assignment, direction reversal, ID-less geometry and occlusion. The separate headless `Tests/DerivedPreview/run.cjs --selection` procedure exercises the signed page resource in Chrome and Edge. Real Temporary Chat results require the candidate's native receipts and a complete case for each browser. The release acceptance report records those results separately.
