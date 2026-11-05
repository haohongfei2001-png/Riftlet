# Resume here

1. Read this directory's STATUS, EVIDENCE and BLOCKERS; inspect actual Git status/HEAD and open PRs. Do not restart from historical candidate instructions.
2. Engineering worktree: `codex/autonomous-readiness-20261106` from b61fc46. Separate existing design branch: `design/settings-control-center-20261106`.
3. Current ownership: root integration/reliability/settings; storage contributor `scripts/storage-*`, `Tests/StorageReadiness/`, `docs/STORAGE_RECOVERY.md`; release contributor `scripts/release-*`, `Tests/ReleaseReadiness/`, `packaging/release/`, `docs/RELEASE_ENGINEERING.md`. Independent reviewer closes design WP01 then reviews engineering units.
4. Finish WP01 commit/push, continue WP02–WP07. No installed-App update, private-chat test upload, production write or main merge is implied.
5. Preserve raw failed tests, hashes and original evidence. Use `test-results/` for local execution logs; only sanitized engineering summaries enter public Git.
6. For a formal PR, follow `docs/MAINLINE_GOVERNANCE.md`: exact source G, non-author review, direct admission-only H, actual five checks. Do not claim source admission from a passing build.

This is a persistent checkpoint, not a claim that an unattended background executor will continue after this session stops.
