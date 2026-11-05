# Scoped external requirements

These do not block independent engineering work.

- BLOCKED_CREDENTIALS: actual Developer ID signing/notarization/stapling and clean-device Gatekeeper acceptance; no private certificate/key will be exported or invented.
- DECISION_REQUIRED: final settings/brand aesthetics before full visual AppKit integration; current work is nonvisual foundation only.
- DECISION_REQUIRED: retention duration, quota and permanent-delete policy. Existing data is retained.
- EXTERNAL_ACCEPTANCE: physical sleep/display hotplug, new-user TCC grant/revoke and external supported-platform matrix require appropriate real environments; simulations will be labeled separately.
- RELEASE_DECISION: public distribution, support commitments and commercial/download publication remain unapproved.

Record exact observed blockers rather than repeatedly retrying limited resources.

- LOCAL_TOOLCHAIN: this Mac has only CommandLineTools Swift 6.4, no XCTest. Complete XCTest uses existing macOS CI; standalone native probes and product builds remain available locally. No Xcode installation/user action is requested.
