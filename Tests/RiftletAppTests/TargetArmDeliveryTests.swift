import Foundation
import XCTest
import RiftletCore
import RiftletAdapters
@testable import RiftletApp

/// Native scheduling/clock boundaries only. These tests do not create an AX
/// observer, query permission, touch Chrome or establish physical-click success.
final class TargetArmDeliveryTests: XCTestCase {
    private func target(_ draft: String = "draft-A") -> TargetLease {
        TargetLease(adapterID: "chatgpt-web", surface: .webChat,
            applicationID: "com.google.Chrome", sessionID: "chrome-kernel-v1:42:100:1",
            windowID: "7", tabID: "9", documentID: "document", composerID: "composer",
            draftGeneration: draft)
    }

    func testPublicationBeforePresentationCanPreserveAnAlreadyLaterOriginalEvent() throws {
        var scheduler = TargetArmScheduler()
        scheduler.start()
        let capture = try XCTUnwrap(scheduler.begin())
        XCTAssertTrue(try XCTUnwrap(scheduler.complete(capture)).acceptsAcknowledgement)
        let lease = target()
        let actualPublication = ArmedTarget(target: lease, acknowledgedUptime: 10.005,
                                             hostSession: capture.epoch)
        // The event occurred while unrelated presentation work occupied MainActor.
        // It is delivered afterward, but its original time must remain unchanged.
        XCTAssertEqual(actualPublication.freeze(eventUptime: 10.010, nowUptime: 10.100,
            hostSession: scheduler.epoch, foregroundSession: lease.sessionID), lease)
        let presentationFirst = ArmedTarget(target: lease, acknowledgedUptime: 10.100,
                                             hostSession: capture.epoch)
        XCTAssertNil(presentationFirst.freeze(eventUptime: 10.010, nowUptime: 10.100,
            hostSession: scheduler.epoch, foregroundSession: lease.sessionID))
    }

    func testColdOrSimultaneousPressCannotBorrowLaterPublication() throws {
        let lease = target(), epoch = UUID()
        let late = ArmedTarget(target: lease, acknowledgedUptime: 20.010, hostSession: epoch)
        for event in [20.000, 20.010] {
            XCTAssertNil(late.freeze(eventUptime: event, nowUptime: 20.100,
                hostSession: epoch, foregroundSession: lease.sessionID))
        }
        XCTAssertEqual(late.freeze(eventUptime: 20.011, nowUptime: 20.100,
            hostSession: epoch, foregroundSession: lease.sessionID), lease)
        XCTAssertNil(late.freeze(eventUptime: 20.011, nowUptime: 20.100,
            hostSession: epoch, foregroundSession: "different-process"))
    }

    func testAToBToAReturnCannotRepublishTheOriginalCaptureOrACK() throws {
        var scheduler = TargetArmScheduler()
        scheduler.start()
        let original = try XCTUnwrap(scheduler.begin())
        let lease = target()
        let old = ArmedTarget(target: lease, acknowledgedUptime: 30, hostSession: original.epoch)
        XCTAssertFalse(scheduler.request(invalidateEpoch: true)) // A -> B
        let middleEpoch = scheduler.epoch
        XCTAssertFalse(scheduler.request(invalidateEpoch: true)) // B -> A
        XCTAssertNotEqual(scheduler.epoch, middleEpoch)
        XCTAssertNil(old.freeze(eventUptime: 31, nowUptime: 31,
            hostSession: scheduler.epoch, foregroundSession: lease.sessionID))
        let obsolete = try XCTUnwrap(scheduler.complete(original))
        XCTAssertFalse(obsolete.acceptsAcknowledgement)
        XCTAssertTrue(obsolete.shouldWake)
        let replacement = try XCTUnwrap(scheduler.begin())
        XCTAssertNotEqual(replacement.epoch, original.epoch)
        XCTAssertTrue(try XCTUnwrap(scheduler.complete(replacement)).acceptsAcknowledgement)
    }

    func testFocusAndCaptureDemandCoalesceWithoutLosingTheFollowupOrParallelCapture() throws {
        var scheduler = TargetArmScheduler()
        scheduler.start()
        let capture = try XCTUnwrap(scheduler.begin())
        for _ in 0..<8 {
            XCTAssertFalse(scheduler.request(invalidateEpoch:
                ChromeActivityHintPolicy.invalidatesTarget("chromeFocus")))
            XCTAssertNil(scheduler.begin())
        }
        let finished = try XCTUnwrap(scheduler.complete(capture))
        XCTAssertTrue(finished.acceptsAcknowledgement)
        XCTAssertTrue(finished.shouldWake)
        let next = try XCTUnwrap(scheduler.begin())
        XCTAssertEqual(next.epoch, capture.epoch)
        XCTAssertNil(scheduler.complete(capture))
        XCTAssertEqual(scheduler.inFlight, next)
        XCTAssertFalse(try XCTUnwrap(scheduler.complete(next)).shouldWake)
    }

    func testOriginalRecoveryDefersOnlyOneStaleCompletionDespiteRepeatedTargetChanges() throws {
        var scheduler = TargetArmScheduler(), recovery = OriginalRecoveryDeferral()
        scheduler.start()
        let first = try XCTUnwrap(scheduler.begin())
        scheduler.request(invalidateEpoch: true)
        let stale = try XCTUnwrap(scheduler.complete(first))
        XCTAssertFalse(recovery.shouldStart(after: stale, isRunning: scheduler.isRunning))
        let next = try XCTUnwrap(scheduler.begin())
        scheduler.request(invalidateEpoch: true)
        let staleAgain = try XCTUnwrap(scheduler.complete(next))
        XCTAssertFalse(staleAgain.acceptsAcknowledgement)
        XCTAssertTrue(staleAgain.shouldWake)
        XCTAssertTrue(recovery.shouldStart(after: staleAgain, isRunning: scheduler.isRunning),
            "Repeated structural activity must not indefinitely starve original read-only observation")
        XCTAssertNotNil(scheduler.begin(), "Recovery eligibility cannot consume the arm wake")
    }

    func testCurrentCompletionMayRecoverEvenWithoutAPublishedTarget() throws {
        var scheduler = TargetArmScheduler(), recovery = OriginalRecoveryDeferral()
        scheduler.start()
        let current = try XCTUnwrap(scheduler.begin())
        // A permission/target failure still completes this scheduler attempt;
        // no target is manufactured to make original recovery eligible.
        let completion = try XCTUnwrap(scheduler.complete(current))
        XCTAssertTrue(completion.acceptsAcknowledgement)
        XCTAssertTrue(recovery.shouldStart(after: completion, isRunning: scheduler.isRunning))
        XCTAssertNil(scheduler.begin())
    }

    func testStoppedCompletionCannotStartRecoveryOrSpendTheDeferral() throws {
        var scheduler = TargetArmScheduler(), recovery = OriginalRecoveryDeferral()
        scheduler.start()
        let old = try XCTUnwrap(scheduler.begin())
        scheduler.stop()
        let stopped = try XCTUnwrap(scheduler.complete(old))
        XCTAssertFalse(recovery.shouldStart(after: stopped, isRunning: scheduler.isRunning))
        scheduler.start()
        let fresh = try XCTUnwrap(scheduler.begin())
        scheduler.request(invalidateEpoch: true)
        let firstStaleAfterRestart = try XCTUnwrap(scheduler.complete(fresh))
        XCTAssertFalse(recovery.shouldStart(after: firstStaleAfterRestart, isRunning: scheduler.isRunning))
    }

    /// Complement to executable policy tests: verify the actual App call site,
    /// not a second delivery implementation in the test. This is a source-order
    /// regression guard, not a runtime AX/presentation measurement.
    func testProductionDeliveryPublishesBeforePresentationAndWakesBeforeBackgroundWork() throws {
        let source = try mainSource()
        let start = try XCTUnwrap(source.range(of: "private func performPendingArm()"))
        let end = try XCTUnwrap(source.range(of: "private func recordPresentation", range: start.upperBound..<source.endIndex))
        let body = String(source[start.lowerBound..<end.lowerBound])
        let publication = try XCTUnwrap(body.range(of: "self.armedTarget = ArmedTarget"))
        let record = try XCTUnwrap(body.range(of: "self.recordAcceptance(fields)"))
        let presentation = try XCTUnwrap(body.range(of: "self.updateSetup()"))
        let wake = try XCTUnwrap(body.range(of: "if completion.shouldWake { self.performPendingArm() }"))
        let binding = try XCTUnwrap(body.range(of: "self.bindDeferredChromeActivity(afterCaptureIn: attempt.epoch)"))
        let deferral = try XCTUnwrap(body.range(of: "self.originalRecoveryDeferral.shouldStart(after: completion, isRunning: self.armScheduler.isRunning)"))
        let recovery = try XCTUnwrap(body.range(of: "self.startOriginalRecovery()"))
        XCTAssertLessThan(publication.lowerBound, record.lowerBound)
        XCTAssertLessThan(record.lowerBound, presentation.lowerBound)
        XCTAssertLessThan(wake.lowerBound, binding.lowerBound)
        XCTAssertLessThan(wake.lowerBound, recovery.lowerBound)
        XCTAssertLessThan(deferral.lowerBound, recovery.lowerBound)
    }

    func testProductionEmptyRecoveryExitsBeforePermissionOrTransportTask() throws {
        let source = try mainSource()
        let start = try XCTUnwrap(source.range(of: "private func startOriginalRecovery()"))
        let end = try XCTUnwrap(source.range(of: "private func startAttachmentObservationIfPermitted", range: start.upperBound..<source.endIndex))
        let body = String(source[start.lowerBound..<end.lowerBound])
        let consumed = try XCTUnwrap(body.range(of: "originalRecoveryIDs = nil"))
        let emptyGuard = try XCTUnwrap(body.range(of: "guard !ids.isEmpty else { return }"))
        let task = try XCTUnwrap(body.range(of: "originalRecoveryTask = Task"))
        let permission = try XCTUnwrap(body.range(of: "inspectAutomationPermission(reason: \"originalRecovery\")"))
        let observe = try XCTUnwrap(body.range(of: "transfer.recoverOriginalObservations(operationIDs: ids)"))
        XCTAssertLessThan(consumed.lowerBound, emptyGuard.lowerBound)
        XCTAssertLessThan(emptyGuard.lowerBound, task.lowerBound)
        XCTAssertLessThan(task.lowerBound, permission.lowerBound)
        XCTAssertLessThan(permission.lowerBound, observe.lowerBound)
    }

    private func mainSource() throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent("Sources/RiftletApp/RiftletMain.swift"), encoding: .utf8)
    }
}
