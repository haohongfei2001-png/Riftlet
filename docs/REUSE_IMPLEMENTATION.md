# Source reuse and license record

2026-10-27. Native application has **zero third-party package/runtime dependencies**. Its frameworks and SQLite come from macOS. This record distinguishes adapted mechanisms, independently written code and archived source evidence.

| Source (pinned) | Exact origin | Riftlet use and modifications | License handling |
| --- | --- | --- | --- |
| Sukurini `c74210f81347a1df4ef407523361e7a45c12ab3e` | `Sources/Sukurini/Core/FolderWatcher.swift` | Lifecycle adapted in `RiftletCapture/FolderWatcher.swift`: open event-only FD, DispatchSource, cancel-close, rename/delete/revoke. Own bounded debounce/generation/recovery integration; no Log/store/updater/analytics | Full Apache-2.0 + original NOTICE in `ThirdPartyNotices/Sukurini`; modification attribution in source |
| Screenshoss `8ef6ef7cf721a2eb29f76a94815e6992d3d3a1ac` | `Sources/ShossApp/ScreenshotImportService.swift`, filesystem test ideas | Signature/complete-image mechanisms in `FileValidation.swift`, new tests. Add source identity, symlink rejection, private copy/recheck/decode; no moveItem, English filename filter or serial per-file delay | Full MIT and copyright in `ThirdPartyNotices/Screenshoss`; source attribution |
| Tendedero `32a3e47187fdea7b2fd43b3ab5a913f0ed33724a` | `Sources/Tendedero/LinePanel.swift`, `GrabArea.swift` first-mouse mechanism | Independent small AppKit panel implementation; no source/artwork imported, no CGS, pointer polling, delay-before-single-click or automatic deletion | Preserve upstream MIT/restricted-artwork notice for reference in `ThirdPartyNotices/Tendedero`; no implied license to name/icon/docs images |
| Oracle `fde96271db1611c0287fcfde3053c19325280d10` | attachmentEvidence/Context/Progress/DataTransfer and completion | Runtime code not imported. Composer/identity concepts inform interface. Six original source/fixture files plus LICENSE are archived only for reproduction | Upstream LICENSE beside `research/technical-decision-2026-10-26/evidence/oracle`; not a runtime dependency |
| Maccy `54fb9f00b828a4ec367e706c0e276df90febe76a` | `Maccy/Clipboard.swift` | Reference only; no clipboard code this tranche. Future small writer after Mac evidence; audit Clipy-derived paste section if actually copied | No runtime source copied. Retain MIT and applicable Clipy attribution if adopted later |

Fixed URLs and original scope: [source manifest](../research/technical-decision-2026-10-26/SOURCE_MANIFEST.json), [detailed reuse map](../research/technical-decision-2026-10-26/02_REUSE_MAP.md). No blanket license decision for Riftlet's own newly authored code is implied by preserving upstream licenses.

The build script includes `ThirdPartyNotices` in `.app/Contents/Resources`. Archived Oracle evidence remains source-only; it is not packaged into the app. No upstream brand/logo/photograph is reused. Each new adaptation should update this record with source commit, exact path and modification scope before merge.

## Reuse decisions during parallel development

The implementation lead selects reuse without a routine user-approval step. Start with the pinned source above, inspect the exact required functions, compare their adaptation cost with a small native implementation, and record the result. Do not repeat broad competitive research or fork a complete upstream app to unblock one module. Retain the license/copyright/NOTICE in the same increment that introduces copied or adapted code; attribution is not a release-only follow-up. Current use of Sukurini/Screenshoss, independent Tendedero-informed panels and reference-only Oracle/Maccy must remain distinguishable in progress reports.
