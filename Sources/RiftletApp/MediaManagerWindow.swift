import AppKit
import RiftletCapture
import RiftletUI

@MainActor
final class MediaManagerWindow: NSWindowController {
    private let importer: PrivateAssetImporter
    private let captureBusy: () -> Bool
    private let changed: () async -> Void
    private let summary = NSTextField(wrappingLabelWithString: "")
    private let status = NSTextField(wrappingLabelWithString: "")
    private let rule = NSPopUpButton()
    private let existing = NSButton(checkboxWithTitle: ProductCopy.text("也应用于已有截图", "Apply to existing screenshots too"), target: nil, action: nil)
    private var items: [MediaCleanupItem] = []
    private var pending: [URL] = []
    private var actions: [NSButton] = []
    private var working = false
    private let text = ProductCopy.text as (String, String) -> String

    init(importer: PrivateAssetImporter, captureBusy: @escaping () -> Bool, changed: @escaping () async -> Void) {
        self.importer = importer; self.captureBusy = captureBusy; self.changed = changed
        let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 535, height: 355), styleMask: [.titled, .closable],
                             backing: .buffered, defer: false)
        super.init(window: panel)
        panel.isReleasedWhenClosed = false
        panel.identifier = .init("RiftletMediaManager")
        panel.title = text("管理截图资料", "Manage Screenshots")
        let stack = NSStackView()
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 24, bottom: 20, right: 24)
        panel.contentView = stack
        rule.addItems(withTitles: [text("一直保留", "Keep indefinitely"), text("30 天", "30 days"), text("90 天", "90 days")])
        let save = button(text("保存", "Save"), #selector(saveRule))
        stack.addArrangedSubview(NSStackView(views: [NSTextField(labelWithString: text("收起后保留副本", "Keep hidden copies for")), rule, existing, save]))
        let explanation = NSTextField(wrappingLabelWithString: text("到期仅整理已验证有系统原图的副本。桌面中、交接中和需要处理的图片会保留。",
            "Scheduled cleanup requires a verified original. Desktop screenshots, transfers and items needing attention stay in the library."))
        stack.addArrangedSubview(explanation); stack.addArrangedSubview(summary)
        let trash = button(text("移到废纸篓", "Move to Trash"), #selector(clean))
        let undo = button(text("从废纸篓找回", "Restore from Trash"), #selector(restore))
        stack.addArrangedSubview(NSStackView(views: [trash, undo]))
        let recover = button(text("收录待找回截图", "Recover pending captures"), #selector(collect))
        let reveal = button(text("显示捕获原件", "Show capture originals"), #selector(revealCaptures))
        stack.addArrangedSubview(NSStackView(views: [recover, reveal]))
        stack.addArrangedSubview(status)
        actions = [save, trash, undo, recover, reveal]
        for (control, name) in zip(actions, ["save", "trash", "restore", "recover", "reveal"]) {
            control.identifier = .init("media.manage." + name)
        }
        for field in [summary, explanation, status] {
            field.preferredMaxLayoutWidth = 480
            field.setContentCompressionResistancePriority(.required, for: .vertical)
        }
        panel.center()
    }
    required init?(coder: NSCoder) { nil }

    private func button(_ title: String, _ action: Selector) -> NSButton {
        NSButton(title: title, target: self, action: action)
    }

    func present() {
        showWindow(nil); window?.makeKeyAndOrderFront(nil)
        run {}
    }

    private func run(_ operation: @escaping @MainActor () async throws -> Void) {
        guard !working else { return }
        working = true
        actions.forEach { $0.isEnabled = false }
        rule.isEnabled = false; existing.isEnabled = false
        status.stringValue = text("正在检查…", "Checking…")
        Task {
            defer { working = false; rule.isEnabled = true; existing.isEnabled = true; actions[0].isEnabled = true }
            var failed = false
            do { try await operation() } catch { failed = true }
            do {
                let policy = try await importer.retention()
                rule.selectItem(at: [0, 30, 90].firstIndex(of: policy.days) ?? 0)
                existing.state = policy.since == nil && policy.days > 0 ? .on : .off
                items = try await importer.cleanupItems()
                let restored = try await importer.recoverableTrashCount()
                pending = try await importer.pendingOwnedCaptures()
                let size = ByteCountFormatter.string(fromByteCount: items.reduce(0) { $0 + $1.record.image.byteCount }, countStyle: .file)
                let unique = items.filter { !$0.verifiedOriginal }.count
                summary.stringValue = text("可整理 \(items.count) 张，共 \(size)。其中 \(unique) 张没有已验证的外部原图。废纸篓可找回 \(restored) 张，待收录 \(pending.count) 张。",
                    "\(items.count) eligible (\(size)), including \(unique) without a verified external original. \(restored) recoverable from Trash. \(pending.count) pending capture(s).")
                status.stringValue = text("清空系统废纸篓后才会释放空间。", "Empty the system Trash to release disk space.")
                actions[1].isEnabled = !items.isEmpty; actions[2].isEnabled = restored > 0
                actions[3].isEnabled = !pending.isEmpty && !captureBusy(); actions[4].isEnabled = true
            } catch { failed = true }
            if failed {
                status.stringValue = text("部分资料未能处理。请检查磁盘与废纸篓权限，再次打开管理查看当前状态。",
                    "Some items could not be processed. Check disk and Trash access, then reopen Manage to refresh.")
            }
        }
    }

    @objc private func saveRule() {
        let days = [0, 30, 90][rule.indexOfSelectedItem], include = existing.state == .on
        run { try await self.importer.setRetention(days: days, includeExisting: include) }
    }
    @objc private func clean() {
        let selected = items
        run { try await self.importer.cleanup(selected); await self.changed() }
    }
    @objc private func restore() {
        run { try await self.importer.restoreTrash(); await self.changed() }
    }
    @objc private func collect() {
        guard !captureBusy() else { return }
        let selected = pending
        run {
            var firstError: Error?
            for url in selected {
                do { _ = try await self.importer.collectOwnedCapture(url) }
                catch { firstError = firstError ?? error }
            }
            await self.changed()
            if let firstError { throw firstError }
        }
    }
    @objc private func revealCaptures() {
        Task {
            let urls = try? await importer.captureOriginals()
            if let urls, !urls.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(urls) }
            else { status.stringValue = text("没有保留的捕获原件。", "No saved capture originals.") }
        }
    }
}
