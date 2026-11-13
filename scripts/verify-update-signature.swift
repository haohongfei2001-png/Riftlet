// Standalone public-key verification for CI and release consumers. No keychain access.
import CryptoKit
import Foundation

func die(_ message: String) -> Never {
    FileHandle.standardError.write(Data(("Update verification: " + message + "\n").utf8))
    exit(1)
}

do {
    let args = Array(CommandLine.arguments.dropFirst())
    guard args.count == 2 || args.count == 3 else {
        die("expected Info.plist and signed XML, or Info.plist, archive and detached signature")
    }
    let plist = try Data(contentsOf: URL(fileURLWithPath: args[0]))
    let info = try PropertyListSerialization.propertyList(from: plist, format: nil) as? [String: Any]
    guard let text = info?["SUPublicEDKey"] as? String, let pub = Data(base64Encoded: text) else {
        die("invalid public key")
    }
    let key = try Curve25519.Signing.PublicKey(rawRepresentation: pub)
    let file = try Data(contentsOf: URL(fileURLWithPath: args[1]), options: [.mappedIfSafe])
    let content: Data
    let signature: Data
    if args.count == 3 {
        guard let detached = Data(base64Encoded: args[2]) else { die("invalid archive signature") }
        signature = detached
        content = file
    } else {
        // Official sign_update appends this exact block after the bytes it signs.
        let start = Data("<!-- sparkle-signatures:\n".utf8)
        guard let marker = file.range(of: start, options: .backwards),
              let trailer = String(data: file[marker.upperBound...], encoding: .utf8) else {
            die("missing signed feed trailer")
        }
        let fields = trailer.components(separatedBy: "\n")
        guard fields.count == 4, fields[0].hasPrefix("edSignature: "), fields[1].hasPrefix("length: "),
              fields[2] == "-->", fields[3].isEmpty,
              let detached = Data(base64Encoded: String(fields[0].dropFirst("edSignature: ".count))),
              let length = Int(fields[1].dropFirst("length: ".count)), length == marker.lowerBound else {
            die("invalid signed feed length or trailer")
        }
        content = file[..<marker.lowerBound]
        signature = detached
    }
    guard signature.count == 64, key.isValidSignature(signature, for: content) else {
        die("signature does not match the App public key")
    }
} catch {
    die(error.localizedDescription)
}
