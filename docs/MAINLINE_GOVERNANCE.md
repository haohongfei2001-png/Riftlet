# Riftlet mainline governance

## Official source and scope

The user authorized PR #1's standard merge into `main` on 2026-10-31. The actual
merge is `58f894af0f5d9bb0250c1e41750528232696b60c`, with ordered parents
`fccd809e9d55e0b221e75e6dcd7c21f6d357ee74` and
`253ac8db92bfba9083d485b71b84c594223da217`. Its tree is
`d7a16bf0d5550c3d54972d6fd4ac7c74133167eb`, identical to the previously reviewed,
tested and packaged PR merge `a589d1bddcb387fd45e71522265a811d4caacdc3`.

`main` is the official product source. The old long-lived PR #1 branch is retained
as history, not a second official baseline. Use short-lived PR branches from the
actual latest main; preserve both parents with standard merge commits. No squash,
rebase, force push, direct source push to main, or review bypass is authorized by
this governance work. Independent engineering review is not a GitHub human
APPROVED review; identify which evidence actually exists.

This change only governs Git and CI. It does not change any runtime product file,
upload profile, user data, screenshot, UNKNOWN record, or Feedback service.
Ordinary production input/start/completion, built-in screenshot upload, safe-retry
and Web continuation remain closed. Existing restricted candidate scope stays
unchanged. Native builds remain development/ad-hoc CI artifacts, not a public
release, notarized installer or real-device acceptance.

## Evidence-preserving source admission

`scripts/verify-final-product-composition.py` and the inherited historical gates
remain byte-for-byte unchanged. The new `scripts/verify-mainline-composition.py`
executes the old final gate's fixed blob at both the original PR #1 source and the
actual mainline foundation. Historical results remain attached to those sources.
The old gate deliberately still rejects later mainline source; do not edit it to
make a newer tree pass.

The successor gate freezes the foundation identity, tree and ordered parents,
all 34 approved website/configuration objects, all existing `engineering/evidence/`
and `research/` objects, and eight historical gate files. It also preserves evidence
already present in the reviewed main base, so evidence added in one accepted PR
cannot be rewritten by the next. New evidence may be added in an explicitly
reviewed source checkpoint; correct an old result in a new record instead of
rewriting the original result. Website changes require their own explicit policy
review, not an automatic allowance based on the current contents of main.

Each formal PR uses the following sequence:

1. Read the actual current main commit **B**, start a short-lived branch from it,
   and make the necessary source/test/documentation changes. Do not overwrite
   another developer's branch. Resolve integration before review.
2. Commit a complete source checkpoint **G**. The existing regular file
   `engineering/mainline/source-admission.json` must already be present. Its old or
   pending contents do not admit the new source. No source SHA is trusted merely
   because it is HEAD or because a build passed.
3. Have a non-author reviewer inspect G, the combined changes from B, relevant
   evidence and tests. Preserve the exact report as UTF-8 JSON. Reports must
   identify `reviewedSource`, `reviewedTree`, `reviewer`, and `result: "PASS"`.
4. Create **H**, a direct single-parent child of G that changes only the admission
   JSON. Record exact B/G/tree, the source author role, distinct reviewer roles,
   complete raw JSON report strings and their SHA-256 hashes. Preserve every
   production boundary field. Missing, stale, duplicate, malformed, oversized or
   mismatched review records fail closed. No policy/source CLI override exists.
5. Run the formal Native and Feedback workflows on the actual GitHub PR merge.
   The ordered parents must be exactly `[B, H]`; the complete merge tree and
   admission blob must equal H. Every other file/object/mode must equal G.
   The Actions event's repository, SHA, PR ref, base and head must agree with the
   actual commit graph. Actual checkout bytes/modes and unexpected inputs are
   checked directly, independent of Git ignore rules or index flags. Only Git
   metadata and `test-results/` / `feedback-results/` report roots are omitted from the untracked
   inventory. This is the pre-build source job, not a claim that a later test
   cannot write files in its separate execution runner. `.swiftpm` configuration
   and build directories are not exempt; use a clean source-job checkout.
6. Inspect the actual checks and artifacts, complete independent review of the
   admission-only delta, then perform a standard merge. If main advanced, integrate
   its current state into a new G and repeat exact review/admission; do not reuse
   a stale B. A source fix after review also requires a new G and reviewed record.
7. Verify the real main merge and its push CI. The push must identify the same
   ordered parents, `before == B`, and `after == checkout`. Single-parent direct
   main pushes, forced/deleted main updates and additional parents are rejected
   by source CI. These checks detect invalid changes; branch protection is needed
   to prevent such pushes from reaching the remote ref in the first place.

The JSON and verifier live in the repository. Their matching hashes establish
exact source agreement and record consistency, not cryptographic reviewer
identity. An author could otherwise edit both policy and claims. Independent
review of workflow/policy changes and remotely enforced PR protection are the
external trust boundary. Never describe this source check alone as protection
against an administrator or writer replacing the workflow itself.

## Long-term CI

Both existing workflows run on every main push and every main-target PR without
path filters, including documentation-only changes. Existing specialist push
patterns are retained. PR #24 and other active branches are not edited or
retargeted by this migration. Existing specialist-only step conditions remain
at their original scope.

| Required check name | Execution |
|---|---|
| Native source admission | New exact mainline audit, old pinned audits, existing isolation suites and new rejection fixtures |
| Native ARM64 | Existing complete Native pipeline on `macos-15` |
| Native Intel | Existing complete Native pipeline on `macos-15-intel` |
| Feedback source admission | Same mainline and historical source audit |
| Feedback native and service | Existing native/UI, service faults, repeated Close regressions and offline demo |

Both Native architectures still execute the complete Swift suite, packaging,
binary policy checks, native visual/R2 evidence and existing archived evidence
fixtures. Feedback service tests remain offline/synthetic, not native cloud E2E.
The workflows use fixed action commits, `contents: read`, no persisted checkout
credentials, and the actual PR merge checkout; no `pull_request_target`, secret
access, new skip, `continue-on-error` or test-count shortcut is introduced.

Local source inspection is `python3 -B scripts/verify-mainline-composition.py H`.
Formal jobs add `--github-event`; a missing event fails instead of silently
falling back to local mode. The in-process custom policy seam is only for
disposable Git fixtures in `Tests/MainlineIsolation`, not a CLI approval route.

## Remote main protection

`engineering/mainline/branch-protection.request.json` is the concrete desired
GitHub REST request body, **not evidence that protection has been applied**.
It requires the five unique check names from GitHub Actions app ID 15368, a
current base, one real non-author approving GitHub review, stale-review dismissal,
latest-push approval, conversation resolution and administrator enforcement.
Force pushes/deletion are disabled; linear-history enforcement is false so
standard two-parent merges remain possible. There is no bypass allowlist.

During migration the branch endpoint reported `protected: false`, no repository
rulesets were listed, and the protection endpoint returned HTTP 403
`Resource not accessible by integration`. The connected GitHub App does not
provide Administration access. Repository owner metadata is not that permission.
The missing capability is **repository Administration: write** (and a supported
configuration surface). The final delivery records whether this subsequently
changed. Do not claim remote enforcement from the checked-in JSON.

With authorized admin access, apply this body to the main branch protection
endpoint and read the result back. Before applying, verify the five check names
and GitHub Actions app ID against the actual completed governance runs and
ensure a real eligible non-author GitHub reviewer can approve future PRs.
Do not fabricate a second identity, self-approve an author's PR, dismiss a
blocking review or temporarily disable protection to merge.

## Active specialist work and final device acceptance

PR #23 is already an ancestor of the formal source; do not merge it again.
PR #24 remains an independent Draft R2.1 development task and is not admitted by
this migration. Preserve its branch and work. Once its owner reaches a handoff,
integrate the then-current main into a new reviewed checkpoint using the protocol
above, inspect all overlap, then target main deliberately. Historical research
branches do not all need to be merged.

The last product verification remains the exact R2 final delivery: Native
41182699411, Feedback 41182699399, source253/checkouta589 and the two original ZIP
hashes. Governance PR and main runs produce their own manifests and artifacts;
use their actual `sourceHeadSHA`, `checkoutSHA`, tree, run ID, architecture and
binary/ZIP hashes. Runtime source equality is not a claim of binary byte equality
or a newly completed physical test.

Outstanding acceptance is unchanged: final ordinary App startup/second instance/
exit/crash recovery; actual system capture and pointer/target preservation;
existing-chat and Home/local focused/unfocused first-click flow; original
selection-preservation failure; multi-monitor/Spaces/VoiceOver; native Feedback
to independently verified cloud delivery. Use only new isolated operations,
preserve old UNKNOWN/media/data, and defer only the exact physical action or new
permission that is unavailable. Do not open production admission to complete
Git governance. The original final PR #1 checklist remains the starting point.
