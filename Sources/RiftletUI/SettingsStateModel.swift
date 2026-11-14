import Foundation
import RiftletCapture

/// Presentation state only. No file, window, capture, browser or upload access.
public enum SettingsDomain: String, CaseIterable, Sendable {
    case collection, visibility, entry, captureMode, arrival, layout, placement, display, desktopForm, windChimeArrangement, trayTheme, archive
    case trayFavorite1, trayFavorite2, trayFavorite3

    var writesConfiguration: Bool {
        switch self {
        case .layout, .placement, .display, .desktopForm, .windChimeArrangement, .trayTheme, .trayFavorite1, .trayFavorite2, .trayFavorite3: return true
        default: return false
        }
    }
}

extension RiftTrayFavoriteSlot {
    var settingsDomain: SettingsDomain {
        switch self {
        case .first: return .trayFavorite1
        case .second: return .trayFavorite2
        case .third: return .trayFavorite3
        }
    }
}

public enum SettingsDraftPage: Equatable, Sendable { case display, motion }

/// Only currently effective numeric settings are editable. Codable compatibility
/// fields and display identity never enter this patch vocabulary.
public enum SettingsField: String, CaseIterable, Hashable, Sendable {
    case fitWidth, fitHeight, hiddenFraction, trayOcclusion, trayTintHue, trayTintStrength, rowPitch, outerInset, windChimeLineInset, firstCenterFromTop
    case numberFontSize, numberGap, leftPadding, minimumHitWidth, minimumHitHeight, visibleCountPreference
    case pressDuration, swallowDuration, shiftDuration, returnDuration

    static let publicNumbers: [Self] = [.visibleCountPreference, .outerInset, .hiddenFraction, .windChimeLineInset, .trayOcclusion, .trayTintHue, .trayTintStrength]
    fileprivate var isCustomTrayTint: Bool { self == .trayTintHue || self == .trayTintStrength }

    public var page: SettingsDraftPage {
        switch self {
        case .pressDuration, .swallowDuration, .shiftDuration, .returnDuration: return .motion
        default: return .display
        }
    }

    /// Text is shown in percent / milliseconds; RiftConfiguration retains its units.
    fileprivate var scale: Double {
        if self == .hiddenFraction || self == .trayOcclusion || self == .trayTintStrength { return 100 }
        return page == .motion ? 1000 : 1
    }

    fileprivate func value(in c: RiftConfiguration) -> Double {
        switch self {
        case .fitWidth: return c.fitWidth
        case .fitHeight: return c.fitHeight
        case .trayTintHue: return c.trayTintHue
        case .trayTintStrength: return c.trayTintStrength
        case .trayOcclusion: return c.trayOcclusion
        case .hiddenFraction: return c.hiddenFraction
        case .rowPitch: return c.rowPitch
        case .windChimeLineInset: return c.windChimeLineInset
        case .outerInset: return c.outerInset
        case .firstCenterFromTop: return c.firstCenterFromTop
        case .numberFontSize: return c.numberFontSize
        case .numberGap: return c.numberGap
        case .leftPadding: return c.leftPadding
        case .minimumHitWidth: return c.minimumHitWidth
        case .minimumHitHeight: return c.minimumHitHeight
        case .visibleCountPreference: return Double(c.visibleCountPreference)
        case .pressDuration: return c.pressDuration
        case .swallowDuration: return c.swallowDuration
        case .shiftDuration: return c.shiftDuration
        case .returnDuration: return c.returnDuration
        }
    }

    fileprivate func put(_ value: Double, into c: inout RiftConfiguration) throws {
        guard value.isFinite else { throw SettingsValidationFailure.invalidNumber(self) }
        switch self {
        case .fitWidth: c.fitWidth = value
        case .fitHeight: c.fitHeight = value
        case .trayTintHue:
            guard (0...360).contains(value) else { throw SettingsValidationFailure.invalidNumber(self) }
            c.trayTintHue = value
        case .trayTintStrength:
            guard (0...1).contains(value) else { throw SettingsValidationFailure.invalidNumber(self) }
            c.trayTintStrength = value
        case .trayOcclusion:
            guard (0...0.9).contains(value) else { throw SettingsValidationFailure.invalidNumber(self) }
            c.trayOcclusion = value
        case .hiddenFraction: c.hiddenFraction = value
        case .rowPitch: c.rowPitch = value
        case .windChimeLineInset:
            guard (0...256).contains(value) else { throw SettingsValidationFailure.invalidNumber(self) }
            c.windChimeLineInset = value
        case .outerInset: c.outerInset = value
        case .firstCenterFromTop: c.firstCenterFromTop = value
        case .numberFontSize: c.numberFontSize = value
        case .numberGap: c.numberGap = value
        case .leftPadding: c.leftPadding = value
        case .minimumHitWidth: c.minimumHitWidth = value
        case .minimumHitHeight: c.minimumHitHeight = value
        case .visibleCountPreference:
            guard value.rounded() == value, (1...10).contains(value) else {
                throw SettingsValidationFailure.invalidNumber(self)
            }
            c.visibleCountPreference = Int(value)
        case .pressDuration: c.pressDuration = value
        case .swallowDuration: c.swallowDuration = value
        case .shiftDuration: c.shiftDuration = value
        case .returnDuration: c.returnDuration = value
        }
    }
}

public struct SettingsDisplayPreference: Equatable, Sendable {
    public let id: UInt32
    public let uuid: String?
    public init(id: UInt32, uuid: String?) { self.id = id; self.uuid = uuid }
}

/// An immutable request target; retry never obtains a target by toggling state.
public enum SettingsIntent: Equatable, Sendable {
    case collectionPaused(Bool), hidden(Bool), entryEnabled(Bool)
    case captureMode(ScreenshotMode), arrival(ArrivalMotionMode)
    case desktopForm(RiftDesktopForm), windChimeArrangement(RiftWindChimeArrangement), trayTheme(RiftTrayTheme)
    case trayFavorite(RiftTrayFavoriteSlot, RiftTrayFavoriteChoice)
    case layout([SettingsField: Double]), placement(RiftPlacement)
    case display(SettingsDisplayPreference), archiveMinutes(Double?)

    public var domain: SettingsDomain {
        switch self {
        case .collectionPaused: return .collection
        case .hidden: return .visibility
        case .entryEnabled: return .entry
        case .captureMode: return .captureMode
        case .arrival: return .arrival
        case .desktopForm: return .desktopForm
        case .windChimeArrangement: return .windChimeArrangement
        case .trayTheme: return .trayTheme
        case .trayFavorite(let slot, _): return slot.settingsDomain
        case .layout: return .layout
        case .placement: return .placement
        case .display: return .display
        case .archiveMinutes: return .archive
        }
    }
}

public enum SettingsConfirmedValue: Equatable, Sendable {
    case boolean(Bool), captureMode(ScreenshotMode), arrival(ArrivalMotionMode)
    case desktopForm(RiftDesktopForm), windChimeArrangement(RiftWindChimeArrangement), trayTheme(RiftTrayTheme)
    case trayFavorite(RiftTrayFavoriteChoice)
    case configuration(RiftConfiguration), placement(RiftPlacement?)
    case display(id: UInt32?, uuid: String?), archiveMinutes(Double?)
}

public enum SettingsSaveFailure: Equatable, Sendable {
    /// Includes write-then-chmod failures. It makes no claim about current disk bytes.
    case writeUnconfirmed, ownerUnavailable, staleReceipt, invalidOwnerSnapshot, confirmationMismatch
}

public enum SettingsValidationFailure: Error, Equatable, Sendable {
    case invalidNumber(SettingsField), invalidConfiguration, invalidArchive, displayUnavailable, inactiveLegacyField
}

public struct SettingsDomainState: Equatable, Sendable {
    public fileprivate(set) var lastConfirmed: SettingsConfirmedValue?
    public fileprivate(set) var pending: SettingsIntent?
    public fileprivate(set) var saveFailure: SettingsSaveFailure?
    public fileprivate(set) var validationFailure: SettingsValidationFailure?
    public fileprivate(set) var isSaving = false

    public var hasIssue: Bool { saveFailure != nil || validationFailure != nil }
    fileprivate init(lastConfirmed: SettingsConfirmedValue? = nil) { self.lastConfirmed = lastConfirmed }
}

/// A coherent observation from existing owners. The host increments revision for
/// every new observation/command receipt, including unsuccessful save attempts.
public struct SettingsOwnerSnapshot: Equatable, Sendable {
    public let revision: UInt64
    public var settings: RiftSettingsSnapshot
    public var collectionPaused: Bool
    public var isHidden: Bool
    public var mainDisplayID: UInt32?
    /// Actual session fallback is owned by RiftPanelController, not this model.
    public var effectiveDisplayID: UInt32?

    public init(revision: UInt64, settings: RiftSettingsSnapshot, collectionPaused: Bool,
                isHidden: Bool, mainDisplayID: UInt32? = nil, effectiveDisplayID: UInt32? = nil) {
        self.revision = revision; self.settings = settings
        self.collectionPaused = collectionPaused; self.isHidden = isHidden
        self.mainDisplayID = mainDisplayID; self.effectiveDisplayID = effectiveDisplayID
    }
}

public struct SettingsSaveRequest: Equatable, Sendable {
    public let intent: SettingsIntent
    public let ownerRevision: UInt64
    /// A validated full configuration, patched from the latest owner snapshot.
    /// Non-nil for preferences owned by the layout configuration file.
    public let configuration: RiftConfiguration?
}

public enum SettingsSaveOutcome: Sendable {
    case confirmed(SettingsOwnerSnapshot)
    case unconfirmed(SettingsOwnerSnapshot?, SettingsSaveFailure)
}

/// MainActor boundary; QueueStore and capture owners may suspend before returning.
/// The owner performs existing stop-before-save / save-before-resume behavior,
/// then returns actual effective state even when persistence was unconfirmed.
/// A nonthrowing host method with preferenceSaveFailed must return unconfirmed.
@MainActor public protocol SettingsPersistenceAdapter {
    func save(_ request: SettingsSaveRequest) async -> SettingsSaveOutcome
}

@MainActor public struct SettingsPersistenceClosures: SettingsPersistenceAdapter {
    private let body: @MainActor (SettingsSaveRequest) async -> SettingsSaveOutcome
    public init(save: @escaping @MainActor (SettingsSaveRequest) async -> SettingsSaveOutcome) { body = save }
    public func save(_ request: SettingsSaveRequest) async -> SettingsSaveOutcome { await body(request) }
}

public enum SettingsCommand: Sendable {
    case commitField(SettingsField, String, maximumCount: Int? = nil), commitArchive(String?), restoreVisibleDefaults
    case edit(SettingsField, String), editArchive(String?), restoreDefaults(SettingsDraftPage)
    case discardLayout, discardArchive, discardDrafts, applyLayout, applyArchive, applyDrafts(maximumCount: Int? = nil)
    case setCollectionPaused(Bool), setHidden(Bool), setEntryEnabled(Bool)
    case setCaptureMode(ScreenshotMode), setArrival(ArrivalMotionMode)
    case selectDesktopForm(RiftDesktopForm), selectWindChimeArrangement(RiftWindChimeArrangement), selectTrayTheme(RiftTrayTheme)
    case selectTrayFavorite(RiftTrayFavoriteSlot, RiftTrayFavoriteChoice)
    case selectPlacement(RiftPlacement), selectDisplay(UInt32?), retry(SettingsDomain)
}

public struct SettingsSubmission: Equatable, Sendable {
    public fileprivate(set) var confirmed: [SettingsDomain] = []
    public fileprivate(set) var failed: [SettingsDomain] = []
    /// Already writing this owner. No second write, queued action or UI-wide lock.
    public fileprivate(set) var busy: [SettingsDomain] = []
}

public struct SettingsStateSnapshot: Equatable, Sendable {
    public let revision: UInt64
    public let owner: SettingsOwnerSnapshot
    public let layoutText: [SettingsField: String]
    public let configurationDraft: RiftConfiguration?
    public let archiveText: String?
    public let domains: [SettingsDomain: SettingsDomainState]
    public var hasSaveIssues: Bool { domains.values.contains { $0.saveFailure != nil } }
}

/// Not wired into Main or an existing view. It never creates an OS effect itself.
@MainActor public final class SettingsStateModel {
    /// Host refreshes all surfaces without recreating controls or starting an effect.
    public var onChange: (@MainActor (SettingsStateSnapshot) -> Void)?
    private let adapter: any SettingsPersistenceAdapter
    private let decimalSeparator: String
    private var owner: SettingsOwnerSnapshot
    private var revision: UInt64 = 0
    private var layoutText: [SettingsField: String] = [:]
    /// A disabled draft has no numeric input. Empty or zero text remains a user edit to validate.
    private enum ArchiveDraft {
        case disabled, minutes(String)
        var text: String? {
            if case .minutes(let text) = self { return text }
            return nil
        }
    }
    private var archiveDraft: ArchiveDraft?
    private var domains: [SettingsDomain: SettingsDomainState]
    private var layoutEditVersions: [SettingsField: UInt64] = [:]
    private var archiveEditVersion: UInt64?
    private var pendingTextVersions: [SettingsDomain: TextVersions] = [:]
    private var writes: Set<SettingsDomain> = []
    // A receipt for one numeric field cannot confirm another field in the same file.
    private struct FailedLayoutField {
        let value: Double
        let editVersion: UInt64?
        let failure: SettingsSaveFailure
    }
    private var failedLayoutFields: [SettingsField: FailedLayoutField] = [:]

    private struct TextVersions: Sendable {
        var layout: [SettingsField: UInt64] = [:]
        var archive: UInt64?
    }
    private struct PreparedSave: Sendable {
        let intent: SettingsIntent
        let textVersions: TextVersions
    }
    private struct SaveWork: Sendable {
        let prepared: PreparedSave
        let request: SettingsSaveRequest
        let writer: SettingsDomain
    }

    /// Known confirmations must be supplied explicitly. Effective values alone
    /// (especially an unsaved stopped state) never manufacture a confirmation.
    public init(owner: SettingsOwnerSnapshot, confirmed: [SettingsDomain: SettingsConfirmedValue] = [:],
                decimalSeparator: String = Locale.current.decimalSeparator ?? ".",
                adapter: any SettingsPersistenceAdapter) throws {
        try Self.validate(owner)
        self.owner = owner; self.adapter = adapter
        self.decimalSeparator = decimalSeparator.isEmpty ? "." : decimalSeparator
        domains = Dictionary(uniqueKeysWithValues: SettingsDomain.allCases.map {
            ($0, SettingsDomainState(lastConfirmed: confirmed[$0]))
        })
    }

    public var snapshot: SettingsStateSnapshot {
        var visibleDomains = domains
        if case .invalidNumber(let field) = visibleDomains[.layout]?.validationFailure,
           !includedInLayoutDraft(field) { visibleDomains[.layout]?.validationFailure = nil }
        let draft: RiftConfiguration?
        do { draft = try configuration(for: .layout(layoutPatch())) }
        catch {
            draft = nil
            if let validation = error as? SettingsValidationFailure {
                visibleDomains[.layout]?.validationFailure = validation
            }
        }
        return .init(revision: revision, owner: owner, layoutText: layoutText,
                     configurationDraft: draft, archiveText: archiveDraft?.text, domains: visibleDomains)
    }

    public var configurationDraft: RiftConfiguration? { snapshot.configurationDraft }

    public func text(for field: SettingsField) -> String {
        layoutText[field] ?? format(field.value(in: owner.settings.configuration) * field.scale)
    }
    func effectiveText(for field: SettingsField) -> String {
        format(field.value(in: owner.settings.configuration) * field.scale)
    }
    public var archiveDraftText: String {
        archiveDraft?.text ?? Self.archiveMinutesText(owner.settings.archiveAfterMinutes ?? QueueArchivePolicy.defaultMinutes,
                                                decimalSeparator: decimalSeparator)
    }
    static func archiveMinutesText(_ minutes: Double, decimalSeparator: String) -> String {
        // Seconds can round-trip 1.077 minutes to 1.0770000000000002. Use the
        // shorter spelling only when it identifies the same persisted duration.
        let short = String(format: "%.15g", locale: Locale(identifier:"en_US_POSIX"), minutes)
        let text = Double(short).map { ($0 * 60) / 60 == minutes } == true ? short : String(minutes)
        return text.replacingOccurrences(of: ".", with: decimalSeparator)
    }
    public var archiveIsDisabled: Bool {
        switch archiveDraft {
        case .disabled?: return true
        case .minutes?: return false
        case nil: return owner.settings.archiveAfterMinutes == nil
        }
    }

    /// Reading an owner refresh neither saves nor clears an unresolved error.
    /// Dirty text remains byte-for-byte; all untouched values read the new owner.
    @discardableResult public func receive(_ value: SettingsOwnerSnapshot) -> Bool {
        guard value.revision > owner.revision, (try? Self.validate(value)) != nil else { return false }
        owner = value; revision += 1; onChange?(snapshot); return true
    }

    public var hasLayoutDraft: Bool {
        guard let patch = try? layoutPatch() else { return true }
        return patch.contains { $0.value != $0.key.value(in: owner.settings.configuration) }
    }
    public var hasArchiveDraft: Bool {
        guard let archiveDraft else { return false }
        do { return try parseArchive(archiveDraft) != owner.settings.archiveAfterMinutes }
        catch { return true }
    }

    /// Text delegates must finish the draft edit before the first Save/Close click.
    public func setDraftText(_ text: String, for field: SettingsField) {
        layoutText[field] = text; revision += 1; layoutEditVersions[field] = revision
        onChange?(snapshot)
    }
    public func setArchiveDraftText(_ text: String?) {
        archiveDraft = text.map(ArchiveDraft.minutes) ?? .disabled
        revision += 1; archiveEditVersion = revision
        onChange?(snapshot)
    }

    @discardableResult public func perform(_ command: SettingsCommand) async -> SettingsSubmission {
        defer { onChange?(snapshot) }
        var result = SettingsSubmission()
        switch command {
        case .commitField(let field, let text, let maximumCount):
            guard includedInLayoutDraft(field) else { return result }
            guard let value = parse(text) else { invalid(.layout, .invalidNumber(field), into: &result); return result }
            if field == .visibleCountPreference, let maximumCount, value > Double(maximumCount) {
                invalid(.layout, .invalidNumber(field), into: &result); return result
            }
            await save(prepare(.layout([field: value / field.scale])), into: &result)
        case .commitArchive(let text):
            do {
                let target = try parseArchive(text.map(ArchiveDraft.minutes) ?? .disabled)
                await save(prepare(.archiveMinutes(target)), into: &result)
            } catch { invalid(.archive, .invalidArchive, into: &result) }
        case .restoreVisibleDefaults:
            let defaults = RiftConfiguration()
            let patch = Dictionary(uniqueKeysWithValues: SettingsField.publicNumbers.filter(includedInLayoutDraft).map {
                ($0, $0.value(in: defaults))
            })
            for field in patch.keys { layoutText.removeValue(forKey: field); layoutEditVersions.removeValue(forKey: field) }
            await save(prepare(.layout(patch)), into: &result)
        case .edit(let field, let text):
            setDraftText(text, for: field)
        case .editArchive(let text):
            setArchiveDraftText(text)
        case .restoreDefaults(let page):
            let defaults = RiftConfiguration()
            revision += 1
            for field in SettingsField.allCases where field.page == page && includedInLayoutDraft(field) {
                if field == .trayOcclusion && owner.settings.configuration.desktopForm != .tray { continue }
                layoutText[field] = format(field.value(in: defaults) * field.scale)
                layoutEditVersions[field] = revision
            }
        case .discardLayout: discard(.layout)
        case .discardArchive: discard(.archive)
        case .discardDrafts: discard(.layout); discard(.archive)
        case .applyLayout:
            if let prepared = prepareLayout(into: &result) { await save(prepared, into: &result) }
        case .applyArchive:
            if let prepared = prepareArchive(into: &result) { await save(prepared, into: &result) }
        case .applyDrafts(let maximumCount):
            // Separate owners are not a transaction. Keep each actual result;
            // reserve both requests before either await. Neither is a queued
            // command that could overwrite a newer explicit save after waiting.
            let layout = prepareLayout(into: &result, maximumCount: maximumCount).flatMap { begin($0, into: &result) }
            let archive = prepareArchive(into: &result).flatMap { begin($0, into: &result) }
            async let layoutResult = finish(layout)
            async let archiveResult = finish(archive)
            let completed = await (layoutResult, archiveResult)
            result.confirmed += completed.0.confirmed + completed.1.confirmed
            result.failed += completed.0.failed + completed.1.failed
        case .setCollectionPaused(let value): await save(prepare(.collectionPaused(value)), into: &result)
        case .setHidden(let value): await save(prepare(.hidden(value)), into: &result)
        case .setEntryEnabled(let value): await save(prepare(.entryEnabled(value)), into: &result)
        case .setCaptureMode(let value): await save(prepare(.captureMode(value)), into: &result)
        case .setArrival(let value): await save(prepare(.arrival(value)), into: &result)
        case .selectDesktopForm(let value):
            await save(prepare(.desktopForm(value)), into: &result)
        case .selectWindChimeArrangement(let value): await save(prepare(.windChimeArrangement(value)), into: &result)
        case .selectTrayTheme(let value): await save(prepare(.trayTheme(value)), into: &result)
        case .selectTrayFavorite(let slot, let choice):
            guard choice != .unsupported else { return result }
            await save(prepare(.trayFavorite(slot, choice)), into: &result)
        case .selectPlacement(let value): await save(prepare(.placement(value)), into: &result)
        case .selectDisplay(let requested):
            let displays = owner.settings.displays
            let selected = requested ?? RiftDisplaySelection.choose(preferred: nil, main: owner.mainDisplayID,
                                                                     available: displays.map(\.id))
            let matches = displays.filter { $0.id == selected }
            guard matches.count == 1, let display = matches.first else {
                invalid(.display, .displayUnavailable, into: &result); return result
            }
            await save(prepare(.display(.init(id: display.id, uuid: display.uuid))), into: &result)
        case .retry(let domain):
            if let pending = prepareRetry(domain) { await save(pending, into: &result) }
        }
        return result
    }

    private func applicable(_ field: SettingsField) -> Bool {
        field != .firstCenterFromTop || owner.settings.configuration.placement == nil
    }

    private func includedInLayoutDraft(_ field: SettingsField) -> Bool {
        let configuration = owner.settings.configuration
        switch field {
        case .windChimeLineInset: return configuration.desktopForm == .windChime
        case .hiddenFraction: return configuration.desktopForm == .microSlit
        case .outerInset: return configuration.desktopForm != .windChime
        case .trayOcclusion: return configuration.desktopForm == .tray
        case .trayTintHue, .trayTintStrength: return configuration.desktopForm == .tray && configuration.trayTheme == .custom
        case .fitWidth, .fitHeight, .rowPitch, .numberFontSize, .numberGap, .leftPadding, .minimumHitWidth, .minimumHitHeight:
            return configuration.desktopForm != .tray
        case .firstCenterFromTop: return configuration.placement == nil && configuration.desktopForm != .tray
        default: return true
        }
    }

    private func layoutPatch() throws -> [SettingsField: Double] {
        try Dictionary(uniqueKeysWithValues: layoutText.filter { includedInLayoutDraft($0.key) }.map { field, text in
            guard let value = parse(text) else { throw SettingsValidationFailure.invalidNumber(field) }
            return (field, value / field.scale)
        })
    }

    private func prepare(_ intent: SettingsIntent) -> PreparedSave {
        PreparedSave(intent: intent, textVersions: TextVersions(layout: layoutEditVersions, archive: archiveEditVersion))
    }

    private func prepareRetry(_ domain: SettingsDomain) -> PreparedSave? {
        guard let intent = domains[domain]?.pending else { return nil }
        return PreparedSave(intent: intent, textVersions: pendingTextVersions[domain] ?? TextVersions())
    }

    private func prepareLayout(into result: inout SettingsSubmission, maximumCount: Int? = nil) -> PreparedSave? {
        guard !writes.contains(.layout) else { result.busy.append(.layout); return nil }
        do {
            if layoutText.isEmpty, let pending = prepareRetry(.layout) { return pending }
            let patch = try layoutPatch()
            if let count = patch[.visibleCountPreference], let maximumCount, count > Double(maximumCount) {
                throw SettingsValidationFailure.invalidNumber(.visibleCountPreference)
            }
            let prepared = prepare(.layout(patch))
            if !hasLayoutDraft && domains[.layout]?.pending == nil {
                clearSubmittedText(prepared)
                domains[.layout]?.validationFailure = nil
                revision += 1
                return nil
            }
            return patch.isEmpty ? nil : prepared
        } catch let error as SettingsValidationFailure { invalid(.layout, error, into: &result) }
        catch { invalid(.layout, .invalidConfiguration, into: &result) }
        return nil
    }

    private func prepareArchive(into result: inout SettingsSubmission) -> PreparedSave? {
        guard !writes.contains(.archive) else { result.busy.append(.archive); return nil }
        do {
            guard let archiveDraft else { return prepareRetry(.archive) }
            let minutes = try parseArchive(archiveDraft)
            if minutes == owner.settings.archiveAfterMinutes && domains[.archive]?.pending == nil {
                discard(.archive); return nil
            }
            return prepare(.archiveMinutes(minutes))
        } catch { invalid(.archive, .invalidArchive, into: &result) }
        return nil
    }

    private func configuration(for intent: SettingsIntent) throws -> RiftConfiguration? {
        var candidate = owner.settings.configuration
        switch intent {
        case .layout(let patch):
            for (field, value) in patch {
                guard applicable(field) else { throw SettingsValidationFailure.inactiveLegacyField }
                if field == .visibleCountPreference && candidate.desktopForm == .tray && value > 4 {
                    throw SettingsValidationFailure.invalidNumber(field)
                }
                try field.put(value, into: &candidate)
                // The owner snapshot was valid. Associate a rejected change with its
                // field so switching forms can put only that error back in its draft.
                do { try candidate.validate() }
                catch { throw SettingsValidationFailure.invalidNumber(field) }
            }
            return candidate
        case .desktopForm(let value): candidate.desktopForm = value
        case .windChimeArrangement(let value): candidate.windChimeArrangement = value
        case .trayTheme(let value): candidate.trayTheme = value
        case .trayFavorite(let slot, let choice): candidate.setTrayFavorite(choice, for: slot)
        case .placement(let placement): candidate.placement = placement; candidate.placementSource = .user
        case .display(let display):
            candidate.preferredDisplayID = display.id; candidate.preferredDisplayUUID = display.uuid
            candidate.placementSource = .user
        default: return nil
        }
        try candidate.validate(); return candidate
    }

    private func save(_ prepared: PreparedSave, into result: inout SettingsSubmission) async {
        let work = begin(prepared, into: &result)
        let completed = await finish(work)
        result.confirmed += completed.confirmed; result.failed += completed.failed
    }

    private func begin(_ prepared: PreparedSave, into result: inout SettingsSubmission) -> SaveWork? {
        let intent = prepared.intent
        let domain = intent.domain
        // These commands persist the same full configuration. Other
        // owners remain independent, including pause, hide and archive.
        let writer: SettingsDomain = domain.writesConfiguration ? .layout : domain
        guard !writes.contains(writer) else { result.busy.append(domain); return nil }
        let configuration: RiftConfiguration?
        do { configuration = try self.configuration(for: intent) }
        catch let error as SettingsValidationFailure { invalid(domain, error, into: &result); return nil }
        catch { invalid(domain, .invalidConfiguration, into: &result); return nil }
        let request = SettingsSaveRequest(intent: intent, ownerRevision: owner.revision, configuration: configuration)
        if domains[domain]?.pending == nil, domains[domain]?.saveFailure == nil,
           matches(request, owner), domains[domain]?.lastConfirmed == confirmedValue(domain, owner) {
            domains[domain]?.validationFailure = nil; clearSubmittedText(prepared); revision += 1; return nil
        }
        writes.insert(writer)
        domains[domain]?.pending = intent; domains[domain]?.isSaving = true
        pendingTextVersions[domain] = prepared.textVersions
        domains[domain]?.validationFailure = nil; revision += 1
        onChange?(snapshot)
        return SaveWork(prepared: prepared, request: request, writer: writer)
    }

    private func finish(_ work: SaveWork?) async -> SettingsSubmission {
        var result = SettingsSubmission()
        guard let work else { return result }
        let prepared = work.prepared
        let request = work.request
        let intent = prepared.intent
        let domain = intent.domain
        defer {
            if case .layout(let patch) = intent {
                if let failure = result.failed.isEmpty ? nil : domains[.layout]?.saveFailure {
                    for (field, value) in patch {
                        failedLayoutFields[field] = .init(value: value, editVersion: prepared.textVersions.layout[field], failure: failure)
                    }
                } else if !result.confirmed.isEmpty {
                    for field in patch.keys { failedLayoutFields.removeValue(forKey: field) }
                }
                if !failedLayoutFields.isEmpty {
                    domains[.layout]?.pending = .layout(failedLayoutFields.mapValues(\.value))
                    domains[.layout]?.saveFailure = failedLayoutFields.values.first?.failure
                    pendingTextVersions[.layout] = TextVersions(layout: failedLayoutFields.compactMapValues(\.editVersion))
                }
            }
            writes.remove(work.writer)
            onChange?(snapshot)
        }
        let outcome = await adapter.save(request)
        domains[domain]?.isSaving = false
        let observed: SettingsOwnerSnapshot?
        let error: SettingsSaveFailure?
        switch outcome {
        case .confirmed(let value): observed = value; error = nil
        case .unconfirmed(let value, let reason): observed = value; error = reason
        }
        if let observed {
            guard observed.revision > request.ownerRevision else {
                failed(domain, .staleReceipt, into: &result); return result
            }
            guard (try? Self.validate(observed)) != nil else {
                failed(domain, .invalidOwnerSnapshot, into: &result); return result
            }
            guard observed.revision != owner.revision || observed == owner else {
                failed(domain, .staleReceipt, into: &result); return result
            }
            // A different owner may have produced a later coherent observation
            // while this write awaited. This receipt can confirm its own domain
            // without replacing that newer effective snapshot.
            if observed.revision > owner.revision { owner = observed }
        }
        if let error { failed(domain, error, into: &result); return result }
        guard let observed, matches(request, observed) else {
            failed(domain, .confirmationMismatch, into: &result); return result
        }
        domains[domain] = SettingsDomainState(lastConfirmed: confirmedValue(domain, observed))
        pendingTextVersions.removeValue(forKey: domain)
        clearSubmittedText(prepared)
        if case .placement = intent,
           layoutEditVersions[.firstCenterFromTop] == prepared.textVersions.layout[.firstCenterFromTop] {
            layoutText.removeValue(forKey: .firstCenterFromTop)
            layoutEditVersions.removeValue(forKey: .firstCenterFromTop)
        }
        revision += 1; result.confirmed.append(domain)
        return result
    }

    private func matches(_ request: SettingsSaveRequest, _ value: SettingsOwnerSnapshot) -> Bool {
        switch request.intent {
        case .collectionPaused(let target): return value.collectionPaused == target
        case .hidden(let target): return value.isHidden == target
        case .entryEnabled(let target): return value.settings.entryEnabled == target && !value.settings.capturePreferencesSaveFailed
        case .captureMode(let target): return value.settings.defaultCaptureMode == target && !value.settings.capturePreferencesSaveFailed
        case .arrival(let target): return value.settings.arrivalMode == target && value.settings.hasArrivalSelection
        case .archiveMinutes(let target): return value.settings.archiveAfterMinutes == target
        case .layout(let patch):
            // Confirm the requested fields. A concurrent owner observation may
            // legitimately change untouched fields before a rebased write.
            return patch.allSatisfy { $0.key.value(in: value.settings.configuration) == $0.value }
        case .desktopForm(let target): return value.settings.configuration.desktopForm == target
        case .windChimeArrangement(let target): return value.settings.configuration.windChimeArrangement == target
        case .trayTheme(let target): return value.settings.configuration.trayTheme == target
        case .trayFavorite(let slot, let choice): return value.settings.configuration.trayFavorite(slot) == choice
        case .placement(let target):
            return value.settings.configuration.placement == target && value.settings.configuration.placementSource == .user
        case .display(let target):
            return value.settings.configuration.preferredDisplayID == target.id &&
                value.settings.configuration.preferredDisplayUUID == target.uuid && value.settings.configuration.placementSource == .user
        }
    }

    private func confirmedValue(_ domain: SettingsDomain, _ value: SettingsOwnerSnapshot) -> SettingsConfirmedValue {
        switch domain {
        case .collection: return .boolean(value.collectionPaused)
        case .visibility: return .boolean(value.isHidden)
        case .entry: return .boolean(value.settings.entryEnabled)
        case .captureMode: return .captureMode(value.settings.defaultCaptureMode)
        case .arrival: return .arrival(value.settings.arrivalMode)
        case .desktopForm: return .desktopForm(value.settings.configuration.desktopForm)
        case .windChimeArrangement: return .windChimeArrangement(value.settings.configuration.windChimeArrangement)
        case .trayTheme: return .trayTheme(value.settings.configuration.trayTheme)
        case .trayFavorite1: return .trayFavorite(value.settings.configuration.trayFavorite(.first))
        case .trayFavorite2: return .trayFavorite(value.settings.configuration.trayFavorite(.second))
        case .trayFavorite3: return .trayFavorite(value.settings.configuration.trayFavorite(.third))
        case .layout: return .configuration(value.settings.configuration)
        case .placement: return .placement(value.settings.configuration.placement)
        case .display: return .display(id: value.settings.configuration.preferredDisplayID, uuid: value.settings.configuration.preferredDisplayUUID)
        case .archive: return .archiveMinutes(value.settings.archiveAfterMinutes)
        }
    }

    private func clearSubmittedText(_ prepared: PreparedSave) {
        switch prepared.intent {
        case .layout(let patch):
            for (field, value) in patch {
                if layoutEditVersions[field] == prepared.textVersions.layout[field],
                   let text = layoutText[field], parse(text).map({ $0 / field.scale }) == value {
                    layoutText.removeValue(forKey: field)
                    layoutEditVersions.removeValue(forKey: field)
                }
            }
        case .archiveMinutes(let value):
            if archiveEditVersion == prepared.textVersions.archive, let draft = archiveDraft {
                do { if try parseArchive(draft) == value { archiveDraft = nil; archiveEditVersion = nil } }
                catch { /* A newer invalid draft is still the user's text. */ }
            }
        default: break
        }
    }

    private func discard(_ domain: SettingsDomain) {
        if domain == .layout { layoutText = [:]; layoutEditVersions = [:] }
        if domain == .archive { archiveDraft = nil; archiveEditVersion = nil }
        // Discarding text cannot cancel a write that the owner is already doing.
        // Its eventual result still needs to be surfaced.
        guard domains[domain]?.isSaving != true else { revision += 1; return }
        if domain == .layout { failedLayoutFields.removeAll() }
        pendingTextVersions.removeValue(forKey: domain)
        domains[domain]?.pending = nil; domains[domain]?.saveFailure = nil
        domains[domain]?.validationFailure = nil; revision += 1
    }
    private func failed(_ domain: SettingsDomain, _ failure: SettingsSaveFailure, into result: inout SettingsSubmission) {
        domains[domain]?.saveFailure = failure; revision += 1; result.failed.append(domain)
    }
    private func invalid(_ domain: SettingsDomain, _ failure: SettingsValidationFailure, into result: inout SettingsSubmission) {
        domains[domain]?.validationFailure = failure; revision += 1; result.failed.append(domain)
    }
    private func parse(_ raw: String) -> Double? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: decimalSeparator, with: ".")
        guard text.range(of: #"^(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?$"#,
                         options: .regularExpression) != nil,
              let number = Double(text), number.isFinite else { return nil }
        return number
    }
    private func parseArchive(_ draft: ArchiveDraft) throws -> Double? {
        guard case .minutes(let raw) = draft else { return nil }
        guard let minutes = parse(raw), QueueArchivePolicy.minutesRange.contains(minutes) else {
            throw SettingsValidationFailure.invalidArchive
        }
        // The owner exposes minutes converted back from its durable seconds.
        return (minutes * 60) / 60
    }
    private func format(_ value: Double) -> String {
        let text = String(value)
        // Only format values read from an owner or defaults. User-entered text
        // stays in layoutText/archiveText, including decimal and IME drafts.
        let display = text.hasSuffix(".0") ? String(text.dropLast(2)) : text
        return display.replacingOccurrences(of: ".", with: decimalSeparator)
    }
    private static func validate(_ owner: SettingsOwnerSnapshot) throws {
        try owner.settings.configuration.validate()
        if let minutes = owner.settings.archiveAfterMinutes {
            guard QueueArchivePolicy.minutesRange.contains(minutes) else { throw SettingsValidationFailure.invalidArchive }
        }
    }
}
