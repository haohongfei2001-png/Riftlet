import AppKit
import XCTest
@testable import RiftletUI

/// Main-actor deadlines are advanced explicitly: CI scheduler delays must not
/// turn a before-deadline assertion into an accidental after-deadline assertion.
@MainActor final class RiftPeekTestClock {
    private var now: TimeInterval = 0
    private var tasks: [(TimeInterval, @MainActor () -> Void)] = []
    func schedule(_ delay: TimeInterval, _ action: @escaping @MainActor () -> Void) {
        tasks.append((now + delay, action))
    }
    func advance(by interval: TimeInterval) {
        now += interval
        while let index = tasks.indices.filter({ tasks[$0].0 <= now }).min(by: { tasks[$0].0 < tasks[$1].0 }) {
            tasks.remove(at: index).1()
        }
    }
}

final class RiftWarmPeekTests: XCTestCase {
    @MainActor func testColdWarmAtomicSwapFixedCanvasAndBoundedLatestDecode() throws {
        _ = NSApplication.shared
        let clock = RiftPeekTestClock(), peek = RiftPeek(schedule: clock.schedule)
        defer { peek.close() }
        let ids = [UUID(), UUID(), UUID()]
        let page = ids.enumerated().map { index, id in
            RiftPeekItem(id: id, visibilityRevision: 0,
                         imageSize: index == 1 ? CGSize(width: 100, height: 1000) : CGSize(width: 1600, height: 900))
        }
        let context = try XCTUnwrap(CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8,
            bytesPerRow: 16, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let cg = try XCTUnwrap(context.makeImage())
        var deliveries: [(UUID, (CGImage?) -> Void)] = []
        func request(_ index: Int, page next: [RiftPeekItem]? = nil) {
            peek.schedule(id: ids[index], rank: index + 1, page: next ?? page, stillValid: { true },
                load: { deliveries.append((ids[index], $0)) },
                anchor: { (CGRect(x: 950, y: 350, width: 50, height: 56), CGRect(x: 0, y: 0, width: 1100, height: 800), 900) })
        }
        request(0); XCTAssertEqual(deliveries.count, 1)
        deliveries[0].1(cg)
        clock.advance(by: 0.449); XCTAssertNil(peek.displayedAssetID)
        clock.advance(by: 0.0011)
        XCTAssertEqual(peek.displayedAssetID, ids[0]); XCTAssertEqual(peek.displayedRank, 1)
        let frame = peek.presentationPanel.frame
        XCTAssertEqual(frame.size, CGSize(width: 336, height: 272))
        request(1)
        XCTAssertNil(peek.displayedAssetID, "Waiting shell must remove old pixels before changing rank")
        deliveries[1].1(cg)
        clock.advance(by: 0.089); XCTAssertNil(peek.displayedAssetID)
        clock.advance(by: 0.0011)
        XCTAssertEqual(peek.displayedAssetID, ids[1]); XCTAssertEqual(peek.displayedRank, 2)
        XCTAssertEqual(peek.presentationPanel.frame, frame)
        request(0) // one running decode
        request(1); request(2); request(0) // replace waiting intent, including A-B-A
        XCTAssertEqual(deliveries.count, 3)
        clock.advance(by: 0.1)
        deliveries[2].1(cg) // old A callback cannot commit to new A request
        XCTAssertNil(peek.displayedAssetID)
        XCTAssertEqual(deliveries.count, 4); XCTAssertEqual(deliveries[3].0, ids[0])
        deliveries[3].1(cg)
        XCTAssertEqual(peek.displayedAssetID, ids[0]); XCTAssertEqual(peek.displayedRank, 1)
        request(1); peek.cancel(); deliveries[4].1(cg)
        clock.advance(by: 1)
        XCTAssertNil(peek.displayedAssetID); XCTAssertFalse(peek.presentationPanel.isVisible)
    }

    @MainActor func testSameIDGracePreservesDeadlineAndPageRevisionInvalidatesCallback() throws {
        _ = NSApplication.shared
        let clock = RiftPeekTestClock(), peek = RiftPeek(schedule: clock.schedule)
        defer { peek.close() }
        let id = UUID(); var callbacks: [(CGImage?) -> Void] = []
        func request(_ revision: Int64) {
            peek.schedule(id: id, rank: 1, page: [RiftPeekItem(id: id, visibilityRevision: revision, imageSize: CGSize(width: 20, height: 20))],
                stillValid: { true }, load: { callbacks.append($0) },
                anchor: { (CGRect(x: 900, y: 300, width: 50, height: 50), CGRect(x: 0, y: 0, width: 1000, height: 800), 850) })
        }
        let context = try XCTUnwrap(CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8,
            bytesPerRow: 16, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let cg = try XCTUnwrap(context.makeImage())
        request(0); clock.advance(by: 0.4); peek.leave(); clock.advance(by: 0.025); request(0)
        XCTAssertEqual(callbacks.count, 1)
        callbacks[0](cg); clock.advance(by: 0.026)
        XCTAssertEqual(peek.displayedAssetID, id, "Same-ID reentry must retain original 450ms deadline")
        request(1); XCTAssertNil(peek.displayedAssetID)
        clock.advance(by: 0.1); callbacks[1](cg)
        XCTAssertNil(peek.displayedAssetID, "Revision change is a cold session")
        clock.advance(by: 0.351); XCTAssertEqual(peek.displayedAssetID, id)
    }
    @MainActor func testDeadlineAndDecodeDuringLeaveGraceRemainUsableOnSameIDReentry() throws {
        _ = NSApplication.shared
        let clock = RiftPeekTestClock(), peek = RiftPeek(schedule: clock.schedule)
        defer { peek.close() }
        let id = UUID(); var hovering = true
        var callback: ((CGImage?) -> Void)?
        var loadCount = 0
        func request() {
            peek.schedule(id: id, rank: 1, stillValid: { hovering }, load: { loadCount += 1; callback = $0 },
                anchor: { (CGRect(x: 900, y: 300, width: 50, height: 50), CGRect(x: 0, y: 0, width: 1000, height: 800), 850) })
        }
        let context = try XCTUnwrap(CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8,
            bytesPerRow: 16, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let cg = try XCTUnwrap(context.makeImage())
        request(); clock.advance(by: 0.4); hovering = false; peek.leave()
        clock.advance(by: 0.06); callback?(cg)
        XCTAssertNil(peek.displayedAssetID)
        hovering = true; request()
        XCTAssertEqual(peek.displayedAssetID, id)
        XCTAssertEqual(loadCount, 1)
    }

    @MainActor func testColdSlowDecodeShowsCandidateShellAndFadeReentryCancelsOldAlphaWrites() {
        _ = NSApplication.shared
        let clock = RiftPeekTestClock(), peek = RiftPeek(schedule: clock.schedule)
        defer { peek.close() }
        let id = UUID()
        func request() {
            peek.schedule(id: id, rank: 7, page: [RiftPeekItem(id: id, visibilityRevision: 0,
                imageSize: CGSize(width: 400, height: 300))], stillValid: { true }, load: { _ in },
                anchor: { (CGRect(x: 900, y: 300, width: 50, height: 50), CGRect(x: 0, y: 0, width: 1000, height: 800), 850) })
        }
        request(); clock.advance(by: 0.449)
        XCTAssertFalse(peek.presentationPanel.isVisible)
        clock.advance(by: 0.002)
        XCTAssertTrue(peek.presentationPanel.isVisible)
        XCTAssertNil(peek.displayedAssetID)
        XCTAssertNil(peek.displayedRank)
        let labels = peek.presentationPanel.contentView?.subviews.compactMap { $0 as? NSTextField } ?? []
        XCTAssertTrue(labels.contains { !$0.isHidden && $0.stringValue == "7" })
        peek.leave(); clock.advance(by: 0.1); clock.advance(by: 0.04)
        XCTAssertLessThan(peek.presentationPanel.alphaValue, 1)
        request(); XCTAssertEqual(peek.presentationPanel.alphaValue, 1)
        clock.advance(by: 0.2)
        XCTAssertTrue(peek.presentationPanel.isVisible)
        XCTAssertEqual(peek.presentationPanel.alphaValue, 1)
    }

    @MainActor func testFeedbackDeadlineDeterministicallyRejectsStaleDecode() async throws {
        _ = NSApplication.shared
        guard let screen = NSScreen.screens.first else { throw XCTSkip("No AppKit display") }
        let clock = RiftPeekTestClock()
        let peek = RiftPeek(schedule: clock.schedule); defer { peek.close() }
        let context = try XCTUnwrap(CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8,
            bytesPerRow: 16, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let cg = try XCTUnwrap(context.makeImage()), id = UUID()
        let row = CGRect(x: screen.visibleFrame.maxX - 90, y: screen.visibleFrame.midY, width: 70, height: 44)
        let anchor = { (row, screen.visibleFrame, row.minX) as (CGRect, CGRect, CGFloat)? }
        var delivery: ((CGImage?) -> Void)?
        peek.schedule(id: id, immediate: true, stillValid: { true }, load: { delivery = $0 }, anchor: anchor)
        XCTAssertNotNil(delivery)
        let panel = peek.presentationPanel
        peek.scheduleNote(id: id, text: "正在等待附加", delay: 0.25, stillValid: { true }, anchor: anchor)
        delivery?(cg)
        clock.advance(by: 0.1)
        XCTAssertFalse(panel.isVisible, "An old image decode cannot bypass the waiting delay")
        peek.leave()
        clock.advance(by: 0.2)
        XCTAssertFalse(panel.isVisible, "Leaving the island cancels the pending explanation")
        XCTAssertNil(peek.assetID)
        peek.scheduleNote(id: id, text: "图片已保留，当前聊天暂时不能接收图片。", delay: 0,
            stillValid: { true }, anchor: anchor)
        clock.advance(by: 0)
        XCTAssertTrue(peek.isNoteVisible)
        XCTAssertTrue(panel.ignoresMouseEvents); XCTAssertFalse(panel.canBecomeKey); XCTAssertFalse(panel.canBecomeMain)
        XCTAssertLessThanOrEqual(panel.frame.width, 240)
        XCTAssertLessThanOrEqual(panel.frame.maxX, row.minX - 12)
        XCTAssertTrue(screen.visibleFrame.contains(panel.frame))
        // A repeated projection does not renew the bounded display lifetime.
        peek.scheduleNote(id: id, text: "图片已保留，当前聊天暂时不能接收图片。", delay: 0,
            stillValid: { true }, anchor: anchor)
        clock.advance(by: 2.6)
        XCTAssertFalse(panel.isVisible); XCTAssertNil(peek.assetID)
    }

}
