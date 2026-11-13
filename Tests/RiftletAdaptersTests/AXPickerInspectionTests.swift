import ApplicationServices
import XCTest
@testable import RiftletAdapters

final class AXPickerInspectionTests: XCTestCase {
    @MainActor func testBoundWindowAndSheetRequireOriginalDraftAtBothReads() throws {
        let driver = PickerDriver()
        let inspection = driver.binding
        XCTAssertEqual(try inspection.attachedSheet { true }, driver.sheet)
        var validations = 0
        XCTAssertNil(try inspection.attachedSheet { validations += 1; return validations == 1 })
        XCTAssertEqual(validations, 2)
        driver.duplicates = true
        XCTAssertNil(try inspection.attachedSheet { true })
        XCTAssertEqual(driver.presses, 0)
    }

    @MainActor func testOneShotFileSelectionDoesNotSubmitAfterTargetSwitchOrLostReply() throws {
        let driver = PickerDriver()
        func run(throwAfterChoice: Bool) throws {
            driver.elsewhere = false
            driver.onPress = { node in
                if node == driver.choice {
                    if throwAfterChoice { throw NativeMacAXError.accessibility(-25204) }
                    driver.elsewhere = true
                }
            }
            let handoff = AXPickerFileHandoff(binding: driver.binding, choice: driver.choice, submit: driver.submit)
            let input = AXPickerFileHandoff.Input(matchesDraft: { true }, matchesChoice: { _ in true })
            XCTAssertEqual(try handoff.handOff(input), throwAfterChoice ? .uncertain : .refused)
            XCTAssertEqual(try handoff.handOff(input), .refused)
        }
        try run(throwAfterChoice: false)
        try run(throwAfterChoice: true)
        XCTAssertEqual(driver.presses, 2)
        XCTAssertEqual(driver.pressed, [driver.choice, driver.choice])
    }

    @MainActor func testBoundFileAndSubmitPressOnceAndOnlyWhenSelectionIsObserved() throws {
        let driver = PickerDriver()
        let input = AXPickerFileHandoff.Input(matchesDraft: { true }, matchesChoice: { stage in
            stage == .beforeSelection || driver.pressed.last == driver.choice
        })
        let handoff = AXPickerFileHandoff(binding: driver.binding, choice: driver.choice, submit: driver.submit)
        XCTAssertEqual(try handoff.handOff(input), .submitted)
        XCTAssertEqual(try handoff.handOff(input), .refused)
        XCTAssertEqual(driver.pressed, [driver.choice, driver.submit])
        let second = AXPickerFileHandoff(binding: driver.binding, choice: driver.choice, submit: driver.submit)
        XCTAssertEqual(try second.handOff(.init(matchesDraft: { true }, matchesChoice: { $0 == .beforeSelection })), .refused)
        XCTAssertEqual(driver.pressed, [driver.choice, driver.submit, driver.choice])
    }

    @MainActor func testDisabledConfirmWithoutPressActionWaitsForOriginalSelectionPublication() throws {
        let driver = PickerDriver()
        driver.confirmEnabled = false
        var selectionQueued = false
        driver.onPress = { control in
            if control == driver.choice { selectionQueued = true }
            else { XCTAssertTrue(driver.confirmEnabled) }
        }
        let handoff = AXPickerFileHandoff(binding: driver.binding, choice: driver.choice, submit: driver.submit)
        var input = AXPickerFileHandoff.Input(matchesDraft: { true }, matchesChoice: { stage in
            stage == .beforeSelection || selectionQueued && driver.confirmEnabled
        })
        input.selectionSettled = {
            // Model the next receiver event, after the selection AXPress has returned.
            XCTAssertTrue(selectionQueued)
            XCTAssertFalse(driver.confirmEnabled)
            XCTAssertEqual(driver.pressed, [driver.choice])
            driver.confirmEnabled = true
            return true
        }
        XCTAssertEqual(try handoff.handOff(input), .submitted)
        XCTAssertEqual(driver.pressed, [driver.choice, driver.submit])
        XCTAssertEqual(try handoff.handOff(input), .refused)
        driver.confirmEnabled = false
        let lost = AXPickerFileHandoff(binding: driver.binding, choice: driver.choice, submit: driver.submit)
        input.selectionSettled = { false }
        XCTAssertEqual(try lost.handOff(input), .refused)
        XCTAssertEqual(lost.refusal, .settlement)
        XCTAssertEqual(driver.pressed, [driver.choice, driver.submit, driver.choice])
    }

    @MainActor func testRejectsOtherWindowProcessReplacementAndUnownedPanelService() throws {
        let driver = PickerDriver()
        let inspection = driver.binding
        driver.elsewhere = true
        XCTAssertNil(try inspection.attachedSheet { true })
        driver.elsewhere = false
        driver.foreignSheet = true
        XCTAssertNil(try inspection.attachedSheet { true })
        driver.foreignSheet = false
        driver.generation = 2
        XCTAssertNil(try inspection.attachedSheet { true })
        driver.generation = 1
        driver.trusted = false
        XCTAssertNil(try inspection.attachedSheet { true })
        XCTAssertEqual(driver.presses, 0)
    }
}

@MainActor
private final class PickerDriver: MacAXDriver {
    // Opaque local handles. The fake never messages these PIDs or actual apps.
    let app = MacAXElement(AXUIElementCreateApplication(700001))
    let window = MacAXElement(AXUIElementCreateApplication(700002))
    let editor = MacAXElement(AXUIElementCreateApplication(700003))
    let entry = MacAXElement(AXUIElementCreateApplication(700004))
    let sheet = MacAXElement(AXUIElementCreateApplication(700005))
    let other = MacAXElement(AXUIElementCreateApplication(700006))
    var duplicates = false
    var elsewhere = false
    var foreignSheet = false
    var generation: TimeInterval = 1
    var trusted = true
    var confirmEnabled = true
    let choice = MacAXElement(AXUIElementCreateApplication(700007))
    let submit = MacAXElement(AXUIElementCreateApplication(700008))
    var presses = 0
    var pressed: [MacAXElement] = []
    var onPress: ((MacAXElement) throws -> Void)?

    var identity: MacAXApplicationIdentity {
        .init(processID: 1000, launchedAt: Date(timeIntervalSince1970: generation),
              bundleID: "org.riftlet.fixture", version: "1", build: "1")
    }
    var binding: AXPickerInspection { .init(driver: self, process: identity, window: window, editor: editor, entry: entry) }
    func isTrusted() -> Bool { trusted }
    func frontmostApplication() -> MacAXApplicationIdentity? { identity }
    func applicationIdentity(processID: Int32) -> MacAXApplicationIdentity? { identity }
    func applicationElement(processID: Int32) -> MacAXElement { app }
    func processID(of element: MacAXElement) -> Int32 { element == sheet && foreignSheet ? 2000 : identity.processID }
    func elementAttribute(_ attribute: String, of element: MacAXElement) -> MacAXElement? {
        if element == app && attribute == kAXFocusedWindowAttribute { return elsewhere ? other : window }
        if element == sheet && attribute == kAXParentAttribute { return window }
        if [editor, entry, sheet, choice, submit].contains(element) && attribute == kAXWindowAttribute { return window }
        return nil
    }
    func stringAttribute(_ attribute: String, of element: MacAXElement) -> String? {
        guard attribute == kAXRoleAttribute else { return nil }
        if element == window { return kAXWindowRole }
        if element == entry || element == submit { return kAXButtonRole }
        if element == choice { return kAXRadioButtonRole }
        if [sheet, other].contains(element) { return kAXSheetRole }
        return nil
    }
    func boolAttribute(_ attribute: String, of element: MacAXElement) -> Bool? {
        if element == submit && attribute == kAXEnabledAttribute { return confirmEnabled }
        if element == choice && attribute == kAXEnabledAttribute { return true }
        return element == window && attribute == kAXMinimizedAttribute ? false : nil
    }
    func elementsAttribute(_ attribute: String, of element: MacAXElement, maximumCount: Int) -> [MacAXElement] {
        if element == app && attribute == kAXWindowsAttribute { return [window, other] }
        if element == window && attribute == kAXChildrenAttribute { return duplicates ? [sheet, other] : [sheet] }
        return []
    }
    func actionNames(of element: MacAXElement) -> [String] {
        if element == submit && !confirmEnabled { return [] }
        return [entry, choice, submit].contains(element) ? [kAXPressAction] : []
    }
    func press(_ element: MacAXElement) throws { presses += 1; pressed.append(element); try onPress?(element) }
}
