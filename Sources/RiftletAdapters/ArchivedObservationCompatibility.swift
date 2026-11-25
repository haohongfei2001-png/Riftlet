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
                                   source: "0ac5c59b4856f26a50f5f22d8142314444db361a69753d0ee32cb767d89be87f", bytes: 123_906),
              let build58 = prefix(build: 58, compressed: "d05979dfae4b702d907b1f7f50a6312f9d7c25a5c6b484ed493bbfd39d9f6fbb",
                                   source: "43e43df544d4edb6081dfe592b1b18166039f98983ab8f0fac0f31efdf60d166", bytes: 125_752),
              let build59 = prefix(build: 59, compressed: "19677788b6a846b2868e0159d8467f9de37544a2ffc24bfd1676b499314580f5",
                                   source: "b6eee615982d839285ea6af4abb16018939f9be91b18215554e847f4a6eb2215", bytes: 133_936),
              let build60 = prefix(build: 60, compressed: "3b0e9863be0e542c816f7688f9a880e1a2811e979d33636a611fa8127b76fde6",
                                   source: "a4da18056ed85a5a360f30f22c6965138d917cfde2c404e9aa24422b1f7b8250", bytes: 141_709),
              let build61 = prefix(build: 61, compressed: "e11bbf207a9649b390944a6024409ba399a638924b0ff4210366c8e0cefdc9c6",
                                   source: "2f6e2f6e1d80184813f6f967cc340638b96082abd5bd98c2f9e97b0597f982f2", bytes: 142_523),
              let build67 = prefix(build: 67, compressed: "d8f2abcb8a3f1d2230f05a2836e6c8753e9bc6ab04b49ef25281400867061ad1",
                                   source: "72a7f8174d5eefa3cdcbd466408ebd5a35d236e585bcfc14b330eb3a95bbf995", bytes: 151_055)
        else { return nil }
        return [build56, build57, build58, build59, build60, build61, build67]
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
