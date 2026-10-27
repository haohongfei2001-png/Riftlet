import Foundation
import JavaScriptCore
import XCTest
@testable import RiftletAdapters

final class LegacyWebObservationProgramTests: XCTestCase {
    private func context() throws -> JSContext {
        let context = try XCTUnwrap(JSContext())
        let current = WebPageProgram(sourceID: "current-fixture", functionSource: """
            function(command,native){ currentCalls++; return {action:command.action,current:true}; }
            """)
        let wrapped = try LegacyWebObservationProgram.wrapping(current)
        XCTAssertEqual(wrapped.sourceID, "current-fixture")
        context.evaluateScript("""
            var currentCalls=0, drains=0, samples=0;
            var native={applicationID:'com.google.Chrome',sessionID:'fixture:1',windowID:'17',tabID:'19'};
            var target={...native,adapterID:'chatgpt-web',surface:'webChat',documentID:'document',composerID:'composer',draftGeneration:'original'};
            var identity={operationID:'11111111-1111-4111-8111-111111111111',assetID:'22222222-2222-4222-8222-222222222222',
                attempt:1,assetSHA256:'a'.repeat(64),target};
            var command={action:'observe',target,identity};
            var wrapped=(\(wrapped.functionSource));
            function originalState(){return {target,operations:new Map(),next:null,
                drain(){drains++},sample(){samples++},observationIdentityValid(){return true}};}
            """)
        XCTAssertNil(context.exception)
        return context
    }

    func testInputActionsNeverReadLegacyRegistries() throws {
        let context = try context()
        context.evaluateScript("""
            for(const version of ['v6','v7','v8','v9','v10','v11','v12']) Object.defineProperty(globalThis,'__riftletWebAcceptance20261027'+version,
                {get(){throw Error('legacy registry must not be read for input')}});
            """)
        for action in ["captureTarget", "validate", "begin", "chunk", "commit", "discard"] {
            let reply = context.evaluateScript("wrapped({action:'\(action)'},native)")
            XCTAssertNil(context.exception)
            XCTAssertEqual(reply?.forProperty("action")?.toString(), action)
            XCTAssertEqual(reply?.forProperty("current")?.toBool(), true)
        }
        XCTAssertEqual(context.evaluateScript("currentCalls")?.toInt32(), 6)
    }

    func testMissingRegistryDelegatesOnlyOnceAndInstallsNothing() throws {
        let context = try context()
        XCTAssertEqual(context.evaluateScript("wrapped(command,native).current")?.toBool(), true)
        XCTAssertNil(context.exception)
        XCTAssertEqual(context.evaluateScript("currentCalls")?.toInt32(), 1)
        XCTAssertEqual(context.evaluateScript("Object.keys(globalThis).some(k=>k.startsWith('__riftletWebAcceptance'))")?.toBool(), false)
    }

    func testMissingOrMismatchedOriginalOperationReturnsDecodableUnknownWithoutFallback() throws {
        for version in ["v6", "v7", "v8", "v9", "v10", "v11", "v12"] {
            let context = try context()
            context.evaluateScript("var state=originalState();globalThis.__riftletWebAcceptance20261027\(version)={head:state};")
            for seed in ["", "state.operations.set(identity.operationID,{identity:{...identity,attempt:2},committed:true,inputCount:1});"] {
                context.evaluateScript(seed)
                let raw = try XCTUnwrap(context.evaluateScript("JSON.stringify(wrapped(command,native))")?.toString())
                let envelope = try ObservationDecoder.decode(Data(raw.utf8))
                XCTAssertEqual(envelope.provenance.evidenceID, "\(["v8", "v9", "v10", "v11", "v12"].contains(version) ? "W5" : "W4")-legacy-\(version)-original-observer")
                XCTAssertEqual(envelope.schemaVersion, 1)
                XCTAssertEqual(envelope.observation.state, .invalidated)
                XCTAssertFalse(envelope.observation.belongsToOriginalDraft)
                XCTAssertFalse(envelope.observation.exactImageIdentity)
                XCTAssertEqual(context.evaluateScript("currentCalls+drains+samples")?.toInt32(), 0)
            }
        }
    }

    func testBrokenOldClosureCannotPublishPartialSuccessOrPrivateError() throws {
        let context = try context()
        context.evaluateScript("""
            var state=originalState();globalThis.__riftletWebAcceptance20261027v7={head:state};
            state.operations.set(identity.operationID,{identity,committed:true,inputCount:1});
            state.sample=()=>{throw Error('private page detail')};
            """)
        let raw = try XCTUnwrap(context.evaluateScript("JSON.stringify(wrapped(command,native))")?.toString())
        let envelope = try ObservationDecoder.decode(Data(raw.utf8))
        XCTAssertFalse(raw.contains("private page detail"))
        XCTAssertFalse(envelope.observation.belongsToOriginalDraft)
        XCTAssertFalse(envelope.observation.exactImageIdentity)
        XCTAssertEqual(context.evaluateScript("currentCalls")?.toInt32(), 0)
        XCTAssertNil(context.exception)
    }

    func testV8UploadingOperationStaysSchemaOneWithoutStartEvidenceOrCurrentFallback() throws {
        let context = try context()
        context.evaluateScript("""
            var state=originalState();globalThis.__riftletWebAcceptance20261027v8={head:state};
            state.operations.set(identity.operationID,{identity,committed:true,inputCount:1,
                invalid:false,error:false,uploading:true,uploadStarted:true,
                uploadStartEvidence:{version:1,inputCount:1}});
            """)
        let raw = try XCTUnwrap(context.evaluateScript("JSON.stringify(wrapped(command,native))")?.toString())
        let envelope = try ObservationDecoder.decode(Data(raw.utf8))
        XCTAssertEqual(envelope.schemaVersion, 1)
        XCTAssertEqual(envelope.provenance.evidenceID, "W5-legacy-v8-original-observer")
        XCTAssertEqual(envelope.observation.state, .inputTriggered)
        XCTAssertTrue(envelope.observation.isUploading)
        XCTAssertFalse(envelope.observation.exactImageIdentity)
        XCTAssertFalse(raw.contains("uploadStart"))
        XCTAssertEqual(context.evaluateScript("currentCalls")?.toInt32(), 0)
        XCTAssertEqual(context.evaluateScript("drains")?.toInt32(), 1)
        XCTAssertEqual(context.evaluateScript("samples")?.toInt32(), 1)
        XCTAssertNil(context.exception)
    }

    func testV9UploadingOperationStaysSchemaOneWithoutStartEvidenceOrCurrentFallback() throws {
        let context = try context()
        context.evaluateScript("""
            var state=originalState();globalThis.__riftletWebAcceptance20261027v9={head:state};
            state.operations.set(identity.operationID,{identity,committed:true,inputCount:1,
                invalid:false,error:false,uploading:true,uploadStarted:true,
                uploadStart:{version:1,signal:'correlatedProgress',inputCount:1,previousProgress:20,currentProgress:40}});
            """)
        let raw = try XCTUnwrap(context.evaluateScript("JSON.stringify(wrapped(command,native))")?.toString())
        let envelope = try ObservationDecoder.decode(Data(raw.utf8))
        XCTAssertEqual(envelope.schemaVersion, 1)
        XCTAssertEqual(envelope.provenance.evidenceID, "W5-legacy-v9-original-observer")
        XCTAssertEqual(envelope.observation.state, .inputTriggered)
        XCTAssertTrue(envelope.observation.isUploading)
        XCTAssertFalse(envelope.observation.exactImageIdentity)
        XCTAssertFalse(raw.contains("uploadStart"))
        XCTAssertEqual(context.evaluateScript("currentCalls")?.toInt32(), 0)
        XCTAssertEqual(context.evaluateScript("drains")?.toInt32(), 1)
        XCTAssertEqual(context.evaluateScript("samples")?.toInt32(), 1)
        XCTAssertNil(context.exception)
    }

    func testV10UploadingOperationStaysSchemaOneWithoutStartEvidenceOrCurrentFallback() throws {
        let context = try context()
        context.evaluateScript("""
            var state=originalState();globalThis.__riftletWebAcceptance20261027v10={head:state};
            state.operations.set(identity.operationID,{identity,committed:true,inputCount:1,
                invalid:false,error:false,uploading:true,uploadStarted:true,
                uploadStart:{version:1,signal:'correlatedProgress',inputCount:1,previousProgress:20,currentProgress:40}});
            """)
        let raw = try XCTUnwrap(context.evaluateScript("JSON.stringify(wrapped(command,native))")?.toString())
        let envelope = try ObservationDecoder.decode(Data(raw.utf8))
        XCTAssertEqual(envelope.schemaVersion, 1)
        XCTAssertEqual(envelope.provenance.evidenceID, "W5-legacy-v10-original-observer")
        XCTAssertEqual(envelope.observation.state, .inputTriggered)
        XCTAssertTrue(envelope.observation.isUploading)
        XCTAssertFalse(envelope.observation.exactImageIdentity)
        XCTAssertFalse(raw.contains("uploadStart"))
        XCTAssertEqual(context.evaluateScript("currentCalls")?.toInt32(), 0)
        XCTAssertEqual(context.evaluateScript("drains")?.toInt32(), 1)
        XCTAssertEqual(context.evaluateScript("samples")?.toInt32(), 1)
        XCTAssertNil(context.exception)
    }

    func testV11UploadingOperationStaysSchemaOneWithoutStartEvidenceOrCurrentFallback() throws {
        let context = try context()
        context.evaluateScript("""
            var state=originalState();globalThis.__riftletWebAcceptance20261027v11={head:state};
            state.operations.set(identity.operationID,{identity,committed:true,inputCount:1,
                invalid:false,error:false,uploading:true,uploadStarted:true,
                uploadStart:{version:1,signal:'correlatedProgress',inputCount:1,previousProgress:20,currentProgress:40}});
            """)
        let raw = try XCTUnwrap(context.evaluateScript("JSON.stringify(wrapped(command,native))")?.toString())
        let envelope = try ObservationDecoder.decode(Data(raw.utf8))
        XCTAssertEqual(envelope.schemaVersion, 1)
        XCTAssertEqual(envelope.provenance.evidenceID, "W5-legacy-v11-original-observer")
        XCTAssertEqual(envelope.observation.state, .inputTriggered)
        XCTAssertTrue(envelope.observation.isUploading)
        XCTAssertFalse(envelope.observation.exactImageIdentity)
        XCTAssertFalse(raw.contains("uploadStart"))
        XCTAssertEqual(context.evaluateScript("currentCalls")?.toInt32(), 0)
        XCTAssertEqual(context.evaluateScript("drains")?.toInt32(), 1)
        XCTAssertEqual(context.evaluateScript("samples")?.toInt32(), 1)
        XCTAssertNil(context.exception)
    }

    func testWrappingPreservesCurrentCodeOwnedChunkLimit() throws {
        for limit in [64 * 1024, 256 * 1024] {
            let current = WebPageProgram(sourceID: "current-fixture", functionSource: "function(){return null;}",
                                         maximumChunkBytes: limit)
            let wrapped = try LegacyWebObservationProgram.wrapping(current)
            XCTAssertEqual(wrapped.maximumChunkBytes, limit)
            XCTAssertEqual(wrapped.sourceID, current.sourceID)
        }
    }

    func testCombinedSourceRetainsTransportBound() throws {
        XCTAssertThrowsError(try LegacyWebObservationProgram.wrapping(
            WebPageProgram(sourceID: "oversized", functionSource: String(repeating: " ", count: 128 * 1024)))) {
            XCTAssertEqual($0 as? WebAdapterError, .programUnavailable)
        }
        XCTAssertThrowsError(try LegacyWebObservationProgram.wrapping(WebPageProgram(sourceID: "empty", functionSource: "")))
    }
}
