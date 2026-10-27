import Foundation
import CoreFoundation

/// Closed code-owned labels only; arbitrary page exception messages stay local.
public enum WebPageRejection: String, CaseIterable, Sendable {
    case unsupportedSurface = "UNSUPPORTED_TEST_SURFACE"
    case ambiguousComposer = "AMBIGUOUS_COMPOSER"
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
        reader = "(()=>{const n=document.documentElement,s=n.getAttribute('\(attribute)')||'';if(s)n.removeAttribute('\(attribute)');return s})()"
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
