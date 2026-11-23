import Foundation
import CryptoKit
import RiftletCore

/// A document-local MAIN closure, installed when an explicit click first resolves
/// its fixed target. Later commands cross the shared DOM through execute-JavaScript; unlike
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
        let actions = String(decoding: try! JSONEncoder().encode(WebBridgeAction.allCases.map(\.rawValue)), as: UTF8.self)
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
            ||!q.command||!\(actions).includes(q.command.action)
            ||seen.has(q.nonce))return;
          seen.add(q.nonce); // Lifetime nonce tombstone, before executing/reentrancy.
          const receiver=q.command.action==='observe'&&legacySession&&q.command.target?.sessionID===legacySession
            ?Object.freeze({...native,sessionID:legacySession}):native;
          // Menu discovery can await a real application render. Invoke once,
          // then publish only its settled result; serializing a Promise as {}
          // would lose a successful input and release the host lane too early.
          let replied=false;
          const publish=r=>{if(replied)return;replied=true;
            if(document.documentElement!==root)return;
            const reply='data-riftlet-reply-'+q.nonce;root.setAttribute(reply,JSON.stringify(r));
            setTimeout(()=>root.removeAttribute(reply),10000);};
          const success=result=>publish({nonce:q.nonce,ok:true,result});
          const failure=e=>{const r={nonce:q.nonce,ok:false},code=e?.message;
            if(\(codes).includes(code))r.rejection=code;publish(r);};
          try{const result=program(q.command,receiver);
            if(result&&typeof result.then==='function')Promise.resolve(result).then(success,failure);
            else success(result);
          }catch(e){failure(e);}
        });
        root.setAttribute(attribute,marker);})()
        """
    }

    /// Read-only recovery of an already installed exact-version channel after
    /// native restart. Zero/ambiguous matches do not install or run a command.
    var discovery: String { Self.discovery(marker: marker) }

    fileprivate static func discovery(marker: String) -> String {
        """
        (()=>{const root=document.documentElement;if(root.attributes.length>1024)return 'ambiguous';
        const matches=[...root.attributes].filter(a=>a.name.startsWith('data-riftlet-channel-')&&a.value==='\(marker)')
          .map(a=>a.name.slice('data-riftlet-channel-'.length))
          .filter(id=>/^[a-f0-9]{8}-(?:[a-f0-9]{4}-){3}[a-f0-9]{12}$/.test(id));
        return matches.length===1?matches[0]:(matches.length===0?'':'ambiguous');})()
        """
    }

    func dispatch(_ envelope: MainWorldCommandEnvelope) -> String {
        Self.dispatch(channel: channel, marker: marker, nonce: envelope.nonce, commandJSON: envelope.commandJSON)
    }

    fileprivate static func dispatch(channel: String, marker: String, nonce: String, commandJSON: String) -> String {
        let request = "{nonce:'\(nonce)',command:\(commandJSON)}"
        return """
        (()=>{const root=document.documentElement;
        if(root.getAttribute('data-riftlet-channel-\(channel)')!=='\(marker)')throw Error('BRIDGE_UNAVAILABLE');
        root.setAttribute('data-riftlet-command',JSON.stringify(\(request)));
        root.dispatchEvent(new Event('riftlet-command-\(channel)'));
        root.removeAttribute('data-riftlet-command');return 'submitted';})()
        """
    }
}

/// Read-only recovery after the native binding is gone. Both historical and
/// current channels can survive on one document; none has priority over another.
struct OriginalObservationChannel {
    let discovery: String
    private let currentMarker: String
    private let markers: Set<String>
    private let owner: ObservationIdentity

    init?(context: String, legacySession: String?, currentMarker: String, owner: ObservationIdentity) {
        guard let archived = ArchivedObservationCompatibility.markers(contextJSON: context, legacyObservationSession: legacySession)
        else { return nil }
        self.currentMarker = currentMarker
        self.owner = owner
        markers = Set(archived + [currentMarker])
        let values = String(decoding: try! JSONEncoder().encode(markers.sorted()), as: UTF8.self)
        discovery = """
        (()=>{const root=document.documentElement;if(root.attributes.length>1024)return 'ambiguous';
        const prefix='data-riftlet-channel-',markers=new Set(\(values));
        const matches=[...root.attributes].filter(a=>a.name.startsWith(prefix)&&markers.has(a.value));
        if(matches.length!==1)return matches.length?'ambiguous':'';
        const id=matches[0].name.slice(prefix.length);
        return /^[a-f0-9]{8}-(?:[a-f0-9]{4}-){3}[a-f0-9]{12}$/.test(id)?matches[0].value+':'+id:'ambiguous';})()
        """
    }

    func read(match: String, nonce: String, command: WebBridgeCommand) throws -> String {
        let parts = match.components(separatedBy: ":")
        guard parts.count == 2, markers.contains(parts[0]),
              let id = UUID(uuidString: parts[1]), id.uuidString.lowercased() == parts[1],
              let receipt = UUID(uuidString: nonce), receipt.uuidString.lowercased() == nonce,
              command.action == .observe, let target = command.target,
              let identity = command.identity, identity == owner, owner.target == target,
              parts[0] == currentMarker || command.invocationID != nil
        else { throw WebAdapterError.invalidTarget }
        let original = WebBridgeCommand(action: .observe, target: target, identity: identity,
            invocationID: command.invocationID, requireLiveOriginal: parts[0] == currentMarker ? command.requireLiveOriginal : true,
            preferStartReceipt: command.preferStartReceipt)
        let json = String(decoding: try JSONEncoder().encode(original), as: UTF8.self)
        let dispatch = MainWorldCommandRelay.dispatch(channel: parts[1], marker: parts[0], nonce: nonce, commandJSON: json)
        // The document can acquire a second relay between the two native sends.
        return "(()=>{if(\(discovery)!=='\(match)')throw Error('BRIDGE_UNAVAILABLE');return \(dispatch);})()"
    }
}

/// Native ownership only. A click may initialize its exact saved tab without a
/// historical relay. Observation never creates a relay or captures a new target.
final class MainWorldRelayStore: @unchecked Sendable {
    private let lock = NSLock()
    private var values = ChromeSessionCache<MainWorldCommandRelay>()
    private var targetRelays = ChromeSessionCache<MainWorldCommandRelay>()
    func bind(_ relay: MainWorldCommandRelay, to target: TargetLease) {
        lock.lock(); defer { lock.unlock() }
        targetRelays.store(relay, for: target.stableKey)
    }
    func unbind(_ target: TargetLease) {
        lock.lock(); defer { lock.unlock() }
        targetRelays.remove(for: target.stableKey)
    }
    func bound(to target: TargetLease) -> MainWorldCommandRelay? {
        lock.lock(); defer { lock.unlock() }
        return targetRelays.value(for: target.stableKey)
    }
    func adopt(function: String, contextJSON: String, channel: String,
               legacyObservationSession: String?) -> MainWorldCommandRelay? {
        guard let id = UUID(uuidString: channel), id.uuidString.lowercased() == channel else { return nil }
        let key = SHA256.hash(data: Data((function + "\n" + contextJSON).utf8)).map { String(format: "%02x", $0) }.joined()
        lock.lock(); defer { lock.unlock() }
        if let value = values.value(for: key) { return value }
        let value = MainWorldCommandRelay(function: function, contextJSON: contextJSON,
            legacyObservationSession: legacyObservationSession, channel: channel)
        values.store(value, for: key)
        return value
    }
    func relay(function: String, contextJSON: String, allowCreate: Bool, legacyObservationSession: String? = nil) -> MainWorldCommandRelay? {
        let key = SHA256.hash(data: Data((function + "\n" + contextJSON).utf8)).map { String(format: "%02x", $0) }.joined()
        lock.lock(); defer { lock.unlock() }
        if let value = values.value(for: key), !allowCreate || legacyObservationSession == nil || value.legacyObservationSession == legacyObservationSession { return value }
        guard allowCreate else { return nil }
        let value = MainWorldCommandRelay(function: function, contextJSON: contextJSON, legacyObservationSession: legacyObservationSession)
        values.store(value, for: key)
        return value
    }
}
