// Open only the named synthetic button of a browser created by this fixture
// runner on a disposable guest. Never enter paths, edit text, or grant trust.
import AppKit
import ApplicationServices
import Darwin

func attribute(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success else { return nil }
    return value
}

@main struct FirefoxAXProbe {
    static func main() throws {
        var model = [CChar](repeating: 0, count: 128), size = 128
        guard CommandLine.arguments.count == 2, let pid = Int32(CommandLine.arguments[1]),
              sysctlbyname("hw.model", &model, &size, nil, 0) == 0, String(cString: model) == "VirtualMac2,1",
              let app = NSRunningApplication(processIdentifier: pid), app.bundleIdentifier == "org.mozilla.firefox"
        else { exit(2) }
        var record = proc_bsdinfo()
        let length = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &record, length) == length,
              record.pbi_pid == UInt32(pid), record.pbi_ppid == UInt32(getppid()) else { exit(2) }
        let trusted = AXIsProcessTrusted()
        var result: [String: Any] = ["trusted": trusted, "openedScopedPicker": false, "enteredFilePath": false,
                                    "attachmentAccepted": "NOT_RUN", "exactOriginalReceipt": "NOT_RUN"]
        defer {
            if let bytes = try? JSONSerialization.data(withJSONObject: result) { FileHandle.standardOutput.write(bytes) }
        }
        guard trusted else { result["stop"] = "ACCESSIBILITY_NOT_GRANTED"; return }
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 1)
        let windows = attribute(application, kAXWindowsAttribute) as? [AXUIElement] ?? []
        let matches = windows.filter { (attribute($0, kAXTitleAttribute) as? String)?.hasPrefix("Riftlet synthetic host fixture") == true }
        guard matches.count == 1, let window = matches.first else { result["stop"] = "NO_UNIQUE_FIXTURE_WINDOW"; return }
        var queue = [window], index = 0, buttons = [AXUIElement]()
        while index < queue.count && queue.count <= 600 {
            let node = queue[index]
            index += 1
            if attribute(node, kAXRoleAttribute) as? String == kAXButtonRole,
               [kAXTitleAttribute,kAXDescriptionAttribute].contains(where: { attribute(node, $0) as? String == "Riftlet synthetic file" }) {
                buttons.append(node)
            }
            queue.append(contentsOf: attribute(node, kAXChildrenAttribute) as? [AXUIElement] ?? [])
        }
        guard index == queue.count, buttons.count == 1, let button = buttons.first else {
            result["stop"] = "NO_UNIQUE_SCOPED_BUTTON"; return
        }
        guard AXUIElementPerformAction(button, kAXPressAction as CFString) == .success else {
            result["stop"] = "BUTTON_PRESS_REFUSED"; return
        }
        for _ in 0..<15 {
            let children = attribute(window, kAXChildrenAttribute) as? [AXUIElement] ?? []
            let sheets = children.filter { attribute($0, kAXRoleAttribute) as? String == kAXSheetRole }
            if sheets.count == 1, let sheet = sheets.first {
                var owner: pid_t = 0
                guard AXUIElementGetPid(sheet, &owner) == .success && owner == pid else { break }
                result["openedScopedPicker"] = true
                result["stop"] = "NO_DOCUMENT_OR_OPERATION_RECEIPT_FROM_AX_SHEET"
                _ = AXUIElementPerformAction(sheet, kAXCancelAction as CFString)
                return
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        result["stop"] = "NO_ORIGINAL_WINDOW_SHEET"
    }
}
