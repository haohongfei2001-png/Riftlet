import Foundation
import RiftletCapture

/// Storage for separately owned sessions in the installable binary. The App
/// mode, independently of these paths, chooses the adapter and capture policy.
struct SettingsReviewEnvironment {
    enum Failure: Error { case invalidIdentifier, foreignDirectory }
    let identifier: UUID
    let root: URL
    let isPreClickQA: Bool
    var source: URL { root.appendingPathComponent(isPreClickQA ? "capture-source" : "fixture-source", isDirectory: true) }
    var suiteName: String { (isPreClickQA ? "com.riftlet.preclick-qa." : "com.riftlet.settings-review.") + identifier.uuidString.lowercased() }
    var defaults: UserDefaults { UserDefaults(suiteName: suiteName)! }
    var captureLocation: any CaptureLocationProviding {
        if isPreClickQA { return PreClickQAEnvironment.FixedSource(directory: source) }
        return SystemCaptureLocationProvider(preferencesFile: root.appendingPathComponent("fixture-location.plist"), fallbackDirectory: source)
    }

    static func identifier(in arguments: [String]) throws -> UUID {
        let indices = arguments.indices.filter { arguments[$0] == "--settings-review" }
        guard indices.count == 1, let index = indices.first, arguments.indices.contains(index + 1),
              let id = UUID(uuidString: arguments[index + 1]) else { throw Failure.invalidIdentifier }
        return id
    }

    static func directoryName(for identifier: UUID) -> String { "Riftlet-Settings-Review-" + identifier.uuidString.lowercased() }

    init(identifier: UUID, applicationSupport: URL, isPreClickQA: Bool = false) {
        self.identifier = identifier
        self.isPreClickQA = isPreClickQA
        let name = isPreClickQA ? "Riftlet-PreClick-QA-" + identifier.uuidString.lowercased() : Self.directoryName(for: identifier)
        root = applicationSupport.standardizedFileURL.resolvingSymlinksInPath().appendingPathComponent(name, isDirectory: true)
    }

    func prepare() throws {
        let manager = FileManager.default
        let marker = root.appendingPathComponent("settings-review-identity.txt")
        let expected = Data((identifier.uuidString.lowercased() + "\n").utf8)
        if manager.fileExists(atPath: root.path) {
            if isPreClickQA { try PreClickQAEnvironment.checkOwnership(root: root, marker: marker, byteCount: expected.count) }
            guard root.resolvingSymlinksInPath().standardizedFileURL.path == root.standardizedFileURL.path,
                  marker.resolvingSymlinksInPath().standardizedFileURL.path == marker.standardizedFileURL.path,
                  try Data(contentsOf: marker) == expected else { throw Failure.foreignDirectory }
        } else {
            try manager.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try expected.write(to: marker, options: .withoutOverwriting)
        }
    }

    /// Call only after winning the existing whole-App ownership lock. A losing
    /// second launch may validate identity but cannot change an in-use fixture.
    func prepareFixtures() throws {
        let manager = FileManager.default
        if isPreClickQA { try PreClickQAEnvironment.checkTree(root: root) }
        // Foundation may change a nonexistent directory URL's directory hint
        // while resolving it. Compare canonical filesystem paths, not that
        // metadata; actual links must still resolve to a different path.
        guard source.resolvingSymlinksInPath().standardizedFileURL.path == source.standardizedFileURL.path else { throw Failure.foreignDirectory }
        try manager.createDirectory(at: source, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        if isPreClickQA { return }
        // Never read the macOS Screenshot preference domain, even if a fixture
        // preference is later absent. A malformed preference fails closed.
        let preferences = root.appendingPathComponent("fixture-location.plist")
        let data = try PropertyListSerialization.data(fromPropertyList: ["location": source.path], format: .binary, options: 0)
        try data.write(to: preferences, options: .atomic)
    }
}
