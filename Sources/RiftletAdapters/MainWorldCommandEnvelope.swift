import Foundation
import CoreFoundation

/// Closed code-owned labels only; arbitrary page exception messages stay local.
public enum WebPageRejection: String, Codable, CaseIterable, Sendable {
    // Legacy receipt decoding only; the current program reports the individual
    // gate below so route, visibility and focus are never conflated again.
    case unsupportedSurface = "UNSUPPORTED_TEST_SURFACE"
    case pageRouteUnsupported = "PAGE_ROUTE_UNSUPPORTED"
    case pageNotTopLevel = "PAGE_NOT_TOP_LEVEL"
    case pageNotVisible = "PAGE_NOT_VISIBLE"
    case pageUnfocused = "PAGE_UNFOCUSED"
    case editorUnavailable = "EDITOR_UNAVAILABLE"
    case attachmentInputUnavailable = "ATTACHMENT_INPUT_UNAVAILABLE"
    case ambiguousComposer = "AMBIGUOUS_COMPOSER"
    case composerUnavailable = "COMPOSER_UNAVAILABLE"
    case unprovenMode = "UNPROVEN_CHAT_MODE"
    case unprovenThread = "UNPROVEN_THREAD_IDENTITY"
    case unobservedThread = "UNOBSERVED_THREAD_COMPOSER"
    case unobservedInput = "UNOBSERVED_INPUT_STRUCTURE"
    case nativeContext = "NATIVE_CONTEXT_REQUIRED"
    case generationLimit = "LEASE_GENERATION_LIMIT"
    case invalidTarget = "TARGET_INVALID"
    case clickRouteUnobserved = "CLICK_ROUTE_UNOBSERVED"
    case clickPinRefused = "CLICK_PIN_REFUSED"
    case clickPinLimit = "CLICK_PIN_LIMIT"
    case clickPinSpent = "CLICK_PIN_SPENT"
    case beginRefused = "BEGIN_REFUSED"
    case chunkRefused = "CHUNK_REFUSED"
    case commitRefused = "COMMIT_REFUSED"
    case invocationMismatch = "INVOCATION_MISMATCH"
    case originalOperationRequired = "ORIGINAL_OPERATION_REQUIRED"
    case bridgeUnavailable = "BRIDGE_UNAVAILABLE"
    case rootMonitorLost = "ROOT_MONITOR_LOST"
    case rootMonitorLimit = "ROOT_MONITOR_LIMIT"
    case rootMonitorUnavailable = "ROOT_MONITOR_UNAVAILABLE"
    case unobservedRootDescriptor = "UNOBSERVED_ROOT_DESCRIPTOR"
    case unprovenMonitoredBinding = "UNPROVEN_MONITORED_BINDING"
    case inputResourceUnavailable = "INPUT_RESOURCE_UNAVAILABLE"
    case inputResourceNativeFilesRetained = "INPUT_RESOURCE_NATIVE_FILES_RETAINED"
    case inputResourceNativeValueNonempty = "INPUT_RESOURCE_NATIVE_VALUE_NONEMPTY"
    case inputResourceNativeAccessUnverified = "INPUT_RESOURCE_NATIVE_ACCESS_UNVERIFIED"
    case inputResourceExecutionBusy = "INPUT_RESOURCE_EXECUTION_BUSY"
    case inputResourceExecutionUncertain = "INPUT_RESOURCE_EXECUTION_UNCERTAIN"
    case inputResourceGenerationBusy = "INPUT_RESOURCE_GENERATION_BUSY"
    case inputResourceRegistryUnverified = "INPUT_RESOURCE_REGISTRY_UNVERIFIED"
    case inputResourceTargetChanged = "INPUT_RESOURCE_TARGET_CHANGED"
    case inputResourceBaselineChanged = "INPUT_RESOURCE_BASELINE_CHANGED"
    case inputResourceReservationBusy = "INPUT_RESOURCE_RESERVATION_BUSY"
    case inputResourcePriorAttachmentUnproven = "INPUT_RESOURCE_PRIOR_ATTACHMENT_UNPROVEN"
    case inputResourceQualificationPending = "INPUT_RESOURCE_QUALIFICATION_PENDING"
    case inputResourceQualificationFailed = "INPUT_RESOURCE_QUALIFICATION_FAILED"

    var isInputResourceRefusal: Bool {
        switch self {
        case .inputResourceUnavailable, .inputResourceNativeFilesRetained, .inputResourceNativeValueNonempty,
             .inputResourceNativeAccessUnverified, .inputResourceExecutionBusy, .inputResourceExecutionUncertain,
             .inputResourceGenerationBusy, .inputResourceRegistryUnverified, .inputResourceTargetChanged,
             .inputResourceBaselineChanged, .inputResourceReservationBusy, .inputResourcePriorAttachmentUnproven,
             .inputResourceQualificationPending, .inputResourceQualificationFailed: return true
        default: return false
        }
    }
}

/// One command, one random receipt. Reading a lost receipt must never execute the
/// command again. Only code-owned errors cross the bridge; no page exception text.
struct MainWorldCommandEnvelope {
    let nonce: String
    let commandJSON: String
    let source: String
    let reader: String

    init(function: String, commandJSON: String, contextJSON: String) {
        self.commandJSON = commandJSON
        nonce = UUID().uuidString.lowercased()
        let attribute = "data-riftlet-reply-" + nonce
        let codes = String(decoding: try! JSONEncoder().encode(WebPageRejection.allCases.map(\.rawValue)), as: UTF8.self)
        source = """
        (()=>{const root=document.documentElement;let replied=false;
        const publish=r=>{if(replied)return;replied=true;if(document.documentElement!==root)return;
          root.setAttribute('\(attribute)',JSON.stringify(r));
          setTimeout(()=>root.removeAttribute('\(attribute)'),10000);};
        const success=result=>publish({nonce:'\(nonce)',ok:true,result});
        const failure=e=>{const r={nonce:'\(nonce)',ok:false},code=e?.message;
          if(\(codes).includes(code))r.rejection=code;publish(r);};
        try{const result=(\(function))(\(commandJSON),\(contextJSON));
          if(result&&typeof result.then==='function')Promise.resolve(result).then(success,failure);
          else success(result);
        }catch(e){failure(e);}})()
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
/// Receipt polling uses short individual reads. Synchronous click snapshot
/// queries use the remaining one-shot budget and never reissue the request.
struct MainWorldReceiptReadBudget: Sendable {
    let deadlineUptime: TimeInterval
    private let maximumEventDuration: TimeInterval

    init(deadlineUptime: TimeInterval, clickSnapshot: Bool = false) {
        self.deadlineUptime = deadlineUptime
        maximumEventDuration = clickSnapshot ? 1 : 0.25
    }

    func timeout(at uptime: TimeInterval) throws -> TimeInterval {
        guard uptime.isFinite, uptime >= 0, deadlineUptime.isFinite,
              deadlineUptime > uptime else { throw WebAdapterError.invalidReply }
        let remaining = deadlineUptime - uptime
        // Foundation does not document sub-tick timeout conversion. Refuse the
        // last <50 ms instead of passing zero/sub-tick or special timeout values.
        guard remaining >= 0.05 else { throw WebAdapterError.invalidReply }
        // One quarter of the original one-second budget leaves room to recover
        // a lost read reply; this is a bound, not a measured Chrome latency claim.
        return min(maximumEventDuration, remaining)
    }
}

/// Submit is deliberately absent from this interface. Only empty receipts and
/// errAETimeout (-1712) can cause another read of the same nonce and native IDs.
/// Decoding failures and all other errors leave immediately. This does not grant
/// an ACK or change the App's original-event/publication ordering contract.
enum MainWorldReceiptReader {
    static func read(_ envelope: MainWorldCommandEnvelope,
                     timeout: TimeInterval = 1,
                     clock: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
                     sleep: (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) },
                     checkContinuation: () throws -> Void = {},
                     fetch: (MainWorldReceiptReadBudget) throws -> String)
        throws -> (text: String, receivedUptime: TimeInterval) {
        let started = clock(), deadline = started + timeout
        guard timeout.isFinite, timeout > 0, timeout <= 10,
              started.isFinite, started >= 0, deadline.isFinite, deadline > started else {
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
        // The 20 ms polling interval permits at most 50 reads per second.
        // A commit may await the application's attachment-menu render, while
        // other reads retain the one-second budget. This separate cap bounds a
        // stalled/injected clock; no timeout ever executes the command again.
        let maximumReads = Int(ceil(timeout / 0.02))
        for attempt in 0..<maximumReads {
            try checkContinuation()
            _ = try budget.timeout(at: checkedUptime())
            let raw: String
            do { raw = try fetch(budget) }
            catch {
                guard (error as? WebAdapterError) == .nativeEventFailed(-1712) else { throw error }
                raw = ""
            }
            try checkContinuation()
            let received = try checkedUptime()
            if !raw.isEmpty {
                let text = try envelope.decode(raw)
                _ = try checkedUptime() // Even a valid reply arriving/decoding too late is refused.
                try checkContinuation()
                return (text, received)
            }
            guard attempt < maximumReads - 1 else { break }
            let beforeSleep = try checkedUptime()
            sleep(min(0.02, deadline - beforeSleep))
        }
        throw WebAdapterError.invalidReply
    }
}
