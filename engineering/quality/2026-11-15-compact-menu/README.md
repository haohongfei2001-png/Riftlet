# Next-version menu and settings consolidation

Base: main `b5a412f6d37378b7cfef56e2f1e9524cc9b1ac6e` (public 1.0.2).
This increment inherits the existing released quality fixes and Sparkle updater;
it does not re-merge the stale PR100 audit branch or restart product design.

User direction on 2026-11-15:
- Slightly smaller original menu-bar Logo, retaining proportions and click area.
- Compact menu: Settings, Screenshot Library, Check for Updates, Quit.
- No everyday pause action; retain a recovery path for previously paused users.
- Settings use aligned, appropriately sized native controls and clear groups,
  inspired by the installed Saytile while preserving Riftlet colors.
- All effective preferences remain accessible; unsupported choices cannot act
  as editable controls. Existing legacy values remain readable.

Reference: installed Saytile 0.12 (373), recorded source
`a4f9f08656d1a22d2e0b6c59ad60e36452881010`: native menu, stable template icon,
grouped settings, 24pt content margins. No copied unpublished Saytile work.
Riftlet keeps its existing tested NSPopover lifecycle and reduces its content
rather than replacing target/focus handling with a new menu implementation.

Implementation:
- Original SVG mark scales 0.25 → 0.21 inside the same 18pt image canvas.
- Four 32pt action rows in a 224pt popover; same four actions in context menu.
- Update always discoverable; availability/enabled state comes from Sparkle.
- Quit delegates to the existing safe shutdown owner.
- Screenshot Library naming consistent in menu, settings, history and guide.
- Settings standalone actions stop stretching across the full content width;
  row labels expand, controls keep natural width and vertical center.
- Previously paused collection has an explicit resume action in settings;
  desktop visibility and library list/grid share their existing real owners.

Protected: screenshot/attachment execution, START/UNKNOWN, SQLite schema, media,
feedback data, Bundle identity, update feed and installed user App are unchanged.
No new release, public download, personal installation or version bump here.
Intel physical testing remains skipped by user; existing repository CI remains
unchanged. macOS13 and complete VoiceOver acceptance remain separately scoped.

Validation is recorded in DELIVERY.json when actually completed. Local XCTest
requires full Xcode (this host currently has Command Line Tools only); a failed
XCTest import is an environment failure, not a product test result. Native
programmatic review and WindowServer captures are separate from real user input.
