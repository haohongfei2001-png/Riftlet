import CryptoKit
import Darwin
import Foundation
import XCTest
import RiftletCore
@testable import RiftletAdapters

final class MacClipboardCoordinatorTests: XCTestCase {
    private var root: URL!
    private var scope: URL { root.appendingPathComponent("shared-clipboard") }
    private let profileID = "mac-coordination-synthetic-v1"

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("riftlet-coordination-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    private func request() async throws -> TransferRequest {
        let bytes = Data("synthetic byte-identity fixture, not codec validation".utf8)
        let file = root.appendingPathComponent("\(UUID()).png")
        try bytes.write(to: file)
        let asset = ImportedAsset(sourceKey: UUID().uuidString, fileName: file.lastPathComponent,
            sha256: SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(),
            byteCount: Int64(bytes.count), pixelWidth: 1, pixelHeight: 1, mediaType: "image/png", origin: .synthetic)
        let launch = Date(timeIntervalSince1970: 1_000)
        let target = TargetLease(adapterID: "mac-coordination", surface: .macChat, applicationID: "fixture.mac",
            sessionID: MacTargetSession.sessionID(processID: 12, launchedAt: launch), windowID: "window",
            documentID: "document", composerID: "composer", draftGeneration: "1")
        let store = try QueueStore(databaseURL: root.appendingPathComponent("\(UUID()).sqlite"))
        _ = try await store.importAsset(asset)
        let operation = try await store.prepare(assetID: asset.id, target: target)
        try await store.markDispatchIntent(operation.id)
        let saved = try await store.operation(id: operation.id)
        return TransferRequest(operation: try XCTUnwrap(saved), asset: asset, fileURL: file)
    }

    @discardableResult
    private func prepareInput(_ coordinator: MacClipboardCoordinator, _ request: TransferRequest) throws -> ClipboardOwnerState {
        try coordinator.reserve(request)
        try coordinator.markClipboardWriteIntent(for: request)
        let payload = try ClipboardAttachmentPayload(request: request)
        let owner = ClipboardOwnerState(changeCount: 17, marker: payload.marker)
        try coordinator.clipboardWritten(for: request, owner: owner)
        try coordinator.markInputIntent(for: request, owner: owner)
        return owner
    }

    private func receipt(_ request: TransferRequest, failure: Bool = false) -> TransferReceipt {
        TransferReceipt(operationID: request.operation.id, assetID: request.asset.id,
            attempt: request.operation.attempt, assetSHA256: request.asset.sha256, target: request.operation.target,
            outcome: failure ? .definitiveFailure : .verifiedReady, profileID: profileID,
            attachmentID: failure ? nil : "synthetic-own-attachment", positiveReady: !failure,
            belongsToOriginalDraft: true, hasError: failure, safeToRetry: failure)
    }

    func testActualLockExcludesAnotherInstanceAndASeparateProcessUntilRelease() async throws {
        let item = try await request()
        let first = try MacClipboardCoordinator(directoryURL: scope)
        let second = try MacClipboardCoordinator(directoryURL: scope)
        try first.reserve(item)
        XCTAssertFalse(try second.canReserve())
        XCTAssertThrowsError(try second.reserve(item)) { XCTAssertEqual($0 as? MacClipboardCoordinationError, .busy) }
        XCTAssertEqual(try probeLockInSeparateProcess(), 23)
        try first.cancelBeforeClipboardMutation(item)
        XCTAssertTrue(try second.canReserve())
        XCTAssertEqual(try probeLockInSeparateProcess(), 0)
        XCTAssertThrowsError(try second.reserve(item)) {
            XCTAssertEqual($0 as? MacClipboardCoordinationError, .duplicateOperation)
        }
    }

    func testRestartKeepsInputIntentAndNeverAuthorizesAnotherPaste() async throws {
        let item = try await request()
        var first: MacClipboardCoordinator? = try MacClipboardCoordinator(directoryURL: scope)
        let owner = try prepareInput(try XCTUnwrap(first), item)
        first = nil // Actual FD close/unlock; persistent journal remains.
        let reopened = try MacClipboardCoordinator(directoryURL: scope)
        XCTAssertFalse(try reopened.canReserve())
        XCTAssertEqual(try reopened.recoverForObservation(item).phase, .inputIntent)
        XCTAssertThrowsError(try reopened.markInputIntent(for: item, owner: owner)) {
            XCTAssertEqual($0 as? MacClipboardCoordinationError, .invalidTransition)
        }
        let other = try await request()
        XCTAssertThrowsError(try reopened.recoverForObservation(other)) {
            XCTAssertEqual($0 as? MacClipboardCoordinationError, .busy)
        }
        XCTAssertThrowsError(try reopened.cancelBeforeClipboardMutation(item))
        XCTAssertNil(try reopened.authorizeSettlement(receipt(item), request: item, policy: .init()))
    }

    func testRecoveredPrewriteReservationCancelsOnlyItselfWithoutReplaying() async throws {
        let item = try await request()
        var first: MacClipboardCoordinator? = try MacClipboardCoordinator(directoryURL: scope)
        try first?.reserve(item); first = nil
        let reopened = try MacClipboardCoordinator(directoryURL: scope)
        XCTAssertEqual(try reopened.recoverForObservation(item).phase, .cancelled)
        XCTAssertTrue(try reopened.canReserve())
        XCTAssertThrowsError(try reopened.reserve(item))
        let other = try await request()
        try reopened.reserve(other)
        try reopened.cancelBeforeClipboardMutation(other)
    }

    func testWriteIntentAndOwnedButUnprovedClipboardStayConservativeAfterRestart() async throws {
        for written in [false, true] {
            let item = try await request()
            let directory = root.appendingPathComponent(UUID().uuidString)
            var first: MacClipboardCoordinator? = try MacClipboardCoordinator(directoryURL: directory)
            try first?.reserve(item); try first?.markClipboardWriteIntent(for: item)
            if written {
                let payload = try ClipboardAttachmentPayload(request: item)
                try first?.clipboardWritten(for: item, owner: .init(changeCount: 5, marker: payload.marker))
            }
            first = nil
            let reopened = try MacClipboardCoordinator(directoryURL: directory)
            XCTAssertFalse(try reopened.canReserve())
            let saved = try reopened.recoverForObservation(item)
            XCTAssertEqual(saved.phase, written ? .clipboardOwned : .clipboardWriteIntent)
            XCTAssertThrowsError(try reopened.authorizeSettlement(receipt(item), request: item,
                policy: .init(admittedProfiles: [profileID: .macChat])))
        }
    }

    func testOnlySeparateAdmissionResolvesAndTheLockOutlivesResolutionUntilSettlement() async throws {
        let item = try await request()
        let first = try MacClipboardCoordinator(directoryURL: scope)
        let second = try MacClipboardCoordinator(directoryURL: scope)
        try prepareInput(first, item)
        XCTAssertNil(try first.authorizeSettlement(receipt(item, failure: true), request: item,
            policy: .init(admittedProfiles: [profileID: .macChat])))
        XCTAssertEqual(try first.authorizeSettlement(receipt(item), request: item,
            policy: .init(admittedProfiles: [profileID: .macChat])), .consumed)
        XCTAssertFalse(try second.canReserve(), "Restoration fragment still owns the global lock")
        try first.finishSettlement(item)
        XCTAssertTrue(try second.canReserve())
        XCTAssertThrowsError(try second.reserve(item))
        let next = try await request()
        try prepareInput(second, next)
        XCTAssertEqual(try second.authorizeSettlement(receipt(next, failure: true), request: next,
            policy: .init(retrySafeProfiles: [profileID: .macChat])), .retryPermitted)
        try second.finishSettlement(next)
    }

    func testOwnerAndReceiptIdentityMismatchCannotAdvanceOrRelease() async throws {
        let item = try await request()
        let other = try await request()
        let coordinator = try MacClipboardCoordinator(directoryURL: scope)
        try coordinator.reserve(item); try coordinator.markClipboardWriteIntent(for: item)
        let payload = try ClipboardAttachmentPayload(request: item)
        let owner = ClipboardOwnerState(changeCount: 3, marker: payload.marker)
        XCTAssertThrowsError(try coordinator.clipboardWritten(for: item,
            owner: .init(changeCount: 3, marker: "invalid-owner")))
        try coordinator.clipboardWritten(for: item, owner: owner)
        XCTAssertThrowsError(try coordinator.markInputIntent(for: item,
            owner: .init(changeCount: 4, marker: payload.marker)))
        try coordinator.markInputIntent(for: item, owner: owner)
        XCTAssertThrowsError(try coordinator.authorizeSettlement(receipt(other), request: item,
            policy: .init(admittedProfiles: [profileID: .macChat])))
        XCTAssertThrowsError(try coordinator.finishSettlement(item))
        XCTAssertFalse(try coordinator.canReserve())
    }

    func testResolvedTombstoneCanReobserveAfterCrashBeforeQueueReceiptCommit() async throws {
        let item = try await request()
        let policy = ReceiptPolicy(admittedProfiles: [profileID: .macChat], retrySafeProfiles: [profileID: .macChat])
        var first: MacClipboardCoordinator? = try MacClipboardCoordinator(directoryURL: scope)
        let owner = try prepareInput(try XCTUnwrap(first), item)
        _ = try first?.authorizeSettlement(receipt(item), request: item, policy: policy)
        first = nil // Crash before finishSettlement or a durable queue receipt.
        let reopened = try MacClipboardCoordinator(directoryURL: scope)
        XCTAssertEqual(try reopened.recoverForObservation(item).phase, .resolved)
        XCTAssertThrowsError(try reopened.markInputIntent(for: item, owner: owner))
        XCTAssertThrowsError(try reopened.authorizeSettlement(receipt(item, failure: true), request: item, policy: policy))
        XCTAssertEqual(try reopened.authorizeSettlement(receipt(item), request: item, policy: policy), .consumed)
        try reopened.finishSettlement(item)
        XCTAssertTrue(try reopened.canReserve())
    }

    func testConsumedObservationRequiresExactTombstoneAndNeverDisplacesAnotherOwner() async throws {
        let item = try await request(), other = try await request()
        func completed(_ request: TransferRequest, phase: OperationPhase = .succeeded) throws -> TransferRequest {
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(request.operation)) as? [String: Any])
            object["phase"] = phase.rawValue
            let operation = try JSONDecoder().decode(TransferOperation.self, from: JSONSerialization.data(withJSONObject: object))
            return TransferRequest(operation: operation, asset: request.asset, fileURL: request.fileURL)
        }
        let succeeded = try completed(item)
        let first = try MacClipboardCoordinator(directoryURL: scope)
        let second = try MacClipboardCoordinator(directoryURL: scope)
        XCTAssertThrowsError(try first.verifyConsumedObservation(succeeded)) {
            XCTAssertEqual($0 as? MacClipboardCoordinationError, .identityMismatch)
        }
        XCTAssertTrue(try second.canReserve())
        try prepareInput(first, item)
        XCTAssertThrowsError(try first.verifyConsumedObservation(succeeded)) {
            XCTAssertEqual($0 as? MacClipboardCoordinationError, .busy)
        }
        _ = try first.authorizeSettlement(receipt(item), request: item,
            policy: .init(syntheticAcceptanceProfiles: [profileID: .macChat]))
        try first.finishSettlement(item)
        let before = try Data(contentsOf: scope.appendingPathComponent("journal.json"))
        try second.verifyConsumedObservation(succeeded)
        try second.verifyConsumedObservation(completed(item, phase: .compensated))
        XCTAssertThrowsError(try second.verifyConsumedObservation(item)) {
            XCTAssertEqual($0 as? MacClipboardCoordinationError, .invalidTransition)
        }
        XCTAssertThrowsError(try second.verifyConsumedObservation(completed(other))) {
            XCTAssertEqual($0 as? MacClipboardCoordinationError, .identityMismatch)
        }
        XCTAssertEqual(try Data(contentsOf: scope.appendingPathComponent("journal.json")), before)
        try first.reserve(other)
        for coordinator in [first, second] {
            XCTAssertThrowsError(try coordinator.verifyConsumedObservation(succeeded)) {
                XCTAssertEqual($0 as? MacClipboardCoordinationError, .busy)
            }
        }
        XCTAssertEqual(try probeLockInSeparateProcess(), 23, "Read-only observation must not unlock the new owner")
        try first.cancelBeforeClipboardMutation(other)
        try second.verifyConsumedObservation(succeeded)
        XCTAssertTrue(try first.canReserve())
        XCTAssertThrowsError(try second.verifyConsumedObservation(completed(other))) {
            XCTAssertEqual($0 as? MacClipboardCoordinationError, .invalidTransition)
        }
    }

    func testJournalCapacityNeverEvictsOldInputOrCancellationTombstones() async throws {
        let first = try await request(), second = try await request(), third = try await request()
        let coordinator = try MacClipboardCoordinator(directoryURL: scope, maximumEntries: 2)
        for item in [first, second] {
            try coordinator.reserve(item); try coordinator.cancelBeforeClipboardMutation(item)
        }
        XCTAssertFalse(try coordinator.canReserve())
        XCTAssertThrowsError(try coordinator.reserve(third)) { XCTAssertEqual($0 as? MacClipboardCoordinationError, .journalFull) }
        XCTAssertThrowsError(try coordinator.reserve(first)) { XCTAssertEqual($0 as? MacClipboardCoordinationError, .duplicateOperation) }
        let data = try Data(contentsOf: scope.appendingPathComponent("journal.json"))
        let value = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(value.keys), Set(["version", "records"]))
        let records = try XCTUnwrap(value["records"] as? [[String: Any]])
        XCTAssertEqual(records.count, 2)
        for record in records {
            XCTAssertEqual(Set(record.keys), Set(["identity", "phase"]))
        }
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains(root.path))
    }

    func testFailureAfterIntentRenameRetainsExclusionAndDurableUncertainty() async throws {
        let item = try await request()
        let fault = JournalFaultSwitch()
        var first: MacClipboardCoordinator? = try MacClipboardCoordinator(directoryURL: scope,
            maximumEntries: 256, fault: { try fault.check($0) })
        let payload = try ClipboardAttachmentPayload(request: item)
        let owner = ClipboardOwnerState(changeCount: 7, marker: payload.marker)
        try first?.reserve(item); try first?.markClipboardWriteIntent(for: item)
        try first?.clipboardWritten(for: item, owner: owner)
        fault.arm()
        XCTAssertThrowsError(try first?.markInputIntent(for: item, owner: owner))
        XCTAssertThrowsError(try first?.canReserve()) { XCTAssertEqual($0 as? MacClipboardCoordinationError, .poisoned) }
        let second = try MacClipboardCoordinator(directoryURL: scope)
        XCTAssertFalse(try second.canReserve())
        first = nil
        XCTAssertEqual(try second.recoverForObservation(item).phase, .inputIntent)
        XCTAssertThrowsError(try second.markInputIntent(for: item, owner: owner))
    }

    func testCorruptJournalAndSpecialFilesFailClosedWithoutOverwriting() throws {
        let coordinator = try MacClipboardCoordinator(directoryURL: scope)
        let journal = scope.appendingPathComponent("journal.json")
        let corrupt = Data("{invalid-private-journal".utf8)
        try corrupt.write(to: journal)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: journal.path)
        XCTAssertThrowsError(try coordinator.canReserve())
        XCTAssertEqual(try Data(contentsOf: journal), corrupt)
        try FileManager.default.removeItem(at: journal)
        XCTAssertEqual(mkfifo(journal.path, 0o600), 0)
        XCTAssertThrowsError(try coordinator.canReserve()) // O_NONBLOCK prevents a FIFO open hang.
        try FileManager.default.removeItem(at: journal)
        let outside = root.appendingPathComponent("outside.json")
        try corrupt.write(to: outside)
        try FileManager.default.createSymbolicLink(at: journal, withDestinationURL: outside)
        XCTAssertThrowsError(try coordinator.canReserve())
        XCTAssertEqual(try Data(contentsOf: outside), corrupt)
    }

    /// A real child process proves the flock boundary rather than a second Swift
    /// wrapper sharing only in-memory state. Python is already a CI prerequisite.
    private func probeLockInSeparateProcess() throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", "-c", """
        import fcntl, os, sys
        fd = os.open(sys.argv[1], os.O_RDWR | os.O_NONBLOCK)
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            sys.exit(23)
        finally:
            os.close(fd)
        """, scope.appendingPathComponent("owner.lock").path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run(); process.waitUntilExit()
        return process.terminationStatus
    }
}

private final class JournalFaultSwitch: @unchecked Sendable {
    private let lock = NSLock()
    private var armed = false
    func arm() { lock.lock(); armed = true; lock.unlock() }
    func check(_ point: MacClipboardCoordinator.Checkpoint) throws {
        lock.lock(); defer { lock.unlock() }
        if armed, case .journalRenamed = point { throw MacClipboardCoordinationError.storageFailure(EIO) }
    }
}
