# Independent review of the 1.0.7 baseline gate

Decision: PASS for the inspected W0 verifier and build 53 package identity. Product acceptance remains blocked. This review did not exercise a signed-in draft, grant permission to merge #119, or approve a public release.

## What was independently checked

- Reproduced the pre-fix false positive in 4daab3f with a synthetic merged PR, correct ancestry, no CI checks and G1/G2/G4 explicitly NOT_RUN. The former script returned REVIEW_MERGED_107_ACCEPTANCE.
- Queried GitHub for the current PR, both official workflow runs and their five successful jobs. Native run 44668259735 and Feedback run 44668259741 are pull_request runs on c7642464 for #119. Exercised verify_checks against the live records.
- Verified that product 0dc6780a, review f7287e05 and source admission c7642464 form the expected parent chain, that the review-only delta contains release documentation, and that the embedded review digest is 26954f872d3d43459c91473477f842174a49d25e86d30a6460fe6011981555ce. Exercised verify_source using those real upstream objects and an illustrative post-merge tree; the PR itself is still unmerged.
- Exercised verify_package against the original release workspace. Its first run found that a genuine notarized image was rejected when hdiutil canonicalized the temporary mount path. After the path fix, the current record validated the signed and stapled build 53 image, embedded App and Gatekeeper assessments. DMG SHA-256 9458479641bde6147de37fda8b873507b2a312a153a76c08e166e50903583dee. Signed App SHA-256 1f5fe8af25e6e64b9c64204297aa4f578c44bc3f6e795ab95effc577e536ad6a, using the canonical root-relative inventory of the App.
- Inspected the separate native/observer inputs, evidence-admission report and mandatory original-artifact digests. The trust boundary is the admitted independent review of the link between the original observations and the public measurements. Repeated a positive synthetic G1 fixture and seven independent mutations covering mixed build, mismatched payload, repeated card, boolean count, simultaneous pair, copied observations and changed target; each invalid mutation was rejected. Checked correction of cold-first, unique UI captures and failed/retried operation identities. All 13 checked-in W0 regressions passed, including rejection of a changed reviewed DMG hash and a mismatched App manifest.
- Verified the actual GitHub product tree against itself and the incompatible public baseline; the changed product was rejected. The live top-level gate returned WAITING_FOR_107_BASELINE because #119 is unmerged. No actual G1/G2/G4 results or public download changes follow from this review.

Final delta review confirmed the recorded CI conclusion is checked alongside the live job result, and that a positive decision rereads the PR head, merge commit and main after clearing the API cache. Replayed the extracted App manifest verifier against the original release manifest. Reviewed the extension to three or more rapid pairs. Every additional pair must have both members and pass the original timing, target and session checks. Extra single attachments are subject to the same per-image identity, receipt and uniqueness checks. The earlier real mounted-image verification applies to the unchanged bytes and inventory algorithm.

## Reviewed content SHA-256

| File | Digest |
| --- | --- |
| baseline.py | 4b22c9adc5d4cd07786a4ab2bcfb7b6d4aa02bfa0ad8db042c3f049855de532c |
| gate107.py | 28e6fd96ea119b3298945d2ee495ade17e75306d6b1a4de8cfe7479768dbfeab |
| tests/test_baseline.py | 62b6b3ecba1f8a539d5b5f721ad8af4d6d5f5854ec0dcd28e9b9250985840d47 |
| 107-admission.json | 8762e3333ee1f20f496008b5918371d35315367da2fcbaac78b365cbd44eb3d2 |
