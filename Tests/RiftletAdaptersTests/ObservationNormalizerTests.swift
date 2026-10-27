import Foundation
import XCTest
import RiftletCore
@testable import RiftletAdapters

final class ObservationNormalizerTests: XCTestCase {
    private var directory: URL!
    private let profileID = "synthetic-observer-test-v1"

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("riftlet-observer-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }

    private func fixture(origin: AssetOrigin = .synthetic, dispatch: Bool = true) async throws -> (QueueStore, TransferRequest) {
        let store = try QueueStore(databaseURL: directory.appendingPathComponent("\(UUID()).sqlite"))
        let asset = ImportedAsset(sourceKey: UUID().uuidString, fileName: "\(UUID()).png",
                                  sha256: String(repeating: "a", count: 64), byteCount: 128,
                                  pixelWidth: 32, pixelHeight: 24, mediaType: "image/png", origin: origin)
        _ = try await store.importAsset(asset)
        let target = TargetLease(adapterID: "chatgpt-web", surface: .webChat,
            applicationID: "com.google.Chrome", sessionID: "fixture-session",
            windowID: "fixture-window", tabID: "fixture-tab", documentID: "fixture-document",
            composerID: "fixture-composer", draftGeneration: "fixture-generation")
        let prepared = try await store.prepare(assetID: asset.id, target: target)
        if dispatch { try await store.markDispatchIntent(prepared.id) }
        let saved = try await store.operation(id: prepared.id)
        let operation = try XCTUnwrap(saved)
        return (store, TransferRequest(operation: operation, asset: asset,
                                       fileURL: directory.appendingPathComponent(asset.fileName)))
    }

    private func profile(completion: ObservationCompletionSignal? = nil,
                         failure: ObservationFailureSignal? = nil) -> ObservationNormalizer {
        ObservationNormalizer(profile: ObservationProfile(adapterID: "chatgpt-web", surface: .webChat,
            profileID: profileID, completionSignal: completion, failureSignal: failure))
    }

    private func envelope(_ request: TransferRequest,
                          state: AttachmentObservedState = .attached,
                          source: ObservationSource = .syntheticFixture,
                          changes: [String: Any] = [:]) throws -> AttachmentObservationEnvelope {
        let identity = ObservationIdentity(operationID: request.operation.id, assetID: request.asset.id,
            attempt: request.operation.attempt, assetSHA256: request.asset.sha256, target: request.operation.target)
        let observation = AttachmentObservation(identity: identity, state: state, attachmentID: "fixture-attachment",
            exactImageIdentity: true, belongsToOriginalDraft: true)
        let packet = AttachmentObservationEnvelope(
            provenance: ObservationProvenance(source: source, evidenceID: "W0-test-generated"),
            observation: observation)
        return try mutate(packet) { root in
            var item = root["observation"] as! [String: Any]
            for (key, value) in changes { item[key] = value }
            root["observation"] = item
        }
    }

    private func mutate(_ packet: AttachmentObservationEnvelope,
                        _ body: (inout [String: Any]) -> Void) throws -> AttachmentObservationEnvelope {
        var root = try JSONSerialization.jsonObject(with: JSONEncoder().encode(packet)) as! [String: Any]
        body(&root)
        return try ObservationDecoder.decode(JSONSerialization.data(withJSONObject: root))
    }

    func testVersionedFixtureIsExplicitlySyntheticAndRoundTrips() throws {
        let file = try XCTUnwrap(Bundle.module.url(forResource: "synthetic-attached-v1", withExtension: "json"))
        let packet = try ObservationDecoder.decode(Data(contentsOf: file))
        XCTAssertEqual(packet.schemaVersion, 1)
        XCTAssertEqual(packet.provenance.source, .syntheticFixture)
        XCTAssertEqual(packet.provenance.evidenceID, "W0-synthetic-attached-v1")
        XCTAssertEqual(packet, try ObservationDecoder.decode(JSONEncoder().encode(packet)))
    }

    func testDecoderRejectsUnknownVersionOversizeAndPayloadAdmissionFields() async throws {
        let (_, request) = try await fixture()
        let packet = try envelope(request)
        XCTAssertThrowsError(try mutate(packet) { $0["schemaVersion"] = 2 }) {
            XCTAssertEqual($0 as? ObservationError, .unsupportedSchema(2))
        }
        XCTAssertThrowsError(try ObservationDecoder.decode(Data(repeating: 32, count: 65 * 1024))) {
            XCTAssertEqual($0 as? ObservationError, .oversizedPayload)
        }
        XCTAssertThrowsError(try mutate(packet) { $0["profileID"] = "trusted-ready" })
        XCTAssertThrowsError(try mutate(packet) { root in
            var item = root["observation"] as! [String: Any]
            item["safeToRetry"] = true; root["observation"] = item
        })
        for nestedTarget in [false, true] {
            XCTAssertThrowsError(try mutate(packet) { root in
                var item = root["observation"] as! [String: Any]
                var identity = item["identity"] as! [String: Any]
                if nestedTarget {
                    var target = identity["target"] as! [String: Any]
                    target["admittedProfile"] = "injected"
                    identity["target"] = target
                } else { identity["admittedProfile"] = "injected" }
                item["identity"] = identity; root["observation"] = item
            })
        }
        XCTAssertThrowsError(try ObservationDecoder.decode(Data("{bad json".utf8)))
    }

    func testDefaultAttachedMappingCannotConsumeEvenWithAnAdmittedReceiptProfile() async throws {
        let (store, request) = try await fixture()
        let receipt = try profile().receipt(from: envelope(request), for: request)
        XCTAssertEqual(receipt.outcome, .attachedCandidate)
        XCTAssertFalse(receipt.positiveReady)
        let record = try await store.apply(receipt, policy: .init(admittedProfiles: [profileID: .webChat]))
        XCTAssertEqual(record.status, .transferring)
        let queue = try await store.assets()
        XCTAssertEqual(queue.map(\.id), [request.asset.id])
    }

    func testCodeSelectedAttachedCompletionStillRequiresCorePolicyAdmission() async throws {
        let (store, request) = try await fixture()
        let receipt = try profile(completion: .attached).receipt(from: envelope(request), for: request)
        XCTAssertEqual(receipt.outcome, .verifiedReady)
        let record = try await store.apply(receipt)
        XCTAssertEqual(record.status, .unknown)
        XCTAssertEqual(record.activeOperationID, request.operation.id)
        let operation = try await store.prepare(assetID: request.asset.id, target: request.operation.target)
        XCTAssertEqual(operation.id, request.operation.id)
    }

    func testSyntheticProductAttachedFixtureUsesExistingDurableSuccessTransaction() async throws {
        let (store, request) = try await fixture()
        let receipt = try profile(completion: .attached).receipt(from: envelope(request), for: request)
        let record = try await store.apply(receipt, policy: .init(admittedProfiles: [profileID: .webChat]))
        XCTAssertEqual(record.status, .used)
        try await store.recoverInterruptedOperations()
        let operation = try await store.operation(id: request.operation.id)
        let queue = try await store.assets()
        XCTAssertEqual(operation?.phase, .succeeded)
        XCTAssertTrue(queue.isEmpty)
    }

    func testEveryRequestIdentityFieldIsBoundBeforeAnyReceiptCanBeApplied() async throws {
        let (store, request) = try await fixture()
        let base = try envelope(request)
        let changes: [(String, Any)] = [
            ("operationID", UUID().uuidString), ("assetID", UUID().uuidString),
            ("attempt", request.operation.attempt + 1), ("assetSHA256", String(repeating: "b", count: 64))
        ]
        for (key, value) in changes {
            let packet = try mutate(base) { root in
                var item = root["observation"] as! [String: Any]
                var identity = item["identity"] as! [String: Any]
                identity[key] = value; item["identity"] = identity; root["observation"] = item
            }
            XCTAssertThrowsError(try profile(completion: .attached).receipt(from: packet, for: request)) {
                XCTAssertEqual($0 as? ObservationError, .identityMismatch)
            }
        }
        for field in ["adapterID", "applicationID", "sessionID", "windowID", "tabID", "documentID", "composerID", "draftGeneration", "surface"] {
            let packet = try mutate(base) { root in
                var item = root["observation"] as! [String: Any]
                var identity = item["identity"] as! [String: Any]
                var target = identity["target"] as! [String: Any]
                target[field] = field == "surface" ? "webWork" : "different"
                identity["target"] = target; item["identity"] = identity; root["observation"] = item
            }
            XCTAssertThrowsError(try profile(completion: .attached).receipt(from: packet, for: request)) {
                XCTAssertEqual($0 as? ObservationError, .identityMismatch)
            }
        }
        let saved = try await store.asset(id: request.asset.id)
        XCTAssertEqual(saved?.status, .transferring)
    }

    func testErrorUploadingUnprovenImageAndWrongMembershipNeverBecomeSuccess() async throws {
        let mutations: [[String: Any]] = [
            ["hasError": true], ["isUploading": true], ["exactImageIdentity": false],
            ["belongsToOriginalDraft": false], ["attachmentID": NSNull()], ["attachmentAbsent": true]
        ]
        for change in mutations {
            let (store, request) = try await fixture()
            let receipt = try profile(completion: .attached).receipt(from: envelope(request, changes: change), for: request)
            XCTAssertEqual(receipt.outcome, .unknown)
            XCTAssertFalse(receipt.positiveReady)
            let result = try await store.apply(receipt, policy: .init(admittedProfiles: [profileID: .webChat]))
            XCTAssertEqual(result.status, .unknown)
        }
    }

    func testInputUnknownAndNavigationCannotMasqueradeAsCompletion() async throws {
        for state in [AttachmentObservedState.inputTriggered, .unknown, .invalidated] {
            let (_, request) = try await fixture()
            let receipt = try profile(completion: .attached).receipt(from: envelope(request, state: state), for: request)
            XCTAssertFalse(receipt.positiveReady)
            XCTAssertFalse(receipt.safeToRetry)
            XCTAssertEqual(receipt.outcome, state == .inputTriggered ? .inputTriggered : .unknown)
        }
    }

    func testAmbiguousFailureHasNoSafeRetryWithoutAllIndependentFacts() async throws {
        let (_, request) = try await fixture()
        let base: [String: Any] = ["hasError": true, "attachmentAbsent": true,
                                   "attachmentID": NSNull(), "automaticRetryExcluded": true]
        for missing in ["hasError", "attachmentAbsent", "automaticRetryExcluded", "exactImageIdentity", "belongsToOriginalDraft"] {
            var changes = base; changes[missing] = false
            let packet = try envelope(request, state: .failed, changes: changes)
            let receipt = try profile(failure: .terminalErrorAndNoResidual).receipt(from: packet, for: request)
            XCTAssertEqual(receipt.outcome, .unknown)
            XCTAssertFalse(receipt.safeToRetry)
        }
        let packet = try envelope(request, state: .failed, changes: base)
        let noFailureMapping = try profile(completion: .attached).receipt(from: packet, for: request)
        XCTAssertEqual(noFailureMapping.outcome, .unknown)
        XCTAssertFalse(noFailureMapping.safeToRetry)
    }

    func testLegacyAbsenceFailureCannotGrantRetryEvenWithSeparateProfileAdmission() async throws {
        let (store, request) = try await fixture()
        let packet = try envelope(request, state: .failed, changes: [
            "hasError": true, "attachmentAbsent": true, "attachmentID": NSNull(), "automaticRetryExcluded": true
        ])
        let normalizer = profile(failure: .terminalErrorAndNoResidual)
        let receipt = try normalizer.receipt(from: packet, for: request)
        XCTAssertEqual(receipt.outcome, .definitiveFailure)
        XCTAssertNil(receipt.attachmentID, "Legacy absence proof cannot identify a safely retired original attachment")
        let unknown = try await store.apply(receipt, policy: .init(admittedProfiles: [profileID: .webChat]))
        XCTAssertEqual(unknown.status, .unknown)
        let stillUnknown = try await store.apply(receipt, policy: .init(retrySafeProfiles: [profileID: .webChat]))
        XCTAssertEqual(stillUnknown.status, .unknown)
        let retained = try await store.prepare(assetID: request.asset.id, target: request.operation.target)
        XCTAssertEqual(retained.id, request.operation.id)
        XCTAssertEqual(retained.attempt, 1)
        XCTAssertEqual(retained.phase, .unknown)
        // Safe, identified termination and stale-attempt isolation are exercised
        // separately in Core. Do not fabricate that proof in this v1 observer.
    }

    func testDevelopmentProvenanceCannotDriveARealScreenshotOperation() async throws {
        let (_, request) = try await fixture(origin: .systemScreenshot)
        for source in [ObservationSource.syntheticFixture, .integratedDevelopment] {
            XCTAssertThrowsError(try profile(completion: .attached).receipt(from: envelope(request, source: source), for: request)) {
                XCTAssertEqual($0 as? ObservationError, .syntheticEvidenceForRealAsset)
            }
        }
    }

    func testClaimedRealProvenanceDoesNotGrantACompletionMappingOrAdmission() async throws {
        let (store, request) = try await fixture()
        // This only exercises the audit label; it is not archived real-world evidence.
        let packet = try envelope(request, source: .sanitizedReal)
        let receipt = try profile().receipt(from: packet, for: request)
        XCTAssertEqual(receipt.outcome, .attachedCandidate)
        XCTAssertFalse(receipt.positiveReady)
        let result = try await store.apply(receipt)
        XCTAssertNotEqual(result.status, .used)
    }

    func testPreparedOperationCannotAcceptAnObservationBeforeDurableIntent() async throws {
        let (_, request) = try await fixture(dispatch: false)
        XCTAssertThrowsError(try profile(completion: .attached).receipt(from: envelope(request), for: request)) {
            XCTAssertEqual($0 as? ObservationError, .operationNotDispatched)
        }
    }

    func testMappingDoesNotLeakAcrossSurfacesAndRejectsBlankAttachmentIdentity() async throws {
        let (_, request) = try await fixture()
        let other = ObservationNormalizer(profile: .init(adapterID: "chatgpt-web", surface: .webWork,
            profileID: profileID, completionSignal: .attached))
        XCTAssertThrowsError(try other.receipt(from: envelope(request), for: request)) {
            XCTAssertEqual($0 as? ObservationError, .profileTargetMismatch)
        }
        XCTAssertThrowsError(try envelope(request, changes: ["attachmentID": "   "])) {
            XCTAssertEqual($0 as? ObservationError, .invalidField("attachment identity"))
        }
    }
}
