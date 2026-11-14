import ApplicationServices
import Foundation

/// AXOpenPanel does not identify the originating conversation. Callers retain
/// the actual process, parent window, editor and entry in a service-specific
/// click binding; direct children of an unrelated panel service are ineligible.
@MainActor
struct AXPickerInspection {
    let driver: any MacAXDriver
    let process: MacAXApplicationIdentity
    let window: MacAXElement
    let editor: MacAXElement
    let entry: MacAXElement

    func originalDraftIsCurrent(_ matchesDraft: () throws -> Bool) throws -> Bool {
        guard driver.isTrusted(),
              try driver.frontmostApplication() == process,
              try driver.applicationIdentity(processID: process.processID) == process else { return false }
        let application = try driver.applicationElement(processID: process.processID)
        guard try driver.elementAttribute(kAXFocusedWindowAttribute, of: application) == window,
              try driver.elementsAttribute(kAXWindowsAttribute, of: application, maximumCount: 64).contains(window),
              try driver.processID(of: window) == process.processID,
              try driver.stringAttribute(kAXRoleAttribute, of: window) == kAXWindowRole,
              try driver.boolAttribute(kAXMinimizedAttribute, of: window) == false else { return false }
        for element in [entry, editor] {
            guard try driver.processID(of: element) == process.processID,
                  try driver.elementAttribute(kAXWindowAttribute, of: element) == window else { return false }
        }
        guard try driver.stringAttribute(kAXRoleAttribute, of: entry) == kAXButtonRole,
              try driver.actionNames(of: entry).contains(kAXPressAction) else { return false }
        return try matchesDraft()
    }

    /// Read-only capability probe. A standalone NSOpenPanel or XPC-hosted sheet
    /// without a proven relationship to the frozen window returns nil. Avoids
    /// press/open on a target when no unattended file delivery is available.
    func attachedSheet(_ matchesDraft: () throws -> Bool) throws -> MacAXElement? {
        guard try originalDraftIsCurrent(matchesDraft) else { return nil }
        let sheets = try driver.elementsAttribute(kAXChildrenAttribute, of: window, maximumCount: 128).filter {
            try driver.stringAttribute(kAXRoleAttribute, of: $0) == kAXSheetRole
        }
        guard sheets.count == 1, let sheet = sheets.first,
              try driver.processID(of: sheet) == process.processID,
              try driver.elementAttribute(kAXWindowAttribute, of: sheet) == window,
              try driver.elementAttribute(kAXParentAttribute, of: sheet) == window,
              try originalDraftIsCurrent(matchesDraft) else { return nil }
        return sheet
    }
}
