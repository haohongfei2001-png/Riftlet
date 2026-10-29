import AppKit
import XCTest
import RiftletFeedback
@testable import RiftletFeedbackUI

final class FeedbackRecordsTests: XCTestCase {
    @MainActor private func views(_ root: NSView) -> [NSView] { [root] + root.subviews.flatMap(views) }
    @MainActor private func fixture() throws -> (FeedbackStore, FeedbackEngine) {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("feedback-records-" + UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let store = try FeedbackStore(directory: root)
        return (store, FeedbackEngine(store: store, secrets: MemoryFeedbackSecrets(), transport: DisabledFeedbackTransport()))
    }
    @MainActor private func card(_ id: String, in controller: FeedbackWindowController) throws -> NSView {
        try XCTUnwrap(views(try XCTUnwrap(controller.window?.contentView)).first { $0.identifier?.rawValue == "feedback.record.\(id)" })
    }
    @MainActor private func button(_ title: String, in root: NSView) throws -> NSButton {
        try XCTUnwrap(views(root).compactMap { $0 as? NSButton }.first { $0.title == title })
    }

    @MainActor func testEachLocalRecordHasItsOwnCompleteBodyAndLifecycleActions() async throws {
        let (store, engine) = try fixture()
        let completeText = "第一段完整正文\n" + String(repeating: "中文与 emoji 🌱 不应被列表截断。", count: 100)
        let queued = try await engine.enqueue(FeedbackDraft(text: completeText, revision: 1), appVersion: "0.1.0")
        let cancelled = try await engine.enqueue(FeedbackDraft(text: "已取消的独立记录", revision: 3), appVersion: "0.1.0")
        try await engine.requestDeletion(id: cancelled)
        let pending = try await engine.enqueue(FeedbackDraft(text: "已有尝试，仍须等待删除确认", revision: 5), appVersion: "0.1.0")
        let began = try await store.beginAttempt(id: pending, expected: .queued); XCTAssertTrue(began)
        try await engine.requestDeletion(id: pending)
        let controller = FeedbackWindowController(engine: engine, diagnostics: FeedbackDiagnostics(), appVersion: "0.1.0")
        await controller.waitUntilLoaded(); defer { controller.window?.close() }
        controller.show()
        let content = try XCTUnwrap(controller.window?.contentView)
        let disclosure = try XCTUnwrap(views(content).compactMap { $0 as? NSButton }.first {
            $0.identifier?.rawValue == "feedback.recordsDisclosure"
        })
        disclosure.performClick(nil); content.layoutSubtreeIfNeeded()
        let queuedCard = try card(queued, in: controller)
        let queuedBody = try XCTUnwrap(views(queuedCard).compactMap { $0 as? NSTextView }.first)
        XCTAssertEqual(queuedBody.string, completeText)
        XCTAssertFalse(queuedBody.isEditable); XCTAssertTrue(queuedBody.isSelectable)
        let viewport = try XCTUnwrap(queuedBody.enclosingScrollView)
        XCTAssertGreaterThan(viewport.frame.width, 100)
        XCTAssertGreaterThanOrEqual(viewport.frame.height, 26)
        XCTAssertLessThanOrEqual(viewport.frame.height, 100)
        XCTAssertGreaterThan(queuedBody.frame.height, viewport.contentSize.height, "A long body stays complete and scrollable inside its bounded card")
        let lastCharacter = NSRange(location: (completeText as NSString).length - 1, length: 1)
        queuedBody.scrollRangeToVisible(lastCharacter)
        let manager = try XCTUnwrap(queuedBody.layoutManager), container = try XCTUnwrap(queuedBody.textContainer)
        let glyphs = manager.glyphRange(forCharacterRange: lastCharacter, actualCharacterRange: nil)
        let tail = manager.boundingRect(forGlyphRange: glyphs, in: container)
            .offsetBy(dx: queuedBody.textContainerOrigin.x, dy: queuedBody.textContainerOrigin.y)
        XCTAssertTrue(viewport.documentVisibleRect.contains(CGPoint(x: tail.midX, y: tail.midY)), "The final saved characters remain reachable by native scrolling")
        XCTAssertNoThrow(try button("取消待发送", in: queuedCard))
        XCTAssertFalse(views(queuedCard).compactMap { $0 as? NSButton }.contains { $0.title.contains("移除本机") })
        let cancelledCard = try card(cancelled, in: controller)
        XCTAssertNoThrow(try button("移除本机正文与凭证…", in: cancelledCard))
        XCTAssertFalse(views(cancelledCard).compactMap { $0 as? NSButton }.contains { $0.title == "取消待发送" })
        let pendingCard = try card(pending, in: controller)
        XCTAssertTrue(views(pendingCard).compactMap { $0 as? NSTextField }.contains { $0.stringValue == "等待删除确认" })
        XCTAssertFalse(views(pendingCard).compactMap { $0 as? NSButton }.contains { $0.title.contains("移除本机") || $0.title == "取消待发送" })
        let records = try await store.records()
        XCTAssertEqual(records.first { $0.id == queued }?.attempts, 0)
        XCTAssertEqual(records.first { $0.id == pending }?.state, .deletionQueued)
        XCTAssertFalse(controller.statusText.contains("云端已持久接收"))
        await engine.stop()
    }

    @MainActor func testRecordRefreshAndFoldingPreserveEditorMarkedTextSelectionAndConsent() async throws {
        let (_, engine) = try fixture()
        let id = try await engine.enqueue(FeedbackDraft(text: "后台刷新的记录", revision: 1), appVersion: "0.1.0")
        let controller = FeedbackWindowController(engine: engine, diagnostics: FeedbackDiagnostics(), appVersion: "0.1.0")
        await controller.waitUntilLoaded(); defer { controller.window?.close() }
        let content = try XCTUnwrap(controller.window?.contentView)
        let editor = try XCTUnwrap(views(content).compactMap { $0 as? NSTextView }.first { $0.isEditable })
        controller.window?.makeFirstResponder(editor)
        editor.setMarkedText("中文组合尚未提交", selectedRange: NSRange(location: 2, length: 3),
                             replacementRange: NSRange(location: NSNotFound, length: 0))
        let beforeSelection = editor.selectedRange(), beforeMarked = editor.markedRange()
        let beforeDraft = controller.draftForTesting
        let disclosure = try XCTUnwrap(views(content).compactMap { $0 as? NSButton }.first {
            $0.identifier?.rawValue == "feedback.recordsDisclosure"
        })
        disclosure.performClick(nil)
        try await engine.requestDeletion(id: id)
        await controller.refreshRecords()
        disclosure.performClick(nil)
        XCTAssertTrue(editor.hasMarkedText())
        XCTAssertEqual(editor.markedRange(), beforeMarked); XCTAssertEqual(editor.selectedRange(), beforeSelection)
        XCTAssertTrue(controller.window?.firstResponder === editor)
        XCTAssertEqual(controller.currentText, "中文组合尚未提交")
        XCTAssertEqual(controller.draftForTesting, beforeDraft); XCTAssertFalse(controller.diagnosticSelected)
        XCTAssertNoThrow(try button("移除本机正文与凭证…", in: card(id, in: controller)))
        editor.unmarkText(); _ = await controller.saveBeforeClosing(); await engine.stop()
    }

    @MainActor func testRecordCancellationSheetTargetsOnlyClickedIDAfterListRefresh() async throws {
        guard !NSScreen.screens.isEmpty else { throw XCTSkip("AppKit window server unavailable") }
        let (store, engine) = try fixture()
        let first = try await engine.enqueue(FeedbackDraft(text: "保留的第一条", revision: 1), appVersion: "0.1.0")
        let second = try await engine.enqueue(FeedbackDraft(text: "点击取消的第二条", revision: 3), appVersion: "0.1.0")
        let controller = FeedbackWindowController(engine: engine, diagnostics: FeedbackDiagnostics(), appVersion: "0.1.0")
        await controller.waitUntilLoaded(); controller.show(); defer { controller.window?.close() }
        let window = try XCTUnwrap(controller.window)
        let content = try XCTUnwrap(window.contentView)
        let disclosure = try XCTUnwrap(views(content).compactMap { $0 as? NSButton }.first {
            $0.identifier?.rawValue == "feedback.recordsDisclosure"
        })
        disclosure.performClick(nil)
        try button("取消待发送", in: card(second, in: controller)).performClick(nil)
        let sheet = try XCTUnwrap(window.attachedSheet)
        let sheetContent = try XCTUnwrap(sheet.contentView)
        XCTAssertTrue(views(sheetContent).compactMap { $0 as? NSTextField }.contains { $0.stringValue.contains("RF-\(second.prefix(8))") })
        let keep = try button("保留", in: sheetContent)
        XCTAssertTrue(sheet.defaultButtonCell === keep.cell)
        XCTAssertEqual(keep.keyEquivalent, "\u{1b}")
        XCTAssertTrue(try button("取消待发送", in: sheetContent).keyEquivalent.isEmpty)
        // A refresh cannot retarget a pending confirmation to another row.
        await controller.refreshRecords()
        window.endSheet(sheet, returnCode: .alertFirstButtonReturn)
        var result: [FeedbackRecord] = []
        for _ in 0..<100 {
            result = try await store.records()
            if result.first(where: { $0.id == second })?.state == .cancelled { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(result.first { $0.id == first }?.state, .queued)
        XCTAssertEqual(result.first { $0.id == second }?.state, .cancelled)
        XCTAssertTrue(result.allSatisfy { $0.attempts == 0 })
        XCTAssertEqual(Set(result.map(\.envelope.text)), ["保留的第一条", "点击取消的第二条"])
        await engine.stop()
    }

    @MainActor func testConfirmationReturnAndEscapeKeepTheFeedbackRecord() async throws {
        guard !NSScreen.screens.isEmpty else { throw XCTSkip("AppKit window server unavailable") }
        let (store, engine) = try fixture()
        let id = try await engine.enqueue(FeedbackDraft(text: "Return 和 Escape 都应保留", revision: 1), appVersion: "0.1.0")
        let controller = FeedbackWindowController(engine: engine, diagnostics: FeedbackDiagnostics(), appVersion: "0.1.0")
        await controller.waitUntilLoaded(); controller.show()
        let window = try XCTUnwrap(controller.window)
        defer {
            if let sheet = window.attachedSheet { window.endSheet(sheet, returnCode: .alertSecondButtonReturn) }
            window.close()
        }
        let disclosure = try XCTUnwrap(views(try XCTUnwrap(window.contentView)).compactMap { $0 as? NSButton }
            .first { $0.identifier?.rawValue == "feedback.recordsDisclosure" })
        disclosure.performClick(nil)
        for (characters, keyCode) in [("\r", UInt16(36)), ("\u{1b}", UInt16(53))] {
            try button("取消待发送", in: card(id, in: controller)).performClick(nil)
            let sheet = try XCTUnwrap(window.attachedSheet)
            let keep = try button("保留", in: try XCTUnwrap(sheet.contentView))
            XCTAssertTrue(sheet.defaultButtonCell === keep.cell)
            let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: sheet.windowNumber, context: nil,
                characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode))
            // Real AppKit event dispatch to the visible sheet; a software key
            // event is not claimed as physical keyboard/VoiceOver acceptance.
            if !sheet.performKeyEquivalent(with: event) { sheet.sendEvent(event) }
            for _ in 0..<100 {
                if window.attachedSheet == nil { break }
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            XCTAssertNil(window.attachedSheet, "The non-destructive action must dismiss this sheet")
            let records = try await store.records()
            XCTAssertEqual(records.first { $0.id == id }?.state, .queued)
            XCTAssertEqual(records.first { $0.id == id }?.attempts, 0)
        }
        await engine.stop()
    }
}
