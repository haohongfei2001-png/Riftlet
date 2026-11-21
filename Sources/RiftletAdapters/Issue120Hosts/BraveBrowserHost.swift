import AppKit
import Carbon
import RiftletCore

@MainActor final class BraveBrowserHost: BrowserHost {
    static let applicationID = "com.brave.Browser"
    let bundle = BraveBrowserHost.applicationID
    let capabilities = HostCapabilities(world: .unknown, reply: .unknown, locator: .stableNativeID,
                                        epoch: .unknown, fileSetterAndDataTransferVerified: false, maximumPinBytes: 0)

    private struct FrozenSelection {
        let click: NativeClick
        let receiver: CandidateReceiver
        let absoluteTab: NSAppleEventDescriptor
    }
    private var selected: FrozenSelection?

    func permissionState() -> OriginalReceiverAccess {
        CandidateReceiver.forSettings(bundle)?.automationState() ?? .unavailable
    }

    func freezeClick() throws -> NativeClick {
        selected = nil
        let start = ProcessInfo.processInfo.systemUptime
        let deadline = ChromeClickDeadline(start: start)
        guard let receiver = CandidateReceiver.foreground(bundle) else { throw BindingError.targetChanged }
        let front = try Self.object("cwin", form: "indx", key: .init(int32: 1))
        let active = try Self.property("acTa", of: front)
        let properties = try Self.property("pALL", of: active)
        var stage = "brave_click"
        let replies = try ChromeClickSnapshot.read(pid: receiver.birth.pid, active: active, properties: properties,
                                                    deadline: deadline, stage: &stage)
        // The descriptor's container chain must be ID-based in its entirety.
        // When the two reads straddle a switch, refuse instead of looking up a later tab.
        let route = try Self.frozenRoute(replies) { tab in
            guard CandidateReceiver.foreground(bundle) == receiver else { throw BindingError.targetChanged }
            return try Self.readOriginalURL(tab, pid: receiver.birth.pid, deadline: deadline)
        }
        guard CandidateReceiver.foreground(bundle) == receiver else { throw BindingError.targetChanged }
        try deadline.checkReturn()
        let click = NativeClick(bundle: bundle, pid: receiver.birth.pid, processBirth: receiver.session,
                                session: receiver.session, window: route.window, tab: route.tab, url: route.url,
                                generation: UUID(), uptime: start)
        selected = FrozenSelection(click: click, receiver: receiver, absoluteTab: replies.activeTab)
        return click
    }

    static func frozenRoute(_ replies: ChromeClickSnapshot.Replies,
                            originalURL: (NSAppleEventDescriptor) throws -> String) throws -> (window: String, tab: String, url: URL) {
        guard let ids = ChromeActiveTabDescriptor.identity(in: replies.activeTab) else { throw BindingError.targetChanged }
        let address: String
        if let properties = replies.properties {
            guard let matched = try ChromeActiveTabDescriptor.matchedURL(properties: properties, tab: ids.tab)
            else { throw BindingError.targetChanged }
            address = matched
        } else {
            // pALL includes the page title and can exceed the reply buffer or its
            // optional wait. Read just the URL from the original absolute object.
            address = try originalURL(replies.activeTab)
        }
        guard let url = URL(string: address), url.scheme?.lowercased() == "https", url.host != nil
        else { throw BindingError.targetChanged }
        return (ids.window, ids.tab, url)
    }

    nonisolated static func readOriginalURL(_ tab: NSAppleEventDescriptor, pid: pid_t,
                                            deadline: ChromeClickDeadline) throws -> String {
        guard ChromeActiveTabDescriptor.identity(in: tab) != nil else { throw BindingError.targetChanged }
        let event = NSAppleEventDescriptor(eventClass: kAECoreSuite, eventID: kAEGetData,
                                           targetDescriptor: .init(processIdentifier: pid), returnID: -1, transactionID: 0)
        event.setParam(try property("URL ", of: tab), forKeyword: keyDirectObject)
        let reply = try event.sendEvent(options: ChromeClickSnapshot.waitOptions, timeout: deadline.timeout())
        try deadline.checkReturn()
        if let error = reply.paramDescriptor(forKeyword: keyErrorNumber)?.int32Value, error != noErr {
            throw WebAdapterError.nativeEventFailed(error)
        }
        guard let url = reply.paramDescriptor(forKeyword: keyDirectObject)?.stringValue else {
            throw BindingError.targetChanged
        }
        return url
    }

    enum ScriptRead: Equatable { case available, browserSettingDisabled, automationRequired }

    /// Explicit candidate setup diagnostic. A positive read does not prove the
    /// page world, unchanged draft epoch, or availability of the upload channel.
    func readScriptSetting(for click: NativeClick) throws -> ScriptRead {
        guard let selected, selected.click == click, CandidateReceiver.foreground(bundle) == selected.receiver
        else { throw BindingError.targetChanged }
        let event = NSAppleEventDescriptor(eventClass: Self.code("CrSu"), eventID: Self.code("ExJa"),
                                           targetDescriptor: .init(processIdentifier: click.pid), returnID: -1, transactionID: 0)
        event.setParam(selected.absoluteTab, forKeyword: keyDirectObject)
        // This fixed expression has no DOM reads, writes or callbacks.
        event.setParam(.init(string: "'RIFTLET_SCRIPT_AVAILABLE'"), forKeyword: Self.code("JvSc"))
        let result: ScriptRead
        do {
            let reply = try event.sendEvent(options: ChromeClickSnapshot.waitOptions, timeout: 0.25)
            let status = reply.paramDescriptor(forKeyword: keyErrorNumber)?.int32Value ?? 0
            result = try Self.scriptRead(status: status, reply: reply.paramDescriptor(forKeyword: keyDirectObject)?.stringValue)
        } catch let error as NSError where error.domain == NSOSStatusErrorDomain {
            result = try Self.scriptRead(status: Int32(exactly: error.code) ?? -1, reply: nil)
        }
        guard CandidateReceiver.foreground(bundle) == selected.receiver else { throw BindingError.targetChanged }
        return result
    }

    static func scriptRead(status: OSStatus, reply: String?) throws -> ScriptRead {
        switch status {
        case noErr where reply == "RIFTLET_SCRIPT_AVAILABLE": return .available
        case 12: return .browserSettingDisabled
        case OSStatus(errAEEventNotPermitted), OSStatus(errAEEventWouldRequireUserConsent): return .automationRequired
        default: throw BindingError.unsupported
        }
    }

    func enqueuePin(click: NativeClick, route: ProviderRoute, maximumBytes: Int) throws -> Task<PinReceipt, Error> {
        // The isolated probe did not prove Brave's execution world or original async reply.
        throw BindingError.unsupported
    }

    private nonisolated static func code(_ string: String) -> OSType { string.utf8.reduce(0) { ($0 << 8) | OSType($1) } }

    private nonisolated static func object(_ type: String, form: String, key: NSAppleEventDescriptor,
                               container: NSAppleEventDescriptor = .null()) throws -> NSAppleEventDescriptor {
        let record = NSAppleEventDescriptor.record()
        record.setDescriptor(.init(typeCode: code(type)), forKeyword: code("want"))
        record.setDescriptor(.init(enumCode: code(form)), forKeyword: code("form"))
        record.setDescriptor(key, forKeyword: code("seld"))
        record.setDescriptor(container, forKeyword: code("from"))
        guard let object = record.coerce(toDescriptorType: code("obj ")) else { throw BindingError.unsupported }
        return object
    }

    private nonisolated static func property(_ property: String, of owner: NSAppleEventDescriptor) throws -> NSAppleEventDescriptor {
        try object("prop", form: "prop", key: .init(typeCode: code(property)), container: owner)
    }
}
