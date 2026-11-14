import ApplicationServices
import Foundation

/// One-use handoff for the owned native chooser fixture. A client-specific
/// provider must prove the exact choice, selection and submit control. There
/// is no production registration; no action reaches a platform receipt policy.
@MainActor
final class AXPickerFileHandoff: AttachmentTransport {
    enum Stage: String { case beforeSelection, beforeSubmit }
    enum Handoff { case submitted, refused, uncertain }
    enum Refusal: String {
        case draft, owner, window, role, disabled, noPressAction, choice, settlement
    }
    struct Input {
        let matchesDraft: () throws -> Bool
        let matchesChoice: (Stage) throws -> Bool
        /// A receiver may publish selection asynchronously after AXPress. This
        /// callback only observes the original chooser, until a bounded deadline.
        var selectionSettled: () throws -> Bool = { true }
    }
    private let binding: AXPickerInspection
    private let choice: MacAXElement
    private let submit: MacAXElement
    private var consumed = false
    private(set) var lastStage = Stage.beforeSelection
    private(set) var refusal: Refusal?

    init(binding: AXPickerInspection, choice: MacAXElement, submit: MacAXElement) {
        self.binding = binding; self.choice = choice; self.submit = submit
    }

    func handOff(_ input: Input) throws -> Handoff {
        guard !consumed else { return .refused }
        consumed = true
        refusal = try rejection(input, stage: .beforeSelection)
        guard refusal == nil else { return .refused }
        do {
            try binding.driver.press(choice)
            lastStage = .beforeSubmit
            guard try input.selectionSettled() else { refusal = .settlement; return .refused }
            refusal = try rejection(input, stage: .beforeSubmit)
            guard refusal == nil else { return .refused }
            try binding.driver.press(submit)
            return .submitted
        } catch { return .uncertain }
    }

    private func rejection(_ input: Input, stage: Stage) throws -> Refusal? {
        let driver = binding.driver
        guard try binding.originalDraftIsCurrent(input.matchesDraft) else { return .draft }
        for node in [choice, submit] {
            guard try driver.processID(of: node) == binding.process.processID else { return .owner }
            guard try driver.elementAttribute(kAXWindowAttribute, of: node) == binding.window else { return .window }
        }
        guard try driver.stringAttribute(kAXRoleAttribute, of: choice) == kAXRadioButtonRole,
              try driver.stringAttribute(kAXRoleAttribute, of: submit) == kAXButtonRole else { return .role }
        let currentControl = stage == .beforeSelection ? choice : submit
        guard try driver.boolAttribute(kAXEnabledAttribute, of: currentControl) == true else { return .disabled }
        guard try driver.actionNames(of: currentControl).contains(kAXPressAction) else { return .noPressAction }
        return try input.matchesChoice(stage) ? nil : .choice
    }
}
