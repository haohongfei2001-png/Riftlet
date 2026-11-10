import AppKit

private final class SettingsFlippedView: NSView { override var isFlipped: Bool { true } }

@MainActor
final class ReviewSettings: NSObject {
    static let pageNames = ["外观与布局", "截图", "使用与历史", "权限与帮助"]
    private let icons = ["rectangle.3.group", "camera", "clock.arrow.circlepath", "hand.raised"]
    private let subtitles = ["让截图停在顺手的屏幕边缘。", "选择收录位置，以及如何开始截图。", "管理截图收录，随时找回本机上的图片。", "按需要的功能检查访问权限。"]
    let window: NSWindow
    var onOpenHistory: (() -> Void)?
    var onReviewValueChange: ((String,String) -> Void)?

    func reviewValue(_ key:String) -> String {
        switch key {
        case "collection": return value("collection","on")
        case "hidden": return value("desktop","on") == "on" ? "off" : "on"
        case "built-in": return value("entry","on")
        case "history-style": return value("history-style","列表")
        default: return ""
        }
    }

    func setReviewValue(_ key:String,_ newValue:String) {
        guard reviewValue(key) != newValue else { return }
        switch (key,newValue) {
        case ("collection","on"),("collection","off"),("history-style","列表"),("history-style","图像网格"):
            save(key,newValue,fromCompanion:true)
        case ("hidden","on"),("hidden","off"):
            save("desktop",newValue == "on" ? "off":"on",fromCompanion:true)
        case ("built-in","on"),("built-in","off"):
            save("entry",newValue,fromCompanion:true)
        default: break
        }
    }
    var prefersHistoryGrid: Bool { prefs["history-style"] == "图像网格" }
    var onShowGuide: (() -> Void)?
    var onOpenFeedback: (() -> Void)?
    private let sidebar = NSVisualEffectView()
    private let nav = NSStackView()
    private let pageHeading = NSTextField(labelWithString: "")
    private let pageDetail = NSTextField(labelWithString: "")
    private let scroll = NSScrollView()
    private let content = NSStackView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let feedbackBar = NSStackView()
    private let retry = NSButton()
    private var page = 0
    private var handlers: [ObjectIdentifier:(NSControl)->Void] = [:]
    private var navButtons: [NSButton] = []
    private var expanded: Set<String> = []
    private var prefs: [String:String]
    private var pending: (key:String,value:String)?
    private let prefURL: URL
    private var isReviewFailureScene = false
    private var messageTask: Task<Void,Never>?
    private static var tint: NSColor {
        NSColor(name:nil) { a in
            a.bestMatch(from:[.darkAqua,.aqua]) == .darkAqua ?
              NSColor(srgbRed:0.25,green:0.84,blue:0.75,alpha:1) :
              NSColor(srgbRed:0.03,green:0.44,blue:0.39,alpha:1)
        }
    }

    override init() {
        let support=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0]
        prefURL=support.appendingPathComponent("Riftlet-PR58-VisualReview/appearance.json")
        prefs=(try? JSONDecoder().decode([String:String].self,from:Data(contentsOf:prefURL))) ?? [:]
        window=NSWindow(contentRect:NSRect(x:0,y:0,width:814,height:580),
                        styleMask:[.titled,.closable,.resizable,.miniaturizable,.fullSizeContentView],
                        backing:.buffered,defer:false)
        super.init()
        window.title = "Riftlet 设置 · 设计预览"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width:716,height:450)
        applyWindowAppearance()
        buildWindow()
        showPage(0)
        window.setContentSize(NSSize(width:814,height:580))
        window.contentMinSize = NSSize(width:716,height:450)
        window.center()
    }

    private func buildWindow() {
        let root=NSView(frame:NSRect(x:0,y:0,width:814,height:580))
        window.contentView=root
        // AppKit also derives the window minimum from the content view. Provide
        // the width of a readable form before the scroll document is fitted.
        root.widthAnchor.constraint(greaterThanOrEqualToConstant:716).isActive=true
        let readingWidth=root.widthAnchor.constraint(equalToConstant:814)
        readingWidth.priority = .init(251)
        readingWidth.isActive=true
        root.heightAnchor.constraint(greaterThanOrEqualToConstant:450).isActive=true
        let panel=NSVisualEffectView()
        panel.material = .contentBackground; panel.blendingMode = .withinWindow; panel.state = .active
        sidebar.material = .sidebar; sidebar.blendingMode = .behindWindow; sidebar.state = .active
        let split=NSBox();split.boxType = .separator
        for v in [sidebar,panel,split] as [NSView] {v.translatesAutoresizingMaskIntoConstraints=false;root.addSubview(v)}
        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo:root.leadingAnchor), sidebar.widthAnchor.constraint(equalToConstant:183),
            sidebar.topAnchor.constraint(equalTo:root.topAnchor), sidebar.bottomAnchor.constraint(equalTo:root.bottomAnchor),
            panel.leadingAnchor.constraint(equalTo:sidebar.trailingAnchor),panel.trailingAnchor.constraint(equalTo:root.trailingAnchor),
            panel.topAnchor.constraint(equalTo:root.topAnchor),panel.bottomAnchor.constraint(equalTo:root.bottomAnchor),
            split.leadingAnchor.constraint(equalTo:sidebar.trailingAnchor),split.topAnchor.constraint(equalTo:root.topAnchor),
            split.bottomAnchor.constraint(equalTo:root.bottomAnchor),split.widthAnchor.constraint(equalToConstant:1)
        ])
        let brand=NSStackView()
        brand.spacing=8
        if let url=Bundle.main.url(forResource:"riftlet",withExtension:"svg"),let image=NSImage(contentsOf:url) {
            let logo=NSImageView(image:image);size(logo,22,22);brand.addArrangedSubview(logo)
        }
        brand.addArrangedSubview(label("Riftlet",19,.semibold))
        let section=label("设置",11,.semibold,.secondaryLabelColor)
        nav.orientation = .vertical;nav.alignment = .leading;nav.spacing=4
        for (i,title) in Self.pageNames.enumerated() {
            let button=NSButton(title:"  "+title,target:self,action:#selector(navigate(_:)))
            button.bezelStyle = .regularSquare;button.isBordered=false;button.alignment = .left
            button.font = .systemFont(ofSize:13,weight:.medium);button.imagePosition = .imageLeading
            button.image=NSImage(systemSymbolName:icons[i],accessibilityDescription:nil)?.withSymbolConfiguration(.init(pointSize:15,weight:.medium))
            button.tag=i;button.setAccessibilityLabel(title);button.wantsLayer=true;button.layer?.cornerRadius=7
            button.identifier=NSUserInterfaceItemIdentifier("settings.page.\(i)")
            size(button,153,34);nav.addArrangedSubview(button);navButtons.append(button)
        }
        let foot=label("原生外观预览",11,.regular,.secondaryLabelColor)
        for v in [brand,section,nav,foot] as [NSView] {v.translatesAutoresizingMaskIntoConstraints=false;sidebar.addSubview(v)}
        NSLayoutConstraint.activate([
            brand.leadingAnchor.constraint(equalTo:sidebar.leadingAnchor,constant:21),brand.topAnchor.constraint(equalTo:sidebar.topAnchor,constant:51),
            section.leadingAnchor.constraint(equalTo:brand.leadingAnchor),section.topAnchor.constraint(equalTo:brand.bottomAnchor,constant:27),
            nav.leadingAnchor.constraint(equalTo:sidebar.leadingAnchor,constant:15),nav.topAnchor.constraint(equalTo:section.bottomAnchor,constant:7),
            foot.leadingAnchor.constraint(equalTo:brand.leadingAnchor),foot.bottomAnchor.constraint(equalTo:sidebar.bottomAnchor,constant:-19)
        ])
        pageHeading.font = .systemFont(ofSize:27,weight:.semibold)
        pageDetail.font = .systemFont(ofSize:13);pageDetail.textColor = .secondaryLabelColor
        let header=NSBox();header.boxType = .separator
        scroll.drawsBackground=false;scroll.hasVerticalScroller=true;scroll.autohidesScrollers=true
        let doc=SettingsFlippedView()
        scroll.documentView=doc
        content.orientation = .vertical;content.alignment = .leading;content.spacing=0
        content.translatesAutoresizingMaskIntoConstraints=false;doc.addSubview(content)
        doc.translatesAutoresizingMaskIntoConstraints=false
        NSLayoutConstraint.activate([
            doc.leadingAnchor.constraint(equalTo:scroll.contentView.leadingAnchor),doc.topAnchor.constraint(equalTo:scroll.contentView.topAnchor),
            doc.widthAnchor.constraint(equalTo:scroll.contentView.widthAnchor),
            content.leadingAnchor.constraint(equalTo:doc.leadingAnchor,constant:30),content.trailingAnchor.constraint(equalTo:doc.trailingAnchor,constant:-30),
            content.topAnchor.constraint(equalTo:doc.topAnchor,constant:15),content.bottomAnchor.constraint(equalTo:doc.bottomAnchor,constant:-22)
        ])
        retry.title="重试";retry.bezelStyle = .inline;retry.target=self;retry.action=#selector(retrySave)
        statusLabel.textColor = .secondaryLabelColor;statusLabel.font = .systemFont(ofSize:11)
        feedbackBar.addArrangedSubview(statusLabel);feedbackBar.addArrangedSubview(retry);feedbackBar.spacing=6
        for v in [pageHeading,pageDetail,header,scroll,feedbackBar] as [NSView] {v.translatesAutoresizingMaskIntoConstraints=false;panel.addSubview(v)}
        NSLayoutConstraint.activate([
            pageHeading.leadingAnchor.constraint(equalTo:panel.leadingAnchor,constant:30),pageHeading.topAnchor.constraint(equalTo:panel.topAnchor,constant:38),
            pageDetail.leadingAnchor.constraint(equalTo:pageHeading.leadingAnchor),pageDetail.topAnchor.constraint(equalTo:pageHeading.bottomAnchor,constant:4),
            header.leadingAnchor.constraint(equalTo:pageHeading.leadingAnchor),header.trailingAnchor.constraint(equalTo:panel.trailingAnchor,constant:-30),
            header.topAnchor.constraint(equalTo:pageDetail.bottomAnchor,constant:17),header.heightAnchor.constraint(equalToConstant:1),
            scroll.leadingAnchor.constraint(equalTo:panel.leadingAnchor),scroll.trailingAnchor.constraint(equalTo:panel.trailingAnchor),
            scroll.topAnchor.constraint(equalTo:header.bottomAnchor),scroll.bottomAnchor.constraint(equalTo:panel.bottomAnchor),
            feedbackBar.trailingAnchor.constraint(equalTo:header.trailingAnchor),feedbackBar.centerYAnchor.constraint(equalTo:pageHeading.centerYAnchor)
        ])
        retry.isHidden=true;window.center()
    }

    @objc private func navigate(_ sender:NSButton) { showPage(sender.tag) }

    func showPage(_ index:Int) {
        guard Self.pageNames.indices.contains(index) else {return}
        if isReviewFailureScene {
            isReviewFailureScene=false
            pending=nil
            notify("")
        }
        page=index;pageHeading.stringValue=Self.pageNames[index];pageDetail.stringValue=subtitles[index]
        for (i,b) in navButtons.enumerated() {
            b.layer?.backgroundColor = i == index ? Self.tint.withAlphaComponent(0.13).cgColor : NSColor.clear.cgColor
            b.contentTintColor = i == index ? Self.tint : .secondaryLabelColor
            b.setAccessibilityValue(i == index ? "已选中" : "")
        }
        render(keepOffset:false)
    }

    func showSaveFailurePreview() {
        showPage(0)
        isReviewFailureScene=true
        pending=("appearance",prefs["appearance"] ?? "跟随系统")
        notify("更改尚未保存",error:true)
    }
    @objc private func retrySave() {
        guard let p=pending else{return}
        save(p.key,p.value)
    }
    private func save(_ key:String,_ value:String,fromCompanion:Bool=false) {
        var next=prefs;next[key]=value
        do {
            try FileManager.default.createDirectory(at:prefURL.deletingLastPathComponent(),withIntermediateDirectories:true)
            try JSONEncoder().encode(next).write(to:prefURL,options:.atomic)
            prefs=next
            if key=="appearance" {applyWindowAppearance()}
            if pending?.key==key {pending=nil}
            if pending==nil {notify("已保存")}
            if let shared=["collection":"collection","desktop":"hidden","entry":"built-in","history-style":"history-style"][key] {
                onReviewValueChange?(shared,reviewValue(shared))
            }
        } catch {
            pending=(key,value);notify("更改尚未保存",error:true)
        }
        if fromCompanion && key != "entry" {
            // Only update this control. In particular, preserve an in-progress
            // archive duration edit when the companion popover changes state.
            if let c=control(in:content,with:.init("settings."+key)) as? NSSwitch {
                c.state=prefs[key]=="off" ? .off:.on
            } else if let c=control(in:content,with:.init("settings."+key)) as? NSSegmentedControl {
                c.selectedSegment=prefersHistoryGrid ? 1:0
            }
        } else if !fromCompanion || page==0 || page==1 {
            render(keepOffset:true)
        }
    }
    private func applyWindowAppearance() {
        switch prefs["appearance"] {
        case "浅色": window.appearance=NSAppearance(named:.aqua)
        case "深色": window.appearance=NSAppearance(named:.darkAqua)
        default: window.appearance=nil
        }
    }
    private func notify(_ text:String,error:Bool=false) {
        messageTask?.cancel()
        statusLabel.stringValue=text;statusLabel.textColor=error ? .systemOrange:.secondaryLabelColor
        retry.isHidden = !error
        if !error {
            messageTask=Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds:2_400_000_000)
                guard !Task.isCancelled else{return}
                self?.statusLabel.stringValue=""
            }
        }
    }
    private func render(keepOffset:Bool) {
        let offset=keepOffset ? scroll.contentView.bounds.origin : NSPoint.zero
        let focus=(window.firstResponder as? NSControl)?.identifier
        handlers.removeAll()
        for view in content.arrangedSubviews {content.removeArrangedSubview(view);view.removeFromSuperview()}
        switch page {case 0:appearancePage();case 1:capturePage();case 2:historyPage();default:accessPage()}
        window.contentView?.layoutSubtreeIfNeeded()
        scroll.contentView.scroll(to:offset);scroll.reflectScrolledClipView(scroll.contentView)
        if keepOffset, let focus, let replacement=control(in:content,with:focus) {window.makeFirstResponder(replacement)}
        window.recalculateKeyViewLoop()
    }
    private func control(in view:NSView,with id:NSUserInterfaceItemIdentifier)->NSControl? {
        if view.identifier==id {return view as? NSControl}
        for v in view.subviews {if let c=control(in:v,with:id){return c}}
        return nil
    }
    private func value(_ key:String,_ fallback:String)->String {prefs[key] ?? fallback}
    private func label(_ text:String,_ pt:CGFloat=13,_ weight:NSFont.Weight = .regular,_ color:NSColor = .labelColor)->NSTextField {
        let result=NSTextField(labelWithString:text)
        result.font = .systemFont(ofSize:pt,weight:weight);result.textColor=color
        return result
    }
    private func size(_ v:NSView,_ w:CGFloat?,_ h:CGFloat) {
        v.heightAnchor.constraint(equalToConstant:h).isActive=true
        if let w {v.widthAnchor.constraint(equalToConstant:w).isActive=true}
    }
    private func add(_ view:NSView) {
        content.addArrangedSubview(view)
        view.widthAnchor.constraint(equalTo:content.widthAnchor).isActive=true
    }
    private func section(_ text:String) {
        let field=label(text,12,.semibold,Self.tint)
        let band=NSView();field.translatesAutoresizingMaskIntoConstraints=false;band.addSubview(field)
        field.leadingAnchor.constraint(equalTo:band.leadingAnchor).isActive=true
        field.bottomAnchor.constraint(equalTo:band.bottomAnchor,constant:-6).isActive=true
        size(band,nil,34);add(band)
    }
    private func row(_ title:String,_ control:NSView,detail:String?=nil) {
        let left=NSStackView();left.orientation = .vertical;left.alignment = .leading;left.spacing=3
        left.addArrangedSubview(label(title,13,.medium))
        if let detail {left.addArrangedSubview(label(detail,11,.regular,.secondaryLabelColor))}
        let line=NSStackView(views:[left,NSView(),control]);line.spacing=10;line.alignment = .centerY
        size(line,nil,detail==nil ? 39:51)
        add(line)
        let sep=NSBox();sep.boxType = .separator;add(sep);sep.heightAnchor.constraint(equalToConstant:1).isActive=true
    }
    private func bind(_ c:NSControl,_ key:String,_ title:String,perform:@escaping (NSControl)->Void) {
        c.identifier = .init("settings."+key);c.setAccessibilityLabel(title)
        c.target=self;c.action=#selector(activate(_:));handlers[ObjectIdentifier(c)]=perform
    }
    @objc private func activate(_ c:NSControl) { handlers[ObjectIdentifier(c)]?(c) }
    private func popup(_ key:String,_ choices:[String],_ defaultValue:String,title:String)->NSPopUpButton {
        let c=NSPopUpButton(frame:.zero,pullsDown:false);c.addItems(withTitles:choices)
        c.selectItem(withTitle:value(key,defaultValue));c.controlSize = .regular
        bind(c,key,title){[weak self] sender in
            if let choice=(sender as? NSPopUpButton)?.titleOfSelectedItem {self?.save(key,choice)}
        }
        return c
    }
    private func displayPicker() -> NSPopUpButton {
        let picker=NSPopUpButton(frame:.zero,pullsDown:false)
        picker.autoenablesItems=false
        let primary="primary"
        picker.addItem(withTitle:"主显示器")
        picker.lastItem?.representedObject=primary
        let screens=NSScreen.screens
        let counts=Dictionary(grouping:screens,by:\.localizedName).mapValues(\.count)
        var ordinal: [String:Int]=[:]
        for screen in screens {
            let name=screen.localizedName
            ordinal[name,default:0]+=1
            let title=counts[name,default:0] > 1 ? name+" · "+String(ordinal[name,default:0]) : name
            let item=NSMenuItem(title:title,action:nil,keyEquivalent:"")
            if let id=(screen.deviceDescription[.init("NSScreenNumber")] as? NSNumber)?.uint32Value,
               let uuid=CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() {
                item.representedObject=CFUUIDCreateString(nil,uuid) as String
            } else {
                item.isEnabled=false
            }
            picker.menu?.addItem(item)
        }
        let current=value("display-uuid",primary)
        if let selected=picker.itemArray.first(where:{ ($0.representedObject as? String)==current }) {
            picker.select(selected)
        } else {
            let missing=NSMenuItem(title:"已选显示器（未连接）",action:nil,keyEquivalent:"")
            missing.isEnabled=false
            picker.menu?.addItem(missing)
            picker.select(missing)
        }
        bind(picker,"display","目标显示器") { [weak self] sender in
            guard let id=(sender as? NSPopUpButton)?.selectedItem?.representedObject as? String else { return }
            self?.save("display-uuid",id)
        }
        return picker
    }
    private func toggle(_ key:String,_ title:String,starts:Bool)->NSSwitch {
        let c=NSSwitch();c.state=value(key,starts ? "on":"off")=="on" ? .on:.off
        bind(c,key,title){[weak self] in self?.save(key,($0 as? NSSwitch)?.state == .on ? "on":"off")};return c
    }
    private func button(_ title:String,_ id:String,_ action:@escaping ()->Void)->NSButton {
        let c=NSButton(title:title,target:nil,action:nil);c.bezelStyle = .rounded
        bind(c,id,title){_ in action()};return c
    }
    private func slider(_ key:String,title:String,range:ClosedRange<Double>,initial:Double,suffix:String) -> NSView {
        let v=Double(value(key,String(initial))) ?? initial
        let field=label(String(Int(v))+suffix,12,.medium,.secondaryLabelColor)
        let c=NSSlider(value:v,minValue:range.lowerBound,maxValue:range.upperBound,target:nil,action:nil)
        c.isContinuous=false;c.widthAnchor.constraint(equalToConstant:103).isActive=true
        bind(c,key,title){[weak self] in self?.save(key,String(Int($0.doubleValue.rounded())))}
        return NSStackView(views:[c,field])
    }
    private func disclosure(_ title:String,key:String,contents:()->Void) {
        let open=expanded.contains(key)
        let c=button(title,key){[weak self] in
            guard let self else{return}
            if open {self.expanded.remove(key)} else {self.expanded.insert(key)}
            self.render(keepOffset:true)
        }
        c.isBordered=false;c.alignment = .left;c.font = .systemFont(ofSize:13,weight:.medium)
        c.image=NSImage(systemSymbolName:open ? "chevron.down":"chevron.right",accessibilityDescription:nil)
        c.imagePosition = .imageLeading;c.contentTintColor = .secondaryLabelColor
        size(c,nil,38);add(c)
        if open {contents()}
    }
    private func segment(_ key:String, labels:[String], initial:String, title:String) -> NSSegmentedControl {
        let s=NSSegmentedControl(labels:labels,trackingMode:.selectOne,target:nil,action:nil)
        s.segmentStyle = .rounded
        s.selectedSegment=labels.firstIndex(of:value(key,initial)) ?? 0
        bind(s,key,title) { [weak self] sender in
            guard let c=sender as? NSSegmentedControl,labels.indices.contains(c.selectedSegment) else{return}
            self?.save(key,labels[c.selectedSegment])
        }
        return s
    }
    private func appearancePage() {
        let isTray=value("form","截图托盘")=="截图托盘"
        let places=["左上","左中","左下","右上","右中","右下"]
        let visual=SettingsDesktopPreview()
        visual.showsTray=isTray;visual.placement=places.firstIndex(of:value("place","右中")) ?? 4
        visual.visible=Int(value("count","3")) ?? 3;visual.includesEntry=value("entry","on")=="on"
        let theme=value("material","紫蓝玻璃")
        visual.hue=theme=="自定义" ? CGFloat(Double(value("hue","255")) ?? 255)/360 : 0.71
        visual.saturation=theme=="系统玻璃" ? 0.02 : (theme=="自定义" ? CGFloat(Double(value("strength","65")) ?? 65)*0.003:0.21)
        visual.setAccessibilityElement(true)
        visual.setAccessibilityRole(.image);visual.setAccessibilityLabel("桌面边缘预览，"+value("place","右中")+"，"+value("form","截图托盘"))
        size(visual,nil,115);add(visual)
        let forms=["截图托盘","风铃","微缝"]
        let chooser=segment("form",labels:forms,initial:"截图托盘",title:"桌面形态")
        chooser.setEnabled(false,forSegment:1)
        chooser.setToolTip("风铃尚缺已确认的设计，暂不可选",forSegment:1)
        row("桌面形态",chooser,detail:"风铃设计待确认。")
        row("屏幕边缘",popup("place",places,"右中",title:"屏幕边缘"))
        row("显示器",displayPicker())
        if isTray {
            row("托盘材质",popup("material",["系统玻璃","紫蓝玻璃","自定义"],"紫蓝玻璃",title:"托盘材质"))
            if theme == "自定义" {
                row("玻璃色调",slider("hue",title:"玻璃色调",range:0...360,initial:255,suffix:"°"))
                row("色彩强度",slider("strength",title:"色彩强度",range:0...100,initial:65,suffix:"%"))
            }
            row("缩略图遮挡",slider("occlusion",title:"缩略图遮挡",range:0...90,initial:0,suffix:"%"))
        }
        row("可见截图",slider("count",title:"可见截图数",range:1...10,initial:3,suffix:" 张"))
        row("窗口外观",popup("appearance",["跟随系统","浅色","深色"],"跟随系统",title:"窗口外观"))
        disclosure("高级布局与动效",key:"fine-layout") {
            row("到达动效",popup("motion",["直接出现","磁力吸入"],"直接出现",title:"截图到达动效"))
            if !isTray {
                row("藏入边缘",slider("hidden-fraction",title:"藏入边缘",range:0...90,initial:25,suffix:"%"))
                for (key,title,initial,maximum) in [("inset","边缘内缩",6,128),("thumb-width","缩略图最大宽度",72,320),("thumb-height","缩略图最大高度",56,240),("pitch","排列间距",60,180),("number","编号大小",11,26),("gap","编号间距",8,32),("left-padding","行内留白",4,64),("hit-width","点击区最小宽度",44,160),("hit-height","点击区最小高度",44,120)] {
                    row(title,slider(key,title:title,range:1...Double(maximum),initial:Double(initial),suffix:" pt"))
                }
            }
            for (key,title,initial) in [("press","轻按反馈",60),("swallow","吞噬",120),("refill","补位",160),("restore","失败返回",180)] {
                row(title,slider(key,title:title,range:0...500,initial:Double(initial),suffix:" ms"))
            }
        }
    }
    private func capturePage() {
        section("macOS 系统截图")
        let shortcuts=NSStackView()
        shortcuts.distribution = .fillEqually;shortcuts.spacing=14
        for (keys,name) in [("⇧ ⌘ 3","全屏"),("⇧ ⌘ 4","区域"),("⇧ ⌘ 5","截图工具栏")] {
            let large=label(keys,19,.medium)
            large.font = .monospacedSystemFont(ofSize:18,weight:.medium)
            let small=label(name,11,.regular,.secondaryLabelColor)
            let group=NSStackView(views:[large,small]);group.orientation = .vertical;group.spacing=5;group.alignment = .centerX
            shortcuts.addArrangedSubview(group)
        }
        size(shortcuts,nil,64);add(shortcuts)
        row("截图保存位置",button("查看访问状态","source-help"){[weak self] in self?.showPage(3)},detail:"下载文件夹")
        section("Riftlet 内置截图")
        row("显示截图入口",toggle("entry","显示内置截图入口",starts:true),detail:"在桌面边缘开始窗口、区域或全屏截图。")
        if value("entry","on")=="on" {
            row("默认截图方式",segment("default-mode",labels:["窗口","区域","全屏"],initial:"窗口",title:"默认截图方式"))
            if value("form","截图托盘")=="截图托盘" {
                disclosure("自定义三个常用键",key:"capture-keys") {
                    for i in 1...3 {row("常用键 "+String(i),popup("fav-"+String(i),["自动","窗口","区域","全屏","留空"],"自动",title:"常用键 "+String(i)))}
                }
            }
        }
    }
    private func historyPage() {
        section("日常使用")
        row("收录系统截图",toggle("collection","收录系统截图",starts:true),detail:"暂停收录后，已收录的截图仍可使用。")
        row("显示桌面截图",toggle("desktop","显示桌面截图",starts:true),detail:"隐藏桌面截图时，仍按收录设置工作。")
        row("登录时启动 Riftlet",label("由系统管理",12,.regular,.secondaryLabelColor))
        section("本机历史")
        row("浏览历史",button("打开历史…","open-history"){[weak self] in self?.onOpenHistory?()},detail:"预览、还原或移除已有截图。")
        row("历史样式",segment("history-style",labels:["列表","图像网格"],initial:"列表",title:"历史样式"))
        row("闲置后归档",popup("archive",["不自动归档","1 小时","8 小时","24 小时","72 小时","自定义"],"24 小时",title:"闲置后归档"))
        if value("archive","24 小时")=="自定义" {
            let hours=NSTextField(string:value("archive-hours","24"))
            hours.alignment = .right
            hours.widthAnchor.constraint(equalToConstant:66).isActive=true
            bind(hours,"archive-hours","归档小时数") { [weak self] sender in
                guard let hours=Double(sender.stringValue), hours.isFinite, hours>=0 else {
                    self?.notify("请输入有效小时数");return
                }
                self?.save("archive-hours",sender.stringValue)
            }
            row("归档时限",NSStackView(views:[hours,label("小时",12,.regular,.secondaryLabelColor)]),detail:"支持小数小时，0 表示不自动归档。")
        }
        disclosure("存储与恢复",key:"restore-info") {
            row("本地备份",label("配置、数据库和原图",12,.regular,.secondaryLabelColor))
            row("未确认的附加结果",label("在历史中查看",12,.regular,.secondaryLabelColor),detail:"保留原图和记录，避免重复附加。")
        }
    }
    private func accessPage() {
        section("访问权限")
        permission("folder","截图文件夹","收录保存到下载文件夹的系统截图。","已允许访问",action:"查看",info:"变更系统截图目录后，可重新选择保存位置并授权。")
        permission("globe","Chrome 自动化","点击桌面截图时，附加到当前 ChatGPT 草稿。","使用时检查",action:"查看",info:"首次附加时允许 Riftlet 控制 Chrome，并允许 Chrome 接收 Apple 事件中的 JavaScript。")
        permission("rectangle.dashed","屏幕录制","用于 Riftlet 的窗口、区域和全屏截图。","使用时请求",action:"查看",info:"在系统设置的屏幕录制权限中允许 Riftlet，返回后重新检查。")
        section("使用帮助")
        row("开始使用",button("查看引导…","start-guide"){[weak self] in self?.onShowGuide?()},detail:"从截取第一张图片到点击附加。")
        disclosure("关于与诊断",key:"about") {
            row("版本",label("PR #58 · 原生设计预览",12,.regular,.secondaryLabelColor))
            row("诊断数据",label("本机保存",12,.regular,.secondaryLabelColor))
            if let open=onOpenFeedback {row("反馈与建议",button("写反馈…","feedback"){open()})}
        }
    }
    private func permission(_ icon:String,_ name:String,_ detail:String,_ state:String,action:String,info:String) {
        let image=NSImageView(image:NSImage(systemSymbolName:icon,accessibilityDescription:nil) ?? NSImage())
        image.contentTintColor=Self.tint;size(image,22,22)
        let labels=NSStackView(views:[label(name,14,.medium),label(detail,11,.regular,.secondaryLabelColor)])
        labels.orientation = .vertical;labels.alignment = .leading;labels.spacing=5
        let key="perm-"+icon
        let accessory=button(expanded.contains(key) ? "收起":action,key){[weak self] in
            guard let self else{return}
            if self.expanded.contains(key){self.expanded.remove(key)}else{self.expanded.insert(key)}
            self.render(keepOffset:true)
        }
        accessory.bezelStyle = .inline;accessory.contentTintColor=Self.tint
        let trail=NSStackView(views:[label(state,11,.medium,.secondaryLabelColor),accessory]);trail.spacing=7
        let line=NSStackView(views:[image,labels,NSView(),trail]);line.spacing=11;line.alignment = .centerY
        size(line,nil,63);add(line)
        if expanded.contains(key) {
            let txt=NSTextField(wrappingLabelWithString:info);txt.font = .systemFont(ofSize:12);txt.textColor = .secondaryLabelColor
            add(txt)
            let gap=NSView();size(gap,nil,8);add(gap)
        }
        let sep=NSBox();sep.boxType = .separator;add(sep);sep.heightAnchor.constraint(equalToConstant:1).isActive=true
    }
}
