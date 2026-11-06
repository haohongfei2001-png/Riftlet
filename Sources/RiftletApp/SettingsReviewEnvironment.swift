import Foundation
import RiftletCapture

/// Explicit native review environment in the same installable binary. It has
/// real local persistence/collection, but no browser, capture or cloud authority.
struct SettingsReviewEnvironment {
    enum Failure: Error { case invalidIdentifier, foreignDirectory }
    let identifier: UUID
    let root: URL
    var source: URL { root.appendingPathComponent("fixture-source", isDirectory: true) }
    var suiteName: String { "com.riftlet.settings-review." + identifier.uuidString.lowercased() }
    var defaults: UserDefaults { UserDefaults(suiteName: suiteName)! }
    var captureLocation: SystemCaptureLocationProvider {
        .init(preferencesFile: root.appendingPathComponent("fixture-location.plist"), fallbackDirectory: source)
    }

    static func identifier(in arguments: [String]) throws -> UUID {
        let indices = arguments.indices.filter { arguments[$0] == "--settings-review" }
        guard indices.count == 1, let index = indices.first, arguments.indices.contains(index + 1),
              let id = UUID(uuidString: arguments[index + 1]) else { throw Failure.invalidIdentifier }
        return id
    }

    static func directoryName(for identifier: UUID) -> String { "Riftlet-Settings-Review-" + identifier.uuidString.lowercased() }

    init(identifier: UUID, applicationSupport: URL) {
        self.identifier = identifier
        root = applicationSupport.standardizedFileURL.resolvingSymlinksInPath()
            .appendingPathComponent(Self.directoryName(for: identifier), isDirectory: true)
    }

    func prepare() throws {
        let manager = FileManager.default
        let marker = root.appendingPathComponent("settings-review-identity.txt")
        let expected = Data((identifier.uuidString.lowercased() + "\n").utf8)
        if manager.fileExists(atPath: root.path) {
            guard root.resolvingSymlinksInPath().standardizedFileURL == root.standardizedFileURL,
                  marker.resolvingSymlinksInPath().standardizedFileURL == marker.standardizedFileURL,
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
        guard source.resolvingSymlinksInPath().standardizedFileURL == source.standardizedFileURL else { throw Failure.foreignDirectory }
        try manager.createDirectory(at: source, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        // Never read the macOS Screenshot preference domain, even if a fixture
        // preference is later absent. A malformed preference fails closed.
        let preferences = root.appendingPathComponent("fixture-location.plist")
        let data = try PropertyListSerialization.data(fromPropertyList: ["location": source.path], format: .binary, options: 0)
        try data.write(to: preferences, options: .atomic)
    }
}
