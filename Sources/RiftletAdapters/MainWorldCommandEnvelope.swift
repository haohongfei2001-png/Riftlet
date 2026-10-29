import Foundation
import CoreFoundation

/// Closed code-owned labels only; arbitrary page exception messages stay local.
public enum WebPageRejection: String, CaseIterable, Sendable {
    case unsupportedSurface = "UNSUPPORTED_TEST_SURFACE"
    case ambiguousComposer = "AMBIGUOUS_COMPOSER"
    case composerUnavailable = "COMPOSER_UNAVAILABLE"
    case unprovenMode = "UNPROVEN_CHAT_MODE"
    case unprovenThread = "UNPROVEN_THREAD_IDENTITY"
    case unobservedThread = "UNOBSERVED_THREAD_COMPOSER"
    case unobservedInput = "UNOBSERVED_INPUT_STRUCTURE"
    case nativeContext = "NATIVE_CONTEXT_REQUIRED"
    case generationLimit = "LEASE_GENERATION_LIMIT"
    case invalidTarget = "TARGET_INVALID"
    case rootMonitorLost = "ROOT_MONITOR_LOST"
    case rootMonitorLimit = "ROOT_MONITOR_LIMIT"
    case rootMonitorUnavailable = "ROOT_MONITOR_UNAVAILABLE"
    case unobservedRootDescriptor = "UNOBSERVED_ROOT_DESCRIPTOR"
    case unprovenMonitoredBinding = "UNPROVEN_MONITORED_BINDING"
}

/// One command, one random receipt. Reading a lost receipt must never execute the
/// command again. Only code-owned errors cross the bridge; no page exception text.
struct MainWorldCommandEnvelope {
    let nonce: String
    let source: String
    let reader: String

    init(function: String, commandJSON: String, contextJSON: String) {
        nonce = UUID().uuidString.lowercased()
        let attribute = "data-riftlet-reply-" + nonce
        let codes = String(decoding: try! JSONEncoder().encode(WebPageRejection.allCases.map(\.rawValue)), as: UTF8.self)
        source = """
        (()=>{let r;try{r={nonce:'\(nonce)',ok:true,result:(\(function))(\(commandJSON),\(contextJSON))};}
        catch(e){r={nonce:'\(nonce)',ok:false};const code=e?.message;if(\(codes).includes(code))r.rejection=code;}
        document.documentElement.setAttribute('\(attribute)',JSON.stringify(r));
        setTimeout(()=>document.documentElement.removeAttribute('\(attribute)'),10000);})()
        """
        // Reading must not consume the receipt before its AppleEvent reply has
        // reached the host. A timed-out read may already have executed in Chrome.
        // Only the original ten-second cleanup removes this nonce's receipt.
        reader = "(()=>document.documentElement.getAttribute('\(attribute)')||'')()"
    }

    func decode(_ raw: String) throws -> String {
        guard raw.utf8.count <= ObservationDecoder.maximumPayloadBytes,
              let object = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any],
              object["nonce"] as? String == nonce,
              let ok = object["ok"] as? NSNumber, CFGetTypeID(ok) == CFBooleanGetTypeID() else {
            throw WebAdapterError.invalidReply
        }
        if !ok.boolValue, Set(object.keys) == Set(["nonce", "ok", "rejection"]),
           let value = object["rejection"] as? String, let code = WebPageRejection(rawValue: value) {
            throw WebAdapterError.pageRejected(code)
        }
        guard ok.boolValue, Set(object.keys) == Set(["nonce", "ok", "result"]),
              let result = object["result"], JSONSerialization.isValidJSONObject(result),
              let bytes = try? JSONSerialization.data(withJSONObject: result) else {
            throw WebAdapterError.invalidReply
        }
        return String(decoding: bytes, as: UTF8.self)
    }
}

/// The absolute budget reaches the actual send, after descriptor construction.
/// It applies only to reading an already submitted command's nonce receipt.
struct MainWorldReceiptReadBudget: Sendable {
    let deadlineUptime: TimeInterval

    func timeout(at uptime: TimeInterval) throws -> TimeInterval {
        guard uptime.isFinite, uptime >= 0, deadlineUptime.isFinite,
              deadlineUptime > uptime else { throw WebAdapterError.invalidReply }
        let remaining = deadlineUptime - uptime
        // Foundation does not document sub-tick timeout conversion. Refuse the
        // last <50 ms instead of passing zero/sub-tick or special timeout values.
        guard remaining >= 0.05 else { throw WebAdapterError.invalidReply }
        // One quarter of the original one-second budget leaves room to recover
        // a lost read reply; this is a bound, not a measured Chrome latency claim.
        return min(0.25, remaining)
    }
}

/// Submit is deliberately absent from this interface. Only empty receipts and
/// errAETimeout (-1712) can cause another read of the same nonce and native IDs.
/// Decoding failures and all other errors leave immediately. This does not grant
/// an ACK or change the App's original-event/publication ordering contract.
enum MainWorldReceiptReader {
    static func read(_ envelope: MainWorldCommandEnvelope,
                     clock: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
                     sleep: (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) },
                     fetch: (MainWorldReceiptReadBudget) throws -> String)
        throws -> (text: String, receivedUptime: TimeInterval) {
        let started = clock(), deadline = started + 1
        guard started.isFinite, started >= 0, deadline.isFinite, deadline > started else {
            throw WebAdapterError.invalidReply
        }
        let budget = MainWorldReceiptReadBudget(deadlineUptime: deadline)
        var previous = started
        func checkedUptime() throws -> TimeInterval {
            let now = clock()
            guard now.isFinite, now >= previous, now < deadline else { throw WebAdapterError.invalidReply }
            previous = now
            return now
        }
        // The original 20 ms polling interval permits at most 50 ordinary reads
        // per second. This separate cap also bounds a stalled/injected clock.
        for attempt in 0..<50 {
            _ = try budget.timeout(at: checkedUptime())
            let raw: String
            do { raw = try fetch(budget) }
            catch {
                guard (error as? WebAdapterError) == .nativeEventFailed(-1712) else { throw error }
                raw = ""
            }
            let received = try checkedUptime()
            if !raw.isEmpty {
                let text = try envelope.decode(raw)
                _ = try checkedUptime() // Even a valid reply arriving/decoding too late is refused.
                return (text, received)
            }
            guard attempt < 49 else { break }
            let beforeSleep = try checkedUptime()
            sleep(min(0.02, deadline - beforeSleep))
        }
        throw WebAdapterError.invalidReply
    }
}
