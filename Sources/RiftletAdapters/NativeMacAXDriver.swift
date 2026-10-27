import AppKit
import ApplicationServices
import Foundation

public enum NativeMacAXError: Error, Equatable {
    case invalidConfiguration, permissionUnavailable, invalidElement, invalidValue, boundsExceeded
    case unsupportedClient, targetChanged, invalidPrivateFile, clipboardChanged, inputAlreadyAttempted
    case accessibility(Int32)
}

/// An exact AX object, not a query, title or guessed child index. Object references
/// stay local; persisted TargetLease tokens are supplied by the evidence provider.
public struct MacAXElement: @unchecked Sendable, Equatable {
    public let rawValue: AXUIElement
    public init(_ rawValue: AXUIElement) { self.rawValue = rawValue }
    public static func == (lhs: Self, rhs: Self) -> Bool { CFEqual(lhs.rawValue, rhs.rawValue) }
}

public struct MacAXApplicationIdentity: Equatable, Sendable {
    public let processID: Int32
    public let launchedAt: Date
    public let bundleID: String
    public let version: String
    public let build: String
    public init(processID: Int32, launchedAt: Date, bundleID: String, version: String, build: String) {
        self.processID = processID; self.launchedAt = launchedAt
        self.bundleID = bundleID; self.version = version; self.build = build
    }
}

/// Standard AX primitives only. No method searches for a ChatGPT composer or a
/// localized Paste title, changes focus, types keys, opens menus or sends a chat.
@MainActor public protocol MacAXDriver: Sendable {
    func isTrusted() -> Bool
    func frontmostApplication() throws -> MacAXApplicationIdentity?
    func applicationIdentity(processID: Int32) throws -> MacAXApplicationIdentity?
    func applicationElement(processID: Int32) throws -> MacAXElement
    func processID(of element: MacAXElement) throws -> Int32
    func elementAttribute(_ attribute: String, of element: MacAXElement) throws -> MacAXElement?
    func stringAttribute(_ attribute: String, of element: MacAXElement) throws -> String?
    func boolAttribute(_ attribute: String, of element: MacAXElement) throws -> Bool?
    func elementsAttribute(_ attribute: String, of element: MacAXElement, maximumCount: Int) throws -> [MacAXElement]
    func actionNames(of element: MacAXElement) throws -> [String]
    func press(_ element: MacAXElement) throws
}

/// Actual ApplicationServices backend. Every exact object receives its own
/// bounded messaging timeout; an application's timeout does not cover its peers
/// or children. Timeouts are per call, not an atomic cross-process transaction.
@MainActor public final class NativeMacAXDriver: MacAXDriver {
    private let messagingTimeout: Float

    public init(messagingTimeout: Float = 0.25) throws {
        guard messagingTimeout.isFinite, (0.05...2).contains(messagingTimeout) else {
            throw NativeMacAXError.invalidConfiguration
        }
        self.messagingTimeout = messagingTimeout
    }

    /// Read-only trust query. Deliberately no WithOptions / prompt flag.
    public func isTrusted() -> Bool { AXIsProcessTrusted() }

    public func frontmostApplication() throws -> MacAXApplicationIdentity? {
        guard let application = NSWorkspace.shared.frontmostApplication else { return nil }
        return identity(application)
    }

    public func applicationIdentity(processID: Int32) throws -> MacAXApplicationIdentity? {
        guard processID > 0, let application = NSRunningApplication(processIdentifier: processID) else { return nil }
        return identity(application)
    }

    public func applicationElement(processID: Int32) throws -> MacAXElement {
        guard processID > 0 else { throw NativeMacAXError.invalidElement }
        let element = MacAXElement(AXUIElementCreateApplication(processID))
        try configure(element)
        return element
    }

    public func processID(of element: MacAXElement) throws -> Int32 {
        try configure(element)
        var pid: pid_t = 0
        try check(AXUIElementGetPid(element.rawValue, &pid))
        guard pid > 0 else { throw NativeMacAXError.invalidElement }
        return pid
    }

    public func elementAttribute(_ attribute: String, of element: MacAXElement) throws -> MacAXElement? {
        guard let value = try value(attribute, of: element) else { return nil }
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else { throw NativeMacAXError.invalidValue }
        return MacAXElement(unsafeBitCast(value, to: AXUIElement.self))
    }

    public func stringAttribute(_ attribute: String, of element: MacAXElement) throws -> String? {
        guard let value = try value(attribute, of: element) else { return nil }
        guard CFGetTypeID(value) == CFStringGetTypeID(), let string = value as? String else {
            throw NativeMacAXError.invalidValue
        }
        guard string.utf8.count <= 4_096 else { throw NativeMacAXError.boundsExceeded }
        return string
    }

    public func boolAttribute(_ attribute: String, of element: MacAXElement) throws -> Bool? {
        guard let value = try value(attribute, of: element) else { return nil }
        guard CFGetTypeID(value) == CFBooleanGetTypeID(), let boolean = value as? Bool else {
            throw NativeMacAXError.invalidValue
        }
        return boolean
    }

    public func elementsAttribute(_ attribute: String, of element: MacAXElement,
                                  maximumCount: Int = 64) throws -> [MacAXElement] {
        guard (1...256).contains(maximumCount) else { throw NativeMacAXError.invalidConfiguration }
        try validate(attribute); try configure(element)
        var count: CFIndex = 0
        let result = AXUIElementGetAttributeValueCount(element.rawValue, attribute as CFString, &count)
        if result == .noValue || result == .attributeUnsupported { return [] }
        try check(result)
        guard count >= 0, count <= maximumCount else { throw NativeMacAXError.boundsExceeded }
        guard count > 0 else { return [] }
        var values: CFArray?
        try check(AXUIElementCopyAttributeValues(element.rawValue, attribute as CFString, 0, count, &values))
        guard let values, CFArrayGetCount(values) == count,
              let items = values as? [AXUIElement] else { throw NativeMacAXError.invalidValue }
        return try items.map {
            guard CFGetTypeID($0) == AXUIElementGetTypeID() else { throw NativeMacAXError.invalidValue }
            return MacAXElement($0)
        }
    }

    public func actionNames(of element: MacAXElement) throws -> [String] {
        try configure(element)
        var values: CFArray?
        try check(AXUIElementCopyActionNames(element.rawValue, &values))
        guard let values, let actions = values as? [String] else { throw NativeMacAXError.invalidValue }
        guard actions.count <= 64, actions.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 512 }) else {
            throw NativeMacAXError.boundsExceeded
        }
        return actions
    }

    public func press(_ element: MacAXElement) throws {
        try configure(element)
        // cannotComplete is not evidence that the action did not happen. The
        // executor journals first, never retries, and reports UNKNOWN on errors.
        try check(AXUIElementPerformAction(element.rawValue, kAXPressAction as CFString))
    }

    private func value(_ attribute: String, of element: MacAXElement) throws -> CFTypeRef? {
        try validate(attribute); try configure(element)
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element.rawValue, attribute as CFString, &value)
        if result == .noValue || result == .attributeUnsupported { return nil }
        try check(result)
        guard let value else { throw NativeMacAXError.invalidValue }
        return value
    }

    private func identity(_ application: NSRunningApplication) -> MacAXApplicationIdentity? {
        guard !application.isTerminated, let launch = application.launchDate,
              let bundleID = application.bundleIdentifier, let url = application.bundleURL,
              let bundle = Bundle(url: url),
              let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
              [bundleID, version, build].allSatisfy({ !$0.isEmpty && $0.utf8.count <= 512 }) else { return nil }
        return MacAXApplicationIdentity(processID: application.processIdentifier, launchedAt: launch,
                                         bundleID: bundleID, version: version, build: build)
    }

    private func configure(_ element: MacAXElement) throws {
        try check(AXUIElementSetMessagingTimeout(element.rawValue, messagingTimeout))
    }
    private func validate(_ attribute: String) throws {
        guard !attribute.isEmpty, attribute.utf8.count <= 512 else { throw NativeMacAXError.invalidConfiguration }
    }
    private func check(_ result: AXError) throws {
        guard result == .success else { throw NativeMacAXError.accessibility(result.rawValue) }
    }
}
