import ApplicationServices
import Foundation

/// One-use handoff for the owned native chooser fixture. A client-specific
/// provider must prove the exact choice, selection and submit control. There
/// is no production registration; no action reaches a platform receipt policy.
@MainActor
final class AXPickerFileHandoff: AttachmentTransport {
    enum Stage { case beforeSelection, beforeSubmit }
    enum Handoff { case submitted, refused, uncertain }
    struct Input {
        let matchesDraft: () throws -> Bool
        let matchesChoice: (Stage) throws -> Bool
    }
    private let binding: AXPickerInspection
    private let choice: MacAXElement
    private let submit: MacAXElement
    private var consumed = false

    init(binding: AXPickerInspection, choice: MacAXElement, submit: MacAXElement) {
        self.binding = binding; self.choice = choice; self.submit = submit
    }

    func handOff(_ input: Input) throws -> Handoff {
        guard !consumed else { return .refused }
        consumed = true
        guard try valid(input, stage: .beforeSelection) else { return .refused }
        do {
            try binding.driver.press(choice)
            guard try valid(input, stage: .beforeSubmit) else { return .refused }
            try binding.driver.press(submit)
            return .submitted
        } catch { return .uncertain }
    }

    private func valid(_ input: Input, stage: Stage) throws -> Bool {
        let driver = binding.driver
        guard try binding.originalDraftIsCurrent(input.matchesDraft) else { return false }
        for node in [choice, submit] {
            guard try driver.processID(of: node) == binding.process.processID,
                  try driver.elementAttribute(kAXWindowAttribute, of: node) == binding.window,
                  try driver.actionNames(of: node).contains(kAXPressAction) else { return false }
        }
        let enabled = stage == .beforeSelection ? choice : submit
        guard try driver.boolAttribute(kAXEnabledAttribute, of: enabled) == true,
              try driver.stringAttribute(kAXRoleAttribute, of: choice) == kAXRadioButtonRole,
              try driver.stringAttribute(kAXRoleAttribute, of: submit) == kAXButtonRole else { return false }
        return try input.matchesChoice(stage)
    }
}
