import AppKit
import Carbon

/// Apple Event Manager measures its synchronous wait in whole ticks (1/60 s).
/// All reads of one click use the original absolute deadline. Zero means an
/// unbounded wait to AESendMessage, so a remaining fraction of one tick is refused.
struct EdgeClickAppleEvent {
    let deadlineUptime: TimeInterval

    func ticks(at uptime: TimeInterval) throws -> Int {
        guard deadlineUptime.isFinite, uptime.isFinite, uptime >= 0 else {
            throw WebAdapterError.nativeEventFailed(OSStatus(errAETimeout))
        }
        let remaining = deadlineUptime - uptime
        let ticks = (min(0.15, remaining) * 60).rounded(.down)
        guard ticks >= 1 else { throw WebAdapterError.nativeEventFailed(OSStatus(errAETimeout)) }
        return Int(ticks)
    }

    func send(_ event: NSAppleEventDescriptor,
              uptime: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
              sendMessage: (UnsafePointer<AppleEvent>?, UnsafeMutablePointer<AppleEvent>?, AESendMode, Int) -> OSStatus = AESendMessage)
        throws -> NSAppleEventDescriptor {
        let timeout = try ticks(at: uptime())
        var reply = AppleEvent()
        let status = sendMessage(event.aeDesc, &reply, AESendMode(kAEWaitReply | kAENeverInteract), timeout)
        guard status == noErr else {
            AEDisposeDesc(&reply)
            throw WebAdapterError.nativeEventFailed(status)
        }
        // Foundation assumes ownership of the received descriptor even when
        // the reply is subsequently discarded for arriving past the deadline.
        let descriptor = NSAppleEventDescriptor(aeDescNoCopy: &reply)
        guard uptime() < deadlineUptime else { throw WebAdapterError.nativeEventFailed(OSStatus(errAETimeout)) }
        return descriptor
    }
}
