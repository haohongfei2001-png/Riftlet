# Historical observer fixtures

These are byte-for-byte public repository page sources, used only to test read-only compatibility with retained original closures:

- `v6.js`: commit `fff0e8c090f125211b35a56e7a16abef61109fb1`, `Sources/RiftletAdapters/Resources/chatgpt-web-20261027.js`.
- `v7.js`: commit `a441c70f3c4071069bd594513ecf16600bbb0ab8`, the same source path.
- `v8.js`: commit `c9c68a66c4b6ff55ffe8048cff6f1cf781600519`, the same source path. `v8-dom-fixture.cjs` retains that commit's synthetic DOM helper for the original availability checks.

SHA-256: `v6.js` = `956c138cb79e5b3905687b1d7ce126281ee097c6d0f897b8cafcc6391ab8a8f5`; `v7.js` = `f8980e524cc62f4fd913d54e9fbe3855c4112737b7f503f9229f215ccd4dfb9a`.
`v8.js` = `01098ef810dd0fdbdb982e4fe56fa3da362b8f359687892de6ca7866afc411f6`.

They are test resources, not fallback input programs. The application bundles only the small read-only compatibility observer. These synthetic tests establish no new live ChatGPT or physical interaction admission.

All historical observations remain schema 1. Their original completion/late-error proof may continue to be read, but none may mint schema-2 uploadStarted evidence, rewrite old identity or regain input authority.

- `v9.js`: exact commit `1f9dec2dec9cf6ef61f36776a6e4f7c3439f4f8a`, same public page source; SHA-256 `a79216b283fb8a32ab76fd177dd0fab371f011c8067cc6984e8028424057ef43`. `v9-dom-fixture.cjs` retains the round5 synthetic DOM helper, adding a null initial-progress option to represent a missing `aria-valuenow`. Original v9 start evidence is never copied: retained operations are read through their original closures and normalized to schema 1, including original final proof and late error only.

- `v10.js`: exact commit `0659e1cc603b1963367a2ba3a032414eeb5ad2ed`, same public page source; SHA-256 `c41476f2adcbe6c267a2ef4fadc9b606539460bde8334407215f67c1bbd82bc3`. `v10-dom-fixture.cjs` retains that commit's synthetic helper. The historical NodeList callback defect is deliberately not patched: callback failure yields unknown; no hundred-percent or final proof is reconstructed. Existing valid original proofs remain readable.

- `v11.js`: exact commit `53ebcc4da4b0df508edc11f6ead9ea4d8a843dad`, same public page source; SHA-256 `d284e10e5b3bf060066c3acdafa80e138772407520753a448c47f8bd3650f9d4`. `v11-dom-fixture.cjs` retains that commit's NodeList-like synthetic helper. The original v11 event closures may continue final proof and late-error observation; compatibility output remains schema 1 with no start or input authority.
