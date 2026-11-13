import Darwin
import XCTest
@testable import RiftletAdapters

final class EdgeApplicationHostTests: XCTestCase {
    private func birth(pid: pid_t = 71, second: UInt64 = 10) -> KernelProcessBirth {
        var record = proc_bsdinfo()
        record.pbi_pid = UInt32(pid)
        record.pbi_start_tvsec = second
        return KernelProcessBirth(requestedPID: pid, record: record, bytesRead: Int32(MemoryLayout.size(ofValue: record)))!
    }

    func testStableForegroundWindowAndTabRequiredEvenWithSameURL() throws {
        let process = birth()
        var chosen = ("13", "45")
        let host = EdgeApplicationHost(frontmost: { process }, selected: { _ in chosen }, address: { _, _, _ in "https://example.test" })
        let original = try host.freeze()
        try host.revalidate(original)
        chosen = ("14", "45")
        XCTAssertThrowsError(try host.revalidate(original))
        chosen = ("13", "46")
        XCTAssertThrowsError(try host.revalidate(original))
    }

    func testForegroundOrLaunchChangeRefusesBeforeReadingNewReceiver() throws {
        var foreground: KernelProcessBirth? = birth()
        var reads = 0
        let host = EdgeApplicationHost(frontmost: { foreground }, selected: { _ in
            reads += 1
            return ("13", "45")
        }, address: { _, _, _ in "https://example.test" })
        let original = try host.freeze()
        let initial = reads
        foreground = nil
        XCTAssertThrowsError(try host.revalidate(original))
        foreground = birth(second: 11)
        XCTAssertThrowsError(try host.revalidate(original))
        XCTAssertEqual(reads, initial)
    }

    func testTabChangedBetweenDescriptorAndURLReadRefusesAndNavigationInvalidates() throws {
        let process = birth()
        var counter = 0
        let unstable = EdgeApplicationHost(frontmost: { process }, selected: { _ in
            counter += 1
            return ("13", String(counter))
        }, address: { _, _, _ in "https://example.test" })
        XCTAssertThrowsError(try unstable.freeze())
        var url = "https://example.test/a"
        let host = EdgeApplicationHost(frontmost: { process }, selected: { _ in ("13", "45") }, address: { _, _, _ in url })
        let original = try host.freeze()
        url = "https://example.test/b"
        XCTAssertThrowsError(try host.revalidate(original))
    }
}

extension EdgeApplicationHostTests {
    func testServiceInspectionUsesOriginalDocumentBindingAndNeverRedirectsOnSwitch() throws {
        let process = birth(), address = "https://claude.ai/chat/fixture"
        var tab = "45"
        let host = EdgeApplicationHost(frontmost: { process }, selected: { _ in ("13", tab) }, address: { _, _, _ in address })
        var actions = [ConversationSurfaceAction](), ids = [UUID]()
        let reader = EdgeConversationInspection(host: host) { service, action, id, target in
            XCTAssertEqual(service.service, .claude)
            XCTAssertEqual(target.address, address)
            actions.append(action)
            ids.append(id)
            let status: ConversationSurfaceStatus = action == .bind ? .bound : .unchanged
            return ConversationSurfaceInspection(status: status, entry: .button, attachmentCount: 1)
        }
        let pinned = try host.freeze()
        let binding = try reader.bind(pinned)
        _ = try reader.revalidate(binding)
        tab = "46"
        XCTAssertThrowsError(try reader.revalidate(binding))
        XCTAssertThrowsError(try reader.release(binding))
        XCTAssertEqual(actions, [.bind, .revalidate])
        XCTAssertEqual(Set(ids).count, 1)
    }

    func testRejectedPageOrNavigationDuringDiscoveryCannotCreateBinding() throws {
        let process = birth()
        var address = "https://poe.com/"
        let host = EdgeApplicationHost(frontmost: { process }, selected: { _ in ("13", "45") }, address: { _, _, _ in address })
        let pinned = try host.freeze()
        let changedReader = EdgeConversationInspection(host: host) { _, _, _, _ in
            address = "https://poe.com/chat/other"
            return ConversationSurfaceInspection(status: .bound, entry: .button, attachmentCount: 0)
        }
        XCTAssertThrowsError(try changedReader.bind(pinned))
        let refused = EdgeConversationInspection(host: host) { _, _, _, _ in
            ConversationSurfaceInspection(status: .ambiguous, entry: nil, attachmentCount: nil)
        }
        XCTAssertThrowsError(try refused.bind(host.freeze()))
    }
}
