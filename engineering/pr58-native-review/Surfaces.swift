import AppKit

@MainActor
final class ReviewSurfaces: NSObject, NSMenuDelegate, NSSearchFieldDelegate {
    typealias UI = SurfaceStyle
    static let scenes = ["intro-capture", "intro-connect", "intro-place", "history-list", "history-grid", "history-unknown",
                         "control", "control-paused", "control-hidden", "control-both", "permission", "feedback"]

    static func title(for scene: String) -> String {
        let names = ["首用 · 截图", "首用 · 连接", "首用 · 位置", "历史 · 列表", "历史 · 图像",
                     "历史 · 待核实", "控制中心 · 收录中", "控制中心 · 已暂停", "控制中心 · 已隐藏",
                     "控制中心 · 暂停并隐藏", "权限恢复", "反馈"]
        return scenes.firstIndex(of: scene).map { names[$0] } ?? scene
    }

    var onSettings: (() -> Void)?
    var onReviewValueChange: ((String, String) -> Void)?
    private let popover = NSPopover()
    private var status: NSStatusItem?
    private var presented: NSWindow?
    private var original: NSWindow?
    private var popupAnchor: NSWindow?
    private var paused = false, hidden = false, builtin = true
    private var controlExample: (paused: Bool, hidden: Bool)?
    private var step = 0, placement = 4, selected = 0, filter = 0
    private var grid = false
    private weak var historyStyleControl: NSSegmentedControl?
    private var restored = Set<Int>()
    private var query = "", draft = "", includeDetails = false
    private var historyWindow: NSWindow?
    private var historyHost: NSView?
    private var permissionTopic = 0
    private var permissionExpanded = false
    private var currentScene = ""
    private weak var feedbackField: NSTextView?

    override init() {
        super.init()
        popover.behavior = .transient
        popover.animates = false
    }

    func applyReviewValue(_ key: String, _ value: String) {
        switch key {
        case "collection":
            paused = value == "off"
            controlExample?.paused = paused
        case "hidden":
            hidden = value == "on"
            controlExample?.hidden = hidden
        case "built-in": builtin = value == "on"
        case "history-style":
            grid = value == "图像网格"
            historyStyleControl?.selectedSegment = grid ? 1 : 0
            if historyHost != nil { renderRecords() }
        default: return
        }
        if popover.isShown { renderPopover() }
    }

    private func setReviewValue(_ key: String, _ value: String) {
        applyReviewValue(key, value)
        onReviewValueChange?(key, value)
    }

    func dismiss() {
        if currentScene == "feedback" { draft = feedbackField?.string ?? draft }
        popover.performClose(nil)
        controlExample = nil
        original?.orderOut(nil)
        original = nil
        presented?.orderOut(nil)
        presented = nil
        popupAnchor?.orderOut(nil)
        popupAnchor = nil
        historyHost = nil
        historyWindow = nil
    }

    @discardableResult func show(_ scene: String) -> NSWindow? {
        dismiss()
        currentScene = scene
        switch scene {
        case "intro-capture", "intro-connect", "intro-place":
            step = ["intro-capture", "intro-connect", "intro-place"].firstIndex(of: scene) ?? 0
            return showIntro()
        case "history-list", "history-grid", "history-unknown":
            if scene != "history-unknown" {
                setReviewValue("history-style", scene == "history-grid" ? "图像网格" : "列表")
            }
            selected = scene == "history-unknown" ? 2 : 0
            filter = 0
            query = ""
            return showHistory()
        case "permission":
            permissionExpanded = false
            return showPermission()
        case "feedback": return showFeedback()
        case "control-current": return showPopover()
        case "control", "control-paused", "control-hidden", "control-both":
            controlExample = (paused: scene == "control-paused" || scene == "control-both",
                              hidden: scene == "control-hidden" || scene == "control-both")
            return showPopover()
        default: return nil
        }
    }

    private func window(_ title: String, width: CGFloat, height: CGFloat) -> NSWindow {
        let w = NSWindow(contentRect: .init(x: 0, y: 0, width: width, height: height),
                         styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        w.title = title
        w.isReleasedWhenClosed = false
        w.center()
        presented = w
        return w
    }

    private func present(_ w: NSWindow, _ body: NSView) -> NSWindow {
        let host = UI.material(.windowBackground)
        w.contentView = host
        UI.fill(body, in: host)
        w.orderFront(nil)
        return w
    }

    private func showIntro() -> NSWindow {
        let w = presented ?? window("开始使用 Riftlet", width: 584, height: 417)
        let titles = ["从一张截图开始", "连接截图与草稿", "选一个顺手的位置"]
        let descriptions = ["照常按 ⇧⌘4 截图。在 Chrome 打开目标聊天，点一下桌面边缘的图片，即可附到草稿。",
                            "截图文件夹提供原图。通过 Chrome 附加时，Riftlet 需要自动化访问。",
                            "新截图会从所选的屏幕边缘出现。之后可以在设置中调整。"]
        let phases = ["截图", "连接", "位置"]
        var phaseLabels: [NSView] = []
        for i in phases.indices {
            if i > 0 { phaseLabels.append(UI.symbol("chevron.right", size: 9, color: .tertiaryLabelColor)) }
            phaseLabels.append(UI.label(phases[i], 12, weight: i == step ? .semibold : .regular,
                                        color: i == step ? UI.teal : .secondaryLabelColor))
        }
        let heading = UI.series([UI.stack(phaseLabels, horizontal: true, gap: 9),
                                 UI.label(titles[step], 29, weight: .semibold),
                                 UI.label(descriptions[step], 14, color: .secondaryLabelColor)], gap: 10)
        let middle: NSView
        if step == 1 {
            let source = UI.row("folder", "截图文件夹", "下载", trailing: UI.label("可收录", 12, color: UI.teal))
            let chrome = UI.row("macwindow", "Chrome 自动化", "首次附加时按系统提示选择允许")
            let help = UI.button("查看授权说明", plain: true) { [weak self] in
                guard let self else { return }
                self.permissionTopic = 1
                _ = self.show("permission")
            }
            middle = UI.series([source, UI.line(), chrome, UI.stack([help, UI.spacer()], horizontal: true)], gap: 12)
        } else {
            let diagram = SurfaceDesktopDiagram(stage: step, placement: placement)
            diagram.heightAnchor.constraint(equalToConstant: step == 0 ? 169 : 134).isActive = true
            if step == 2 {
                let names = ["左上", "左中", "左下", "右上", "右中", "右下"]
                let selector = NSSegmentedControl(labels: names, trackingMode: .selectOne, target: self, action: #selector(setPlacement))
                selector.selectedSegment = placement
                selector.setAccessibilityLabel("屏幕位置")
                middle = UI.series([diagram, selector], gap: 12)
            } else { middle = diagram }
        }
        let next = UI.button(step == 2 ? "完成" : "继续") { [weak self] in
            guard let self else { return }
            if self.step == 2 { self.dismiss() } else { self.step += 1; _ = self.showIntro() }
        }
        next.keyEquivalent = "\r"
        let back = UI.button(step == 0 ? "稍后设置" : "上一步") { [weak self] in
            guard let self else { return }
            if self.step == 0 { self.dismiss() } else { self.step -= 1; _ = self.showIntro() }
        }
        let body = UI.series([heading, middle, NSView(), UI.line(), UI.stack([back, UI.spacer(), next], horizontal: true)], gap: 17)
        return present(w, UI.pad(body, 28))
    }

    @objc private func setPlacement(_ sender: NSSegmentedControl) {
        placement = sender.selectedSegment
        _ = showIntro()
    }

    private func showHistory() -> NSWindow {
        let w = window("截图历史", width: 808, height: 460)
        w.titleVisibility = .hidden
        historyWindow = w
        w.contentMinSize = NSSize(width: 808, height: 460)
        w.contentMaxSize = w.contentMinSize
        let head = UI.stack([UI.label("截图历史", 24, weight: .semibold), UI.spacer()], horizontal: true)
        let search = NSSearchField()
        search.placeholderString = "搜索截图"
        search.setAccessibilityLabel("搜索截图")
        search.delegate = self
        search.widthAnchor.constraint(equalToConstant: 148).isActive = true
        let popup = NSPopUpButton()
        popup.addItems(withTitles: ["全部状态", "已归档", "已附加", "待核实", "在桌面"])
        popup.target = self
        popup.action = #selector(filterChanged)
        popup.setAccessibilityLabel("状态筛选")
        let viewMode = NSSegmentedControl(images: ["list.bullet", "square.grid.2x2"].map { NSImage(systemSymbolName: $0, accessibilityDescription: nil)! },
                                          trackingMode: .selectOne, target: self, action: #selector(viewModeChanged))
        viewMode.setAccessibilityLabel("历史样式")
        viewMode.setToolTip("列表", forSegment: 0)
        viewMode.setToolTip("图像网格", forSegment: 1)
        historyStyleControl = viewMode
        viewMode.selectedSegment = grid ? 1 : 0
        for control in [search, popup, viewMode] as [NSView] { head.addArrangedSubview(control) }
        let host = NSView()
        historyHost = host
        let wrapper = UI.series([UI.pad(head, 17), UI.line(), host])
        let result = present(w, wrapper)
        renderRecords()
        return result
    }

    func controlTextDidChange(_ obj: Notification) {
        guard let search = obj.object as? NSSearchField else { return }
        query = search.stringValue
        renderRecords()
    }

    @objc private func filterChanged(_ sender: NSPopUpButton) { filter = sender.indexOfSelectedItem; renderRecords() }
    @objc private func viewModeChanged(_ sender: NSSegmentedControl) {
        setReviewValue("history-style", sender.selectedSegment == 1 ? "图像网格" : "列表")
    }

    private func state(_ index: Int) -> String { restored.contains(index) ? "在桌面" : SurfaceImages.items[index].3 }

    private func renderRecords() {
        guard let host = historyHost else { return }
        host.subviews.forEach { $0.removeFromSuperview() }
        let filters = ["全部状态", "已归档", "已附加", "待核实", "在桌面"]
        let ids = SurfaceImages.items.indices.filter {
            (filter == 0 || filters[filter] == state($0)) && (query.isEmpty || SurfaceImages.items[$0].1.contains(query))
        }
        if !ids.contains(selected), let first = ids.first { selected = first }
        let date = UI.label("今天", 13, weight: .semibold, color: .secondaryLabelColor)
        var records: [NSView] = [UI.stack([date, UI.spacer(), UI.label("\(ids.count) 张", 12, color: .secondaryLabelColor)], horizontal: true)]
        if ids.isEmpty { records.append(UI.label("没有匹配的截图", 13, color: .secondaryLabelColor)) }
        if grid {
            var pair: [NSView] = []
            for i in ids {
                pair.append(recordView(i))
                if pair.count == 2 { records.append(UI.stack(pair, horizontal: true, gap: 8)); pair = [] }
            }
            if !pair.isEmpty { records.append(UI.stack(pair + [UI.spacer()], horizontal: true, gap: 8)) }
        } else { records += ids.map(recordView) }
        let list = UI.series(records + [NSView()], gap: 10)
        let pane = UI.pad(list, 16, material: .sidebar)
        pane.widthAnchor.constraint(equalToConstant: grid ? 345 : 275).isActive = true
        let detail: NSView
        if ids.isEmpty { detail = NSView() } else {
            let name = SurfaceImages.items[selected].1
            let time = SurfaceImages.items[selected].2
            let image = SurfaceDetailImage()
            image.image = SurfaceImages.load(SurfaceImages.items[selected].0)
            image.imageScaling = .scaleProportionallyUpOrDown
            image.setAccessibilityLabel(name)
            let preview = UI.material(.underWindowBackground)
            preview.wantsLayer = true
            preview.layer?.cornerRadius = 7
            preview.layer?.masksToBounds = true
            UI.fill(image, in: preview, inset: 9)
            preview.heightAnchor.constraint(equalToConstant: 211).isActive = true
            let caption = UI.label(name, 19, weight: .semibold)
            let facts = UI.label("今天 \(time)　·　\(state(selected))", 12, color: .secondaryLabelColor)
            let bigger = UI.button("查看原图", image: "magnifyingglass") { [weak self] in self?.showOriginal() }
            var actions: [NSView] = [bigger]
            if selected == 0 && !restored.contains(0) {
                actions.append(UI.button("恢复到桌面", image: "arrow.uturn.backward") { [weak self] in
                    self?.restored.insert(0); self?.renderRecords()
                })
            }
            var parts: [NSView] = [preview, UI.series([caption, facts], gap: 4)]
            if selected == 2 { parts.append(UI.label("这次附加的结果尚待核实，请先检查原聊天的附件。", 12, color: .secondaryLabelColor)) }
            parts += [NSView(), UI.stack(actions + [UI.spacer()], horizontal: true)]
            detail = UI.pad(UI.series(parts, gap: 10), 19)
        }
        let divider = UI.line(vertical: true)
        for view in [pane, divider, detail] {
            host.addSubview(view)
            view.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([view.topAnchor.constraint(equalTo: host.topAnchor),
                                         view.bottomAnchor.constraint(equalTo: host.bottomAnchor)])
        }
        NSLayoutConstraint.activate([pane.leadingAnchor.constraint(equalTo: host.leadingAnchor),
                                     divider.leadingAnchor.constraint(equalTo: pane.trailingAnchor),
                                     detail.leadingAnchor.constraint(equalTo: divider.trailingAnchor),
                                     detail.trailingAnchor.constraint(equalTo: host.trailingAnchor)])
    }

    private func recordView(_ i: Int) -> NSView {
        let name = SurfaceImages.items[i].1
        let snippet = SurfaceImages.preview(i, size: grid ? .init(width: 125, height: 64) : .init(width: 54, height: 38))
        let title = UI.label(name, 12, weight: .medium)
        let meta = UI.label(grid ? SurfaceImages.items[i].2 : SurfaceImages.items[i].2 + "　·　" + state(i), 11, color: .secondaryLabelColor)
        let items = grid ? UI.stack([snippet,title,meta], gap: 3) : UI.stack([snippet,UI.stack([title,meta], gap: 4),UI.spacer()], horizontal: true)
        let select = UI.button("", plain: true) { [weak self] in self?.selected = i; self?.renderRecords() }
        select.setAccessibilityLabel(name + "，" + state(i))
        select.title = ""
        let host = NSView()
        host.wantsLayer = true
        host.layer?.cornerRadius = 6
        if i == selected {
            host.layer?.backgroundColor = UI.teal.withAlphaComponent(0.12).cgColor
            host.layer?.borderColor = UI.teal.withAlphaComponent(0.50).cgColor
            host.layer?.borderWidth = 1
        }
        UI.fill(items, in: host, inset: 8)
        UI.fill(select, in: host)
        return host
    }

    private func showOriginal() {
        original?.orderOut(nil)
        let w = NSWindow(contentRect: .init(x: 0, y: 0, width: 640, height: 450), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        w.title = SurfaceImages.items[selected].1
        w.isReleasedWhenClosed = false
        let v = NSImageView()
        v.image = SurfaceImages.load(SurfaceImages.items[selected].0)
        v.imageScaling = .scaleProportionallyUpOrDown
        v.setAccessibilityLabel(w.title)
        w.contentView = v
        w.center()
        w.orderFront(nil)
        original = w
    }

    private func installStatusItem() -> NSStatusBarButton? {
        if let status { return status.button }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status = item
        guard let b = item.button else { return nil }
        b.image = NSImage(systemSymbolName: "rectangle.inset.filled.and.camera", accessibilityDescription: "Riftlet 视觉审查") ??
                  NSImage(systemSymbolName: "camera", accessibilityDescription: "Riftlet 视觉审查")
        b.target = self
        b.action = #selector(statusClicked)
        b.sendAction(on: [.leftMouseUp, .rightMouseUp])
        b.toolTip = "Riftlet · 原生视觉审查"
        return b
    }

    @objc private func statusClicked() {
        guard let item = status else { return }
        if NSApp.currentEvent?.type == .rightMouseUp || NSApp.currentEvent?.modifierFlags.contains(.control) == true {
            popover.performClose(nil)
            let menu = NSMenu()
            menu.delegate = self
            func add(_ title: String, _ action: @escaping () -> Void) {
                let item = SurfaceMenuAction(title: title, action: #selector(SurfaceMenuAction.invoke), keyEquivalent: "")
                item.target = item
                item.clicked = action
                menu.addItem(item)
            }
            add(paused ? "继续收录" : "暂停收录") { [weak self] in guard let self else { return }; self.setReviewValue("collection", self.paused ? "on" : "off") }
            add(hidden ? "显示桌面截图" : "隐藏桌面截图") { [weak self] in guard let self else { return }; self.setReviewValue("hidden", self.hidden ? "off" : "on") }
            menu.addItem(.separator())
            add("截图历史…") { [weak self] in guard let self else { return }; _ = self.show(self.grid ? "history-grid" : "history-list") }
            add("设置…") { [weak self] in self?.openSettings() }
            item.menu = menu
            item.button?.performClick(nil)
        } else if popover.isShown { popover.performClose(nil) }
        else { controlExample = nil; _ = showPopover() }
    }

    func menuDidClose(_ menu: NSMenu) { status?.menu = nil }

    private func openSettings() {
        dismiss()
        onSettings?()
    }

    private func showPopover() -> NSWindow? {
        guard let anchor = installStatusItem() else { return nil }
        let viewController = NSViewController()
        popover.contentViewController = viewController
        renderPopover()
        var origin: NSView = anchor
        if anchor.window == nil || anchor.window?.isOnActiveSpace == false || anchor.visibleRect.isEmpty {
            let fallback = NSPanel(contentRect: .init(x: 0, y: 0, width: 32, height: 26), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            fallback.isReleasedWhenClosed = false
            let target = NSView(frame: .init(x: 0, y: 0, width: 32, height: 26))
            fallback.contentView = target
            fallback.center()
            fallback.orderFront(nil)
            popupAnchor = fallback
            origin = target
        }
        popover.show(relativeTo: origin.bounds, of: origin, preferredEdge: .minY)
        return viewController.view.window
    }

    private func renderPopover() {
        guard let vc = popover.contentViewController else { return }
        let paused = controlExample?.paused ?? self.paused
        let hidden = controlExample?.hidden ?? self.hidden
        let symbol = UI.symbol(paused ? "pause.circle" : "circle.fill", size: paused ? 17 : 11,
                               color: paused ? .secondaryLabelColor : UI.teal)
        let state = UI.stack([symbol, UI.label(paused ? "已暂停收录" : "正在收录截图", 17, weight: .semibold), UI.spacer()], horizontal: true)
        let position = UI.label(hidden ? "桌面截图已隐藏" : "桌面截图已显示", 12, color: .secondaryLabelColor)
        let primary = UI.button("截图…", image: "camera") { [weak self] in self?.explainCapturePreview() }
        primary.isEnabled = builtin && !hidden
        primary.toolTip = !builtin ? "内置截图已关闭" : (hidden ? "显示桌面截图后可使用内置截图" : "预览内置截图入口")
        let pausedSwitch = NSSwitch()
        pausedSwitch.state = paused ? .on : .off
        pausedSwitch.setAccessibilityLabel("暂停收录")
        pausedSwitch.target = self
        pausedSwitch.action = #selector(togglePause)
        let hiddenSwitch = NSSwitch()
        hiddenSwitch.state = hidden ? .on : .off
        hiddenSwitch.setAccessibilityLabel("隐藏桌面截图")
        hiddenSwitch.target = self
        hiddenSwitch.action = #selector(toggleHidden)
        let history = UI.button("截图历史", image: "clock", plain: true) { [weak self] in guard let self else { return }; _ = self.show(self.grid ? "history-grid" : "history-list") }
        let settings = UI.button("设置", image: "gearshape", plain: true) { [weak self] in self?.openSettings() }
        let heading = UI.series([state, position], gap: 4)
        let body = UI.series([UI.stack([heading, UI.spacer(), primary], horizontal: true), UI.line(),
                              UI.row("pause", "暂停收录", trailing: pausedSwitch),
                              UI.row("eye.slash", "隐藏桌面截图", trailing: hiddenSwitch),
                              UI.line(), UI.stack([history, UI.spacer(), settings], horizontal: true)], gap: 10)
        let host = SurfacePopoverBody()
        UI.fill(body, in: host, inset: 16)
        let width = CGFloat(294)
        host.widthAnchor.constraint(equalToConstant: width).isActive = true
        let height = ceil(host.fittingSize.height)
        vc.view = host
        host.frame = .init(x: 0, y: 0, width: width, height: height)
        popover.contentSize = .init(width: width, height: height)
    }

    private func explainCapturePreview() {
        dismiss()
        let w = window("内置截图", width: 402, height: 184)
        let close = UI.button("完成") { [weak self] in self?.dismiss() }
        close.keyEquivalent = "\r"
        let body = UI.series([UI.symbol("camera", size: 24), UI.label("窗口截图", 19, weight: .semibold),
                              UI.label("正式应用会打开系统截图选择器。此界面预览仅演示入口。", 13, color: .secondaryLabelColor),
                              NSView(), UI.stack([UI.spacer(), close], horizontal: true)], gap: 8)
        _ = present(w, UI.pad(body, 18))
    }

    @objc private func togglePause(_ sender: NSSwitch) { setReviewValue("collection", sender.state == .on ? "off" : "on") }
    @objc private func toggleHidden(_ sender: NSSwitch) { setReviewValue("hidden", sender.state == .on ? "on" : "off") }

    private func showPermission() -> NSWindow {
        let size = NSSize(width: 554, height: permissionExpanded ? 290 : 224)
        let w = presented ?? window("权限与帮助", width: size.width, height: size.height)
        w.setContentSize(size)
        let choices = ["截图文件夹", "Chrome", "内置截图"]
        let labels = ["重新选择截图文件夹", "允许 Chrome 接收附件", "允许内置截图"]
        let notes = ["Riftlet 暂时无法读取已选择的位置。选回系统截图所在的文件夹后，新截图就能进入托盘。",
                     "要把图片附加到当前草稿，请允许 Riftlet 控制 Chrome，并打开 Chrome 的 Apple 事件 JavaScript 选项。",
                     "使用 Riftlet 自带的窗口、区域或全屏截图时，macOS 会询问屏幕录制权限。"]
        let selector = NSSegmentedControl(labels: choices, trackingMode: .selectOne, target: self, action: #selector(topicChanged))
        selector.selectedSegment = permissionTopic
        selector.setAccessibilityLabel("权限类型")
        let icons = ["folder.badge.questionmark", "macwindow", "rectangle.dashed"]
        let icon = UI.symbol(icons[permissionTopic], size: 25)
        let steps = ["打开文件夹选择器，选中系统保存截图的文件夹，点击「打开」。",
                     "在系统设置的「隐私与安全性 → 自动化」允许 Riftlet 控制 Chrome，再在 Chrome 的「显示（或视图）→ 开发者」中允许来自 Apple 事件的 JavaScript。",
                     "打开系统设置的「隐私与安全性 → 屏幕与系统音频录制」，启用 Riftlet，并按 macOS 提示重新打开应用。"]
        let more = UI.button(permissionExpanded ? "收起恢复步骤" : "查看恢复步骤", image: permissionExpanded ? "chevron.up" : "chevron.down") { [weak self] in
            guard let self else { return }; self.permissionExpanded.toggle(); _ = self.showPermission()
        }
        let instruction = UI.label(steps[permissionTopic], 13, color: .secondaryLabelColor)
        let heading = UI.stack([icon, UI.label(labels[permissionTopic], 22, weight: .semibold), UI.spacer()], horizontal: true)
        let parts: [NSView] = [selector, UI.line(), heading, UI.label(notes[permissionTopic], 14, color: .secondaryLabelColor),
                               UI.stack([more, UI.spacer()], horizontal: true)]
        let body = UI.series(parts + (permissionExpanded ? [instruction] : []) + [NSView()], gap: 13)
        return present(w, UI.pad(body, 25))
    }

    @objc private func topicChanged(_ sender: NSSegmentedControl) { permissionTopic = sender.selectedSegment; permissionExpanded = false; _ = showPermission() }

    private func showFeedback() -> NSWindow {
        let w = window("反馈", width: 506, height: 319)
        let heading = UI.label("使用反馈", 25, weight: .semibold)
        let field = NSTextView()
        field.isRichText = false
        field.isAutomaticQuoteSubstitutionEnabled = false
        field.font = .systemFont(ofSize: 14)
        field.textContainerInset = .init(width: 8, height: 8)
        field.backgroundColor = .textBackgroundColor
        field.string = draft
        field.setAccessibilityLabel("遇到的问题或建议")
        let scrolling = NSScrollView()
        scrolling.borderType = .bezelBorder
        scrolling.hasVerticalScroller = true
        scrolling.documentView = field
        field.autoresizingMask = [.width]
        field.isVerticallyResizable = true
        field.textContainer?.widthTracksTextView = true
        scrolling.heightAnchor.constraint(equalToConstant: 96).isActive = true
        feedbackField = field
        let opt = NSButton(checkboxWithTitle: "附上版本与运行状态", target: self, action: #selector(diagnosticChanged))
        opt.state = includeDetails ? .on : .off
        let send = UI.button("发送反馈") {}
        send.isEnabled = false
        send.toolTip = "视觉审查仅在本地保留草稿"
        let body = UI.series([heading, UI.label("你遇到了什么问题？", 13, color: .secondaryLabelColor),
                              scrolling, opt, NSView(), UI.line(), UI.stack([UI.spacer(), send], horizontal: true)], gap: 9)
        return present(w, UI.pad(body, 22))
    }

    @objc private func diagnosticChanged(_ sender: NSButton) { includeDetails = sender.state == .on }
}
