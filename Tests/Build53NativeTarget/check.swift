import AppKit
import Carbon
import CryptoKit
import Darwin
@testable import RiftletAdapters
import RiftletCore

struct CheckFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

func require(_ value: Bool, _ explanation: String) throws {
    if !value { throw CheckFailure(explanation) }
}

struct Sample {
    let process: ChromeProcessIdentity
    let launchServicesMatched: Bool
}

// The headless backend does not always register an NSRunningApplication.
// In that case classify the owned child by its kernel-reported executable,
// and keep that observation distinct from a successful product acquisition.
func sample(_ child: Process, bundle: Bundle) throws -> Sample {
    guard let executable = bundle.executableURL, let id = bundle.bundleIdentifier else {
        throw CheckFailure("browser bundle unavailable")
    }
    for _ in 0..<40 {
        guard child.isRunning else { throw CheckFailure("owned headless process exited") }
        if let exact = ChromeProcessIdentity.read(pid: child.processIdentifier, applicationID: id) {
            return Sample(process: exact, launchServicesMatched: true)
        }
        Thread.sleep(forTimeInterval: 0.05)
    }
    let pid = child.processIdentifier
    var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
    let size = UInt32(buffer.count)
    guard let birth = KernelProcessBirth.read(pid: pid),
          proc_pidpath(pid, &buffer, size) > 0, let path = String(validatingUTF8: buffer),
          URL(fileURLWithPath: path).resolvingSymlinksInPath() == executable.resolvingSymlinksInPath(),
          let result = ChromeProcessIdentity(birth: birth, applicationID: id, terminated: false,
              launchDate: nil, executablePath: path), result.isCurrent() else {
        throw CheckFailure("kernel child identity unavailable")
    }
    return Sample(process: result, launchServicesMatched: false)
}

func launch(_ bundle: Bundle, profile: URL) throws -> Process {
    let task = Process()
    task.executableURL = bundle.executableURL
    task.arguments = ["--headless=new", "--user-data-dir=" + profile.path, "--no-first-run",
        "--no-default-browser-check", "--disable-background-networking", "--disable-sync",
        "--disable-component-update", "--disable-extensions", "--disable-gpu", "about:blank"]
    task.standardOutput = FileHandle.nullDevice
    task.standardError = FileHandle.nullDevice
    try task.run()
    // Allow the fresh profile to finish its first browser startup. The
    // Apple Event responder need not be ready when Launch Services sees PID.
    for _ in 0..<100 {
        if !task.isRunning { throw CheckFailure("headless child exited during startup") }
        if FileManager.default.fileExists(atPath:profile.appendingPathComponent("Default").path) { return task }
        Thread.sleep(forTimeInterval:0.05)
    }
    stop(task)
    throw CheckFailure("owned headless profile not initialized")
}

func stop(_ task: Process) {
    guard task.isRunning else { return }
    task.terminate()
    task.waitUntilExit()
}

enum NativeWindow {
    static func code(_ s: String) -> UInt32 { s.utf8.reduce(0) { $0 << 8 | UInt32($1) } }

    static func object(_ kind: String, _ form: String, _ key: NSAppleEventDescriptor,
                       parent: NSAppleEventDescriptor = .null()) throws -> NSAppleEventDescriptor {
        let desc = NSAppleEventDescriptor.record()
        desc.setDescriptor(.init(typeCode: code(kind)), forKeyword: code("want"))
        desc.setDescriptor(.init(enumCode: code(form)), forKeyword: code("form"))
        desc.setDescriptor(key, forKeyword: code("seld"))
        desc.setDescriptor(parent, forKeyword: code("from"))
        guard let result = desc.coerce(toDescriptorType: code("obj ")) else { throw CheckFailure("descriptor") }
        return result
    }

    static func request(_ pid: pid_t, _ eventClass: String, _ eventID: String,
                        _ object: NSAppleEventDescriptor) throws -> NSAppleEventDescriptor {
        let request = NSAppleEventDescriptor(eventClass: code(eventClass), eventID: code(eventID),
            targetDescriptor: .init(processIdentifier: pid), returnID: -1, transactionID: 0)
        request.setParam(object, forKeyword: keyDirectObject)
        let reply = try request.sendEvent(options: ChromeClickSnapshot.waitOptions, timeout: 1)
        let error = reply.paramDescriptor(forKeyword: keyErrorNumber)?.int32Value ?? 0
        if error != 0 { throw NSError(domain: NSOSStatusErrorDomain, code: Int(error)) }
        return reply
    }

    static func ids(_ pid: pid_t) throws -> [String] {
        let all = try object("cwin", "indx", ChromeHistoryTabSelection.allTabsOrdinal())
        let property = try object("prop", "prop", .init(typeCode: code("ID  ")), parent: all)
        guard let list = try request(pid, "core", "getd", property).paramDescriptor(forKeyword: keyDirectObject) else {
            throw CheckFailure("window ID list missing")
        }
        guard list.descriptorType == typeAEList else {
            throw CheckFailure("unexpected window ID list type " + String(list.descriptorType))
        }
        return try (0..<list.numberOfItems).map { index in
            guard let id = list.atIndex(index + 1)?.stringValue else { throw CheckFailure("window ID missing") }
            return id
        }
    }

    static func active(_ pid: pid_t) throws -> (window: String, tab: String) {
        let front = try object("cwin", "indx", .init(int32: 1))
        let tab = try object("prop", "prop", .init(typeCode: code("acTa")), parent: front)
        guard let value = try request(pid,"core","getd",tab).paramDescriptor(forKeyword: keyDirectObject),
              let pair = ChromeActiveTabDescriptor.identity(in: value) else { throw CheckFailure("headless native window unavailable") }
        return pair
    }
}

// Force the old and new processes to have the same PID only in a synthetic
// proc_bsdinfo record. Real process termination and restart are tested separately.
func checkPIDReuse(_ frozen: ChromeProcessIdentity) throws {
    var record = proc_bsdinfo()
    record.pbi_pid = UInt32(frozen.pid)
    record.pbi_start_tvsec = frozen.birth.seconds + 1
    record.pbi_start_tvusec = frozen.birth.microseconds
    guard let birth = KernelProcessBirth(requestedPID: frozen.pid, record: record,
                  bytesRead: Int32(MemoryLayout<proc_bsdinfo>.size)),
          let other = ChromeProcessIdentity(birth: birth, applicationID: frozen.applicationID,
                   terminated: false, launchDate: nil) else { throw CheckFailure("fixture invalid") }
    try require(!other.matches(session: frozen.session, allowLegacyObservation: true) && frozen != other, "PID reuse accepted")
}

// A newly reopened executor has no write route. Its observation branch can
// still look up the original process and address just the saved window/tab.
// A closed window must fail that read before receipt or dispatch.
@MainActor
func checkClosedWindow(_ op: TransferOperation, image: ImportedAsset, invocation: UUID,
                       directory: URL) async throws -> [String] {
    let trace = BoundedDiagnosticTrace(enabled:true,directory:directory,emitStandardError:false)
    let executor = ChromeAppleEventsExecutor(diagnosticTrace:trace)
    let identity = ObservationIdentity(operationID:op.id,assetID:image.id,attempt:op.attempt,
                                       assetSHA256:image.sha256,target:op.target)
    let program = try ChatGPTWebPageProgram.load()
    for action in [WebBridgeAction.commit,.observe] {
        do {
            _ = try await executor.execute(.init(action:action,target:op.target,identity:identity,
                                                  invocationID:invocation),program:program)
            throw CheckFailure("closed window accepted")
        } catch is WebAdapterError { }
    }
    trace.flushForTesting()
    let events = try nativeEvents(directory)
    let phases = events.compactMap { $0["phase"] as? String }
    try require(phases == ["originalRouteUnavailable","selection"] &&
                    events.allSatisfy { $0["transportSucceeded"] as? Bool == false },
                "closed window not refused at write-route / saved-window lookup")
    return phases
}

func nativeEvents(_ directory: URL) throws -> [[String:Any]] {
    let file = directory.appendingPathComponent("acceptance-recent.jsonl")
    let lines = try String(contentsOf:file,encoding:.utf8)
    return try lines.split(separator:"\n").map {
        try JSONSerialization.jsonObject(with:Data($0.utf8)) as? [String:Any] ?? [:]
    }
}

@main struct NativeTargetCheck {
    @MainActor static func run(_ appPath: String, _ directory: URL) async throws -> [String:Any] {
        guard let bundle = Bundle(path: appPath) else { throw CheckFailure("browser not installed") }
        let profile = directory.appendingPathComponent("profile")
        let task = try launch(bundle, profile: profile)
        defer { stop(task) }
        var window: (window: String, tab: String)?
        var windowStatus = "NOT_RUN"
        var closeStage = "originalWindow", closeSent = 0, polls = 0, presentSamples = 0
        var lastReply = "none", lastRead = "none"
        func detail(_ error: Error) -> String {
            if let check = error as? CheckFailure { return check.description }
            let native = error as NSError
            return "\(native.domain):\(native.code)"
        }

        let readyDeadline = ProcessInfo.processInfo.systemUptime + 6
        var originalReads = 0
        while task.isRunning {
            originalReads += 1
            do { window = try NativeWindow.active(task.processIdentifier); break }
            catch {
                let status = (error as NSError).code
                windowStatus = "NOT_RUN original window unavailable in owned headless process (code \(status))"
                // Only retry a transient process-not-ready reply, with no UI
                // interaction. Permission denial never triggers another call.
                if status != procNotFound || ProcessInfo.processInfo.systemUptime >= readyDeadline { break }
                try await Task.sleep(nanoseconds:200_000_000)
            }
        }

        // A fresh profile directory and a Launch Services entry can precede
        // Chromium's native window receiver. Freeze the test's process identity
        // only after the initial read. No operation exists during startup.
        let first = try sample(task, bundle: bundle)
        try checkPIDReuse(first.process)
        var kernelMatchedAtClose = false, taskRunningAtClose = false, classifiedAtClose = false

        let target = TargetLease(adapterID:"chatgpt-web",surface:.webChat,applicationID:first.process.applicationID,
            sessionID:first.process.session,windowID:window?.window ?? "100",tabID:window?.tab ?? "101",
            documentID:"isolated-document",composerID:"isolated-composer",draftGeneration:"one",clickBindingID:UUID())
        let db = directory.appendingPathComponent("queue.sqlite")
        let bytes = Data(base64Encoded:"iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGPgqn3/HwAEgQJ296314AAAAABJRU5ErkJggg==")!
        let digest = SHA256.hash(data:bytes).map { String(format:"%02x",$0) }.joined()
        let image = ImportedAsset(sourceKey:UUID().uuidString,fileName:"qa.png",sha256:digest,
            byteCount:Int64(bytes.count),pixelWidth:1,pixelHeight:1,mediaType:"image/png",origin:.synthetic)
        let imageURL = directory.appendingPathComponent(image.fileName)
        try bytes.write(to:imageURL)
        let operation: TransferOperation, invocation: UUID
        do {
            let store = try QueueStore(databaseURL:db)
            _ = try await store.importAsset(image)
            operation = try await store.prepare(assetID:image.id,target:target)
            invocation = try await store.markIndependentFileInputIntent(operation.id,ownerID:UUID())
        }

        if let window {
            do {
                closeStage = "verifyOriginal"
                kernelMatchedAtClose = KernelProcessBirth.read(pid:first.process.pid) == first.process.birth
                taskRunningAtClose = task.isRunning
                classifiedAtClose = ChromeProcessIdentity.read(pid:first.process.pid,applicationID:first.process.applicationID) == first.process
                guard first.process.isCurrent() else { throw CheckFailure("owned process no longer current") }
                let before = try NativeWindow.active(first.process.pid)
                guard before.window == window.window && before.tab == window.tab else {
                    throw CheckFailure("owned original window or tab changed before close")
                }
                closeStage = "sendOnce"
                let original = try NativeWindow.object("cwin","ID  ",.init(string:window.window))
                closeSent = 1
                do {
                    _ = try NativeWindow.request(first.process.pid,"core","clos",original)
                    lastReply = "acknowledged"
                } catch {
                    lastReply = detail(error)
                    if (error as NSError).code == errAEEventNotPermitted { throw error }
                    // An uncertain reply does not authorize a second close.
                }
                closeStage = "observeRemoval"
                let deadline = ProcessInfo.processInfo.systemUptime + 4
                while true {
                    if !task.isRunning {
                        windowStatus = "original process exited after close"; lastRead = "receiverExited"
                        break
                    }
                    guard first.process.isCurrent() else { throw CheckFailure("receiver birth no longer current") }
                    polls += 1
                    do {
                        let remaining = try NativeWindow.ids(first.process.pid)
                        if !remaining.contains(window.window) {
                            lastRead = "originalAbsent"; windowStatus = "original native window confirmed absent"
                            break
                        }
                        presentSamples += 1; lastRead = "originalStillPresent"
                    } catch {
                        lastRead = detail(error)
                        if (error as NSError).code == errAEEventNotPermitted { throw error }
                    }
                    guard ProcessInfo.processInfo.systemUptime < deadline else {
                        throw CheckFailure("bounded observation ended: " + lastRead)
                    }
                    try await Task.sleep(nanoseconds:100_000_000)
                }
                closeStage = "verified"
            } catch {
                windowStatus = "NOT_RUN close confirmation incomplete (" + closeStage + ": " + detail(error) + ")"
            }
        }
        var closePhases: [String] = []
        if windowStatus == "original native window confirmed absent" && first.process.isCurrent() {
            closePhases = try await checkClosedWindow(operation,image:image,invocation:invocation,
                directory:directory.appendingPathComponent("closed-window"))
        }
        stop(task)
        let next = try launch(bundle, profile: profile)
        defer { stop(next) }
        let second = try sample(next,bundle:bundle)
        try require(!first.process.isCurrent() && second.process.isCurrent() && first.process != second.process &&
            !second.process.matches(session:first.process.session,allowLegacyObservation:true), "old process accepted after restart")

        let reopened = try QueueStore(databaseURL:db)
        try await reopened.recoverInterruptedOperations()
        guard let restored = try await reopened.operation(id:operation.id),
              restored.target == target, restored.phase == .unknown,
              let restoredInvocation = try await reopened.dispatchInvocationID(for:operation.id),
              restoredInvocation == invocation else { throw CheckFailure("durable original operation lost") }
        let expectedIdentity = ObservationIdentity(operationID:restored.id,assetID:image.id,attempt:restored.attempt,
            assetSHA256:digest,target:restored.target)
        let trace = BoundedDiagnosticTrace(enabled:true,directory:directory,emitStandardError:false)
        let original = ChromeAppleEventsExecutor(diagnosticTrace:trace)
        let program = try ChatGPTWebPageProgram.load()
        for action in [WebBridgeAction.commit,.observe,.commit] {
            do {
                _ = try await original.execute(.init(action:action,target:restored.target,identity:expectedIdentity,
                    invocationID:restoredInvocation),program:program)
                throw CheckFailure("stale native command accepted")
            } catch WebAdapterError.invalidTarget { }
        }
        trace.flushForTesting()
        let events = try nativeEvents(directory)
        let phases = events.compactMap { $0["phase"] as? String }
        try require(phases == ["originalRouteUnavailable","originalProcessUnavailable","originalRouteUnavailable"],
                    "unexpected native refusal stage")
        let after = try await reopened.unresolvedOperations()
        let retainedCall = try await reopened.dispatchInvocationID(for:operation.id)
        try require(after.count == 1 && after[0].id == operation.id && after[0].phase == .unknown &&
            retainedCall == invocation && (try Data(contentsOf:imageURL)) == bytes, "observation changed original data")
        return ["bundle":first.process.applicationID,"oldProcessPID":first.process.pid,"newProcessPID":second.process.pid,
            "oldProcessNoLongerCurrent":true,"newProcessCurrent":true,"actualPIDReuse":first.process.pid == second.process.pid,
            "constructedSamePIDNewBirthRejected":true,"launchServicesMatched":[first.launchServicesMatched,second.launchServicesMatched],
            "nativeWindowIDSource":window == nil ? "fixture" : "observed in owned process","ownedNativeWindowClose":windowStatus,
            "closeEvidence":["stage":closeStage,"originalWindowReads":originalReads,"closeRequests":closeSent,"reply":lastReply,
                "readOnlySamples":polls,"samplesStillPresent":presentSamples,"lastRead":lastRead,
                "kernelBirthMatchedBeforeClose":kernelMatchedAtClose,"childRunningBeforeClose":taskRunningAtClose,
                "productClassificationMatchedBeforeClose":classifiedAtClose] as [String:Any],
            "operationID":operation.id.uuidString,"invocationID":invocation.uuidString,"assetSHA256":digest,"storePhase":"unknown",
            "afterClosedWindowNativePhases":closePhases,"observedNativePhases":phases,"pageDispatch":"did not enter native page dispatch","DOMCounters":NSNull(),
            "cachedRouteAfterWindowClose":"NOT_RUN (requires a foreground click-bound original)",
            "cachedRouteAfterRestart":"NOT_RUN (requires a foreground click-bound original)"]
    }

    static func main() async throws {
        guard CommandLine.arguments.count == 3 else { throw CheckFailure("supply an installed browser bundle and unique QA directory") }
        let privateDirectory = URL(fileURLWithPath: CommandLine.arguments[2],isDirectory:true)
        try FileManager.default.createDirectory(at: privateDirectory,withIntermediateDirectories:false)
        let report = try await run(CommandLine.arguments[1],privateDirectory)
        print(String(decoding:try JSONSerialization.data(withJSONObject:report,options:[.sortedKeys]),as:UTF8.self))
    }
}
