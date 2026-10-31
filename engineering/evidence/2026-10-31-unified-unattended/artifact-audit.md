# Formal unified App artifact provenance — 2026-10-31

**PASS, artifact provenance only.** Both architectures were downloaded and inspected without executing either App. This audit performs no GUI, Chrome, account, database or permission operation and does not rerun CI.

## Why the artifact SHA differs from the PR head

[Native run 41126228170](https://github.com/haohongfei2001-png/Riftlet/actions/runs/41126228170) and [Feedback run 41126227847](https://github.com/haohongfei2001-png/Riftlet/actions/runs/41126227847) are successful `pull_request` runs. Their API head is `2bddb61a19114167b7485c392600c4b91dc62725`, but checkout logs prove both actually used `refs/pull/1/merge` at `f2610e795c2eb41242289a32d0517edde094b587`.

The merge has parents `fccd809e9d55e0b221e75e6dcd7c21f6d357ee74` (base) and `2bddb61a19114167b7485c392600c4b91dc62725` (formal head). Its differences from the formal head are 28 website-only files. Thus the full trees differ, while the App/build source inputs do not. No website was overwritten to obtain this result.

Each architecture's actual Beta ZIP contains a `build-info.json` recording both source head and checkout SHA, the Native run ID and its architecture. All 14 recorded build-input Git objects match the formal head exactly: Sources, Tests, Resources, Package.swift, scripts, packaging, .github, Feedback service, notices, research and four original evidence directories. Every listed package file SHA256 matches its actual ZIP bytes. Native source admission, ARM tests/package and Intel tests/package all passed; Feedback checkout and success were independently read from their logs.

## Verified artifacts

| Architecture | GitHub artifact ID | App binary SHA256 |
|---|---|---|
| arm64 | 13011261938 | `7bc97eca7c9ce66ce1a5e4554145131d5e02059c2cddc009b14bee12b210b475` |
| x86_64 | 13012235205 | `5d80bd630d95dd36163bcf405d1d43178984b24efa50f4e4c1b0661a26d0546c` |

Artifact names are `native-foundation-macos-15-f2610e795c2eb41242289a32d0517edde094b587` and `native-foundation-macos-15-intel-f2610e795c2eb41242289a32d0517edde094b587`. Each includes `build/Riftlet-Internal-Beta.zip` and `build/Riftlet-macOS-development.zip`. Within each architecture the two packages contain identical App executable bytes. Mach-O CPU type independently matches the manifest. ZIP hashes and all exact input objects are in [artifact-audit.json](artifact-audit.json).

The ARM package can supply the exact formal baseline for the authorized Mac's tests. The Intel package is provenance-verified only and was not run on ARM. These packages are development builds without Developer ID signing/notarization, not public releases.

## Product and successor boundaries

The manifest explicitly says ordinary default `capture-upload-disabled`; its internal launcher uses `--system-screenshot-candidate`. Successful CI does not open ordinary upload, safe retry, Web continuation or new sources. Historical H acceptance in the manifest is not a fresh unified-App Chrome result.

**These artifacts predate the subsequent local startup-instance ownership patch.** Their exact hashes, CI success and source-admission results must not be relabeled as testing or packaging that successor. A successor build must retain its own source/binary identity and appropriate checks. This audit neither installs nor launches an App and supplies no new physical, real Chrome or final successor end-to-end acceptance.
