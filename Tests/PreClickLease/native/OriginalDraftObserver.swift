import AppKit
import Carbon
import CryptoKit
import Foundation
@testable import RiftletAdapters

@main enum OriginalDraftObserver {
    typealias Record = [String: Any]
    static func require(_ ok: Bool, _ message: String) throws {
        if !ok { throw Identity.Refusal(message) }
    }
    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    static func receipt(_ url: URL) throws -> Record {
        guard let value = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? Record else {
            throw Identity.Refusal("INVALID_RECEIPT")
        }
        return value
    }

    @MainActor static func run(_ directory: URL) throws -> Record {
        func read(_ name: String) throws -> Record { try receipt(directory.appendingPathComponent(name)) }
        let before = try read("before.json"), creation = try read("creation.json"), challenge = try read("challenge.json")
        guard let family = creation["family"] as? String, let vendor = Identity.families[family],
              let windowID = creation["windowID"] as? String, let tabID = creation["tabID"] as? String,
              let session = creation["sessionID"] as? String, let priorWindows = before["windowIDs"] as? [String],
              !priorWindows.contains(windowID), creation["phase"] as? String == "qaAddressConfirmed",
              before["sessionID"] as? String == session, before["dynamicSignature"] as? Bool == true,
              challenge["sessionID"] as? String == session, challenge["windowID"] as? String == windowID,
              challenge["tabID"] as? String == tabID, challenge["bundle"] as? String == vendor.bundle,
              challenge["dynamicSignature"] as? Bool == true,
              let marker = challenge["doc"] as? String, UUID(uuidString: marker) != nil,
              (challenge["renderer"] as? Record)?["sameDocument"] as? Bool == true
        else { throw Identity.Refusal("ORIGINAL_CREATION_REQUIRED") }
        let process = try Identity.certified(vendor, expectedPID: nil)
        try require(process.session == session && creation["pid"] as? Int32 == process.pid, "BROWSER_BIRTH_CHANGED")
        let address = ["applicationID":vendor.bundle, "session":session, "windowID":windowID, "tabID":tabID]
        let encoded = try JSONEncoder().encode(address)
        _ = try QAOriginalBrowserTab.decode(String(decoding: encoded, as: UTF8.self))
        let win = try Identity.object("cwin", "ID  ", .init(string: windowID))
        let tab = try Identity.object("CrTb", "ID  ", .init(string: tabID), win)
        func selected() throws -> Bool {
            let front = try Identity.object("cwin","indx",.init(int32:1))
            let current = try Identity.get(process, Identity.property("acTa",front))
            let ids = ChromeActiveTabDescriptor.identity(in:current)
            return ids?.window == windowID && ids?.tab == tabID
        }
        func check(_ expected: String, requireFront: Bool = true) throws {
            try require(process.isCurrent(), "BROWSER_BIRTH_CHANGED")
            try require(try Owned.tabIDs(process,window:win) == [tabID], "SOLE_ORIGINAL_TAB_REQUIRED")
            try require(try Identity.get(process, Identity.property("URL ",tab)).stringValue == expected, "ORIGINAL_URL_CHANGED")
            if requireFront {
                try require(try selected(), "ORIGINAL_TAB_NOT_SELECTED")
                try require(NSWorkspace.shared.frontmostApplication?.processIdentifier == process.pid,"ORIGINAL_PROCESS_NOT_FOREGROUND")
            }
        }

        #if QA_NAVIGATE
        // Separate setup binary. Its only destination is the original owned loopback document.
        guard let local = try read("urls.json")[family] as? String, Owned.valid(local) else {
            throw Identity.Refusal("LOCAL_CHALLENGE_REQUIRED")
        }
        try check(local, requireFront:false)
        let proof = try Owned.request(process,"CrSu","ExJa",["----":tab,"JvSc":.init(string:"document.querySelector('output#doc')?.textContent || ''")])
        try require(proof.stringValue == marker, "LOCAL_DOCUMENT_CHANGED")
        if NSWorkspace.shared.frontmostApplication?.processIdentifier != process.pid {
            try require(NSRunningApplication(processIdentifier:process.pid)?.activate(options:[]) == true,"OWNED_ACTIVATION_REFUSED")
        }
        if try !selected() {
            _ = try Owned.request(process,"core","setd",["----":Identity.property("pidx",win),"data":.init(int32:1)])
        }
        let until = Date(timeIntervalSinceNow:1)
        while try !selected() && Date() < until {
            RunLoop.current.run(until:Date(timeIntervalSinceNow:0.04))
        }
        try check(local)
        _ = try Owned.request(process,"core","setd",["----":Identity.property("URL ",tab),"data":.init(string:QAOriginalBrowserTab.temporaryChat)])
        return ["navigationRequested":true,"sourceDoc":marker,"route":address]
        #else
        let nav = try read("site-navigation-return.json")
        try require(nav["navigationRequested"] as? Bool == true &&
                    nav["sourceDoc"] as? String == marker && nav["route"] as? [String:String] == address,
                    "MISSING_OWNED_NAVIGATION")
        try check(QAOriginalBrowserTab.temporaryChat, requireFront:false)
        let initialSelection = try selected()
        let initialForeground = NSWorkspace.shared.frontmostApplication?.processIdentifier == process.pid
        guard let nonce = UUID(uuidString:marker) else {throw Identity.Refusal("INVALID_DOCUMENT_NONCE")}
        let key = nonce.uuidString.replacingOccurrences(of:"-",with:"")
        let source = readOriginalDraft.replacingOccurrences(of:"QA_ORIGINAL_DOCUMENT_NONCE",with:"'"+key+"'")
        let reply = try Owned.request(process,"CrSu","ExJa",["----":tab,"JvSc":.init(string:source)])
        try check(QAOriginalBrowserTab.temporaryChat, requireFront:false)
        let finalSelection = try selected()
        let finalForeground = NSWorkspace.shared.frontmostApplication?.processIdentifier == process.pid
        guard let string = reply.stringValue, string.utf8.count < 65536,
              var page = try JSONSerialization.jsonObject(with:Data(string.utf8)) as? Record,
              let entry = page["entryID"] as? String, UUID(uuidString:entry) != nil
        else { throw Identity.Refusal("ORIGINAL_PAGE_READ_UNAVAILABLE") }
        let enrollment = directory.appendingPathComponent("original-entry.json")
        if FileManager.default.fileExists(atPath:enrollment.path) {
            let saved = try receipt(enrollment)
            try require(saved["entryID"] as? String == entry && saved["timeOrigin"] as? Double == page["timeOrigin"] as? Double &&
                        saved["sourceDoc"] as? String == marker, "TEMPORARY_DOCUMENT_REPLACED")
        } else if page["editor"] as? Bool == true && page["uploadEntry"] as? Bool == true {
            let pin:Record = ["sourceDoc":marker,"entryID":entry,"timeOrigin":page["timeOrigin"] ?? NSNull()]
            try JSONSerialization.data(withJSONObject:pin).write(to:enrollment,options:.withoutOverwriting)
        }
        #if QA_FOCUS || QA_PRESENT
        try require(FileManager.default.fileExists(atPath:enrollment.path) && page["editor"] as? Bool == true,
                    "EDITOR_NOT_BOUND")
        if NSWorkspace.shared.frontmostApplication?.processIdentifier != process.pid {
            try require(NSRunningApplication(processIdentifier:process.pid)?.activate(options:[]) == true,"ACTIVATION_REFUSED")
        }
        let activationDeadline = ProcessInfo.processInfo.systemUptime + 1.5
        while NSWorkspace.shared.frontmostApplication?.processIdentifier != process.pid &&
              ProcessInfo.processInfo.systemUptime < activationDeadline {
            RunLoop.current.run(until:Date(timeIntervalSinceNow:0.04))
        }
        try require(NSWorkspace.shared.frontmostApplication?.processIdentifier == process.pid, "ACTIVATION_REFUSED")
        if try !selected() {
            _ = try Owned.request(process,"core","setd",["----":Identity.property("pidx",win),"data":.init(int32:1)])
        }
        let deadline = Date(timeIntervalSinceNow:1.5)
        while try !selected() && Date() < deadline { RunLoop.current.run(until:Date(timeIntervalSinceNow:0.04)) }
        try check(QAOriginalBrowserTab.temporaryChat)
        #if QA_PRESENT
        // Only this disposable, already claimed QA window is normalized.
        // Chromium can report hidden to a selected tab in an occluded native window.
        if let webState = page["observationState"] as? Record, webState["visible"] as? Bool == false {
            let bounds = CGDisplayBounds(CGMainDisplayID())
            let width = min(1040.0, bounds.width - 80), height = min(700.0, bounds.height - 100)
            try require(width > 400 && height > 300, "DISPLAY_TOO_SMALL")
            let rect: [Int16] = [52,48,Int16(52+height),Int16(48+width)]
            let qd = rect.withUnsafeBytes { NSAppleEventDescriptor(descriptorType:typeQDRectangle,bytes:$0.baseAddress,length:$0.count) }!
            _ = try Owned.request(process,"core","setd",["----":Identity.property("pbnd",win),"data":qd])
            _ = try Owned.request(process,"core","setd",["----":Identity.property("pmnd",win),"data":.init(boolean:true)])
            RunLoop.current.run(until:Date(timeIntervalSinceNow:0.4))
            _ = try Owned.request(process,"core","setd",["----":Identity.property("pmnd",win),"data":.init(boolean:false)])
            _ = try Owned.request(process,"core","setd",["----":Identity.property("pidx",win),"data":.init(int32:1)])
            RunLoop.current.run(until:Date(timeIntervalSinceNow:0.45))
            if NSWorkspace.shared.frontmostApplication?.processIdentifier != process.pid {
                try require(NSRunningApplication(processIdentifier:process.pid)?.activate(options:[]) == true,"OWNED_RESTORE_REFUSED")
            }
            let until = ProcessInfo.processInfo.systemUptime + 1.5
            while NSWorkspace.shared.frontmostApplication?.processIdentifier != process.pid && ProcessInfo.processInfo.systemUptime < until {
                RunLoop.current.run(until:Date(timeIntervalSinceNow:0.04))
            }
            if try !selected() {
                _ = try Owned.request(process,"core","setd",["----":Identity.property("pidx",win),"data":.init(int32:1)])
            }
            try check(QAOriginalBrowserTab.temporaryChat)
        }
        #endif
        let renewed = try Owned.request(process,"CrSu","ExJa",["----":tab,"JvSc":.init(string:"JSON.stringify([navigation.currentEntry.id,performance.timeOrigin])")])
        guard let raw = renewed.stringValue, let after = try JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [Any],
              after.count == 2, after[0] as? String == entry, after[1] as? Double == page["timeOrigin"] as? Double else {
            throw Identity.Refusal("ORIGINAL_DOCUMENT_NOT_FOCUSED")
        }
        return ["originalFocus":true]
        #else
        let bindings = page.removeValue(forKey:"pending") as? [Record] ?? []
        page["preparedBindingSHA256"] = bindings.compactMap { record -> String? in
            guard let target = record["target"] as? [String:Any], let id = target["clickBindingID"] as? String,
                  UUID(uuidString:id) != nil, target["sessionID"] as? String == session,
                  target["applicationID"] as? String == vendor.bundle, target["windowID"] as? String == windowID,
                  target["tabID"] as? String == tabID else { return nil }
            return digest(Data(id.lowercased().utf8))
        }
        let desktop = CGSessionCopyCurrentDictionary() as? [String:Any]
        let nativeWindow:Record = [
            "browserHidden":NSRunningApplication(processIdentifier:process.pid)?.isHidden ?? true,
            "minimized":(try? Identity.get(process,Identity.property("pmnd",win)).booleanValue) as Any? ?? NSNull(),
            "visible":(try? Identity.get(process,Identity.property("pvis",win)).booleanValue) as Any? ?? NSNull(),
            "displayAsleep":CGDisplayIsAsleep(CGMainDisplayID()) != 0,
            "onConsole":desktop?["kCGSessionOnConsoleKey"] ?? NSNull(),
            "screenLocked":desktop?["CGSSessionScreenIsLocked"] ?? false]
        let payload:Record = ["timestamp":ISO8601DateFormatter().string(from:Date()),"systemUptime":ProcessInfo.processInfo.systemUptime,
             "nativeWindow":nativeWindow,"family":family,"bundle":vendor.bundle,"pid":process.pid,"sessionID":session,"windowID":windowID,"tabID":tabID,
             "dynamicSignature":true,"exactTemporaryURL":true,"originalSelection":initialSelection && finalSelection,"originalSoleTab":true,"systemForeground":initialForeground && finalForeground,"page":page]
        let bytes = try JSONSerialization.data(withJSONObject:payload,options:.sortedKeys)
        return ["payload":payload,"payloadBase64":bytes.base64EncodedString(),"sha256":digest(bytes)]
        #endif
        #endif
    }

    @MainActor static func main() {
        do {
            guard CommandLine.arguments.count == 2 else {throw Identity.Refusal("QA_STATE_DIRECTORY_REQUIRED")}
            let result = try run(URL(fileURLWithPath:CommandLine.arguments[1], isDirectory:true))
            FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject:result,options:.sortedKeys))
        } catch {
            let message = (error as? Identity.Refusal)?.reason ?? "QA_RECEIPT_OR_RENDERER_UNAVAILABLE"
            FileHandle.standardError.write(Data((message + "\n").utf8))
            exit(1)
        }
    }
}
