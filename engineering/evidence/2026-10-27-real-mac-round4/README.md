# Fourth real-Mac increment — 2026-10-27

## Checkpoint and scope

- Formal baseline, verified by live remote refs: `a441c70f3c4071069bd594513ecf16600bbb0ab8` on `codex/engineering-foundation-20261027`.
- Separate worktree/branch: `riftlet-real-mac-round4` / `codex/riftlet-real-mac-round4-20261027`. Earlier worktrees and stores were retained.
- First source increment: `35e98517ce2808a35a45a26a08d18e4b386b8bf7`.
- Final tested source and actual successful App: **`c9c68a66c4b6ff55ffe8048cff6f1cf781600519`**. Later handoff-only commits do not constitute another native test run.
- Product authority: PR #4 contract files at `90a04883160032fc6354fb4f3d3f7d56fede2947`. Positive actual uploadStarted must precede rapid visual exit; final completion and safe retry remain independent. This branch does **not** implement or certify that new visibility lifecycle. Pro owns Core/UI/App integration.
- Local environment: macOS 27.0 (26A428), arm64, Swift 6.4, Chrome 156.0.8078.48. Actual App uses `--web-acceptance --acceptance-trace`, synthetic assets only. Capture-only production policy and safe-retry admission remain disabled.

## Concrete result

**PASS, limited:** one user-performed physical first click on the new generated noise PNG appended it to an ordinary **persisted** ChatGPT Chat draft with the editor unfocused. For this new asset it produced one native selection, one commit, one original-operation file input, a correlated completed-image proof and `verifiedReady`; the durable item became `used`. No Send action occurred. This was **prebound**, not a cold click before complete ACK.

The complete trace also contains two later mouse selections on one old UNKNOWN asset; these are separate from the single new-asset selection, and no additional commit/input occurred. Their physical provenance is not independently attested. The user explicitly reported the single physical click on the new asset. Native evidence records `source=mouse`, event 27520, the exact synthetic asset, frozen original target, matching foreground session and host epoch. `mouse` alone would not prove human provenance; the contemporaneous user report supplies that part. The DOM file `change` is programmatic (`isTrusted=false`), as expected for the adapter, and is not described as the human mouse event.

The editor was blurred through a diagnostic setup call, not a demonstrated physical body/sidebar click. At actual file input and later observation, `document.hasFocus()` was true and the editor remained unfocused. The draft baseline contained no text and zero attachments: preservation of **nonempty** original text/attachments was not exercised. The selection snapshot was taken before blur/setup and differed at file input; without a snapshot at the actual pre-input boundary, this cannot attribute the difference to upload. Selection preservation remains NOT_RUN.

See [first-click.json](first-click.json) for full source SHA, clocks, target digest, operation/hash/attempt and bounded event order. No raw conversation ID, URL, text, screenshots or browser secrets are published. The generated PNG was 3,147,775 bytes, SHA-256 `494d7d015dc1a91073b356e1d6d64a546497aab37f8c47c4f82c630d7033f5bb`, imported as a fresh source occurrence using the existing importer. An old used/UNKNOWN operation was not reused.

## Fixes and evidence

1. **Outside-composer interaction:** v7 permanently revoked input after every trusted outside pointer/click/key event. v8 rechecks the same original binding and availability after the event instead. Document focus, visibility, foreground native process/window/tab, modal/inert/disabled blockers and the final post-hash synchronous input check remain gates. It never focuses the editor or substitutes a new post-click target.
2. **Previously missed persisted conversation IDs:** live ancestry had exactly one current committed branch, depth 380, matching full Chat-mode and draft property groups, and identical bare UUID conversation/draft keys. The old `local-chatgpt:`-only format rejected it as `UNPROVEN_THREAD_IDENTITY`. See [before](binding-before-fix.json) and [exact bare-UUID diagnostic](binding-persisted-proof.json). c9c68a6 retains the exact raw UUID and uses a separate `chatgpt-composer-react-persisted-20261027-v1` profile. Local IDs keep their existing profile. No URL-derived identity, normalization, old-row backfill or synthetic alias is used.
3. **Original v6/v7 observation compatibility:** only `observe` can use retained original closures/proofs. Exact frozen target and operation/asset/attempt/hash must match; input actions never run old code. Actual retained v6 compensated and UNKNOWN operations were read without new input: both returned invalidated/no exact proof, input totals stayed 3→3. Two other original tabs no longer existed and were not recreated. These were direct read-only page compatibility calls, not full App restart-recovery acceptance. Live v7 original-operation recovery was NOT_RUN; snapshot fixtures cover it. A stopped old monitor cannot have its proof reconstructed. Active v7 monitor ownership may safely refuse a new v8 bind; this branch never stops it to bypass that refusal.
4. **ACK causality:** native receipt arrival, complete target/context validation and MainActor return now share an opaque request ID and canonical target digest. This is explicitly diagnostic, **not** App publication or click authority. For the successful click, complete native validation and App acknowledgement preceded the raw event; callback delay was about 3.40 ms. The actual click was not in an in-flight-arm gap. [Pro interface request](app-integration-request.md) specifies the remaining original-event/publication boundary work.
5. **Native diagnostics:** AX hint registration checks whether the 50 ms timeout could be set. The actual App reported hint binding available. GUI helper now records raw local, content, window, screen and CGEvent coordinates without altering events. No Core/UI/App product source was changed.

## Important residual limits

The restored negative fixture proves an **unobserved** same-DOM business B→A, with no root setter/DOM/navigation evidence, can validate the old lease after outside-event blanket revocation is removed. This is a known fail-closed coverage gap, not an ABA safety PASS. More polling or a fixed delay cannot prove the missed interval. The counterexample is deliberately retained in the suite, and production admission remains closed. The actual one-click success does not establish that all live business transitions are observed by this React monitor.

Core does not yet recognize the new persisted profile. Consequently an unresolved operation conservatively blocks its entire tab, including a proven different persisted draft; cross-profile and legacy locks stay conservative. [The exact minimum Core proposal](core-persisted-identity-request.md) is for Pro to review/integrate/test. It is **not applied** here. It must not be presented as an implemented UNKNOWN-unblocking fix.

## Result matrix

| Item | Result | Actual scope / remaining reason |
| --- | --- | --- |
| Ordinary persisted thread, editor unfocused, first physical click | **PASS** | One prebound generated-image operation; exact input and completion; no Send |
| Unique valid composer, modal/disabled/ambiguous rejection, final target checks | **PASS** | Synthetic regression; actual unique ordinary composer also observed; live modal/address-bar matrix NOT_RUN |
| Fresh cold page before complete ACK; queued Apple Events; target changing during click | **NOT_RUN** | Successful click already had ACK; no backdating or after-click recapture added |
| Nonempty original text, old attachments and selection | **NOT_RUN** | Actual baseline empty; selection baseline not at input boundary |
| Same-tab real A→B→A, same-URL replacement, refresh/restart/window move independence | **NOT_RUN** | No complete real transition sequence collected; VM cases do not substitute |
| Unobservable business ABA safe rejection | **FAIL** | Explicit counterexample remains; production closed |
| Existing UNKNOWN/compensated no replay and preservation | **PASS** | Original operations/media audited; live old observe input count unchanged |
| Physical micro-thumbnail first click, Chrome document focus | **PASS** | User click + native event + file-event focus evidence, this single scenario |
| CLEAR/GAP/OUTER/numeral hit, hold/reorder/double click, other-app focus, Spaces/fullscreen/rotated displays | **NOT_RUN** | No new reliable physical evidence; prior automated GAP is not promoted; CUA cannot reliably address all tiny windows |
| React monitor overhead | **PASS** | One observed monitor: 312 commits/checks, 47.1 ms total, 1.8 ms maximum; not a whole-App resource or business-transition proof |
| System screenshot excludes visible Riftlet | **FAIL, inherited** | Round3 real CLI region failure remains unresolved; this round official API review only, no new screenshot PASS |
| T0 actual system capture complete → T1 complete file → T2 first clickable thumbnail | **NOT_RUN** | No new three-boundary trace; old 61.5 s remains unattributed |
| Real MID byte request/interruption | **NOT_RUN / NOT_EXERCISED** | Existing bounded probe expired before click; zero bound input/request/hash; no abort or retry claim |
| New uploadStarted fast visual swallow + production screenshot end-to-end | **NOT_RUN** | Pro lifecycle not wired in this branch; source/success gates remain closed |

The MID probe reached its 60-second deadline, restored fetch/XHR originals, and retained zero clone readers. It initiated no request or abort. We did not repeat a successful upload merely to generate a network sample. Existing POST100 evidence was not reclassified or rerun. See [system capture API findings](system-screenshot-exclusion.md) for the scoped native exclusion conclusion and public sources.

## Validation and independent review

- Final source macOS CI: [run 40478928761](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40478928761), **PASS**. 235 native unit/integration tests, 48 page VM tests, 14 legacy observer VM tests, existing archived replay/fault/probe suites, packaged App and helper self-checks.
- First increment CI: [run 40476593735](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40476593735), PASS at 35e9851. It is not the c9c68a6 test run.
- Local complete App build and self-checks PASS. Local Command Line Tools lack XCTest; full native tests ran in CI, not falsely reported as local.
- Independent non-author reviews caught the wrapper sourceID mismatch before CI (fixed) and the missing old ABA counterexample (restored). Persisted UUID/profile change was separately reviewed with three targeted VM tests. No additional blocker in that scoped change; all residual limits above retained.

## Preservation and shutdown

[Preservation audit](preservation-audit.json): both SQLite v2 quick checks passed. Original capture store stays 6 pending/0 operations. Web store becomes 4 UNKNOWN + 7 used, adding exactly one new succeeded operation. Original 16 operation identities/attempts/targets and all 3 compensation records remain. Three old operation observation timestamps changed, and one existing UNKNOWN observation receipt was updated read-only; no old asset status changed. All 16 original media files match their pre-round size and SHA-256. Clipboard reconciliation/checkpoint tables are compared separately in the audit.

Private before/after SQLite snapshots, media inventories and raw native trace are kept outside Git under the round4 private backup directory. An invalid duplicate remote ref filename `origin/HEAD 2` was moved intact into `.git/riftlet-preserved-invalid-refs/`; valid refs/branches and previous worktrees were not reset. Remote heads were independently verified. A later Git push used the machine's already configured local HTTP proxy for that command only, without changing system/Git settings.

The App was normally terminated after settled success. The temporary preservation listener was removed. The original v8 page observer/root monitor is intentionally retained for read-only late-failure recovery; stopping it would clear its original proof. No registry, UNKNOWN, database or compensation audit was cleared. While the App is stopped it cannot write late compensation; restart can observe only while the original page/registry/browser session still survives. This is not an unattended monitor promise.

## Next Pro action

Integrate the two source commits and this handoff on the formal branch; review the persisted-profile Core proposal and original-event ACK publication interface. Keep production and safe-retry admission closed. Next live work should target the **missing cold first-click boundary and actual business transitions**, rather than repeating this prebound success. Apply the new uploadStarted visual contract in Pro's lifecycle, then independently verify it with source and completion gates intact.
