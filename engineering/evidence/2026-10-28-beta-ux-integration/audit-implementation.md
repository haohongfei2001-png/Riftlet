# Beta UX fixed-source audit update

Role: audit implementation author, not the final independent reviewer.
Date: 2026-10-28 (Asia/Shanghai).

## Authorized scope

Only these repository files were edited:

- `scripts/verify-internal-beta-integration.py`
- `Tests/InternalBetaIsolation/test_integration.py`

No product source, workflow, Git commit/ref, endpoint, browser, application data or real screenshot was changed by this role.

## Fixed composition policy

The read-only audit still inspects committed Git objects with replacement refs disabled. The CLI has no source-pin override, does not read dirty files as policy, and does not fetch or mutate the repository. Missing fixed objects fail closed.

The fixed ancestry now requires all six accepted commits:

| Role | Commit |
| --- | --- |
| Original restricted screenshot source | `e421e6687651c2fac1441410c1af2bd5b8151e55` |
| Original H evidence | `c177174e400064d8ec8bb79685c33d01c4e93b89` |
| Feedback delivery | `f195bebbc22ed1a162b5866ca1fe6c7ccb9835b9` |
| Existing unified Beta | `b4bcfa41e8e237723b975d2a9a0059e955fa0c1f` |
| Approved UX source | `fa74f3c68f05ab4eaccfc24e2f39c0177289ddb3` |
| UX evidence handoff | `8e1a1688e75db8c18965e073ae357010e7397a3a` |

The seven approved non-Main UX files are checked against their exact `fa74f3c` objects (mode, type, SHA). The four affected UI/GUIAcceptance/UI-test/App-test directories retain exact recursive `e421e668` objects for every other file, including rejection of added unreviewed neighbors. Original App files stay pinned to `e421e668` except the two individually checked UX files, the separately checked FeedbackHost, and the separately reviewed Main.

The combined Main blob is pinned to `05fe28ec734ba0d8c040810c737b26715a33d5de`, supplied by the integration lead after the two requested conflict resolutions. That blob was not authored by this audit role and must receive independent composition review.

The original ten protected screenshot trees/paths retain their exact original `e421e668` objects, including Core, Capture, Adapters, CSQLite, Resources, ThirdPartyNotices and their unchanged tests/Web tests. All eleven Feedback source/test/service/Package/script paths retain exact `f195beb` objects. Both H and UX evidence directories retain exact `c177174` / `8e1a1688` objects respectively.

The complete expected audit has **42 checks**: 6 ancestry, 10 unchanged screenshot paths, 7 approved UX files, 11 Feedback paths, 2 evidence directories, 4 unchanged portions of affected UX roots, 1 unchanged original App set, and 1 exact reviewed Main. Report schema advances to 2 to reflect the new pins.

## Validation performed

`python3 -m unittest discover -s Tests/InternalBetaIsolation -v`: **10 tests passed**, no skips/failures. Each fixture constructs actual isolated temporary Git histories, including the earlier Feedback merge and a later UX/evidence branch from before that integration. The tests cover:

- Exact accepted merged composition despite dirty/untracked worktree files.
- Old Core overwrite rejected.
- Feedback mutation rejected.
- All seven approved UX files reject old Beta content.
- Unapproved neighboring changes/additions inside affected directories rejected.
- Lost files from either evidence archive rejected despite retained ancestors.
- Identical flattened tree without required delivery ancestry rejected.
- Copied UX content on the old unified Beta without the UX/evidence parents rejected.
- Main, ordinary App changes and unreviewed App additions rejected.
- Fixed CLI pins, structured missing-object failure, and explicit override-option rejection.

`git diff --check` for both edited paths passed. No host repository test commits/refs were created; all fixture writes were isolated to temporary repositories and automatically removed. The actual final integration revision must run the 42-check CLI after its committed merge exists, followed by the required independent review and CI. These local fixture results do not stand in for final macOS CI or real-Mac experience.
