import Foundation
import CryptoKit

/// A document-local MAIN closure, installed only while capturing a foreground
/// target. Later commands cross the shared DOM through execute-JavaScript; unlike
/// Chrome's javascript: URL setter this does not raise the addressed window.
/// The DOM channel is correlation, not protection against same-page malicious JS.
struct MainWorldCommandRelay: Sendable {
    let channel: String
    let marker: String
    let installer: String
    let probe: String
    let legacyObservationSession: String?

    init(function: String, contextJSON: String, legacyObservationSession: String? = nil, channel: String = UUID().uuidString.lowercased()) {
        self.channel = channel
        self.legacyObservationSession = legacyObservationSession
        let legacyJSON = String(decoding: try! JSONEncoder().encode(legacyObservationSession), as: UTF8.self)
        marker = SHA256.hash(data: Data((function + "\n" + contextJSON + "\n" + legacyJSON).utf8)).map { String(format: "%02x", $0) }.joined()
        let attribute = "data-riftlet-channel-" + channel
        let event = "riftlet-command-" + channel
        let codes = String(decoding: try! JSONEncoder().encode(WebPageRejection.allCases.map(\.rawValue)), as: UTF8.self)
        probe = "(()=>document.documentElement.getAttribute('\(attribute)')==='\(marker)'?'ready':'missing')()"
        installer = """
        (()=>{const root=document.documentElement,attribute='\(attribute)',marker='\(marker)';
        if(root.hasAttribute(attribute)){if(root.getAttribute(attribute)!==marker)throw Error('BRIDGE_UNAVAILABLE');return;}
        const program=(\(function)),native=Object.freeze(\(contextJSON)),legacySession=\(legacyJSON),seen=new Set();
        root.addEventListener('\(event)',event=>{
          if(document.documentElement!==root||event.target!==root||root.getAttribute(attribute)!==marker)return;
          const raw=root.getAttribute('data-riftlet-command');root.removeAttribute('data-riftlet-command');
          if(typeof raw!=='string'||raw.length>524288||new TextEncoder().encode(raw).length>524288)return;
          let q;try{q=JSON.parse(raw);}catch{return;}
          if(!q||Object.keys(q).sort().join(',')!=='command,nonce'
            ||typeof q.nonce!=='string'||!/^[a-f0-9]{8}-(?:[a-f0-9]{4}-){3}[a-f0-9]{12}$/.test(q.nonce)
            ||!q.command||!['captureTarget','pinTarget','prepareClick','resolveClick','validate','begin','chunk','commit','observe','discard'].includes(q.command.action)
            ||seen.has(q.nonce))return;
          seen.add(q.nonce); // Lifetime nonce tombstone, before executing/reentrancy.
          const receiver=q.command.action==='observe'&&legacySession&&q.command.target?.sessionID===legacySession
            ?Object.freeze({...native,sessionID:legacySession}):native;
          let r;try{r={nonce:q.nonce,ok:true,result:program(q.command,receiver)};}
          catch(e){r={nonce:q.nonce,ok:false};const code=e?.message;if(\(codes).includes(code))r.rejection=code;}
          const reply='data-riftlet-reply-'+q.nonce;root.setAttribute(reply,JSON.stringify(r));
          setTimeout(()=>root.removeAttribute(reply),10000);
        });
        root.setAttribute(attribute,marker);})()
        """
    }

    /// Read-only recovery of an already installed exact-version channel after
    /// native restart. Zero/ambiguous matches do not install or run a command.
    var discovery: String {
        """
        (()=>{const root=document.documentElement;if(root.attributes.length>1024)return 'ambiguous';
        const matches=[...root.attributes].filter(a=>a.name.startsWith('data-riftlet-channel-')&&a.value==='\(marker)')
          .map(a=>a.name.slice('data-riftlet-channel-'.length))
          .filter(id=>/^[a-f0-9]{8}-(?:[a-f0-9]{4}-){3}[a-f0-9]{12}$/.test(id));
        return matches.length===1?matches[0]:(matches.length===0?'':'ambiguous');})()
        """
    }

    func dispatch(_ envelope: MainWorldCommandEnvelope) -> String {
        let request = "{nonce:'\(envelope.nonce)',command:\(envelope.commandJSON)}"
        return """
        (()=>{const root=document.documentElement;
        if(root.getAttribute('data-riftlet-channel-\(channel)')!=='\(marker)')throw Error('BRIDGE_UNAVAILABLE');
        root.setAttribute('data-riftlet-command',JSON.stringify(\(request)));
        root.dispatchEvent(new Event('riftlet-command-\(channel)'));
        root.removeAttribute('data-riftlet-command');return 'submitted';})()
        """
    }
}

/// Native ownership only. A missing relay on a background route never causes a
/// URL-setter fallback or new capture. A new document must be captured foreground.
final class MainWorldRelayStore: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: MainWorldCommandRelay] = [:]
    func adopt(function: String, contextJSON: String, channel: String,
               legacyObservationSession: String?) -> MainWorldCommandRelay? {
        guard let id = UUID(uuidString: channel), id.uuidString.lowercased() == channel else { return nil }
        let key = SHA256.hash(data: Data((function + "\n" + contextJSON).utf8)).map { String(format: "%02x", $0) }.joined()
        lock.lock(); defer { lock.unlock() }
        if let value = values[key] { return value }
        let value = MainWorldCommandRelay(function: function, contextJSON: contextJSON,
            legacyObservationSession: legacyObservationSession, channel: channel)
        values[key] = value
        return value
    }
    func relay(function: String, contextJSON: String, allowCreate: Bool, legacyObservationSession: String? = nil) -> MainWorldCommandRelay? {
        let key = SHA256.hash(data: Data((function + "\n" + contextJSON).utf8)).map { String(format: "%02x", $0) }.joined()
        lock.lock(); defer { lock.unlock() }
        if let value = values[key], !allowCreate || legacyObservationSession == nil || value.legacyObservationSession == legacyObservationSession { return value }
        guard allowCreate else { return nil }
        let value = MainWorldCommandRelay(function: function, contextJSON: contextJSON, legacyObservationSession: legacyObservationSession)
        values[key] = value
        return value
    }
}
