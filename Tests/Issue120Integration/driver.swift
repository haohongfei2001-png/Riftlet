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
        let events = "input-change"
        let lane: String, card: String
        let explicitFailure = "[role=alert][aria-label=failed]"
        let maxBytes = 65536
    }
    let origin: String
    let paths: [String]
    let recipe: Recipe
    let editor: String, action: String
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
        let profileID = CommandLine.arguments[2]
        let paths = ["fixture-gemini-like": "/app", "fixture-claude-like": "/fixture-claude-like"]
        guard let path = paths[profileID], let endpoint = URL(string:origin+path), let port = endpoint.port,
              origin == "http://127.0.0.1:\(port)", let resourceDir = Bundle.main.resourceURL,
              let bundle = Bundle(url:resourceDir.appendingPathComponent("Riftlet_RiftletAdapters.bundle")),
              let js = bundle.url(forResource:"issue120-provider-runtime",withExtension:"js")
        else { throw BindingError.unsupported }
        let claudeFixture = profileID == "fixture-claude-like"
        let definition = FixtureScope(origin:origin, paths:[path],
            recipe:.init(lane:claudeFixture ? "ul[data-fixture-lane]" : "section", card:claudeFixture ? "li" : "article"),
            editor:claudeFixture ? "[data-fixture-editor][contenteditable=true]" : "[contenteditable=true]",
            action:claudeFixture ? "button[data-fixture-upload]" : "label")
        let program = try Issue120ProviderCatalog.bind(runtime:String(contentsOf:js,encoding:.utf8), definition:definition)
        let profile = try ProviderProfile(id:profileID,revision:1,program:Data(program.utf8))
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
            byteCount:Int64(png.count),pixelWidth:1,pixelHeight:1,mediaType:"image/png",origin:.synthetic))
        try await runtime.preflight(asset:asset.image,fileURL:file,frozenTarget:target)
        let op = try await store.prepare(assetID:asset.id,target:target)
        let owner = UUID()
        let id = try await store.markIndependentFileInputIntent(op.id,ownerID:owner)
        let original = try await store.operation(id:op.id)!
        let request = TransferRequest(operation:original,asset:asset.image,fileURL:file,invocationID:id)
        let receipt = try await runtime.append(request)
        let repeated = try? await runtime.append(request)
        guard repeated == nil else { throw BindingError.targetChanged }
        try await store.recordInputExecutionReturned(operationID:op.id,invocationID:id,ownerID:owner)
        let policy = ReceiptPolicy(syntheticUploadStartProfiles: [profileID: .webChat])
        _ = try await store.apply(receipt, policy:policy)
        let reopened = try QueueStore(databaseURL:db)
        let after = ProviderAttachmentRuntime(resolver:resolver,store:reopened)
        let replay = try? await after.append(request)
        guard replay == nil, !receipt.safeToRetry, !receipt.positiveReady else { throw BindingError.targetChanged }
        if CommandLine.arguments[3] == "lost" {
            let read = try await after.reconcile(request)
            guard receipt.outcome == .unknown, receipt.attachmentID == nil, read.outcome == .unknown,
                  !read.safeToRetry, read.uploadStartEvidence == nil,
                  try await reopened.uploadStartReceipt(for:op.id) == nil,
                  try await reopened.asset(id:asset.id)?.visibility == .visible,
                  try await reopened.dispatchInvocationID(for:op.id) == id,
                  try exchange(.init(action:"finish")).result == "checked" else { throw BindingError.targetChanged }
            return
        }
        guard receipt.outcome == .uploadStarted, receipt.belongsToOriginalDraft, let member = receipt.attachmentID,
              try exchange(.init(action:"fail")).result == "original-card-updated" else { throw BindingError.targetChanged }
        let coordinator = TransferCoordinator(store:reopened,adapter:after,mediaDirectory:temp,policy:policy)
        let checked = try await coordinator.recheckOriginal(operationID:op.id,authorize:{ $0 == target })
        let restarted = try QueueStore(databaseURL:db)
        guard checked == .observed, let recovery = try await restarted.receipt(for:op.id),
              try await restarted.uploadStartReceipt(for:op.id)?.attachmentID == member else { throw BindingError.targetChanged }
        guard recovery.outcome == .unknown, recovery.hasError, !recovery.safeToRetry, !recovery.positiveReady,
              recovery.originalCardFailureInvocationID == id, recovery.attachmentID == member else {
            throw BindingError.targetChanged
        }
        let restored = try await restarted.stageAttachmentForReattach(operationID:op.id)
        let stagedRuntime = ProviderAttachmentRuntime(resolver:resolver,store:restarted)
        let replayAfterRestore = try? await stagedRuntime.append(request)
        guard replayAfterRestore == nil, restored.visibility == .visible, restored.activeOperationID == op.id,
              try Data(contentsOf:file) == png else { throw BindingError.targetChanged }
        guard try exchange(.init(action:"finish")).result == "checked" else { throw BindingError.unsupported }
    }
}
