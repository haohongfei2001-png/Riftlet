import AppKit
import Carbon
import Darwin
import XCTest
@testable import RiftletAdapters

/// Original host code and Apple Event tick handling with injected native reads.
/// No browser, screen input, upload or real timing assertion is involved.
final class EdgeRapidClickFreezeTests: XCTestCase {
    private func birth(second: UInt64 = 10) -> KernelProcessBirth {
        var record = proc_bsdinfo(); record.pbi_pid = 71; record.pbi_start_tvsec = second
        return KernelProcessBirth(requestedPID: 71, record: record,
            bytesRead: Int32(MemoryLayout.size(ofValue: record)))!
    }

    func testClickBracketReadsOnlyOriginalAddressAndFinalSelectionWhileFullRevalidateRemains() throws {
        let process = birth()
        var events = [String]()
        let host = EdgeApplicationHost(frontmost: { process }, selected: { pid in
            XCTAssertEqual(pid, process.pid); events.append("selected"); return ("13", "45")
        }, address: { pid, window, tab in
            XCTAssertEqual(pid, process.pid); XCTAssertEqual(window, "13"); XCTAssertEqual(tab, "45")
            events.append("original-address"); return "https://chatgpt.com/?temporary-chat=true"
        })
        let original = try host.freezeForClick()
        XCTAssertEqual(events, ["selected", "original-address"])
        // The synchronous executor runs the original page's focused/visible
        // document pin here, then this exact final native ID check.
        try host.recheckClickSelection(original)
        XCTAssertEqual(events, ["selected", "original-address", "selected"])
        events.removeAll()
        try host.revalidate(original)
        XCTAssertEqual(events, ["selected", "original-address", "selected"])
        XCTAssertEqual(original.process, process)
        XCTAssertEqual(original.windowID, "13"); XCTAssertEqual(original.tabID, "45")
    }

    func testClickSnapshotNeverRedirectsAddressAfterSelectionChangesAndFinalCheckRejects() throws {
        let process = birth()
        for changeWindow in [false, true] {
            var chosen = ("13", "45"), addresses = [(String, String)]()
            let host = EdgeApplicationHost(frontmost: { process }, selected: { _ in chosen },
                address: { _, window, tab in
                    addresses.append((window, tab))
                    chosen = changeWindow ? ("14", "45") : ("13", "46")
                    return "https://chatgpt.com/?temporary-chat=true"
                })
            let original = try host.freezeForClick()
            XCTAssertEqual(original.windowID, "13"); XCTAssertEqual(original.tabID, "45")
            XCTAssertThrowsError(try host.recheckClickSelection(original)) {
                XCTAssertEqual($0 as? EdgeHostError, .changed)
            }
            XCTAssertEqual(addresses.count, 1)
            XCTAssertEqual(addresses.first?.0, "13"); XCTAssertEqual(addresses.first?.1, "45")
        }
    }

    func testClickSnapshotRejectsProcessExitRestartOrForegroundChangeDuringOriginalAddressRead() throws {
        let process = birth()
        for restarted in [false, true] {
            var foreground: KernelProcessBirth? = process
            var reads = 0
            let host = EdgeApplicationHost(frontmost: { foreground }, selected: { _ in
                reads += 1; return ("13", "45")
            }, address: { _, _, _ in
                foreground = restarted ? self.birth(second: 11) : nil
                return "https://chatgpt.com/?temporary-chat=true"
            })
            XCTAssertThrowsError(try host.freezeForClick()) { XCTAssertEqual($0 as? EdgeHostError, .changed) }
            XCTAssertEqual(reads, 1)
        }
    }

    func testClickSnapshotRejectsEmptyAddressAndFullRecheckStillDetectsNavigation() throws {
        let process = birth()
        var url = ""
        let host = EdgeApplicationHost(frontmost: { process }, selected: { _ in ("13", "45") },
            address: { _, _, _ in url })
        XCTAssertThrowsError(try host.freezeForClick())
        url = "https://chatgpt.com/?temporary-chat=true"
        let original = try host.freezeForClick()
        url = "https://chatgpt.com/c/neutral-other"
        try host.recheckClickSelection(original)
        XCTAssertThrowsError(try host.revalidate(original)) { XCTAssertEqual($0 as? EdgeHostError, .changed) }
    }

    func test641AggregateTimingCounterexampleKeeps150MSAndSavesOneBoundedEvent() throws {
        // Only the three phase aggregates are from 641. The split of its
        // 87.0785 ms native freeze is a deterministic injected-cost model,
        // not a claim about the live duration of an individual Apple Event.
        func run(fullInitialFreeze: Bool) throws -> (events: Int, ticks: [Int]) {
            var now: TimeInterval = 100, selectedReads = 0, events = 0, ticks = [Int]()
            let deadline = MainWorldReceiptReadBudget.clickSnapshot(start: now).deadlineUptime
            XCTAssertTrue(abs((deadline - now) - 0.15) < 0.000001)
            let event = EdgeClickAppleEvent(deadlineUptime: deadline)
            func read(cost: TimeInterval) throws {
                _ = try event.send(.null(), uptime: { now }) { _, reply, mode, timeout in
                    events += 1; ticks.append(timeout)
                    XCTAssertEqual(mode, AESendMode(kAEWaitReply | kAENeverInteract))
                    now += cost
                    return OSStatus(AEDuplicateDesc(NSAppleEventDescriptor.null().aeDesc, reply))
                }
            }
            let process = birth()
            let host = EdgeApplicationHost(frontmost: { process }, selected: { _ in
                selectedReads += 1
                let intermediateRead = fullInitialFreeze && selectedReads == 2
                try read(cost: selectedReads == 1 ? 0.030 : intermediateRead ? 0.020 : 0.001)
                return ("13", "45")
            }, address: { _, _, _ in try read(cost: 0.030); return "https://chatgpt.com/?temporary-chat=true" })
            let original = try (fullInitialFreeze ? host.freeze() : host.freezeForClick())
            now += 0.00707849998609163 // Remaining modeled native-identity work.
            try read(cost: 0.03628254166687839) // Real pin aggregate, injected.
            now += 0.01129870832664892 // Real recheck-phase aggregate, injected before its send.
            if fullInitialFreeze {
                XCTAssertThrowsError(try host.recheckClickSelection(original)) {
                    XCTAssertEqual($0 as? WebAdapterError, .nativeEventFailed(-1712))
                }
                XCTAssertEqual(events, 4) // Refused final event was never sent.
            } else {
                try host.recheckClickSelection(original)
                XCTAssertEqual(selectedReads, 2)
                XCTAssertEqual(events, 4) // Address, pin and both outer selections.
                XCTAssertEqual(ticks.last, 2)
                XCTAssertTrue(now < deadline)
            }
            return (events, ticks)
        }
        _ = try run(fullInitialFreeze: true)
        let first = try run(fullInitialFreeze: false), second = try run(fullInitialFreeze: false)
        XCTAssertEqual(first.events, second.events)
        XCTAssertEqual(first.ticks, second.ticks)
    }
}
