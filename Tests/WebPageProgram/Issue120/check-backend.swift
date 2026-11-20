import CryptoKit
import Foundation
import RiftletCore
@testable import RiftletAdapters

private actor LocalPage: Issue120ProviderTransport {
    enum Mode { case accepted, lostCommitReply, failed, wrongFailureCard, wrongPayload, wrongKey }
    var mode = Mode.accepted
    var commits = 0
    var reads = 0
    var returned = 0
    var target: TargetLease
    init(_ target: TargetLease) { self.target = target }
    func set(_ m: Mode) { mode = m }
    func bind(_ newTarget: TargetLease) { target = newTarget }
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
        case .wrongFailureCard: return .init(key:key,state:.failedOriginalCard(card:"foreign-card",observedPayloadSHA256:key.pngSHA256))
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
        func clickTarget() -> TargetLease {
            TargetLease(adapterID:"riftlet-web-provider-v1",surface:.webChat,applicationID:"com.google.Chrome",
                sessionID:"controlled-process-birth",windowID:"1",tabID:"2",documentID:"document",composerID:"editor",
                draftGeneration:"epoch",clickBindingID:UUID(),providerBinding:binding)
        }
        let target = clickTarget()
        let policy = ReceiptPolicy(syntheticUploadStartProfiles: [profile.id: .webChat])
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
                byteCount:Int64(png.count),pixelWidth:1,pixelHeight:1,mediaType:"image/png",origin:.synthetic))
            let op = try await store.prepare(assetID:imported.id,target:target)
            let owner = UUID()
            let invocation = try await store.markIndependentFileInputIntent(op.id,ownerID:owner)
            let actual = try await store.operation(id:op.id)!
            let req = TransferRequest(operation:actual,asset:imported.image,fileURL:file,invocationID:invocation)
            await page.set(i == 1 ? .accepted : .lostCommitReply)
            let receipt = try await runtime.append(req,onInputExecutionReturned:{ await page.returnBoundary() })
            precondition(receipt.outcome == (i == 1 ? .uploadStarted : .unknown) && !receipt.safeToRetry && !receipt.positiveReady)
            let duplicate = try? await runtime.append(req)
            precondition(duplicate == nil)
            try await store.recordInputExecutionReturned(operationID: op.id, invocationID: invocation, ownerID: owner)
            let settled = try await store.apply(receipt, policy: policy)
            precondition(settled.visibility == (i == 1 ? .swallowed : .visible))
            let database = try QueueStore(databaseURL: db)
            let reopened = ProviderAttachmentRuntime(resolver: resolver, store: database)
            let modes: [LocalPage.Mode] = i == 1 ? [.wrongKey, .wrongPayload, .failed] : [.wrongKey, .wrongPayload]
            for mode in modes {
                await page.set(mode)
                let read = try await reopened.reconcile(req)
                precondition(read.outcome == .unknown && !read.safeToRetry && !read.positiveReady)
                precondition(read.originalCardFailureInvocationID == (mode == .failed ? invocation : nil))
            }
            if i == 1 {
                let coordinator = TransferCoordinator(store: database, adapter: reopened, mediaDirectory: directory,
                    policy: policy, validateAcceptedSelection: { $0.isValid() })
                try await coordinator.recover()
                await page.set(.wrongFailureCard)
                let rejected = try await coordinator.recheckOriginal(operationID: op.id, authorize: { $0 == target })
                precondition(rejected == .unavailable)
                await page.set(.failed)
                let checked = try await coordinator.recheckOriginal(operationID: op.id, authorize: { $0 == target })
                let history = try await database.historySnapshot().first { $0.record.id == imported.id }
                precondition(checked == .observed && history?.attachmentState == .originalCardFailed)
                precondition(history?.startReceipt?.attachmentID == receipt.attachmentID)
                let staged = try await database.stageAttachmentForReattach(operationID: op.id)
                let before = await page.commits
                let restored = try Data(contentsOf: file)
                precondition(before == 1 && restored == png && staged.visibility == .visible && staged.activeOperationID == op.id)

                let freshTarget = clickTarget()
                await page.bind(freshTarget)
                await page.set(.accepted)
                let click = AcceptedSelection(assetID: imported.id, target: freshTarget, visibilityRevision: staged.visibilityRevision)
                try await coordinator.reattach(click, replacing: op.id)
                for _ in 0..<200 where await coordinator.hasInFlightAttachmentWork {
                    try await Task.sleep(nanoseconds: 5_000_000)
                }
                let duplicateClick: Void? = try? await coordinator.reattach(click, replacing: op.id)
                precondition(duplicateClick == nil)
                let after = try await database.historySnapshot().first { $0.record.id == imported.id }
                let writes = await page.commits
                precondition(writes == 2 && after?.operation?.attempt == 2 && after?.operation?.target == freshTarget)
                precondition(after?.attachmentState == .handedOff && after?.record.visibility == .swallowed)
                let original = try await database.receipt(for: op.id)
                precondition(original?.originalCardFailureInvocationID == invocation)
                await page.bind(target)
            }
        }
        let commits = await page.commits, reads = await page.reads, returned = await page.returned
        precondition(commits == 3 && reads == 10 && returned == 2)
        print("PASS controlled Swift provider and SQLite: original failure survived restart, exact PNG restored without input, explicit new click attached on attempt 2; lost reply and wrong identity never automatically retransmitted")
    }
}
