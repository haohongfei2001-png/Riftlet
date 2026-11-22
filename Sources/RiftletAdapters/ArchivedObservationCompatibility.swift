import CryptoKit
import Foundation

/// These releases hashed the whole page program before the original host context.
/// Only verified SHA states are retained. No archived bytes become executable code.
enum ArchivedObservationCompatibility {
    private static let prefixes: [SHA256]? = {
        let bundle: Bundle
        if Bundle.main.bundleURL.pathExtension == "app" {
            guard let directory = Bundle.main.resourceURL,
                  let embedded = Bundle(url: directory.appendingPathComponent("Riftlet_RiftletAdapters.bundle"))
            else { return nil }
            bundle = embedded
        } else {
            bundle = .module
        }
        func prefix(build: Int, compressed: String, source: String, bytes: Int) -> SHA256? {
            guard let url = bundle.url(forResource: "build\(build)-observation-fingerprint", withExtension: "dat"),
                  let archived = try? Data(contentsOf: url), archived.count <= 64 * 1024,
                  hex(SHA256.hash(data: archived)) == compressed,
                  let data = try? (archived as NSData).decompressed(using: .lzfse), data.length == bytes
            else { return nil }
            var hash = SHA256()
            hash.update(data: data as Data)
            return hex(hash.finalize()) == source ? hash : nil
        }
        guard let build56 = prefix(build: 56, compressed: "ed470481df5373d0e702c87087785235d080fb75b85ea27f1e07408e0357ae52",
                                   source: "61669b502526bd01b71b6c9aead85c224d9f3a50263ff121997769527368e2c5", bytes: 117_213),
              let build57 = prefix(build: 57, compressed: "c691e6b7bd848bc8e1fb994aa9efd2dc7419b8b73549c0c1e31eb09499287e8a",
                                   source: "0ac5c59b4856f26a50f5f22d8142314444db361a69753d0ee32cb767d89be87f", bytes: 123_906)
        else { return nil }
        return [build56, build57]
    }()

    static func markers(contextJSON: String, legacyObservationSession: String?) -> [String]? {
        guard let prefixes, let legacy = try? JSONEncoder().encode(legacyObservationSession) else { return nil }
        var suffix = Data(("\n" + contextJSON + "\n").utf8)
        suffix.append(legacy)
        return prefixes.map { prefix in
            var hash = prefix
            hash.update(data: suffix)
            return hex(hash.finalize())
        }
    }

    private static func hex(_ digest: SHA256.Digest) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}
