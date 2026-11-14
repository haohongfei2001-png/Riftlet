import AppKit

/// A fixture-owned AppKit control. An enabled file choice exposes exactly the
/// action that its target handles. Disabled confirmation exposes no action.
@MainActor final class AXPickerActionButton: NSButton {
    override func accessibilityValue() -> Any? {
        if accessibilityRole() == .radioButton { return NSNumber(value: state == .on) }
        return super.accessibilityValue()
    }
    override func accessibilityActionNames() -> [NSAccessibility.Action] { isEnabled ? [.press] : [] }
    override func isAccessibilitySelectorAllowed(_ selector: Selector) -> Bool {
        if selector == #selector(accessibilityPerformPress) { return isEnabled }
        return super.isAccessibilitySelectorAllowed(selector)
    }
    override func accessibilityPerformPress() -> Bool {
        guard isEnabled, let action, let target else { return false }
        if accessibilityRole() == .radioButton { state = .on }
        return sendAction(action, to: target)
    }
    override func accessibilityPerformAction(_ action: NSAccessibility.Action) {
        if action == .press { _ = accessibilityPerformPress() }
    }
}
