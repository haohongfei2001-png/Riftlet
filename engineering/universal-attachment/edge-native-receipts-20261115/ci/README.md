# PR #69 exact-head CI verification

Independent read-only verification completed 2026-11-15. **All five required jobs succeeded on attempt 1. No workflow was rerun.** Full results, line-level test records, log hashes, artifact identities and scope are in [ci-verification.json](ci-verification.json).

- Reviewed source G: `fb081508d5cbe8f7a686446f99946f4f6666e5cb`, tree `ad0560439c018c575cc7883873121ac2a65087c0`.
- Admission H: `d23267fe825f9ad2384b35b03db9fe2692485741`. Its only change is the admission JSON; its parent is G and the exact 11,388-byte independent report is preserved with SHA-256 `f1a1a6b7b2cd005af458cb00031f392b35fc22c5b8cb68b49c3d61ac7dc29020`.
- Actual tested merge M: `5e07809dbcddbdfe914da8e7af75990c990bb639`, ordered parents `[b5a412f6d37378b7cfef56e2f1e9524cc9b1ac6e, d23267fe825f9ad2384b35b03db9fe2692485741]`. Its tree equals H. GitHub commit metadata and all five job logs agree.
- Final PR readback remains Draft, open and unmerged at H.

| Workflow/job | Result |
| --- | --- |
| [Native foundation](https://github.com/haohongfei2001-png/Riftlet/actions/runs/43715330247): Native source admission | success |
| Native ARM64 | success |
| Native Intel | success |
| [Feedback v0.1](https://github.com/haohongfei2001-png/Riftlet/actions/runs/43715330351): Feedback source admission | success |
| Feedback native and service | success |

Both architecture logs show actual parallel execution of all five new `EdgeCalibrationDiagnosticsTests`, within the successful 1,435-case parallel suite. The new `testUntaggedWindowDispatchRetainsIndependentAssetReceiptsAfterRefresh` also has explicit detailed XCTest PASS records: ARM64 0.029 seconds, Intel 0.059 seconds. The updated opt-in/gate case explicitly passed on both. These are controlled diagnostic/direct AppKit tests, not WindowServer or commercial upload acceptance.

Existing skips remain visible. Each architecture has an appearance-dependent history test skipped before high contrast is available, and an ordinary palette test skipped while high contrast is active. The prior conditional arrival step remains skipped; Intel's ordinary Edge and extension-free candidate steps remain conditionally skipped, as does the existing Feedback composition step. No skip was promoted to PASS.

The ARM64 ordinary App/Edge attempt is **NOT_RUN_SYSTEM_AUTOMATION_CONSENT**: one software mouse pair produced the exact original asset/window/tag/event-number receipt followed by `nativeEventFailed(-1744)` before target resolution. The original Edge lost foreground during consent; second click NOT_RUN. Operations, fixture file changes and upload starts are zero. [Extracted original record](arm64-ordinary-edge-host-from-log.json). This green CI job does not satisfy the real two-image commercial goal.

Full job logs were returned by the GitHub connector, retained without filtering and hashed as UTF-8 including the original BOM. All five artifact IDs, sizes and GitHub SHA-256 digests were cross-checked against the corresponding raw uploader-log digest. Local ZIP downloads failed through the bounded transport attempts, so the report explicitly does not claim local ZIP hash recomputation. No browser or account material was accessed by this verification.

`ci-verification.json`: 19,477 bytes, SHA-256 `ea02e798291fff5734b3b666018b238e27f2158154ceeb7ebd6c6d1049a54e69`.
