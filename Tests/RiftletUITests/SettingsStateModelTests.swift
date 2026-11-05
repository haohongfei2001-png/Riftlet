import Foundation
import XCTest
import RiftletCapture
@testable import RiftletUI

/// Pure state/owner-adapter tests. No NSApplication, WindowServer or user files.
final class SettingsStateModelTests: XCTestCase {
    @MainActor private final class Gate {
        private var suspended: CheckedContinuation<Void, Never>?
        private var released = false
        let entered = XCTestExpectation(description: "Synthetic owner is awaiting its receipt")
        var isSuspended: Bool { suspended != nil }

        func suspend() async {
            guard !released else { return }
            await withCheckedContinuation { continuation in
                suspended = continuation
                entered.fulfill()
            }
        }
        func release() { released = true; suspended?.resume(); suspended = nil }
    }

    @MainActor private final class Owner: SettingsPersistenceAdapter {
        var value: SettingsOwnerSnapshot
        var failures: Set<SettingsDomain> = []
        var requests: [SettingsSaveRequest] = []
        var beforeReturn: (@MainActor (SettingsSaveRequest, SettingsOwnerSnapshot) async -> Void)?

        init(configuration: RiftConfiguration = .init(), archive: Double? = 24) {
            value = SettingsOwnerSnapshot(revision: 1,
                settings: RiftSettingsSnapshot(entryAvailable: true, displays: [
                    .init(id: 1, name: "Synthetic A", uuid: Self.a),
                    .init(id: 2, name: "Synthetic B", uuid: Self.b)
                ], archiveAfterHours: archive, configuration: configuration),
                collectionPaused: false, isHidden: false, mainDisplayID: 1, effectiveDisplayID: 1)
        }
        static let a = "01000000-0000-0000-0000-000000000001"
        static let b = "02000000-0000-0000-0000-000000000002"

        func advance(_ mutate: (inout SettingsOwnerSnapshot) -> Void = { _ in }) {
            var next = value; mutate(&next)
            value = .init(revision: value.revision + 1, settings: next.settings,
                          collectionPaused: next.collectionPaused, isHidden: next.isHidden,
                          mainDisplayID: next.mainDisplayID, effectiveDisplayID: next.effectiveDisplayID)
        }

        var known: [SettingsDomain: SettingsConfirmedValue] {
            [.collection: .boolean(value.collectionPaused), .visibility: .boolean(value.isHidden),
             .entry: .boolean(value.settings.entryEnabled), .layout: .configuration(value.settings.configuration),
             .archive: .archiveHours(value.settings.archiveAfterHours)]
        }

        func save(_ request: SettingsSaveRequest) async -> SettingsSaveOutcome {
            requests.append(request)
            let failed = failures.contains(request.intent.domain)
            advance { next in
                // Mirrors existing owner semantics, not production filesystem execution.
                switch request.intent {
                case .collectionPaused(let paused): if paused || !failed { next.collectionPaused = paused }
                case .hidden(let hidden): if hidden || !failed { next.isHidden = hidden }
                case .entryEnabled(let enabled):
                    if !enabled || !failed { next.settings.entryEnabled = enabled }
                    next.settings.capturePreferencesSaveFailed = failed
                case .captureMode(let mode):
                    if !failed { next.settings.defaultCaptureMode = mode }
                    next.settings.capturePreferencesSaveFailed = failed
                case .arrival(let mode):
                    if !failed { next.settings.arrivalMode = mode; next.settings.hasArrivalSelection = true }
                case .archiveHours(let hours): if !failed { next.settings.archiveAfterHours = hours }
                case .layout, .placement, .display:
                    if !failed, let configuration = request.configuration {
                        next.settings.configuration = configuration
                        next.settings.preferredDisplayID = configuration.preferredDisplayID
                    }
                }
            }
            let receipt = value
            await beforeReturn?(request, receipt)
            return failed ? .unconfirmed(receipt, .writeUnconfirmed) : .confirmed(receipt)
        }
    }

    @MainActor private func model(_ owner: Owner, known: Bool = true) throws -> SettingsStateModel {
        try SettingsStateModel(owner: owner.value, confirmed: known ? owner.known : [:], decimalSeparator: ".", adapter: owner)
    }
    private func personalized() throws -> RiftConfiguration {
        // Real legacy Codable path; no alternate migration implementation.
        try JSONDecoder().decode(RiftConfiguration.self, from: Data(#"{"lineWidth":1.25,"lineExtension":13.5,"emptyTraceLength":37,"screenPadding":23,"arrivalDuration":0.33,"inwardDistance":2.75,"reducedMotionDuration":0.19,"preferredDisplayID":2,"preferredDisplayUUID":"02000000-0000-0000-0000-000000000002"}"#.utf8))
    }
    private func compatibility(_ c: RiftConfiguration) -> [Double] {
        [c.lineWidth, c.lineExtension, c.emptyTraceLength, c.screenPadding,
         c.arrivalDuration, c.inwardDistance, c.reducedMotionDuration]
    }

    @MainActor func testInitializationAndReadRefreshNeverInventConfirmationOrWrite() async throws {
        let owner = Owner(); let model = try model(owner, known: false)
        XCTAssertTrue(model.snapshot.domains.values.allSatisfy { $0.lastConfirmed == nil })
        owner.advance { $0.collectionPaused = true; $0.settings.entryEnabled = false }
        XCTAssertTrue(model.receive(owner.value))
        XCTAssertTrue(model.snapshot.owner.collectionPaused)
        XCTAssertFalse(model.snapshot.owner.settings.entryEnabled)
        XCTAssertTrue(model.snapshot.domains.values.allSatisfy { $0.lastConfirmed == nil })
        XCTAssertTrue(owner.requests.isEmpty)
        XCTAssertFalse(model.receive(owner.value), "Duplicate observations are not another revision")
    }

    @MainActor func testDirtyPatchUsesLatestOwnerFallbackAndCompatibilityWithoutLosingText() async throws {
        let owner = Owner(configuration: try personalized()); let model = try model(owner)
        await model.perform(.edit(.fitWidth, "96.250"))
        owner.advance { value in
            value.settings.configuration.fitHeight = 88
            value.settings.configuration.lineExtension = 27
            value.settings.configuration.placement = .rightBottom
            value.settings.configuration.placementSource = .user
            value.settings.displays.removeAll { $0.id == 2 }
            value.effectiveDisplayID = 1
            value.settings.displayRestoreAvailable = false
            value.collectionPaused = true
        }
        XCTAssertTrue(model.receive(owner.value))
        XCTAssertEqual(model.text(for: .fitWidth), "96.250")
        XCTAssertEqual(model.text(for: .fitHeight), "88.0")
        XCTAssertEqual(model.configurationDraft?.fitWidth, 96.25)
        XCTAssertEqual(model.configurationDraft?.fitHeight, 88)
        let latest = owner.value.settings.configuration
        let result = await model.perform(.applyLayout)
        XCTAssertEqual(result.confirmed, [.layout])
        let written = try XCTUnwrap(owner.requests.last?.configuration)
        XCTAssertEqual(written.fitWidth, 96.25); XCTAssertEqual(written.fitHeight, 88)
        XCTAssertEqual(compatibility(written), compatibility(latest))
        XCTAssertEqual(written.preferredDisplayID, 2, "A runtime fallback is not a persistent preference")
        XCTAssertEqual(written.preferredDisplayUUID, Owner.b)
        XCTAssertEqual(written.placement, .rightBottom); XCTAssertEqual(written.placementSource, .user)
        XCTAssertTrue(model.snapshot.owner.collectionPaused)
        XCTAssertEqual(owner.requests.count, 1)
    }

    @MainActor func testThreeUnconfirmedStopsRetainActualStateAndRetryOnlyOneTargetAtATime() async throws {
        let owner = Owner(); let model = try model(owner)
        owner.failures = [.collection, .visibility, .entry]
        await model.perform(.setCollectionPaused(true)); await model.perform(.setHidden(true)); await model.perform(.setEntryEnabled(false))
        var snapshot = model.snapshot
        XCTAssertTrue(snapshot.owner.collectionPaused); XCTAssertTrue(snapshot.owner.isHidden)
        XCTAssertFalse(snapshot.owner.settings.entryEnabled)
        XCTAssertEqual(snapshot.domains[.collection]?.lastConfirmed, .boolean(false))
        XCTAssertEqual(snapshot.domains[.visibility]?.lastConfirmed, .boolean(false))
        XCTAssertEqual(snapshot.domains[.entry]?.lastConfirmed, .boolean(true))
        XCTAssertEqual(snapshot.domains[.collection]?.pending, .collectionPaused(true))
        XCTAssertEqual(snapshot.domains[.entry]?.pending, .entryEnabled(false))
        XCTAssertEqual(snapshot.domains.values.filter { $0.saveFailure != nil }.count, 3)
        owner.failures = []
        let untouched = snapshot.domains[.collection]
        let retried = await model.perform(.retry(.visibility))
        XCTAssertEqual(retried.confirmed, [.visibility])
        snapshot = model.snapshot
        XCTAssertNil(snapshot.domains[.visibility]?.saveFailure)
        XCTAssertEqual(snapshot.domains[.visibility]?.lastConfirmed, .boolean(true))
        XCTAssertEqual(snapshot.domains[.collection], untouched)
        XCTAssertEqual(snapshot.domains[.entry]?.saveFailure, .writeUnconfirmed)
        XCTAssertEqual(owner.requests.last?.intent, .hidden(true))
        await model.perform(.retry(.entry)); await model.perform(.retry(.collection))
        XCTAssertFalse(model.snapshot.hasSaveIssues)
        XCTAssertEqual(owner.requests.map(\.intent), [.collectionPaused(true), .hidden(true), .entryEnabled(false),
                                                       .hidden(true), .entryEnabled(false), .collectionPaused(true)])
    }

    @MainActor func testFailedResumeDoesNotOptimisticallyChangeEffectiveState() async throws {
        let owner = Owner(); let model = try model(owner)
        await model.perform(.setCollectionPaused(true)); await model.perform(.setHidden(true)); await model.perform(.setEntryEnabled(false))
        owner.failures = [.collection, .visibility, .entry]
        await model.perform(.setCollectionPaused(false)); await model.perform(.setHidden(false)); await model.perform(.setEntryEnabled(true))
        XCTAssertTrue(model.snapshot.owner.collectionPaused); XCTAssertTrue(model.snapshot.owner.isHidden)
        XCTAssertFalse(model.snapshot.owner.settings.entryEnabled)
        XCTAssertEqual(model.snapshot.domains[.collection]?.lastConfirmed, .boolean(true))
        XCTAssertEqual(model.snapshot.domains[.collection]?.pending, .collectionPaused(false))
        owner.failures = []
        await model.perform(.retry(.collection)); await model.perform(.retry(.visibility)); await model.perform(.retry(.entry))
        XCTAssertFalse(model.snapshot.owner.collectionPaused); XCTAssertFalse(model.snapshot.owner.isHidden)
        XCTAssertTrue(model.snapshot.owner.settings.entryEnabled)
        XCTAssertEqual(Array(owner.requests.suffix(3)).map(\.intent), [.collectionPaused(false), .hidden(false), .entryEnabled(true)])
    }

    @MainActor func testUnrelatedSuccessAndObservationCannotClearLayoutFailure() async throws {
        let owner = Owner(); let model = try model(owner)
        owner.failures = [.layout]; await model.perform(.edit(.fitWidth, "96")); await model.perform(.applyLayout)
        let failure = model.snapshot.domains[.layout]
        await model.perform(.setHidden(true))
        owner.advance { $0.settings.displayRestoreAvailable = true }
        model.receive(owner.value)
        XCTAssertEqual(model.snapshot.domains[.layout], failure)
        XCTAssertEqual(model.text(for: .fitWidth), "96")
        XCTAssertEqual(model.snapshot.owner.settings.configuration.fitWidth, 72)
        XCTAssertTrue(model.snapshot.owner.settings.displayRestoreAvailable)
    }

    @MainActor func testApplyBothDraftsRetainsPartialSuccessAndDoesNotWriteSuccessfulDomainAgain() async throws {
        let owner = Owner(); let model = try model(owner)
        await model.perform(.edit(.fitWidth, "96")); await model.perform(.editArchive("2.5"))
        owner.failures = [.archive]
        let first = await model.perform(.applyDrafts)
        XCTAssertEqual(first.confirmed, [.layout]); XCTAssertEqual(first.failed, [.archive])
        XCTAssertFalse(model.hasLayoutDraft); XCTAssertTrue(model.hasArchiveDraft)
        XCTAssertEqual(model.snapshot.owner.settings.configuration.fitWidth, 96)
        XCTAssertEqual(model.snapshot.owner.settings.archiveAfterHours, 24)
        owner.failures = []
        let retried = await model.perform(.applyDrafts)
        XCTAssertEqual(retried.confirmed, [.archive])
        XCTAssertEqual(owner.requests.filter { $0.intent.domain == .layout }.count, 1)
        XCTAssertEqual(owner.requests.filter { $0.intent.domain == .archive }.count, 2)
        XCTAssertEqual(owner.requests.last?.intent.domain, .archive)
        XCTAssertEqual(model.snapshot.owner.settings.archiveAfterHours, 2.5)
        XCTAssertFalse(model.hasArchiveDraft); XCTAssertFalse(model.snapshot.hasSaveIssues)
    }

    @MainActor func testRetryKeepsOriginalPatchAndNewerDraftWhileRebasingUneditedOwnerFields() async throws {
        let owner = Owner(configuration: try personalized()); let model = try model(owner)
        owner.failures = [.layout]
        await model.perform(.edit(.fitWidth, "96")); await model.perform(.applyLayout)
        await model.perform(.edit(.fitWidth, "100.000"))
        owner.advance { $0.settings.configuration.fitHeight = 90; $0.settings.configuration.lineWidth = 2 }
        model.receive(owner.value); owner.failures = []
        await model.perform(.retry(.layout))
        XCTAssertEqual(owner.requests.last?.configuration?.fitWidth, 96, "Retry is the pending target, not a new form submission")
        XCTAssertEqual(owner.requests.last?.configuration?.fitHeight, 90)
        XCTAssertEqual(owner.requests.last?.configuration?.lineWidth, 2)
        XCTAssertEqual(model.text(for: .fitWidth), "100.000"); XCTAssertTrue(model.hasLayoutDraft)
        await model.perform(.applyLayout)
        XCTAssertEqual(owner.requests.last?.configuration?.fitWidth, 100)
        XCTAssertEqual(owner.requests.last?.configuration?.fitHeight, 90)
        XCTAssertEqual(owner.requests.last?.configuration?.lineWidth, 2)
    }

    @MainActor func testDiscardOnlyRemovesDraftErrorsNotFailedControlIntents() async throws {
        let owner = Owner(); let model = try model(owner)
        owner.failures = [.collection, .layout, .archive]
        await model.perform(.setCollectionPaused(true)); await model.perform(.edit(.fitWidth, "96"))
        await model.perform(.editArchive("3")); await model.perform(.applyDrafts)
        let control = model.snapshot.domains[.collection]
        await model.perform(.discardLayout)
        XCTAssertNil(model.snapshot.domains[.layout]?.saveFailure)
        XCTAssertEqual(model.snapshot.domains[.archive]?.saveFailure, .writeUnconfirmed)
        await model.perform(.discardDrafts)
        XCTAssertNil(model.snapshot.domains[.archive]?.saveFailure)
        XCTAssertEqual(model.snapshot.domains[.collection], control)
        XCTAssertTrue(model.snapshot.owner.collectionPaused)
        XCTAssertEqual(model.snapshot.domains[.layout]?.lastConfirmed, .configuration(RiftConfiguration()))
    }

    @MainActor func testPageDefaultsAndApplicationKeepSevenPersonalizedCompatibilityValues() async throws {
        let configuration = try personalized()
        XCTAssertNil(configuration.placement); XCTAssertEqual(configuration.outerInset, 14)
        let owner = Owner(configuration: configuration); let model = try model(owner)
        await model.perform(.edit(.fitWidth, "96")); await model.perform(.edit(.returnDuration, "240")); await model.perform(.applyLayout)
        for page in [SettingsDraftPage.display, .motion] {
            await model.perform(.restoreDefaults(page)); await model.perform(.applyLayout)
            XCTAssertEqual(compatibility(owner.value.settings.configuration), compatibility(configuration))
            XCTAssertEqual(owner.value.settings.configuration.preferredDisplayID, 2)
            XCTAssertEqual(owner.value.settings.configuration.preferredDisplayUUID, Owner.b)
            XCTAssertNil(owner.value.settings.configuration.placement)
            XCTAssertEqual(owner.value.settings.configuration.placementSource, .legacy)
        }
        XCTAssertEqual(owner.value.settings.configuration.hiddenFraction, 0.25, "Restore uses actual main defaults, not the 0% design recommendation")
        XCTAssertEqual(owner.value.settings.configuration.fitWidth, 72)
        XCTAssertEqual(owner.value.settings.configuration.returnDuration, 0.18)
    }

    @MainActor func testPrimaryChoiceIsConcreteAndFallbackObservationNeverPersists() async throws {
        let owner = Owner(configuration: try personalized()); let model = try model(owner)
        await model.perform(.edit(.fitWidth, "96"))
        owner.advance { value in
            value.settings.displays.removeAll { $0.id == 2 }; value.effectiveDisplayID = 1
            value.settings.displayRestoreAvailable = false
        }
        model.receive(owner.value)
        XCTAssertEqual(model.snapshot.owner.settings.configuration.preferredDisplayID, 2)
        XCTAssertTrue(owner.requests.isEmpty)
        await model.perform(.selectDisplay(nil))
        XCTAssertEqual(owner.requests.last?.intent, .display(.init(id: 1, uuid: Owner.a)))
        await model.perform(.applyLayout)
        XCTAssertEqual(owner.value.settings.configuration.preferredDisplayID, 1)
        XCTAssertEqual(owner.value.settings.configuration.preferredDisplayUUID, Owner.a)
        XCTAssertEqual(owner.value.settings.configuration.fitWidth, 96)
        XCTAssertEqual(compatibility(owner.value.settings.configuration), compatibility(try personalized()))
    }

    @MainActor func testInvalidTextStaysEditableAndNeverCallsAdapter() async throws {
        let owner = Owner(); let model = try model(owner)
        for text in ["", ".", "NaN", "Infinity", "-1", "257", "1abc"] {
            await model.perform(.edit(.fitWidth, text)); await model.perform(.applyLayout)
            XCTAssertEqual(model.text(for: .fitWidth), text)
            XCTAssertNotNil(model.snapshot.domains[.layout]?.validationFailure)
        }
        await model.perform(.discardLayout)
        await model.perform(.edit(.visibleCountPreference, "3.5")); await model.perform(.applyLayout)
        XCTAssertTrue(owner.requests.isEmpty)
        await model.perform(.discardDrafts)
        for text in ["", "-1", "Infinity", "1e309", "1abc"] {
            await model.perform(.editArchive(text)); await model.perform(.applyArchive)
            XCTAssertEqual(model.archiveDraftText, text)
        }
        XCTAssertTrue(owner.requests.isEmpty)
        await model.perform(.editArchive("0")); await model.perform(.applyArchive)
        XCTAssertNil(owner.value.settings.archiveAfterHours)
        XCTAssertNil(model.snapshot.archiveText); XCTAssertFalse(model.hasArchiveDraft)
        await model.perform(.applyArchive)
        XCTAssertEqual(owner.requests.count, 1, "Already saved disabled archive is not written again")
    }

    @MainActor func testLocaleUnitsFractionalArchiveAndExplicitNoneSelection() async throws {
        let owner = Owner()
        let model = try SettingsStateModel(owner: owner.value, confirmed: owner.known, decimalSeparator: ",", adapter: owner)
        await model.perform(.edit(.hiddenFraction, "12,5")); await model.perform(.edit(.swallowDuration, "40")); await model.perform(.applyLayout)
        XCTAssertEqual(owner.value.settings.configuration.hiddenFraction, 0.125)
        XCTAssertEqual(owner.value.settings.configuration.swallowDuration, 0.04)
        await model.perform(.editArchive("0,011")); await model.perform(.applyArchive); await model.perform(.applyArchive)
        XCTAssertEqual(owner.requests.filter { $0.intent.domain == .archive }.count, 1)
        XCTAssertEqual(owner.value.settings.archiveAfterHours, (0.011 * 3600) / 3600)
        XCTAssertFalse(owner.value.settings.hasArrivalSelection)
        await model.perform(.setArrival(.none))
        XCTAssertTrue(owner.value.settings.hasArrivalSelection, "Fallback none is not an already-saved explicit none")
    }

    @MainActor func testNonthrowingOwnerFailureCannotBeMistakenForConfirmation() async throws {
        let initial = Owner().value
        let adapter = SettingsPersistenceClosures { _ in
            var settings = initial.settings; settings.entryEnabled = false; settings.capturePreferencesSaveFailed = true
            // Deliberately broken integration: the model must not bless this as saved.
            return .confirmed(.init(revision: 2, settings: settings, collectionPaused: false, isHidden: false))
        }
        let model = try SettingsStateModel(owner: initial, confirmed: [.entry: .boolean(true)], adapter: adapter)
        let result = await model.perform(.setEntryEnabled(false))
        XCTAssertEqual(result.failed, [.entry])
        XCTAssertFalse(model.snapshot.owner.settings.entryEnabled)
        XCTAssertEqual(model.snapshot.domains[.entry]?.saveFailure, .confirmationMismatch)
        XCTAssertEqual(model.snapshot.domains[.entry]?.lastConfirmed, .boolean(true))
    }

    @MainActor func testLaterObservationIsNotOverwrittenByEarlierValidReceipt() async throws {
        let owner = Owner(); let model = try model(owner)
        defer { owner.beforeReturn = nil }
        owner.beforeReturn = { _, _ in
            owner.advance { $0.settings.configuration.fitHeight = 90 }
            XCTAssertTrue(model.receive(owner.value))
        }
        await model.perform(.edit(.fitWidth, "96")); await model.perform(.applyLayout)
        XCTAssertNil(model.snapshot.domains[.layout]?.saveFailure)
        XCTAssertEqual(model.snapshot.owner.settings.configuration.fitHeight, 90)
        var confirmed = RiftConfiguration(); confirmed.fitWidth = 96
        XCTAssertEqual(model.snapshot.domains[.layout]?.lastConfirmed, .configuration(confirmed))
        XCTAssertEqual(model.text(for: .fitWidth), "96.0")
        XCTAssertEqual(owner.requests.count, 1)
    }

    @MainActor func testAdapterReentrancyCannotDuplicateTheSameOwnerWrite() async throws {
        let owner = Owner(); let model = try model(owner)
        defer { owner.beforeReturn = nil }
        owner.beforeReturn = { _, _ in
            let nested = await model.perform(.setHidden(true))
            XCTAssertEqual(nested.busy, [.visibility])
        }
        let result = await model.perform(.setHidden(true))
        XCTAssertEqual(result.confirmed, [.visibility])
        XCTAssertEqual(owner.requests.count, 1)
        XCTAssertFalse(model.snapshot.domains[.visibility]!.isSaving)
    }

    @MainActor func testDelayedLayoutKeepsNewRawEditsAndDoesNotBlockIndependentOwners() async throws {
        let owner = Owner(); let model = try model(owner); let gate = Gate()
        owner.beforeReturn = { request, _ in if request.intent.domain == .layout { await gate.suspend() } }
        defer { gate.release(); owner.beforeReturn = nil }
        await model.perform(.edit(.fitWidth, "96"))
        let saving = Task { await model.perform(.applyLayout) }
        await fulfillment(of: [gate.entered], timeout: 5)
        guard gate.isSuspended else { return }
        XCTAssertTrue(model.snapshot.domains[.layout]!.isSaving)
        await model.perform(.edit(.fitWidth, "NaN"))
        let stillBusy = await model.perform(.applyLayout)
        XCTAssertEqual(stillBusy.busy, [.layout]); XCTAssertTrue(stillBusy.failed.isEmpty)
        await model.perform(.edit(.fitWidth, "96.000"))
        await model.perform(.edit(.fitHeight, "70"))
        let duplicate = await model.perform(.retry(.layout))
        let overlappingFile = await model.perform(.selectDisplay(2))
        XCTAssertEqual(duplicate.busy, [.layout]); XCTAssertEqual(overlappingFile.busy, [.display])
        XCTAssertEqual(owner.requests.count, 1, "Same config writer is not queued or replayed")
        let hidden = await model.perform(.setHidden(true))
        await model.perform(.editArchive("3"))
        let archive = await model.perform(.applyArchive)
        XCTAssertEqual(hidden.confirmed, [.visibility]); XCTAssertEqual(archive.confirmed, [.archive])
        XCTAssertTrue(model.snapshot.owner.isHidden)
        let latestRevision = model.snapshot.owner.revision
        gate.release()
        let result = await saving.value
        XCTAssertEqual(result.confirmed, [.layout]); XCTAssertTrue(result.failed.isEmpty)
        XCTAssertEqual(model.snapshot.owner.revision, latestRevision, "An earlier receipt cannot restore an old cross-domain snapshot")
        XCTAssertTrue(model.snapshot.owner.isHidden); XCTAssertEqual(model.snapshot.owner.settings.archiveAfterHours, 3)
        XCTAssertEqual(model.text(for: .fitWidth), "96.000", "Equal numeric value does not permit clearing a newer edit")
        XCTAssertEqual(model.text(for: .fitHeight), "70")
        XCTAssertEqual(model.configurationDraft?.fitHeight, 70)
        XCTAssertFalse(model.snapshot.domains[.layout]!.isSaving)
        XCTAssertEqual(owner.requests.count, 3)
    }

    @MainActor func testDelayedFailureAndCrossDomainSuccessRemainIndependent() async throws {
        let owner = Owner(); let model = try model(owner); let gate = Gate()
        owner.failures = [.collection]
        owner.beforeReturn = { request, _ in if request.intent.domain == .collection { await gate.suspend() } }
        defer { gate.release(); owner.beforeReturn = nil }
        let stopping = Task { await model.perform(.setCollectionPaused(true)) }
        await fulfillment(of: [gate.entered], timeout: 5)
        guard gate.isSuspended else { return }
        XCTAssertTrue(model.receive(owner.value), "The stopped runtime can be observed before persistence completes")
        XCTAssertTrue(model.snapshot.owner.collectionPaused)
        XCTAssertEqual(model.snapshot.domains[.collection]?.lastConfirmed, .boolean(false))
        let reverse = await model.perform(.setCollectionPaused(false))
        XCTAssertEqual(reverse.busy, [.collection])
        let entry = await model.perform(.setEntryEnabled(false))
        XCTAssertEqual(entry.confirmed, [.entry])
        gate.release()
        let result = await stopping.value
        XCTAssertEqual(result.failed, [.collection])
        XCTAssertEqual(model.snapshot.domains[.collection]?.saveFailure, .writeUnconfirmed)
        XCTAssertEqual(model.snapshot.domains[.collection]?.pending, .collectionPaused(true))
        XCTAssertEqual(model.snapshot.domains[.entry]?.lastConfirmed, .boolean(false))
        XCTAssertNil(model.snapshot.domains[.entry]?.saveFailure)
        XCTAssertFalse(model.snapshot.owner.settings.entryEnabled)
        owner.beforeReturn = nil; owner.failures = []
        let retried = await model.perform(.retry(.collection))
        XCTAssertEqual(retried.confirmed, [.collection])
        XCTAssertEqual(owner.requests.map(\.intent), [.collectionPaused(true), .entryEnabled(false), .collectionPaused(true)])
    }

    @MainActor func testApplyBothFreezesArchiveIntentBeforeLayoutAwait() async throws {
        let owner = Owner(); let model = try model(owner); let gate = Gate(); let archiveGate = Gate()
        owner.beforeReturn = { request, _ in
            if request.intent.domain == .layout { await gate.suspend() }
            if request.intent.domain == .archive { await archiveGate.suspend() }
        }
        defer { gate.release(); archiveGate.release(); owner.beforeReturn = nil }
        await model.perform(.edit(.fitWidth, "96")); await model.perform(.editArchive("2.5"))
        let saving = Task { await model.perform(.applyDrafts) }
        await fulfillment(of: [gate.entered, archiveGate.entered], timeout: 5)
        guard gate.isSuspended, archiveGate.isSuspended else { return }
        XCTAssertTrue(model.snapshot.domains[.layout]!.isSaving)
        XCTAssertTrue(model.snapshot.domains[.archive]!.isSaving)
        await model.perform(.editArchive("4.125"))
        let concurrentApply = await model.perform(.applyArchive)
        XCTAssertEqual(concurrentApply.busy, [.archive])
        gate.release(); archiveGate.release()
        let result = await saving.value
        XCTAssertEqual(result.confirmed, [.layout, .archive])
        XCTAssertEqual(owner.requests.last { $0.intent.domain == .archive }?.intent, .archiveHours(2.5))
        XCTAssertEqual(model.snapshot.owner.settings.archiveAfterHours, 2.5)
        XCTAssertEqual(model.archiveDraftText, "4.125")
        XCTAssertTrue(model.hasArchiveDraft)
        await model.perform(.applyArchive)
        XCTAssertEqual(owner.requests.last?.intent, .archiveHours(4.125))
        XCTAssertFalse(model.hasArchiveDraft)
    }

    @MainActor func testReceiptMustAdvancePastItsOwnRequestObservation() async throws {
        let initial = Owner().value
        let adapter = SettingsPersistenceClosures { _ in .confirmed(initial) }
        let model = try SettingsStateModel(owner: initial, confirmed: [.visibility: .boolean(false)], adapter: adapter)
        let result = await model.perform(.setHidden(true))
        XCTAssertEqual(result.failed, [.visibility])
        XCTAssertEqual(model.snapshot.domains[.visibility]?.saveFailure, .staleReceipt)
        XCTAssertEqual(model.snapshot.domains[.visibility]?.pending, .hidden(true))
        XCTAssertEqual(model.snapshot.domains[.visibility]?.lastConfirmed, .boolean(false))
        XCTAssertFalse(model.snapshot.owner.isHidden)
    }

    @MainActor func testConfigReceiptCanPreserveNewOwnerFieldsWhileConfirmingRequestedPatch() async throws {
        let owner = Owner(configuration: try personalized()); let gate = Gate()
        let adapter = SettingsPersistenceClosures { request in
            await gate.suspend()
            // A hypothetical async config owner must rebase at the actual write,
            // just as this synthetic owner does; it cannot blindly use an old copy.
            owner.advance { $0.settings.configuration.fitWidth = request.configuration!.fitWidth }
            return .confirmed(owner.value)
        }
        let model = try SettingsStateModel(owner: owner.value, confirmed: owner.known, adapter: adapter)
        defer { gate.release() }
        await model.perform(.edit(.fitWidth, "96"))
        let saving = Task { await model.perform(.applyLayout) }
        await fulfillment(of: [gate.entered], timeout: 5)
        guard gate.isSuspended else { return }
        owner.advance { $0.settings.configuration.fitHeight = 90; $0.settings.configuration.lineWidth = 2 }
        model.receive(owner.value)
        gate.release()
        let result = await saving.value
        XCTAssertEqual(result.confirmed, [.layout])
        XCTAssertEqual(model.snapshot.owner.settings.configuration.fitWidth, 96)
        XCTAssertEqual(model.snapshot.owner.settings.configuration.fitHeight, 90)
        XCTAssertEqual(model.snapshot.owner.settings.configuration.lineWidth, 2)
        XCTAssertEqual(model.snapshot.domains[.layout]?.lastConfirmed, .configuration(owner.value.settings.configuration))
    }

    @MainActor func testUnconfirmedEffectiveValueDoesNotProveWhatReachedDisk() async throws {
        let initial = Owner().value
        let adapter = SettingsPersistenceClosures { _ in
            var settings = initial.settings; settings.configuration.fitWidth = 96
            return .unconfirmed(.init(revision: 2, settings: settings, collectionPaused: false, isHidden: false), .writeUnconfirmed)
        }
        let model = try SettingsStateModel(owner: initial,
            confirmed: [.layout: .configuration(initial.settings.configuration)], adapter: adapter)
        await model.perform(.edit(.fitWidth, "96")); await model.perform(.applyLayout)
        XCTAssertEqual(model.snapshot.owner.settings.configuration.fitWidth, 96)
        XCTAssertEqual(model.snapshot.domains[.layout]?.lastConfirmed, .configuration(initial.settings.configuration))
        XCTAssertEqual(model.snapshot.domains[.layout]?.pending, .layout([.fitWidth: 96]))
        XCTAssertEqual(model.snapshot.domains[.layout]?.saveFailure, .writeUnconfirmed)
    }
}
