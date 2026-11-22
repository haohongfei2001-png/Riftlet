# macOS QA window evidence

The host serves the private, independently installed build 60 acceptance runner and the single Aqua supervisor. The public source contains no account identifiers, document contents, browser URLs from personal tabs, captured images, or production data.

## Read-only admission

`WindowEvidence.swift environment` uses CoreGraphics, accessibility and NSWorkspace to collect the foreground process, process ownership, AX role, subrole, modal flag, frame and the visible CG layers. It checks the console with Apple's SDK keys. It does not request permission. The host enumerates notification and security windows only for those metadata attributes. A visible system dialog, a protected foreground process, or a front application modal prevents admission. Seeing AXSystemDialog with AXModal false leaves the purpose undetermined.

`WindowEvidence.swift original` also checks the new native window and sole original tab from the retained creation and local document records in a signed browser process of the same kernel birth. The native Chromium window and its WindowServer surface have different identifier types. The host reads the original window's native bounds, requires exactly one on-screen layer-zero surface in the same process and compares the bounds with the unique main AXStandardWindow. The center point must hit that same CGWindowNumber. Frame matching allows one point of rounding. A minimized window, absent AX or CG surface, or ambiguous frame keeps the gate closed.

`gui_sample.py` reconciles that proof with the original Temporary Chat observer. Separate native and document readings must report the same PID, process birth, window ID, tab ID, original navigation entry and time origin. The original page must be visible, focused, signed in and have its composer and upload entry. The target hash remains the same for a given original window/document when a case label changes. The signed product additionally binds its Document, composer and draft generation at its normal pre-click boundary. Public macOS APIs used here provide no global enumeration of other applications' Spaces. The host never infers a specific Space or Stage Manager as the cause of absence.

## Presentation and execution

`PresentOriginal.swift` can restore only the window and tab in a verified creation, local document, navigation and original-entry receipt. It checks the retained navigation entry and time origin before and after each presentation. It can bring that specific window to the front or normalize its minimized state. It activates the browser only when its selected tab already identifies the enrolled window. A presentation result cannot authorize a product click. The host performs two independent full reads immediately before it launches the pinned runner.

The private deployment provides the sealed QA programs from the independent installation and a process-local read-only host description. The Swift sources are compiled with the repository's existing `Tests/PreClickLease/native/{identity,owned,press}.swift` and the retained instrumented modules, using the `ORIGINAL_DRAFT_OBSERVER` conditional. The executable opens no new debugger connection and never navigates to a script URL. The private launcher rejects a changed component manifest member. The supervisor verifies the path and hash of that launcher.

The command contract is shared with the supervisor in the adjacent directory.

- `host sample FAMILY NONCE` performs only reads. A fresh `checks` object gives the twelve independent predicates in `gui_sample.CHECKS`.
- `host prepare FAMILY CASE NONCE` receives the supervisor's open GUI flock. It preserves the current scope and may present that exact original on a changed eligible desktop. When no scope is outstanding, the Chrome/Edge matrix and large-image case can enroll a fresh dedicated window.
- `host run FAMILY CASE NONCE CLAIM_JSON` checks the inherited file descriptor's device and inode and the claim's source, package, nonce, case, attempt and target. It durably records the original business claim before starting one issuer. A crash, missing reply or underlying uncertainty cannot cause a second input. A watcher or a named-failure case that still needs examination keeps its original scope. Other completed and exited suites can close their own window through the pinned helper.

G1 and G2 use the cold first screenshot in the empty draft and the next first screenshot after the original card exists. The latter is also the first member of rapid pair one. The audit requires independent source, pixel, card, input and SQLite proof. G4-C uses its dedicated bound private driver. The B4 size report preserves actual capture, PNG and browser evidence. A size warning by itself supplies no status code for an upstream request; a qualifying G4-B decision remains independent.

Run the six offline controls with `python3 -B -m unittest -q test_gui_host` in this directory. No browser or system notification is opened by these controls.
