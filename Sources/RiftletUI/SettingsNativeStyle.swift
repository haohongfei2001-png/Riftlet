import AppKit

/// V2 Quiet Edge tokens scoped to the settings surfaces; thumbnail geometry and
/// capture hit regions are deliberately outside this style.
public enum SettingsColorRole: String, Sendable { case window, surface, sidebar, ink, secondary, border, selection, accent, accentInk, warning, warningBackground }
@MainActor public enum SettingsNativeStyle {
    public static let settingsSize = NSSize(width: 960, height: 684)
    public static let settingsMinimumSize = NSSize(width: 760, height: 540)
    public static let sidebarWidth: CGFloat = 184
    public static let controlCenterWidth: CGFloat = 336
    public static let onboardingSize = NSSize(width: 652, height: 608)
    public static func color(_ role: SettingsColorRole) -> NSColor {
        if NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast {
            switch role {
            case .ink, .secondary: return .labelColor
            case .border: return .separatorColor
            default: break
            }
        }
        return NSColor(name: NSColor.Name("Riftlet.Settings." + role.rawValue)) { appearance in
            let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let hex: UInt32
            switch role {
            case .window: hex = dark ? 0x1c2420 : 0xf7f9f8
            case .surface: hex = dark ? 0x26312b : 0xffffff
            case .sidebar: hex = dark ? 0x19241e : 0xedf1ee
            case .ink: hex = dark ? 0xedf3ef : 0x172521
            case .secondary: hex = dark ? 0xadbab1 : 0x59675f
            case .border: hex = dark ? 0x3b4840 : 0xdce2de
            case .selection: hex = dark ? 0x294d3d : 0xdcebe4
            case .accent: hex = dark ? 0x65d2bb : 0x087f73
            case .accentInk: hex = dark ? 0x65d2bb : 0x086d63
            case .warning: hex = dark ? 0xe8bc7e : 0x9b6429
            case .warningBackground: hex = dark ? 0x3a3020 : 0xfaf3e7
            }
            return NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
                           green: CGFloat((hex >> 8) & 255) / 255,
                           blue: CGFloat(hex & 255) / 255, alpha: 1)
        }
    }
    public static func label(_ text: String, role: String = "body") -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        switch role {
        case "title": label.font = .systemFont(ofSize: 22, weight: .semibold)
        case "heading", "rowTitle": label.font = .systemFont(ofSize: 13, weight: .medium)
        case "secondary": label.font = .systemFont(ofSize: 12)
        case "caption": label.font = .systemFont(ofSize: 11)
        default: label.font = .systemFont(ofSize: 13)
        }
        label.textColor = color(role == "secondary" || role == "caption" ? .secondary : .ink)
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        label.maximumNumberOfLines = 0
        return label
    }
    public static func button(_ title: String) -> NSButton {
        let button = NSButton(title: title, target: nil, action: nil)
        button.bezelStyle = .rounded
        button.font = .systemFont(ofSize: 13)
        button.setAccessibilityLabel(title)
        return button
    }
    public static func stack(_ views: [NSView] = [], vertical: Bool = true, spacing: CGFloat = 12) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = vertical ? .vertical : .horizontal
        stack.alignment = vertical ? .leading : .centerY
        stack.spacing = spacing
        return stack
    }
    public static func card() -> SettingsSurfaceView { SettingsSurfaceView(role: .surface, radius: 9) }
}

@MainActor public final class SettingsSurfaceView: NSView {
    public var role: SettingsColorRole { didSet { refreshColors() } }
    public var radius: CGFloat { didSet { layer?.cornerRadius = radius } }
    public init(role: SettingsColorRole = .surface, radius: CGFloat = 0) {
        self.role = role; self.radius = radius
        super.init(frame: .zero)
        wantsLayer = true
        refreshColors()
    }
    public required init?(coder: NSCoder) { nil }
    public override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); refreshColors() }
    public func refreshColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = SettingsNativeStyle.color(role).cgColor
            layer?.cornerRadius = radius
            layer?.borderColor = SettingsNativeStyle.color(.border).cgColor
            layer?.borderWidth = role == .surface ? (NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ? 1.5 : 0.5) : 0
        }
        needsDisplay = true
    }
}
