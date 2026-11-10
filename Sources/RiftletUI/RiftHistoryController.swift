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
/// Loaded bitmap dimensions must likewise not increase the window's fitting
/// width; both the detail and original views fit inside their existing bounds.
private final class HistoryPreviewImageView: NSImageView {
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }
}

/// Wrap the action hint inside its detail column when AppKit measures the window.
private final class HistoryActionNote: NSTextField {
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        let textWidth = alignmentRect(forFrame: bounds).width
        if textWidth > 0, preferredMaxLayoutWidth != textWidth {
            preferredMaxLayoutWidth = textWidth
        }
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
    private let onDisplayStyleChanged: (HistoryDisplayStyle) -> Void
    public private(set) var displayStyle: HistoryDisplayStyle
    public private(set) var selectedRecordID: UUID?
    private var suppressSelection = false
    private let styleSelector = NSSegmentedControl(images: [
        NSImage(systemSymbolName: "list.bullet", accessibilityDescription: "列表")!,
        NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: "图像网格")!
    ], trackingMode: .selectOne, target: nil, action: nil)
    private let gridFilter = NSPopUpButton()
    private let gridTitle = NSTextField(labelWithString: "截图历史")
    private var tableScroll: NSScrollView!
    private var detailScroll: NSScrollView!
    private var listWidths: [NSLayoutConstraint] = []
    private lazy var grid = HistoryGridRenderer(directory: mediaDirectory,
        onSelection: { [weak self] in self?.selectRecord($0) },
        onPreview: { [weak self] in self?.previewSelected() }, stateText: Self.stateText,
        mayLoad: { [weak self] in
            self?.historyWindow.isVisible == true && self?.displayStyle == .imageGrid
        })
    private let search = NSSearchField()
    private var filterIndex = 0
    private let table = HistoryTableView()
    private let detailImage = HistoryPreviewImageView()
    private let imageBackdrop = NSVisualEffectView()
    private let detailTitle = NSTextField(wrappingLabelWithString: "选择一张截图")
    private let detailMetadata = NSTextField(wrappingLabelWithString: "")
    private let detailState = NSTextField(wrappingLabelWithString: "原图与本地记录始终保留。")
    private var detailID: UUID?
    private var detailAsset: ImportedAsset?
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
    private let restoreButton = NSButton(title: "恢复到桌面", target: nil, action: nil)
    private let removeButton = NSButton(title: "移出可见队列", target: nil, action: nil)
    private let revealButton = NSButton(title: "在 Finder 中显示", target: nil, action: nil)
    private let originalButton = NSButton(title: "查看原图", target: nil, action: nil)
    private let newerButton = NSButton(title: "上一页", target: nil, action: nil)
    private let olderButton = NSButton(title: "下一页", target: nil, action: nil)
    private let actionNote = HistoryActionNote(wrappingLabelWithString: "")
    private var entries: [RiftHistoryEntry] = []
    private var displayed: [RiftHistoryEntry] = []
    private var pageOffset = 0
    private var hasEarlier = false
    private var hasPresented = false

    public var isVisible: Bool { historyWindow.isVisible }
    public var window: NSWindow { historyWindow }

    public init(mediaDirectory: URL, onRestore: @escaping (UUID) -> Void,
                onRemove: @escaping (UUID) -> Void, onReveal: @escaping (UUID) -> Void,
                onNextPage: (() -> Void)? = nil, onPreviousPage: (() -> Void)? = nil,
                displayStyle: HistoryDisplayStyle = .current,
                onDisplayStyleChanged: @escaping (HistoryDisplayStyle) -> Void = { _ in }) {
        self.cache = ThumbnailCache(directory: mediaDirectory)
        self.mediaDirectory = mediaDirectory
        self.onRestore = onRestore; self.onRemove = onRemove; self.onReveal = onReveal
        self.onNextPage = onNextPage; self.onPreviousPage = onPreviousPage
        self.displayStyle = displayStyle; self.onDisplayStyleChanged = onDisplayStyleChanged
        historyWindow = RiftVisualStyle.window(outerSize: NSSize(width: 808, height: 492),
            minimum: NSSize(width: 680, height: 480), title: "Riftlet — 截图历史")
        super.init()
        historyWindow.title = "截图历史"
        historyWindow.titleVisibility = .hidden
        historyWindow.identifier = .init("RiftletHistory")
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
        let size = hasPresented ? historyWindow.frame.size : NSSize(width: 808, height: 492)
        applyRendererLayout()
        refresh()
        RiftVisualStyle.restoreWindowSize(historyWindow, size: size, constrainOrigin: !hasPresented)
        historyWindow.makeKeyAndOrderFront(nil)
        RiftVisualStyle.restoreWindowSize(historyWindow, size: size, constrainOrigin: !hasPresented)
        hasPresented = true
        NSApp.activate(ignoringOtherApps: true)
        grid.refreshVisible()
    }

    /// Projection from the shared preference owner. It does not query history,
    /// dispatch a preference callback, replace detail/preview state or activate.
    public func updateDisplayStyle(_ style: HistoryDisplayStyle) {
        guard style != displayStyle else { return }
        let followsRenderer = historyWindow.firstResponder === table || historyWindow.firstResponder === grid.collection
        let anchor: UUID?
        if displayStyle == .current {
            let rows = table.rows(in: table.visibleRect)
            anchor = displayed.indices.contains(rows.location) ? displayed[rows.location].id : nil
        } else { anchor = grid.firstVisibleID }
        let size = historyWindow.frame.size
        displayStyle = style
        applyRendererLayout()
        RiftVisualStyle.restoreWindowSize(historyWindow, size: size)
        if followsRenderer { historyWindow.makeFirstResponder(style == .imageGrid ? grid.collection : table) }
        if let anchor {
            if style == .imageGrid { grid.scroll(to: anchor) }
            else if let row = displayed.firstIndex(where: { $0.id == anchor }) { table.scrollRowToVisible(row) }
        }
    }

    public func close() { previewWindow?.close(); historyWindow.close() }

    public func windowWillClose(_ notification: Notification) {
        if let previewWindow, notification.object as? NSWindow === previewWindow {
            clearPreview(); return
        }
        guard notification.object as? NSWindow === historyWindow else { return }
        detailGeneration &+= 1
        grid.setVisible(false); grid.clear()
        cache.clear(); detailID = nil; detailAsset = nil; selectedRecordID = nil
        detailImage.image = nil; previewWindow?.close(); previewWindow = nil
        displayed.removeAll()
        suppressSelection = true; table.reloadData(); suppressSelection = false
    }

    public func windowDidResize(_ notification: Notification) {
        if notification.object as? NSWindow === historyWindow { grid.resize(); return }
        guard let previewWindow, notification.object as? NSWindow === previewWindow else { return }
        requestPreview(debounce: true)
    }

    public func windowDidChangeBackingProperties(_ notification: Notification) {
        if notification.object as? NSWindow === historyWindow { grid.refreshVisible(); return }
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
        let list = NSVisualEffectView()
        list.material = .sidebar
        list.blendingMode = .behindWindow
        list.state = .active
        let previewColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("preview"))
        previewColumn.width = 72; previewColumn.minWidth = 72; previewColumn.maxWidth = 72
        let descriptionColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("description"))
        descriptionColumn.width = 172; descriptionColumn.minWidth = 148
        table.addTableColumn(previewColumn); table.addTableColumn(descriptionColumn)
        table.headerView = nil; table.rowHeight = 64; table.intercellSpacing = .zero
        table.usesAlternatingRowBackgroundColors = false; table.backgroundColor = .clear
        table.allowsMultipleSelection = false; table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.dataSource = self; table.delegate = self; table.target = self
        table.doubleAction = #selector(previewSelected)
        table.onPreview = { [weak self] in self?.previewSelected() }
        table.setAccessibilityLabel("本机截图记录；空格查看预览")
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        tableScroll = scroll
        scroll.drawsBackground = false; scroll.documentView = table
        let paging = NSStackView(views: [newerButton, olderButton]); paging.spacing = 8
        for button in [restoreButton, removeButton, revealButton, originalButton, newerButton, olderButton] {
            RiftVisualStyle.style(button); button.target = self
        }
        restoreButton.action = #selector(restoreSelected); removeButton.action = #selector(removeSelected)
        revealButton.action = #selector(revealSelected); newerButton.action = #selector(previousPage); olderButton.action = #selector(nextPage)
        originalButton.action = #selector(previewSelected)
        for (button, identifier) in [(restoreButton, "restore"), (removeButton, "remove"), (revealButton, "reveal"),
                                      (originalButton, "original"), (newerButton, "previous"), (olderButton, "next")] {
            button.identifier = .init("history." + identifier)
        }
        search.identifier = .init("history.search"); table.identifier = .init("history.current.table")
        countLabel.identifier = .init("history.count")
        countLabel.font = RiftVisualStyle.secondaryFont; countLabel.textColor = RiftVisualStyle.secondary
        styleSelector.identifier = .init("history.displayStyle")
        for (index, style) in HistoryDisplayStyle.allCases.enumerated() {
            styleSelector.setToolTip(style.title, forSegment: index)
            styleSelector.setImageScaling(.scaleProportionallyDown, forSegment: index)
        }
        styleSelector.segmentStyle = .rounded
        styleSelector.target = self; styleSelector.action = #selector(styleChanged(_:))
        styleSelector.setAccessibilityLabel("历史显示方式")
        gridFilter.identifier = .init("history.grid.filter")
        gridFilter.addItems(withTitles: ["全部截图", "待核实", "已附加", "已归档", "明确失败", "已移除"])
        gridFilter.target = self; gridFilter.action = #selector(gridFilterChanged(_:))
        gridFilter.setAccessibilityLabel("筛选当前历史页")
        gridTitle.font = .systemFont(ofSize: 23, weight: .semibold); gridTitle.textColor = .labelColor
        let heading = NSStackView(views: [gridTitle, NSView(), search, gridFilter, styleSelector])
        heading.alignment = .centerY; heading.spacing = 8
        search.widthAnchor.constraint(equalToConstant: 138).isActive = true
        for view in [scroll, grid.scrollView, paging, countLabel] {
            view.translatesAutoresizingMaskIntoConstraints = false
            list.addSubview(view)
        }
        for renderer in [scroll, grid.scrollView] {
            NSLayoutConstraint.activate([renderer.topAnchor.constraint(equalTo: list.topAnchor, constant: 12),
                renderer.leadingAnchor.constraint(equalTo: list.leadingAnchor, constant: 8),
                renderer.trailingAnchor.constraint(equalTo: list.trailingAnchor, constant: -8),
                renderer.bottomAnchor.constraint(equalTo: paging.topAnchor, constant: -8)])
        }
        paging.spacing = 4
        newerButton.title = ""; olderButton.title = ""
        newerButton.image = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: nil)
        olderButton.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)
        newerButton.setAccessibilityLabel("上一页"); olderButton.setAccessibilityLabel("下一页")
        newerButton.toolTip = "上一页"; olderButton.toolTip = "下一页"
        NSLayoutConstraint.activate([countLabel.leadingAnchor.constraint(equalTo: list.leadingAnchor, constant: 14),
            countLabel.centerYAnchor.constraint(equalTo: paging.centerYAnchor),
            countLabel.trailingAnchor.constraint(lessThanOrEqualTo: paging.leadingAnchor, constant: -4),
            paging.trailingAnchor.constraint(equalTo: list.trailingAnchor, constant: -14),
            paging.bottomAnchor.constraint(equalTo: list.bottomAnchor, constant: -12)])
        detailTitle.font = RiftVisualStyle.titleFont; detailTitle.textColor = RiftVisualStyle.ink
        detailMetadata.font = RiftVisualStyle.secondaryFont; detailMetadata.textColor = RiftVisualStyle.secondary
        detailMetadata.isSelectable = true
        detailState.font = RiftVisualStyle.bodyFont; detailState.textColor = RiftVisualStyle.ink
        actionNote.font = RiftVisualStyle.secondaryFont; actionNote.textColor = RiftVisualStyle.secondary
        for field in [detailTitle, detailMetadata, detailState, actionNote] {
            field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            RiftVisualStyle.applyTextStyle(field)
        }
        detailImage.imageScaling = .scaleProportionallyUpOrDown
        detailImage.identifier = .init("history.detail.image")
        detailImage.setAccessibilityLabel("完整比例截图预览")
        detailImage.heightAnchor.constraint(equalToConstant: 200).isActive = true
        let surface = imageBackdrop
        surface.material = .underWindowBackground
        surface.blendingMode = .withinWindow
        surface.wantsLayer = true; surface.layer?.cornerRadius = 7; surface.layer?.masksToBounds = true
        detailImage.translatesAutoresizingMaskIntoConstraints = false
        surface.addSubview(detailImage)
        NSLayoutConstraint.activate([detailImage.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 8),
            detailImage.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -8),
            detailImage.topAnchor.constraint(equalTo: surface.topAnchor, constant: 8),
            detailImage.bottomAnchor.constraint(equalTo: surface.bottomAnchor, constant: -8)])
        let viewActions = NSStackView(views: [originalButton, revealButton])
        let queueActions = NSStackView(views: [restoreButton, removeButton])
        let detail = RiftVisualStyle.documentStack([surface, detailTitle, detailMetadata, detailState,
                                                   viewActions, queueActions, actionNote], spacing: 8)
        detail.edgeInsets = NSEdgeInsets(top: 17, left: 18, bottom: 16, right: 18)
        for view in [surface, detailTitle, detailMetadata, detailState, actionNote] {
            view.widthAnchor.constraint(equalTo: detail.widthAnchor, constant: -36).isActive = true
        }
        let detailScroll = RiftVisualStyle.topAlignedScrollView()
        self.detailScroll = detailScroll
        detailScroll.drawsBackground = false
        detailScroll.documentView = detail; detail.translatesAutoresizingMaskIntoConstraints = false
        let divider = NSBox(); divider.boxType = .separator
        let headerDivider = NSBox(); headerDivider.boxType = .separator
        for view in [heading, headerDivider, list, divider, detailScroll] {
            view.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(view)
        }
        listWidths = [0.34, 0.425].map { list.widthAnchor.constraint(equalTo: content.widthAnchor, multiplier: $0) }
        NSLayoutConstraint.activate([
            heading.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 17),
            heading.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -17),
            heading.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            headerDivider.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 12),
            headerDivider.leadingAnchor.constraint(equalTo: content.leadingAnchor), headerDivider.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            list.topAnchor.constraint(equalTo: headerDivider.bottomAnchor), list.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            list.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            divider.leadingAnchor.constraint(equalTo: list.trailingAnchor), divider.widthAnchor.constraint(equalToConstant: 1),
            divider.topAnchor.constraint(equalTo: list.topAnchor), divider.bottomAnchor.constraint(equalTo: list.bottomAnchor),
            detailScroll.leadingAnchor.constraint(equalTo: divider.trailingAnchor), detailScroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            detailScroll.topAnchor.constraint(equalTo: list.topAnchor), detailScroll.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            detail.widthAnchor.constraint(equalTo: detailScroll.contentView.widthAnchor),
            detail.leadingAnchor.constraint(equalTo: detailScroll.contentView.leadingAnchor), detail.topAnchor.constraint(equalTo: detailScroll.contentView.topAnchor)])
        applyRendererLayout()
        updateActions()
    }

    private func applyRendererLayout() {
        let isGrid = displayStyle == .imageGrid
        // Retire native grid items before removing their viewport constraints.
        // Otherwise AppKit lays out cached visible items in the collapsing view.
        if !isGrid { grid.setVisible(false) }
        listWidths[isGrid ? 0 : 1].isActive = false
        listWidths[isGrid ? 1 : 0].isActive = true
        tableScroll.isHidden = isGrid
        styleSelector.selectedSegment = isGrid ? 1 : 0
        originalButton.isHidden = selectedEntry == nil
        originalButton.isEnabled = selectedEntry != nil
        historyWindow.backgroundColor = .windowBackgroundColor
        detailTitle.textColor = .labelColor
        detailState.textColor = .labelColor
        detailMetadata.textColor = .secondaryLabelColor
        for field in [detailTitle, detailState, detailMetadata] { RiftVisualStyle.applyTextStyle(field) }
        historyWindow.contentView?.layoutSubtreeIfNeeded()
        grid.select(selectedRecordID); grid.setVisible(isGrid)
    }

    private var selectedEntry: RiftHistoryEntry? {
        guard let selectedRecordID else { return nil }
        return displayed.first { $0.id == selectedRecordID }
    }

    private func refresh() {
        let selectedID = selectedRecordID
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
        gridFilter.selectItem(at: filterIndex)
        selectedRecordID = selectedID.flatMap { id in displayed.contains(where: { $0.id == id }) ? id : nil }
        suppressSelection = true
        table.reloadData()
        if let selectedID, let row = displayed.firstIndex(where: { $0.id == selectedID }) {
            table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        } else { table.deselectAll(nil) }
        suppressSelection = false
        grid.update(entries: displayed, selection: selectedRecordID)
        countLabel.stringValue = "\(displayed.count) / \(entries.count) 张 · 第 \(pageOffset / HistoryPresentation.pageSize + 1) 页"
        updateActions()
    }

    private func updateActions() {
        restoreButton.isEnabled = selectedEntry?.canRestoreToRift == true
        removeButton.isEnabled = selectedEntry?.canRemoveFromRift == true
        revealButton.isEnabled = selectedEntry != nil
        originalButton.isEnabled = selectedEntry != nil
        originalButton.isHidden = selectedEntry == nil
        restoreButton.isHidden = !restoreButton.isEnabled
        removeButton.isHidden = !removeButton.isEnabled
        revealButton.isHidden = selectedEntry == nil
        let notes = [restoreButton.isEnabled ? "恢复到桌面后，可再次点选。" : nil,
                     removeButton.isEnabled ? "移出队列不会删除私有副本、系统原图或聊天附件。" : nil].compactMap { $0 }
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
            detailID = nil; detailAsset = nil; detailImage.image = nil; imageBackdrop.isHidden = true; detailTitle.stringValue = "截图会留在这里"
            detailMetadata.stringValue = ""; detailState.stringValue = "选择一张截图，查看原比例预览与本地状态。"
            for field in [detailTitle, detailMetadata, detailState] { RiftVisualStyle.applyTextStyle(field) }
            return
        }
        let sameBitmap = detailID == entry.id && detailAsset == entry.record.image && detailImage.image != nil
        detailID = entry.id; detailAsset = entry.record.image
        if !sameBitmap { detailImage.image = nil }
        imageBackdrop.isHidden = false
        detailTitle.stringValue = Self.captureTitle(entry)
        detailMetadata.stringValue = "\(entry.record.image.pixelWidth) × \(entry.record.image.pixelHeight)　·　\(Self.stateText(entry))"
        detailMetadata.toolTip = entry.id.uuidString
        let explanation = entry.needsVerification ? "尚不能确认这次附加的结果。原图和本地记录均保留，不会自动再次附加。" :
            entry.record.status == .used ? "后台已取得独立完成证明。原始系统截图仍然保留。" :
            entry.record.status == .failed && !entry.isConfirmedFailure ? "本次未附加不代表已证明远端上传失败；不会自动重传。" : "附加、归档或移除后，本地记录仍保留。可用操作会随记录状态更新。"
        detailState.stringValue = explanation
        detailImage.setAccessibilityLabel(Self.previewDescription(entry))
        for field in [detailTitle, detailMetadata, detailState] { RiftVisualStyle.applyTextStyle(field) }
        if !sameBitmap { cache.image(for: entry.record.image, maxPixelSize: Int(320 * historyWindow.backingScaleFactor)) { [weak self] image in
            guard let self, self.detailID == entry.id, self.detailGeneration == generation,
                  self.historyWindow.isVisible else { return }
            self.detailImage.image = image.map { NSImage(cgImage: $0, size: .zero) }
        } }
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
        grid.refreshVisible()
    }

    @objc private func changePreviewZoom(_ sender: NSSegmentedControl) {
        previewZoom = sender.selectedSegment == 0 ? nil : (sender.selectedSegment == 1 ? 1 : 2)
        requestPreview(clearImage: true)
    }
    @objc private func revealPreview() { if let entry = previewEntry { onReveal(entry.id) } }

    @objc private func styleChanged(_ sender: NSSegmentedControl) {
        guard HistoryDisplayStyle.allCases.indices.contains(sender.selectedSegment) else { return }
        let requested = HistoryDisplayStyle.allCases[sender.selectedSegment]
        sender.selectedSegment = displayStyle == .current ? 0 : 1
        if requested != displayStyle { onDisplayStyleChanged(requested) }
    }
    @objc private func gridFilterChanged(_ sender: NSPopUpButton) { filterIndex = sender.indexOfSelectedItem; refresh() }
    public func controlTextDidChange(_ obj: Notification) { refresh() }
    public func tableViewSelectionDidChange(_ notification: Notification) {
        guard !suppressSelection, displayStyle == .current else { return }
        selectRecord(displayed.indices.contains(table.selectedRow) ? displayed[table.selectedRow].id : nil)
    }
    private func selectRecord(_ id: UUID?) {
        selectedRecordID = id
        suppressSelection = true
        if let id, let row = displayed.firstIndex(where: { $0.id == id }) {
            table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        } else { table.deselectAll(nil) }
        suppressSelection = false
        grid.select(id); updateActions()
    }
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
