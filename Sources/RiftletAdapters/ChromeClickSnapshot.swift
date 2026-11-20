import AppKit
import Carbon

/// Both reads are sent in order to the same Chrome process at mouse-down. A fresh
/// port for each reply keeps late answers out of subsequent clicks. Receiving
/// directly also avoids pumping AppKit events inside the original mouse event.
enum ChromeClickSnapshot {
    // Ask macOS to enforce consent on the event itself. A separate wildcard
    // permission preflight costs an additional IPC round trip during mouse-down.
    // Only the explicit setup action may ask macOS to display a consent dialog.
    static let queuedMode = AESendMode(kAEQueueReply | kAENeverInteract | kAEDoNotPromptForUserConsent)
    static let waitOptions: NSAppleEventDescriptor.SendOptions = [
        .waitForReply, .neverInteract, .init(rawValue: UInt(kAEDoNotPromptForUserConsent))
    ]

    struct Replies {
        let activeTab: NSAppleEventDescriptor
        let properties: NSAppleEventDescriptor?
    }

    static func read(pid: pid_t, active: NSAppleEventDescriptor, properties: NSAppleEventDescriptor,
                     deadline: ChromeClickDeadline, stage: inout String) throws -> Replies {
        stage = "create_reply_ports"
        let identityPort = try replyPort()
        defer { mach_port_destroy(mach_task_self_, identityPort) }
        let propertiesPort = try replyPort()
        defer { mach_port_destroy(mach_task_self_, propertiesPort) }
        stage = "send_identity"
        try enqueue(active, pid: pid, id: 1, port: identityPort, deadline: deadline)
        stage = "send_properties"
        try enqueue(properties, pid: pid, id: 2, port: propertiesPort, deadline: deadline)
        stage = "receive_identity"
        guard let absolute = try receive(port: identityPort, id: 1, optional: false, deadline: deadline) else {
            throw WebAdapterError.invalidReply
        }
        stage = "receive_properties"
        let record = try receive(port: propertiesPort, id: 2, optional: true, deadline: deadline)
        return Replies(activeTab: absolute, properties: record)
    }

    /// A single queued Apple Event owns this receive right. Late answers for an
    /// abandoned click cannot be consumed by another click.
    final class WitnessReply: Sendable {
        fileprivate let port: mach_port_t
        fileprivate init(port: mach_port_t) { self.port = port }
        deinit { mach_port_destroy(mach_task_self_, port) }

        func boundWithinClick(before deadline: ChromeClickDeadline) throws -> Bool {
            let value = try receive(port: port, id: 3, optional: false, deadline: deadline)?.stringValue
            if value == "expired" { return false }
            guard value == "bound" else { throw WebAdapterError.pageRejected(.clickPinRefused) }
            return true
        }
    }

    static func enqueueWitness(_ event: NSAppleEventDescriptor, before deadline: ChromeClickDeadline) throws -> WitnessReply {
        let reply = WitnessReply(port: try replyPort())
        try enqueueEvent(event, port: reply.port, deadline: deadline)
        return reply
    }

    private static func replyPort() throws -> mach_port_t {
        var port: mach_port_t = 0
        guard mach_port_allocate(mach_task_self_, MACH_PORT_RIGHT_RECEIVE, &port) == KERN_SUCCESS else {
            throw WebAdapterError.nativeExecutionFailed
        }
        return port
    }

    private static func enqueue(_ object: NSAppleEventDescriptor, pid: pid_t, id: Int16, port: mach_port_t,
                                deadline: ChromeClickDeadline) throws {
        let request = NSAppleEventDescriptor(eventClass: kAECoreSuite, eventID: kAEGetData,
            targetDescriptor: .init(processIdentifier: pid), returnID: id, transactionID: 0)
        request.setParam(object, forKeyword: keyDirectObject)
        try enqueueEvent(request, port: port, deadline: deadline)
    }

    private static func enqueueEvent(_ request: NSAppleEventDescriptor, port: mach_port_t,
                                     deadline: ChromeClickDeadline) throws {
        var destination = port
        guard AEPutAttributePtr(UnsafeMutablePointer(mutating: request.aeDesc), keyReplyPortAttr,
            typeMachPort, &destination, MemoryLayout<mach_port_t>.size) == noErr else {
            throw WebAdapterError.nativeExecutionFailed
        }
        let ticks = Int(try deadline.timeout() * 60)
        let status = AESendMessage(request.aeDesc, nil, queuedMode, ticks)
        guard status == noErr else { throw WebAdapterError.nativeEventFailed(status) }
    }

    private static func value(_ reply: NSAppleEventDescriptor, optional: Bool) throws -> NSAppleEventDescriptor? {
        if let error = reply.paramDescriptor(forKeyword: keyErrorNumber)?.int32Value, error != 0 {
            // Older Chrome dictionaries may not supply the all-properties record.
            if optional && [errAECoercionFail, errAEEventNotHandled, errAENoSuchObject].contains(Int(error)) { return nil }
            throw WebAdapterError.nativeEventFailed(error)
        }
        guard let value = reply.paramDescriptor(forKeyword: keyDirectObject) else { throw WebAdapterError.invalidReply }
        return value
    }

    private static func receive(port: mach_port_t, id: Int16, optional: Bool,
                                deadline: ChromeClickDeadline) throws -> NSAppleEventDescriptor? {
        let size = 64 * 1024
        let storage = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 16)
        defer { storage.deallocate() }
        let header = storage.bindMemory(to: mach_msg_header_t.self, capacity: 1)
        let remaining = try deadline.receiveMilliseconds()
        // Once identity is fixed, give the optional record at most one event tick
        // when a pinned URL read could still fit. A slow optional read must not
        // occupy the entire original deadline.
        let timeout = optional && remaining >= 34 ? 17 : remaining
        let status = mach_msg(header, MACH_RCV_MSG | MACH_RCV_TIMEOUT, 0, mach_msg_size_t(size), port, timeout, 0)
        // pALL includes a title. A large optional reply never invalidates the
        // absolute identity from the other port; callers may read its pinned URL.
        if optional && (status == MACH_RCV_TOO_LARGE || status == MACH_RCV_TIMED_OUT) { return nil }
        if status == MACH_RCV_TIMED_OUT { throw WebAdapterError.nativeEventFailed(Int32(errAETimeout)) }
        guard status == MACH_MSG_SUCCESS else { throw WebAdapterError.nativeExecutionFailed }
        var event = AppleEvent(), unusedReply = AppleEvent()
        let decoded = AEDecodeMessage(header, &event, &unusedReply)
        defer { AEDisposeDesc(&unusedReply) }
        guard decoded == noErr else {
            AEDisposeDesc(&event)
            throw WebAdapterError.nativeEventFailed(decoded)
        }
        let reply = NSAppleEventDescriptor(aeDescNoCopy: &event)
        guard reply.eventClass == kCoreEventClass, reply.eventID == kAEAnswer, reply.returnID == id else {
            throw WebAdapterError.invalidReply
        }
        return try value(reply, optional: optional)
    }
}
