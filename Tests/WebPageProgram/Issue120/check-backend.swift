import CryptoKit
import Foundation
import RiftletCore
@testable import RiftletAdapters

private actor LocalPage: Issue120ProviderTransport {
    enum Mode { case accepted, lostCommitReply, failed, wrongPayload, wrongKey }
    var mode = Mode.accepted
    var commits = 0
    var reads = 0
    var returned = 0
    let target: TargetLease
    init(_ target: TargetLease) { self.target = target }
    func set(_ m: Mode) { mode = m }
    func returnBoundary() { returned += 1 }
    func validateOriginal(_ target: TargetLease, profile: ProviderProfile) -> Bool {
        self.target == target && target.providerBinding?.programSHA256 == profile.digest
    }
    func commitOnce(_ key: Issue120Invocation, png: Data) throws -> Issue120InputReply {
        precondition(key.target == target && key.pngSHA256 == hash(png))
        commits += 1
        if mode == .lostCommitReply { throw BindingError.targetChanged }
        return .init(key: key, confirmedOneInput: true)
    }
    func observeOriginal(_ key: Issue120Invocation) -> Issue120Observation {
        reads += 1
        let card = "isolated-"+key.invocation.uuidString
        switch mode {
        case .lostCommitReply: return .init(key: key,state:.unknown)
        case .failed: return .init(key:key,state:.failedOriginalCard(card:card,observedPayloadSHA256:key.pngSHA256))
        case .accepted: return .init(key:key,state:.accepted(card:card,observedPayloadSHA256:key.pngSHA256))
        case .wrongPayload: return .init(key:key,state:.accepted(card:card,observedPayloadSHA256:String(repeating:"0",count:64)))
        case .wrongKey:
            let stale = Issue120Invocation(target:key.target,profile:key.profile,operation:key.operation,
                invocation:UUID(),asset:key.asset,attempt:key.attempt,pngSHA256:key.pngSHA256)
            return .init(key:stale,state:.accepted(card:card,observedPayloadSHA256:key.pngSHA256))
        }
    }
}
private func hash(_ bytes: Data) -> String { SHA256.hash(data: bytes).map { String(format:"%02x",$0) }.joined() }

@main struct BackendCheck {
    static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:false)
        defer { try? FileManager.default.removeItem(at:directory) }
        let db = directory.appendingPathComponent("store.sqlite")
        let store = try QueueStore(databaseURL:db)
        let endpoint = URL(string:"http://127.0.0.1:12345/app")!
        let profile = try ProviderProfile(id:"fixture-gemini-like",revision:1,program:Data("controlled program".utf8))
        let binding = WebProviderBinding(providerID:profile.id,revision:profile.revision,programSHA256:profile.digest,
            routeSHA256:hash(Data(endpoint.absoluteString.utf8)),surface:"ordinary-fixture",mode:"image-fixture")
        let target = TargetLease(adapterID:"riftlet-web-provider-v1",surface:.webChat,applicationID:"com.google.Chrome",
            sessionID:"controlled-process-birth",windowID:"1",tabID:"2",documentID:"document",composerID:"editor",
            draftGeneration:"epoch",clickBindingID:UUID(),providerBinding:binding)
        let page = LocalPage(target)
        let backend = try Issue120ProviderAdapter(loopback:endpoint,profile:profile,bundle:target.applicationID,
                                                   mediaDirectory:directory,transport:page)
        let disabled = Issue120ProviderAdapter(profile:profile,bundle:target.applicationID,mediaDirectory:directory,transport:page)
        let permitted = try await disabled.validate(target)
        precondition(!permitted)
        let address = AdapterAddress(bundle:target.applicationID,profile:profile,adapterID:target.adapterID)
        let resolver = AdapterResolver(adapters:[address:backend])
        let runtime = ProviderAttachmentRuntime(resolver:resolver,store:store)
        let png = Data(base64Encoded:"iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+X2ZsAAAAASUVORK5CYII=")!
        for i in 1...2 {
            let name = "\(i).png", file = directory.appendingPathComponent(name)
            try png.write(to:file)
            let imported = try await store.importAsset(.init(sourceKey:name,fileName:name,sha256:hash(png),
                byteCount:Int64(png.count),pixelWidth:1,pixelHeight:1,mediaType:"image/png"))
            let op = try await store.prepare(assetID:imported.id,target:target)
            let invocation = try await store.markIndependentFileInputIntent(op.id,ownerID:UUID())
            let actual = try await store.operation(id:op.id)!
            let req = TransferRequest(operation:actual,asset:imported.image,fileURL:file,invocationID:invocation)
            await page.set(i == 1 ? .accepted : .lostCommitReply)
            let receipt = try await runtime.append(req,onInputExecutionReturned:{ await page.returnBoundary() })
            precondition(receipt.outcome == (i == 1 ? .uploadStarted : .unknown) && !receipt.safeToRetry && !receipt.positiveReady)
            let duplicate = try? await runtime.append(req)
            precondition(duplicate == nil)
            let reopened = ProviderAttachmentRuntime(resolver:resolver,store:try QueueStore(databaseURL:db))
            for mode in [LocalPage.Mode.wrongKey,.wrongPayload,.failed] {
                await page.set(mode)
                let read = try await reopened.reconcile(req)
                precondition(read.outcome == .unknown && !read.safeToRetry && !read.positiveReady)
                precondition(read.originalCardFailureInvocationID == (mode == .failed ? invocation : nil))
            }
        }
        let commits = await page.commits, reads = await page.reads, returned = await page.returned
        precondition(commits == 2 && reads == 8 && returned == 2)
        print("PASS Swift backend + real SQLite: 2 fresh operations, 2 input returns, 2 duplicate calls refused, 8 original-only reads; wrong payload/key UNKNOWN, no re-input after restart")
    }
}
