# Source-level technology reuse index

Pro independently reviewed these repository versions; **no open-source code has been copied into Riftlet**. Licenses must be checked again at actual integration time, and relevant copyright/NOTICE retained. Not all artwork/brands inherit source-code licenses.

| Project (pinned source) | Main files / modules | Candidate value | Exclude / caveat |
| --- | --- | --- | --- |
| [Sukurini](https://github.com/ssut/Sukurini/tree/c74210f81347a1df4ef407523361e7a45c12ab3e) (Apache-2.0, NOTICE) | `Sources/Sukurini/Core/FolderWatcher.swift`, `ThumbnailLoader.swift`, `ScreenshotStore.swift`, `LatestScreenshotPaster.swift` | Watcher lifecycle, bounded image loading/cache | Fixed-delay clipboard restoration and absent ready feedback |
| [Screenshoss](https://github.com/m0ztop/Screenshoss/tree/8ef6ef7cf721a2eb29f76a94815e6992d3d3a1ac) (MIT) | `Sources/ShossApp/ScreenshotLibrary.swift`, `ScreenshotImportService.swift`, `ShelfPanelController.swift`; filesystem integration tests | Stable completed screenshot file detection and tests | Don't move original screenshot or assume only English filenames |
| [Tendedero](https://github.com/alejandrobujan/tendedero/tree/32a3e47187fdea7b2fd43b3ab5a913f0ed33724a) (MIT code; asset restrictions) | `LinePanel.swift`, `ScreenshotWatcher.swift`, `Line.swift` | Extremely thin nonactivating edge UI | Exclude private CGS calls, automatic oldest-item deletion, branding and decorative sound/motion |
| [Oracle](https://github.com/steipete/oracle/tree/fde96271db1611c0287fcfde3053c19325280d10) (MIT) | `src/browser/actions/attachmentDataTransfer.ts`, `attachmentEvidence.ts`, `attachmentContext.ts`, `attachmentProgress.ts` | File/Blob input, scoped attachment evidence and target context | Its weaker input-only READY fallback, text mutation and sending messages |
| [Maccy](https://github.com/p0deje/Maccy/tree/54fb9f00b828a4ec367e706c0e276df90febe76a) (MIT) | `Maccy/Clipboard.swift` | Pasteboard representations and change counting | Never equate paste delivery with target upload completion |
| [Screeen](https://github.com/Clipy/Screeen/tree/f8f4bfa6cb38cb69ec1ee104fb5ad949a92b2ae3) (MIT) | `Lib/Screeen/ScreenShotObserver.swift` | Supplemental metadata scan | Insufficient as sole low-latency ingestion |

**Research conclusion:** reuse individual proven mechanisms; do not fork a whole screenshot shelf with conflicting product behaviors. See the 23-page original report for detailed references.
