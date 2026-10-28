# Internal Beta composition audit — implementation handoff

Date: 2026-10-28 (Asia/Shanghai)

Author: `beta_evidence_review`, acting as the assigned audit implementation author for this packet. This new audit must receive a separate non-author review; my earlier independent c177 evidence review does not constitute independent review of code I authored here.

## Exclusive changes

Only these two new worktree paths were written:

- `scripts/verify-internal-beta-integration.py`
- `Tests/InternalBetaIsolation/test_integration.py`

No existing source, resource, script, workflow, Git index, reference or repository object was modified. Temporary regression repositories and this report reside under `/tmp`.

## Fixed contract

The executable's pins are code-owned and have no CLI/environment overrides:

- Official screenshot source: `e421e6687651c2fac1441410c1af2bd5b8151e55`.
- Evidence-only child: `c177174e400064d8ec8bb79685c33d01c4e93b89`.
- Feedback delivery: `f195bebbc22ed1a162b5866ca1fe6c7ccb9835b9`.
- Minimal merged `RiftletMain.swift` blob: `5b1c64348cc0661f0de359c45a54158e828d6c22`, independently obtained by `git hash-object` on the current reviewed minimal composition.

The chosen revision defaults to HEAD and is resolved to an actual commit, tree and parent list. It must have all three deliveries as ancestors, regardless of whether CI checks out a direct integration push or a synthetic PR #1 merge. Missing Git objects/history fail closed. Git replacement objects are disabled; revision strings cannot inject Git options.

All comparisons read Git objects, including file mode and object type. No working-tree file contents, untracked paths, event base metadata, current remote ref, or merge-parent ordering supplies comparison authority.

31 structured checks cover:

1. Three exact required ancestors.
2. Fourteen complete screenshot-related trees: Core/Capture/UI/Adapters/GUIAcceptance/CSQLite, Resources/ThirdPartyNotices, all five screenshot Swift-test modules, and WebPageProgram, against e421.
3. Eleven Feedback trees/blobs, including Core/UI/Demo/Host, both native test modules, original isolation tests, services, Package.swift, demo builder and original isolation shell script, against f195.
4. The entire original c177 evidence directory, preserving all seven files verbatim.
5. Every original App path except Main and the separately checked FeedbackHost. Missing, modified and unexpected added App files fail.
6. Main's exact reviewed `100644` blob.

The program writes a structured JSON report to stdout and a single `INTERNAL_BETA_INTEGRATION_PASS` or `INTERNAL_BETA_INTEGRATION_FAIL` marker to stderr. Exit status is 0 only for complete PASS. It performs no fetch, file creation or Git mutation.

## Executed meaningful regressions

`python3 -B -m unittest discover -s Tests/InternalBetaIsolation -v`

**7 tests passed, 0 failures, 0 skips (1.456 seconds in this executor).** Each test creates a real independent temporary Git history where Feedback forks from an older common baseline, the screenshot branch advances, an evidence-only child is added, and a true two-parent merge resolves Main. They check:

1. Correct three-way composition passes even with dirty tracked and untracked working-tree files, proving the audited input is the committed tree.
2. Restoring old screenshot code from the Feedback baseline fails; explicitly selecting the previous good commit still passes.
3. Mutating delivered Feedback source fails.
4. Removing a single acceptance file fails despite preserved ancestry.
5. An identical tree with flattened/missing acceptance and Feedback ancestry fails exactly those ancestry checks.
6. Old Main plus altered/extra App files fail their separate checks.
7. The real CLI rejects fixture histories missing its fixed production pins and still emits parseable JSON plus a clear failure marker.

`git diff --check` also passed. No Swift/native/Mac execution is claimed here.

The real worktree's precommit HEAD is still c177 while the Feedback merge remains uncommitted. Running the new CLI on that real HEAD correctly returns FAIL for the absent Feedback ancestry, Feedback delivery paths and reviewed merged Main; it does not accept pending index or working-tree contents. This is expected and not the final combined CI result. The diagnostic report is `/tmp/riftlet-beta-integration-precommit-audit.json`. Run against the actual committed merge once the integration lead creates it.

## CI entry points for the integration lead

The checkout requires `fetch-depth: 0` (or equivalently all referenced commit history). Suggested commands:

```bash
python3 -B -m unittest discover -s Tests/InternalBetaIsolation -v
python3 scripts/verify-internal-beta-integration.py HEAD > test-results/internal-beta-integration.json
```

Create the output directory in the workflow; the audit itself remains read-only. A distinct `--repository /path/to/worktree` and positional Git revision are supported for read-only inspection. The original Feedback PR isolation shell script remains unchanged.

## File integrity

- Audit SHA-256: `6573d6f3dda074f37bb089e43e9962dff5fe3fda32196c384c61874220e00ecf`.
- Regression SHA-256: `05405ef1ca9ea4c7844c97e6168b8708dce4b9647b74274b1ccb42dfc03cbb55`.

Any later change to the reviewed Main requires a deliberate new non-author review and a new code pin, not an environment bypass. No product behavior or screenshot admission was changed by this packet.
