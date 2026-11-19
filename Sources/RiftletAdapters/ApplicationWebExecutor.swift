import AppKit
import RiftletCore

/// The click chooses one host synchronously. Every later command uses only the
/// immutable lease's application identity, including read-only reconciliation.
@MainActor public final class ApplicationWebExecutor: WebClickTargetPinning {
    public static let applicationIDs: Set<String> = ["com.google.Chrome", "com.microsoft.edgemac"]
    private let executors: [String: any WebClickTargetPinning]
    private let foreground: () -> String?

    public convenience init(traceEnabled: Bool = false, diagnosticTrace: BoundedDiagnosticTrace? = nil) {
        self.init(executors: [
            "com.google.Chrome": ChromeAppleEventsExecutor(traceEnabled: traceEnabled, diagnosticTrace: diagnosticTrace),
            "com.microsoft.edgemac": EdgeAppleEventsExecutor(diagnosticTrace: diagnosticTrace)
        ], foreground: { NSWorkspace.shared.frontmostApplication?.bundleIdentifier })
    }

    init(executors: [String: any WebClickTargetPinning], foreground: @escaping () -> String?) {
        self.executors = executors
        self.foreground = foreground
    }

    public func targetForClick(program: WebPageProgram) throws -> Task<TargetLease, Error> {
        guard let application = foreground(), let executor = executors[application] else {
            throw WebAdapterError.browserNotFrontmost
        }
        let original = try executor.targetForClick(program: program)
        return Task {
            try await withTaskCancellationHandler {
                try Task.checkCancellation()
                let target = try await original.value
                try Task.checkCancellation()
                guard target.applicationID == application else { throw WebAdapterError.invalidTarget }
                return target
            } onCancel: { original.cancel() }
        }
    }

    public func execute(_ command: WebBridgeCommand, program: WebPageProgram) async throws -> Data {
        if command.action == .captureTarget {
            let original = try targetForClick(program: program)
            return try await withTaskCancellationHandler {
                try Task.checkCancellation()
                return try JSONEncoder().encode(try await original.value)
            } onCancel: { original.cancel() }
        }
        guard let application = command.target?.applicationID, let executor = executors[application] else {
            throw WebAdapterError.invalidTarget
        }
        return try await executor.execute(command, program: program)
    }
}
