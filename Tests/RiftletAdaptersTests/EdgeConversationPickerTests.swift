import AppKit
import CryptoKit
import XCTest
@testable import RiftletAdapters

final class EdgeConversationPickerTests: XCTestCase {
    private struct Draft: Equatable {
        var document = UUID()
        var editor = UUID()
        var text = "Neutral existing draft."
        var selection = NSRange(location: 1, length: 4)
        var prior = [UUID()]
    }

    @MainActor private final class Fixture {
        let driver = PickerDriver()
        let id = UUID()
        let root: URL
        var open = false
        var selected: URL?
        var draft = Draft()
        var discoverWhileOpen: (() throws -> Void)?
        var afterSelection: (() throws -> Void)?
        var onSubmit: (() throws -> Void)?

        init() throws {
            root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
            driver.bundleID = "org.riftlet.axpicker." + id.uuidString
            driver.foreignSheet = true
            driver.onPress = { [unowned self] node in
                if node == driver.entry { open = true }
                if node == driver.submit { try onSubmit?(); open = false }
            }
        }

        func add(_ name: String, pixel: UInt8) throws -> URL {
            // Two tiny, fully encoded PNGs created without any screenshot data.
            let space = CGColorSpaceCreateDeviceRGB()
            let alpha = CGImageAlphaInfo.noneSkipLast.rawValue
            let context = try XCTUnwrap(CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8,
                                                  bytesPerRow: 4, space: space, bitmapInfo: alpha))
            context.setFillColor(red: CGFloat(pixel) / 255, green: 0, blue: 0, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
            let image = NSBitmapImageRep(cgImage: try XCTUnwrap(context.makeImage()))
            let data = try XCTUnwrap(image.representation(using: .png, properties: [:]))
            let file = root.appendingPathComponent(name)
            try data.write(to: file, options: .withoutOverwriting)
            return file
        }

        func freeze(_ url: URL) throws -> EdgeConversationPicker {
            let original = draft, bytes = try Data(contentsOf: url)
            let hash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
            return try EdgeConversationPicker.controlled(fixtureID: id, binding: driver.binding,
                originalDraft: { [unowned self] in draft == original }, directory: root, file: url,
                bytes: Int64(bytes.count), sha256: hash)
        }

        func input(expected: URL) -> EdgeConversationPicker.Input {
            .init(chooserIsAbsent: { !self.open }, findOpenedControls: { url in
                guard self.open, expected == url else { return nil }
                try self.discoverWhileOpen?()
                return .fileList(EdgeConversationPicker.Controls(choice: self.driver.choice, submit: self.driver.submit,
                    matchesFile: { stage in
                        guard self.open, url == expected else { return false }
                        return stage == .beforeSelection || self.selected == expected
                    }, selectionSettled: {
                        self.selected = url
                        try self.afterSelection?()
                        return true
                    }))
            })
        }
        func clean() { try? FileManager.default.removeItem(at: root) }
    }

    @MainActor func testTwoOriginalPNGClicksRemainIndependentAfterAmbiguousSubmit() throws {
        let f = try Fixture(); defer { f.clean() }
        let first = try f.add("one.png", pixel: 20), second = try f.add("two.png", pixel: 220)
        let a = try f.freeze(first), b = try f.freeze(second)
        f.onSubmit = { throw NativeMacAXError.accessibility(-25204) }
        XCTAssertEqual(try a.handOff(f.input(expected: first)), .uncertain)
        XCTAssertEqual(try a.handOff(f.input(expected: first)), .alreadyAttempted)
        // The fixture's original native list closed on its own despite the lost reply.
        f.open = false; f.onSubmit = nil; f.selected = nil
        XCTAssertEqual(try b.handOff(f.input(expected: second)), .inputAttempted)
        XCTAssertEqual(try b.handOff(f.input(expected: second)), .alreadyAttempted)
        XCTAssertEqual(f.driver.pressed, [f.driver.entry, f.driver.choice, f.driver.submit,
                                           f.driver.entry, f.driver.choice, f.driver.submit])
    }

    @MainActor func testEachDraftReplacementBetweenEntryAndSelectionStopsFileInput() throws {
        let mutations: [(inout Draft) -> Void] = [
            { $0.document = UUID() }, { $0.editor = UUID() }, { $0.text += "changed" },
            { $0.selection.length = 0 }, { $0.prior.append(UUID()) }
        ]
        for mutate in mutations {
            let f = try Fixture(); defer { f.clean() }
            let file = try f.add("one.png", pixel: 10)
            let picker = try f.freeze(file)
            f.discoverWhileOpen = { mutate(&f.draft) }
            XCTAssertEqual(try picker.handOff(f.input(expected: file)), .entryAttempted)
            XCTAssertEqual(f.driver.pressed, [f.driver.entry])
            XCTAssertEqual(try picker.handOff(f.input(expected: file)), .alreadyAttempted)
        }
    }

    @MainActor func testSelectionChangeAfterFileRowPressRefusesTheOriginalSubmit() throws {
        let f = try Fixture(); defer { f.clean() }
        let file = try f.add("one.png", pixel: 10), picker = try f.freeze(file)
        f.afterSelection = { f.draft.selection = NSRange(location: 2, length: 0) }
        XCTAssertEqual(try picker.handOff(f.input(expected: file)), .entryAttempted)
        XCTAssertEqual(f.driver.pressed, [f.driver.entry, f.driver.choice])
        XCTAssertEqual(try picker.handOff(f.input(expected: file)), .alreadyAttempted)
    }

    @MainActor func testRestartPriorChooserAndWrongApplicationRefuseWithoutPress() throws {
        let f = try Fixture(); defer { f.clean() }
        let file = try f.add("one.png", pixel: 10)
        let original = try f.freeze(file)
        f.driver.generation += 1
        XCTAssertEqual(try original.handOff(f.input(expected: file)), .refusedBeforeEntry)
        let next = try f.freeze(file)
        f.open = true
        XCTAssertEqual(try next.handOff(f.input(expected: file)), .refusedBeforeEntry)
        f.driver.bundleID = "com.microsoft.edgemac"
        XCTAssertThrowsError(try f.freeze(file))
        XCTAssertTrue(f.driver.pressed.isEmpty)
    }

    @MainActor func testFileIdentityReplacementAndInvalidPNGRefuseBeforeEntry() throws {
        let f = try Fixture(); defer { f.clean() }
        let file = try f.add("one.png", pixel: 10), bytes = try Data(contentsOf: file)
        let task = try f.freeze(file)
        try bytes.write(to: file, options: .atomic)
        XCTAssertThrowsError(try task.handOff(f.input(expected: file)))
        try Data("neutral invalid".utf8).write(to: file)
        XCTAssertThrowsError(try f.freeze(file))
        XCTAssertTrue(f.driver.pressed.isEmpty)
    }
}
