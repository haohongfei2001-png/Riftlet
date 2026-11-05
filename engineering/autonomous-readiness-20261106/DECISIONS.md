# Decisions

- Preserve accepted Beta `personal-beta.1+004741f`; engineering builds remain separate and uninstalled.
- Preserve v1 prototype and all failed evidence; revision 2 has its own files, hashes and runs. No visual AppKit integration until design approval.
- Share one main-based engineering worktree with exclusive path ownership. Root owns integration, shared source/Package/CI and refs; contributors do not commit concurrently.
- Storage backup must prove quiescence/consistency; a live filesystem copy is not a verified backup. Restore only to a separate empty destination.
- Release preparation may be tested offline, but Developer ID, notarization and Gatekeeper acceptance require actual credentials/artifacts and remain separate.
- No automatic data deletion, remote upload, auto-update feed or new attachment permission gates.
