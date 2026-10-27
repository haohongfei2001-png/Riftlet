# Round 9: historical monitor recovery and remaining first-click boundary

Branch: `codex/riftlet-real-mac-round9-20261028`. Web/live App source: **`fcb052bfe6fad09af5de3c90d5954259e000a8ef`**. It starts from formal `b83923068064f6d82f2d253a3c177661fdabc294` and preserves round-eight ancestry through merge `57157c387ed46b9aeebe86775c38e3d9d53eefb4`. Final helper/full-build source: **`23becda7b5a82beb4634ba3816fde6dac49034d2`**. It changes only the helper and review; App/Core/UI/Web production sources are identical to fcb052b. Exact CI status is recorded in [verification](verification.json).

## Product result

| Item | Result | Evidence scope |
| --- | --- | --- |
| Retained v10 monitor preventing current target capture | **PASS — repaired on real Chrome** | v13 obtains a complete native ACK while borrowing the original accessor. Old registry, operation and proof reference (including absent proof) stay unchanged. The editor was unfocused in before/after snapshots. |
| Upgrade from an existing v12 page | **PASS — real read-only capture** | The existing same-root v12 monitor is retained and borrowed; exact descriptor identity stays unchanged. This page had no old operations, so live v12 final-proof recovery is not claimed. |
| Genuine App-cold first click before any ACK | **FAIL product; safe refusal PASS** | One exact AXPress occurred 208.687ms before full native verification and 209.412ms before App publication. Zero input, zero new operation, no replay or second press. |
| Fresh page / reload immediate recognition | **FAIL within bounded observation** | No ACK in the respective 10s / 12s windows; composerUnavailable appeared during loading. A later ACK was recorded separately and never applied to an earlier event. |
| Replacement double-click | **PASS — software native routing** | Two CGEvent pairs, 124.964ms apart; first selects A once, second reaches replacement B but selects nothing. Explicit supplied clickState=2, not hardware classification. |
| Human physical mouse / full desktop matrix | **NOT_RUN** | No new human input; AX and CGEvent are explicitly separate. Existing helper entry is documented. |
| Production system-screenshot end-to-end | **NOT_RUN / gated** | Parallel candidate source is not merged here and no production profile is enabled. |

The actual fix removes the historical accessor conflict; it does not solve every event-before-proof cold click. No successful upload, uploadStarted latency, failure rebirth or new completion is claimed in this round. The only new generated image remains local and unsubmitted.

## What changed

The current page registry becomes v13. It can subscribe to one explicitly matched, intact original v10 or v12 monitor on the same root. Those two frozen owner implementations are identical. A private per-form group token installs the new generation's own predicate without reusing or invalidating the old form group's predicate. New checker exceptions are caught before the historical setter. Local stop retires only the borrower; it never restores root.current or stops the old owner. A stopped/lost/ambiguous owner still refuses.

This requires the existing code-owned MAIN-world registry integrity assumption. Source/shape checks do not authenticate arbitrary closure bindings against malicious same-world registry tampering. A genuine monitor deliberately swapped from another root can share function text without sharing the intended closed-over root; that unsupported case has an explicit regression documenting the limitation. No setter probe, global built-in patch or synthetic React commit was introduced. Unobserved same-URL business ABA remains unsupported.

Old v6–v12 operations route only through the exact original observation closures, normalized to schema 1. They receive no new input authority or schema-2 start evidence. v10's original NodeList callback defect is not repaired or used to reconstruct missing completion. Synthetic fixture tests cover retained real v10/v12 source, independent new input/proof, old proof/late-error preservation, stop and invalidation; those are not live uploads.

## Cold-click technical decision

[Original event and full ACK evidence](cold-and-monitor.json) separates three cases:

- **A — recoverable earlier recognition:** the v10/v12 incompatibility is fixed and both retained real pages now bind automatically. More frequent timer polling was not added.
- **B — complete native ACK awaiting publication:** this sample's native-validation-to-App-publication interval is 0.725ms. It is after the original event, so eliminating that interval would not authorize this click.
- **C — original event before complete proof:** the App's first capture was still executing. Passive startup permission took 31.173ms; the arming check took 67.018ms; the initial bridge queue took 15.761ms and execution 358.327ms. These are one loaded-host sample, not a performance baseline: local Swift test compilation overlapped. A native event can occur before an asynchronous Apple Events round trip finishes. No fixed delay or retrospective target lookup can establish the missing pre-event proof.

**Decision:** ship no new extension requirement and do not keep adjusting timers as a purported guarantee. Retain the safe refusal until the original event can be paired with trustworthy pre-event target evidence. The round-eight isolated push/native laboratory is comparison evidence only; it does not prove business-draft identity or remove notification delivery gaps. The no-extension route now recovers the measured monitor incompatibility, but the strict zero-proof cold boundary remains a first-release limitation requiring an explicit engineering scope decision.

[Read-only lifecycle evidence](lifecycle-readonly.json) includes retained-tab return, a new independent document and reload. These tabs reference the same saved conversation: this is not real same-tab business A→B→A. Later structural availability snapshots were hidden/unfocused and cannot prove availability at earlier failures. The old tabs were not reloaded or cleared. Existing Chrome processes, permissions and original databases were preserved.

## GUI and remaining acceptance

The prior CLEAR/GAP/IMAGE/NUMBER/hold implementation is unchanged. One new bounded helper experiment targets the previously missing replacement double-click. The initial run selected original A once but refused its second pair before native replacement geometry was visible; [original result](gui-double-initial.json) remains retained. That is a helper sampling limitation, not proof of a product double-click failure. A minimal helper correction samples native frame/window routing within the original double-click deadline; the [corrected final run](gui-double-final.json) passes software replacement protection. Two actual down/up pairs reached distinct original/replacement native windows within 124.964ms (system interval 500ms); only A was selected, B zero selections, helper focus endpoints stable. This is not cross-application physical focus or system hardware double-click classification.

The [minimal human entry](gui-entry.md) requires no new test system. Human first click, CLEAR/GAP keyboard focus across applications, hardware double-click classification, fullscreen/Spaces and 1× display scale remain NOT_RUN. Existing two displays are retained; software tests do not become physical results.

MID byte interruption, real safe-failure rebirth, same-URL business replacement, Chrome permission revoke/regrant/restart and system screenshot T0/T1/T2 remain open. No DOM/offline anomaly is relabeled as a network failure. The already accepted two-image FIFO and upload-start path were not repeatedly exercised.

## Integration and preservation

Root was the only live Mac/browser/DB input owner. web_safety authored the page compatibility change; native_gui authored the helper increment; late_failure performed independent source/test review. web_safety independently checked public runtime evidence against private logs. [Review and trust boundaries](monitor-compat-review.md).

[Data retention](data-preservation.json): all 25 original assets/media hashes, 27 operation identities/phases, six unresolved phases, three compensation rows, six start receipts and 14 other private files are retained. One generated asset was added; no operation was added. Five observation timestamps/reasons and two observation receipts refreshed through original read-only recovery. Before/after SQLite backup snapshots are privately retained under the existing writer lock; this is not a byte-identical database claim.

During this work formal and system-capture-candidate refs both advanced to `4d352c28dcb70e8f6dc42ef93d9df46042a9215d`; formal CI40553084871 passed. Only refs and the formal handoff were read; the candidate is not merged, rewritten or run by this branch. Its formal handoff still describes the prior integration, and no new candidate-specific real-test admission was delivered here. Pro owns candidate admission, combined integration and release; preserve its new Core/App deadline changes when integrating this branch.

No main, formal PR #1, website, brand, production admission or browser-extension installation changed. No ChatGPT message was sent. Pro can integrate the two round-nine source increments after reviewing the exact remaining limitations; round-eight ancestry is preserved and must not be re-cherry-picked blindly.

## Verification handoff

Full exact-source release packaging/ad-hoc signature and four self-checks PASS. Page/legacy VM 144 PASS, packaging Python 12 PASS. Local native XCTest is **NOT_RUN** because this CommandLineTools installation cannot resolve XCTest; this is not a native test pass. Final-source [CI40555899978](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40555899978) is **pending, zero steps executed** at handoff. The earlier source run40554102772 was automatically superseded by the actual helper fix, also zero steps; no unchanged-SHA rerun was requested. Pro must complete native CI for the final combination before admission.

Next concrete integration action: review source commits fcb052b and 23becda plus the retained round-eight ancestry against Pro's current candidate. Keep the candidate's Core/App changes, rerun only the final combined native checks, and use an independent candidate data root after candidate-specific internal admission. The existing generated-image queue must never become the system-capture candidate queue. This handoff does not start a background executor, promise unattended progress, or close the stated product gaps.
