# Renderer original-target checks

Run against an absolute path to the candidate's installed or source JavaScript resource. The runner extracts the single marked receiver function verbatim, records both hashes, and serves it without changing the loopback origin.

```sh
node Tests/OriginalDocumentDelivery/renderer/run.cjs chrome /absolute/path/to/chatgpt-web-20261027.js
node Tests/OriginalDocumentDelivery/renderer/run.cjs edge /absolute/path/to/chatgpt-web-20261027.js
```

Each run owns a fresh temporary profile, child browser process group and inherited debugging pipes. A synchronous page barrier saves the already-bound callable before changing the target. Effect counters are observed separately from permission checks. The same-URL iframe cases keep old callables in a surviving parent so they can be invoked after the replacement document becomes active; the positive control then operates on that new document. The top-level BFCache case requires restoration of the original document with a trusted persisted event. A browser that does not restore it reports NOT_RUN.

The text mutation is native textarea setRangeText, a semantic editing operation. The PNG check uses the real HTMLInputElement file accessor, reads and hashes the resulting File, and measures input/change and submit. It checks original text, selection and the existing attachment element before running the text control. These cases cover the extracted primitive on QA pages, independently of any site adapter, OS key or signed-app upload.

Use RIFTLET_CI_VISIBLE=1 only on an isolated GitHub Actions macOS runner to exercise normal WindowServer focus behavior. The default is headless. stdout is one JSON report; a failed or unexecuted case makes the process exit nonzero.
