# Historical root-monitor compatibility: independent review constraints

Status: scoped independent source review PASS; current-page 83 plus legacy 61 VM tests passed (144/144). Native compilation/CI and real browser acceptance are separate root-owned checks, not established by this review. Reviewer `late_failure` did not run Chrome, GUI, live DB, capture or input. The implementation belongs to `web_safety`; this document is not permission to clear historical state or enable production.

## Frozen public sources

- v10: commit `0659e1cc603b1963367a2ba3a032414eeb5ad2ed`, page resource `Sources/RiftletAdapters/Resources/chatgpt-web-20261027.js`; the historical fixture is byte-for-byte identical, SHA256 `c41476f2adcbe6c267a2ef4fadc9b606539460bde8334407215f67c1bbd82bc3`.
- v12: commit `7878de3138d1c140369c3cfbe69a28dd2770294c`, same path; also byte-for-byte identical at `ee1d960adf67432be627e86e7aa9350e5d85d9c0`, which supplies the added frozen v12 fixture. SHA256 `622895461443c813f6827fc5efb3c65bab0e407b5a2d8fcd06970aa87be2184a`.
- The 4,005-byte block starting with the two-space-indented `function rootMonitor` and ending before the next `function install` is identical: SHA256 `855731a3b1f3cfe45a634d0765f007d1879d40fcfc1f33cc3c152fa48b61d043`.
- `readThreadBinding` and the `checkBinding` closure are also byte-identical in those frozen sources. This comparison does not approve other versions merely because they expose similarly named methods.

## What the existing monitor actually guarantees

The original monitor owns one `root.current` accessor pair and retains the most recent assigned tree. Its setter first preserves that value, then runs each live group's check. A failed group invalidates every lease registered in that group. A thrown check or reentrant commit disqualifies the whole monitor. `intact()` checks the exact installed getter/setter and descriptor flags; descriptor loss is a permanent tombstone. `stop()` disqualifies all groups and restores only its own descriptor, using the latest value rather than the original tree.

`bind` groups by its first argument, currently the real form. If editor, input, route and logical identity are unchanged, it adds another invalidation callback but **keeps the first group's check closure**. That old closure currently checks structural form/editor/input/root membership, route and exact logical identity. It does not consult its generation's `invalid`, `inputRevoked`, `valid()` or `monitorAlive()` flags. Thus ordinary same-ID typing and focus rearming do not inherently make its structural predicate stale. However, blindly sharing that closure with a different implementation would assume all future predicates are equivalent. Function names or matching current business IDs are insufficient proof of that assumption.

`revokeInput()` and `invalidate()` are deliberately different. Focus/visibility revocation can retire input while preserving original attachment observation. Root/group invalidation sets the generation invalid and clears every operation's `proof` and staged file data. Calling `stopRootMonitors()` to obtain an ordinary writable descriptor would therefore destroy the continuity needed to observe old UNKNOWN/completed operations and correlated late errors. It is not an acceptable compatibility or cleanup step.

The v10 NodeList callback defect also remains historical: sharing a root observer cannot repair its old mutation callback, reconstruct missed final progress, or manufacture a final proof. The existing legacy reader continues exact-original-operation schema-1 observation through the original callbacks only.

## Minimal compatible implementation constraints

The implementation follows these reviewed invariants:

1. Admit only one explicitly frozen v10 or v12 owner, for the exact same current React root. Check its nonwritable/nonconfigurable registry property, bounded acyclic generation chain and real Map, owner function/accessor structure, original installed descriptor and `intact()` result. Unknown accessors, ambiguous/multiple owners, stopped/lost descriptors and unproven registries refuse. No replacement setter or descriptor restoration is involved.
2. Keep the historical registry, state chain, operation maps, callbacks, identities and proofs. New input must use a new current-version lease and current validation. No historical operation is migrated, resubmitted, given schema-2 start evidence or granted new input authority.
3. Do not pass the real form as the borrowed group's key. A private per-real-form token isolates the new implementation's group from the original form group. The real form/editor/input/root/route/business identity remain explicit inputs to the new structural predicate. The old monitor uses that key only for grouping; it performs no DOM operation on the key.
4. Keep one token for each form within the borrower, and retain its tombstone. Repeated focus rearming must not allocate a new group each time. A changed binding invalidates the prior new group; returning A after A→B→A never revives the old group or lease. Each freshly installed lease still immediately runs its own `checkBinding` and checks monitor liveness.
5. **Catch all exceptions in the new check callback before returning to the old setter.** Return false and retire only the new group. Otherwise one new implementation exception reaches the historical setter's global `CHECK_FAILED` path and erases old proofs. New invalidation callbacks similarly must not throw into the owner.
6. Borrower stop is local: permanently retire only borrower-owned groups/states, never call the owner's stop. Owner stop or actual descriptor loss still legitimately invalidates both old and new observation. No stopped borrower is recreated by deleting its map entry or minting another token.
7. Bound registrations, not just roots. The old source bounds each registry to 32 generations and four monitors. The proposed scope is one admitted v10 or v12 owner plus one current borrower registry, with at most 32 old and 32 new per-generation/form registrations overall; normal same-form rearming should cost two checks per commit (one old group and one new group), not grow per generation. Future borrower versions require an explicit combined-capacity review.
8. Do not overstate source attestation. Known function text and object/descriptor checks reject ordinary malformed or spoofed objects; they do not cryptographically authenticate arbitrary closures in a fully hostile MAIN world. A forged closure can share source text while capturing other bindings. In particular, deliberately swapping a genuine monitor from another root into the historical Map can pass function-source checks while binding new notifications to the wrong root. The historical ABI exposes no immutable accessor/root identity that a pure reader can authenticate. This is an explicit unsupported same-world-registry-tampering case, not a rejected negative case. It does not arise through the unchanged historical implementation; no setter probe or global monkey-patch is added to infer its closure bindings. This is a narrow compatibility profile under the existing page trust model, not new protection against arbitrary same-world tampering.

## Reviewed regression expectations

- Real frozen v10 and v12 installation followed by the new program on the same fixture/root succeeds without replacing getter/setter, registry, state functions, operation object, original proof or attachment identity.
- Same-ID normal commits and repeated blur/rearm keep old read-only observation alive, keep new valid input scoped to its own generation, and show bounded group/check counts.
- Two genuine root setter commits A→B→A invalidate every old A lease and the new A lease permanently; subsequent fresh capture has a different generation.
- New callback exception invalidates only new participation; the old owner remains intact and its existing proof/late-error reader remains usable. Reentrant root mutation remains fail-closed without throwing into React or rolling back the latest tree.
- Local borrower stop retains old observation/proof; explicit owner stop or descriptor replacement permanently invalidates both; no restore/reinstall path revives them.
- Wrong version, forged/incomplete monitor functions, plain unknown accessor, root without an admitted owner, multiple owners, cyclic/oversized generation chain, getter-valued metadata and capacity exhaustion refuse before new registration/input.
- Existing v10 final proof and correlated late error remain exact-original schema-1 observations with input count unchanged. The old v10 NodeList failure still yields unknown without rewriting its closure or progress history.
- New proof cannot change/remove an old attachment or be returned for an old target/operation. Unknown operations retain original identity and are never retried through the new lease.
- Preserve the existing explicit unsupported ABA fixture: a transient business transition that bypasses root assignment, DOM mutation and Navigation events cannot be inferred from the final A snapshot. Compatibility must not relabel this existing limitation as solved.

## Scope

This approach can fix the measured cross-version instrumentation conflict while preserving the original accessor and observations. It does not make an ACK exist before a cold click, establish continuously observed business identity for every real ChatGPT transition, prove final upload completion, or enable production/retry. Final review must be against the author's actual source and test result; real Mac validation belongs to the root runtime owner.

## Adjacent independent checks

The root-owned v12 legacy route was independently reviewed: frozen v12 source matches the stated commit/hash, observations remain schema 1 through original closures, input-side wrapper actions use the current program, and the full original operation/target identity remains required. Swift public source ID changes to v13 while the wrapper preserves it and forwards the 256-KiB maximum current chunk size. Current page and legacy resources total approximately 57 KiB, under the existing 128-KiB guard. No new production start, completion or retry profile is admitted.

The helper-only double replacement probe was also reviewed without GUI execution. It posts at most two paired software down/up events, verifies first selection before synthetic display-only removal, checks replacement geometry/window and actual event timing/count, and requires zero acceptance/selection on the replacement. Its supplied CGEvent click-state 2 is not hardware/WindowServer double-click classification; physical and cross-application focus acceptance remain NOT_RUN.

## Final non-author review result

The reviewer independently ran `node --test --test-reporter=dot Tests/WebPageProgram/acceptance-program.test.cjs Tests/WebPageProgram/legacy-web-observe.test.cjs`: 144/144 passed (83 page, 61 legacy). Reviewed current resource SHA256: `903d6d0b2c13b6b2d10a6eb585f84afabaf8a10fe0047cbd4ac1661812c27988`. The historical owned-monitor body remains byte-identical after normalizing only its local function name. No production source was edited by this reviewer.

Final changes close the normal cross-version upgrade regression for both explicitly frozen v10 and v12 owners. The tests exercise real historical installation, independent new single-input/final-proof flow, retained original proof and correlated late error after local borrower stop, ordinary typing/rearm, observed setter ABA, invalidation, malformed owners and unknown getter-valued diagnostics (zero getter calls). The unchanged legacy suite continues to preserve the v10 NodeList limitation. No current-version input can reuse the historical target.

Two explicit unsupported fixtures are intentionally passing as **limitation assertions**, not security acceptance: unobserved business ABA that bypasses all available observations; and deliberate authentic cross-root monitor substitution inside a corrupted MAIN-world registry. The latter cannot be authenticated using the old ABI's function text and Map alone. This scoped review accepts the existing untampered same-world-registry assumption for development evidence; it does not establish adversarial MAIN-world integrity or any production profile. Bounds are enforced in source and inherited generation-limit coverage; this review does not claim an exhaustive adversarial object/proxy or combined-capacity fuzz test.

No blocking source defect remains within that declared scope. Root-owned live testing must separately establish that the actual retained observer is compatible and the old original operation identities/proofs remain observable; no cold-first-click, physical-input, universal ABA or whole-product PASS follows from these tests.
