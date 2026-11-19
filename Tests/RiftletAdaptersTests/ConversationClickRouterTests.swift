import XCTest
import RiftletCore
@testable import RiftletAdapters

@MainActor private final class RecordingClickAdapter: ConversationClickAdapter {
    let applicationID: String
    let applicationIDs: Set<String>
    var calls = 0
    var captureError: WebAdapterError?
    var resultTarget: TargetLease?
    private(set) var captures: [Task<TargetLease, Error>] = []
    init(_ id: String, applications: Set<String>? = nil) {
        applicationID = id; applicationIDs = applications ?? [id]
    }
    func targetForClick() throws -> Task<TargetLease, Error> {
        calls += 1
        if let captureError { throw captureError }
        let resultTarget = resultTarget
        let capture = Task<TargetLease, Error> {
            try Task.checkCancellation()
            if let resultTarget { return resultTarget }
            throw WebAdapterError.invalidTarget
        }
        captures.append(capture)
        return capture
    }
}

@MainActor private final class RouterWebExecutor: WebClickTargetPinning {
    var calls = 0
    func targetForClick(program: WebPageProgram) throws -> Task<TargetLease, Error> {
        calls += 1
        return Task { throw WebAdapterError.captureSuperseded }
    }
    func execute(_ command: WebBridgeCommand, program: WebPageProgram) async throws -> Data {
        XCTFail("Click routing must call the synchronous click entry")
        throw WebAdapterError.invalidRequest
    }
}

final class ConversationClickRouterTests: XCTestCase {
    @MainActor func testMouseDownInvokesExactlyOneAdmittedForegroundHostSynchronously() throws {
        let chrome = RecordingClickAdapter("com.google.Chrome"), edge = RecordingClickAdapter("com.microsoft.edgemac")
        var current: String? = edge.applicationID
        let router = ConversationClickRouter(adapters: [chrome, edge], foreground: { current })
        let first = try router.targetForClick()
        XCTAssertEqual(edge.calls, 1)
        current = chrome.applicationID
        let next = try router.targetForClick()
        XCTAssertEqual(chrome.calls, 1)
        for missing in [nil, "other.app"] as [String?] {
            current = missing
            XCTAssertThrowsError(try router.targetForClick())
        }
        let duplicate = ConversationClickRouter(adapters: [edge, edge], foreground: { edge.applicationID })
        XCTAssertThrowsError(try duplicate.targetForClick())
        XCTAssertEqual(edge.calls, 1)
        XCTAssertEqual(chrome.calls, 1)
        first.cancel()
        next.cancel()
    }

    @MainActor func testMultiHostAdapterIsSelectedByItsAdvertisedHostsAtMouseDown() async throws {
        let web = RecordingClickAdapter("com.google.Chrome", applications: ["com.google.Chrome", "com.microsoft.edgemac"])
        let unrelated = RecordingClickAdapter("other.application")
        var current: String? = "com.microsoft.edgemac", foregroundReads = 0
        let router = ConversationClickRouter(adapters: [web, unrelated], foreground: {
            foregroundReads += 1; return current
        })
        let capture = try router.targetForClick()
        XCTAssertEqual(web.calls, 1)
        XCTAssertEqual(unrelated.calls, 0)
        XCTAssertEqual(foregroundReads, 1)
        current = unrelated.applicationID
        do { _ = try await capture.value; XCTFail("Original capture error must propagate") }
        catch { XCTAssertEqual(error as? WebAdapterError, .invalidTarget) }
        XCTAssertEqual(web.calls, 1)
        XCTAssertEqual(unrelated.calls, 0)
        XCTAssertEqual(foregroundReads, 1)
    }

    @MainActor func testOverlappingMultiHostRegistrationsRefuseBeforeAnyCapture() {
        let web = RecordingClickAdapter("com.google.Chrome", applications: ["com.google.Chrome", "com.microsoft.edgemac"])
        let edge = RecordingClickAdapter("com.microsoft.edgemac")
        for adapters in [[web, edge], [edge, web], [web, web]] {
            let router = ConversationClickRouter(adapters: adapters, foreground: { "com.microsoft.edgemac" })
            XCTAssertThrowsError(try router.targetForClick()) {
                XCTAssertEqual($0 as? WebAdapterError, .browserNotFrontmost)
            }
        }
        XCTAssertEqual(web.calls, 0)
        XCTAssertEqual(edge.calls, 0)
    }

    @MainActor func testMultiHostCaptureCannotReturnHostChangedAfterRouterBoundary() async throws {
        let web = RecordingClickAdapter("com.google.Chrome", applications: ["com.google.Chrome", "com.microsoft.edgemac"])
        // Simulates an executor's second foreground read selecting Chrome after
        // the router has already frozen Edge for this single mouse press.
        web.resultTarget = TargetLease(adapterID: "chatgpt-web", surface: .webChat,
            applicationID: "com.google.Chrome", sessionID: "owned-later-session", windowID: "1", tabID: "2",
            documentID: "owned-later-document", composerID: "owned-later-editor", draftGeneration: "owned-later-draft")
        var current = "com.microsoft.edgemac", reads = 0
        let router = ConversationClickRouter(adapters: [web], foreground: { reads += 1; return current })
        let original = try router.targetForClick()
        XCTAssertEqual(web.calls, 1)
        current = "com.google.Chrome"
        do { _ = try await original.value; XCTFail("A later host cannot replace the original click destination") }
        catch { XCTAssertEqual(error as? WebAdapterError, .nativeSelectionChanged) }
        XCTAssertEqual(reads, 1)
        XCTAssertEqual(web.calls, 1)
        XCTAssertEqual(web.captures.count, 1)
    }

    @MainActor func testEmptyAdvertisedHostsCannotFallBackToLegacyPrimaryApplicationID() {
        let disabled = RecordingClickAdapter("com.google.Chrome", applications: [])
        let router = ConversationClickRouter(adapters: [disabled], foreground: { disabled.applicationID })
        XCTAssertThrowsError(try router.targetForClick()) {
            XCTAssertEqual($0 as? WebAdapterError, .browserNotFrontmost)
        }
        XCTAssertEqual(disabled.calls, 0)
    }

    @MainActor func testSynchronousFailureAndCancellationNeverSelectAnotherAdapter() async throws {
        let chrome = RecordingClickAdapter("com.google.Chrome"), edge = RecordingClickAdapter("com.microsoft.edgemac")
        var current: String? = edge.applicationID
        let router = ConversationClickRouter(adapters: [chrome, edge], foreground: { current })
        edge.captureError = .nativeSelectionChanged
        XCTAssertThrowsError(try router.targetForClick()) {
            XCTAssertEqual($0 as? WebAdapterError, .nativeSelectionChanged)
        }
        edge.captureError = nil
        let capture = try router.targetForClick()
        current = chrome.applicationID
        capture.cancel()
        do { _ = try await capture.value; XCTFail("Cancelled original capture must not resolve another host") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertTrue(try XCTUnwrap(edge.captures.first).isCancelled)
        XCTAssertEqual(edge.calls, 2)
        XCTAssertEqual(chrome.calls, 0)
    }

    @MainActor func testWebAdapterMultiHostAdvertisementRemainsAllowlistedAndReachesClickEntry() async throws {
        let executor = RouterWebExecutor()
        // This path is never opened: click routing neither imports media nor creates a database.
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let program = WebPageProgram(sourceID: "owned-router-fixture", functionSource: "function () {}")
        let web = WebAttachmentAdapter(mediaDirectory: directory, executor: executor, program: program,
            mode: .syntheticDevelopment, applicationIDs: ["com.google.Chrome", "com.microsoft.edgemac", "unadmitted.application"])
        let advertised: any ConversationClickAdapter = web
        XCTAssertEqual(advertised.applicationIDs, ["com.google.Chrome", "com.microsoft.edgemac"])
        let defaultWeb = WebAttachmentAdapter(mediaDirectory: directory, executor: executor)
        XCTAssertEqual(defaultWeb.applicationIDs, ["com.google.Chrome"])
        let edgeRouter = ConversationClickRouter(adapters: [web], foreground: { "com.microsoft.edgemac" })
        let capture = try edgeRouter.targetForClick()
        XCTAssertEqual(executor.calls, 1)
        do { _ = try await capture.value; XCTFail("Original capture failure must survive both routing layers") }
        catch { XCTAssertEqual(error as? WebAdapterError, .captureSuperseded) }
        let unknownRouter = ConversationClickRouter(adapters: [web], foreground: { "unadmitted.application" })
        XCTAssertThrowsError(try unknownRouter.targetForClick()) {
            XCTAssertEqual($0 as? WebAdapterError, .browserNotFrontmost)
        }
        XCTAssertEqual(executor.calls, 1)
    }
}
