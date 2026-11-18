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
        preview.setAccessibilityLabel(ProductCopy.text("截图预览", "Screenshot preview"))
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

/// Detail labels wrap at the column width, including when AppKit measures a resized window.
private final class HistoryDetailLabel: NSTextField {
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
    private let copy: ProductCopy
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
    private lazy var styleSelector = NSSegmentedControl(images: [
        NSImage(systemSymbolName: "list.bullet", accessibilityDescription: copy.text("列表", "List"))!,
        NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: copy.text("图像网格", "Image Grid"))!
    ], trackingMode: .selectOne, target: nil, action: nil)
    private let gridFilter = NSPopUpButton()
    private lazy var gridTitle = NSTextField(labelWithString: copy.text("截图仓库", "Screenshot Library"))
    private var tableScroll: NSScrollView!
    private var detailScroll: NSScrollView!
    private var listWidths: [NSLayoutConstraint] = []
    private lazy var grid = HistoryGridRenderer(copy: copy, directory: mediaDirectory,
        onSelection: { [weak self] in self?.selectRecord($0) },
        onPreview: { [weak self] in self?.previewSelected() }, stateText: { [copy] in HistoryPresentation.localizedState(for: $0, copy: copy) },
        mayLoad: { [weak self] in
            self?.historyWindow.isVisible == true && self?.displayStyle == .imageGrid
        })
    private let search = NSSearchField()
    public var onLibraryQueryChanged: (() -> Void)?
    public var onRetryHistory: (() -> Void)?
    private let dateFilter = NSPopUpButton()
    private let fromDate = NSDatePicker()
    private let toDate = NSDatePicker()
    private let dateControls = NSStackView()
    private let noticeControls = NSStackView()
    private let notice = NSTextField(wrappingLabelWithString: "")
    private let noticeAction = NSButton(title: "", target: nil, action: nil)
    private var issueText: String?
    private var failedRead = false
    private var hasNewCaptures = false

    public var libraryQuery: HistoryQuery {
        let calendar = Calendar.autoupdatingCurrent
        let today = calendar.startOfDay(for: Date())
        let range: DateInterval?
        switch dateFilter.indexOfSelectedItem {
        case 1: range = calendar.dateInterval(of: .day, for: today)
        case 2:
            range = DateInterval(start: calendar.date(byAdding: .day, value: -6, to: today)!,
                                 end: calendar.date(byAdding: .day, value: 1, to: today)!)
        case 3:
            let start = calendar.startOfDay(for: fromDate.dateValue)
            let last = max(start, calendar.startOfDay(for: toDate.dateValue))
            range = DateInterval(start: start, end: calendar.date(byAdding: .day, value: 1, to: last)!)
        default: range = nil
        }
        let filter = RiftHistoryFilter.menuFilters[filterIndex]
        return HistoryQuery(text: search.stringValue, filter: filter.libraryFilter, dateRange: range)
    }
    private var filterIndex = 0
    private let table = HistoryTableView()
    private let detailImage = HistoryPreviewImageView()
    private let imageBackdrop = NSVisualEffectView()
    private lazy var detailTitle = HistoryDetailLabel(wrappingLabelWithString: copy.text("选择一张截图", "Select a screenshot"))
    private let detailMetadata = NSTextField(wrappingLabelWithString: "")
    private lazy var detailState = NSTextField(wrappingLabelWithString: copy.text("原图与本地记录始终保留。", "Original images and local records are kept."))
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
    private lazy var restoreButton = NSButton(title: copy.text("恢复到托盘", "Restore to Tray"), target: nil, action: nil)
    private lazy var removeButton = NSButton(title: copy.text("从桌面收起", "Hide from Desktop"), target: nil, action: nil)
    public var onCheckOriginal: ((UUID) -> Void)?
    public var onMarkHandled: ((UUID) -> Void)?
    public var onPrepareReattachment: ((UUID, UUID) -> Void)?
    public var onFocusOriginal: ((TransferOperation) async -> Bool)?
    private lazy var checkButton = NSButton(title: copy.text("重新核对状态", "Check Status Again"), target: self, action: #selector(checkOriginal))
    private lazy var handledButton = NSButton(title: copy.text("标为已处理", "Mark as Handled"), target: self, action: #selector(markHandled))
    private lazy var reattachButton = NSButton(title: copy.text("重新附加…", "Attach Again…"), target: self, action: #selector(prepareReattachment))
    private lazy var focusButton = NSButton(title: copy.text("返回原草稿", "Return to Original Draft"), target: self, action: #selector(focusOriginal))
    private lazy var conversationButton = NSButton(title: copy.text("打开会话记录", "Open Conversation History"), target: nil, action: nil)
    private lazy var revealButton = NSButton(title: copy.text("在 Finder 中显示", "Show in Finder"), target: nil, action: nil)
    private lazy var originalButton = NSButton(title: copy.text("查看原图", "View Original"), target: nil, action: nil)
    private lazy var newerButton = NSButton(title: copy.text("上一页", "Previous Page"), target: nil, action: nil)
    private lazy var olderButton = NSButton(title: copy.text("下一页", "Next Page"), target: nil, action: nil)
    private let actionNote = HistoryDetailLabel(wrappingLabelWithString: "")
    private var entries: [RiftHistoryEntry] = []
    private var displayed: [RiftHistoryEntry] = []
    private var pageOffset = 0
    private var hasEarlier = false
    private var hasPresented = false

    public var isVisible: Bool { historyWindow.isVisible }
    public var window: NSWindow { historyWindow }

    public init(copy: ProductCopy = .current, mediaDirectory: URL, onRestore: @escaping (UUID) -> Void,
                onRemove: @escaping (UUID) -> Void, onReveal: @escaping (UUID) -> Void,
                onNextPage: (() -> Void)? = nil, onPreviousPage: (() -> Void)? = nil,
                displayStyle: HistoryDisplayStyle = .current,
                onDisplayStyleChanged: @escaping (HistoryDisplayStyle) -> Void = { _ in }) {
        self.copy = copy
        self.cache = ThumbnailCache(directory: mediaDirectory)
        self.mediaDirectory = mediaDirectory
        self.onRestore = onRestore; self.onRemove = onRemove; self.onReveal = onReveal
        self.onNextPage = onNextPage; self.onPreviousPage = onPreviousPage
        self.displayStyle = displayStyle; self.onDisplayStyleChanged = onDisplayStyleChanged
        historyWindow = RiftVisualStyle.window(outerSize: NSSize(width: 808, height: 492),
            minimum: NSSize(width: 680, height: 480), title: copy.text("Riftlet — 截图仓库", "Riftlet — Screenshot Library"))
        super.init()
        historyWindow.title = copy.text("截图仓库", "Screenshot Library")
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
    public func update(entries: [RiftHistoryEntry], pageOffset: Int = 0, hasEarlier: Bool = false, hasNewCaptures: Bool = false) {
        let sorted = onLibraryQueryChanged == nil ? HistoryPresentation.matching(entries) : entries
        let next = Array(sorted.prefix(HistoryPresentation.pageSize))
        if self.entries == next, self.pageOffset == pageOffset, self.hasEarlier == hasEarlier,
           self.hasNewCaptures == hasNewCaptures, !failedRead { return }
        let anchor: UUID?
        if self.pageOffset == pageOffset && isVisible {
            let first = table.rows(in: table.visibleRect).location
            anchor = displayStyle == .imageGrid ? grid.firstVisibleID : (displayed.indices.contains(first) ? displayed[first].id : nil)
        } else { anchor = nil }
        self.hasNewCaptures = hasNewCaptures
        if failedRead { failedRead = false; issueText = nil }
        self.entries = next
        self.pageOffset = max(0, pageOffset); self.hasEarlier = hasEarlier
        if historyWindow.isVisible {
            refresh()
            if let anchor, let row = displayed.firstIndex(where: { $0.id == anchor }) {
                if displayStyle == .imageGrid { grid.scroll(to: anchor) }
                else { table.scrollRowToVisible(row) }
            }
        }
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
        search.placeholderString = copy.text("搜索截图", "Search screenshots"); search.setAccessibilityLabel(copy.text("搜索截图", "Search screenshots"))
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
        table.setAccessibilityLabel(copy.text("本机截图记录；空格查看预览", "Local screenshot history. Press Space to preview."))
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        tableScroll = scroll
        scroll.drawsBackground = false; scroll.documentView = table
        let paging = NSStackView(views: [newerButton, olderButton]); paging.spacing = 8
        for button in [restoreButton, removeButton, revealButton, originalButton, conversationButton, newerButton, olderButton, checkButton, handledButton, reattachButton, focusButton] {
            RiftVisualStyle.style(button); button.target = self
        }
        restoreButton.action = #selector(restoreSelected); removeButton.action = #selector(removeSelected)
        revealButton.action = #selector(revealSelected); newerButton.action = #selector(previousPage); olderButton.action = #selector(nextPage)
        for (button, id) in [(focusButton, "focusOriginal"), (checkButton, "checkOriginal"), (handledButton, "markHandled"), (reattachButton, "reattach")] {
            button.identifier = .init("history." + id)
        }
        conversationButton.action = #selector(viewOriginalConversation)
        conversationButton.identifier = .init("history.conversation")
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
            styleSelector.setToolTip(style.title(copy: copy), forSegment: index)
            styleSelector.setImageScaling(.scaleProportionallyDown, forSegment: index)
        }
        styleSelector.segmentStyle = .rounded
        styleSelector.target = self; styleSelector.action = #selector(styleChanged(_:))
        styleSelector.setAccessibilityLabel(copy.text("历史显示方式", "History display style"))
        gridFilter.identifier = .init("history.grid.filter")
        gridFilter.addItems(withTitles: RiftHistoryFilter.menuFilters.map { $0.title(copy: copy) })
        gridFilter.target = self; gridFilter.action = #selector(gridFilterChanged(_:))
        gridFilter.setAccessibilityLabel(copy.text("筛选截图状态", "Filter screenshots by status"))
        gridTitle.font = .systemFont(ofSize: 23, weight: .semibold); gridTitle.textColor = .labelColor
        configureDateFilters()
        let tools = NSStackView(views: [search, gridFilter, dateFilter, NSView(), styleSelector])
        tools.spacing = 8
        search.widthAnchor.constraint(greaterThanOrEqualToConstant: 106).isActive = true
        let preferredSearchWidth = search.widthAnchor.constraint(equalToConstant: 138)
        preferredSearchWidth.priority = .defaultHigh; preferredSearchWidth.isActive = true
        notice.identifier = .init("history.notice")
        notice.font = RiftVisualStyle.bodyFont
        noticeAction.identifier = .init("history.notice.action")
        noticeAction.target = self; noticeAction.action = #selector(performNoticeAction)
        RiftVisualStyle.style(noticeAction)
        noticeControls.addArrangedSubview(notice); noticeControls.addArrangedSubview(noticeAction)
        noticeControls.isHidden = true
        let heading = NSStackView(views: [gridTitle, tools, dateControls, noticeControls])
        heading.orientation = .vertical; heading.alignment = .leading; heading.spacing = 8
        tools.widthAnchor.constraint(equalTo: heading.widthAnchor).isActive = true
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
        newerButton.setAccessibilityLabel(copy.text("上一页", "Previous Page")); olderButton.setAccessibilityLabel(copy.text("下一页", "Next Page"))
        newerButton.toolTip = copy.text("上一页", "Previous Page"); olderButton.toolTip = copy.text("下一页", "Next Page")
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
        detailImage.setAccessibilityLabel(copy.text("完整比例截图预览", "Screenshot preview with original proportions"))
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
                                                   viewActions, focusButton, conversationButton, checkButton, handledButton, reattachButton, queueActions, actionNote], spacing: 8)
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
        let filter = RiftHistoryFilter.menuFilters[filterIndex]
        if onLibraryQueryChanged != nil { displayed = entries }
        else {
            let interval = libraryQuery.dateRange
            displayed = HistoryPresentation.matching(entries, filter: filter, query: search.stringValue).filter { item in
                guard let interval else { return true }
                let date = HistoryPresentation.captureDate(for: item)
                return date >= interval.start && date < interval.end
            }
        }
        refreshNotice()
        gridFilter.selectItem(at: filterIndex)
        selectedRecordID = selectedID.flatMap { id in displayed.contains(where: { $0.id == id }) ? id : nil }
        suppressSelection = true
        table.reloadData()
        if let selectedID, let row = displayed.firstIndex(where: { $0.id == selectedID }) {
            table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        } else { table.deselectAll(nil) }
        suppressSelection = false
        grid.update(entries: displayed, selection: selectedRecordID)
        countLabel.stringValue = copy.text("\(displayed.count) 张 · 第 \(pageOffset / HistoryPresentation.pageSize + 1) 页",
            "\(displayed.count) · Page \(pageOffset / HistoryPresentation.pageSize + 1)")
        updateActions()
    }

    private func updateActions() {
        restoreButton.isEnabled = selectedEntry?.canRestoreToRift == true
        removeButton.isEnabled = selectedEntry?.canRemoveFromRift == true
        let actionable = selectedEntry?.hasRecoveryOptions == true
        checkButton.isHidden = selectedEntry?.canReviewOriginal != true || onCheckOriginal == nil || selectedEntry?.isHandled == true
        focusButton.isHidden = selectedEntry?.canReviewOriginal != true || onFocusOriginal == nil
        handledButton.isHidden = !actionable || selectedEntry?.isHandled == true || onMarkHandled == nil
        reattachButton.isHidden = !actionable || onPrepareReattachment == nil
        conversationButton.isHidden = selectedEntry?.conversationURL == nil
        revealButton.isEnabled = selectedEntry != nil
        originalButton.isEnabled = selectedEntry != nil
        originalButton.isHidden = selectedEntry == nil
        restoreButton.isHidden = !restoreButton.isEnabled
        removeButton.isHidden = !removeButton.isEnabled
        revealButton.isHidden = selectedEntry == nil
        let notes = [restoreButton.isEnabled ? copy.text("恢复后可以再次点选。", "You can click it again after restoring it.") : nil,
                     removeButton.isEnabled ? copy.text("收起后仍可在截图仓库找到。", "Hidden screenshots stay in your library.") : nil].compactMap { $0 }
        actionNote.stringValue = notes.joined(separator: copy.text("", " "))
        RiftVisualStyle.applyTextStyle(actionNote)
        actionNote.isHidden = notes.isEmpty
        newerButton.isEnabled = pageOffset > 0 && onPreviousPage != nil
        olderButton.isEnabled = hasEarlier && onNextPage != nil
        updateDetail()
    }

    private func stateText(_ entry: RiftHistoryEntry) -> String {
        entry.isHandled ? copy.text("已处理", "Handled") : HistoryPresentation.localizedState(for: entry, copy: copy)
    }
    private func updateDetail() {
        detailGeneration &+= 1
        let generation = detailGeneration
        guard let entry = selectedEntry else {
            previewWindow?.close()
            detailID = nil; detailAsset = nil; detailImage.image = nil; imageBackdrop.isHidden = true; detailTitle.stringValue = copy.text("截图会留在这里", "Your screenshots stay here")
            detailMetadata.stringValue = ""; detailState.stringValue = copy.text("选择一张截图，查看原比例预览与本地状态。", "Select a screenshot to preview it and see its local status.")
            for field in [detailTitle, detailMetadata, detailState] { RiftVisualStyle.applyTextStyle(field) }
            return
        }
        let sameBitmap = detailID == entry.id && detailAsset == entry.record.image && detailImage.image != nil
        detailID = entry.id; detailAsset = entry.record.image
        if !sameBitmap { detailImage.image = nil }
        imageBackdrop.isHidden = false
        detailTitle.stringValue = captureTitle(entry)
        detailMetadata.stringValue = "\(entry.record.image.pixelWidth) × \(entry.record.image.pixelHeight)　·　\(stateText(entry))"
        detailMetadata.toolTip = entry.id.uuidString
        detailState.stringValue = HistoryPresentation.detailText(for: entry, copy: copy)
        detailImage.setAccessibilityLabel(previewDescription(entry))
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
        let status = RiftVisualStyle.label(copy.text("正在加载预览…", "Loading preview…"), role: "secondary")
        status.identifier = .init("history.preview.status")
        let reveal = NSButton(title: copy.text("在 Finder 中显示", "Show in Finder"), target: self, action: #selector(revealPreview))
        RiftVisualStyle.style(reveal)
        let zoom = NSSegmentedControl(labels: [copy.text("适合", "Fit"), "100%", "200%"], trackingMode: .selectOne, target: self, action: #selector(changePreviewZoom(_:)))
        zoom.selectedSegment = 0; zoom.identifier = .init("history.preview.zoom"); zoom.setAccessibilityLabel(copy.text("原图缩放：适合、100% 逻辑尺寸、200%", "Original image zoom: Fit, 100% logical size, 200%"))
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

    private func captureTitle(_ entry: RiftHistoryEntry) -> String {
        let formatter = DateFormatter(); formatter.dateStyle = .medium; formatter.timeStyle = .medium
        return copy.text("截图 · ", "Screenshot · ") + formatter.string(from: HistoryPresentation.captureDate(for: entry))
    }

    private func previewDescription(_ entry: RiftHistoryEntry) -> String {
        copy.text("\(captureTitle(entry))，\(entry.record.image.pixelWidth) × \(entry.record.image.pixelHeight)，\(stateText(entry))，编号 \(entry.id.uuidString.prefix(8))。Escape 或空格关闭预览。",
            "\(captureTitle(entry)), \(entry.record.image.pixelWidth) × \(entry.record.image.pixelHeight), \(stateText(entry)), ID \(entry.id.uuidString.prefix(8)). Press Escape or Space to close the preview.")
    }

    private func updatePreviewIdentity() {
        guard let entry = previewEntry else { return }
        previewWindow?.title = captureTitle(entry) + " · " + String(entry.id.uuidString.prefix(8))
        previewImage?.setAccessibilityLabel(previewDescription(entry))
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
        previewStatus?.stringValue = view.image == nil ? copy.text("正在加载预览…", "Loading preview…") : copy.text("正在加载清晰预览…", "Loading detailed preview…")
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
                        self.previewStatus?.stringValue = self.previewZoom == nil ? self.copy.text("已按窗口显示", "Fit to window") : self.copy.text("原件校验预览 · 显示解码受内存上限保护", "Verified original preview · memory use is limited")
                    default:
                        self.previewImage?.image = nil; self.previewVerifiedAsset = nil
                        self.previewStatus?.stringValue = self.copy.text("无法加载清晰预览，图片记录仍保留", "Couldn’t load the detailed preview. The image record is still saved.")
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
    private func configureDateFilters() {
        dateFilter.identifier = .init("history.date")
        dateFilter.setAccessibilityLabel(copy.text("截图日期", "Capture date"))
        dateFilter.addItems(withTitles: [copy.text("全部日期", "All Dates"), copy.text("今天", "Today"),
            copy.text("最近7天", "Last 7 Days"), copy.text("自定日期…", "Custom Dates…")])
        dateFilter.target = self; dateFilter.action = #selector(dateChanged(_:))
        for (index, picker) in [fromDate, toDate].enumerated() {
            picker.datePickerStyle = .textFieldAndStepper
            picker.datePickerElements = .yearMonthDay
            picker.dateValue = Date()
            picker.identifier = .init(index == 0 ? "history.date.from" : "history.date.to")
            picker.setAccessibilityLabel(index == 0 ? copy.text("开始日期", "Start date") : copy.text("结束日期", "End date"))
            picker.target = self; picker.action = #selector(dateChanged(_:))
        }
        dateControls.addArrangedSubview(fromDate)
        dateControls.addArrangedSubview(NSTextField(labelWithString: copy.text("至", "to")))
        dateControls.addArrangedSubview(toDate); dateControls.isHidden = true
    }

    @objc private func dateChanged(_ sender: NSControl) {
        dateControls.isHidden = dateFilter.indexOfSelectedItem != 3
        if fromDate.dateValue > toDate.dateValue {
            if sender === toDate { fromDate.dateValue = toDate.dateValue }
            else { toDate.dateValue = fromDate.dateValue }
        }
        queryChanged()
    }

    private func queryChanged() {
        issueText = nil; failedRead = false
        refreshNotice()
        if let onLibraryQueryChanged { onLibraryQueryChanged() }
        else { refresh() }
    }

    public func showReadError() {
        failedRead = true
        showActionError(copy.text("未能读取截图仓库。", "Your library could not be read."))
    }

    public func showActionError(_ message: String) {
        let announce = message != issueText
        issueText = message; refreshNotice()
        if announce && historyWindow.isVisible {
            NSAccessibility.post(element: notice, notification: .announcementRequested,
                userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
        }
    }

    private var hasFilters: Bool {
        filterIndex != 0 || dateFilter.indexOfSelectedItem > 0 || !search.stringValue.isEmpty
    }

    private func refreshNotice() {
        let message: String
        if let issueText {
            message = issueText
            noticeAction.title = failedRead ? copy.text("重试", "Retry") : copy.text("关闭", "Dismiss")
        } else if displayed.isEmpty && hasFilters {
            message = copy.text("没有符合条件的截图。", "No matching screenshots.")
            noticeAction.title = copy.text("清除筛选", "Clear Filters")
        } else if hasNewCaptures {
            message = copy.text("有新截图", "New screenshots available")
            noticeAction.title = copy.text("刷新", "Refresh")
        } else { noticeControls.isHidden = true; return }
        notice.stringValue = message; noticeControls.isHidden = false
    }

    @objc private func performNoticeAction() {
        if failedRead { onRetryHistory?(); return }
        if issueText != nil { issueText = nil; refreshNotice(); return }
        if displayed.isEmpty && hasFilters {
            filterIndex = 0; gridFilter.selectItem(at: 0); dateFilter.selectItem(at: 0)
            dateControls.isHidden = true; search.stringValue = ""
        }
        queryChanged()
    }

    @objc private func gridFilterChanged(_ sender: NSPopUpButton) {
        guard RiftHistoryFilter.menuFilters.indices.contains(sender.indexOfSelectedItem) else { return }
        filterIndex = sender.indexOfSelectedItem
        queryChanged()
    }
    public func controlTextDidChange(_ obj: Notification) {
        if let editor = search.currentEditor() as? NSTextView, editor.hasMarkedText() { return }
        queryChanged()
    }
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
            cell.identifier = column.identifier; cell.preview.setAccessibilityLabel(copy.text("截图预览", "Screenshot preview"))
            cell.representedID = entry.id; cell.preview.image = nil
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
        cell.subtitle.stringValue = stateText(entry)
        cell.toolTip = HistoryPresentation.dateText(for: entry) + " · " + stateText(entry)
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

    @objc private func checkOriginal() {
        guard let op = selectedEntry?.currentOperation else { return }
        onCheckOriginal?(op.id)
    }

    @objc private func markHandled() {
        guard let entry = selectedEntry, entry.hasRecoveryOptions, !entry.isHandled,
              let op = entry.currentOperation else { return }
        onMarkHandled?(op.id)
    }

    @objc private func prepareReattachment() {
        guard let entry = selectedEntry, entry.hasRecoveryOptions, let op = entry.currentOperation else { return }
        let alert = NSAlert()
        alert.messageText = copy.text("再次附加这张截图？", "Attach this screenshot again?")
        alert.informativeText = copy.text("原草稿可能已有这张图。继续后，请打开目标草稿，再点一下桌面上的截图。", "The original draft may already contain this image. Continue, open the draft you want, then click the screenshot on your desktop.")
        alert.addButton(withTitle: copy.text("继续", "Continue"))
        alert.addButton(withTitle: copy.text("取消", "Cancel"))
        alert.beginSheetModal(for: historyWindow) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.onPrepareReattachment?(entry.id, op.id)
        }
    }

    @objc private func focusOriginal() {
        guard let op = selectedEntry?.currentOperation, let onFocusOriginal else { return }
        Task { [weak self] in
            let focused = await onFocusOriginal(op)
            guard !focused, let self, self.selectedEntry?.currentOperation?.id == op.id else { return }
            self.showActionError(self.copy.text("未能定位原草稿。可查看原图，或打开已有的会话记录。", "The original draft could not be located. View the image or open the conversation history if available."))
        }
    }

    @objc private func viewOriginalConversation() {
        guard let url = selectedEntry?.conversationURL else { return }
        guard let chrome = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome") else {
            showActionError(copy.text("找不到 Chrome。可查看原图后在原草稿中核对。", "Chrome is unavailable. View the original image and compare it with your draft."))
            return
        }
        NSWorkspace.shared.open([url], withApplicationAt: chrome, configuration: .init()) { [weak self] _, error in
            if error != nil {
                Task { @MainActor in self?.showActionError(ProductCopy.text("未能打开原对话。请在原草稿中核对图片。", "Could not open the conversation. Check the image in your original draft.")) }
            }
        }
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
