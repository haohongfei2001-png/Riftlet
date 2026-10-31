import XCTest
@testable import RiftletApp
@testable import RiftletCapture
import RiftletUI
import RiftletAdapters

final class FirstUseTests: XCTestCase {
    func testSourceReadabilityNeverTransfersFromOldFolderToNewPreference() {
        let old = URL(fileURLWithPath: "/tmp/previous-source", isDirectory: true)
        let new = URL(fileURLWithPath: "/tmp/new-source", isDirectory: true)
        let previous = CaptureStatusSnapshot(sourceDirectory: old, isRunning: true, sourceAccessible: true, latestDiagnostic: nil)
        let source = ProductStatus.sourceState(detectedSource: new, observation: previous,
            systemCollection: true, paused: false, initialized: true)
        XCTAssertEqual(source, .unavailable)
        XCTAssertEqual(ProductStatus.collectionState(systemCollection: true, paused: false,
            initialized: true, running: true, source: source), .waitingForSource)
        XCTAssertEqual(ProductStatus.sourceState(detectedSource: old, observation: previous,
            systemCollection: true, paused: false, initialized: true), .accessible)
    }

    func testPauseAndFirstCheckAreNotPermissionDenial() {
        let directory = URL(fileURLWithPath: "/tmp/source", isDirectory: true)
        XCTAssertEqual(ProductStatus.sourceState(detectedSource: directory, observation: nil,
            systemCollection: true, paused: true, initialized: true), .notChecked)
        XCTAssertEqual(ProductStatus.sourceState(detectedSource: directory, observation: nil,
            systemCollection: true, paused: false, initialized: false), .checking)
        XCTAssertEqual(ProductStatus.collectionState(systemCollection: true, paused: true,
            initialized: true, running: false, source: .notChecked), .paused)
        XCTAssertEqual(ProductStatus.sourceState(detectedSource: directory, observation: nil,
            systemCollection: false, paused: false, initialized: true), .notApplicable)
    }

    func testPresentationPersistsButIsIsolatedFromDevelopmentModes() throws {
        let suite = "Riftlet.FirstUseTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let capture = FirstUsePreferences(defaults: defaults, modeName: "Riftlet")
        XCTAssertTrue(capture.needsAutomaticPresentation)
        capture.recordPresentation()
        XCTAssertFalse(FirstUsePreferences(defaults: defaults, modeName: "Riftlet").needsAutomaticPresentation)
        XCTAssertTrue(FirstUsePreferences(defaults: defaults, modeName: "Riftlet-Simulation").needsAutomaticPresentation)
        XCTAssertEqual(defaults.persistentDomain(forName: suite)?.count, 1,
                       "First-use presentation must not record permission, visibility, or upload admission")
    }

    func testFolderGrantCannotRedirectScreenshotSource() throws {
        let actual = FileManager.default.temporaryDirectory.appendingPathComponent("riftlet-source-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: actual, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: actual) }
        XCTAssertTrue(SourceAccessSelection.matches(selected: actual.appendingPathComponent("."), actualSource: actual))
        XCTAssertTrue(SourceAccessSelection.matches(selected: actual, actualSource: URL(fileURLWithPath: actual.path, isDirectory: false)))
        XCTAssertFalse(SourceAccessSelection.matches(selected: actual.deletingLastPathComponent(), actualSource: actual))
        XCTAssertFalse(SourceAccessSelection.matches(selected: URL(string: "https://example.org")!, actualSource: actual))
    }

    func testCaptureDiagnosticsRemainDistinctFromAttachmentPermission() {
        XCTAssertEqual(ProductStatus.issue(.init(code: .insufficientStorage)), .insufficientSpace)
        XCTAssertEqual(ProductStatus.issue(.init(code: .privateWriteFailed)), .privateWriteFailed)
        XCTAssertEqual(ProductStatus.issue(.init(code: .sourceUnavailable)), .sourceAccess)
        XCTAssertEqual(ProductStatus.issue(.init(code: .unsupportedFormat)), .unsupportedFormat)
        XCTAssertEqual(ProductStatus.issue(.init(code: .imageTooLarge)), .unsupportedSize)
        XCTAssertEqual(ProductStatus.issue(.init(code: .missingPrivateCopy)), .imageUnavailable)
        let view = SetupPresentation(snapshot: .init(attachment: .productionDisabled,
            permission: ProductStatus.permission(.denied), supportDescription: ProductStatus.supportDescription))
        XCTAssertNil(view.permissionText)
        XCTAssertFalse(view.canRequestPermission)
        XCTAssertTrue(view.attachmentText.contains("尚未启用"))
        for issue in [SetupIssue.visibilityPreferenceUnsaved, .collectionPreferenceUnsaved] {
            let failure = SetupPresentation(snapshot: .init(collection: .paused, isHidden: true, issue: issue))
            XCTAssertTrue(failure.issueText?.contains("未能保存") == true)
            XCTAssertTrue(failure.issueText?.contains("重启可能恢复之前") == true)
            XCTAssertNil(failure.permissionText)
        }
    }

    func testUnknownPresentationCannotBecomeFailureOrRetryPermission() {
        let view = SetupPresentation(snapshot: .init(isHidden: true, visibleCount: 0, pendingCount: 2,
            attachment: .syntheticWeb, permission: .granted))
        XCTAssertTrue(try! XCTUnwrap(view.pendingText).contains("待核实"))
        XCTAssertTrue(try! XCTUnwrap(view.pendingText).contains("不会自动再次附加"))
        XCTAssertFalse(try! XCTUnwrap(view.pendingText).contains("失败"))
        XCTAssertTrue(view.riftText.contains("隐藏"))
    }

    func testClickFeedbackCannotBlamePermissionForDisabledProduction() {
        XCTAssertNil(ProductStatus.clickIssue(WebAdapterError.disabled, frontmostBundleID: "com.apple.Safari", webAcceptance: false))
        XCTAssertEqual(ProductStatus.clickIssue(WebAdapterError.browserNotFrontmost, frontmostBundleID: "com.apple.Safari", webAcceptance: true), .unsupportedBrowser)
        XCTAssertEqual(ProductStatus.clickIssue(WebAdapterError.invalidTarget, frontmostBundleID: "com.google.Chrome", webAcceptance: true), .targetUnavailable)
        XCTAssertEqual(ProductStatus.clickIssue(WebAdapterError.nativeEventFailed(-1743), frontmostBundleID: "com.google.Chrome", webAcceptance: true), .permissionDenied)
        XCTAssertEqual(ProductStatus.clickIssue(WebAdapterError.invalidPrivateFile, frontmostBundleID: nil, webAcceptance: true), .imageUnavailable)
    }
}
