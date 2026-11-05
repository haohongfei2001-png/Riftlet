# Attachment entry repair — PR #41

## Incident and scope

The user reports that installed PR #41 head `e9ecafa7` reached Chrome page
execution but repeatedly returned `ATTACHMENT_INPUT_UNAVAILABLE` during
`captureTarget`, followed by `click_input_refused`. No current file input or new
operation occurred. This is supplied real-device evidence, not a new live test
performed by this executor. Production SQLite/media and the installed Mac App
are inaccessible here and have not been modified.

The old page `composer()` required a fixed editor selector, a form/ancestor
relation to a file input, a short accept-value whitelist, and one eligible picker.
Its only portal fallback required exactly one unowned global picker and still
required the editor's form. A normal attachment menu could therefore upload a
PNG while Riftlet refused that same controlled page before creating an operation.

## Implementation

- Capture and validate bind the clicked native tab and original page/editor.
  They do not require a file input to be mounted, local to a form, or unique.
- Direct input resolves an explicitly linked current-chat control, or a sole
  local control when no attachment entry exists. Hidden inputs work; `accept`
  never licenses, ranks or rejects a route. A sole global input is not guessed.
- When the direct route is unresolved, commit activates the actual attachment
  button, follows its newly opened local-file menu, and captures the input that
  the application invokes through click/showPicker/label. Dynamic inputs and
  portalled inputs can be resolved without opening a native chooser for the user.
- Only callbacks scheduled by that actual entry carry its activation context
  (timers, microtasks, animation frames and Promise callbacks). Normal unrelated
  avatar/project picker activity is not captured. A late callback of a cancelled
  entry cannot open a chooser or resurrect input. Temporary APIs are restored
  before yielding; this is no cross-operation upload eligibility state.
- Normal pointerdown/up/click activation supports pointer-based menu primitives.
  Only temporary chooser suppression is installed, then restored. No input node,
  attachment card, synthetic success, React state or network upload is fabricated.
- A setter/change is entered at most once per operation. Ambiguous or missing
  routes can fall back only before that boundary. Throwing or uncertain input is
  observed under its original operation and never submitted through another path.
- Dynamic discovery has a three-second wall-clock deadline checked again before
  setter entry. Menu cleanup occurs after input, so a menu-owned picker is not
  unmounted prematurely. Text/selection and old attachment cards are preserved.
- The MAIN-world relay awaits Promise settlement and publishes the original
  nonce once. The native commit reader waits up to eight seconds. An interrupted
  commit receipt is recovered by bounded observation of that current execution,
  not by repeating commit or inspecting an older upload's outcome.
- `inputExecutionPending` describes only current in-flight discovery. It is not
  historical upload permission. Ordinary settled input releases the lane before
  START/completion observation; old UNKNOWN/START/COMPLETE stays irrelevant.
- START requires a new accepted preview/progress card identified by the current
  unique filename or the current File's blob URL, including portalled cards.
  Setter/change alone, a filename placeholder and an error card cannot swallow.

## Validation boundaries

`Tests/WebPageProgram/acceptance-program.test.cjs` exercises application handlers,
actual command staging, file input, appended cards and START in a controlled DOM.
`chrome-input-resource.test.cjs` additionally runs real Chrome File, FileList,
DataTransfer, Selection and DOM events against an isolated loopback application.
The latter is required on both native CI architectures and never contacts a
real ChatGPT session, CDP endpoint, or user browser profile.

Swift tests cover Promise receipts, one-time nonces, closed error propagation,
original-document settlement, interrupted discovery, preserved screenshot state,
execution release and SQLite compatibility. The original ordinary App UI,
capture/animation, Feedback and historical observation tests remain enabled.

The independent reviewer and exact source/admission SHA are recorded in
`engineering/mainline/source-admission.json`; final CI runs and downloadable
ordinary ARM64 App identity are recorded in PR #41. A successful controlled test
or build is not real ChatGPT acceptance.

## Actual device status

Browser returned missing originating browser context in this execution. No
alternate shell, Apple Events, CDP or cloud browser path was used to access the
user's real ChatGPT. There is no connected Mac filesystem for backup, installation
or production data verification. Those operations and real first/second/five
click acceptance remain NOT_RUN for this source until separately evidenced.
Do not describe the product incident as resolved solely from this source or CI.
