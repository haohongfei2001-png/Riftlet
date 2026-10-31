import XCTest
import Foundation
import Darwin
@testable import RiftletAdapters

final class ChromeProcessIdentityTests: XCTestCase {
    private func record(pid: UInt32 = 23, seconds: UInt64 = 100, micros: UInt64 = 7) -> proc_bsdinfo {
        var r = proc_bsdinfo(); r.pbi_pid = pid; r.pbi_start_tvsec = seconds; r.pbi_start_tvusec = micros
        return r
    }
    private func identity(seconds: UInt64 = 100, micros: UInt64 = 7, date: Date? = nil) throws -> ChromeProcessIdentity {
        let birth = try XCTUnwrap(KernelProcessBirth(requestedPID: 23,
            record: record(seconds: seconds, micros: micros), bytesRead: Int32(MemoryLayout<proc_bsdinfo>.size)))
        return try XCTUnwrap(ChromeProcessIdentity(birth: birth, applicationID: "com.google.Chrome", terminated: false, launchDate: date))
    }
    func testMissingLaunchServicesDateHasVersionedIntegerIdentity() throws {
        XCTAssertEqual(try identity().session, "chrome-kernel-v1:23:100:7")
    }
    func testLateLaunchServicesDateCannotChangeNewSession() throws {
        let a = try identity(), b = try identity(date: Date(timeIntervalSince1970: 101.25))
        XCTAssertEqual(a, b); XCTAssertEqual(a.session, b.session)
        XCTAssertTrue(b.matches(session: a.session))
    }
    func testPIDReuseOrBirthMicrosecondChangeRejectsOriginalSession() throws {
        let before = try identity()
        for after in [try identity(seconds: 101), try identity(micros: 8)] {
            XCTAssertNotEqual(before, after)
            XCTAssertFalse(after.matches(session: before.session, allowLegacyObservation: true))
        }
    }
    func testIncompleteInvalidAndMismatchedKernelRecordsFailClosed() {
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        for count in [-1, 0, size - 1, size + 1] as [Int32] {
            XCTAssertNil(KernelProcessBirth(requestedPID: 23, record: record(), bytesRead: count))
        }
        for r in [record(pid: 24), record(seconds: 0), record(micros: 1_000_000)] {
            XCTAssertNil(KernelProcessBirth(requestedPID: 23, record: r, bytesRead: size))
        }
        XCTAssertNil(KernelProcessBirth(requestedPID: -1, record: record(), bytesRead: size))
    }
    func testWrongApplicationAndTerminatedProcessAreNotIdentities() throws {
        let birth = try identity().birth
        XCTAssertNil(ChromeProcessIdentity(birth: birth, applicationID: "other", terminated: false, launchDate: nil))
        XCTAssertNil(ChromeProcessIdentity(birth: birth, applicationID: nil, terminated: false, launchDate: nil))
        XCTAssertNil(ChromeProcessIdentity(birth: birth, applicationID: "com.google.Chrome", terminated: true, launchDate: nil))
    }
    func testLegacyObservationRequiresActualOriginalLaunchDateAndExplicitReadOnlyFlag() throws {
        let legacy = "23:100.5", withDate = try identity(date: Date(timeIntervalSince1970: 100.5))
        XCTAssertFalse(withDate.matches(session: legacy))
        XCTAssertTrue(withDate.matches(session: legacy, allowLegacyObservation: true))
        XCTAssertFalse(try identity().matches(session: legacy, allowLegacyObservation: true))
        XCTAssertFalse(withDate.matches(session: "24:100.5", allowLegacyObservation: true))
        XCTAssertFalse(withDate.matches(session: "23:100.500", allowLegacyObservation: true))
        XCTAssertFalse(withDate.matches(session: "23:100.000007", allowLegacyObservation: true))
    }
    func testKernelBirthCanBeReadForThisProcessWithoutGUIOrChrome() throws {
        let first = try XCTUnwrap(KernelProcessBirth.read(pid: getpid()))
        XCTAssertEqual(KernelProcessBirth.read(pid: getpid()), first)
        XCTAssertEqual(first.pid, getpid())
        XCTAssertNil(ChromeProcessIdentity.read(pid: getpid()), "A test runner is not Chrome")
        XCTAssertNil(KernelProcessBirth.read(pid: -1))
    }
}
