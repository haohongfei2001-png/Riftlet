import AppKit
import RiftletCore

private final class HistoryTextCell: NSTableCellView {
    let title = NSTextField(labelWithString: "")
    let subtitle = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        title.font = .systemFont(ofSize: 12)
        subtitle.font = .systemFont(ofSize: 11)
        subtitle.textColor = .secondaryLabelColor
        title.lineBreakMode = .byTruncatingTail
        subtitle.lineBreakMode = .byTruncatingTail
        let stack = NSStackView(views: [title, subtitle])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 5
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
        preview.setAccessibilityLabel("Screenshot preview")
        addSubview(preview)
        NSLayoutConstraint.activate([
            preview.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            preview.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            preview.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            preview.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

/// Explicitly opened local history, with one bounded metadata page and reused
/// downsampled thumbnails. No adapter, upload, clipboard or deletion capability.
@MainActor
public final class RiftHistoryController: NSObject, NSTableViewDataSource, NSTableViewDelegate,
                                           NSSearchFieldDelegate, NSWindowDelegate {
    private let historyWindow: NSWindow
    private let cache: ThumbnailCache
    private let onRestore: (UUID) -> Void
    private let onRemove: (UUID) -> Void
    private let onReveal: (UUID) -> Void
    private let onNextPage: (() -> Void)?
    private let onPreviousPage: (() -> Void)?
    private let search = NSSearchField()
    private let filter = NSPopUpButton(frame: .zero, pullsDown: false)
    private let table = NSTableView()
    private let countLabel = NSTextField(labelWithString: "")
    private let restoreButton = NSButton(title: "Return to Rift", target: nil, action: nil)
    private let removeButton = NSButton(title: "Remove from Rift", target: nil, action: nil)
    private let revealButton = NSButton(title: "Show in Finder", target: nil, action: nil)
    private let newerButton = NSButton(title: "Newer", target: nil, action: nil)
    private let olderButton = NSButton(title: "Older", target: nil, action: nil)
    private var entries: [RiftHistoryEntry] = []
    private var displayed: [RiftHistoryEntry] = []
    private var pageOffset = 0
    private var hasEarlier = false

    public var isVisible: Bool { historyWindow.isVisible }

    public init(mediaDirectory: URL, onRestore: @escaping (UUID) -> Void,
                onRemove: @escaping (UUID) -> Void, onReveal: @escaping (UUID) -> Void,
                onNextPage: (() -> Void)? = nil, onPreviousPage: (() -> Void)? = nil) {
        self.cache = ThumbnailCache(directory: mediaDirectory)
        self.onRestore = onRestore; self.onRemove = onRemove; self.onReveal = onReveal
        self.onNextPage = onNextPage; self.onPreviousPage = onPreviousPage
        historyWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 500),
                                 styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                 backing: .buffered, defer: false)
        super.init()
        historyWindow.title = "Riftlet — Screenshot History"
        historyWindow.isReleasedWhenClosed = false
        historyWindow.minSize = NSSize(width: 560, height: 340)
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
        refresh()
        historyWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func close() { historyWindow.close() }

    public func windowWillClose(_ notification: Notification) {
        cache.clear()
        displayed.removeAll()
        table.reloadData()
    }

    private func configureContent() {
        guard let content = historyWindow.contentView else { return }
        search.placeholderString = "Search this page: date, image ID or state"
        search.delegate = self
        search.sendsSearchStringImmediately = true
        filter.addItems(withTitles: RiftHistoryFilter.allCases.map(\.title))
        filter.target = self; filter.action = #selector(filterChanged)
        filter.setAccessibilityLabel("History filter")
        let top = NSStackView(views: [search, filter])
        top.orientation = .horizontal; top.spacing = 10
        search.widthAnchor.constraint(greaterThanOrEqualToConstant: 250).isActive = true

        let previewColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("preview"))
        previewColumn.width = 92; previewColumn.minWidth = 92; previewColumn.maxWidth = 92
        let descriptionColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("description"))
        descriptionColumn.minWidth = 320
        table.addTableColumn(previewColumn); table.addTableColumn(descriptionColumn)
        table.headerView = nil; table.rowHeight = 68
        table.intercellSpacing = NSSize(width: 0, height: 2)
        table.usesAlternatingRowBackgroundColors = true
        table.allowsMultipleSelection = false
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.dataSource = self; table.delegate = self
        table.target = self; table.doubleAction = #selector(revealSelected)
        table.setAccessibilityLabel("Local screenshots")
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        scroll.borderType = .bezelBorder; scroll.documentView = table

        for button in [restoreButton, removeButton, revealButton, newerButton, olderButton] {
            button.bezelStyle = .rounded; button.target = self
        }
        restoreButton.action = #selector(restoreSelected)
        removeButton.action = #selector(removeSelected)
        revealButton.action = #selector(revealSelected)
        newerButton.action = #selector(previousPage)
        olderButton.action = #selector(nextPage)
        let actions = NSStackView(views: [revealButton, restoreButton, removeButton])
        actions.orientation = .horizontal; actions.spacing = 8
        let paging = NSStackView(views: [newerButton, olderButton])
        paging.orientation = .horizontal; paging.spacing = 8
        countLabel.font = .systemFont(ofSize: 11); countLabel.textColor = .secondaryLabelColor
        countLabel.lineBreakMode = .byTruncatingTail
        let note = NSTextField(wrappingLabelWithString:
            "Returning to the rift does not upload. Removing here keeps the local image and the ChatGPT attachment.")
        note.font = .systemFont(ofSize: 11); note.textColor = .secondaryLabelColor

        for view in [top, scroll, actions, paging, countLabel, note] {
            view.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            top.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            top.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            top.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            scroll.topAnchor.constraint(equalTo: top.bottomAnchor, constant: 12),
            scroll.leadingAnchor.constraint(equalTo: top.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: top.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: countLabel.topAnchor, constant: -10),
            countLabel.leadingAnchor.constraint(equalTo: top.leadingAnchor),
            countLabel.centerYAnchor.constraint(equalTo: paging.centerYAnchor),
            countLabel.trailingAnchor.constraint(lessThanOrEqualTo: paging.leadingAnchor, constant: -8),
            paging.trailingAnchor.constraint(equalTo: top.trailingAnchor),
            paging.bottomAnchor.constraint(equalTo: actions.topAnchor, constant: -10),
            actions.leadingAnchor.constraint(equalTo: top.leadingAnchor),
            actions.bottomAnchor.constraint(equalTo: note.topAnchor, constant: -8),
            note.leadingAnchor.constraint(equalTo: top.leadingAnchor),
            note.trailingAnchor.constraint(equalTo: top.trailingAnchor),
            note.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -14)
        ])
        updateActions()
    }

    private var selectedEntry: RiftHistoryEntry? {
        guard displayed.indices.contains(table.selectedRow) else { return nil }
        return displayed[table.selectedRow]
    }

    private func refresh() {
        let selectedID = selectedEntry?.id
        let selectedFilter = RiftHistoryFilter.allCases.indices.contains(filter.indexOfSelectedItem)
            ? RiftHistoryFilter.allCases[filter.indexOfSelectedItem] : .all
        displayed = HistoryPresentation.matching(entries, filter: selectedFilter, query: search.stringValue)
        table.reloadData()
        if let selectedID, let row = displayed.firstIndex(where: { $0.id == selectedID }) {
            table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        } else { table.deselectAll(nil) }
        countLabel.stringValue = "\(displayed.count) of \(entries.count) on this page · page \(pageOffset / HistoryPresentation.pageSize + 1)"
        updateActions()
    }

    private func updateActions() {
        restoreButton.isEnabled = selectedEntry?.canRestoreToRift == true
        removeButton.isEnabled = selectedEntry?.canRemoveFromRift == true
        revealButton.isEnabled = selectedEntry != nil
        newerButton.isEnabled = pageOffset > 0 && onPreviousPage != nil
        olderButton.isEnabled = hasEarlier && onNextPage != nil
    }

    @objc private func filterChanged() { refresh() }
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
        let asset = entry.record.image
        cell.title.stringValue = "\(HistoryPresentation.dateText(for: entry)) · \(asset.pixelWidth) × \(asset.pixelHeight)"
        cell.subtitle.stringValue = HistoryPresentation.stateText(for: entry)
        cell.toolTip = [entry.id.uuidString, entry.detail].compactMap { $0 }.joined(separator: "\n")
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
