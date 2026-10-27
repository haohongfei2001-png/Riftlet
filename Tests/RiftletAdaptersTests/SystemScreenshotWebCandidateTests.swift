import XCTest
import Foundation
import CryptoKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import RiftletCore
@testable import RiftletAdapters

/// Original-origin objects below contain generated test bytes. They exercise
/// the native candidate gates; none is evidence of a live system screenshot.
final class SystemScreenshotWebCandidateTests: XCTestCase {
    private var directory: URL!
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("system-web-input-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }

    func testUnsupportedFormatBytesPixelsAndOriginRefuseBeforeOperationOrWebCall() async throws {
        let variants: [(String, Int64, Int, Int, AssetOrigin, SystemScreenshotInputError)] = [
            ("image/jpeg", 100, 1, 1, .systemScreenshot, .unsupportedFormat),
            ("image/heic", 100, 1, 1, .systemScreenshot, .unsupportedFormat),
            ("image/heif", 100, 1, 1, .systemScreenshot, .unsupportedFormat),
            ("image/tiff", 100, 1, 1, .systemScreenshot, .unsupportedFormat),
            ("image/png", 8 * 1024 * 1024 + 1, 1, 1, .systemScreenshot, .byteLimit),
            ("image/png", 100, 4097, 4096, .systemScreenshot, .pixelLimit),
            ("image/png", 100, 1, 1, .synthetic, .systemScreenshotsOnly)
        ]
        for (mime, size, width, height, origin, expected) in variants {
            let store = try QueueStore(databaseURL: directory.appendingPathComponent("\(UUID()).sqlite"))
            let image = asset(mime: mime, size: size, width: width, height: height, origin: origin)
            _ = try await store.importAsset(image)
            let bridge = CandidateGateBridge()
            let coordinator = TransferCoordinator(store: store, adapter: try adapter(store, bridge), mediaDirectory: directory)
            do { try await coordinator.select(image.id, frozenTarget: CandidateGateBridge.target); XCTFail("Ineligible image prepared") }
            catch let error as SystemScreenshotInputError { XCTAssertEqual(error, expected) }
            let record = try await store.asset(id: image.id)
            XCTAssertNil(record?.activeOperationID); XCTAssertEqual(record?.status, .pending)
            XCTAssertEqual(record?.visibility, .visible)
            let commands = await bridge.actions; XCTAssertTrue(commands.isEmpty)
        }
    }

    func testCurrentPageLimitsAreExactAndNoLargerTransportIsNegotiated() throws {
        try SystemScreenshotWebCandidate.validateMetadata(asset(size: 8 * 1024 * 1024, width: 4096, height: 4096))
        XCTAssertThrowsError(try SystemScreenshotWebCandidate.validateMetadata(asset(width: Int.max, height: 1)))
        XCTAssertThrowsError(try SystemScreenshotWebCandidate.validateMetadata(asset(size: 0)))
        let page = try ChatGPTWebPageProgram.load()
        XCTAssertEqual(page.sourceID, SystemScreenshotWebCandidate.sourceID)
        XCTAssertEqual(page.maximumChunkBytes, 256 * 1024)
    }

    func testMislabeledPrivateFileRefusesLocallyWithoutCreatingUnknown() async throws {
        let store = try QueueStore(databaseURL: directory.appendingPathComponent("queue.sqlite"))
        let bytes = Data(repeating: 42, count: 100)
        let image = asset(size: Int64(bytes.count), hash: hash(bytes))
        let file = directory.appendingPathComponent(image.fileName); try bytes.write(to: file)
        _ = try await store.importAsset(image)
        let bridge = CandidateGateBridge()
        let coordinator = TransferCoordinator(store: store, adapter: try adapter(store, bridge), mediaDirectory: directory)
        do { try await coordinator.select(image.id, frozenTarget: CandidateGateBridge.target); XCTFail("Non-PNG prepared") }
        catch WebAdapterError.invalidPrivateFile {}
        let record = try await store.asset(id: image.id)
        XCTAssertNil(record?.activeOperationID); XCTAssertEqual(record?.status, .pending)
        let actions = await bridge.actions; XCTAssertTrue(actions.isEmpty)
        XCTAssertEqual(try Data(contentsOf: file), bytes)
    }

    func testHashCorruptionAfterHeaderRetainsConservativeUnknownWithoutAnyInput() async throws {
        let bytes = try png()
        let image = asset(size: Int64(bytes.count), width: 12, height: 8, hash: hash(bytes))
        var damaged = bytes; damaged[damaged.count - 1] ^= 1
        try damaged.write(to: directory.appendingPathComponent(image.fileName))
        let store = try QueueStore(databaseURL: directory.appendingPathComponent("queue.sqlite"))
        _ = try await store.importAsset(image)
        let bridge = CandidateGateBridge()
        let coordinator = TransferCoordinator(store: store, adapter: try adapter(store, bridge), mediaDirectory: directory)
        try await coordinator.select(image.id, frozenTarget: CandidateGateBridge.target)
        let record = try await store.asset(id: image.id)
        XCTAssertEqual(record?.status, .unknown); XCTAssertEqual(record?.visibility, .visible)
        let actions = await bridge.actions
        XCTAssertEqual(actions, [.validate], "The descriptor hash must refuse before begin or commit")
    }

    func testOldUnknownWithNowUnsupportedFormatOnlyObservesItsOriginalIdentity() async throws {
        let store = try QueueStore(databaseURL: directory.appendingPathComponent("queue.sqlite"))
        let image = asset(mime: "image/jpeg")
        _ = try await store.importAsset(image)
        let operation = try await store.prepare(assetID: image.id, target: CandidateGateBridge.target)
        try await store.markDispatchIntent(operation.id)
        try await store.markUnknown(operation.id, reason: "Software historical-operation fixture")
        let bridge = CandidateGateBridge()
        let coordinator = TransferCoordinator(store: store, adapter: try adapter(store, bridge), mediaDirectory: directory)
        try await coordinator.select(image.id, frozenTarget: nil)
        let actions = await bridge.actions; XCTAssertEqual(actions, [.observe])
        let record = try await store.asset(id: image.id)
        XCTAssertEqual(record?.activeOperationID, operation.id); XCTAssertEqual(record?.status, .unknown)
        let identities = await bridge.identities
        XCTAssertTrue(identities.allSatisfy { $0.operationID == operation.id && $0.assetID == image.id && $0.target == operation.target })
    }

    func testCandidateRequiresItsOwnProfileAndDurableJournalBeforeAnyPageAction() async throws {
        let store = try QueueStore(databaseURL: directory.appendingPathComponent("queue.sqlite"))
        let bridge = CandidateGateBridge(), page = try ChatGPTWebPageProgram.load()
        let noJournal = WebAttachmentAdapter(mediaDirectory: directory, executor: bridge, program: page,
            mode: .systemScreenshotCandidate, profile: SystemScreenshotWebCandidate.profile)
        let syntheticProfile = WebAttachmentAdapter(mediaDirectory: directory, executor: bridge, program: page,
            mode: .systemScreenshotCandidate, profile: ChatGPTWebPageProgram.acceptanceProfile,
            candidateJournal: SystemScreenshotObservationJournal(store: store))
        for client in [noJournal, syntheticProfile] {
            do { _ = try await client.captureTarget(); XCTFail("Unscoped candidate ran") }
            catch WebAdapterError.programUnavailable {}
        }
        let actions = await bridge.actions; XCTAssertTrue(actions.isEmpty)
    }

    func testSyntheticFixtureCanNeverBecomeRealCandidateEvidence() async throws {
        let store = try QueueStore(databaseURL: directory.appendingPathComponent("queue.sqlite"))
        let image = asset()
        _ = try await store.importAsset(image)
        let operation = try await store.prepare(assetID: image.id, target: CandidateGateBridge.target)
        try await store.markDispatchIntent(operation.id)
        let current = try await store.operation(id: operation.id)
        let request = TransferRequest(operation: try XCTUnwrap(current), asset: image,
            fileURL: directory.appendingPathComponent(image.fileName))
        let bridge = CandidateGateBridge(source: .syntheticFixture)
        do { _ = try await adapter(store, bridge).reconcile(request); XCTFail("Fixture admitted as real-origin evidence") }
        catch ObservationError.syntheticEvidenceForRealAsset {}
        let actions = await bridge.actions; XCTAssertEqual(actions, [.observe])
    }

    private func adapter(_ store: QueueStore, _ bridge: CandidateGateBridge) throws -> WebAttachmentAdapter {
        WebAttachmentAdapter(mediaDirectory: directory, executor: bridge, program: try ChatGPTWebPageProgram.load(),
            mode: .systemScreenshotCandidate, profile: SystemScreenshotWebCandidate.profile, polling: .disabled,
            candidateJournal: SystemScreenshotObservationJournal(store: store))
    }
    private func asset(mime: String = "image/png", size: Int64 = 100, width: Int = 1, height: Int = 1,
                       origin: AssetOrigin = .systemScreenshot, hash: String = String(repeating: "a", count: 64)) -> ImportedAsset {
        ImportedAsset(sourceKey: UUID().uuidString, fileName: "\(UUID()).png", sha256: hash, byteCount: size,
            pixelWidth: width, pixelHeight: height, mediaType: mime, origin: origin)
    }
    private func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private func png() throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: 12, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.7, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 12, height: 8))
        let image = try XCTUnwrap(context.makeImage()), data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }
}

private actor CandidateGateBridge: WebBridgeExecutor {
    static let target = TargetLease(adapterID: "chatgpt-web", surface: .webChat, applicationID: "com.google.Chrome",
        sessionID: "candidate-software", windowID: "1", tabID: "2", documentID: "doc", composerID: "composer", draftGeneration: "original")
    private(set) var actions: [WebBridgeAction] = []
    private(set) var identities: [ObservationIdentity] = []
    private let source: ObservationSource
    init(source: ObservationSource = .integratedDevelopment) { self.source = source }
    func execute(_ command: WebBridgeCommand, program: WebPageProgram) async throws -> Data {
        actions.append(command.action)
        if let identity = command.identity { identities.append(identity) }
        if command.action == .validate {
            let target = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Self.target))
            return try JSONSerialization.data(withJSONObject: ["valid": true, "target": target])
        }
        if command.action == .observe, let identity = command.identity {
            return try JSONEncoder().encode(AttachmentObservationEnvelope(
                provenance: .init(source: source, evidenceID: "candidate-software-only"),
                observation: .init(identity: identity, state: .unknown)))
        }
        XCTFail("Unexpected input in a refusal/read-only test")
        throw WebAdapterError.invalidRequest
    }
}
