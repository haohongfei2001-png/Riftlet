# Historical observer fixtures

These are byte-for-byte public repository page sources, used only to test read-only compatibility with retained original closures:

- `v6.js`: commit `fff0e8c090f125211b35a56e7a16abef61109fb1`, `Sources/RiftletAdapters/Resources/chatgpt-web-20261027.js`.
- `v7.js`: commit `a441c70f3c4071069bd594513ecf16600bbb0ab8`, the same source path.
- `v8.js`: commit `c9c68a66c4b6ff55ffe8048cff6f1cf781600519`, the same source path. `v8-dom-fixture.cjs` retains that commit's synthetic DOM helper for the original availability checks.

SHA-256: `v6.js` = `956c138cb79e5b3905687b1d7ce126281ee097c6d0f897b8cafcc6391ab8a8f5`; `v7.js` = `f8980e524cc62f4fd913d54e9fbe3855c4112737b7f503f9229f215ccd4dfb9a`.
`v8.js` = `01098ef810dd0fdbdb982e4fe56fa3da362b8f359687892de6ca7866afc411f6`.

They are test resources, not fallback input programs. The application bundles only the small read-only compatibility observer. These synthetic tests establish no new live ChatGPT or physical interaction admission.

All historical observations remain schema 1. Their original completion/late-error proof may continue to be read, but none may mint schema-2 uploadStarted evidence, rewrite old identity or regain input authority.
