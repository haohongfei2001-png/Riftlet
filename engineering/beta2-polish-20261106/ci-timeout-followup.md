# Intel CI timeout follow-up

The first polish admission `5d096b0499db314177fbad3d011e387e17c60b76`
produced four successful jobs and one cancelled job. The cancelled Native Intel
job is **not** a passing check:

- Native run: `42224955310`, Intel job: `127915990631`, attempt 1.
- Started `2026-11-06T13:22:23Z`, completed `2026-11-06T13:42:45Z`.
- GitHub check annotation: “The job has exceeded the maximum execution time of 20m0s”.
- Full XCTest, release checks and packaging completed successfully before the
  cancellation. The actual high-contrast step was interrupted; its last motion
  capture did not finish. Later `always()` output/archival success does not turn
  the cancelled job into a pass.
- Preserved full Intel log SHA-256:
  `c6deb0db9cfeecf904bb920a34714fce68a55844890c780bd08f84f7633cc825`.

The bounded correction gives Intel 30 minutes and keeps ARM64 at 20 minutes.
No steps, assertions, required check names or source-admission rules change.
The complete five-check run must pass at the successor admission before delivery
can claim five successful checks. Its exact identities belong in the final PR
and package receipt; they were not known at this source checkpoint.

No App, runtime source, test, resource or packaging script changes in this
follow-up. The already tested `a5aefd3d166156c74399b700fa9f167e6bc2408d`
App remains the delivery binary, with SHA-256
`e0505af18b2828c3acf88477e6fbb382c975c9097b1de1a222a19e5383e36c39`.
The previous source/admission records, failed native runs and cancelled CI
remain historical evidence, not overwritten results.
