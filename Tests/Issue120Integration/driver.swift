import CryptoKit
import Foundation
import RiftletCore
@testable import RiftletAdapters

private func hash(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

private struct Command: Codable {
    let action: String
    var program: String? = nil
    var body: String? = nil
    var click: String? = nil
    var identity: String? = nil
}

private struct Reply: Codable {
    let action: String
    let result: String
    var identity: String?
    var digest: String?
    var card: String?
    var document: String?
    var editor: String?
    var epoch: String?
}

private func exchange(_ cmd: Command) throws -> Reply {
    var data = try JSONEncoder().encode(cmd)
    data.append(10)
    try FileHandle.standardOutput.write(contentsOf: data)
    guard let line = readLine() else { throw BindingError.unsupported }
    let reply = try JSONDecoder().decode(Reply.self, from: Data(line.utf8))
    guard reply.action == cmd.action, reply.result != "error" else { throw BindingError.targetChanged }
    return reply
}

private struct FixtureScope: Encodable {
    struct Recipe: Encodable {
        let events = "input-change", lane = "section", card = "article"
        let explicitFailure = "[role=alert][aria-label=failed]"
        let maxBytes = 65536
    }
    let origin: String
    let paths = ["/app"]
    let recipe = Recipe()
    let editor = "[contenteditable=true]", action = "label"
}

// This test transport sends commands through one private loopback page session.
// Its original click/document are never re-selected when SQLite is reopened.
private actor Browser: Issue120ProviderTransport {
    let target: TargetLease
    init(_ target: TargetLease) { self.target = target }

    func validateOriginal(_ candidate: TargetLease, profile: ProviderProfile) throws -> Bool {
        guard candidate == target, candidate.providerBinding?.programSHA256 == profile.digest else { return false }
        let r = try exchange(.init(action:"validate"))
        return r.result == "current" && r.document == target.documentID && r.editor == target.composerID &&
               r.epoch == target.draftGeneration
    }

    private func identity(_ k: Issue120Invocation) throws -> String {
        guard k.target == target, let click = k.target.clickBindingID else { throw BindingError.targetChanged }
        let fields = ["click":click.uuidString.lowercased(),"operation":k.operation.uuidString.lowercased(),
                      "invocation":k.invocation.uuidString.lowercased(),"asset":k.asset.uuidString.lowercased(),
                      "attempt":String(k.attempt),"originalSHA256":k.pngSHA256,"payloadSHA256":k.pngSHA256,
                      "profileDigest":k.profile.digest,"document":target.documentID,"editor":target.composerID,
                      "epoch":target.draftGeneration]
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding:try encoder.encode(fields),as:UTF8.self)
    }

    func commitOnce(_ key: Issue120Invocation, png: Data) throws -> Issue120InputReply {
        let token = try identity(key)
        let r = try exchange(.init(action:"commit",body:png.base64EncodedString(),identity:token))
        guard r.result == "input_returned", r.identity == token else { throw BindingError.targetChanged }
        return .init(key:key,confirmedOneInput:true)
    }

    func observeOriginal(_ key: Issue120Invocation) throws -> Issue120Observation {
        let token = try identity(key)
        let r = try exchange(.init(action:"observe",identity:token))
        guard r.identity == token, let card = r.card, let digest = r.digest else {
            return .init(key:key,state:.unknown)
        }
        switch r.result {
        case "accepted_into_draft": return .init(key:key,state:.accepted(card:card,observedPayloadSHA256:digest))
        case "original_card_failed": return .init(key:key,state:.failedOriginalCard(card:card,observedPayloadSHA256:digest))
        default: return .init(key:key,state:.unknown)
        }
    }
}

@main struct Integration {
    static func main() async throws {
        let origin = CommandLine.arguments[1]
        guard let endpoint = URL(string:origin+"/app"), let port = endpoint.port,
              origin == "http://127.0.0.1:\(port)", let resourceDir = Bundle.main.resourceURL,
              let bundle = Bundle(url:resourceDir.appendingPathComponent("Riftlet_RiftletAdapters.bundle")),
              let js = bundle.url(forResource:"issue120-provider-runtime",withExtension:"js")
        else { throw BindingError.unsupported }
        let program = try Issue120ProviderCatalog.bind(runtime:String(contentsOf:js,encoding:.utf8),
                                                        definition:FixtureScope(origin:origin))
        let profile = try ProviderProfile(id:"fixture-gemini-like",revision:1,program:Data(program.utf8))
        let click = UUID()
        let pin = try exchange(.init(action:"pin",program:program,click:click.uuidString.lowercased()))
        guard pin.digest == profile.digest, let document = pin.document, let editor = pin.editor, let epoch = pin.epoch,
              !document.isEmpty, !editor.isEmpty, !epoch.isEmpty else { throw BindingError.targetChanged }
        let scope = WebProviderBinding(providerID:profile.id,revision:1,programSHA256:profile.digest,
            routeSHA256:hash(Data(endpoint.absoluteString.utf8)),surface:"ordinary-fixture",mode:"image-fixture")
        let target = TargetLease(adapterID:"riftlet-web-provider-v1",surface:.webChat,applicationID:"com.google.Chrome",
            sessionID:"isolated-loopback-test",windowID:"fixture-window",tabID:"fixture-tab",
            documentID:document,composerID:editor,draftGeneration:epoch,clickBindingID:click,providerBinding:scope)
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:temp,withIntermediateDirectories:false)
        defer { try? FileManager.default.removeItem(at:temp) }
        let db = temp.appendingPathComponent("qa.sqlite")
        let store = try QueueStore(databaseURL:db)
        let page = Browser(target)
        let adapter = try Issue120ProviderAdapter(loopback:endpoint,profile:profile,bundle:target.applicationID,
                                                  mediaDirectory:temp,transport:page)
        let address = AdapterAddress(bundle:target.applicationID,profile:profile,adapterID:target.adapterID)
        let resolver = AdapterResolver(adapters:[address:adapter])
        let runtime = ProviderAttachmentRuntime(resolver:resolver,store:store)
        let png = Data(base64Encoded:"iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+X2ZsAAAAASUVORK5CYII=")!
        let file = temp.appendingPathComponent("capture.png")
        try png.write(to:file)
        let asset = try await store.importAsset(.init(sourceKey:"generated",fileName:file.lastPathComponent,sha256:hash(png),
            byteCount:Int64(png.count),pixelWidth:1,pixelHeight:1,mediaType:"image/png"))
        try await runtime.preflight(asset:asset.image,fileURL:file,frozenTarget:target)
        let op = try await store.prepare(assetID:asset.id,target:target)
        let owner = UUID()
        let id = try await store.markIndependentFileInputIntent(op.id,ownerID:owner)
        let original = try await store.operation(id:op.id)!
        let request = TransferRequest(operation:original,asset:asset.image,fileURL:file,invocationID:id)
        let accepted = try await runtime.append(request)
        guard accepted.outcome == .uploadStarted, accepted.belongsToOriginalDraft, !accepted.safeToRetry,
              !accepted.positiveReady, let member = accepted.attachmentID else { throw BindingError.targetChanged }
        let repeated = try? await runtime.append(request)
        guard repeated == nil else { throw BindingError.targetChanged }
        try await store.recordInputExecutionReturned(operationID:op.id,invocationID:id,ownerID:owner)
        guard try exchange(.init(action:"fail")).result == "original-card-updated" else { throw BindingError.unsupported }
        let reopened = try QueueStore(databaseURL:db)
        let after = ProviderAttachmentRuntime(resolver:resolver,store:reopened)
        let recovery = try await after.reconcile(request)
        guard recovery.outcome == .unknown, recovery.hasError, !recovery.safeToRetry, !recovery.positiveReady,
              recovery.originalCardFailureInvocationID == id, recovery.attachmentID == member else {
            throw BindingError.targetChanged
        }
        guard try exchange(.init(action:"finish")).result == "checked" else { throw BindingError.unsupported }
    }
}
