import AppKit
import Carbon

// Internal primitive shared only with the controlled fixture driver. The registered
// Edge surface adapter constructs scripts exclusively from the bundled inspector.
enum EdgeJavaScriptEvent {
    static func send(_ js: String, to lease: EdgeWindowTab, using host: EdgeApplicationHost) throws -> String {
        let code = EdgeReadEvents.code
        let receiver = NSAppleEventDescriptor(processIdentifier: lease.process.pid)
        let status = AEDeterminePermissionToAutomateTarget(receiver.aeDesc, code("CrSu"), code("ExJa"), false)
        guard status == noErr else { throw EdgeHostError.automation(status) }
        try host.revalidate(lease)
        let event = NSAppleEventDescriptor(eventClass: code("CrSu"), eventID: code("ExJa"),
                                           targetDescriptor: receiver, returnID: -1, transactionID: 0)
        event.setParam(try EdgeReadEvents.tab(window: lease.windowID, id: lease.tabID), forKeyword: code("----"))
        event.setParam(.init(string: js), forKeyword: code("JvSc"))
        let reply = try event.sendEvent(options: [.waitForReply, .neverInteract], timeout: 1)
        if let failure = reply.paramDescriptor(forKeyword: code("errn")), failure.int32Value != 0 {
            throw EdgeHostError.automation(failure.int32Value)
        }
        guard let value = reply.paramDescriptor(forKeyword: code("----"))?.stringValue else {
            throw EdgeHostError.unsupportedDescriptor
        }
        return value
    }
}
