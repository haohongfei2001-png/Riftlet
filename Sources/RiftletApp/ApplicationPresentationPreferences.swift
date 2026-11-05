import AppKit
import Foundation

enum ApplicationAppearanceChoice: String, Codable, CaseIterable, Sendable {
    case system, light, dark
}

/// Owns only the application appearance preference. Construction reads the
/// supplied file; it neither creates a data root nor changes an application.
@MainActor
final class ApplicationPresentationPreferences {
    static let fileName = "app-presentation-settings.json"

    enum LoadState: Equatable, Sendable { case unselected, selected, unreadable }
    enum Failure: Error, Equatable, Sendable { case preparationFailed, saveFailed }
    typealias PrepareAppearance = @MainActor (ApplicationAppearanceChoice) throws -> NSAppearance?
    typealias ApplyAppearance = @MainActor (NSAppearance?) -> Void
    typealias WriteDocument = @MainActor (Data, URL) throws -> Void

    let url: URL
    /// Last accepted preference, not a read of NSApp or the system theme.
    private(set) var selection: ApplicationAppearanceChoice = .system
    private(set) var loadState: LoadState = .unselected
    /// Historical confirmation only: a failed write may already have replaced
    /// the file before a later permission operation throws.
    private(set) var lastConfirmedSelection: ApplicationAppearanceChoice?
    private(set) var pendingSelection: ApplicationAppearanceChoice?
    private(set) var failure: Failure?
    /// Nil until the injected application callback has explicitly run.
    private(set) var appliedSelection: ApplicationAppearanceChoice?

    private let prepare: PrepareAppearance
    private let apply: ApplyAppearance
    private let write: WriteDocument

    init(url: URL,
         prepareAppearance: @escaping PrepareAppearance = { try ApplicationPresentationPreferences.prepareAppearance($0) },
         applyAppearance: @escaping ApplyAppearance,
         writeDocument: @escaping WriteDocument = { try ApplicationPresentationPreferences.writeDocument($0, to: $1) }) {
        self.url = url
        prepare = prepareAppearance
        apply = applyAppearance
        write = writeDocument
        do {
            guard let attributes = try Self.fileAttributes(at: url) else { return }
            guard attributes[.type] as? FileAttributeType == .typeRegular,
                  let size = attributes[.size] as? NSNumber,
                  size.int64Value <= 4_096 else { throw CocoaError(.fileReadCorruptFile) }
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            guard data.count <= 4_096 else { throw CocoaError(.fileReadCorruptFile) }
            let document = try JSONDecoder().decode(Document.self, from: data)
            selection = document.appearance
            lastConfirmedSelection = document.appearance
            loadState = .selected
        } catch {
            // An unreadable document remains untouched until an explicit choice
            // successfully replaces it. Cold startup safely follows the system.
            loadState = .unreadable
        }
    }

    /// An explicit user choice is prepared, saved, then applied, in that order.
    /// Failure retains the previous accepted/applied choice and this exact goal.
    func select(_ choice: ApplicationAppearanceChoice) throws {
        pendingSelection = choice
        let appearance: NSAppearance?
        do { appearance = try preparedAppearance(for: choice) }
        catch {
            failure = .preparationFailed
            throw Failure.preparationFailed
        }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try write(encoder.encode(Document(appearance: choice)), url)
        } catch {
            failure = .saveFailed
            throw Failure.saveFailed
        }
        selection = choice
        lastConfirmedSelection = choice
        loadState = .selected
        pendingSelection = nil
        failure = nil
        apply(appearance)
        appliedSelection = choice
    }

    /// No toggle inversion or automatic retry. A new explicit selection may
    /// replace the pending target; retry always uses the latest failed target.
    @discardableResult
    func retry() throws -> Bool {
        guard let target = pendingSelection else { return false }
        try select(target)
        return true
    }

    /// Reserved for explicit future host startup wiring. This applies the
    /// accepted selection without saving, including nil for system inheritance.
    /// It does not clear a separate pending save failure or replace its target.
    func applyAcceptedSelection() throws {
        let appearance: NSAppearance?
        do { appearance = try preparedAppearance(for: selection) }
        catch { throw Failure.preparationFailed }
        apply(appearance)
        appliedSelection = selection
    }

    static func prepareAppearance(_ choice: ApplicationAppearanceChoice) throws -> NSAppearance? {
        let name: NSAppearance.Name
        switch choice {
        case .system: return nil
        case .light: name = .aqua
        case .dark: name = .darkAqua
        }
        guard let appearance = NSAppearance(named: name) else { throw Failure.preparationFailed }
        return appearance
    }

    private func preparedAppearance(for choice: ApplicationAppearanceChoice) throws -> NSAppearance? {
        let appearance = try prepare(choice)
        // A missing explicit appearance must not silently become system mode.
        guard (choice == .system) == (appearance == nil) else { throw Failure.preparationFailed }
        return appearance
    }

    private static func fileAttributes(at url: URL) throws -> [FileAttributeKey: Any]? {
        guard url.isFileURL else { throw CocoaError(.fileReadUnsupportedScheme) }
        do { return try FileManager.default.attributesOfItem(atPath: url.path) }
        catch {
            let error = error as NSError
            if error.domain == NSCocoaErrorDomain,
               [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(error.code) { return nil }
            throw error
        }
    }

    /// Same small-file atomic replacement and private mode used by the existing
    /// capture-entry preferences; no new storage service or parent creation.
    static func writeDocument(_ data: Data, to url: URL) throws {
        if let attributes = try fileAttributes(at: url) {
            guard attributes[.type] as? FileAttributeType == .typeRegular else {
                throw CocoaError(.fileWriteInvalidFileName)
            }
        }
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private struct Document: Codable {
        let version: Int
        let appearance: ApplicationAppearanceChoice

        init(appearance: ApplicationAppearanceChoice) {
            version = 1
            self.appearance = appearance
        }

        private struct Key: CodingKey {
            let stringValue: String
            var intValue: Int? { nil }
            init?(stringValue: String) { self.stringValue = stringValue }
            init?(intValue: Int) { return nil }
            static let version = Key(stringValue: "version")!
            static let appearance = Key(stringValue: "appearance")!
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: Key.self)
            guard Set(values.allKeys.map(\.stringValue)) == ["version", "appearance"],
                  try values.decode(Int.self, forKey: .version) == 1 else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                        debugDescription: "Unsupported appearance document"))
            }
            version = 1
            appearance = try values.decode(ApplicationAppearanceChoice.self, forKey: .appearance)
        }

        func encode(to encoder: Encoder) throws {
            var values = encoder.container(keyedBy: Key.self)
            try values.encode(version, forKey: .version)
            try values.encode(appearance, forKey: .appearance)
        }
    }
}
