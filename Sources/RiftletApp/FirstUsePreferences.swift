import Foundation

/// Presentation only. Never stores permission, upload admission or queue state.
struct FirstUsePreferences {
    private let defaults: UserDefaults
    private let presentedKey: String
    private let progressKey: String

    init(defaults: UserDefaults = .standard, modeName: String) {
        self.defaults = defaults
        presentedKey = "Riftlet.firstUse.presented.v1.\(modeName)"
        progressKey = "Riftlet.firstUse.setup.v2.\(modeName)"
    }

    var hasPresented: Bool { defaults.bool(forKey: presentedKey) }

    var needsAutomaticPresentation: Bool {
        if let progress = defaults.string(forKey: progressKey) { return progress != "completed" }
        // Existing installations already chose how they use Riftlet.
        return !defaults.bool(forKey: presentedKey)
    }

    /// Mark when the window is actually presented, not on a background refresh.
    /// Closing it is not consent to any system permission or external input.
    func recordPresentation() {
        if defaults.object(forKey: progressKey) == nil && !defaults.bool(forKey: presentedKey) {
            defaults.set("started", forKey: progressKey)
        }
        defaults.set(true, forKey: presentedKey)
    }

    func recordCompletion() { defaults.set("completed", forKey: progressKey) }
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
    enum Restoration { case noApplicableBookmark, matchingBookmark, needsSelection }
    private var activeURL: URL?
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, modeName: String) {
        self.defaults = defaults; key = "Riftlet.sourceAccess.v1.\(modeName)"
    }

    @discardableResult
    func restore(for source: URL) -> Restoration {
        stop()
        return inspect(source, activate: true)
    }

    // Watch callbacks may outlive the directory that was originally selected.
    // Revalidate before reading, without dropping the active security scope.
    func permitsRead(of source: URL) -> Bool {
        inspect(source, activate: false) != .needsSelection
    }

    private func inspect(_ source: URL, activate: Bool) -> Restoration {
        guard let stored = defaults.object(forKey: key) else { return .noApplicableBookmark }
        guard let data = stored as? Data else { return .needsSelection }
        let savedPath = NSURL.resourceValues(forKeys: [.pathKey], fromBookmarkData: data)?[.pathKey] as? String
        let wasSelectedPath = savedPath.map {
            SourceAccessSelection.matches(selected: URL(fileURLWithPath: $0, isDirectory: true), actualSource: source)
        }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data,
                                options: [.withSecurityScope, .withoutUI, .withoutMounting],
                                relativeTo: nil, bookmarkDataIsStale: &stale) else {
            return wasSelectedPath == false ? .noApplicableBookmark : .needsSelection
        }
        guard SourceAccessSelection.matches(selected: url, actualSource: source) else {
            return wasSelectedPath == true ? .needsSelection : .noApplicableBookmark
        }
        // A stale bookmark can resolve to a new directory at the same path.
        // Only the user's selection can replace the previously saved bytes.
        guard !stale else { return .needsSelection }
        // A false result is not a permission verdict (e.g. an unsandboxed app
        // may already have access). The collector performs the real read check.
        if activate && url.startAccessingSecurityScopedResource() { activeURL = url }
        return .matchingBookmark
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
    var recoverySuggestion: String? { "请选择窗口中显示的截图文件夹。可以在 macOS「截屏」的「选项」中查看保存位置。" }
}
