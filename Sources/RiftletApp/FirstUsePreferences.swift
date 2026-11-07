import Foundation

/// Presentation only. Never stores permission, upload admission or queue state.
struct FirstUsePreferences {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, modeName: String) {
        self.defaults = defaults
        key = "Riftlet.firstUse.presented.v1.\(modeName)"
    }

    var needsAutomaticPresentation: Bool { !defaults.bool(forKey: key) }

    /// Mark when the window is actually presented, not on a background refresh.
    /// Closing it is not consent to any system permission or external input.
    func recordPresentation() { defaults.set(true, forKey: key) }
}

/// A user-selected folder grants access only to the system's actual screenshot
/// destination. It cannot silently redirect the collector to a different folder.
enum SourceAccessSelection {
    static func matches(selected: URL, actualSource: URL) -> Bool {
        selected.isFileURL && actualSource.isFileURL &&
        selected.standardizedFileURL.resolvingSymlinksInPath().path ==
        actualSource.standardizedFileURL.resolvingSymlinksInPath().path
    }

    static func validate(selected: URL, actualSource: URL?) throws {
        guard let actualSource, matches(selected: selected, actualSource: actualSource) else {
            throw SourceAccessError.differentFolder
        }
    }
}

@MainActor
final class ScreenshotFolderAccess {
    private var activeURL: URL?
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, modeName: String) {
        self.defaults = defaults; key = "Riftlet.sourceAccess.v1.\(modeName)"
    }

    func restore(for source: URL) {
        stop()
        guard let data = defaults.data(forKey: key) else { return }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data,
                                options: [.withSecurityScope, .withoutUI, .withoutMounting],
                                relativeTo: nil, bookmarkDataIsStale: &stale),
              SourceAccessSelection.matches(selected: url, actualSource: source) else { return }
        // A false result is not a permission verdict (e.g. an unsandboxed app
        // may already have access). The collector performs the real read check.
        if url.startAccessingSecurityScopedResource() { activeURL = url }
        if stale { try? save(url) }
    }

    func accept(_ selected: URL, actualSource: URL) throws {
        try SourceAccessSelection.validate(selected: selected, actualSource: actualSource)
        stop()
        if selected.startAccessingSecurityScopedResource() { activeURL = selected }
        try save(selected)
    }

    func stop() { activeURL?.stopAccessingSecurityScopedResource(); activeURL = nil }

    private func save(_ url: URL) throws {
        let bookmark = try url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                                           includingResourceValuesForKeys: nil, relativeTo: nil)
        defaults.set(bookmark, forKey: key)
    }
}

enum SourceAccessError: LocalizedError {
    case differentFolder
    var errorDescription: String? { "所选文件夹与当前系统截图位置不同。" }
    var recoverySuggestion: String? { "请选择窗口中显示的截图文件夹。可以按 ⇧⌘5，在“选项”中确认保存位置。" }
}
