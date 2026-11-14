#if RIFTLET_CONTROLLED_EDGE
import ApplicationServices
import Foundation

/// Only the test build can press an Edge-borne panel. A missing original sheet,
/// unpublished file URLs, or a different folder is a refusal; no path typing.
@MainActor
struct EdgeOwnedFilePanel {
    let binding: AXPickerInspection
    let originalDraft: () throws -> Bool
    let file: URL
    let pinned: NativeMacVerifiedFile

    func awaitSheet() throws -> MacAXElement? {
        let deadline = ProcessInfo.processInfo.systemUptime + 1.5
        repeat {
            do {
                if let sheet = try binding.attachedSheet(originalDraft) { return sheet }
            } catch NativeMacAXError.accessibility(let code) where code == AXError.cannotComplete.rawValue {}
            Thread.sleep(forTimeInterval: 0.04)
        } while ProcessInfo.processInfo.systemUptime < deadline
        return nil
    }

    func submit(_ sheet: MacAXElement) throws -> EdgeConversationPicker.Outcome {
        let driver = binding.driver
        func owned(_ node: MacAXElement) throws -> Bool {
            try driver.processID(of: node) == binding.process.processID &&
                driver.elementAttribute(kAXTopLevelUIElementAttribute, of: node) == sheet
        }
        func exactURL(_ node: MacAXElement) -> Bool {
            var raw: CFTypeRef?
            guard AXUIElementCopyAttributeValue(node.rawValue, kAXURLAttribute as CFString, &raw) == .success,
                  let raw, CFGetTypeID(raw) == CFURLGetTypeID(), let url = raw as? URL, url.isFileURL,
                  let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  [nil, "", "localhost"].contains(parts.host?.lowercased()), parts.user == nil, parts.password == nil,
                  parts.query == nil, parts.fragment == nil, parts.port == nil else { return false }
            return url.standardizedFileURL.path == file.path
        }
        guard try binding.attachedSheet(originalDraft) == sheet else { return .entryAttempted }
        var nodes = [sheet], cursor = 0, matches: [(MacAXElement, MacAXElement)] = []
        let deadline = ProcessInfo.processInfo.systemUptime + 1.5
        while cursor < nodes.count {
            guard ProcessInfo.processInfo.systemUptime < deadline else { return .entryAttempted }
            let node = nodes[cursor]
            cursor += 1
            let role = try driver.stringAttribute(kAXRoleAttribute, of: node)
            if role == kAXTableRole || role == kAXOutlineRole {
                guard try owned(node) else { return .entryAttempted }
                for row in try driver.elementsAttribute(kAXRowsAttribute, of: node, maximumCount: 128) where exactURL(row) {
                    guard try owned(row) else { return .entryAttempted }
                    matches.append((node, row))
                }
            }
            for child in try driver.elementsAttribute(kAXChildrenAttribute, of: node, maximumCount: 128)
                where !nodes.contains(child) {
                guard nodes.count < 256, try driver.processID(of: child) == binding.process.processID else {
                    return .entryAttempted
                }
                nodes.append(child)
            }
        }
        guard matches.count == 1 else { return .entryAttempted }
        let (table, row) = matches[0]
        func originalRow() throws -> Bool {
            try binding.attachedSheet(originalDraft) == sheet && owned(table) && owned(row) &&
                driver.elementsAttribute(kAXRowsAttribute, of: table, maximumCount: 128).filter(exactURL) == [row]
        }
        guard try originalRow() else { return .entryAttempted }
        try pinned.verifyPathAndMetadata()
        let status = AXUIElementSetAttributeValue(table.rawValue, kAXSelectedRowsAttribute as CFString, [row.rawValue] as CFArray)
        guard status == .success else { return .uncertain }
        guard try originalRow(), try driver.elementsAttribute(kAXSelectedRowsAttribute, of: table, maximumCount: 4) == [row],
              let confirm = try driver.elementAttribute(kAXDefaultButtonAttribute, of: sheet), try owned(confirm),
              try driver.stringAttribute(kAXRoleAttribute, of: confirm) == kAXButtonRole,
              try driver.boolAttribute(kAXEnabledAttribute, of: confirm) == true,
              try driver.actionNames(of: confirm).contains(kAXPressAction),
              try driver.elementAttribute(kAXDefaultButtonAttribute, of: sheet) == confirm,
              try originalRow(), try driver.elementsAttribute(kAXSelectedRowsAttribute, of: table, maximumCount: 4) == [row]
        else { return .entryAttempted }
        try pinned.verifyPathAndMetadata()
        try driver.press(confirm)
        return .inputAttempted
    }
}
#endif
