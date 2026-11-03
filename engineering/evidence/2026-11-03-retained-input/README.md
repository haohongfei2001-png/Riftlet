# Retained native selection: B START → independent C input

## Incident and evidence boundary

Base is main `6c677f555376e4abcbdfa59e6e9ef1aabb8eadec`, after merged PRs #37
and #38. The user reports B entered the file input at 20:46:38, received actual
START and was swallowed. Five later actions failed at resource preparation in
about one second. B became UNKNOWN only later. The same logical draft was
observed with different document identities. This excludes waiting for B's
final UNKNOWN as the cause of the earlier refusals.

The original Mac logs/database were not accessible in this executor and were
not read, changed, deleted or replayed. Their generic cancellation message does
not identify a unique failed predicate. The source and isolated regressions
establish two concrete defects; they do not retrospectively identify which
predicate caused each of the five reported refusals.

1. Main requires both native FileList and value to be empty. The 2/3/5-input
   regression fails at `prepareInputResource`'s `!nativeInputEmpty()` even when
   the previous original call returned normally and its own START is known.
2. If the original change handler invalidates the binding, `invalidate()` deletes
   `state.input`. The old `finally` releases the wrong WeakMap key, leaving the
   actual original node owned. An independent baseline reproduction demonstrates
   this even with an empty FileList and an already-settled call.

## Runtime repair

The native file selection and input execution are checked separately. Empty
pickers preserve the earlier current-resource path. A retained selection can
produce `settledOwnedNativeFileInput` only when exactly one original operation
owns the selected File, the original setter/change returned normally, its
async work settled, the file hash and single input are verified, its correlated
START exists, and its original attachment remains in the same valid composer.
Every known registry/generation is checked for actual execution or ambiguity.
The one-use new-operation reservation is rechecked before its only setter/change.

New input stores a weak File witness outside the historical operation. The
weak witness survives normal payload release without retaining discarded image
bytes indefinitely. A new state capability marker prevents an updated App from
silently reusing the old v13 empty-only closure in an already-open page.

For old main's START→UNKNOWN payload release, a narrow read-only qualification
can match the current native File to the unique original generated upload name,
byte count, media type and SHA-256, plus the unchanged original START, normal
call return, single input and current attachment. Arbitrary selected files are
not hashed. A pending reply has no input token; polling is bounded and sends no
file. After hashing, the exact current native File object, descriptors, target,
old facts and execution availability are rechecked. Genuine later reselection
is rejected by the original change/input-count guards. No historical operation
or persisted UNKNOWN is reconstructed, promoted or modified by qualification.

The execution `finally` captures and releases the exact original node only if
still owned by that operation. It does not retrospectively erase uncertain old
owners, use a timer to unlock resources, or introduce a second input path.

## Diagnostics

Preparation, BEGIN and final input refusal have closed, non-content reason
codes distinguishing native retained files/value, descriptor access, active or
uncertain execution, old-generation activity, registry integrity, target change,
attachment baseline change, reservation conflict and missing prior ownership.
Read-only qualification pending/failure is distinguishable from execution.
These fields are diagnostic only; they cannot grant retry or no-input authority.

The apparent 4096 lifetime limit was two independent 2048-line caps. The opt-in
trace now has one bounded recent-event file (128 records) and an independent
critical-failure file (32 records), including sanitized prior failure records
across restart. Routine polling cannot exhaust future failure capture. The
existing standard-error stream remains bounded. Files are local to the private
data root's `diagnostics` subdirectory, with directory/file modes 0700/0600.
Local correlations are hashed; raw screenshot/chat content, webpage tokens,
attachment identifiers and arbitrary error descriptions are excluded.

## Verification design and truthful scope

- Baseline red evidence: retained 2/3/5 scenarios fail before a second setter;
  the independent stale-owner reproduction also fails before the next input.
- Current/legacy Web suites cover empty/retained input, active and ambiguous
  execution, setter/change errors, START before COMPLETE, same-draft/new-document
  identity, old UNKNOWN, source upgrade, changed selection during qualification,
  old card/text/noncollapsed selection, late outcomes and duplicate commit.
- The existing native Chrome CI entry point now executes seven controlled
  applications: empty 5; retained 2/3/5; retained 5 with renewed document IDs;
  baseline START→upgrade 3; baseline START→UNKNOWN→upgrade 3. It checks native
  FileList behavior, distinct immutable File and extracted Request bodies,
  independent application attachment records, original UNKNOWN, text/selection,
  no replay, no send and refusal of an unowned selected file.
- Native FileList replacement and application `value=''` reset differ: setter
  replacement preserves earlier list objects, while the controlled app's reset
  clears its earlier list in place. Both retain independently captured File and
  native Request bytes. The retained cases never clear the picker.
- Chrome/FileList/File/Blob/FormData/Request/WebCrypto/Selection are native; the
  application handler and START/progress are synthetic. There are zero upload
  network requests; test-status requests go only to its owned loopback harness.
  This is not proof that today's real ChatGPT application passed append testing.
- Full existing Swift/AppKit/Core/SQLite, Feedback, packaging, candidate self-checks
  and both architecture jobs remain required. Existing SQLite tests already
  cover original START/UNKNOWN/late COMPLETE/failure/restart and history integrity;
  their scheduling/database implementation is unchanged. New native adapter and
  trace regressions cover the retained resource and diagnostic saturation.

The exact reviewed source, completed check results and original App artifact
identities are in the repair PR. The Linux executor has no Swift/AppKit toolchain
or usable Chrome binary; it does not label skipped native execution as PASS.
The authorized Browser bootstrap returned missing originating browser context.
No other browser automation entry accessed ChatGPT. The remaining platform step
is this exact candidate's ordinary App path in the existing user's chat: preserve
old B/UNKNOWN and draft, click distinct C/D, observe each independent input/START,
and confirm prior attachments/text/selection remain intact. No old screenshot
reinput, manual picker clearing, chat switch or app restart is an acceptance step.
