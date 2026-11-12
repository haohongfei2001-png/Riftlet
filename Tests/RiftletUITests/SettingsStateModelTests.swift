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

        init(configuration: RiftConfiguration = .init(), archive: Double? = QueueArchivePolicy.defaultMinutes) {
            value = SettingsOwnerSnapshot(revision: 1,
                settings: RiftSettingsSnapshot(entryAvailable: true, displays: [
                    .init(id: 1, name: "Synthetic A", uuid: Self.a),
                    .init(id: 2, name: "Synthetic B", uuid: Self.b)
                ], archiveAfterMinutes: archive, configuration: configuration),
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
             .archive: .archiveMinutes(value.settings.archiveAfterMinutes)]
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
                case .archiveMinutes(let minutes): if !failed { next.settings.archiveAfterMinutes = minutes }
                case .layout, .placement, .display, .desktopForm, .windChimeArrangement, .trayTheme, .trayFollowsSaytile, .trayFavorite:
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

    @MainActor func testOwnerNumbersUseWholeNumberDisplayWithoutLosingFractionalPrecision() throws {
        var configuration = RiftConfiguration()
        configuration.fitWidth = 72.125
        let owner = Owner(configuration: configuration)
        let model = try SettingsStateModel(owner: owner.value, decimalSeparator: ",", adapter: owner)
        XCTAssertEqual(model.text(for: .visibleCountPreference), "3")
        XCTAssertEqual(model.text(for: .fitWidth), "72,125")
        XCTAssertEqual(model.archiveDraftText, "2")
        XCTAssertTrue(owner.requests.isEmpty)
    }

    @MainActor func testCompactOwnerFormattingNeverNormalizesActiveDraftsOnRefresh() async throws {
        let owner = Owner()
        let model = try SettingsStateModel(owner: owner.value, decimalSeparator: ",", adapter: owner)
        model.setDraftText("3,0", for: .visibleCountPreference)
        model.setDraftText("72,", for: .fitWidth)
        model.setArchiveDraftText("2,500")
        owner.advance { value in
            value.settings.configuration.visibleCountPreference = 4
            value.settings.configuration.fitWidth = 84
            value.settings.archiveAfterMinutes = 8
        }
        XCTAssertTrue(model.receive(owner.value))
        XCTAssertEqual(model.text(for: .visibleCountPreference), "3,0")
        XCTAssertEqual(model.text(for: .fitWidth), "72,")
        XCTAssertEqual(model.archiveDraftText, "2,500")
        XCTAssertTrue(model.hasLayoutDraft)
        XCTAssertTrue(model.hasArchiveDraft)
        XCTAssertTrue(owner.requests.isEmpty)
        await model.perform(.discardDrafts)
        XCTAssertEqual(model.text(for: .visibleCountPreference), "4")
        XCTAssertEqual(model.text(for: .fitWidth), "84")
        XCTAssertEqual(model.archiveDraftText, "8")
        XCTAssertTrue(owner.requests.isEmpty)
    }
    @MainActor func testPresentationPersistsImmediatelyWithoutConsumingLayoutDrafts() async throws {
        let owner = Owner()
        let model = try model(owner)
        model.setDraftText("87", for: .fitWidth)
        let changed = await model.perform(.selectDesktopForm(.tray))
        XCTAssertEqual(changed.confirmed, [.desktopForm])
        XCTAssertEqual(owner.value.settings.configuration.desktopForm, .tray)
        XCTAssertTrue(model.hasLayoutDraft)
        owner.failures.insert(.trayTheme)
        let failed = await model.perform(.selectTrayTheme(.violetGlass))
        XCTAssertEqual(failed.failed, [.trayTheme])
        _ = await model.perform(.selectDesktopForm(.microSlit))
        XCTAssertNotNil(model.snapshot.domains[.trayTheme]?.saveFailure)
        owner.failures.remove(.trayTheme)
        let retry = await model.perform(.retry(.trayTheme))
        XCTAssertEqual(retry.confirmed, [.trayTheme])
        XCTAssertEqual(owner.value.settings.configuration.desktopForm, .microSlit)
        XCTAssertEqual(owner.value.settings.configuration.trayTheme, .violetGlass)
        _ = await model.perform(.applyLayout)
        XCTAssertEqual(owner.value.settings.configuration.fitWidth, 87)
        XCTAssertEqual(owner.value.settings.configuration.desktopForm, .microSlit)
    }

    func testRetiredFormsResolveToTrayWithoutRewritingOriginalValue() throws {
        XCTAssertEqual(RiftDesktopForm.allCases, [.tray, .windChime, .microSlit])
        for raw in ["edgefolio", "pocket", "microSlit"] {
            let data = try JSONSerialization.data(withJSONObject: ["desktopForm": raw, "rowPitch": 60])
            var configuration = try JSONDecoder().decode(RiftConfiguration.self, from: data)
            XCTAssertEqual(configuration.desktopForm, raw == "microSlit" ? .microSlit : .tray)
            configuration.outerInset = 19
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(configuration)) as? [String: Any])
            XCTAssertEqual(json["desktopForm"] as? String, raw)
            XCTAssertEqual(json["outerInset"] as? Int, 19)
        }
    }

    func testPresentationFallbackPreservesUnrecognizedSelections() throws {
        for raw in [#""future-form""#, #"{"version":3,"names":["x"]}"#, "null"] {
            let source = Data("{\"desktopForm\":\(raw),\"trayTheme\":\"future-glass\",\"trayOcclusion\":1.6,\"emptyTraceLength\":33}".utf8)
            var value = try JSONDecoder().decode(RiftConfiguration.self, from: source)
            XCTAssertEqual(value.desktopForm, .microSlit)
            XCTAssertEqual(value.trayTheme, .system)
            XCTAssertEqual(value.trayOcclusion, 0)
            value.outerInset = 19
            let saved = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? NSDictionary)
            let original = try XCTUnwrap(JSONSerialization.jsonObject(with: source) as? NSDictionary)
            for key in ["desktopForm", "trayTheme", "trayOcclusion", "emptyTraceLength"] {
                XCTAssertEqual(saved[key] as? NSObject, original[key] as? NSObject)
            }
        }
    }

    func testStoredWindChimeIsRestoredAndUnknownArrangementSurvivesUnrelatedSaves() throws {
        let legacy = try JSONDecoder().decode(RiftConfiguration.self, from: Data(#"{"desktopForm":"windChime"}"#.utf8))
        XCTAssertEqual(legacy.desktopForm, .windChime)
        XCTAssertEqual(legacy.windChimeArrangement, .aligned)
        var switched = legacy
        switched.desktopForm = .microSlit
        switched = try JSONDecoder().decode(RiftConfiguration.self, from: JSONEncoder().encode(switched))
        switched.desktopForm = .windChime
        XCTAssertEqual(switched.windChimeArrangement, .aligned)
        var fresh = RiftConfiguration()
        fresh.desktopForm = .windChime
        XCTAssertEqual(fresh.windChimeArrangement, .staggered)
        XCTAssertEqual(fresh.windChimeLineInset, 18)
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as? NSDictionary)
        XCTAssertNil(original["windChimeArrangement"])
        for raw in [#""future""#, #"{"axis":[1,2]}"#, "null"] {
            let source = Data("{\"desktopForm\":\"windChime\",\"windChimeArrangement\":\(raw)}".utf8)
            var config = try JSONDecoder().decode(RiftConfiguration.self, from: source)
            XCTAssertEqual(config.windChimeArrangement, .staggered)
            config.desktopForm = .tray
            let saved = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(config)) as? NSDictionary)
            let input = try XCTUnwrap(JSONSerialization.jsonObject(with: source) as? NSDictionary)
            XCTAssertEqual(saved["windChimeArrangement"] as? NSObject, input["windChimeArrangement"] as? NSObject)
            config.windChimeArrangement = .aligned
            let reopened = try JSONDecoder().decode(RiftConfiguration.self, from: JSONEncoder().encode(config))
            XCTAssertEqual(reopened.windChimeArrangement, .aligned)
            XCTAssertEqual(reopened.desktopForm, .tray)
        }
    }

    @MainActor func testWindChimeArrangementRetryRebasesWithoutSwitchingFormOrApplyingDraft() async throws {
        let owner = Owner()
        let model = try model(owner)
        _ = await model.perform(.selectDesktopForm(.windChime))
        model.setDraftText("88", for: .fitWidth)
        owner.failures.insert(.windChimeArrangement)
        let failed = await model.perform(.selectWindChimeArrangement(.aligned))
        XCTAssertEqual(failed.failed, [.windChimeArrangement])
        XCTAssertEqual(owner.value.settings.configuration.windChimeArrangement, .staggered)
        _ = await model.perform(.selectDesktopForm(.microSlit))
        XCTAssertEqual(model.snapshot.domains[.windChimeArrangement]?.pending, .windChimeArrangement(.aligned))
        owner.failures.remove(.windChimeArrangement)
        let retry = await model.perform(.retry(.windChimeArrangement))
        XCTAssertEqual(retry.confirmed, [.windChimeArrangement])
        XCTAssertEqual(owner.value.settings.configuration.desktopForm, .microSlit)
        XCTAssertEqual(owner.value.settings.configuration.windChimeArrangement, .aligned)
        XCTAssertEqual(owner.value.settings.configuration.fitWidth, 72)
        XCTAssertEqual(model.text(for: .fitWidth), "88")
    }

    @MainActor func testWindChimeLineInsetRetainsSeparateDraftAndRetriedTarget() async throws {
        let owner = Owner()
        let model = try model(owner)
        model.setDraftText("24", for: .outerInset)
        _ = await model.perform(.selectDesktopForm(.windChime))
        XCTAssertEqual(model.text(for: .windChimeLineInset), "18")
        model.setDraftText("29", for: .windChimeLineInset)
        XCTAssertEqual(model.configurationDraft?.windChimeLineInset, 29)
        XCTAssertEqual(model.configurationDraft?.outerInset, 6)
        owner.failures.insert(.layout)
        let failed = await model.perform(.applyLayout)
        XCTAssertEqual(failed.failed, [.layout])
        _ = await model.perform(.selectDesktopForm(.microSlit))
        owner.failures.remove(.layout)
        let retried = await model.perform(.retry(.layout))
        XCTAssertEqual(retried.confirmed, [.layout])
        XCTAssertEqual(owner.value.settings.configuration.windChimeLineInset, 29)
        XCTAssertEqual(owner.value.settings.configuration.outerInset, 6)
        XCTAssertEqual(model.text(for: .outerInset), "24")
        _ = await model.perform(.applyLayout)
        XCTAssertEqual(owner.value.settings.configuration.outerInset, 24)
        _ = await model.perform(.selectDesktopForm(.windChime))
        _ = await model.perform(.restoreDefaults(.display))
        _ = await model.perform(.applyLayout)
        XCTAssertEqual(owner.value.settings.configuration.windChimeLineInset, 18)
        XCTAssertEqual(owner.value.settings.configuration.outerInset, 24)
        let disk = try JSONEncoder().encode(owner.value.settings.configuration)
        let reopened = try JSONDecoder().decode(RiftConfiguration.self, from: disk)
        XCTAssertEqual(reopened, owner.value.settings.configuration)
    }

    func testPresentationSettingsRoundTripAndPreserveLegacyDefaults() throws {
        var config = try JSONDecoder().decode(RiftConfiguration.self, from: Data("{}".utf8))
        XCTAssertEqual(config.desktopForm, .microSlit)
        XCTAssertEqual(config.hiddenFraction, 0.25)
        XCTAssertEqual(config.trayOcclusion, 0)
        config.trayTheme = .violetGlass
        config.trayOcclusion = 0.29
        for form in RiftDesktopForm.allCases where form.isAvailable {
            config.desktopForm = form
            let decoded = try JSONDecoder().decode(RiftConfiguration.self, from: JSONEncoder().encode(config))
            XCTAssertEqual(decoded.desktopForm, form)
            XCTAssertEqual(decoded.trayTheme, .violetGlass)
            XCTAssertEqual(decoded.trayOcclusion, 0.29)
            XCTAssertEqual(decoded.hiddenFraction, 0.25)
            XCTAssertNil(decoded.placement)
        }
    }

    @MainActor func testTraySizeOffsetsAndFollowPersistAndRetryTheirOriginalIntent() async throws {
        let owner = Owner()
        let model = try model(owner)
        await model.perform(.selectDesktopForm(.tray))
        model.setDraftText("135", for: .trayScalePercent)
        model.setDraftText("-28", for: .trayHorizontalOffset)
        model.setDraftText("+43", for: .trayVerticalOffset)
        model.setDraftText("16", for: .trayCompanionGap)
        XCTAssertEqual(model.configurationDraft?.trayHorizontalOffset, -28)
        XCTAssertEqual(owner.value.settings.configuration.trayScalePercent, 100)
        let saved = await model.perform(.applyLayout)
        XCTAssertEqual(saved.confirmed, [.layout])
        XCTAssertTrue(model.snapshot.layoutText.isEmpty)

        owner.failures.insert(.trayFollowsSaytile)
        let failed = await model.perform(.setTrayFollowsSaytile(false))
        XCTAssertEqual(failed.failed, [.trayFollowsSaytile])
        XCTAssertTrue(owner.value.settings.configuration.trayFollowsSaytile)
        await model.perform(.selectTrayTheme(.violetGlass))
        XCTAssertNotNil(model.snapshot.domains[.trayFollowsSaytile]?.saveFailure)
        owner.failures.remove(.trayFollowsSaytile)
        let retried = await model.perform(.retry(.trayFollowsSaytile))
        XCTAssertEqual(retried.confirmed, [.trayFollowsSaytile])

        let data = try JSONEncoder().encode(owner.value.settings.configuration)
        let reopened = try JSONDecoder().decode(RiftConfiguration.self, from: data)
        XCTAssertFalse(reopened.trayFollowsSaytile)
        XCTAssertEqual(reopened.trayScalePercent, 135)
        XCTAssertEqual(reopened.trayHorizontalOffset, -28)
        XCTAssertEqual(reopened.trayVerticalOffset, 43)
        XCTAssertEqual(reopened.trayCompanionGap, 16)
        XCTAssertEqual(reopened.trayTheme, .violetGlass)
    }

    @MainActor func testTrayBoundsAndHiddenCompanionGapDoNotBlockStandaloneEdits() async throws {
        let owner = Owner()
        let model = try model(owner)
        await model.perform(.selectDesktopForm(.tray))
        for (field, text) in [(SettingsField.trayScalePercent, "161"), (.trayHorizontalOffset, "-257"),
                              (.trayVerticalOffset, "257"), (.trayCompanionGap, "97")] {
            model.setDraftText(text, for: field)
            let result = await model.perform(.applyLayout)
            XCTAssertEqual(result.failed, [.layout])
            XCTAssertEqual(model.snapshot.domains[.layout]?.validationFailure, .invalidNumber(field))
            await model.perform(.discardLayout)
        }
        model.setDraftText("97", for: .trayCompanionGap)
        await model.perform(.setTrayFollowsSaytile(false))
        model.setDraftText("-8", for: .trayVerticalOffset)
        let saved = await model.perform(.applyLayout)
        XCTAssertEqual(saved.confirmed, [.layout])
        XCTAssertEqual(owner.value.settings.configuration.trayCompanionGap, 10)
        XCTAssertEqual(owner.value.settings.configuration.trayVerticalOffset, -8)
        await model.perform(.setTrayFollowsSaytile(true))
        XCTAssertEqual(model.snapshot.domains[.layout]?.validationFailure, .invalidNumber(.trayCompanionGap))
        await model.perform(.restoreDefaults(.display))
        await model.perform(.applyLayout)
        XCTAssertEqual(owner.value.settings.configuration.trayVerticalOffset, 0)
    }

    func testLegacyAndUnknownTrayPlacementValuesRoundTrip() throws {
        let expectedDefaults = RiftConfiguration()
        XCTAssertTrue(expectedDefaults.trayFollowsSaytile)
        XCTAssertEqual(expectedDefaults.trayScalePercent, 100)
        XCTAssertEqual(expectedDefaults.trayCompanionGap, 10)
        let input = #"{"trayScalePercent":"future","trayFollowsSaytile":{"version":2},"trayCompanionGap":-4,"trayHorizontalOffset":999}"#
        var config = try JSONDecoder().decode(RiftConfiguration.self, from: Data(input.utf8))
        XCTAssertTrue(config.trayFollowsSaytile)
        XCTAssertEqual(config.trayHorizontalOffset, 0)
        XCTAssertEqual(config.trayVerticalOffset, 0)
        XCTAssertEqual(config.trayCompanionGap, 10)
        XCTAssertEqual(config.trayScalePercent, 100)
        config.outerInset = 21
        let stored = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(config)) as? NSDictionary)
        XCTAssertEqual(stored["trayFollowsSaytile"] as? NSDictionary, ["version": 2])
        XCTAssertEqual(stored["trayScalePercent"] as? String, "future")
        XCTAssertEqual(stored["trayCompanionGap"] as? Int, -4)
        XCTAssertEqual(stored["trayHorizontalOffset"] as? Int, 999)
        XCTAssertNil(stored["trayVerticalOffset"])
    }

    @MainActor func testCustomTintValidatesSavesAndReopensWithoutLosingPresetOrOtherSettings() async throws {
        let owner = Owner()
        let model = try model(owner)
        _ = await model.perform(.selectDesktopForm(.tray))
        _ = await model.perform(.selectTrayTheme(.custom))
        model.setDraftText("145", for: .trayTintHue)
        model.setDraftText("101", for: .trayTintStrength)
        _ = await model.perform(.applyLayout)
        XCTAssertEqual(owner.value.settings.configuration.trayTintHue, 255)
        XCTAssertTrue(model.hasLayoutDraft)

        model.setDraftText("42", for: .trayTintStrength)
        owner.failures.insert(.layout)
        let failed = await model.perform(.applyLayout)
        XCTAssertEqual(failed.failed, [.layout])
        _ = await model.perform(.selectTrayTheme(.system))
        XCTAssertEqual(model.text(for: .trayTintHue), "145")
        XCTAssertEqual(model.text(for: .trayTintStrength), "42")
        XCTAssertTrue(model.snapshot.domains[.layout]?.saveFailure != nil)
        _ = await model.perform(.selectTrayTheme(.custom))
        owner.failures.remove(.layout)
        let retried = await model.perform(.retry(.layout))
        XCTAssertEqual(retried.confirmed, [.layout])

        _ = await model.perform(.selectTrayTheme(.violetGlass))
        XCTAssertEqual(owner.value.settings.configuration.trayColors, .violetGlass)
        _ = await model.perform(.selectTrayTheme(.custom))
        let data = try JSONEncoder().encode(owner.value.settings.configuration)
        let persisted = try JSONDecoder().decode(RiftConfiguration.self, from: data)
        XCTAssertEqual(persisted.trayColors, .custom(hue: 145, strength: 0.42))
        XCTAssertEqual(persisted.trayOcclusion, 0)
    }

    @MainActor func testHiddenInvalidTrayTintSurvivesUnrelatedSaveAndNoOpApply() async throws {
        let owner = Owner()
        let model = try model(owner)
        _ = await model.perform(.selectDesktopForm(.tray))
        _ = await model.perform(.selectTrayTheme(.custom))
        model.setDraftText("101", for: .trayTintStrength)
        _ = await model.perform(.applyLayout)
        XCTAssertEqual(model.snapshot.domains[.layout]?.validationFailure, .invalidNumber(.trayTintStrength))

        _ = await model.perform(.selectTrayTheme(.system))
        XCTAssertNil(model.snapshot.domains[.layout]?.validationFailure)
        model.setDraftText("22", for: .outerInset)
        let saved = await model.perform(.applyLayout)
        XCTAssertEqual(saved.confirmed, [.layout])
        XCTAssertEqual(owner.value.settings.configuration.outerInset, 22)
        XCTAssertEqual(owner.value.settings.configuration.trayTintStrength, 0.65)
        let writes = owner.requests.count
        _ = await model.perform(.applyLayout)
        XCTAssertEqual(owner.requests.count, writes)

        // The same controls are also hidden outside the screenshot tray.
        _ = await model.perform(.selectDesktopForm(.microSlit))
        _ = await model.perform(.selectTrayTheme(.custom))
        XCTAssertNil(model.snapshot.domains[.layout]?.validationFailure)
        _ = await model.perform(.applyLayout)
        _ = await model.perform(.selectDesktopForm(.tray))
        XCTAssertEqual(model.text(for: .trayTintStrength), "101")
        XCTAssertEqual(model.snapshot.domains[.layout]?.validationFailure, .invalidNumber(.trayTintStrength))
        model.setDraftText("85", for: .trayTintStrength)
        let corrected = await model.perform(.applyLayout)
        XCTAssertEqual(corrected.confirmed, [.layout])
        XCTAssertEqual(owner.value.settings.configuration.trayTintStrength, 0.85)
        XCTAssertEqual(owner.value.settings.configuration.outerInset, 22)
    }

    func testUnsupportedTintValuesSurviveUnrelatedSavesAndLegacyKeysStayAbsent() throws {
        let source = Data(#"{"trayTheme":"custom","trayTintHue":{"schema":3},"trayTintStrength":-1}"#.utf8)
        var configuration = try JSONDecoder().decode(RiftConfiguration.self, from: source)
        XCTAssertEqual(configuration.trayColors, .custom(hue: 255, strength: 0.65))
        configuration.outerInset = 13
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(configuration)) as? NSDictionary)
        XCTAssertEqual(json["trayTintHue"] as? NSDictionary, ["schema": 3])
        XCTAssertEqual(json["trayTintStrength"] as? Int, -1)
        let legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(RiftConfiguration())) as? NSDictionary)
        XCTAssertNil(legacy["trayTintHue"])
        XCTAssertNil(legacy["trayTintStrength"])
    }

    func testTrayFavoritesKeepSlotIdentityAndOnlyAutomaticKeysFollowTheDefault() throws {
        var config = try JSONDecoder().decode(RiftConfiguration.self, from: Data("{}".utf8))
        XCTAssertEqual(config.trayFavoriteModes(defaultMode: .window), [.region, .fullScreen, nil])
        XCTAssertEqual(config.trayFavoriteModes(defaultMode: .region), [.window, .fullScreen, nil])
        XCTAssertEqual(config.trayFavoriteModes(defaultMode: .fullScreen), [.window, .region, nil])

        config.setTrayFavorite(.mode(.window), for: .third)
        config.setTrayFavorite(.empty, for: .second)
        let reopened = try JSONDecoder().decode(RiftConfiguration.self, from: JSONEncoder().encode(config))
        XCTAssertEqual(reopened.trayFavorite(.second), .empty)
        XCTAssertEqual(reopened.trayFavoriteModes(defaultMode: .window), [.region, nil, .window])
        XCTAssertEqual(reopened.trayFavoriteModes(defaultMode: .region), [.window, nil, .window])
        config.setTrayFavorite(.automatic, for: .second)
        XCTAssertEqual(config.trayFavoriteModes(defaultMode: .region), [.window, .fullScreen, .window])
    }

    func testUnknownFavoriteDoesNotCaptureAndSurvivesEditsToOtherKeys() throws {
        let source = Data(#"{"trayFavorite1":{"later":[2,"key"]},"trayFavorite2":"future","trayFavorite3":"region"}"#.utf8)
        var config = try JSONDecoder().decode(RiftConfiguration.self, from: source)
        XCTAssertEqual(config.trayFavorite(.first), .unsupported)
        XCTAssertEqual(config.trayFavoriteModes(defaultMode: .window), [nil, nil, .region])
        config.setTrayFavorite(.mode(.fullScreen), for: .third)
        let saved = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(config)) as? NSDictionary)
        let old = try XCTUnwrap(JSONSerialization.jsonObject(with: source) as? NSDictionary)
        XCTAssertEqual(saved["trayFavorite1"] as? NSObject, old["trayFavorite1"] as? NSObject)
        XCTAssertEqual(saved["trayFavorite2"] as? String, "future")
        XCTAssertEqual(saved["trayFavorite3"] as? String, "fullScreen")
    }

    @MainActor func testFavoriteRetryPreservesDraftOtherKeysAndNewDefault() async throws {
        let owner = Owner()
        let model = try model(owner)
        model.setDraftText("87.250", for: .fitWidth)
        owner.failures.insert(.trayFavorite1)
        let failed = await model.perform(.selectTrayFavorite(.first, .mode(.region)))
        XCTAssertEqual(failed.failed, [.trayFavorite1])
        _ = await model.perform(.selectTrayFavorite(.third, .mode(.fullScreen)))
        _ = await model.perform(.setCaptureMode(.fullScreen))
        XCTAssertEqual(model.snapshot.domains[.trayFavorite1]?.pending, .trayFavorite(.first, .mode(.region)))
        owner.failures.remove(.trayFavorite1)
        let retry = await model.perform(.retry(.trayFavorite1))
        XCTAssertEqual(retry.confirmed, [.trayFavorite1])
        let config = owner.value.settings.configuration
        XCTAssertEqual(config.trayFavorite(.first), .mode(.region))
        XCTAssertEqual(config.trayFavoriteModes(defaultMode: owner.value.settings.defaultCaptureMode), [.region, .region, .fullScreen])
        XCTAssertEqual(model.text(for: .fitWidth), "87.250")
        XCTAssertTrue(model.hasLayoutDraft)
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
        XCTAssertEqual(model.text(for: .fitHeight), "88")
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
        XCTAssertEqual(model.snapshot.owner.settings.archiveAfterMinutes, 2)
        owner.failures = []
        let retried = await model.perform(.applyDrafts)
        XCTAssertEqual(retried.confirmed, [.archive])
        XCTAssertEqual(owner.requests.filter { $0.intent.domain == .layout }.count, 1)
        XCTAssertEqual(owner.requests.filter { $0.intent.domain == .archive }.count, 2)
        XCTAssertEqual(owner.requests.last?.intent.domain, .archive)
        XCTAssertEqual(model.snapshot.owner.settings.archiveAfterMinutes, 2.5)
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
        for text in ["", "-1", "0", "0.99", "10.01", "Infinity", "1e309", "1abc"] {
            await model.perform(.editArchive(text)); await model.perform(.applyArchive)
            XCTAssertEqual(model.archiveDraftText, text)
        }
        XCTAssertTrue(owner.requests.isEmpty)
        XCTAssertEqual(owner.value.settings.archiveAfterMinutes, QueueArchivePolicy.defaultMinutes)
        await model.perform(.editArchive(nil)); await model.perform(.applyArchive)
        XCTAssertNil(owner.value.settings.archiveAfterMinutes)
        XCTAssertNil(model.snapshot.archiveText); XCTAssertFalse(model.hasArchiveDraft)
        await model.perform(.applyArchive)
        XCTAssertEqual(owner.requests.count, 1, "Already saved disabled archive is not written again")
        for text in ["1", "10"] {
            await model.perform(.editArchive(text)); await model.perform(.applyArchive)
            XCTAssertEqual(owner.value.settings.archiveAfterMinutes, Double(text))
        }
    }

    @MainActor func testLocaleUnitsFractionalArchiveAndExplicitNoneSelection() async throws {
        let owner = Owner()
        let model = try SettingsStateModel(owner: owner.value, confirmed: owner.known, decimalSeparator: ",", adapter: owner)
        await model.perform(.edit(.hiddenFraction, "12,5")); await model.perform(.edit(.swallowDuration, "40")); await model.perform(.applyLayout)
        XCTAssertEqual(owner.value.settings.configuration.hiddenFraction, 0.125)
        XCTAssertEqual(owner.value.settings.configuration.swallowDuration, 0.04)
        await model.perform(.editArchive("1,077")); await model.perform(.applyArchive); await model.perform(.applyArchive)
        XCTAssertEqual(owner.requests.filter { $0.intent.domain == .archive }.count, 1)
        XCTAssertNotEqual(1.077, (1.077 * 60) / 60, "This fixture must exercise a real floating-point round trip")
        XCTAssertEqual(owner.value.settings.archiveAfterMinutes, (1.077 * 60) / 60)
        XCTAssertEqual(model.archiveDraftText, "1,077")
        XCTAssertFalse(model.hasArchiveDraft)
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
        XCTAssertEqual(model.text(for: .fitWidth), "96")
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
        let overlappingFavorite = await model.perform(.selectTrayFavorite(.second, .mode(.region)))
        XCTAssertEqual(duplicate.busy, [.layout]); XCTAssertEqual(overlappingFile.busy, [.display])
        XCTAssertEqual(overlappingFavorite.busy, [.trayFavorite2])
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
        XCTAssertTrue(model.snapshot.owner.isHidden); XCTAssertEqual(model.snapshot.owner.settings.archiveAfterMinutes, 3)
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
        XCTAssertEqual(owner.requests.last { $0.intent.domain == .archive }?.intent, .archiveMinutes(2.5))
        XCTAssertEqual(model.snapshot.owner.settings.archiveAfterMinutes, 2.5)
        XCTAssertEqual(model.archiveDraftText, "4.125")
        XCTAssertTrue(model.hasArchiveDraft)
        await model.perform(.applyArchive)
        XCTAssertEqual(owner.requests.last?.intent, .archiveMinutes(4.125))
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

    @MainActor func testSynchronousDraftAndSavingNotificationsPrecedeDelayedOwnerReceipt() async throws {
        let owner = Owner(); let model = try model(owner); let gate = Gate()
        defer { gate.release() }
        var observations: [SettingsStateSnapshot] = []
        model.onChange = { observations.append($0) }
        model.setDraftText("81.625", for: .fitWidth)
        XCTAssertEqual(model.text(for: .fitWidth), "81.625")
        XCTAssertEqual(observations.last?.layoutText[.fitWidth], "81.625")
        owner.beforeReturn = { request, _ in if request.intent.domain == .layout { await gate.suspend() } }
        let pending = Task { @MainActor in await model.perform(.applyLayout) }
        await fulfillment(of: [gate.entered], timeout: 5)
        XCTAssertEqual(observations.last?.domains[.layout]?.isSaving, true)
        XCTAssertEqual(observations.last?.domains[.layout]?.pending, .layout([.fitWidth: 81.625]))
        gate.release()
        let result = await pending.value
        XCTAssertEqual(result.confirmed, [.layout])
        XCTAssertEqual(observations.last?.domains[.layout]?.isSaving, false)
        XCTAssertNil(observations.last?.domains[.layout]?.pending)
    }

    @MainActor func testIndependentArchiveCompletionPublishesBeforeSlowerLayoutFinishes() async throws {
        let owner = Owner(); let model = try model(owner); let gate = Gate()
        defer { gate.release() }
        let archivePublished = expectation(description: "Archive receipt published while layout still saving")
        var fulfilled = false
        model.onChange = { snapshot in
            if !fulfilled, snapshot.domains[.archive]?.lastConfirmed == .archiveMinutes(2.5),
               snapshot.domains[.layout]?.isSaving == true {
                fulfilled = true; archivePublished.fulfill()
            }
        }
        model.setDraftText("81.625", for: .fitWidth)
        model.setArchiveDraftText("2.5")
        owner.beforeReturn = { request, _ in if request.intent.domain == .layout { await gate.suspend() } }
        let pending = Task { @MainActor in await model.perform(.applyDrafts) }
        await fulfillment(of: [gate.entered, archivePublished], timeout: 5)
        XCTAssertFalse(model.hasArchiveDraft)
        XCTAssertTrue(model.snapshot.domains[.layout]?.isSaving == true)
        gate.release()
        let result = await pending.value
        XCTAssertEqual(Set(result.confirmed), [.layout, .archive])
    }

}
