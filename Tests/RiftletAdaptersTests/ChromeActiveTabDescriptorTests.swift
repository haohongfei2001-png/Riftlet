import Carbon
import Foundation
import JavaScriptCore
import XCTest
@testable import RiftletAdapters

final class ChromeActiveTabDescriptorTests: XCTestCase {
    func testBothBrowserTransportsRequireSystemConsentWithoutPrompting() {
        let consent = UInt(kAEDoNotPromptForUserConsent)
        XCTAssertNotEqual(UInt(ChromeClickSnapshot.queuedMode) & consent, 0)
        XCTAssertTrue(ChromeClickSnapshot.waitOptions.contains(.init(rawValue: consent)))
        XCTAssertTrue(ChromeClickSnapshot.waitOptions.contains(.neverInteract))
        XCTAssertNotEqual(ChromeClickSnapshot.queuedMode & AESendMode(kAENeverInteract), 0)
    }

    func testClickIdentityFallbackAndURLShareTheMouseDownDeadline() throws {
        let deadline = ChromeClickDeadline(start: 10)
        XCTAssertEqual(try deadline.timeout(at: 10), 0.15, accuracy: 0.000_001)
        XCTAssertEqual(try deadline.timeout(at: 10.100), 0.05, accuracy: 0.000_001)
        XCTAssertThrowsError(try deadline.timeout(at: 10.149))
        XCTAssertNoThrow(try deadline.checkReturn(at: 10.149))
        XCTAssertThrowsError(try deadline.checkReturn(at: 10.151))
    }

    func testPinRepliesCanArriveLateWithoutExtendingTheOriginalClick() throws {
        let capture = ChromeClickDeadline(start: 10, wallTime: 1000)
        XCTAssertThrowsError(try capture.checkReturn(at: 10.151))
        XCTAssertNoThrow(try capture.confirmation.checkReturn(at: 10.8))
        XCTAssertThrowsError(try capture.confirmation.checkReturn(at: 11.001))
        XCTAssertEqual(capture.guardExecution(of: "'bound'"), capture.confirmation.guardExecution(of: "'bound'"))
    }

    func testQueuedPinCanOnlyBindAnAlreadyOpenVisibleDocumentWithinTheClickWindow() throws {
        let context = try XCTUnwrap(JSContext())
        context.evaluateScript("""
            var wall=1000050, calls=0; Date.now=()=>wall;
            var performance={timeOrigin: 900000, now: ()=>wall-performance.timeOrigin};
            var document={visibilityState:'visible',hasFocus:()=>true};
            """)
        let deadline = ChromeClickDeadline(start: 10, wallTime: 1000)
        let bind = deadline.guardExecution(of: "(++calls, 'bound')")
        XCTAssertEqual(context.evaluateScript(bind)?.toString(), "bound")
        context.evaluateScript("wall=1000200")
        XCTAssertEqual(context.evaluateScript(bind)?.toString(), "expired")
        context.evaluateScript("wall=1000050; performance.timeOrigin=1000020")
        XCTAssertEqual(context.evaluateScript(bind)?.toString(), "expired")
        context.evaluateScript("performance.timeOrigin=900000; document.visibilityState='hidden'")
        XCTAssertEqual(context.evaluateScript(bind)?.toString(), "refused")
        XCTAssertEqual(context.evaluateScript("calls")?.toInt32(), 1)
        context.evaluateScript("document.visibilityState='visible'")
        XCTAssertEqual(context.evaluateScript(deadline.guardExecution(of: "(globalThis.wall=1000200, 'bound')"))?.toString(), "expired")
    }

    func testAnOldBrowserTimeOriginCannotExtendTheClickAndClockStepsInvalidateTheReply() throws {
        let deadline = ChromeClickDeadline(start: 10, wallTime: 1000)
        XCTAssertNoThrow(try deadline.confirmation.checkClockAgreement(at: 10.2, wallTime: 1000.2))
        XCTAssertThrowsError(try deadline.confirmation.checkClockAgreement(at: 10.2, wallTime: 1000.0))
        XCTAssertThrowsError(try deadline.confirmation.checkClockAgreement(at: 10.2, wallTime: 1000.4))
        let context = try XCTUnwrap(JSContext())
        context.evaluateScript("""
            var wall=1000040, calls=0, age=9840; Date.now=()=>wall;
            var performance={timeOrigin:990000,now:()=>age};
            var document={visibilityState:'visible',hasFocus:()=>true};
            """)
        let request = deadline.guardExecution(of: "(++calls, 'bound')")
        XCTAssertEqual(context.evaluateScript(request)?.toString(), "bound")
        context.evaluateScript("wall=1000240; age+=200")
        XCTAssertEqual(context.evaluateScript(request)?.toString(), "expired")
        XCTAssertEqual(context.evaluateScript("calls")?.toInt32(), 1)
    }

    func testConcurrentTabPropertiesCannotSupplyAnotherTabsURL() throws {
        let record = NSAppleEventDescriptor.record()
        record.setDescriptor(.init(typeCode: code("CrTb")), forKeyword: code("pcls"))
        record.setDescriptor(.init(string: "9"), forKeyword: code("ID  "))
        record.setDescriptor(.init(string: "https://chatgpt.com/c/test"), forKeyword: code("URL "))
        XCTAssertEqual(try ChromeActiveTabDescriptor.matchedURL(properties: record, tab: "9"), "https://chatgpt.com/c/test")
        XCTAssertThrowsError(try ChromeActiveTabDescriptor.matchedURL(properties: record, tab: "8"))
        XCTAssertNil(try ChromeActiveTabDescriptor.matchedURL(properties: .list(), tab: "9"))
        XCTAssertNil(try ChromeActiveTabDescriptor.matchedURL(properties: nil, tab: "9"))
    }

    @MainActor func testBraveReadsOnlyTheFrozenTabWhenOptionalPropertiesAreMissing() throws {
        let original = try tab(id: "9")
        var reads = 0
        func read(_ captured: NSAppleEventDescriptor) -> String {
            XCTAssertTrue(captured === original)
            reads += 1
            return "https://example.test/fixture"
        }
        let route = try BraveBrowserHost.frozenRoute(.init(activeTab: original, properties: nil), originalURL: read)
        XCTAssertEqual(route.tab, "9")
        XCTAssertEqual(route.url.absoluteString, "https://example.test/fixture")
        XCTAssertEqual(reads, 1)

        let properties = NSAppleEventDescriptor.record()
        properties.setDescriptor(.init(typeCode: code("CrTb")), forKeyword: code("pcls"))
        properties.setDescriptor(.init(string: "9"), forKeyword: code("ID  "))
        properties.setDescriptor(.init(string: "https://example.test/from-properties"), forKeyword: code("URL "))
        let provided = try BraveBrowserHost.frozenRoute(.init(activeTab: original, properties: properties), originalURL: read)
        XCTAssertEqual(provided.url.path, "/from-properties")
        properties.setDescriptor(.init(string: "8"), forKeyword: code("ID  "))
        XCTAssertThrowsError(try BraveBrowserHost.frozenRoute(.init(activeTab: original, properties: properties), originalURL: read))
        XCTAssertThrowsError(try BraveBrowserHost.frozenRoute(.init(activeTab: original, properties: .list()), originalURL: read))
        XCTAssertThrowsError(try BraveBrowserHost.frozenRoute(.init(activeTab: .null(), properties: nil), originalURL: read))
        XCTAssertEqual(reads, 1)
    }

    func testQueuedRepliesShareRemainingClickTime() throws {
        let deadline = ChromeClickDeadline(start: 10)
        XCTAssertTrue((49...50).contains(try deadline.receiveMilliseconds(at: 10.100)))
        XCTAssertThrowsError(try deadline.receiveMilliseconds(at: 10.150))
    }

    private func code(_ text: String) -> UInt32 { text.utf8.reduce(0) { ($0 << 8) | UInt32($1) } }

    private func object(_ kind: String, form: String = "ID  ", key: NSAppleEventDescriptor,
                        container: NSAppleEventDescriptor = .null(), omit: String? = nil,
                        extra: Bool = false, wantAsEnum: Bool = false, formAsType: Bool = false,
                        recordOnly: Bool = false) throws -> NSAppleEventDescriptor {
        let record = NSAppleEventDescriptor.record()
        if omit != "want" { record.setDescriptor(wantAsEnum ? .init(enumCode: code(kind)) : .init(typeCode: code(kind)), forKeyword: code("want")) }
        if omit != "form" { record.setDescriptor(formAsType ? .init(typeCode: code(form)) : .init(enumCode: code(form)), forKeyword: code("form")) }
        if omit != "seld" { record.setDescriptor(key, forKeyword: code("seld")) }
        if omit != "from" { record.setDescriptor(container, forKeyword: code("from")) }
        if extra { record.setDescriptor(.init(string: "unexpected"), forKeyword: code("junk")) }
        return recordOnly ? record : try XCTUnwrap(record.coerce(toDescriptorType: code("obj ")))
    }

    private func tab(window: NSAppleEventDescriptor? = nil, id: String = "557755598") throws -> NSAppleEventDescriptor {
        let container = try window ?? object("cwin", key: .init(string: "557755597"))
        return try object("CrTb", key: .init(string: id), container: container)
    }

    func testObservedAbsoluteUnicodeIDChainReturnsBothIDsWithoutCoercion() throws {
        let result = try XCTUnwrap(ChromeActiveTabDescriptor.identity(in: tab()))
        XCTAssertEqual(result.window, "557755597"); XCTAssertEqual(result.tab, "557755598")
        let largest = try tab(window: object("cwin", key: .init(string: String(Int64.max))), id: "1")
        let boundary = try XCTUnwrap(ChromeActiveTabDescriptor.identity(in: largest))
        XCTAssertEqual(boundary.window, String(Int64.max)); XCTAssertEqual(boundary.tab, "1")
    }

    func testRelativeSelectorsAndNumericDescriptorsAreNotTreatedAsFixedIDs() throws {
        let window = try object("cwin", key: .init(string: "123"))
        for form in ["indx", "name", "rang", "rele"] {
            XCTAssertNil(ChromeActiveTabDescriptor.identity(in: try object("CrTb", form: form, key: .init(string: "1"), container: window)))
            XCTAssertNil(ChromeActiveTabDescriptor.identity(in: try tab(window: object("cwin", form: form, key: .init(string: "1")))))
        }
        XCTAssertNil(ChromeActiveTabDescriptor.identity(in: try object("CrTb", key: .init(int32: 123), container: window)))
        XCTAssertNil(ChromeActiveTabDescriptor.identity(in: try tab(window: object("cwin", key: .init(int32: 123)))))
    }

    func testNoncanonicalZeroNegativeOverflowAndUnicodeIDsRefuseOnEitherLevel() throws {
        for text in ["", "0", "-1", "+1", "01", " 1", "1 ", "1\n", "1.0", "1e2", "１２", "9223372036854775808"] {
            XCTAssertNil(ChromeActiveTabDescriptor.identity(in: try tab(id: text)), text)
            XCTAssertNil(ChromeActiveTabDescriptor.identity(in: try tab(window: object("cwin", key: .init(string: text)))), text)
        }
    }

    func testWrongObjectKindsOrDescriptorTypesRefuse() throws {
        let window = try object("cwin", key: .init(string: "123"))
        XCTAssertNil(ChromeActiveTabDescriptor.identity(in: try object("cwin", key: .init(string: "456"), container: window)))
        XCTAssertNil(ChromeActiveTabDescriptor.identity(in: try tab(window: object("CrTb", key: .init(string: "123")))))
        XCTAssertNil(ChromeActiveTabDescriptor.identity(in: try object("CrTb", key: .init(string: "456"), container: window, recordOnly: true)))
        XCTAssertNil(ChromeActiveTabDescriptor.identity(in: .null()))
        XCTAssertNil(ChromeActiveTabDescriptor.identity(in: .list()))
        for wantedEnum in [true, false] {
            XCTAssertNil(ChromeActiveTabDescriptor.identity(in: try object("CrTb", key: .init(string: "456"), container: window,
                wantAsEnum: wantedEnum, formAsType: !wantedEnum)))
        }
    }

    func testMissingOrExtraFieldsAndNonNullNestedContainerRefuse() throws {
        for missing in ["want", "form", "seld", "from"] {
            let window = try object("cwin", key: .init(string: "123"))
            XCTAssertNil(ChromeActiveTabDescriptor.identity(in: try object("CrTb", key: .init(string: "456"), container: window, omit: missing)))
            XCTAssertNil(ChromeActiveTabDescriptor.identity(in: try tab(window: object("cwin", key: .init(string: "123"), omit: missing))))
        }
        let window = try object("cwin", key: .init(string: "123"))
        XCTAssertNil(ChromeActiveTabDescriptor.identity(in: try object("CrTb", key: .init(string: "456"), container: window, extra: true)))
        XCTAssertNil(ChromeActiveTabDescriptor.identity(in: try tab(window: object("cwin", key: .init(string: "123"), extra: true))))
        XCTAssertNil(ChromeActiveTabDescriptor.identity(in: try tab(window: object("cwin", key: .init(string: "123"), container: window))))
    }
}
