# Native lifecycle regression from the first PR #44 CI

The first formal PR #44 attempt used H
`9d62cc7a1e85e92ca90c27e64277ae71795e0c27` and actual merge
`688f8ca75373edd61f92139f2dcb1955ddb0c349`. Both source-admission jobs
passed their 67 checks. Native run `42271170366` failed on ARM64 and Intel
in the same new test:
`testNaturalCloseSuspensionAndDeinitRemoveOutsideMouseObservation`.

After the third `NSStatusBarButton.performClick`, assigning the controller
owner to nil did not immediately clear its weak reference. The observer spy
had two removals instead of three. These original assertions and failures
are retained. The logs do not identify a second failing test; they do not
provide explicit per-case PASS records for every other parallel test.
Subsequent packaging/readiness/accessibility steps were skipped, not passed.

The obsolete Feedback native job was still queued with no runner or executed
step when it was cancelled, after both Native failures were known. Its source
job's success remains recorded separately. This attempt does not satisfy the
five-check gate and must never be cited as successful CI.

Private original evidence SHA-256:

| Record | SHA-256 |
| --- | --- |
| ARM64 job `128075806443` raw log | `aebb74cb719dfc1c98010ec79a2ad6d71c0b15cf3c80c0071fad21d5238c8446` |
| Intel job `128075806537` raw log | `7c8e1b315618def68ae847aa74819f821451652a7100bde4a743944326b5610e` |
| Independent failed-attempt report | `cb227daa253c313ecaf9ac9fdddcfb9a217d4c7c842222f60d8b8afa9862f83e` |

An automated review also referenced an unrelated commit `f762440` while
claiming the admission chain was missing. The actual remote PR commit list,
H's direct parent G, merge's ordered parents `[B, H]`, complete tree and both
source checks disagree with that premise. The origin of that unrelated
commit remains unknown; the original comment is retained. No actual Git
history was rewritten to satisfy it.

## Lifecycle assertion boundary

The test invokes native target-action and then checks object destruction in
the same execution turn. The ownership contract requires the controller and
its observer to be released; it does not require AppKit to finish every
temporary target/action reference before that immediate assertion. The two
failures alone do not prove either a persistent strong cycle or its absence.

The targeted correction waits, using the test suite's existing bounded
five-second asynchronous predicate, for both the weak reference to become nil
and the third monitor removal. The original nil assertion, exact removal
count, and retained late-callback checks remain. Nothing closes the popover,
clears the target, removes the notification observer or manually retires the
mouse monitor during this wait. A persistent retention or cleanup fault must
still fail. No product source or candidate binary changes for this correction.

Two private native object-code probes were attempted on the local Mac. Neither
reached its first shown-popover predicate, including a bounded second run that
explicitly activated only its own probe application. Both results are retained
as incomplete; neither supports a deallocation PASS or a specific temporary
retainer explanation. Further desktop retries were stopped. The actual failing
macOS CI environment must execute the corrected assertions and the complete
five-check pipeline before any integration or installation.

| Additional private record | SHA-256 |
| --- | --- |
| First incomplete native probe | `72d941b6d74fd6fce18ad25677ec5fd3e237d79cfc17440ca8c2ded2309df5c6` |
| Instrumented incomplete native probe | `94b6f09d2616ca0b8afb28946a8f9eded6b2f2a31bc33041c29ecf92dc1b621c` |
| Test-settlement rationale and checks | `b838e8151448a619d838260f18c1129f4f1e6934eb4c255586a06d6d4ed42140` |
