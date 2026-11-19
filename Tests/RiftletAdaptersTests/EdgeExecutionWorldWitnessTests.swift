import JavaScriptCore
import XCTest
@testable import RiftletAdapters

/// Two JavaScriptCore realms with a shared synthetic DOM object. These execute
/// the real witness source, but do not claim Edge's native execute world passed.
final class EdgeExecutionWorldWitnessTests: XCTestCase {
    private func realms() throws -> (JSContext, JSContext) {
        let machine = JSVirtualMachine()
        let main = try XCTUnwrap(JSContext(virtualMachine: machine))
        let isolated = try XCTUnwrap(JSContext(virtualMachine: machine))
        let root = try XCTUnwrap(main.evaluateScript("""
            (()=>{const attributes=new Map();return {
              setAttribute:(key,value)=>attributes.set(key,value),
              getAttribute:key=>attributes.get(key)||null,
              removeAttribute:key=>attributes.delete(key)};})()
            """))
        for realm in [main, isolated] {
            realm.setObject(root, forKeyedSubscript: "sharedRoot" as NSString)
            _ = try evaluate("""
                globalThis.document={documentElement:sharedRoot,visibilityState:'visible',hasFocus:()=>true};
                globalThis.navigation={currentEntry:{id:'original-entry'}};
                globalThis.location={href:'https://chatgpt.com/c/neutral'};
                globalThis.self=globalThis;globalThis.top=globalThis;
                globalThis.setTimeout=()=>0;
                'ready'
                """, in: realm)
        }
        return (main, isolated)
    }
    private func evaluate(_ source: String, in context: JSContext) throws -> String {
        let result = context.evaluateScript(source)
        XCTAssertNil(context.exception)
        return try XCTUnwrap(result?.toString())
    }

    func testActualWitnessScriptRequiresSeparateExecutionRealms() throws {
        let (main, isolated) = try realms(), witness = EdgeExecutionWorldWitness()
        XCTAssertEqual(try evaluate(witness.prepare, in: isolated), "prepared")
        XCTAssertEqual(try evaluate(witness.prepare, in: isolated), "refused")
        _ = try evaluate(witness.bootstrap, in: main)
        XCTAssertEqual(try evaluate(witness.confirm, in: isolated), "verified")
        XCTAssertEqual(try evaluate(witness.validate, in: isolated), "verified")
        let (same, _) = try realms(), sameWorldWitness = EdgeExecutionWorldWitness()
        XCTAssertEqual(try evaluate(sameWorldWitness.prepare, in: same), "prepared")
        _ = try evaluate(sameWorldWitness.bootstrap, in: same)
        XCTAssertEqual(try evaluate(sameWorldWitness.confirm, in: same), "refused")
    }

    func testActualWitnessRejectsReplacementRootAndNavigation() throws {
        for replacement in ["document.documentElement={};", "navigation.currentEntry={id:'replacement-entry'};"] {
            let (main, isolated) = try realms(), witness = EdgeExecutionWorldWitness()
            XCTAssertEqual(try evaluate(witness.prepare, in: isolated), "prepared")
            _ = try evaluate(witness.bootstrap, in: main)
            XCTAssertEqual(try evaluate(witness.confirm, in: isolated), "verified")
            _ = try evaluate(replacement, in: isolated)
            XCTAssertEqual(try evaluate(witness.validate, in: isolated), "refused")
        }
    }

    func testOnlyTheHostInputVersionCanPinItsClick() throws {
        let witness = ChromeClickDocumentWitness()
        let edge = try ChatGPTWebPageProgram.edgeProgram.get()
        let chrome = WebPageProgram(sourceID: ChatGPTWebPageProgram.sourceID, functionSource: "function(){}")
        let old = WebPageProgram(sourceID: ChatGPTWebPageProgram.priorEdgeSource, functionSource: "function(){}")
        let address = "https://chatgpt.com/c/neutral"
        XCTAssertNoThrow(try witness.bindScript(address: address, program: chrome))
        XCTAssertNoThrow(try EdgeExecutionWorldWitness().prepareAndBind(witness, address: address, program: edge))
        XCTAssertThrowsError(try witness.bindScript(address: address, program: edge))
        XCTAssertThrowsError(try EdgeExecutionWorldWitness().prepareAndBind(witness, address: address, program: chrome))
        for host in [ChromeClickDocumentWitness.Host.chrome, .edge] {
            XCTAssertThrowsError(try witness.bindScript(address: address, program: old, host: host))
        }
    }

    func testCombinedScriptPinsOnceAndKeepsTheSeparateWorldRequirement() throws {
        for sameWorld in [false, true] {
            let (main, isolated) = try realms(), world = EdgeExecutionWorldWitness()
            let document = ChromeClickDocumentWitness()
            let program = WebPageProgram(sourceID: ChatGPTWebPageProgram.edgeSourceID, functionSource: """
                function(command){globalThis.pinCalls=(globalThis.pinCalls||0)+1;
                globalThis.pinnedID=command.clickWitnessID;
                return command.action==='pinTarget'&&command.address===location.href?'bound':'refused';}
                """)
            let script = try world.prepareAndBind(document, address: "https://chatgpt.com/c/neutral", program: program)
            XCTAssertEqual(try evaluate(script, in: isolated), "bound")
            XCTAssertEqual(try evaluate("String(pinCalls)", in: isolated), "1")
            XCTAssertEqual(try evaluate("pinnedID", in: isolated), document.id.uuidString)
            XCTAssertEqual(try evaluate(script, in: isolated), "refused")
            XCTAssertEqual(try evaluate("String(pinCalls)", in: isolated), "1")
            _ = try evaluate(world.bootstrap, in: sameWorld ? isolated : main)
            XCTAssertEqual(try evaluate(world.confirm, in: isolated), sameWorld ? "refused" : "verified")
        }
    }

    func testCombinedScriptCannotReplaceARefusedDocumentBindingWithWorldPreparation() throws {
        let (_, isolated) = try realms(), world = EdgeExecutionWorldWitness()
        let program = WebPageProgram(sourceID: ChatGPTWebPageProgram.edgeSourceID,
                                     functionSource: "function(){return 'refused';}")
        XCTAssertEqual(try evaluate(world.prepareAndBind(ChromeClickDocumentWitness(),
            address: "https://chatgpt.com/c/neutral", program: program), in: isolated), "refused")
        XCTAssertEqual(try evaluate(world.validate, in: isolated), "refused")
    }

    func testCombinedPinRefusesAlreadyHiddenOrBlurredOriginalPageBeforeCreatingAnyCapability() throws {
        for state in ["document.visibilityState='hidden';", "document.hasFocus=()=>false;",
                      "delete document.hasFocus;", "document.hasFocus=()=>1;"] {
            let (_, isolated) = try realms(), world = EdgeExecutionWorldWitness()
            let program = WebPageProgram(sourceID: ChatGPTWebPageProgram.edgeSourceID, functionSource:
                "function(){globalThis.pinCalls=(globalThis.pinCalls||0)+1;return 'bound';}")
            _ = try evaluate(state, in: isolated)
            let script = try world.prepareAndBind(ChromeClickDocumentWitness(),
                address: "https://chatgpt.com/c/neutral", program: program)
            XCTAssertEqual(try evaluate(script, in: isolated), "refused")
            XCTAssertEqual(try evaluate("String(globalThis.pinCalls||0)", in: isolated), "0")
            XCTAssertEqual(try evaluate("String(Object.getOwnPropertyNames(globalThis).filter(k=>k.startsWith('__riftletEdgeExecution_')).length)",
                                        in: isolated), "0")
            // Returning to the original tab cannot make the refused capability
            // valid. The production click never repeats prepareAndBind.
            _ = try evaluate("document.visibilityState='visible';document.hasFocus=()=>true;'restored'", in: isolated)
            XCTAssertEqual(try evaluate(world.validate, in: isolated), "refused")
        }
    }

    func testCombinedPinAllowsVisibleFocusedDocumentWithoutEditorKeyboardFocus() throws {
        let (_, isolated) = try realms(), world = EdgeExecutionWorldWitness()
        _ = try evaluate("document.activeElement={id:'ordinary-composer-control'};'ready'", in: isolated)
        let program = WebPageProgram(sourceID: ChatGPTWebPageProgram.edgeSourceID, functionSource:
            "function(){globalThis.pinCalls=(globalThis.pinCalls||0)+1;return 'bound';}")
        XCTAssertEqual(try evaluate(world.prepareAndBind(ChromeClickDocumentWitness(),
            address: "https://chatgpt.com/c/neutral", program: program), in: isolated), "bound")
        XCTAssertEqual(try evaluate("String(pinCalls)", in: isolated), "1")
        XCTAssertEqual(try evaluate("document.activeElement.id", in: isolated), "ordinary-composer-control")
    }
}
