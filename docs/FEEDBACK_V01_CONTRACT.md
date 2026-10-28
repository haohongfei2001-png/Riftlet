# Feedback v0.1 — minimal shared boundary (2026-10-28)

Base: PR #1 `4b7228a07a23381d3de467a44dd8490d73e26e7e`. Working branch: `codex/feedback-v01-20261028`. This is an implementation packet, not a replacement plan. Only this branch is writable; PR #1/main and real-Mac worktrees/data remain untouched. The 41-page Diagnostics/Feedback Design is a reference; current source and the user's 2026-10-28 reduced scope take precedence.

## Ownership and hooks

New paths: Sources/RiftletFeedback/**, Sources/RiftletFeedbackUI/**, Sources/RiftletFeedbackDemo/**, Tests/RiftletFeedbackTests/**, Tests/RiftletFeedbackUITests/**, services/feedback/** and packet-specific documentation/CI. The implementer is the sole writer in this branch. No parallel executor is claimed unless actually available.

Proposed shared changes, restricted to this branch: Package.swift adds isolated targets; RiftletApp gets a menu entry plus typed, nonthrowing observation hooks. No Core, QueueStore, ReceiptPolicy, Capture importer, Web/Chrome, lifecycle or SQLite v3 changes. The final integrator can take this small host diff independently; no implicit merge to the engineering branch.

`FeedbackDiagnostics.record(Fact)` accepts only closed enums and bounded numeric counters. `snapshot()` returns an immutable whitelist DTO; visibility, queue status, operation phase and admitted-start/final-completion remain separate. A swallowed UI item never supplies completion evidence. No trace dictionary, raw Error text, asset/operation/target ID, hash, path, media, browser data or clipboard is accepted. Event ingestion uses a bounded memory ring, no disk/network or unbounded Task per event. Unknown stays unknown. Coverage gaps are explicit.

`FeedbackWindowController` is an ordinary user-opened AppKit window. Menu registration returns an item named 反馈与建议…. Opening the feedback window does not retain or recreate a screenshot target. Drafts, consent snapshot and retry envelopes are separate from all screenshot databases, mode names and origins.

## Durable submission and network

One independent feedback.sqlite per app-mode directory, 0700/0600; no reuse of queue.sqlite or its writer. Human text is not evicted by diagnostic retention. Enqueue freezes text and the exact previewed optional diagnostic bytes; only a user Send creates network authority. Default diagnostic consent is off per new draft. Closing never sends. Concurrent/retried sends reuse the same report ID and secret and never mutate a frozen envelope. Failure to save is shown, never called queued/sent.

HTTPS ephemeral URLSession, no cookies/cache, no cross-host redirects or client GitHub credentials. No endpoint is shipped enabled until Cloudflare and a private destination are authorized. Isolated demo transport is visibly synthetic and cannot submit to the service. Cloud receipt means awaited D1 commit, not an in-memory promise or GitHub call.

Cloudflare receiver + D1 + scheduled GitHub delivery, no admin website. Strict schema/size allowlist on the server too; parameterized SQL; no payload/request logging. Persist one fixed-marker delivery intent before GitHub POST. Ambiguous timeout/crash enters uncertain, read-only reconciliation only, never blind second POST. At-most-one-attempt safety is not a claim of distributed exactly-once availability. Delete requests stop fresh delivery; uncertain/already-created Issues stay deletion_pending until an authorized owner confirms deletion. Retention and restore procedures must preserve tombstones.

## Validation and external prerequisites

Client/HTTP/SQL/worker tests and full existing macOS CI; independent GitHub Codex review on the packet Draft PR. Actual GUI, Cloudflare/D1 and private Issues round-trip remain NOT_RUN until executed. No resources, private repository, secrets, paid services, production endpoint, DNS, screenshot admission or safe retry are provisioned by this contract. Continue independent client/server implementation while these prerequisites are absent.
