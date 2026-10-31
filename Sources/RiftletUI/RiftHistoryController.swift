import AppKit
import RiftletCore

private final class HistoryTextCell: NSTableCellView {
    let title = NSTextField(labelWithString: "")
    let subtitle = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        title.font = RiftVisualStyle.bodyFont
        title.textColor = RiftVisualStyle.ink
        subtitle.font = RiftVisualStyle.secondaryFont
        subtitle.textColor = RiftVisualStyle.secondary
        title.lineBreakMode = .byTruncatingTail
        subtitle.lineBreakMode = .byTruncatingTail
        let stack = NSStackView(views: [title, subtitle])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

private final class HistoryImageCell: NSTableCellView {
    let preview = NSImageView()
    var representedID: UUID?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        preview.imageScaling = .scaleProportionallyUpOrDown
        preview.translatesAutoresizingMaskIntoConstraints = false
        preview.setAccessibilityLabel("截图预览")
        addSubview(preview)
        NSLayoutConstraint.activate([
            preview.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            preview.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            preview.centerYAnchor.constraint(equalTo: centerYAnchor),
            preview.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

/// The viewport must exist before a bitmap is decoded. An empty NSImageView's
/// intrinsic height can otherwise collapse the image area and let the footer
/// absorb the window, leaving no viewport from which to request that bitmap.
private final class HistoryPreviewImageView: NSImageView {
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }
}

/// Explicitly opened local history, with one bounded metadata page and reused
/// downsampled thumbnails. No adapter, upload, clipboard or deletion capability.
@MainActor
public final class RiftHistoryController: NSObject, NSTableViewDataSource, NSTableViewDelegate,
                                           NSSearchFieldDelegate, NSWindowDelegate {
    private let historyWindow: NSWindow
    private let cache: ThumbnailCache
    private let mediaDirectory: URL
    private let onRestore: (UUID) -> Void
    private let onRemove: (UUID) -> Void
    private let onReveal: (UUID) -> Void
    private let onNextPage: (() -> Void)?
    private let onPreviousPage: (() -> Void)?
    private let search = NSSearchField()
    private var filterIndex = 0
    private var filterButtons: [NSButton] = []
    private let table = HistoryTableView()
    private let detailImage = NSImageView()
    private let detailTitle = NSTextField(wrappingLabelWithString: "选择一张截图")
    private let detailMetadata = NSTextField(wrappingLabelWithString: "")
    private let detailState = NSTextField(wrappingLabelWithString: "原图与本地记录始终保留。")
    private var detailID: UUID?
    private var detailGeneration: UInt = 0
    private var previewWindow: NSWindow?
    private var previewImage: NSImageView?
    private var previewStatus: NSTextField?
    private var previewScroll: NSScrollView?
    private var previewZoom: Double?
    public var onPreviewVisibilityChanged: ((Bool) -> Void)?
    private var previewEntry: RiftHistoryEntry?
    private var previewVerifiedAsset: ImportedAsset?
    private let previewOwner = UUID()
    private var previewEpoch: UInt = 0
    private var previewResize: DispatchWorkItem?
    private var previewFileObserver: HistoryPreviewFileObserver?
    private let countLabel = NSTextField(labelWithString: "")
    private let restoreButton = NSButton(title: "放回裂缝", target: nil, action: nil)
    private let removeButton = NSButton(title: "移出可见队列", target: nil, action: nil)
    private let revealButton = NSButton(title: "在 Finder 中显示", target: nil, action: nil)
    private let newerButton = NSButton(title: "上一页", target: nil, action: nil)
    private let olderButton = NSButton(title: "下一页", target: nil, action: nil)
    private let actionNote = RiftVisualStyle.label("放回裂缝不会立即上传。移出队列不会删除本地原图或聊天附件。", role: "secondary")
    private var entries: [RiftHistoryEntry] = []
    private var displayed: [RiftHistoryEntry] = []
    private var pageOffset = 0
    private var hasEarlier = false
    private var hasPresented = false

    public var isVisible: Bool { historyWindow.isVisible }

    public init(mediaDirectory: URL, onRestore: @escaping (UUID) -> Void,
                onRemove: @escaping (UUID) -> Void, onReveal: @escaping (UUID) -> Void,
                onNextPage: (() -> Void)? = nil, onPreviousPage: (() -> Void)? = nil) {
        self.cache = ThumbnailCache(directory: mediaDirectory)
        self.mediaDirectory = mediaDirectory
        self.onRestore = onRestore; self.onRemove = onRemove; self.onReveal = onReveal
        self.onNextPage = onNextPage; self.onPreviousPage = onPreviousPage
        historyWindow = RiftVisualStyle.window(outerSize: NSSize(width: 760, height: 560),
            minimum: NSSize(width: 680, height: 480), title: "Riftlet — 截图历史")
        super.init()
        historyWindow.title = "Riftlet — 截图历史"
        historyWindow.isReleasedWhenClosed = false
        historyWindow.minSize = NSSize(width: 680, height: 480)
        historyWindow.delegate = self
        configureContent()
        historyWindow.center()
    }

    /// Applying observations never orders the history window front or activates
    /// Riftlet. Only an explicit history action calls show().
    public func update(entries: [RiftHistoryEntry], pageOffset: Int = 0, hasEarlier: Bool = false) {
        self.entries = Array(HistoryPresentation.matching(entries).prefix(HistoryPresentation.pageSize))
        self.pageOffset = max(0, pageOffset); self.hasEarlier = hasEarlier
        if historyWindow.isVisible { refresh() }
    }

    public func show() {
        let size = hasPresented ? historyWindow.frame.size : NSSize(width: 760, height: 560)
        refresh()
        RiftVisualStyle.restoreWindowSize(historyWindow, size: size, constrainOrigin: !hasPresented)
        historyWindow.makeKeyAndOrderFront(nil)
        RiftVisualStyle.restoreWindowSize(historyWindow, size: size, constrainOrigin: !hasPresented)
        hasPresented = true
        NSApp.activate(ignoringOtherApps: true)
    }

    public func close() { previewWindow?.close(); historyWindow.close() }

    public func windowWillClose(_ notification: Notification) {
        if let previewWindow, notification.object as? NSWindow === previewWindow {
            clearPreview(); return
        }
        guard notification.object as? NSWindow === historyWindow else { return }
        detailGeneration &+= 1
        cache.clear(); detailID = nil; detailImage.image = nil; previewWindow?.close(); previewWindow = nil
        displayed.removeAll()
        table.reloadData()
    }

    public func windowDidResize(_ notification: Notification) {
        guard let previewWindow, notification.object as? NSWindow === previewWindow else { return }
        requestPreview(debounce: true)
    }

    public func windowDidChangeBackingProperties(_ notification: Notification) {
        guard let previewWindow, notification.object as? NSWindow === previewWindow else { return }
        requestPreview(clearImage: true)
    }

    public func windowDidChangeScreen(_ notification: Notification) {
        guard let previewWindow, notification.object as? NSWindow === previewWindow else { return }
        requestPreview(clearImage: true)
    }

    private func configureContent() {
        guard let content = historyWindow.contentView else { return }
        search.placeholderString = "搜索本页"; search.setAccessibilityLabel("搜索当前历史页")
        search.delegate = self; search.sendsSearchStringImmediately = true
        let sidebar = NSVisualEffectView(); sidebar.material = .sidebar; sidebar.blendingMode = .behindWindow
        let nav = RiftVisualStyle.vertical([RiftVisualStyle.label("本机截图", role: "heading")], spacing: 4)
        let symbols = ["photo.on.rectangle", "clock", "paperclip", "archivebox", "exclamationmark.circle", "minus.circle"]
        for (i, name) in ["全部截图", "待核实", "已附加", "已归档", "明确失败", "已移除"].enumerated() {
            let button = RiftSidebarButton(title: name, target: self, action: #selector(filterChanged(_:)))
            button.tag = i; button.symbolName = symbols[i]; button.setButtonType(.pushOnPushOff)
            button.font = RiftVisualStyle.bodyFont; button.alignment = .left
            button.heightAnchor.constraint(equalToConstant: 36).isActive = true
            button.widthAnchor.constraint(equalToConstant: 128).isActive = true
            filterButtons.append(button); nav.addArrangedSubview(button)
        }
        nav.addArrangedSubview(RiftVisualStyle.label("原图始终保留", role: "secondary"))
        nav.translatesAutoresizingMaskIntoConstraints = false; sidebar.addSubview(nav)
        NSLayoutConstraint.activate([nav.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 12),
            nav.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 24)])
        let list = NSView()
        let previewColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("preview"))
        previewColumn.width = 72; previewColumn.minWidth = 72; previewColumn.maxWidth = 72
        let descriptionColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("description"))
        descriptionColumn.width = 172; descriptionColumn.minWidth = 148
        table.addTableColumn(previewColumn); table.addTableColumn(descriptionColumn)
        table.headerView = nil; table.rowHeight = 64; table.intercellSpacing = .zero
        table.usesAlternatingRowBackgroundColors = false; table.backgroundColor = RiftVisualStyle.window
        table.allowsMultipleSelection = false; table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.dataSource = self; table.delegate = self; table.target = self
        table.doubleAction = #selector(previewSelected)
        table.onPreview = { [weak self] in self?.previewSelected() }
        table.setAccessibilityLabel("本机截图记录；空格查看预览")
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        scroll.drawsBackground = false; scroll.documentView = table
        let paging = NSStackView(views: [newerButton, olderButton]); paging.spacing = 8
        for button in [restoreButton, removeButton, revealButton, newerButton, olderButton] {
            RiftVisualStyle.style(button); button.target = self
        }
        restoreButton.action = #selector(restoreSelected); removeButton.action = #selector(removeSelected)
        revealButton.action = #selector(revealSelected); newerButton.action = #selector(previousPage); olderButton.action = #selector(nextPage)
        countLabel.font = RiftVisualStyle.secondaryFont; countLabel.textColor = RiftVisualStyle.secondary
        for view in [search, scroll, paging, countLabel] { view.translatesAutoresizingMaskIntoConstraints = false; list.addSubview(view) }
        NSLayoutConstraint.activate([search.leadingAnchor.constraint(equalTo: list.leadingAnchor, constant: 12),
            search.trailingAnchor.constraint(equalTo: list.trailingAnchor, constant: -12), search.topAnchor.constraint(equalTo: list.topAnchor, constant: 16),
            scroll.topAnchor.constraint(equalTo: search.bottomAnchor, constant: 12), scroll.leadingAnchor.constraint(equalTo: list.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: list.trailingAnchor), scroll.bottomAnchor.constraint(equalTo: countLabel.topAnchor, constant: -8),
            countLabel.leadingAnchor.constraint(equalTo: list.leadingAnchor, constant: 12),
            countLabel.bottomAnchor.constraint(equalTo: paging.topAnchor, constant: -8),
            paging.leadingAnchor.constraint(equalTo: list.leadingAnchor, constant: 12), paging.bottomAnchor.constraint(equalTo: list.bottomAnchor, constant: -16)])
        detailTitle.font = RiftVisualStyle.titleFont; detailTitle.textColor = RiftVisualStyle.ink
        detailMetadata.font = RiftVisualStyle.secondaryFont; detailMetadata.textColor = RiftVisualStyle.secondary
        detailMetadata.isSelectable = true
        detailState.font = RiftVisualStyle.bodyFont; detailState.textColor = RiftVisualStyle.ink
        for field in [detailTitle, detailMetadata, detailState] {
            field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            RiftVisualStyle.applyTextStyle(field)
        }
        detailImage.imageScaling = .scaleProportionallyUpOrDown
        detailImage.identifier = .init("history.detail.image")
        detailImage.setAccessibilityLabel("完整比例截图预览")
        detailImage.heightAnchor.constraint(equalToConstant: 200).isActive = true
        let detail = RiftVisualStyle.documentStack([detailImage, detailTitle, detailMetadata, detailState, revealButton, restoreButton, removeButton, actionNote], spacing: 12)
        detail.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
        for view in detail.arrangedSubviews where !(view is NSButton) { view.widthAnchor.constraint(equalTo: detail.widthAnchor, constant: -48).isActive = true }
        let detailScroll = RiftVisualStyle.topAlignedScrollView()
        detailScroll.drawsBackground = false; detailScroll.documentView = detail; detail.translatesAutoresizingMaskIntoConstraints = false
        let separator = NSBox(); separator.boxType = .separator
        for view in [sidebar, list, separator, detailScroll] { view.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(view) }
        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: content.leadingAnchor), sidebar.topAnchor.constraint(equalTo: content.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: content.bottomAnchor), sidebar.widthAnchor.constraint(equalToConstant: 152),
            list.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor), list.topAnchor.constraint(equalTo: content.topAnchor),
            list.bottomAnchor.constraint(equalTo: content.bottomAnchor), list.widthAnchor.constraint(equalToConstant: 260),
            separator.leadingAnchor.constraint(equalTo: list.trailingAnchor), separator.widthAnchor.constraint(equalToConstant: 1),
            separator.topAnchor.constraint(equalTo: content.topAnchor), separator.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            detailScroll.leadingAnchor.constraint(equalTo: separator.trailingAnchor), detailScroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            detailScroll.topAnchor.constraint(equalTo: content.topAnchor), detailScroll.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            detail.widthAnchor.constraint(equalTo: detailScroll.contentView.widthAnchor),
            detail.leadingAnchor.constraint(equalTo: detailScroll.contentView.leadingAnchor), detail.topAnchor.constraint(equalTo: detailScroll.contentView.topAnchor)])
        updateActions()
    }

    private var selectedEntry: RiftHistoryEntry? {
        guard displayed.indices.contains(table.selectedRow) else { return nil }
        return displayed[table.selectedRow]
    }

    private func refresh() {
        let selectedID = selectedEntry?.id
        let filtered = entries.filter { entry in
            switch filterIndex {
            case 1: return entry.needsVerification
            case 2: return entry.record.status == .used
            case 3: return entry.record.visibility == .archived
            case 4: return entry.isConfirmedFailure
            case 5: return entry.record.visibility == .removed
            default: return true
            }
        }
        let query = search.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        displayed = HistoryPresentation.matching(filtered).filter { entry in
            query.isEmpty || !HistoryPresentation.matching([entry], query: query).isEmpty || Self.stateText(entry).localizedCaseInsensitiveContains(query)
        }
        for button in filterButtons { button.state = button.tag == filterIndex ? .on : .off; button.contentTintColor = button.state == .on ? RiftVisualStyle.accent : RiftVisualStyle.ink }
        table.reloadData()
        if let selectedID, let row = displayed.firstIndex(where: { $0.id == selectedID }) {
            table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        } else { table.deselectAll(nil) }
        countLabel.stringValue = "本页 \(displayed.count) / \(entries.count) 条 · 第 \(pageOffset / HistoryPresentation.pageSize + 1) 页"
        updateActions()
    }

    private func updateActions() {
        restoreButton.isEnabled = selectedEntry?.canRestoreToRift == true
        removeButton.isEnabled = selectedEntry?.canRemoveFromRift == true
        revealButton.isEnabled = selectedEntry != nil
        restoreButton.isHidden = !restoreButton.isEnabled
        removeButton.isHidden = !removeButton.isEnabled
        revealButton.isHidden = selectedEntry == nil
        let notes = [restoreButton.isEnabled ? "放回裂缝不会立即上传。" : nil,
                     removeButton.isEnabled ? "移出队列不会删除本地原图或聊天附件。" : nil].compactMap { $0 }
        actionNote.stringValue = notes.joined()
        RiftVisualStyle.applyTextStyle(actionNote)
        actionNote.isHidden = notes.isEmpty
        newerButton.isEnabled = pageOffset > 0 && onPreviousPage != nil
        olderButton.isEnabled = hasEarlier && onNextPage != nil
        updateDetail()
    }

    private static func stateText(_ entry: RiftHistoryEntry) -> String {
        if entry.needsVerification { return "结果待核实 · 不会再次附加" }
        if entry.record.status == .used { return "已附加" }
        if entry.isConfirmedFailure { return "已确认失败 · 图片保留" }
        if entry.record.status == .missing { return "本地副本不可用" }
        if entry.record.visibility == .archived { return "已归档" }
        if entry.record.visibility == .removed { return "已移出裂缝" }
        if entry.record.status == .failed { return "未附加 · 图片保留" }
        return "待附加"
    }
    private func updateDetail() {
        detailGeneration &+= 1
        let generation = detailGeneration
        guard let entry = selectedEntry else {
            previewWindow?.close()
            detailID = nil; detailImage.image = nil; detailImage.isHidden = true; detailTitle.stringValue = "截图会留在这里"
            detailMetadata.stringValue = ""; detailState.stringValue = "选择一张截图，查看原比例预览与本地状态。"
            for field in [detailTitle, detailMetadata, detailState] { RiftVisualStyle.applyTextStyle(field) }
            return
        }
        detailID = entry.id; detailImage.image = nil; detailImage.isHidden = false
        detailTitle.stringValue = Self.captureTitle(entry)
        detailMetadata.stringValue = "\(entry.record.image.pixelWidth) × \(entry.record.image.pixelHeight)\n编号 \(entry.id.uuidString.prefix(8))"
        detailMetadata.toolTip = entry.id.uuidString
        let explanation = entry.needsVerification ? "尚不能确认这次附加的结果。原图和本地记录均保留，不会自动再次附加。" :
            entry.record.status == .used ? "后台已取得独立完成证明。原始系统截图仍然保留。" :
            entry.record.status == .failed && !entry.isConfirmedFailure ? "本次未附加不代表已证明远端上传失败；不会自动重传。" : "附加、归档或移除后，本地记录仍保留。可用操作会随记录状态更新。"
        detailState.stringValue = Self.stateText(entry) + "\n" + explanation
        detailImage.setAccessibilityLabel(Self.previewDescription(entry))
        for field in [detailTitle, detailMetadata, detailState] { RiftVisualStyle.applyTextStyle(field) }
        cache.image(for: entry.record.image, maxPixelSize: Int(320 * historyWindow.backingScaleFactor)) { [weak self] image in
            guard let self, self.detailID == entry.id, self.detailGeneration == generation,
                  self.historyWindow.isVisible else { return }
            self.detailImage.image = image.map { NSImage(cgImage: $0, size: .zero) }
        }
        if previewWindow != nil {
            let changed = previewEntry?.record.image != entry.record.image
            previewEntry = entry
            updatePreviewIdentity()
            if changed { observePreviewFile(); requestPreview(clearImage: true) }
        }
    }
    @objc private func previewSelected() {
        guard let entry = selectedEntry else { return }; openOriginal(entry: entry)
    }
    public func openOriginal(id: UUID) {
        guard let entry = entries.first(where: { $0.id == id }) else { return }
        openOriginal(entry: entry)
    }
    /// Caller supplies an original local record, never a thumbnail bitmap.
    public func openOriginal(entry: RiftHistoryEntry) {
        if let panel = previewWindow {
            previewEntry = entry; updatePreviewIdentity(); observePreviewFile()
            requestPreview(clearImage: true); panel.makeKeyAndOrderFront(nil); return
        }
        let panel = HistoryPreviewWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        panel.identifier = .init("RiftletHistoryPreview")
        panel.isReleasedWhenClosed = false; panel.backgroundColor = RiftVisualStyle.window
        panel.minSize = NSSize(width: 360, height: 280); panel.delegate = self
        let view = HistoryPreviewImageView(); view.identifier = .init("history.preview.image")
        view.imageScaling = .scaleProportionallyDown
        let status = RiftVisualStyle.label("正在加载预览…", role: "secondary")
        status.identifier = .init("history.preview.status")
        let reveal = NSButton(title: "在 Finder 中显示", target: self, action: #selector(revealPreview))
        RiftVisualStyle.style(reveal)
        let zoom = NSSegmentedControl(labels: ["适合", "100%", "200%"], trackingMode: .selectOne, target: self, action: #selector(changePreviewZoom(_:)))
        zoom.selectedSegment = 0; zoom.identifier = .init("history.preview.zoom"); zoom.setAccessibilityLabel("原图缩放：适合、100% 逻辑尺寸、200%")
        // A status transition must not resize the image viewport. Keep status
        // on its own fixed single-line row; its full value remains accessible.
        status.maximumNumberOfLines = 1; status.lineBreakMode = .byTruncatingTail
        status.heightAnchor.constraint(equalToConstant: 18).isActive = true
        let actions = NSStackView(views: [zoom, NSView(), reveal]); actions.spacing = 12
        actions.heightAnchor.constraint(equalToConstant: 28).isActive = true
        let footer = NSStackView(views: [status, actions]); footer.orientation = .vertical
        footer.alignment = .leading; footer.spacing = 6
        status.widthAnchor.constraint(equalTo: footer.widthAnchor).isActive = true
        actions.widthAnchor.constraint(equalTo: footer.widthAnchor).isActive = true
        footer.heightAnchor.constraint(equalToConstant: 52).isActive = true
        let scroll = NSScrollView()
        // Fit is a viewport, not a scrolling canvas. Native scrollbar policy
        // may settle asynchronously after presentation; no gutters are needed
        // until the user explicitly chooses a zoomed original.
        scroll.hasHorizontalScroller = false; scroll.hasVerticalScroller = false
        scroll.autohidesScrollers = false; scroll.documentView = view; scroll.drawsBackground = false
        previewScroll = scroll; previewZoom = nil
        footer.setContentHuggingPriority(.defaultHigh, for: .vertical)
        footer.setContentCompressionResistancePriority(.required, for: .vertical)
        status.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        if let content = panel.contentView {
            for item in [scroll, footer] { item.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(item) }
            NSLayoutConstraint.activate([
                scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
                scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
                scroll.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
                scroll.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -12),
                scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 1),
                footer.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
                footer.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
                footer.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
                footer.heightAnchor.constraint(greaterThanOrEqualToConstant: 28)])
        }
        previewWindow = panel; previewImage = view; previewStatus = status; previewEntry = entry
        updatePreviewIdentity(); panel.center(); panel.makeKeyAndOrderFront(nil)
        onPreviewVisibilityChanged?(true)
        observePreviewFile(); requestPreview(clearImage: true)
    }

    private static func captureTitle(_ entry: RiftHistoryEntry) -> String {
        let formatter = DateFormatter(); formatter.dateStyle = .medium; formatter.timeStyle = .medium
        return "截图 · " + formatter.string(from: HistoryPresentation.captureDate(for: entry))
    }

    private static func previewDescription(_ entry: RiftHistoryEntry) -> String {
        "\(captureTitle(entry))，\(entry.record.image.pixelWidth) × \(entry.record.image.pixelHeight)，\(stateText(entry))，编号 \(entry.id.uuidString.prefix(8))。Escape 或空格关闭预览。"
    }

    private func updatePreviewIdentity() {
        guard let entry = previewEntry else { return }
        previewWindow?.title = Self.captureTitle(entry) + " · " + String(entry.id.uuidString.prefix(8))
        previewImage?.setAccessibilityLabel(Self.previewDescription(entry))
    }

    private func observePreviewFile() {
        previewFileObserver?.cancel(); previewFileObserver = nil
        guard let entry = previewEntry else { return }
        let epochAsset = entry.record.image
        guard !epochAsset.fileName.isEmpty, epochAsset.fileName != ".", epochAsset.fileName != "..",
              epochAsset.fileName == URL(fileURLWithPath: epochAsset.fileName).lastPathComponent else { return }
        previewFileObserver = HistoryPreviewFileObserver(url: mediaDirectory.appendingPathComponent(epochAsset.fileName)) { [weak self] in
            guard let self, self.previewEntry?.record.image == epochAsset, self.previewWindow != nil else { return }
            self.observePreviewFile(); self.requestPreview(clearImage: true)
        }
    }

    private func requestPreview(debounce: Bool = false, clearImage: Bool = false) {
        previewEpoch &+= 1
        let epoch = previewEpoch
        previewResize?.cancel(); previewResize = nil
        HistoryPreviewLoader.shared.invalidate(owner: previewOwner)
        guard let panel = previewWindow, let entry = previewEntry, let view = previewImage else { return }
        previewScroll?.hasHorizontalScroller = previewZoom != nil
        previewScroll?.hasVerticalScroller = previewZoom != nil
        panel.contentView?.layoutSubtreeIfNeeded()
        previewScroll?.tile()
        let canvas = previewZoom.map { zoom in CGSize(width: Double(entry.record.image.pixelWidth) * zoom, height: Double(entry.record.image.pixelHeight) * zoom) } ?? previewScroll?.contentSize ?? view.bounds.size
        view.frame = CGRect(origin: .zero, size: canvas)
        if clearImage || previewVerifiedAsset != entry.record.image {
            // ThumbnailCache has a display-only asset key, not a checked file
            // identity/hash. Never place that unverified bitmap under this
            // preview's title while a potentially replaced file is validated.
            view.image = nil; previewVerifiedAsset = nil
            view.imageScaling = .scaleProportionallyDown
        }
        previewStatus?.stringValue = view.image == nil ? "正在加载预览…" : "正在加载清晰预览…"
        let load = DispatchWorkItem { [weak self, weak panel] in
            guard let self, let panel, self.previewWindow === panel, self.previewEpoch == epoch,
                  self.previewEntry?.record.image == entry.record.image, panel.isVisible else { return }
            panel.contentView?.layoutSubtreeIfNeeded()
            self.previewScroll?.tile()
            let viewport: CGSize
            if let zoom = self.previewZoom {
                viewport = CGSize(width: Double(entry.record.image.pixelWidth) * zoom, height: Double(entry.record.image.pixelHeight) * zoom)
            } else { viewport = self.previewScroll?.contentSize ?? view.bounds.size }
            view.frame = CGRect(origin: .zero, size: viewport)
            guard viewport.width > 0, viewport.height > 0 else { return }
            let request = HistoryPreviewRequest(asset: entry.record.image, directory: self.mediaDirectory,
                viewport: viewport, backing: panel.backingScaleFactor)
            HistoryPreviewLoader.shared.request(owner: self.previewOwner, request: request,
                invalidated: { [weak self] in self?.previewWindow?.close() }) { [weak self, weak panel] result in
                    guard let self, let panel, self.previewWindow === panel, self.previewEpoch == epoch,
                          self.previewEntry?.record.image == entry.record.image, panel.isVisible else { return }
                    switch result {
                    case .success(let loaded) where loaded.identity.matches(loaded.url):
                        self.previewImage?.image = NSImage(cgImage: loaded.image,
                            size: loaded.displaySize(backing: panel.backingScaleFactor))
                        self.previewVerifiedAsset = entry.record.image
                        self.previewImage?.imageScaling = self.previewZoom == nil ? .scaleProportionallyDown : .scaleProportionallyUpOrDown
                        self.previewStatus?.stringValue = self.previewZoom == nil ? "已按窗口显示" : "原件校验预览 · 显示解码受内存上限保护"
                    default:
                        self.previewImage?.image = nil; self.previewVerifiedAsset = nil
                        self.previewStatus?.stringValue = "无法加载清晰预览，图片记录仍保留"
                    }
                }
        }
        previewResize = load
        DispatchQueue.main.asyncAfter(deadline: .now() + (debounce ? 0.120 : 0), execute: load)
    }

    private func clearPreview() {
        previewEpoch &+= 1; previewResize?.cancel(); previewResize = nil
        HistoryPreviewLoader.shared.cancel(owner: previewOwner)
        previewFileObserver?.cancel(); previewFileObserver = nil
        previewImage?.image = nil; previewImage = nil; previewStatus = nil
        previewEntry = nil; previewVerifiedAsset = nil; previewWindow = nil
        previewScroll = nil; previewZoom = nil; onPreviewVisibilityChanged?(false)
    }

    @objc private func changePreviewZoom(_ sender: NSSegmentedControl) {
        previewZoom = sender.selectedSegment == 0 ? nil : (sender.selectedSegment == 1 ? 1 : 2)
        requestPreview(clearImage: true)
    }
    @objc private func revealPreview() { if let entry = previewEntry { onReveal(entry.id) } }

    @objc private func filterChanged(_ sender: NSButton) { filterIndex = sender.tag; refresh() }
    public func controlTextDidChange(_ obj: Notification) { refresh() }
    public func tableViewSelectionDidChange(_ notification: Notification) { updateActions() }
    public func numberOfRows(in tableView: NSTableView) -> Int { displayed.count }

    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard displayed.indices.contains(row), let column = tableColumn else { return nil }
        let entry = displayed[row]
        if column.identifier.rawValue == "preview" {
            let cell = (tableView.makeView(withIdentifier: column.identifier, owner: self) as? HistoryImageCell)
                ?? HistoryImageCell(frame: .zero)
            cell.identifier = column.identifier; cell.representedID = entry.id; cell.preview.image = nil
            let scale = historyWindow.backingScaleFactor
            cache.image(for: entry.record.image, maxPixelSize: Int(76 * scale)) { [weak cell] image in
                guard let cell, cell.representedID == entry.id else { return }
                cell.preview.image = image.map { NSImage(cgImage: $0, size: .zero) }
            }
            return cell
        }
        let cell = (tableView.makeView(withIdentifier: column.identifier, owner: self) as? HistoryTextCell)
            ?? HistoryTextCell(frame: .zero)
        cell.identifier = column.identifier
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate(Calendar.current.isDate(HistoryPresentation.captureDate(for: entry), equalTo: Date(), toGranularity: .year) ? "MMMd HHmm" : "yyMMdd HHmm")
        cell.title.stringValue = formatter.string(from: HistoryPresentation.captureDate(for: entry))
        cell.subtitle.stringValue = Self.stateText(entry)
        cell.toolTip = HistoryPresentation.dateText(for: entry) + " · " + Self.stateText(entry)
        return cell
    }

    @objc private func restoreSelected() {
        guard let entry = selectedEntry, entry.canRestoreToRift else { return }
        onRestore(entry.id)
    }

    @objc private func removeSelected() {
        guard let entry = selectedEntry, entry.canRemoveFromRift else { return }
        onRemove(entry.id)
    }

    @objc private func revealSelected() {
        guard let entry = selectedEntry else { return }
        onReveal(entry.id)
    }

    @objc private func nextPage() { guard hasEarlier else { return }; onNextPage?() }
    @objc private func previousPage() { guard pageOffset > 0 else { return }; onPreviousPage?() }
}


@MainActor
private final class HistoryTableView: NSTableView {
    var onPreview: (() -> Void)?
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 49, event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty,
           window?.firstResponder === self { onPreview?(); return }
        super.keyDown(with: event)
    }
}
@MainActor
private final class HistoryPreviewWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) { performClose(sender) }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 49, event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
            performClose(nil); return
        }
        super.keyDown(with: event)
    }
}
