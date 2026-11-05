import AppKit
import XCTest
import RiftletCore
@testable import RiftletUI
@testable import RiftletApp

/// Exercises real panel mouse callbacks, the production click resolver and
/// coordinator against SQLite. The receiving application here is controlled;
/// live Chrome setter/change is covered separately and is not claimed here.
final class FirstClickOperationTests: XCTestCase {
    @MainActor func testColdMouseClicksCreateTwoIndependentOperationsAndStartsWithoutArming() async throws {
        _ = NSApplication.shared
        XCTAssertFalse(NSScreen.screens.isEmpty)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cold-click-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try QueueStore(databaseURL: root.appendingPathComponent("queue.sqlite"))
        var images: [AssetRecord] = []
        for _ in 0..<2 {
            let id = UUID(), bytes = Data("controlled screenshot".utf8)
            let image = ImportedAsset(id: id, sourceKey: id.uuidString, fileName: "\(id).png",
                sha256: String(repeating: "a", count: 64), byteCount: Int64(bytes.count),
                pixelWidth: 1, pixelHeight: 1, mediaType: "image/png", origin: .synthetic)
            try bytes.write(to: root.appendingPathComponent(image.fileName))
            images.append(try await store.importAsset(image))
        }
        let receiver = ClickReceiver(), authority = SelectionAuthority(), queue = SelectionSubmissionQueue()
        let targetRead = ClickReadBarrier()
        let coordinator = TransferCoordinator(store: store, adapter: receiver, mediaDirectory: root,
            policy: .init(syntheticUploadStartProfiles: ["cold-click-start": .webChat]),
            validateAcceptedSelection: { selection in
                await MainActor.run {
                    authority.permits(selection, epoch: UUID(), foregroundSession: nil,
                        hidden: false, terminating: false, now: ProcessInfo.processInfo.systemUptime)
                }
            })
        var targets: [UUID: Task<TargetLease, Error>] = [:]
        var panel: RiftPanelController!
        let submitted = expectation(description: "both native AppKit callback paths submitted")
        submitted.expectedFulfillmentCount = 2
        panel = RiftPanelController(mediaDirectory: root, arrivalMode: .none,
            onPress: { asset, _ in
                // Nothing was captured before mouseDown. Resolve only this
                // click's native read, after mouseUp and loss of Chrome focus.
                targets[asset] = Task { await targetRead.wait(); return ClickReceiver.target }
            }, holdsSelectionUntilFinished: true, onSelect: { asset in
                let task = targets.removeValue(forKey: asset)!
                let revision = panel.selectionRevision(for: asset)!
                let owner = UUID(), selectedAt = ProcessInfo.processInfo.systemUptime
                queue.enqueue(selectionID: owner, deadline: selectedAt + 30, cancelled: {}) { _ in
                    do {
                        let selection = try await authority.accept(id: owner, assetID: asset,
                            visibilityRevision: revision, selectedAt: selectedAt, target: task) { true }
                        try await coordinator.select(selection)
                    } catch { XCTFail("The click failed before/at operation creation: \(error)") }
                    panel.finishSelection(asset)
                    submitted.fulfill()
                }
            })
        defer { panel.close(); queue.stop() }
        panel.render(images)
        for record in images {
            let row = try XCTUnwrap(panel.diagnosticSnapshot.rows.first { $0.assetID == record.id })
            let window = try XCTUnwrap(NSApp.windows.first { $0.windowNumber == row.imageInputWindowNumber })
            let view = try XCTUnwrap(window.contentView)
            let point = window.convertPoint(fromScreen: CGPoint(x: row.imageClipFrame.midX, y: row.imageClipFrame.midY))
            let now = ProcessInfo.processInfo.systemUptime
            func event(_ type: NSEvent.EventType) throws -> NSEvent {
                try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                    timestamp: now, windowNumber: window.windowNumber, context: nil,
                    eventNumber: type == .leftMouseDown ? 51 : 52, clickCount: 1, pressure: 1))
            }
            view.mouseDown(with: try event(.leftMouseDown))
            view.mouseUp(with: try event(.leftMouseUp))
        }
        for image in images {
            let before = try await store.asset(id: image.id)
            XCTAssertNil(before?.activeOperationID, "Target read is deliberately still pending")
        }
        await targetRead.open()
        await fulfillment(of: [submitted], timeout: 5)
        for image in images {
            for _ in 0..<500 {
                if let op = try await store.asset(id: image.id)?.activeOperationID,
                   try await store.uploadStartReceipt(for: op) != nil { break }
                try await Task.sleep(nanoseconds: 2_000_000)
            }
            let record = try await store.asset(id: image.id)
            let op = try XCTUnwrap(record?.activeOperationID)
            let start = try await store.uploadStartReceipt(for: op)
            let operation = try await store.operation(id: op)
            XCTAssertNotNil(start)
            XCTAssertEqual(record?.visibility, .swallowed)
            XCTAssertEqual(operation?.attempt, 1)
            XCTAssertNotEqual(operation?.phase, .succeeded, "No COMPLETE is supplied by this receiver")
        }
        let inputs = await receiver.inputs()
        XCTAssertEqual(inputs, images.map(\.id), "Each original click executes once in order")
        XCTAssertEqual(Set(inputs).count, 2)
    }

    @MainActor func testRemovalWhileColdTargetReadIsPendingCannotSubmitLater() async throws {
        let authority = SelectionAuthority(), barrier = ClickReadBarrier()
        let target = Task<TargetLease, Error> { await barrier.wait(); return ClickReceiver.target }
        var rowStillSelected = true
        let pending = Task {
            try await authority.accept(id: UUID(), assetID: UUID(), visibilityRevision: 0, target: target) {
                rowStillSelected
            }
        }
        await barrier.waitUntilReadStarted()
        rowStillSelected = false
        await barrier.open()
        do { _ = try await pending.value; XCTFail("Removed screenshot was admitted") }
        catch is CancellationError {} catch { XCTFail("Unexpected failure: \(error)") }
    }
}

private actor ClickReadBarrier {
    private var opened = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var readStarted = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        readStarted = true
        let waitingForStart = startWaiters; startWaiters.removeAll()
        waitingForStart.forEach { $0.resume() }
        if opened { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func waitUntilReadStarted() async {
        if readStarted { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }
    func open() {
        opened = true
        let current = waiters; waiters.removeAll()
        current.forEach { $0.resume() }
    }
}

private actor ClickReceiver: IndependentFileInputAdapter {
    nonisolated let id = "cold-click-receiver"
    static let target = TargetLease(adapterID: "cold-click-receiver", surface: .webChat,
        applicationID: "com.google.Chrome", sessionID: "controlled-process", windowID: "1", tabID: "2",
        documentID: "document", composerID: "composer", draftGeneration: "draft")
    private var inserted: [UUID] = []
    func inputs() -> [UUID] { inserted }
    func captureTarget() throws -> TargetLease { throw RiftletError.invalidTransition }
    func validate(_ target: TargetLease) -> Bool { target == Self.target }
    func append(_ request: TransferRequest) async throws -> TransferReceipt {
        try await append(request, onInputExecutionReturned: {})
    }
    func append(_ request: TransferRequest,
                onInputConfirmed: @escaping @Sendable (TransferReceipt) async -> Void) throws -> TransferReceipt {
        throw RiftletError.invalidTransition
    }
    func append(_ request: TransferRequest,
                onInputExecutionReturned: @escaping @Sendable () async -> Void) async throws -> TransferReceipt {
        inserted.append(request.asset.id)
        await onInputExecutionReturned()
        return receipt(request)
    }
    func reconcile(_ request: TransferRequest) -> TransferReceipt { receipt(request) }
    private func receipt(_ request: TransferRequest) -> TransferReceipt {
        .init(operationID: request.operation.id, assetID: request.asset.id, attempt: request.operation.attempt,
            assetSHA256: request.asset.sha256, target: request.operation.target, outcome: .uploadStarted,
            profileID: "cold-click-input", attachmentID: "attachment-\(request.operation.id)",
            belongsToOriginalDraft: true, isUploading: true,
            uploadStartEvidence: .init(profileID: "cold-click-start", signal: .attachmentAccepted,
                                       evidenceID: "start-\(request.operation.id)"))
    }
}
