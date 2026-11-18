import AppKit

@MainActor
private final class TrayTransparencySlider: NSSlider {
    var trackingMouse = false
    var endedTracking: (() -> Void)?
    override func mouseDown(with event: NSEvent) {
        trackingMouse = true
        super.mouseDown(with: event)
        trackingMouse = false
        endedTracking?()
    }
}

@MainActor
extension RiftSettingsCenterController {
    static var cameraChoices: [(String, String?)] {
        [(ProductCopy.text("跟随外观", "Automatic"), nil), (ProductCopy.text("紫", "Violet"), "#8067C7"),
         (ProductCopy.text("蓝", "Blue"), "#367DD9"), (ProductCopy.text("青", "Teal"), "#278F88"),
         (ProductCopy.text("珊瑚", "Coral"), "#C96A58"), (ProductCopy.text("石墨", "Graphite"), "#545B65")]
    }

    func trayAppearanceControls() -> NSView {
        let name = ProductCopy.text("背景透明度", "Background Transparency")
        let slider = TrayTransparencySlider()
        slider.minValue = 0
        slider.maxValue = 0.75
        slider.isContinuous = true
        slider.setAccessibilityLabel(name)
        slider.widthAnchor.constraint(equalToConstant: 142).isActive = true
        configure(slider, id: "tray.transparency") { [weak self, weak slider] in
            guard let self, let slider else { return }
            editingTransparency = true
            previewTransparency = slider.doubleValue
            previewAppearance(debounce: !slider.trackingMouse)
        }
        slider.endedTracking = { [weak self] in self?.flushTrayAppearance() }
        let reset = makeButton(ProductCopy.text("复原", "Reset"), id: "tray.transparency.reset") { [weak self] in
            guard let self else { return }
            editingTransparency = true
            previewTransparency = nil
            flushTrayAppearance()
        }
        reset.setAccessibilityLabel(ProductCopy.text("恢复默认背景透明度", "Restore Default Background Transparency"))
        let ends = SettingsNativeStyle.stack([SettingsNativeStyle.label(ProductCopy.text("更清晰", "Clearer"), role: "secondary"), NSView(),
                                               SettingsNativeStyle.label(ProductCopy.text("更通透", "Lighter"), role: "secondary")], vertical: false, spacing: 0)
        let scale = SettingsNativeStyle.stack([slider, ends], spacing: 2)
        ends.widthAnchor.constraint(equalTo: slider.widthAnchor).isActive = true
        let swatches = SettingsNativeStyle.stack([], vertical: false, spacing: 4)
        for (i, choice) in Self.cameraChoices.enumerated() {
            let swatch = makeButton(choice.0, id: "tray.camera.\(i)") { [weak self] in
                guard let self else { return }
                editingBodyColor = true; previewBodyColor = choice.1
                flushTrayAppearance()
            }
            if choice.1 != nil {
                swatch.imagePosition = .imageOnly
                swatch.widthAnchor.constraint(equalToConstant: 28).isActive = true
            }
            swatch.heightAnchor.constraint(greaterThanOrEqualToConstant: 28).isActive = true
            swatch.toolTip = choice.0
            swatches.addArrangedSubview(swatch)
        }
        let custom = makeButton(ProductCopy.text("自定…", "Custom…"), id: "tray.camera.custom") { [weak self] in self?.showCameraColorPanel() }
        swatches.addArrangedSubview(custom)
        return group([row(name, control: buttonRow([scale, reset])), namedLabel("tray.system.material", role: "secondary"),
                      domainError(.trayBackgroundTransparency),
                      row(ProductCopy.text("相机颜色", "Camera Color"), control: swatches), domainError(.trayCameraBodyColor)])
    }

    private func showCameraColorPanel() {
        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        let value = model.snapshot.owner.settings.configuration.trayCameraBodyColor
        panel.color = Self.sRGB(value) ?? .controlAccentColor
        panel.isContinuous = true
        panel.setTarget(self)
        panel.setAction(#selector(changedCameraColor(_:)))
        panel.orderFront(nil)
    }

    @objc private func changedCameraColor(_ panel: NSColorPanel) {
        guard window.isVisible, selectedPage == .display, model.snapshot.owner.settings.configuration.desktopForm == .tray,
              let color = panel.color.usingColorSpace(.sRGB) else { return }
        let channels = [color.redComponent, color.greenComponent, color.blueComponent].map { Int((min(1, max(0, $0)) * 255).rounded()) }
        editingBodyColor = true
        previewBodyColor = String(format: "#%02X%02X%02X", channels[0], channels[1], channels[2])
        previewAppearance(debounce: true)
    }

    private static func sRGB(_ value: String?) -> NSColor? {
        guard let value, value.count == 7, value.first == "#", let rgb = UInt32(value.dropFirst(), radix: 16) else { return nil }
        return NSColor(srgbRed: CGFloat(rgb >> 16) / 255, green: CGFloat((rgb >> 8) & 255) / 255,
                       blue: CGFloat(rgb & 255) / 255, alpha: 1)
    }

    func previewAppearance(debounce: Bool) {
        let c = displayedTrayConfiguration
        onPreviewChange(c)
        pendingTone?.cancel()
        guard debounce else { return }
        pendingTone = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            if !Task.isCancelled { self?.flushTrayAppearance() }
        }
    }

    private func onPreviewChange(_ c: RiftConfiguration) {
        geometryPreview.update(configuration: c, entryEnabled: model.snapshot.owner.settings.entryEnabled)
        pendingPreview?.cancel()
        pendingPreview = Task { @MainActor [weak self] in
            guard !Task.isCancelled, let self else { return }
            await onAction(.previewTrayAppearance(transparency: c.trayBackgroundTransparency, cameraBodyColor: c.trayCameraBodyColor))
        }
    }

    var displayedTrayConfiguration: RiftConfiguration {
        var c = model.snapshot.owner.settings.configuration
        if editingTransparency { c.trayBackgroundTransparency = previewTransparency }
        if editingBodyColor { c.trayCameraBodyColor = previewBodyColor }
        return c
    }

    func flushTrayAppearance() {
        pendingTone?.cancel(); pendingTone = nil
        pendingPreview?.cancel(); pendingPreview = nil
        if editingTransparency {
            editingTransparency = false
            dispatch(.settings(.setTrayBackgroundTransparency(previewTransparency)))
        }
        if editingBodyColor {
            editingBodyColor = false
            dispatch(.settings(.setTrayCameraBodyColor(previewBodyColor)))
        }
    }

    func renderTrayAppearance() {
        let c = displayedTrayConfiguration
        let value = c.trayBackgroundTransparency ?? RiftTrayGlass.defaultTransparency
        (controls["tray.transparency"] as? NSSlider)?.doubleValue = value
        let editable = product.capabilities.canEditPreferences && !configurationBusy
        let reduced = product.accessibility.reduceTransparency
        enable("tray.transparency", editable && !reduced)
        enable("tray.transparency.reset", editable && c.trayBackgroundTransparency != nil)
        text("tray.system.material", ProductCopy.text("macOS 已启用“减少透明度”。", "Reduce Transparency is enabled in macOS."))
        labels["tray.system.material"]?.isHidden = !reduced
        for (i, choice) in Self.cameraChoices.enumerated() {
            guard let button = controls["tray.camera.\(i)"] as? NSButton else { continue }
            let selected = choice.1 == c.trayCameraBodyColor?.uppercased()
            button.state = selected ? .on : .off
            button.setAccessibilityValue(selected ? ProductCopy.text("已选择", "Selected") : "")
            if let color = Self.sRGB(choice.1) {
                // AppKit tints template symbols monochrome inside rounded push buttons.
                let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
                    color.setFill()
                    NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
                    if selected {
                        let mark = NSBezierPath()
                        mark.move(to: NSPoint(x: 4.5, y: 8)); mark.line(to: NSPoint(x: 7, y: 5.5))
                        mark.line(to: NSPoint(x: 11.5, y: 10.5))
                        NSColor.white.setStroke()
                        mark.lineWidth = 1.6; mark.lineCapStyle = .round; mark.stroke()
                    }
                    return true
                }
                image.isTemplate = false
                button.image = image
            }
            button.isEnabled = editable
        }
        enable("tray.camera.custom", editable)
        let customHex = c.trayCameraBodyColor
        let custom = customHex != nil && !Self.cameraChoices.contains { $0.1 == customHex?.uppercased() }
        buttonTitle("tray.camera.custom", custom ? (customHex ?? "") : ProductCopy.text("自定…", "Custom…"))
    }
}
