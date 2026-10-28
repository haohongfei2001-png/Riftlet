# Native two-mode arrival evidence

Baseline: `1920e0562db893a3292af89a89270a26ddb46a5f` (PR #1).
Design: `0b73291652c11f5cb7b6e2792d001eb3340c988b` (PR #10), Issue #6.

`branch-heads-start.json` preserves all remote HEADs observed from the isolated
clone before implementation. `validation.json` records actual execution and
later updates for this branch; pending work must not be labeled a pass.

Original system screenshots, private chat content and prior local-Mac databases
are not part of this evidence. Native tests use generated fixtures. Physical
mouse, source-position metadata on a real capture, Retina/multiscreen appearance,
capture latency, self-inclusion, VoiceOver and actual ChatGPT upload for this
new binary are separate NOT_RUN gates. Original H/F evidence is preserved and
does not validate this increment.

The implementation note explains the new conservative metadata-build admission
gate. Ordinary execution uses static arrival until a tested build is admitted;
the opt-in candidate switch is for local geometry verification and changes no
upload policy or authority.
