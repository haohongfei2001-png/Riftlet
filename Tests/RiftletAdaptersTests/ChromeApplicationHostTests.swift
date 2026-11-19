import Darwin
import XCTest
@testable import RiftletAdapters

final class ChromeApplicationHostTests: XCTestCase {
    private func process(_ start: UInt64) throws -> ChromeProcessIdentity {
        var info = proc_bsdinfo()
        info.pbi_pid = 72
        info.pbi_start_tvsec = start
        let birth = try XCTUnwrap(KernelProcessBirth(requestedPID: 72, record: info,
            bytesRead: Int32(MemoryLayout<proc_bsdinfo>.size)))
        return try XCTUnwrap(ChromeProcessIdentity(birth: birth, applicationID: "com.google.Chrome",
            terminated: false, launchDate: nil))
    }

    func testForegroundChangesNeverContactAnotherBrowserOrResumeAfterProcessRestart() throws {
        let first = try process(8)
        var foreground: ChromeProcessIdentity? = first
        var queries = 0
        let host = ChromeApplicationHost(foreground: { foreground }, selected: { _ in
            queries += 1
            return ("2", "3")
        }, address: { _, _, _ in "https://chatgpt.com/g/project/c/thread" })
        let target = try host.freeze()
        let captured = queries
        foreground = nil
        XCTAssertThrowsError(try host.freeze())
        XCTAssertThrowsError(try host.revalidate(target))
        foreground = try process(9)
        XCTAssertThrowsError(try host.revalidate(target))
        XCTAssertEqual(queries, captured)
    }

    func testExactSelectionAndServiceAreRequiredBeforeBootstrap() throws {
        let first = try process(3)
        var selection = ("2", "7")
        var url = "https://chatgpt.com/"
        let host = ChromeApplicationHost(foreground: { first }, selected: { _ in selection },
            address: { _, _, _ in url })
        let target = try host.freeze()
        try host.revalidate(target)
        for moved in [("2", "8"), ("9", "7")] {
            selection = moved
            XCTAssertThrowsError(try host.revalidate(target))
        }
        selection = ("2", "7")
        for other in ["https://chatgpt.com/c/another", "https://claude.ai/new"] {
            url = other
            XCTAssertThrowsError(try host.revalidate(target))
        }
        for other in ["https://claude.ai/new", "http://chatgpt.com", "https://chatgpt.com:444/",
                      "https://u@chatgpt.com/", "https://chatgpt.com.other.example"] {
            url = other
            XCTAssertThrowsError(try host.freeze())
        }
    }

    func testSelectionChangedDuringClickSnapshotIsRejected() throws {
        let first = try process(3)
        var tab = "7"
        var switchDuringRead = false
        let host = ChromeApplicationHost(foreground: { first }, selected: { _ in ("2", tab) },
            address: { _, _, _ in
                if switchDuringRead { tab = "8" }
                return "https://chatgpt.com/"
            })
        let original = try host.freeze()
        switchDuringRead = true
        XCTAssertThrowsError(try host.revalidate(original))
        tab = "7"
        XCTAssertThrowsError(try host.freeze())
    }
}
