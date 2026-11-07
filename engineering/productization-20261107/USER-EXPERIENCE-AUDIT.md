# Consumer experience audit

> **合并后更新（2026-11-07）**：后续在可见的当前 Space 完成了控制中心的受控交互，以及明亮/复杂纹理两个原生视觉投影。投影中小编号的点击区实测约 7×13 点；未实测点击失败率。截图目录权限的升级差异另行记录。 [查看最终交付和证据](closeout/README.md)。以下为原始检查点。

The current desktop visual language, official logo and brand colours are unchanged. The previously accepted six-page settings and history choices remain; no design or architecture restart.

## Current complete-App evidence

[Open the original native windows/movies](native/visual/index.html), [acceptance levels and results](native/acceptance.json), [actual geometry and configured timing](native/desktop-baseline.json).

A byte-identical current Beta3 clone, real local collector/database and ten synthetic images cover onboarding, empty/1/3/10 queue, pause/hide separation, no-target click retention, AX paging, dark appearance, history selection/style synchronization, removal/restoration and ordinary exit. Production data and preferences were preserved and the formal App restored. These are scoped native observations, not web prototype passes or live attachment certification.

A guarded software mouse reached a thumbnail and one popover pause control. Ordinary status-icon and pager mouse attempts hit another process and were NOT_SENT; AX paging worked. An AX-requested popover appeared for roughly4.1seconds in continuous owned-window capture then closed. Its lifetime cause remains unresolved; this is not a claim that physical menu access, repeated open/close or VoiceOver navigation all pass.

## Objective fixes this sprint

- Release ZIP packaging now binds extracted candidate identity to the expected external manifest pin; a separately reproduced wrong-valid-ZIP case is rejected.
- Explicit version/build/label handling removes a Beta2 label from new Beta3 packaging; the installed baseline was identified as 0.3.0(3), while the maintenance candidate is explicitly 0.3.1(4).
- Native evidence export/setup failure now returns nonzero after cleanup. The original window-readiness failure remains, with honest NOT_RUN visuals.

- Committed-media recovery no longer repeats pixel decoding for byte-identical validated media. The measured 340-record improvement and independent cold-thumbnail limit are recorded [with exact boundaries](performance/RECOVERY-COST.md).
- The approved, unchanged original SVG now supplies the packaged macOS icon. [All ten native representations](icon/README.md) were decoded and compared to the original raster.

## Remaining design evidence gaps

True current-foreground desktop backgrounds, magnetic arrival, network START swallow and confirmed upload-failure rebirth were not captured this sprint. Browser access is disabled. Native synthetic projection refused an off-Space/occluded backdrop; its qualification was not weakened. Black/transparent regions in raw owned-window captures are not wallpaper trials, and recorder sampling is not App frame-rate evidence.

Configured animation durations and actual panel geometry are supplied for Pro; no subjective redesign or changed upload prerequisite is proposed. Existing native high-contrast, page/search/UUID and restart evidence stays attributable to its original run rather than counted again.

[Maintenance candidate native evidence](maintenance/README.md) adds actual 340-record history pagination and new-process startup, with unedited synthetic window captures and explicit evidence levels.
