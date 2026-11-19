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

    private static func marker(function: String, contextJSON: String, legacyJSON: String) -> String {
        SHA256.hash(data: Data((function + "\n" + contextJSON + "\n" + legacyJSON).utf8))
            .map { String(format: "%02x", $0) }.joined()
    }

    init(function: String, contextJSON: String, legacyObservationSession: String? = nil, channel: String = UUID().uuidString.lowercased()) {
        self.channel = channel
        self.legacyObservationSession = legacyObservationSession
        let legacyJSON = String(decoding: try! JSONEncoder().encode(legacyObservationSession), as: UTF8.self)
        marker = Self.marker(function: function, contextJSON: contextJSON, legacyJSON: legacyJSON)
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
    var discovery: String {
        Self.discovery(markers: [marker])
    }

    private static func discovery(markers: [String]) -> String {
        let values = String(decoding: try! JSONEncoder().encode(markers), as: UTF8.self)
        return """
        (()=>{const root=document.documentElement;if(root.attributes.length>1024)return 'ambiguous';
        const markers=\(values),prefix='data-riftlet-channel-';let result='';
        for(const a of root.attributes){
          if(!a.name.startsWith(prefix))continue;
          const index=markers.indexOf(a.value);if(index<0)continue;
          const id=a.name.slice(prefix.length);
          if(!/^[a-f0-9]{8}-(?:[a-f0-9]{4}-){3}[a-f0-9]{12}$/.test(id))continue;
          if(result)return 'ambiguous';
          result=markers.length===1?id:index+':'+id;
        }
        return result;})()
        """
    }

    static func discoverOriginal(program: WebPageProgram, contextJSON: String, legacyObservationSession: String?,
                                 read: (String) throws -> String) throws -> Self {
        let functions = try ChatGPTWebPageProgram.observationRelayFunctions(for: program)
        let legacyJSON = String(decoding: try JSONEncoder().encode(legacyObservationSession), as: UTF8.self)
        let markers = functions.map { marker(function: $0, contextJSON: contextJSON, legacyJSON: legacyJSON) }
        let reply = try read(discovery(markers: markers))
        let channel: String, index: Int
        if markers.count == 1 {
            (index, channel) = (0, reply)
        } else {
            guard reply.utf8.count <= 40 else { throw WebAdapterError.pageRejected(.bridgeUnavailable) }
            let parts = reply.split(separator: ":", maxSplits: 1)
            guard parts.count == 2, let variant = Int(parts[0]), functions.indices.contains(variant),
                  String(variant) == parts[0] else { throw WebAdapterError.pageRejected(.bridgeUnavailable) }
            (index, channel) = (variant, String(parts[1]))
        }
        guard let uuid = UUID(uuidString: channel), uuid.uuidString.lowercased() == channel else {
            throw WebAdapterError.pageRejected(.bridgeUnavailable)
        }
        return Self(function: functions[index], contextJSON: contextJSON,
                    legacyObservationSession: legacyObservationSession, channel: channel)
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

/// Native ownership only. A click may initialize its exact saved tab without a
/// historical relay. Observation never creates a relay or captures a new target.
final class MainWorldRelayStore: @unchecked Sendable {
    private let lock = NSLock()
    private let activeSourceID: String
    init(activeSourceID: String = ChatGPTWebPageProgram.sourceID) { self.activeSourceID = activeSourceID }

    private func observationOnly(_ sourceID: String) -> Bool {
        sourceID != activeSourceID && ChatGPTWebPageProgram.isHistoricalObserver(sourceID)
    }
    private var values = ChromeSessionCache<MainWorldCommandRelay>()
    // Keep exact per-click relays through the input window. Long-lived read-only
    // operations can rediscover their original page relay from its marker.
    private var targetRelays: [String: (relay: MainWorldCommandRelay, captured: TimeInterval)] = [:]
    // A channel found after restart is only a route back to this original
    // observation. It never enters the capture/input cache.
    private var observed: [(identity: ObservationIdentity, sourceID: String, relay: MainWorldCommandRelay)] = []

    func resolve(_ command: WebBridgeCommand, program: WebPageProgram, contextJSON: String,
                 legacyObservationSession: String? = nil, read: (String) throws -> String) throws -> MainWorldCommandRelay {
        if command.action == .observe {
            guard let target = command.target, let identity = command.identity, identity.target == target else {
                throw WebAdapterError.invalidRequest
            }
            if !observationOnly(program.sourceID), let known = bound(to: target) { return known }
            if let known = lock.withLock({ observed.first { $0.identity == identity && $0.sourceID == program.sourceID } }) {
                return known.relay
            }
            let found = try MainWorldCommandRelay.discoverOriginal(program: program, contextJSON: contextJSON,
                legacyObservationSession: legacyObservationSession, read: read)
            lock.withLock {
                observed.removeAll { $0.identity == identity }
                if observed.count == 32 { observed.removeFirst() }
                observed.append((identity, program.sourceID, found))
            }
            return found
        }
        guard !observationOnly(program.sourceID) else { throw WebAdapterError.invalidRequest }
        if let known = command.target.flatMap({ bound(to: $0) }) ?? relay(function: program.functionSource,
            contextJSON: contextJSON, allowCreate: false, legacyObservationSession: legacyObservationSession) {
            return known
        }
        guard command.action == .captureTarget else { throw WebAdapterError.pageRejected(.bridgeUnavailable) }
        let current = MainWorldCommandRelay(function: program.functionSource, contextJSON: contextJSON,
                                            legacyObservationSession: legacyObservationSession)
        let channel = try read(current.discovery)
        if channel.isEmpty, let created = relay(function: program.functionSource, contextJSON: contextJSON,
            allowCreate: true, legacyObservationSession: legacyObservationSession) { return created }
        guard let existing = adopt(function: program.functionSource, contextJSON: contextJSON,
                                   channel: channel, legacyObservationSession: legacyObservationSession) else {
            throw WebAdapterError.pageRejected(.bridgeUnavailable)
        }
        return existing
    }

    func bind(_ relay: MainWorldCommandRelay, to target: TargetLease) {
        lock.lock(); defer { lock.unlock() }
        let now = ProcessInfo.processInfo.systemUptime
        targetRelays = targetRelays.filter { now - $0.value.captured < 60 }
        targetRelays[target.stableKey] = (relay, now)
    }
    func bound(to target: TargetLease) -> MainWorldCommandRelay? {
        lock.lock(); defer { lock.unlock() }
        return targetRelays[target.stableKey]?.relay
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
