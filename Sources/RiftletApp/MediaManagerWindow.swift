import AppKit
import RiftletCapture
import RiftletUI

@MainActor
final class MediaManagerWindow: NSWindowController, NSWindowDelegate {
    private let importer: PrivateAssetImporter
    private let captureBusy: () -> Bool
    private let retryMaintenance: () async throws -> Void
    private let reportFault: () -> Void
    private let changed: () async -> Void
    private let text = ProductCopy.text as (String, String) -> String
    private let summary = NSTextField(wrappingLabelWithString: "")
    private let status = NSTextField(wrappingLabelWithString: "")
    private let rule = NSPopUpButton()
    private let existing = NSButton(checkboxWithTitle: ProductCopy.text("也应用于已有截图", "Include existing screenshots"), target: nil, action: nil)
    private var cleanButton = NSButton(), restoreButton = NSButton(), collectButton = NSButton(), orphanButton = NSButton()
    private var retryButton = NSButton()
    private var busy = false
    private var refreshTask: Task<Void, Never>?
    private var visibleTimer: Timer?
    private var pending: [URL] = []
    private var lastRecoveryState: Bool?
    private var retry: (() -> Void)?
    private var refreshRequested = false

    init(importer: PrivateAssetImporter, captureBusy: @escaping () -> Bool,
         retryMaintenance: @escaping () async throws -> Void, reportFault: @escaping () -> Void, changed: @escaping () async -> Void) {
        self.importer = importer; self.captureBusy = captureBusy; self.retryMaintenance = retryMaintenance
        self.reportFault = reportFault; self.changed = changed
        let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 445), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init(window: panel)
        panel.delegate = self; panel.isReleasedWhenClosed = false
        panel.identifier = .init("RiftletMediaManager")
        panel.title = text("管理截图资料", "Manage Screenshot Storage")
        let stack = NSStackView()
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 9
        let content = NSView()
        panel.contentView = content
        content.addSubview(stack); stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 22),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -22),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 18)
        ])
        func heading(_ title: String) {
            let label = NSTextField(labelWithString: title)
            label.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
            stack.addArrangedSubview(label)
        }
        heading(text("自动整理", "Automatic cleanup"))
        rule.addItems(withTitles: [text("一直保留", "Keep indefinitely"), text("30 天", "30 days"), text("90 天", "90 days")])
        rule.target = self; rule.action = #selector(saveRule); rule.identifier = .init("media.manage.rule")
        existing.target = self; existing.action = #selector(saveRule)
        stack.addArrangedSubview(NSStackView(views: [rule, existing]))
        let explanation = NSTextField(wrappingLabelWithString: text("到期仅整理已收起且有可验证系统原图的副本。", "Only hidden copies with a verified system original are removed when due."))
        stack.addArrangedSubview(explanation)
        func button(_ zh: String, _ en: String, _ id: String, _ selector: Selector) -> NSButton {
            let control = NSButton(title: text(zh, en), target: self, action: selector)
            control.identifier = .init("media.manage." + id)
            return control
        }
        heading(text("立即整理", "Manual cleanup"))
        stack.addArrangedSubview(summary)
        cleanButton = button("检查全部可整理副本…", "Review all eligible copies…", "trash", #selector(clean))
        stack.addArrangedSubview(cleanButton)
        heading(text("找回", "Recovery"))
        restoreButton = button("从废纸篓找回", "Restore from Trash", "restore", #selector(restore))
        collectButton = button("收录待找回截图", "Recover pending captures", "recover", #selector(collect))
        stack.addArrangedSubview(NSStackView(views: [restoreButton, collectButton]))
        orphanButton = button("在 Finder 查看待找回文件", "Show recovered files in Finder", "orphans", #selector(revealOrphans))
        let originals = button("显示捕获原件", "Show capture originals", "reveal", #selector(revealCaptures))
        stack.addArrangedSubview(NSStackView(views: [originals, orphanButton]))
        stack.addArrangedSubview(status)
        retryButton = button("重试", "Try again", "retry", #selector(retryLast))
        stack.addArrangedSubview(retryButton)
        for field in [summary, status, explanation] { field.preferredMaxLayoutWidth = 510 }
        status.isHidden = true; retryButton.isHidden = true; orphanButton.isHidden = true
        [restoreButton, collectButton, cleanButton, rule, existing].forEach { $0.isEnabled = false }
        panel.center()
    }
    required init?(coder: NSCoder) { nil }

    func present() {
        showWindow(nil); window?.makeKeyAndOrderFront(nil)
        retryOutstandingMaintenance()
        if visibleTimer == nil {
            // Finder Trash changes have no app event. Only stat candidate names
            // while this panel is visible; full hashes require explicit preview.
            visibleTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.hostStateChanged() }
            }
        }
    }
    private func retryOutstandingMaintenance() {
        run(failure: text("上次资料整理未完成。请重试整理。", "The previous maintenance pass did not finish."),
            retry: { [weak self] in self?.retryOutstandingMaintenance() }) {
                try await self.retryMaintenance()
                return ""
            }
    }
    func windowDidBecomeKey(_ notification: Notification) { hostStateChanged() }
    func windowWillClose(_ notification: Notification) {
        visibleTimer?.invalidate(); visibleTimer = nil
        refreshTask?.cancel(); refreshTask = nil
    }

    func hostStateChanged() {
        guard window?.isVisible == true else { return }
        guard !busy, refreshTask == nil else { refreshRequested = true; return }
        refreshTask = Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            refreshRequested = false
            await refresh()
            guard !Task.isCancelled else { return }
            refreshTask = nil
            if refreshRequested { hostStateChanged() }
        }
    }

    private func refresh() async {
        do {
            let policy: MediaRetention?
            do { policy = try await importer.retention() }
            catch CaptureError.invalidManifest { policy = nil }
            let inventory = try await importer.cleanupSummary()
            let trash = try await importer.availableTrashCount()
            let captures = try await importer.pendingOwnedCaptures()
            let orphans = try await importer.orphanFiles()
            guard !busy, !Task.isCancelled else { return }
            pending = captures
            if let policy {
                rule.selectItem(at: [0, 30, 90].firstIndex(of: policy.days) ?? 0)
                existing.state = policy.days > 0 && policy.since == nil ? .on : .off
                existing.isEnabled = policy.days > 0
            } else {
                rule.select(nil); existing.state = .off; existing.isEnabled = false
                show(text("留存规则无法读取。重新选择保留时间可修复。", "Choose a retention period to replace the unreadable rule."))
            }
            rule.isEnabled = true
            let size = ByteCountFormatter.string(fromByteCount: inventory.bytes, countStyle: .file)
            summary.stringValue = text("待核对 \(inventory.count) 份副本（\(size)）。手动整理不限天数，可包含唯一副本。",
                "\(inventory.count) copies to review (\(size)). Manual cleanup includes all ages and may include sole copies.")
            cleanButton.isEnabled = inventory.count > 0
            restoreButton.title = text("从废纸篓找回（\(trash)）", "Restore from Trash (\(trash))")
            restoreButton.isEnabled = trash > 0
            collectButton.title = text("收录待找回截图（\(captures.count)）", "Recover captures (\(captures.count))")
            collectButton.isEnabled = !captureBusy() && !captures.isEmpty
            orphanButton.isHidden = orphans.isEmpty
            let recoveryState = !orphans.isEmpty || !captures.isEmpty
            if lastRecoveryState != recoveryState {
                lastRecoveryState = recoveryState
                await changed()
            }
        } catch {
            guard !busy, !Task.isCancelled else { return }
            show(text("资料概览读取失败。", "Could not read the storage summary."), retry: { [weak self] in self?.hostStateChanged() })
        }
    }

    private func show(_ message: String, retry: (() -> Void)? = nil) {
        self.retry = retry
        status.isHidden = message.isEmpty; status.stringValue = message; retryButton.isHidden = retry == nil
    }
    @objc private func retryLast() { retry?() }

    private func run(failure: String, retry: @escaping () -> Void, operation: @escaping () async throws -> String) {
        guard !busy else { return }
        refreshTask?.cancel(); refreshTask = nil
        busy = true
        [rule, existing, cleanButton, collectButton, restoreButton].forEach { $0.isEnabled = false }
        show(text("正在处理…", "Working…"))
        Task {
            do { show(try await operation()) }
            catch { reportFault(); show(failure, retry: retry) }
            busy = false; hostStateChanged()
        }
    }
    @objc private func saveRule() {
        let days = [0, 30, 90][rule.indexOfSelectedItem]
        let include = existing.state == .on
        persistRule(days, include)
    }
    private func persistRule(_ days: Int, _ include: Bool) {
        run(failure: text("留存规则保存失败。", "Could not save the retention rule."),
            retry: { [weak self] in self?.persistRule(days, include) }) {
            try await self.importer.setRetention(days: days, includeExisting: include)
            return self.text("留存规则已保存。", "Retention rule saved.")
        }
    }

    @objc private func clean() {
        run(failure: text("无法完成移动。请重新检查现有副本。", "Could not finish moving the copies. Review the remaining copies."),
            retry: { [weak self] in self?.clean() }) {
            let items = try await self.importer.cleanupItems()
            guard !items.isEmpty, let window = self.window, window.isVisible else { return self.text("没有可移动的副本。", "No copies available to move.") }
            let unique = items.filter { !$0.verifiedOriginal }.count
            let alert = NSAlert()
            alert.messageText = self.text("将 \(items.count) 份副本移到废纸篓？", "Move \(items.count) copies to Trash?")
            alert.informativeText = self.text("包含所有符合条件的日期。其中 \(unique) 份没有已验证的外部原件，清空废纸篓前可以找回。",
                "Includes all eligible dates. \(unique) copies have no verified external original. You can restore them before emptying Trash.")
            alert.addButton(withTitle: self.text("取消", "Cancel"))
            alert.addButton(withTitle: self.text("移到废纸篓", "Move to Trash")).identifier = .init("media.manage.confirmTrash")
            let confirmed = await withCheckedContinuation { continuation in
                alert.beginSheetModal(for: window) { continuation.resume(returning: $0 == .alertSecondButtonReturn) }
            }
            guard confirmed else { return "" }
            try await self.importer.cleanup(items)
            await self.changed()
            return self.text("已移到废纸篓，可在下方找回。", "Moved to Trash. Use Restore from Trash to undo.")
        }
    }
    @objc private func restore() {
        run(failure: text("找回未完成。请检查废纸篓中的对应文件。", "Restore incomplete. Check the matching files in Trash."), retry: { [weak self] in self?.restore() }) {
            try await self.importer.restoreTrash(); await self.changed()
            return self.text("已找回可恢复的副本。", "Available copies restored.")
        }
    }
    @objc private func collect() {
        guard !captureBusy() else { return }
        let selected = pending
        run(failure: text("部分截图未能收录。请查看捕获原件。", "Could not recover all captures. Check the capture originals."), retry: { [weak self] in self?.collect() }) {
            for url in selected { _ = try await self.importer.collectOwnedCapture(url) }
            await self.changed()
            return self.text("截图已收录。", "Captures recovered.")
        }
    }
    @objc private func revealOrphans() {
        Task {
            do {
                let files = try await importer.orphanFiles()
                if !files.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(files) }
                show(text("可在 Finder 中另存或移到废纸篓。", "Save these files elsewhere or move them to Trash in Finder."))
            } catch { show(text("待找回文件无法打开。", "Could not open the recovered files.")) }
        }
    }
    @objc private func revealCaptures() {
        Task {
            do {
                let files = try await importer.captureOriginals()
                if files.isEmpty { show(text("没有保留的捕获原件。", "No saved capture originals.")) }
                else { NSWorkspace.shared.activateFileViewerSelecting(files) }
            } catch { show(text("捕获原件无法打开。", "Could not open the capture originals.")) }
        }
    }
}
