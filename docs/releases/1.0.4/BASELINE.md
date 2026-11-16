# Riftlet 1.0.4 — frozen audit baseline

Audit date: 2026-11-17 Asia/Shanghai. This is a planning increment, not application implementation or release approval.

| Identity | Verified value |
| --- | --- |
| Planning base B / main | `3f8149e2313fd81bbaee5a7bbbdbb1efca2fc81b` |
| Main tree | `05d7edc568ae287de91f018ed6d71189025e35b3` |
| 1.0.3 release source G | `7bc10b2e6ef9b7e684353d33c3499ce94282b0c6` |
| PR #103 head H | `66294e1d52160b3af49fb1a5c20a804f7009c3e1` |
| PR #103 merge / v1.0.3-zip target | `189782dd943f5215da43539b30db27e482a78b3c` |
| App version / build / ID | `1.0.3` / `25` / `com.riftlet.app` |
| Sources subtree, both release and B | `aaa25b8bb56e9f230ebc2fc289e90f3acd2e8c83` |
| Resources subtree, both release and B | `476042f2d90f3d9658cd47541acdc21ae54281db` |
| ZIP, directly downloaded and hashed this audit | `Riftlet-1.0.3.zip`, 10,483,530 bytes |
| ZIP SHA-256 | `b9814f1df2fa44a8ae1aef3f491ea76fabbc9ff67ac1c0db41cbb55ed18aa836` |
| Live website | Byte-identical to B `index.html`; directs to the above ZIP |
| Live website SHA-256 | `087fcfd01e45560413d422fab32919514d38a5ea83f0a65904fc391516e400bf` |
| Live stable feed | `https://riftlet.com/updates/stable.xml`, latest item 1.0.2 |
| Live stable feed SHA-256 | `8d08d90e7877d5701f863c66f4c7bb50eb2993076bfd1e9b3d29e81239776b1e` |

Release facts: [PR #103](https://github.com/haohongfei2001-png/Riftlet/pull/103) and [PR #105](https://github.com/haohongfei2001-png/Riftlet/pull/105) are merged. [v1.0.3-zip](https://github.com/haohongfei2001-png/Riftlet/releases/tag/v1.0.3-zip) is published, stable, and immutable. The ZIP contains the Developer ID app reported notarized and stapled in #103. The separate outer DMG submission was still In Progress in that release record; no public 1.0.3 DMG or 1.0.3 stable feed item was present at this audit snapshot. Apple notarization is not Mac App Store App Review.

Read-only verification here must not be represented as a fresh signed-install/upgrade test. Exact native evidence and its provenance are recorded separately. Repository issue titles, dated queue counts, CI green status and older screenshots do not override current source or establish current binary behavior.

All 1.0.3 artifacts, immutable tags, signing identities, public website/download and signed stable feed are frozen for this work. Develop 1.0.4 on a separate branch from B with this planning increment; if main changes, compare and record the delta before integration. Do not merge stale PR #100 or open expansion candidates as a substitute for that base. This planning delivery does not modify app code, production data or installed apps.

Remote governance readback: main reports `protected:false`, repository rulesets `[]`. Existing five formal checks and B→G→H admission still apply; their existence is not remote branch protection. PR #103's automated Codex review reports an incomplete/failed review because its review usage limit was reached. This is neither an independent approval nor a proven source defect. Preserve the existing separately recorded source review.
