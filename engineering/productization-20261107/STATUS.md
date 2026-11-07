# Current status

Baseline main: `2e779f646ac4874344fac94f79103e8ddf9b02c8`. Formal installed App remains Personal Beta3 **0.3.0(3)** ARM64, binary `fe5b09c4146a363e45685f8441d081fbd62a3238ed83b115287882b9158e29f3`. The request’s Beta2 installed-version line was stale. PR45 integration, the previous five-check main CI and safe Beta3 upgrade were verified before this sprint; no second upgrade was needed.

The current complete-App clone was byte/mode identical to the formal App. It completed scoped native collection and 0/1/3/10 queue, pause/hide, no-target retention, history style/selection and reversible synthetic queue actions. Production data snapshots before/after isolated GUI have identical paths, bytes and typed database rows; a fresh private restore drill passed. The formal App was normally restarted at the same identity. See [native results](native/acceptance.json).

The isolated real ServiceManagement probe passed seven lifecycle stages, including fresh-process reads and a same-path version-only ad-hoc re-sign. This does not certify production login registration or actual logout/login. Existing PR44 code already implements the repair; no new login defect was shown.

Release engineering now requires an explicit Beta label and binds both review/formal ZIP contents to the external candidate manifest pin. A native evidence-helper error now returns failure after cleanup instead of reporting exit0. The underlying off-Space positive-timeline limitation remains. The official SVG-to-ICNS packaging increment, one-hour high-resolution run and bounded actual disk-full recovery are still in progress at this checkpoint.

Consumer install/privacy/recovery/support guides and the 10–20-person closed Beta protocol are source-audited. No participants were invited. Local signing identities and same-repository cloud signing routes are absent; current ad-hoc App fails external trust assessment as expected. No security override was applied.

Current productization result: **IN_PROGRESS**. Prior `PERSONAL_BETA_3_ACCEPTED` covered PR45 integration/upgrade. This sprint’s expanded A criterion additionally requires current-version real attachment evidence, which is not inferred from that earlier narrow conclusion. Browser inventory returned `Local browser use is disabled in Work settings`; no alternative-interface bypass was used. Native status-item physical/mouse paths remain partial. See [separate readiness levels](RELEASE-READINESS.md) and [scoped blockers](BLOCKERS.md).
