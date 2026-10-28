import Foundation

/// Only explicitly enqueued reports may perform HTTP. Serial actor flight guards
/// survive reentrancy. Frozen envelopes/secrets are reused after all ambiguity.
public actor FeedbackEngine {
    public let store: FeedbackStore
    private let secrets: any FeedbackSecretStorage
    private let transport: any FeedbackTransport
    private var running = false
    private var wake: Task<Void, Never>?
    private var stopped = false
    public nonisolated let configured: Bool
    public init(store: FeedbackStore, secrets: any FeedbackSecretStorage, transport: any FeedbackTransport) {
        self.store = store; self.secrets = secrets; self.transport = transport; configured = transport.configured
    }
    public func enqueue(_ draft: FeedbackDraft, appVersion: String) async throws -> String {
        if let existing = try await store.submittedID(revision: draft.revision) { return existing }
        try await store.saveDraft(draft)
        let envelope = try FeedbackEnvelope(draft: draft, appVersion: appVersion)
        _ = try secrets.secret(for: envelope.id, create: true) // Must persist before enqueue.
        return try await store.enqueue(envelope, from: draft)
    }
    public func pump() async {
        guard configured, !running, !stopped else { return }
        running = true; wake?.cancel(); wake = nil
        defer { running = false }
        do {
            let due = try await store.records().filter {
                ($0.state == .queued || $0.state == .deletionQueued) && $0.nextAttempt <= Date()
            }.prefix(4)
            for record in due {
                guard !stopped, !Task.isCancelled else { break }
                let action: FeedbackRequest = record.state == .deletionQueued ? .delete : .submit
                do {
                    let secret = try secrets.secret(for: record.id, create: false)
                    guard try await store.beginAttempt(id: record.id, expected: record.state) else { continue }
                    let response = try await transport.perform(action, record: record, secret: secret)
                    try response.validate(for: record.id)
                    try await store.apply(response)
                } catch {
                    let blocked: Bool
                    let delay: Double
                    switch error {
                    case FeedbackFailure.rejected, FeedbackFailure.conflict, FeedbackFailure.secretUnavailable:
                        blocked = true; delay = 3600
                    case FeedbackFailure.rateLimited(let seconds): blocked = false; delay = Double(seconds)
                    default: blocked = false; delay = min(3600, 5 * pow(2, Double(min(record.attempts, 9))))
                    }
                    try? await store.reschedule(id: record.id, expected: record.state, after: delay, blocked: blocked)
                }
            }
            try await scheduleNext()
        } catch { /* Feedback failure does not escape into screenshot operations. */ }
    }
    private func scheduleNext() async throws {
        guard !stopped else { return }
        let pending = try await store.records().filter { $0.state == .queued || $0.state == .deletionQueued }
        guard let date = pending.map(\.nextAttempt).min() else { return }
        let delay = max(1, min(3600, date.timeIntervalSinceNow))
        wake = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) } catch { return }
            await self?.pump()
        }
    }
    public func refresh(id: String) async throws {
        guard configured, !running, !stopped, let record = try await store.records().first(where: { $0.id == id }) else { return }
        guard record.state != .cancelled && record.state != .deleted else { return }
        running = true; defer { running = false }
        let secret = try secrets.secret(for: id, create: false)
        let receipt = try await transport.perform(.status, record: record, secret: secret)
        try receipt.validate(for: id); try await store.apply(receipt)
    }
    public func requestDeletion(id: String) async throws {
        try await store.requestDeletion(id: id)
        await pump()
    }
    public func stop() { stopped = true; wake?.cancel(); wake = nil }
}
