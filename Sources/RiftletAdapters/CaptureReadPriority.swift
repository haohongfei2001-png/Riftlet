import Foundation

/// Cancels only replaceable target discovery, never an input or an original
/// operation observation. The existing transport queue remains serial.
final class CaptureReadPriority: @unchecked Sendable {
    private let lock = NSLock()
    private var generation = UUID()

    struct Ticket: Sendable {
        fileprivate let owner: CaptureReadPriority
        fileprivate let generation: UUID

        func check() throws {
            try whileCurrent {}
        }

        /// Publication is atomic with supersession. No Apple Event or wait may
        /// run inside this body; only a small local cache write is permitted.
        func whileCurrent<T>(_ body: () throws -> T) throws -> T {
            owner.lock.lock(); defer { owner.lock.unlock() }
            guard owner.generation == generation else { throw WebAdapterError.captureSuperseded }
            return try body()
        }
    }

    func ticket() -> Ticket {
        lock.lock(); defer { lock.unlock() }
        return Ticket(owner: self, generation: generation)
    }

    func supersede() {
        lock.lock(); defer { lock.unlock() }
        generation = UUID()
    }
}
