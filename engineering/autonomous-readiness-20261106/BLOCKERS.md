# Scoped external requirements and decisions

These are the remaining externally dependent steps, not reasons to stop independent source work or add attachment gates.

| Item | Facts / required decision | Recommendation and effect of deferral |
| --- | --- | --- |
| Developer ID / notarization | No credential supplied or used in this increment; signing, Accepted ticket, staple and clean-device Gatekeeper are NOT_RUN. | An authorized maintainer provides an existing signing identity/team and notary profile at release time. Keep current private Beta; PREPARED/ad-hoc CI packages are not public installers. Never export private keys. |
| Final settings aesthetics | V2 keeps six pages/Quiet Edge and passes browser interactions; native visual integration has not happened. | Review existing complete HTML, not a new information architecture. Accept or specify the remaining typography/density/brand adjustments before AppKit visual implementation. Nonvisual owners are ready for that work. |
| Retention / permanent deletion | Original screenshots, private media and historical UNKNOWN currently persist. Queue clearing is not disk cleanup. | Retain current data-preserving behavior until explicit duration/quota/delete interaction decisions. Storage growth remains visible and documented; no automatic deletion is introduced. |
| Physical / new-user acceptance | Sleep/display hotplug, fresh TCC grant/revoke, clean-device first install and actual release update require appropriate environments. | Execute the small scoped matrix in EXTERNAL_BETA_ACCEPTANCE on a signed candidate. Synthetic and read-only process evidence do not certify these cases. No repeat founder five-image experiment. |
| Supported public platforms | Swift deployment target macOS13 and CI ARM/Intel are engineering facts; accepted real ChatGPT evidence has a narrower exact environment. | Start external support commitments from verified macOS/Chrome/ChatGPT combinations and expand only with evidence; do not advertise every deployment-target configuration as certified. |
| Public distribution / website / commercial choices | Public release and new download publication remain unapproved. Existing website visuals are untouched. | Use WEBSITE_RELEASE_INTEGRATION only after explicit distribution/version/platform decision. No public feed, Sparkle update endpoint, purchase or paid plan change. |

## Environment constraints

Local Swift6.4 CommandLineTools has no XCTest. The existing full macOS CI is the executor; no Xcode installation or user action is requested. Product/native module builds and isolated native probes are available locally. Missing local XCTest is not a passed test, nor a reason to replace its assertions.

The running production root refused offline health inspection with `source-in-use`; do not stop the user's App merely to obtain a result. Use the documented tool during a separately authorized, naturally quiescent maintenance interval. The refusal itself confirms only lock handling.

No current request authorizes main merge, visual UI replacement, installation of this development candidate or public release. A technical non-author review is recorded separately from a real eligible GitHub human approval and remotely enforced branch protection.
