import Foundation
import RiftletCapture

/// Presentation state only. No file, window, capture, browser or upload access.
public enum SettingsDomain: String, CaseIterable, Sendable {
    case collection, visibility, entry, captureMode, arrival, layout, placement, display, desktopForm, trayTheme, archive
    case trayFavorite1, trayFavorite2, trayFavorite3

    var writesConfiguration: Bool {
        switch self {
        case .layout, .placement, .display, .desktopForm, .trayTheme, .trayFavorite1, .trayFavorite2, .trayFavorite3: return true
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
    case fitWidth, fitHeight, hiddenFraction, trayOcclusion, rowPitch, outerInset, firstCenterFromTop
    case numberFontSize, numberGap, leftPadding, minimumHitWidth, minimumHitHeight, visibleCountPreference
    case pressDuration, swallowDuration, shiftDuration, returnDuration

    public var page: SettingsDraftPage {
        switch self {
        case .pressDuration, .swallowDuration, .shiftDuration, .returnDuration: return .motion
        default: return .display
        }
    }

    /// Text is shown in percent / milliseconds; RiftConfiguration retains its units.
    fileprivate var scale: Double {
        if self == .hiddenFraction || self == .trayOcclusion { return 100 }
        return page == .motion ? 1000 : 1
    }

    fileprivate func value(in c: RiftConfiguration) -> Double {
        switch self {
        case .fitWidth: return c.fitWidth
        case .fitHeight: return c.fitHeight
        case .trayOcclusion: return c.trayOcclusion
        case .hiddenFraction: return c.hiddenFraction
        case .rowPitch: return c.rowPitch
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
        case .trayOcclusion:
            guard (0...0.9).contains(value) else { throw SettingsValidationFailure.invalidNumber(self) }
            c.trayOcclusion = value
        case .hiddenFraction: c.hiddenFraction = value
        case .rowPitch: c.rowPitch = value
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
    case desktopForm(RiftDesktopForm), trayTheme(RiftTrayTheme)
    case trayFavorite(RiftTrayFavoriteSlot, RiftTrayFavoriteChoice)
    case layout([SettingsField: Double]), placement(RiftPlacement)
    case display(SettingsDisplayPreference), archiveHours(Double?)

    public var domain: SettingsDomain {
        switch self {
        case .collectionPaused: return .collection
        case .hidden: return .visibility
        case .entryEnabled: return .entry
        case .captureMode: return .captureMode
        case .arrival: return .arrival
        case .desktopForm: return .desktopForm
        case .trayTheme: return .trayTheme
        case .trayFavorite(let slot, _): return slot.settingsDomain
        case .layout: return .layout
        case .placement: return .placement
        case .display: return .display
        case .archiveHours: return .archive
        }
    }
}

public enum SettingsConfirmedValue: Equatable, Sendable {
    case boolean(Bool), captureMode(ScreenshotMode), arrival(ArrivalMotionMode)
    case desktopForm(RiftDesktopForm), trayTheme(RiftTrayTheme)
    case trayFavorite(RiftTrayFavoriteChoice)
    case configuration(RiftConfiguration), placement(RiftPlacement?)
    case display(id: UInt32?, uuid: String?), archiveHours(Double?)
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
    case edit(SettingsField, String), editArchive(String), restoreDefaults(SettingsDraftPage)
    case discardLayout, discardArchive, discardDrafts, applyLayout, applyArchive, applyDrafts
    case setCollectionPaused(Bool), setHidden(Bool), setEntryEnabled(Bool)
    case setCaptureMode(ScreenshotMode), setArrival(ArrivalMotionMode)
    case selectDesktopForm(RiftDesktopForm), selectTrayTheme(RiftTrayTheme)
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
    private var archiveText: String?
    private var domains: [SettingsDomain: SettingsDomainState]
    private var layoutEditVersions: [SettingsField: UInt64] = [:]
    private var archiveEditVersion: UInt64?
    private var pendingTextVersions: [SettingsDomain: TextVersions] = [:]
    private var writes: Set<SettingsDomain> = []

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
        .init(revision: revision, owner: owner, layoutText: layoutText,
              configurationDraft: configurationDraft,
              archiveText: archiveText, domains: domains)
    }

    public var configurationDraft: RiftConfiguration? {
        do { return try configuration(for: .layout(layoutPatch())) }
        catch { return nil }
    }

    public func text(for field: SettingsField) -> String {
        layoutText[field] ?? format(field.value(in: owner.settings.configuration) * field.scale)
    }
    public var archiveDraftText: String { archiveText ?? format(owner.settings.archiveAfterHours ?? 0) }

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
        guard let archiveText else { return false }
        do { return try parseArchive(archiveText) != owner.settings.archiveAfterHours }
        catch { return true }
    }

    /// Text delegates must finish the draft edit before the first Save/Close click.
    public func setDraftText(_ text: String, for field: SettingsField) {
        layoutText[field] = text; revision += 1; layoutEditVersions[field] = revision
        onChange?(snapshot)
    }
    public func setArchiveDraftText(_ text: String) {
        archiveText = text; revision += 1; archiveEditVersion = revision
        onChange?(snapshot)
    }

    @discardableResult public func perform(_ command: SettingsCommand) async -> SettingsSubmission {
        defer { onChange?(snapshot) }
        var result = SettingsSubmission()
        switch command {
        case .edit(let field, let text):
            setDraftText(text, for: field)
        case .editArchive(let text):
            setArchiveDraftText(text)
        case .restoreDefaults(let page):
            let defaults = RiftConfiguration()
            revision += 1
            for field in SettingsField.allCases where field.page == page && applicable(field) {
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
        case .applyDrafts:
            // Separate owners are not a transaction. Keep each actual result;
            // reserve both requests before either await. Neither is a queued
            // command that could overwrite a newer explicit save after waiting.
            let layout = prepareLayout(into: &result).flatMap { begin($0, into: &result) }
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
            guard value.isAvailable else { return result }
            await save(prepare(.desktopForm(value)), into: &result)
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

    private func layoutPatch() throws -> [SettingsField: Double] {
        try Dictionary(uniqueKeysWithValues: layoutText.filter { applicable($0.key) }.map { field, text in
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

    private func prepareLayout(into result: inout SettingsSubmission) -> PreparedSave? {
        guard !writes.contains(.layout) else { result.busy.append(.layout); return nil }
        do {
            if layoutText.isEmpty, let pending = prepareRetry(.layout) { return pending }
            let patch = try layoutPatch()
            if !hasLayoutDraft && domains[.layout]?.pending == nil {
                discard(.layout); return nil
            }
            return prepare(.layout(patch))
        } catch let error as SettingsValidationFailure { invalid(.layout, error, into: &result) }
        catch { invalid(.layout, .invalidConfiguration, into: &result) }
        return nil
    }

    private func prepareArchive(into result: inout SettingsSubmission) -> PreparedSave? {
        guard !writes.contains(.archive) else { result.busy.append(.archive); return nil }
        do {
            guard let archiveText else { return prepareRetry(.archive) }
            let hours = try parseArchive(archiveText)
            if hours == owner.settings.archiveAfterHours && domains[.archive]?.pending == nil {
                discard(.archive); return nil
            }
            return prepare(.archiveHours(hours))
        } catch { invalid(.archive, .invalidArchive, into: &result) }
        return nil
    }

    private func configuration(for intent: SettingsIntent) throws -> RiftConfiguration? {
        var candidate = owner.settings.configuration
        switch intent {
        case .layout(let patch):
            for (field, value) in patch {
                guard applicable(field) else { throw SettingsValidationFailure.inactiveLegacyField }
                try field.put(value, into: &candidate)
            }
        case .desktopForm(let value): candidate.desktopForm = value
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
        defer { writes.remove(work.writer); onChange?(snapshot) }
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
        case .archiveHours(let target): return value.settings.archiveAfterHours == target
        case .layout(let patch):
            // Confirm the requested fields. A concurrent owner observation may
            // legitimately change untouched fields before a rebased write.
            return patch.allSatisfy { $0.key.value(in: value.settings.configuration) == $0.value }
        case .desktopForm(let target): return value.settings.configuration.desktopForm == target
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
        case .trayTheme: return .trayTheme(value.settings.configuration.trayTheme)
        case .trayFavorite1: return .trayFavorite(value.settings.configuration.trayFavorite(.first))
        case .trayFavorite2: return .trayFavorite(value.settings.configuration.trayFavorite(.second))
        case .trayFavorite3: return .trayFavorite(value.settings.configuration.trayFavorite(.third))
        case .layout: return .configuration(value.settings.configuration)
        case .placement: return .placement(value.settings.configuration.placement)
        case .display: return .display(id: value.settings.configuration.preferredDisplayID, uuid: value.settings.configuration.preferredDisplayUUID)
        case .archive: return .archiveHours(value.settings.archiveAfterHours)
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
        case .archiveHours(let value):
            if archiveEditVersion == prepared.textVersions.archive, let text = archiveText {
                do { if try parseArchive(text) == value { archiveText = nil; archiveEditVersion = nil } }
                catch { /* A newer invalid draft is still the user's text. */ }
            }
        default: break
        }
    }

    private func discard(_ domain: SettingsDomain) {
        if domain == .layout { layoutText = [:]; layoutEditVersions = [:] }
        if domain == .archive { archiveText = nil; archiveEditVersion = nil }
        // Discarding text cannot cancel a write that the owner is already doing.
        // Its eventual result still needs to be surfaced.
        guard domains[domain]?.isSaving != true else { revision += 1; return }
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
    private func parseArchive(_ raw: String) throws -> Double? {
        guard let hours = parse(raw), hours >= 0, (hours * 3600).isFinite else {
            throw SettingsValidationFailure.invalidArchive
        }
        // Match the existing lifecycle owner's seconds-to-hours round trip.
        return hours == 0 ? nil : (hours * 3600) / 3600
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
        if let hours = owner.settings.archiveAfterHours {
            guard hours.isFinite, hours >= 0, (hours * 3600).isFinite else { throw SettingsValidationFailure.invalidArchive }
        }
    }
}
