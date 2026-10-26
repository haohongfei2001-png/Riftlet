# Technical baseline (research, not a final architecture)

As of **2026-10-26** the Pro report reviewed current platform documentation and fixed-version open-source code. It **did not** test real ChatGPT attachment injection on a Mac. A separate Codex probe only demonstrated narrow local Swift/AppKit compilation and partial Chrome navigation.

## Candidate architecture
- **Mac app (Swift/AppKit):** filesystem watching, validated file import, private local screenshot copies, tiny non-activating panels, persistent FIFO queue and transaction log.
- **ChatGPT web:** Pro prefers small Chrome extension + Native Messaging host for direct composer/attachment state observation. Mac native + Chrome AppleScript/JS is an additional candidate requiring user-enabled scripting and testing. Neither path has achieved real end-to-end verified ready.
- **ChatGPT Mac (new and Classic):** possible NSPasteboard/Accessibility/event path for pasting; exact target binding and attachment-ready signal depend on actual UI/accessibility exposure and remain **NOT_TESTED**.
- **No server or model API needed** for the original function; local-first, minimal necessary permissions.

## Critical ready contract
Record image/operation/attempt IDs, target app/window/tab/document/composer identity and the attachment baseline. Distinguish INPUT_TRIGGERED, ATTACHMENT_PRESENT, READY, FAILED and UNKNOWN. A paste event, `input.files`, card appearance, disappearance of spinner, enabled send button, or lone HTTP 200 **does not prove exact attachment READY**. UNKNOWN cannot automatically be treated as FAILED, or re-upload may duplicate an already attached image.

Always preserve user text and existing attachments. Never send messages. Window switch after click must not silently retarget the image.

## Screenshot ingestion
Apple's system floating screenshot thumbnail may delay final file save; a watcher cannot receive the final file before it exists. File monitoring with readiness checks, private copy and re-scan after event loss is a viable research candidate, with actual p95 latency **not measured**. Clipboard capture should not indiscriminately collect unrelated copies.

## UI
Nonactivating AppKit panel is plausible. Real fullscreen, first click, click-through gaps, self-inclusion in screenshot and multiple monitors need hands-on validation. The Pro review's dimensional and latency parameters are **unverified targets**.

Sources and limitations: [Pro full reply](../research/PRO_REVIEW_REPLY_2026-10-26.md), [23-page PDF text](../research/PRO_REVIEW_PDF_TEXT_2026-10-26.txt), [Codex probe](../research/CODEX_EXPERIMENT_STATUS_2026-10-26.md).
