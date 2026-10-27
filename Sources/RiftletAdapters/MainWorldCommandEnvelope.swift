import Foundation
import CoreFoundation

/// One command, one random receipt. Reading a lost receipt must never execute the
/// command again. Only code-owned errors cross the bridge; no page exception text.
struct MainWorldCommandEnvelope {
    let nonce: String
    let source: String
    let reader: String

    init(function: String, commandJSON: String, contextJSON: String) {
        nonce = UUID().uuidString.lowercased()
        let attribute = "data-riftlet-reply-" + nonce
        source = """
        (()=>{let r;try{r={nonce:'\(nonce)',ok:true,result:(\(function))(\(commandJSON),\(contextJSON))};}
        catch(_){r={nonce:'\(nonce)',ok:false};}
        document.documentElement.setAttribute('\(attribute)',JSON.stringify(r));
        setTimeout(()=>document.documentElement.removeAttribute('\(attribute)'),10000);})()
        """
        reader = "(()=>{const n=document.documentElement,s=n.getAttribute('\(attribute)')||'';if(s)n.removeAttribute('\(attribute)');return s})()"
    }

    func decode(_ raw: String) throws -> String {
        guard raw.utf8.count <= ObservationDecoder.maximumPayloadBytes,
              let object = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any],
              object["nonce"] as? String == nonce,
              let ok = object["ok"] as? NSNumber, CFGetTypeID(ok) == CFBooleanGetTypeID(), ok.boolValue,
              Set(object.keys) == Set(["nonce", "ok", "result"]),
              let result = object["result"], JSONSerialization.isValidJSONObject(result),
              let bytes = try? JSONSerialization.data(withJSONObject: result) else {
            throw WebAdapterError.invalidReply
        }
        return String(decoding: bytes, as: UTF8.self)
    }
}
