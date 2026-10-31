# Independent integration evidence / ancestry / CI-scope review

Reviewer: `/root/review_evidence` (non-author; read-only tracked source, refs and source evidence).

Reviewed commit: `f2ae645451044649fbe73326952efbe084353869`.
Reviewed tree: `33494e55f3e067782fa2b5f97d61450776f88286`.
Official baseline: `4b7228a07a23381d3de467a44dd8490d73e26e7e`.

## Result

No source/evidence integration blocker found. The six-commit chain is directly fast-forwardable; no duplicate cherry-pick, squash or manufactured merge is required. Final integration-document and actual new macOS CI verification remain separate from this source review.

## Ancestry and preservation

- Actual parent chain is `4b7228a → a5db972 → 3f4e18a → 5d2994c → 867d93f → 48574df → f2ae645`. Each full source SHA was checked with Git ancestor predicates. This preserves stage1 permission wake fix and tests, stage2 v9 monitor compatibility and sRGB fix, original commits and source evidence.
- Stage1 evidence directory Git tree at `f2ae645` equals its tree at `5d2994c`. The final handoff commit changes only documents/evidence: Sources, Tests, Resources, Package.swift, scripts, .github, ThirdPartyNotices and research root objects all match `48574df` exactly.
- Baseline Core, Capture, UI, candidate composition/configuration, ApplicationMode, SelectionAuthority and first-use preference/self-check files have unchanged Git object IDs. The App production diff is limited to consuming the permission-loss scheduler wake and correcting a nil-target diagnostic Boolean; Web production diff is limited to allowing the reviewed v9 owner and removing the canvas performance hint.
- Feedback branch diverges at `4b7228a`; its separate `907f23a` App wiring is absent from this source chain. No Feedback target, source module or Package change is imported. Review did not mutate feedback refs, worktrees or files.
- All three candidate admission maps are explicitly empty in `Sources/RiftletApp/SystemScreenshotCandidateConfiguration.swift:10–12`. Ordinary `.capture` composition still constructs `UnavailableAdapter` with default empty receipt policy (line 36). Existing SQLite v3, original-selection authority, UNKNOWN preservation and no-replay implementation are inherited intact; this review makes no new real-database integrity claim.

## Requested macOS CI coverage

`.github/workflows/native-foundation.yml` at reviewed source runs on macos-14 and includes full parallel native tests, current Web and legacy observe fixtures, archived Web replay, round2 fault/round3 probe/round5 helpers, stage2 helpers, packaging rejection tests, detailed software lifecycle/permission/selection/candidate suites, Release app build and packaging, bundle/ad-hoc checks, four App self-check invocations and GUI helper self-check, plus artifact archive.

The package includes Core/Capture/UI/App/Adapters test targets. The full native suite includes frozen v1→v3 and v2→v3 migration preservation, future-schema rejection and migration rollback in `LifecycleMigrationTests`; UNKNOWN/intent recovery and immutable identity in QueueStore/accepted-selection/journal suites; original ACK-before-event and cancellation tests; the three new `TargetArmPermissionWakeTests` (lost idle wake, consumed wake and single in-flight capture, old-epoch/duplicate completion refusal). The new scheduling tests explicitly do not claim AppKit wiring coverage and contain no XCTSkip.

The original integration branch name was outside push filters. Lead chose the existing permitted `codex/riftlet-real-mac-acceptance-sc-integration-20261028` namespace to obtain CI without workflow/source modification. This resolves execution routing; no permission or test criterion was weakened.

Actual new-run outcome is pending independent log verification. Prior source CI `40656871851` remains prior-source evidence and cannot be relabelled as a new final-HEAD run. CI self-checks are synthetic and do not substitute for real Chrome/system screenshots/physical GUI.

## Inherited real evidence: exact limits

- Stage1 `a5db972`: a single original input of A after earlier rejected clicks; SC-INPUT limited PASS. No positive start; attached candidate observation exists but full SC-COMPLETE FAIL for missing complete preservation/content evidence. This is not proof of unbound cold first click.
- Stage2 actual input runtime is `867d93f`, not fixed `48574df`. One new 1.56 MiB system PNG D, CGEvent down/up, pre-event ACK, original asset/op/attempt/hash/full target, inputCount=1, begin1/chunk7/commit1. SC-INPUT limited PASS.
- SC-START limited PASS is supported by the recorded original progress node increasing 10.2964→18.5335 below 100 after verified file hash, before final progress removal/load, and candidate journal start. Native and page clocks remain separate; no manufactured cross-clock latency is claimed.
- Stage2 full SC-COMPLETE remains FAIL on old runtime. The recorded readonly single-variable comparison found 108,932 one-level differences among 6,148,032 RGBA channels with `willReadFrequently`; removing it while retaining explicit sRGB gave exactly equal RGBA hashes for the same original and preview. This supports the precise fix, but is not patched end-to-end verification, server byte preservation or universal color-format validation.
- `48574df` changes only the context option, retaining exact matching. No new real-system screenshot input after that fix is present. D remains UNKNOWN; no old operation proof may be backfilled and no old input retried.
- Stage2 text48/selection8..11/editor-unfocused preservation is limited to that recorded ordinary-thread case. Old attachment baseline was zero; nonempty old-attachment matrix, physical mouse, no-ACK cold click and full T0/T1/T2 are not covered. Candidate start/completion/safe-failure and ordinary production stay closed despite SC-START evidence.
- Source evidence reports old media/databases/checkpoints retained; private raw data was not accessed by this reviewer and those preservation claims were not independently remeasured here. No live input/GUI/Chrome/database write was performed during this review.

## Current documentation follow-through

The pre-integration candidate document still said SC-INPUT/START NOT_RUN and v10/v12 only. Lead is updating current handoff, execution board and candidate document while preserving original historical packets. The final handoff must distinguish inherited limited PASS from patched completion still unrun, identify exact final HEAD/run, and keep all three admissions closed. This is a current-entrypoint correction, not a reason to repeat old acceptance experiments.

## Integration routing addendum by the lead

Creating the remote branch alone did not start a push workflow. The actual new source CI was started by Draft integration PR #8 targeting the engineering branch: run `40662720558`, head `f2ae645451044649fbe73326952efbe084353869`. No workflow or test criterion changed. The final-document/CI reviewer independently checked this run and the updated entrypoint documents. The earlier routing paragraph records the intended branch-filter match, not a claim that branch creation executed CI.
