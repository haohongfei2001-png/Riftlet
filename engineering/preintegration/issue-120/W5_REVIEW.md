# Independent review of W5 formal result import

Decision: PASS for W5 result import at 7e4a506f035f8457a0f83a89dd8fa24de9740f13.

Scope: formal evidence retrieval, receipt processing, per-variant decisions, and operational boundaries. No browser or service acceptance was run by this review.

- Independently reproduced the old behavior: the default matrix always contained 40 combinations, 16 core, and zero core L3 passes, and previously had no ingestion path for complete signed evidence.
- On synthetic, content-addressed evidence, exercised one complete Chrome/ChatGPT variant. Independently computed its L3 PASS and eligibility for review while the overall 16-cell decision remained PARTIAL. The release enablement flag stayed off.
- Replayed the same valid variant with one attributable L3 failure, environment block, technical block, and unknown result in four separate tests. Each reduced the core count to zero and removed eligibility. A failing shared package/upgrade or host once-input observation also removed review eligibility even when L3 was otherwise complete. Tested source/review product-tree equivalence and a mismatch involving one product file.
- Reviewed GitHub-side selection of the formal #122 main base and its exact admission-only child, the independently reviewed frozen source and signed candidate identity, #119 merge ancestry, new build, product tree, fixed evidence index, and candidate identity. Raw receipt digests, one-pass batch validation and matching site/program/variant boundaries precede aggregation. A native positive cannot be supplied solely by filling a summary status. Without a direct unique input observation a matched live receipt stays UNKNOWN for promotion.
- The computed decision identifies eligibility for a separate release review. Actual W0/W8 authorization, observed site behavior and final product distribution remain distinct. On the actual current #122 comparison base, invoking the formal CLI refused before reading any claimed local package or observation. Rendering the checked-in fixture set still yields 0/16 L3 and enables no cell.

Replayed all 17 frozen matrix tests in an independent checkout. Compared the generated default result with the checked-in results file. The real #122 comparison branch refused formal evidence import. The signed-package reader uses a canonical temporary mount path; the implementation owner verified the reader with old build 53. This review reused that scoped historical-package observation and did not remount the image.
