import Foundation
import XCTest
@testable import RiftletAdapters

final class ChromeActiveTabDescriptorTests: XCTestCase {
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
