# Compiled Provider loopback fixtures

Run `Tests/Issue120Integration/run.sh` on a development Mac. To use a standalone headless binary, set `RIFTLET_HEADLESS_SHELL` to its executable. The default is the installed Chrome binary in headless mode. Each run uses an empty temporary profile, generated PNGs and a private SQLite directory. Both HTTP listeners bind to 127.0.0.1. The second ephemeral port supplies a different origin for the same-path refusal case.

The Swift driver binds the built JavaScript resource to the fixture origin and path. Its program digest follows the click through `ProviderAttachmentRuntime`, `Issue120ProviderAdapter` and the durable SQLite claim. The Gemini-shaped control uses `/app`. The Claude-shaped fixture uses `/fixture-claude-like` and its own test-authored editor, button, list and failure indicator. The fixture transport owns the synthetic draft generation and closes the page pin on in-place edits to the original editor. File assignment, card matching, hashing and duplicate fencing all use the generic Provider implementation.

The runner checks three end-to-end traces.

- Both profiles persist START for one matching new card. A page-side observer counts the native file setter, input/change order, target, original text/selection, prior attachment and sends. On the Claude-shaped page the picker is replaced before the first observation. A recheck observes the same card’s explicit failure, and another SQLite connection reads the persisted UNKNOWN and restores the original PNG for recovery.
- The third trace drops the Claude-shaped commit acknowledgement after one actual assignment and input/change. The fixture displays no matching card. Both the immediate receipt and the read after reopening SQLite remain UNKNOWN. The original invocation cannot write again.
- The Claude-shaped page also runs isolated DOM counterexamples in child documents. Replacing a document at the same URL retires the old handle and leaves the new reader unable to identify its invocation. Changing the original editor text retires the fixture transport’s draft generation, including an edit restored before observation.

Run `Tests/WebPageProgram/Issue120/check-compiled.sh --backend-only` for the separate coordinator test. It covers both fixture profiles, the explicit new selection/attempt allowed after recovery, the preserved original failure and the public Claude admission refusal. Omit the flag to include the compiled Gemini-shaped DOM regression.

These are development L2 fixture results. Native window/tab identity and draft generation are controlled here. The formal matrix requires a signed candidate, an ordinary app click and independent evidence. Claude’s authenticated draft identity, upload-control ownership, event sequence, accepted PNG and original-card failure still require real-site evidence. The historical Gemini receipt in this directory retains its original source and run scope.
