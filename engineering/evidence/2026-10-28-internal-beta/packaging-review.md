# Internal Beta packaging, CI and composition audit — non-author review

Date: 2026-10-28. Reviewer: `beta_integration_review`.

Scope: read-only review of the lead's new packaging/CI files and the independent evidence reviewer's fixed-source audit in `/workspace/scratch/16d4559e9aa8/Riftlet-internal-beta`. The reviewer wrote no repository source, index or refs. Only synthetic package and temporary real-Git regression tests were executed; no real App, screenshot input, cloud service or permission prompt was launched.

## Verdict

**PASS for the reviewed packaging implementation, CI wiring and audit source; no unresolved blocking finding.** Final committed-tree audit, actual macOS native build/executable checks, final workflow conclusions and downloaded artifact integrity remain separate required gates, not claimed by these Linux checks.

## Unified runnable package

`scripts/package-internal-beta.sh` requires macOS, verifies the already built complete `build/Riftlet.app` against repository resources, verifies its strict ad-hoc signature, copies it into a fresh temporary package, adds the explicit candidate launcher and Chinese instructions, writes and verifies build metadata, verifies the copied signature, and produces `build/Riftlet-Internal-Beta.zip`. It copies the real `Riftlet` App rather than the separate Feedback Demo. It does not overwrite an installed App, change user data or download/deploy a service. It rejects linked build/archive destinations and removes only its own temporary packaging directory.

The launcher resolves its own physical directory with quoted shell operations, requires the adjacent executable, and calls `open -n -a <that exact App> --args --system-screenshot-candidate`. There is no eval, argument forwarding, fallback to a globally installed App, process killing, data reset, trace switch, permission automation or cloud configuration. The executable bit is explicitly set and verified. It does not modify ApplicationMode or ordinary capture policy.

The README clearly names the `.command` file as the primary entry, identifies `Riftlet REAL TEST`, explains the temporary Terminal window and lack of Dock icon, preserves the same candidate data directory, and states that direct App double-click is ordinary collection-only. Existing first-use/source/Chrome permission guidance remains in the actual candidate App. The alternate menu path is explicitly secondary. Signature/notarization and unexecuted Finder/Gatekeeper limitations are honest; no blanket quarantine deletion or security bypass is prescribed.

The README retains limited Chrome Chinese ordinary-existing-thread and original single-frame noninterlaced RGBA8 PNG scope, local-only Feedback, no send, no production/retry admission, and preservation of F/H/old UNKNOWN. It distinguishes the source-e421 real CGEvent acceptance from a not-yet-run combined-App real-Mac session.

## Artifact identity and validation

The package checker requires exactly four top-level entries: complete App, launcher, README and build-info.json. All entries must be regular files/directories. It reuses the original strict bundle verifier, verifies launcher executability and byte equality with reviewed package source, and records/checks binary, Info.plist, launcher, README and both adapter resource hashes.

Manifest generation resolves an exact source commit and actual CI checkout, requires source ancestry, compares fourteen relevant build/test input Git objects between the source head and the CI checkout, and rejects tracked input changes. It includes actual CI run ID and architecture; the real acceptance source/evidence are separately labelled. Ordinary capture-disabled mode and local-outbox/no-endpoint Feedback boundaries are checked. A PR synthetic merge cannot be silently relabelled as the source head: mismatching input objects fail packaging.

This source/manifest mechanism is strongest for the clean Actions checkout that performs the actual build immediately before packaging. It is not a claim of reproducible binary compilation or a substitute for downloading and hashing the final archive. The final handoff must record both source HEAD and actual CI checkout, plus final App/archive hashes.

## Fixed-source composition audit

`scripts/verify-internal-beta-integration.py` independently pins:

- official screenshot source `e421e6687651c2fac1441410c1af2bd5b8151e55`;
- real acceptance handoff `c177174e400064d8ec8bb79685c33d01c4e93b89`;
- delivered Feedback source `f195bebbc22ed1a162b5866ca1fe6c7ccb9835b9`;
- reviewed combined Main blob `5b1c64348cc0661f0de359c45a54158e828d6c22`.

The actual Main worktree blob independently recomputed to the pinned value. Protected screenshot files still compare equal to e421. The CLI exposes no environment/source-pin override. It disables Git replacement objects, validates exact commit identities, checks all three delivery ancestors, compares directory trees/modes rather than inferred filenames, requires every expected path to exist, preserves the acceptance evidence tree, checks every original App file except the explicitly handled Main/FeedbackHost, and requires the exact reviewed Main blob. An identical flattened tree with missing delivery history fails. The check deliberately examines a committed revision; uncommitted worktree files cannot make a bad commit pass.

The seven new regression tests create independent temporary Git histories matching the older Feedback branch/newer screenshot base. They cover correct two-parent composition despite dirty/untracked worktree files, old screenshot overwrite, Feedback mutation, lost evidence, flattened ancestry, unreviewed Main/other App edits, and refusal to substitute fixture pins through the executable CLI.

## CI wiring

The native workflow now fetches full history without persistent credentials, retains the complete existing native/Web/legacy/SQLite/lifecycle/self-check gates, runs the seven new packaging tests, reports Feedback's existing native/UI tests in detail, packages the unified App after executable checks, and uploads the new Beta ZIP alongside ordinary engineering artifacts. The source-head environment resolves to the PR head for PR runs and actual push SHA for direct branch runs; the package checker separately verifies checkout inputs.

The Feedback workflow retains its original four isolation regressions, original branch-specific composition audit, service tests, native/window tests and offline Demo build. It adds seven committed-Git integration regressions and the fixed-source audit for this combined delivery. That closes the PR #1 audit gap without interpreting old/stale PR base metadata as source authority. The Demo remains a separate artifact and is not the founder's unified App.

## Reviewer-executed checks

Executed with `PYTHONDONTWRITEBYTECODE=1` to avoid reviewer writes to the worktree:

1. `python3 -m unittest discover -s Tests/InternalBetaPackaging -v`: **7/7 passed**. The launcher test uses a fake `open` and a package path containing both spaces and literal `$()` characters; exact argv is preserved without command substitution. Other cases reject missing executable, modified launcher/resource, missing execution permission, symlink entries, false production/cloud metadata and incomplete build identity.
2. `python3 -m unittest discover -s Tests/InternalBetaIsolation -v`: **7/7 passed**, using real temporary Git object histories; no host repo mutation or network.
3. Protected-path `git diff --exit-code e421 -- ...`: exit 0. `git hash-object Sources/RiftletApp/RiftletMain.swift`: exact pinned Main blob above.

These are fourteen unique Python cases, separate from native test totals. They do not prove a real App launch, Gatekeeper first install, physical mouse, Keychain prompt, UI latency or cloud delivery.

## Final handoff requirements still tracked

Before declaring delivery complete: record the actual committed-source audit PASS, final source/CI checkout ancestry, final full macOS and Feedback CI conclusions, native counts without counting repeated suites twice, real native package executable/self-check/signature results, final artifact download/hash verification, and a concrete founder/local-Codex entry. Preserve the original software CGEvent limited PASS and all unadmitted production/retry/physical/cold-first-click boundaries. Exclude generated `__pycache__` files from the commit.
