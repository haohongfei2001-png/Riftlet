#!/usr/bin/env swift
import Darwin
import Foundation
import Security

// Compare frozen .app bundles before replacement. A match only describes code
// identity. Directory access and system permission decisions are not inspected.
// Exit codes: 0 matches, 1 invalid or unverifiable, 2 identity mismatch, 64 usage.
private let validationFlags = SecCSFlags(rawValue:
    kSecCSStrictValidate | kSecCSCheckAllArchitectures | kSecCSCheckNestedCode).union(.noNetworkAccess)

private struct Inspection: Encodable {
    var signatureValid: Bool?
    var bundleIdentifier: String?
    var signingIdentifier: String?
    var teamIdentifier: String?
    var adHocSignature: Bool?
    var cdHash: String?
    var designatedRequirement: String?
    var failure: String?
    var osStatus: OSStatus?
}

private struct SignedApp {
    let code: SecStaticCode
    let requirement: SecRequirement
}

private func inspect(_ path: String) -> (Inspection, SignedApp?) {
    var report = Inspection()
    func failed(_ stage: String, _ status: OSStatus? = nil) -> (Inspection, SignedApp?) {
        report.failure = stage
        report.osStatus = status
        return (report, nil)
    }

    let url = URL(fileURLWithPath: path, isDirectory: true)
    var directory: ObjCBool = false
    guard url.pathExtension.lowercased() == "app",
          FileManager.default.fileExists(atPath: url.path, isDirectory: &directory),
          directory.boolValue else { return failed("notAnApplicationBundle") }

    var staticCode: SecStaticCode?
    let open = SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode)
    guard open == errSecSuccess, let code = staticCode else { return failed("openStaticCode", open) }
    let validity = SecStaticCodeCheckValidity(code, validationFlags, nil)
    report.signatureValid = validity == errSecSuccess
    guard report.signatureValid == true else { return failed("signatureValidation", validity) }

    var information: CFDictionary?
    let signing = SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information)
    guard signing == errSecSuccess, let info = information as? [String: Any] else {
        return failed("signingInformation", signing)
    }
    guard let plist = info[kSecCodeInfoPList as String] as? [String: Any],
          plist["CFBundlePackageType"] as? String == "APPL",
          let bundleID = plist["CFBundleIdentifier"] as? String, !bundleID.isEmpty,
          let signingID = info[kSecCodeInfoIdentifier as String] as? String, !signingID.isEmpty,
          let hash = info[kSecCodeInfoUnique as String] as? Data, !hash.isEmpty else {
        return failed("incompleteSignedApplicationMetadata")
    }
    report.bundleIdentifier = bundleID
    report.signingIdentifier = signingID
    report.teamIdentifier = info[kSecCodeInfoTeamIdentifier as String] as? String
    if let flags = info[kSecCodeInfoFlags as String] as? NSNumber {
        report.adHocSignature = SecCodeSignatureFlags(rawValue: flags.uint32Value).contains(.adhoc)
    }
    report.cdHash = hash.map { String(format: "%02x", $0) }.joined()
    // Security also signs resource-only bundles. Confirm that the sealed plist
    // identifies an actual executable contained in the supplied application.
    guard let name = plist["CFBundleExecutable"] as? String, !name.isEmpty,
          let executable = info[kSecCodeInfoMainExecutable as String] as? URL,
          executable.isFileURL, executable.lastPathComponent == name,
          executable.resolvingSymlinksInPath().path.hasPrefix(url.resolvingSymlinksInPath().path + "/"),
          FileManager.default.isExecutableFile(atPath: executable.path),
          (try? executable.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
        return failed("missingApplicationExecutable")
    }

    var designated: SecRequirement?
    let copied = SecCodeCopyDesignatedRequirement(code, [], &designated)
    guard copied == errSecSuccess, let requirement = designated else {
        return failed("copyDesignatedRequirement", copied)
    }
    var description: CFString?
    let described = SecRequirementCopyString(requirement, [], &description)
    guard described == errSecSuccess, let description else {
        return failed("describeDesignatedRequirement", described)
    }
    report.designatedRequirement = description as String
    return (report, SignedApp(code: code, requirement: requirement))
}

private struct ResultReport: Encodable {
    let schemaVersion = 1
    let result: String
    let reason: String
    let exitCode: Int32
    var installed: Inspection?
    var candidate: Inspection?
    var requirementCheckOSStatus: OSStatus?
    var usage: String?
    let permissionStateRead = false
    let permissionStateChanged = false
    let directoryAccess = "notEvaluated"
}

private func compare(_ arguments: [String]) -> ResultReport {
    guard arguments.count == 4,
          Set([arguments[0], arguments[2]]) == ["--installed", "--candidate"],
          !arguments[1].isEmpty, !arguments[3].isEmpty else {
        return ResultReport(result: "usage", reason: "expectedTwoAppPaths", exitCode: 64,
                            usage: "swift scripts/check-update-identity.swift --installed OLD.app --candidate NEW.app")
    }
    let installedFirst = arguments[0] == "--installed"
    let (previous, oldApp) = inspect(arguments[installedFirst ? 1 : 3])
    let (replacement, newApp) = inspect(arguments[installedFirst ? 3 : 1])
    guard let oldApp, let newApp else {
        return ResultReport(result: "invalid", reason: "bundleValidationFailed", exitCode: 1,
                            installed: previous, candidate: replacement)
    }
    guard previous.bundleIdentifier == replacement.bundleIdentifier else {
        return ResultReport(result: "mismatch", reason: "bundleIdentifierChanged", exitCode: 2,
                            installed: previous, candidate: replacement)
    }
    // Evaluate the installed bundle's actual requirement against the candidate.
    // Signed versions may satisfy the same requirement with different CDHashes.
    let status = SecStaticCodeCheckValidity(newApp.code, validationFlags, oldApp.requirement)
    switch status {
    case errSecSuccess:
        return ResultReport(result: "match", reason: "installedRequirementSatisfied", exitCode: 0,
                            installed: previous, candidate: replacement, requirementCheckOSStatus: status)
    case errSecCSReqFailed:
        return ResultReport(result: "mismatch", reason: "installedRequirementNotSatisfied", exitCode: 2,
                            installed: previous, candidate: replacement, requirementCheckOSStatus: status)
    default:
        return ResultReport(result: "invalid", reason: "requirementEvaluationFailed", exitCode: 1,
                            installed: previous, candidate: replacement, requirementCheckOSStatus: status)
    }
}

private let result = compare(Array(CommandLine.arguments.dropFirst()))
private let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
do {
    let data = try encoder.encode(result)
    print(String(decoding: data, as: UTF8.self))
    exit(result.exitCode)
} catch {
    fputs("{\"result\":\"invalid\",\"reason\":\"reportEncodingFailed\",\"exitCode\":1}\n", stderr)
    exit(1)
}
