import AppKit
import RiftletCore

/// Scoped to the optional renderer; the existing history/list palette is unchanged.
@MainActor
enum HistoryGridStyle {
    static let surface = adaptive("surface", light: 0xFFFFFF, dark: 0x292D2B)
    static let secondarySurface = adaptive("secondarySurface", light: 0xFBFAF8, dark: 0x242825)
    static let ink = adaptive("ink", light: 0x282B29, dark: 0xE6E9E5)
    static let secondary = adaptive("secondary", light: 0x686F69, dark: 0xA3ABA4)
    static let accent = adaptive("accent", light: 0x19B7A4, dark: 0x19B7A4)
    static let deep = adaptive("deep", light: 0x087C70, dark: 0x087C70)
    static let border = NSColor(name: NSColor.Name("Riftlet.HistoryGrid.border")) { appearance in
        let match = appearance.bestMatch(from: [.accessibilityHighContrastAqua,
            .accessibilityHighContrastDarkAqua, .aqua, .darkAqua])
        if match == .accessibilityHighContrastAqua || match == .accessibilityHighContrastDarkAqua {
            var resolved: NSColor?
            appearance.performAsCurrentDrawingAppearance { resolved = NSColor.separatorColor.usingColorSpace(.sRGB) }
            if let resolved { return resolved }
        }
        return match == .darkAqua || match == .accessibilityHighContrastDarkAqua
            ? NSColor(srgbRed: 224/255, green: 236/255, blue: 225/255, alpha: 0.20)
            : NSColor(srgbRed: 36/255, green: 49/255, blue: 42/255, alpha: 0.20)
    }

    private static func adaptive(_ role: String, light: UInt32, dark: UInt32) -> NSColor {
        NSColor(name: NSColor.Name("Riftlet.HistoryGrid." + role)) { appearance in
            let match = appearance.bestMatch(from: [.accessibilityHighContrastAqua,
                .accessibilityHighContrastDarkAqua, .aqua, .darkAqua])
            let highContrast = match == .accessibilityHighContrastAqua || match == .accessibilityHighContrastDarkAqua
            if highContrast, role == "ink" || role == "secondary" {
                var resolved: NSColor?
                appearance.performAsCurrentDrawingAppearance { resolved = NSColor.labelColor.usingColorSpace(.sRGB) }
                if let resolved { return resolved }
            }
            let value = match == .darkAqua || match == .accessibilityHighContrastDarkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((value >> 16) & 255) / 255,
                           green: CGFloat((value >> 8) & 255) / 255,
                           blue: CGFloat(value & 255) / 255, alpha: 1)
        }
    }
}

struct HistoryGridSection {
    let title: String
    let entries: [RiftHistoryEntry]

    static func make(_ entries: [RiftHistoryEntry], now: Date = Date(), calendar: Calendar = .current,
                     copy: ProductCopy = .current) -> [Self] {
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        let groups = Dictionary(grouping: entries) { entry in
            let date = HistoryPresentation.captureDate(for: entry)
            return calendar.isDate(date, inSameDayAs: today) ? 0 : calendar.isDate(date, inSameDayAs: yesterday) ? 1 : 2
        }
        return [copy.text("今天", "Today"), copy.text("昨天", "Yesterday"), copy.text("更早", "Earlier")].enumerated().compactMap { index, title in
            guard let values = groups[index], !values.isEmpty else { return nil }
            return Self(title: title, entries: values)
        }
    }
}

/// One sequential request at a time through the existing verified decoder.
/// A renderer has independent cancellation state but uses the loader's existing
/// process-wide serial decode queue. It never claims the original preview owner.
/// Only visible metadata is queued; cached bytes and count are bounded.
@MainActor
final class HistoryGridThumbnailLoader {
    private struct Cached {
        let asset: ImportedAsset
        let loaded: HistoryPreviewImage
        var cost: Int { loaded.image.bytesPerRow * loaded.image.height }
    }
    private let directory: URL
    private let loader: HistoryPreviewLoader
    private let owner = UUID()
    private let mayLoad: () -> Bool
    private let didLoad: (UUID) -> Void
    private var cache: [UUID: Cached] = [:]
    private var order: [UUID] = []
    private var failures: [UUID: ImportedAsset] = [:]
    private var queue: [ImportedAsset] = []
    private var completed: [UUID: ImportedAsset] = [:]
    private var generation: UInt = 0
    private var running = false
    private var enabled = false
    private var backing: CGFloat = 1
    private(set) var requestCount = 0

    init(directory: URL, loader: HistoryPreviewLoader? = nil,
         mayLoad: @escaping () -> Bool, didLoad: @escaping (UUID) -> Void) {
        self.directory = directory; self.loader = loader ?? HistoryPreviewLoader()
        self.mayLoad = mayLoad; self.didLoad = didLoad
    }

    func image(for asset: ImportedAsset) -> NSImage? {
        loadedImage(for: asset).map { NSImage(cgImage: $0.image, size: .zero) }
    }

    func loadedImage(for asset: ImportedAsset) -> HistoryPreviewImage? {
        guard let value = cache[asset.id] else { return nil }
        guard value.asset == asset, value.loaded.identity.matches(value.loaded.url) else {
            cache[asset.id] = nil; order.removeAll { $0 == asset.id }; return nil
        }
        return value.loaded
    }

    func update(visible: [RiftHistoryEntry], backing: CGFloat) {
        guard mayLoad() else { suspend(); return }
        let requested = visible.prefix(HistoryPresentation.pageSize).map(\.record.image)
        if self.backing != backing {
            // A decode for the previous screen can complete after this update.
            // Retire its epoch before queuing the new backing-size request.
            suspend(); cache.removeAll(); order.removeAll()
        }
        if requested != queue || self.backing != backing { completed.removeAll() }
        enabled = true; self.backing = backing; queue = requested
        next()
    }

    func suspend() {
        enabled = false; generation &+= 1; running = false; queue.removeAll(); completed.removeAll()
        loader.cancel(owner: owner)
    }

    func clear() {
        suspend(); cache.removeAll(); order.removeAll(); failures.removeAll()
    }

    func pageChanged() { failures.removeAll(); completed.removeAll() }
    func failed(_ asset: ImportedAsset) -> Bool { failures[asset.id] == asset }

    private func next() {
        guard enabled, !running, mayLoad() else { return }
        guard let asset = queue.first(where: { completed[$0.id] != $0 && loadedImage(for: $0) == nil && failures[$0.id] != $0 }) else { return }
        running = true; requestCount += 1
        let epoch = generation
        let request = HistoryPreviewRequest(asset: asset, directory: directory,
            viewport: CGSize(width: 180, height: 112), backing: backing)
        loader.request(owner: owner, request: request, invalidated: { [weak self] in
            // An explicitly injected shared instance may change its owner.
            // Do not issue another thumbnail request against that new owner.
            self?.suspend()
        }) { [weak self] result in
            guard let self, self.enabled, self.generation == epoch else { return }
            self.running = false
            self.completed[asset.id] = asset
            switch result {
            case .success(let loaded) where loaded.identity.matches(loaded.url):
                self.cache[asset.id] = Cached(asset: asset, loaded: loaded)
                self.order.removeAll { $0 == asset.id }; self.order.append(asset.id)
                while self.order.count > 48 || self.cache.values.reduce(0, { $0 + $1.cost }) > 12 * 1_024 * 1_024 {
                    guard !self.order.isEmpty else { break }
                    self.cache[self.order.removeFirst()] = nil
                }
            default: self.failures[asset.id] = asset
            }
            self.didLoad(asset.id)
            self.next()
        }
    }
}

@MainActor
final class HistoryGridRenderer: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegateFlowLayout {
    let scrollView = NSScrollView()
    let collection = HistoryGridCollectionView()
    private let copy: ProductCopy
    private let layout = NSCollectionViewFlowLayout()
    private var sections: [HistoryGridSection] = []
    private var suppressSelection = false
    private var visible = false
    private var refreshing = false
    private var selectedID: UUID?
    private let onSelection: (UUID?) -> Void
    private let onPreview: () -> Void
    private let stateText: (RiftHistoryEntry) -> String
    private let mayLoad: () -> Bool
    private var thumbnails: HistoryGridThumbnailLoader!
    private lazy var empty = NSTextField(wrappingLabelWithString: copy.text("本页没有符合条件的截图", "No matching screenshots on this page"))

    init(copy: ProductCopy = .current, directory: URL, onSelection: @escaping (UUID?) -> Void, onPreview: @escaping () -> Void,
         stateText: @escaping (RiftHistoryEntry) -> String, mayLoad: @escaping () -> Bool) {
        self.copy = copy
        self.onSelection = onSelection; self.onPreview = onPreview
        self.stateText = stateText; self.mayLoad = mayLoad
        super.init()
        thumbnails = HistoryGridThumbnailLoader(directory: directory, mayLoad: { [weak self] in
            self?.visible == true && mayLoad()
        }, didLoad: { [weak self] id in self?.updateImage(id) })
        layout.sectionInset = NSEdgeInsets(top: 4, left: 24, bottom: 20, right: 24)
        layout.minimumInteritemSpacing = 16; layout.minimumLineSpacing = 16
        layout.headerReferenceSize = NSSize(width: 1, height: 28)
        collection.collectionViewLayout = layout
        collection.frame = NSRect(x: 0, y: 0, width: 400, height: 400)
        collection.autoresizingMask = [.width]
        collection.identifier = .init("history.grid")
        collection.backgroundColors = [HistoryGridStyle.surface]
        collection.isSelectable = true; collection.allowsMultipleSelection = false
        collection.dataSource = self; collection.delegate = self
        collection.onPreview = onPreview
        collection.register(HistoryGridItem.self, forItemWithIdentifier: .init("history.grid.item"))
        collection.register(HistoryGridHeader.self, forSupplementaryViewOfKind: NSCollectionView.elementKindSectionHeader,
                            withIdentifier: .init("history.grid.header"))
        collection.setAccessibilityLabel(copy.text("按截图时间分组的本机图像；空格查看原图", "Local images grouped by capture date. Press Space to view the original."))
        scrollView.documentView = collection; scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true; scrollView.drawsBackground = false
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(viewportChanged),
            name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
        empty.textColor = HistoryGridStyle.secondary; empty.font = .systemFont(ofSize: 13)
        empty.alignment = .center; empty.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(empty)
        NSLayoutConstraint.activate([empty.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            empty.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
            empty.widthAnchor.constraint(lessThanOrEqualTo: scrollView.widthAnchor, constant: -48)])
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    func update(entries: [RiftHistoryEntry], selection: UUID?) {
        sections = HistoryGridSection.make(entries, copy: copy); selectedID = selection
        thumbnails.pageChanged()
        suppressSelection = true; collection.reloadData(); restoreSelection(); suppressSelection = false
        empty.isHidden = !entries.isEmpty
        refreshVisible()
    }

    func select(_ id: UUID?) {
        selectedID = id; suppressSelection = true; restoreSelection(); suppressSelection = false
    }

    private func restoreSelection() {
        collection.selectionIndexPaths = visible ? selectedID.flatMap(indexPath).map { [$0] } ?? [] : []
    }

    private func selectFromAccessibility(_ id: UUID, selected: Bool) -> Bool {
        guard visible, let path = indexPath(id) else { return false }
        // A retained/reused AX element never selects a different row by its
        // former index. Use the same UUID and native collection selection as
        // mouse/keyboard selection, then notify the existing controller.
        if selected {
            select(id)
            collection.scrollToItems(at: [path], scrollPosition: .nearestVerticalEdge)
            onSelection(id)
        } else if selectedID == id {
            select(nil)
            onSelection(nil)
        }
        return true
    }

    func setVisible(_ value: Bool) {
        let changed = visible != value
        visible = value
        scrollView.isHidden = !value
        if changed {
            // The hidden renderer retains metadata/UUID, but has no native
            // items to lay out while the other renderer changes its bounds.
            suppressSelection = true
            collection.reloadData(); restoreSelection()
            suppressSelection = false
        }
        if value { refreshVisible() } else { thumbnails.suspend() }
    }

    func clear() { thumbnails.clear(); update(entries: [], selection: nil) }

    var firstVisibleID: UUID? {
        collection.indexPathsForVisibleItems().sorted(by: Self.before).first.flatMap(entry)?.id
    }

    func scroll(to id: UUID) {
        guard let path = indexPath(id) else { return }
        collection.scrollToItems(at: [path], scrollPosition: .top)
        refreshVisible()
    }

    func refreshVisible() {
        guard visible, !refreshing else { return }
        refreshing = true; defer { refreshing = false }
        collection.layoutSubtreeIfNeeded()
        let paths = collection.indexPathsForVisibleItems().sorted(by: Self.before)
        for path in paths { if let value = entry(path) { updateImage(value.id) } }
        thumbnails.update(visible: paths.compactMap(entry), backing: scrollView.window?.backingScaleFactor ?? 1)
    }

    func resize() {
        guard visible else { return }
        layout.invalidateLayout()
        refreshVisible()
    }

    @objc private func viewportChanged() { refreshVisible() }
    private static func before(_ a: IndexPath, _ b: IndexPath) -> Bool {
        a.section == b.section ? a.item < b.item : a.section < b.section
    }

    private func entry(_ path: IndexPath) -> RiftHistoryEntry? {
        guard sections.indices.contains(path.section), sections[path.section].entries.indices.contains(path.item) else { return nil }
        return sections[path.section].entries[path.item]
    }

    private func indexPath(_ id: UUID) -> IndexPath? {
        for (section, group) in sections.enumerated() {
            if let item = group.entries.firstIndex(where: { $0.id == id }) { return IndexPath(item: item, section: section) }
        }
        return nil
    }

    private func updateImage(_ id: UUID) {
        guard let path = indexPath(id), let value = entry(path),
              let item = collection.item(at: path) as? HistoryGridItem else { return }
        item.setImage(thumbnails.loadedImage(for: value.record.image), asset: value.record.image,
                      unavailable: thumbnails.failed(value.record.image))
    }

    func numberOfSections(in collectionView: NSCollectionView) -> Int { visible ? sections.count : 0 }
    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int { sections[section].entries.count }
    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: .init("history.grid.item"), for: indexPath)
        if let cell = item as? HistoryGridItem, let value = entry(indexPath) {
            cell.configure(entry: value, state: stateText(value), copy: copy, onSelection: { [weak self] selected in
                self?.selectFromAccessibility(value.id, selected: selected) ?? false
            })
            cell.setImage(thumbnails.loadedImage(for: value.record.image), asset: value.record.image,
                          unavailable: thumbnails.failed(value.record.image))
        }
        return item
    }
    func collectionView(_ collectionView: NSCollectionView, viewForSupplementaryElementOfKind kind: NSCollectionView.SupplementaryElementKind,
                        at indexPath: IndexPath) -> NSView {
        let view = collectionView.makeSupplementaryView(ofKind: kind, withIdentifier: .init("history.grid.header"), for: indexPath)
        (view as? HistoryGridHeader)?.label.stringValue = sections[indexPath.section].title
        return view
    }
    func collectionView(_ collectionView: NSCollectionView, layout collectionViewLayout: NSCollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> NSSize {
        // During a resize, the viewport and document can update in either
        // order. Every item must fit both of their current widths.
        let insets = sectionInsets(for: collectionView)
        let available = max(0, layoutWidth(for: collectionView) - insets.left - insets.right)
        let columns = max(1, Int((available + 16) / 156))
        return NSSize(width: floor((available - CGFloat(columns - 1) * 16) / CGFloat(columns)), height: 144)
    }
    func collectionView(_ collectionView: NSCollectionView, layout collectionViewLayout: NSCollectionViewLayout,
                        insetForSectionAt section: Int) -> NSEdgeInsets { sectionInsets(for: collectionView) }

    private func layoutWidth(for collectionView: NSCollectionView) -> CGFloat {
        let scroll = collectionView.enclosingScrollView
        let content = scroll?.contentInsets ?? NSEdgeInsetsZero
        let viewport = scroll?.contentView.bounds.width ?? collectionView.bounds.width
        let width = min(collectionView.bounds.width, viewport)
        return max(0, width - max(0, content.left) - max(0, content.right))
    }

    private func sectionInsets(for collectionView: NSCollectionView) -> NSEdgeInsets {
        // Preserve 24-point margins at normal widths; an initial/narrow native
        // layout must not reserve more horizontal inset than its entire width.
        let horizontal = min(24, max(0, (layoutWidth(for: collectionView) - 1) / 2))
        return NSEdgeInsets(top: 4, left: horizontal, bottom: 20, right: horizontal)
    }
    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        guard !suppressSelection, let value = indexPaths.sorted(by: Self.before).first.flatMap(entry) else { return }
        selectedID = value.id; onSelection(value.id)
    }
    func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) {
        guard !suppressSelection else { return }
        // Moving between items may report deselection before selection. Do not
        // close a shared original window/lose its zoom for that transient gap.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.visible, !self.suppressSelection,
                  self.collection.selectionIndexPaths.isEmpty else { return }
            self.selectedID = nil; self.onSelection(nil)
        }
    }
}

@MainActor
final class HistoryGridCollectionView: NSCollectionView {
    var onPreview: (() -> Void)?

    override func setFrameSize(_ newSize: NSSize) {
        // Drop cached item widths before AppKit lays out the narrower document.
        if newSize.width != frame.width { collectionViewLayout?.invalidateLayout() }
        super.setFrameSize(newSize)
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 49, event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
            onPreview?(); return
        }
        super.keyDown(with: event)
    }
    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        if event.clickCount == 2, !selectionIndexPaths.isEmpty { onPreview?() }
    }
}

@MainActor
private final class HistoryGridSurface: NSView {
    var selected = false { didSet { needsDisplay = true } }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        let box = bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: box, xRadius: 6, yRadius: 6)
        HistoryGridStyle.secondarySurface.setFill(); path.fill()
        (selected ? HistoryGridStyle.accent : HistoryGridStyle.border).setStroke()
        let match = effectiveAppearance.bestMatch(from: [.accessibilityHighContrastAqua,
            .accessibilityHighContrastDarkAqua, .aqua, .darkAqua])
        path.lineWidth = selected || match == .accessibilityHighContrastAqua || match == .accessibilityHighContrastDarkAqua ? 2 : 1
        path.stroke()
    }
}

@MainActor
private final class HistoryGridItemView: NSView {
    var selected = false
    var onSelection: ((Bool) -> Bool)?

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .cell }
    override func accessibilityChildren() -> [Any]? { [] }
    override func isAccessibilitySelected() -> Bool { selected }
    override func setAccessibilitySelected(_ selected: Bool) { _ = onSelection?(selected) }
    override func accessibilityPerformPress() -> Bool { onSelection?(true) ?? false }
}

@MainActor
private final class HistoryGridItem: NSCollectionViewItem {
    private let itemView = HistoryGridItemView()
    private let slot = HistoryGridSurface()
    private let image = NSImageView()
    private let time = NSTextField(labelWithString: "")
    private let state = NSTextField(labelWithString: "")
    private var copy: ProductCopy = .current
    private let placeholder = NSTextField(labelWithString: "")
    private var representedAsset: ImportedAsset?
    private var imageIdentity: HistoryPreviewFileIdentity?
    private var imageURL: URL?

    override var isSelected: Bool {
        didSet {
            slot.selected = isSelected
            itemView.selected = isSelected
        }
    }
    override func prepareForReuse() {
        super.prepareForReuse(); image.image = nil
        representedAsset = nil; imageIdentity = nil; imageURL = nil
        itemView.onSelection = nil; itemView.selected = false
        itemView.setAccessibilityIdentifier(nil); itemView.setAccessibilityLabel(nil)
    }

    override func loadView() {
        view = itemView
        image.imageScaling = .scaleProportionallyUpOrDown
        time.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular); time.textColor = HistoryGridStyle.secondary
        state.font = .systemFont(ofSize: 11); state.textColor = HistoryGridStyle.secondary
        state.lineBreakMode = .byTruncatingTail
        placeholder.font = .systemFont(ofSize: 11); placeholder.textColor = HistoryGridStyle.secondary
        for v in [slot, time, state] { v.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(v) }
        for v in [image, placeholder] { v.translatesAutoresizingMaskIntoConstraints = false; slot.addSubview(v) }
        NSLayoutConstraint.activate([
            slot.leadingAnchor.constraint(equalTo: view.leadingAnchor), slot.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            slot.topAnchor.constraint(equalTo: view.topAnchor), slot.heightAnchor.constraint(equalToConstant: 108),
            image.leadingAnchor.constraint(equalTo: slot.leadingAnchor, constant: 10), image.trailingAnchor.constraint(equalTo: slot.trailingAnchor, constant: -10),
            image.topAnchor.constraint(equalTo: slot.topAnchor, constant: 10), image.bottomAnchor.constraint(equalTo: slot.bottomAnchor, constant: -10),
            placeholder.centerXAnchor.constraint(equalTo: slot.centerXAnchor), placeholder.centerYAnchor.constraint(equalTo: slot.centerYAnchor),
            time.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 2), time.topAnchor.constraint(equalTo: slot.bottomAnchor, constant: 5),
            state.leadingAnchor.constraint(equalTo: time.leadingAnchor), state.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -2),
            state.topAnchor.constraint(equalTo: time.bottomAnchor, constant: 2)])
    }

    func configure(entry: RiftHistoryEntry, state: String, copy: ProductCopy = .current, onSelection: @escaping (Bool) -> Bool) {
        _ = view
        let format = DateFormatter(); format.dateFormat = "HH:mm"
        time.stringValue = format.string(from: HistoryPresentation.captureDate(for: entry))
        self.copy = copy
        self.state.stringValue = state
        view.identifier = .init("history.grid.item." + entry.id.uuidString)
        view.toolTip = HistoryPresentation.dateText(for: entry) + " · " + state
        itemView.setAccessibilityIdentifier(view.identifier?.rawValue)
        itemView.setAccessibilityLabel(copy.text("\(HistoryPresentation.dateText(for: entry))，\(entry.record.image.pixelWidth) × \(entry.record.image.pixelHeight)，\(state)，编号 \(entry.id.uuidString.prefix(8))",
            "\(HistoryPresentation.dateText(for: entry)), \(entry.record.image.pixelWidth) × \(entry.record.image.pixelHeight), \(state), ID \(entry.id.uuidString.prefix(8))"))
        itemView.setAccessibilityHelp(copy.text("选择截图；按空格查看原图。", "Select a screenshot. Press Space to view the original."))
        itemView.selected = isSelected; itemView.onSelection = onSelection
    }

    func setImage(_ value: HistoryPreviewImage?, asset: ImportedAsset, unavailable: Bool = false) {
        if let value, value.identity.matches(value.url) {
            image.image = NSImage(cgImage: value.image, size: .zero)
            representedAsset = asset; imageIdentity = value.identity; imageURL = value.url
        } else if representedAsset != asset || imageURL.map({ imageIdentity?.matches($0) != true }) != false {
            image.image = nil; representedAsset = asset; imageIdentity = nil; imageURL = nil
        }
        // A visible cell may keep its own verified display bitmap after LRU
        // eviction. Reuse/replacement cannot put those pixels under another ID.
        placeholder.isHidden = image.image != nil
        placeholder.stringValue = unavailable ? copy.text("预览不可用", "Preview unavailable") : copy.text("正在加载预览…", "Loading preview…")
    }
}

@MainActor
private final class HistoryGridHeader: NSView {
    let label = NSTextField(labelWithString: "")
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        label.font = .systemFont(ofSize: 12, weight: .medium); label.textColor = HistoryGridStyle.secondary
        label.translatesAutoresizingMaskIntoConstraints = false; addSubview(label)
        NSLayoutConstraint.activate([label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}
