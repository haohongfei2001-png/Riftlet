#!/usr/bin/env swift
import CryptoKit
import Darwin
import Foundation
import Security

private typealias Report = [String: Any]
private let subjectDefault = "Riftlet Developer ID Application"
private let csrName = "Riftlet-Developer-ID-Application.certSigningRequest"
private let spkiName = "public-key.spki.der"

private struct Failure: Error {
    let reason: String
    let status: Int?
    init(_ reason: String, _ status: Int? = nil) { self.reason = reason; self.status = status }
}

private func check(_ status: OSStatus, _ reason: String) throws {
    if status != errSecSuccess { throw Failure(reason, Int(status)) }
}

private func secError(_ reason: String, _ error: Unmanaged<CFError>?) -> Failure {
    Failure(reason, error.map { CFErrorGetCode($0.takeRetainedValue()) })
}

private func sha(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

private func der(_ tag: UInt8, _ body: Data) -> Data {
    var length = [UInt8]()
    var count = body.count
    if count < 128 { length = [UInt8(count)] }
    else {
        while count > 0 { length.insert(UInt8(count & 255), at: 0); count >>= 8 }
        length.insert(0x80 | UInt8(length.count), at: 0)
    }
    return Data([tag] + length) + body
}

private func sequence(_ fields: Data...) -> Data { der(0x30, fields.reduce(Data(), +)) }
private let rsaOID = Data([0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01])
private func rsaAlgorithm(_ suffix: UInt8) -> Data {
    sequence(der(0x06, rsaOID + Data([suffix])), der(0x05, Data()))
}

private func publicSPKI(_ key: SecKey) throws -> Data {
    // This function accepts a public reference only. It never serializes a private key.
    guard let attrs = SecKeyCopyAttributes(key) as? [String: Any],
          attrs[kSecAttrKeyClass as String] as? String == kSecAttrKeyClassPublic as String,
          attrs[kSecAttrKeyType as String] as? String == kSecAttrKeyTypeRSA as String else {
        throw Failure("expectedRSAPublicKey")
    }
    var error: Unmanaged<CFError>?
    guard let publicPKCS1 = SecKeyCopyExternalRepresentation(key, &error) as Data? else {
        throw secError("publicKeyRepresentationUnavailable", error)
    }
    return sequence(rsaAlgorithm(1), der(0x03, Data([0]) + publicPKCS1))
}

private func makeCSR(_ privateKey: SecKey, publicKey: SecKey, spki: Data, subject: String, email: String?) throws -> Data {
    var names = der(0x31, sequence(der(0x06, Data([0x55, 0x04, 0x03])), der(0x0c, Data(subject.utf8))))
    if let email {
        let emailOID = Data([0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x09, 0x01])
        names += der(0x31, sequence(der(0x06, emailOID), der(0x16, Data(email.utf8))))
    }
    let info = sequence(der(0x02, Data([0])), der(0x30, names), spki, der(0xa0, Data()))
    var error: Unmanaged<CFError>?
    let algorithm = SecKeyAlgorithm.rsaSignatureMessagePKCS1v15SHA256
    guard let signature = SecKeyCreateSignature(privateKey, algorithm, info as CFData, &error) else {
        throw secError("csrSignatureFailed", error)
    }
    guard SecKeyVerifySignature(publicKey, algorithm, info as CFData, signature, &error) else {
        throw secError("csrSignatureVerificationFailed", error)
    }
    let binary = sequence(info, rsaAlgorithm(11), der(0x03, Data([0]) + (signature as Data)))
    let body = binary.base64EncodedString(options: [.lineLength64Characters, .endLineWithLineFeed])
    return Data(("-----BEGIN CERTIFICATE REQUEST-----\n" + body + "\n-----END CERTIFICATE REQUEST-----\n").utf8)
}

private func regularFile(_ url: URL) throws -> Bool {
    var info = stat()
    if lstat(url.path, &info) != 0 {
        if errno == ENOENT { return false }
        throw Failure("cannotInspectOutput", Int(errno))
    }
    guard info.st_mode & S_IFMT == S_IFREG else { throw Failure("outputIsNotARegularFile") }
    return true
}

private func preserveOrWrite(_ data: Data, at url: URL) throws {
    if try regularFile(url) {
        guard try Data(contentsOf: url) == data else { throw Failure("existingOutputDiffers") }
    } else {
        try data.write(to: url, options: .withoutOverwriting)
    }
}

private struct RequestState: Codable {
    let version: Int
    let id: UUID
    let commonName: String
    let email: String?
    let bits: Int
    var generationAttempted: Bool
    var publicSHA256: String?
    var csrSHA256: String?
    var tag: Data { Data(("org.riftlet.developer-id.application." + id.uuidString.lowercased()).utf8) }
    var label: String { "Riftlet Developer ID Application " + id.uuidString }

    func save(to url: URL, new: Bool = false) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: new ? .withoutOverwriting : .atomic)
    }
}

private func loginKeychain() throws -> SecKeychain {
    // Only this CLI process suppresses UI. A locked keychain or ACL challenge
    // is returned to the caller; no password, unlock, ACL edit or reset occurs.
    try check(SecKeychainSetUserInteractionAllowed(false), "cannotUseNoninteractiveKeychain")
    let path = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Keychains/login.keychain-db")
    var result: SecKeychain?
    try check(SecKeychainOpen(path.path, &result), "openLoginKeychain")
    guard let keychain = result else { throw Failure("missingLoginKeychain") }
    var status: SecKeychainStatus = 0
    try check(SecKeychainGetStatus(keychain, &status), "loginKeychainStatus")
    guard status & UInt32(kSecUnlockStateStatus) != 0 else { throw Failure("loginKeychainLocked") }
    return keychain
}

private func lookup(_ state: RequestState, in keychain: SecKeychain) throws -> SecKey? {
    let query: [CFString: Any] = [kSecClass: kSecClassKey, kSecAttrKeyClass: kSecAttrKeyClassPrivate,
        kSecAttrApplicationTag: state.tag, kSecMatchSearchList: [keychain],
        kSecMatchLimit: kSecMatchLimitAll, kSecReturnRef: true]
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound { return nil }
    try check(status, "lookupTaggedLoginKey")
    guard let keys = result as? [SecKey], keys.count == 1 else { throw Failure("ambiguousTaggedLoginKey") }
    return keys[0]
}

private func generate(bits: Int, state: RequestState?, keychain: SecKeychain?) throws -> SecKey {
    // The file-keychain implementation reads extractability at the top level
    // for the private key. RSA public keys remain exportable.
    var params: [CFString: Any] = [kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeySizeInBits: bits,
                                   kSecAttrIsExtractable: false, kSecAttrIsSensitive: true]
    if let state, let keychain {
        params[kSecUseKeychain] = keychain
        params[kSecPrivateKeyAttrs] = [kSecAttrIsPermanent: true, kSecAttrIsSensitive: true,
            kSecAttrIsExtractable: false, kSecAttrCanSign: true,
            kSecAttrApplicationTag: state.tag, kSecAttrLabel: state.label] as [CFString: Any]
    } else {
        params[kSecPrivateKeyAttrs] = [kSecAttrIsPermanent: false] as [CFString: Any]
    }
    var error: Unmanaged<CFError>?
    guard let key = SecKeyCreateRandomKey(params as CFDictionary, &error) else {
        throw secError("generateRSAKey", error)
    }
    return key
}

private func publishCSR(key: SecKey, state: RequestState, directory: URL) throws -> (String, String, Report) {
    guard let pub = SecKeyCopyPublicKey(key), let attrs = SecKeyCopyAttributes(key) as? [String: Any],
          (attrs[kSecAttrKeySizeInBits as String] as? NSNumber)?.intValue == state.bits else {
        throw Failure("keySizeOrPublicKeyMismatch")
    }
    let spki = try publicSPKI(pub), publicHash = sha(spki)
    if let expected = state.publicSHA256, expected != publicHash { throw Failure("recordedPublicKeyChanged") }
    try preserveOrWrite(spki, at: directory.appendingPathComponent(spkiName))
    let csrURL = directory.appendingPathComponent(csrName)
    let csrHash: String
    if let recorded = state.csrSHA256, try regularFile(csrURL) {
        csrHash = sha(try Data(contentsOf: csrURL))
        guard recorded == csrHash else { throw Failure("recordedCSRDigestChanged") }
    } else {
        let csr = try makeCSR(key, publicKey: pub, spki: spki, subject: state.commonName, email: state.email)
        csrHash = sha(csr)
        if let recorded = state.csrSHA256, recorded != csrHash { throw Failure("recreatedCSRDigestChanged") }
        try preserveOrWrite(csr, at: csrURL)
    }
    var report: Report = ["result": "CSR_READY", "bits": state.bits, "signature": "sha256WithRSAEncryption",
                          "publicKeySPKISHA256": publicHash, "csrSHA256": csrHash,
                          "csrFile": csrName, "emailIncluded": state.email != nil, "privateKeyExported": false]
    if let extractable = attrs[kSecAttrIsExtractable as String] as? NSNumber {
        report["keyReportedExtractable"] = extractable.boolValue
    }
    if let sensitive = attrs[kSecAttrIsSensitive as String] as? NSNumber {
        report["keyReportedSensitive"] = sensitive.boolValue
    }
    return (publicHash, csrHash, report)
}

private func create(directory: URL, options: [String: String], ephemeral: Bool) throws -> Report {
    let subject = options["--common-name"] ?? subjectDefault, email = options["--email"]
    let bits = Int(options["--bits"] ?? "2048") ?? 0
    guard [2048, 3072].contains(bits), !subject.isEmpty, subject.utf8.count <= 64,
          subject.rangeOfCharacter(from: .controlCharacters) == nil,
          email.map({ $0.utf8.count <= 254 && $0.split(separator: "@", omittingEmptySubsequences: false).count == 2 &&
              !$0.hasPrefix("@") && !$0.hasSuffix("@") && $0.utf8.allSatisfy { (33...126).contains($0) } }) ?? true else {
        throw Failure("invalidSubjectOrKeySize")
    }
    let url = directory.appendingPathComponent("request-state.json")
    var state = RequestState(version: 1, id: UUID(), commonName: subject, email: email, bits: bits, generationAttempted: false)
    if ephemeral {
        guard try !regularFile(url) else { throw Failure("testFixtureCannotUsePersistentState") }
        let key = try generate(bits: bits, state: nil, keychain: nil)
        var report = try publishCSR(key: key, state: state, directory: directory).2
        report["keyStorage"] = "ephemeralTestOnly"
        return report
    }
    let keychain = try loginKeychain()
    if try regularFile(url) {
        state = try JSONDecoder().decode(RequestState.self, from: Data(contentsOf: url))
        guard state.version == 1, state.commonName == subject, state.email == email, state.bits == bits else {
            throw Failure("existingRequestParametersDiffer")
        }
    } else {
        guard try !regularFile(directory.appendingPathComponent(csrName)),
              try !regularFile(directory.appendingPathComponent(spkiName)) else { throw Failure("unownedRequestOutputs") }
        try state.save(to: url, new: true)
    }
    let existing = try lookup(state, in: keychain)
    if existing != nil, !state.generationAttempted { throw Failure("existingKeyTagCollision") }
    if existing == nil {
        guard !state.generationAttempted, state.publicSHA256 == nil, state.csrSHA256 == nil else {
            throw Failure("previousGenerationAttemptHasNoConfirmedKey")
        }
        state.generationAttempted = true
        try state.save(to: url)  // Persist intent before the one irreversible operation.
        _ = try generate(bits: state.bits, state: state, keychain: keychain)
    }
    guard let key = try lookup(state, in: keychain) else { throw Failure("newKeyNotFoundInLoginKeychain") }
    let (publicHash, csrHash, output) = try publishCSR(key: key, state: state, directory: directory)
    if state.publicSHA256 != publicHash || state.csrSHA256 != csrHash {
        state.publicSHA256 = publicHash
        state.csrSHA256 = csrHash
        try state.save(to: url)
    }
    var report = output
    report["keyStorage"] = "userLoginKeychain"
    report["createdKey"] = existing == nil
    report["requestedNonExtractable"] = true
    report["requestID"] = state.id.uuidString
    return report
}

// DER SHA-256 for Apple's three root certificates published on Apple PKI.
private let appleRoots: Set<String> = [
    "b0b1730ecbc7ff4505142c49f1295e6eda6bcaed7e2c68c5be91b5a11001f024",
    "c2b9b042dd57830e7d117dac55ac8ae19407d38e41d88f3215bc3a890444a050",
    "63343abfb89a6a03ebb57e9b3f5fa7be7c4f5c756f3017b3a8c488c3653e9179",
]
private let applicationOID = "1.2.840.113635.100.6.1.13"
private let issuerOID = "1.2.840.113635.100.6.2.6"

private func property(_ certificate: SecCertificate, _ oid: String) -> [String: Any]? {
    let values = SecCertificateCopyValues(certificate, [oid] as CFArray, nil) as? [String: [String: Any]]
    return values?[oid]
}

private func readCertificate(_ path: String) throws -> SecCertificate {
    let bytes = try Data(contentsOf: URL(fileURLWithPath: path))
    guard let cert = SecCertificateCreateWithData(nil, bytes as CFData) else { throw Failure("invalidDERCertificate") }
    return cert
}

private func verifyCertificate(_ cert: SecCertificate, issuer: SecCertificate?, team: String, spki: Data) throws -> Report {
    guard team.utf8.count == 10, team.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) }) else {
        throw Failure("invalidExpectedTeamID")
    }
    guard let key = SecCertificateCopyKey(cert), try publicSPKI(key) == spki else { throw Failure("certificatePublicKeyMismatch") }
    guard property(cert, applicationOID) != nil else { throw Failure("notDeveloperIDApplication") }
    let subject = property(cert, kSecOIDX509V1SubjectName as String)?[kSecPropertyKeyValue as String] as? [[String: Any]]
    let units = subject?.filter { $0[kSecPropertyKeyLabel as String] as? String == kSecOIDOrganizationalUnitName as String }
    guard units?.count == 1, units?.first?[kSecPropertyKeyValue as String] as? String == team else {
        throw Failure("certificateTeamMismatch")
    }
    guard let policy = SecPolicyCreateWithProperties(kSecPolicyAppleCodeSigning, nil) else { throw Failure("codeSigningPolicyUnavailable") }
    var object: SecTrust?
    let certificates = [cert] + (issuer.map { [$0] } ?? [])
    try check(SecTrustCreateWithCertificates(certificates as CFArray, policy, &object), "createCertificateTrust")
    guard let trust = object else { throw Failure("missingCertificateTrust") }
    var systemAnchors: CFArray?
    try check(SecTrustCopyAnchorCertificates(&systemAnchors), "readSystemTrustAnchors")
    let anchors = (systemAnchors as? [SecCertificate] ?? []).filter { appleRoots.contains(sha(SecCertificateCopyData($0) as Data)) }
    guard !anchors.isEmpty else { throw Failure("systemAppleRootUnavailable") }
    try check(SecTrustSetAnchorCertificates(trust, anchors as CFArray), "setAppleTrustAnchors")
    try check(SecTrustSetAnchorCertificatesOnly(trust, true), "restrictToAppleTrustAnchors")
    var error: CFError?
    guard SecTrustEvaluateWithError(trust, &error) else {
        throw Failure("certificateChainOrCurrentValidityFailed", error.map(CFErrorGetCode))
    }
    guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate], chain.count >= 3,
          property(chain[1], issuerOID) != nil, let anchor = chain.last,
          appleRoots.contains(sha(SecCertificateCopyData(anchor) as Data)) else { throw Failure("notAppleDeveloperIDIssuer") }
    var report: Report = ["result": "VERIFIED_DEVELOPER_ID_APPLICATION", "teamID": team,
        "certificateSHA256": sha(SecCertificateCopyData(cert) as Data), "publicKeySPKISHA256": sha(spki),
        "appleRootSHA256": sha(SecCertificateCopyData(anchor) as Data), "currentCodeSigningTrustValid": true,
        "developerIDApplicationOID": applicationOID, "developerIDIssuerOID": issuerOID, "certificateWritePerformed": false]
    if #available(macOS 15.0, *), let from = SecCertificateCopyNotValidBeforeDate(cert) as Date?,
       let through = SecCertificateCopyNotValidAfterDate(cert) as Date? {
        let now = Date()
        guard from <= now, now <= through else { throw Failure("certificateOutsideValidityPeriod") }
        let format = ISO8601DateFormatter()
        report["notBefore"] = format.string(from: from)
        report["notAfter"] = format.string(from: through)
    }
    return report
}

private func certificateAction(directory: URL, options: [String: String], install: Bool) throws -> Report {
    guard let path = options["--certificate"], let team = options["--team"] else { throw Failure("usage") }
    let cert = try readCertificate(path)
    let issuer = try options["--issuer"].map(readCertificate)
    let publicURL = directory.appendingPathComponent(spkiName)
    guard try regularFile(publicURL) else { throw Failure("missingRequestPublicKey") }
    let spki = try Data(contentsOf: publicURL)
    var report = try verifyCertificate(cert, issuer: issuer, team: team, spki: spki)

    let stateURL = directory.appendingPathComponent("request-state.json")
    guard try regularFile(stateURL) else { throw Failure("missingPersistentRequestState") }
    let state = try JSONDecoder().decode(RequestState.self, from: Data(contentsOf: stateURL))
    let csrURL = directory.appendingPathComponent(csrName)
    guard state.version == 1, state.generationAttempted, state.publicSHA256 == sha(spki),
          try regularFile(csrURL), try state.csrSHA256 == sha(Data(contentsOf: csrURL)) else {
        throw Failure("requestStateDoesNotMatchPublishedFiles")
    }
    let login = try loginKeychain()
    guard let privateKey = try lookup(state, in: login), let pub = SecKeyCopyPublicKey(privateKey),
          try publicSPKI(pub) == spki else { throw Failure("matchingLoginPrivateKeyUnavailable") }
    report["recordedCSRAndLoginPublicKeyMatched"] = true
    if !install { return report }

    var serialError: Unmanaged<CFError>?
    guard let serial = SecCertificateCopySerialNumberData(cert, &serialError) else {
        throw secError("certificateSerialUnavailable", serialError)
    }
    let add: [CFString: Any] = [kSecClass: kSecClassCertificate, kSecValueRef: cert, kSecUseKeychain: login]
    let status = SecItemAdd(add as CFDictionary, nil)
    if status != errSecDuplicateItem { try check(status, "addVerifiedCertificateToLoginKeychain") }
    report["certificateWritePerformed"] = status == errSecSuccess
    report["certificateAddedThisRun"] = status == errSecSuccess
    let query: [CFString: Any] = [kSecClass: kSecClassCertificate, kSecAttrSerialNumber: serial,
        kSecMatchSearchList: [login], kSecMatchLimit: kSecMatchLimitAll, kSecReturnRef: true]
    var found: CFTypeRef?
    let readback = SecItemCopyMatching(query as CFDictionary, &found)
    let der = SecCertificateCopyData(cert) as Data
    guard readback == errSecSuccess, let same = (found as? [SecCertificate])?.first(where: { SecCertificateCopyData($0) as Data == der }) else {
        report["result"] = "CERTIFICATE_ADD_FINISHED_READBACK_UNCONFIRMED"
        report["readbackOSStatus"] = readback
        return report
    }
    report["certificatePresentInLoginKeychain"] = true
    var identity: SecIdentity?
    let identityStatus = SecIdentityCreateWithCertificate(login, same, &identity)
    report["identityCheckOSStatus"] = identityStatus
    guard identityStatus == errSecSuccess, identity != nil else {
        report["result"] = "CERTIFICATE_ADD_FINISHED_IDENTITY_UNCONFIRMED"
        return report
    }
    report["result"] = "INSTALLED_DEVELOPER_ID_APPLICATION"
    report["certificateInstalled"] = true
    return report
}

private func run(_ args: [String]) throws -> Report {
    guard let action = args.first, ["create", "test-request", "verify-certificate", "install-certificate"].contains(action),
          args.count % 2 == 1 else { throw Failure("usage") }
    let isCreate = action == "create" || action == "test-request"
    let allowed: Set<String> = isCreate ? ["--directory", "--common-name", "--email", "--bits"] :
        ["--directory", "--certificate", "--issuer", "--team"]
    var options = [String: String]()
    for index in stride(from: 1, to: args.count, by: 2) {
        let name = args[index], value = args[index + 1]
        guard allowed.contains(name), options[name] == nil, !value.isEmpty else { throw Failure("usage") }
        options[name] = value
    }
    guard let path = options["--directory"] else { throw Failure("usage") }
    let directory = URL(fileURLWithPath: path, isDirectory: true)
    let fd = open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
    guard fd >= 0 else { throw Failure("openRequestDirectory", Int(errno)) }
    defer { close(fd) }
    var info = stat()
    guard fstat(fd, &info) == 0, info.st_uid == geteuid(), info.st_mode & 0o022 == 0 else { throw Failure("unsafeRequestDirectory") }
    guard flock(fd, LOCK_EX) == 0 else { throw Failure("lockRequestDirectory", Int(errno)) }
    if isCreate { return try create(directory: directory, options: options, ephemeral: action == "test-request") }
    return try certificateAction(directory: directory, options: options, install: action == "install-certificate")
}

private func output(_ report: Report) {
    if let bytes = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
        print(String(decoding: bytes, as: UTF8.self))
    }
}

umask(0o077)
do {
    let result = try run(Array(CommandLine.arguments.dropFirst()))
    output(result)
    exit((result["result"] as? String)?.hasSuffix("_UNCONFIRMED") == true ? 1 : 0)
} catch let error as Failure {
    var result: Report = ["result": "FAILED", "reason": error.reason]
    if let status = error.status { result["status"] = status }
    if error.reason == "usage" {
        result["usage"] = ["create --directory DIR [--bits 2048|3072] [--common-name NAME] [--email ADDRESS]",
            "verify-certificate|install-certificate --directory DIR --certificate LEAF.cer --team TEAMID [--issuer CA.cer]",
            "test-request --directory EMPTY_DIR [--bits 2048|3072] (ephemeral key, no Keychain)"]
    }
    output(result)
    exit(error.reason == "usage" ? 64 : 1)
} catch {
    let error = error as NSError
    output(["result": "FAILED", "reason": "fileOrStateError", "status": error.code])
    exit(1)
}
