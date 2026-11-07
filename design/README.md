# Design — current and proposed desktop presentation forms

Riftlet's desktop supports five mutually exclusive presentation forms. The first three are retained as existing/design-tracked work; forms four and five are the new user-directed proposals.

| Form | Name | Status |
|---|---|---|
| 01 | 微缝 | Existing |
| 02 | 风铃 | Existing |
| 03 | 截图托盘 | User-directed third form; see [PR #51 design](third-form-screenshot-tray/README.md) |
| 04 | 折页 / Edgefolio | User-directed fourth form; [specification and prototype](fourth-fifth-desktop-forms/README.md) |
| 05 | 口袋 / Pocket | User-directed fifth form; [specification and prototype](fourth-fifth-desktop-forms/README.md) |

Forms 04 and 05 share a restrained macOS white-frosted-glass base. The base is a material treatment, not a brand-color change. Their spatial models remain materially different: Edgefolio keeps thumbnails individually exposed in stable slots; Pocket compacts them into an overlapping stack that expands on hover while preserving per-thumbnail hit targets.

All five forms must share the existing screenshot queue, asset identity, click-to-attach contract, START/UNKNOWN/failure lifecycle, archive and history. Selecting a form must not reset existing personalization. Design proposals and browser prototypes are not native AppKit verification or production approval.

## Archived studies

| Study | Scope and status |
|---|---|
| [Art direction — 留在手边 (2026-10-26)](explorations/art-direction-2026-10-26/README.md) | Teal / near-white / apricot visual direction, wordmark and R-form study; archived. |
| [Round 01](explorations/round-01/README.md) | Original spatial direction artifacts and dispositions; preserved. |
| [Round 02](explorations/round-02/README.md) | Straight-rift revision studies; preserved. |

The original Logo remains `website-assets/riftlet.svg`; brand colors remain `#19B7A4` and `#087C70`.
