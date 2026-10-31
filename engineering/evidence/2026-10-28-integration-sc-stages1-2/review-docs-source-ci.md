# Independent final-document and source-CI review

Reviewer: `/root/review_evidence`, non-author. Read-only repository review plus independent GitHub run/job/log/commit/artifact retrieval; no repository tracked edits, ref mutation, real Chrome input, GUI or private database access.

## Verdict

PASS for reviewed source `f2ae645451044649fbe73326952efbe084353869` and its new complete macOS CI `40662720558`. Current handoff documents correctly preserve inherited limited SC-INPUT/SC-START, old-runtime SC-COMPLETE FAIL, patched new-input NOT_RUN, empty candidate admission maps and closed ordinary production. No integration blocker found. A later final documentation commit's exact SHA and official PR #1 run still require verification; this report does not pre-approve or relabel that future run.

## Final-document and manifest verification

Reviewed the uncommitted integration-document diff in `docs/INTEGRATION_HANDOFF.md`, `docs/EXECUTION_BOARD.md`, `docs/SYSTEM_SCREENSHOT_WEB_CANDIDATE.md` and `docs/VERIFICATION.md` against `f2ae645`. The current entrypoint now states actual ancestry, original-source vs handoff distinctions, isolated feedback work, no repeated old merges/acceptance, original data-root preservation and the bounded next new-system-PNG completion check. Historical INTEGRATION_HANDOFF content remains an exact byte-for-byte suffix, rather than being overwritten or silently reclassified.

Independently recomputed `source-manifest.json` against Git and filesystem bytes: all 8 source/build input root pairs match `48574df` and `f2ae645`; all 11 preserved baseline objects match `4b7228a` and `f2ae645`; all 15 original first/second-stage evidence files match their byte length, SHA-256, original Git blob and complete original contents; all 6 listed review/log artifacts match their manifest lengths and SHA-256. Source and private-data claims remain explicitly separate.

One minor wording correction was requested and then verified in the final handoff: the preexisting attachment baseline was zero and total attachments became one. This replaces the shorthand “旧附件0→1” and prevents an unintended claim about preserving a nonempty old-attachment baseline.

Execution-routing correction to the earlier review: creating the branch did not itself trigger a push run. Actual new source CI was triggered by **Draft PR #8**, from `codex/riftlet-real-mac-acceptance-sc-integration-20261028` to `codex/engineering-foundation-20261027`; workflow contents remain unchanged.

## Exact new source CI

- Run: https://github.com/haohongfei2001-png/Riftlet/actions/runs/40662720558
- Run event: `pull_request`, Draft PR #8.
- Reported head SHA: `f2ae645451044649fbe73326952efbe084353869`.
- Job: `122729461430` (`macos`).
- Result: `completed/success`; **18 steps all success**.
- Run updated/completed observation: `2026-10-28T09:16:55Z` / 2026-10-28 17:16:55 UTC+8.
- Environment observed in actual log: macOS 14.8.9 (23J631), arm64, Apple Swift 5.10.
- Actual checkout from log: `3be371d10c2a7a0482faa2cf82eb6aca6399aaaa`.
- Independently fetched GitHub Git-commit object confirms parents `[4b7228a07a23381d3de467a44dd8490d73e26e7e, f2ae645451044649fbe73326952efbe084353869]` and tree `33494e55f3e067782fa2b5f97d61450776f88286`, **the entire reviewed f2ae645 tree exactly**. It is a temporary PR checkout; it is not a merge to main or a change to the formal branch.

The independent complete decoded job log is 250,164 UTF-8 bytes, SHA-256 `631fccb59e663d2ca575c7d00df4fde18367ff388d764a32ea2515a1460b94af`. All test names, final statuses, compiler/build/self-check markers, checkout identity and artifact-upload receipt were examined from this new log. The older source run `40656871851` is not being reused as the new-run result.

## Actual tested counts and gates

| Gate | Actual result |
| --- | --- |
| Unique native tests | 443: Core138 / Adapters137 / Capture65 / UI56 / App47 |
| Detailed existing native suites | 16 suites, 106 passed / 0 skipped; included in the 443, not additive |
| Current Web / historical observe fixtures | 86 / 61 passed, failures0/skips0 |
| Stage2 diagnostic helper fixtures | 12 passed, failures0/skips0 |
| Archived replay | 19 cases; two late-error checks explicitly SIMULATED |
| Round2 fault / round3 read-only probe | 8 / 12 groups passed, real MID still NOT_RUN |
| Round5 helper fixtures | 9 / 4 / 2 passed |
| Packaging rejection tests | 12 passed |
| Release App build | Success; actual build completion logged |
| Bundle / resources / notice / ad-hoc signature checks | PASS, development artifact, not notarized |
| App/helper checks | All five PASS; synthetic scope markers retained |

The full native log includes all four frozen migration/rollback/future-version tests and all three new TargetArmPermissionWakeTests. Existing UNKNOWN/old-target locks, compensation, candidate journal, original ACK-before-event, cancellation, permission/session isolation and original selection tests remain present. No actual skipped-test record appeared in the full log; the 16 detailed suites reported pass individually.

The five check markers are ordinary self-check, Web acceptance, first use, system screenshot candidate, and GUI acceptance helper. They explicitly retain `GENERATED_FIXTURE`, `CHROME_NOT_RUN`, `SYSTEM_SCREENSHOT_NOT_RUN`, `PERMISSIONS_NOT_REQUESTED`, `GUI_NOT_RUN`, `NOT_NOTARIZED` and `GATEKEEPER_NOT_RUN`. This CI does not assert patched real screenshot completion, physical mouse, TCC or production admission.

## Artifact verification scope

Artifact `12804193464`, `native-foundation-3be371d10c2a7a0482faa2cf82eb6aca6399aaaa`, 1,923,964 bytes, expires `2026-11-11T09:16:50Z`.

GitHub metadata digest and actual job upload log both report SHA-256 `60c24150d4478730ba1a3540e097adc085fff9b8912868b552743f861aed5cb4`. This reviewer did not download or independently recompute the ZIP digest. Its development App/helper and test logs are CI outputs, not a public release.

## Remaining verification boundary

Final evidence/document commit will have a different commit SHA while preserving tested source/build inputs. Before the formal handoff, independently check that exact final SHA's actual official PR #1 CI, temporary checkout inputs, all steps, test counts, self-check scope and artifact receipt. Preserve Draft status, do not merge main, do not admit any candidate start/completion/safe-failure policy, and do not imply a new real-system screenshot input occurred.
