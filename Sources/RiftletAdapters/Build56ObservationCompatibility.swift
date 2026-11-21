import CryptoKit
import Foundation

/// Private 1.0.7 build 56 included the exact page program bytes in each relay marker.
/// Only the digest state is retained. The archived bytes never become a page command.
enum Build56ObservationCompatibility {
    private static let sourcePrefix: SHA256? = {
        let resources: Bundle
        if Bundle.main.bundleURL.pathExtension == "app" {
            guard let directory = Bundle.main.resourceURL,
                  let embedded = Bundle(url: directory.appendingPathComponent("Riftlet_RiftletAdapters.bundle"))
            else { return nil }
            resources = embedded
        } else {
            resources = .module
        }
        guard let url = resources.url(forResource: "build56-observation-fingerprint", withExtension: "dat"),
              let compressed = try? Data(contentsOf: url), compressed.count == 33_176,
              hex(SHA256.hash(data: compressed)) == "ed470481df5373d0e702c87087785235d080fb75b85ea27f1e07408e0357ae52",
              let decoded = try? (compressed as NSData).decompressed(using: .lzfse),
              decoded.length == 117_213 else { return nil }

        let bytes = decoded as Data
        guard hex(SHA256.hash(data: bytes)) == "61669b502526bd01b71b6c9aead85c224d9f3a50263ff121997769527368e2c5" else {
            return nil
        }
        var prefix = SHA256()
        prefix.update(data: bytes)
        return prefix
    }()

    static func marker(contextJSON: String, legacyObservationSession: String?) -> String? {
        guard var hash = sourcePrefix,
              let legacy = try? JSONEncoder().encode(legacyObservationSession) else { return nil }
        hash.update(data: Data(("\n" + contextJSON + "\n").utf8))
        hash.update(data: legacy)
        return hex(hash.finalize())
    }

    private static func hex(_ digest: SHA256.Digest) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}
