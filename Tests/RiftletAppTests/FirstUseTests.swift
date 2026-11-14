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

    func testIncompleteSetupResumesAndCompletionIsIsolatedFromDevelopmentModes() throws {
        let suite = "Riftlet.FirstUseTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let capture = FirstUsePreferences(defaults: defaults, modeName: "Riftlet")
        XCTAssertTrue(capture.needsAutomaticPresentation)
        capture.recordPresentation()
        XCTAssertTrue(FirstUsePreferences(defaults: defaults, modeName: "Riftlet").needsAutomaticPresentation)
        capture.recordCompletion()
        capture.recordPresentation() // Opening help later preserves completion.
        XCTAssertFalse(FirstUsePreferences(defaults: defaults, modeName: "Riftlet").needsAutomaticPresentation)
        XCTAssertTrue(FirstUsePreferences(defaults: defaults, modeName: "Riftlet-Simulation").needsAutomaticPresentation)
        XCTAssertEqual(defaults.persistentDomain(forName: suite)?.count, 2,
                       "First-use presentation must not record permission, visibility, or upload admission")
    }

    func testExplicitDeferralSurvivesReopeningHelpAndRelaunch() throws {
        let suite = "Riftlet.DeferredFirstUse.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = FirstUsePreferences(defaults: defaults, modeName: "Riftlet")
        first.recordPresentation()
        XCTAssertTrue(first.needsAutomaticPresentation)
        first.deferPresentation()
        let relaunched = FirstUsePreferences(defaults: defaults, modeName: "Riftlet")
        XCTAssertFalse(relaunched.needsAutomaticPresentation)
        relaunched.recordPresentation()
        XCTAssertFalse(relaunched.needsAutomaticPresentation)
        XCTAssertTrue(FirstUsePreferences(defaults: defaults, modeName: "Riftlet-Simulation").needsAutomaticPresentation)
    }

    func testUpgradingPreservesLegacyOnboardingChoice() throws {
        let suite = "Riftlet.LegacyFirstUse.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "Riftlet.firstUse.presented.v1.Riftlet")
        let prefs = FirstUsePreferences(defaults: defaults, modeName: "Riftlet")
        XCTAssertFalse(prefs.needsAutomaticPresentation)
        prefs.recordPresentation()
        XCTAssertFalse(prefs.needsAutomaticPresentation)
    }

    func testFolderGrantCannotRedirectScreenshotSource() throws {
        let actual = FileManager.default.temporaryDirectory.appendingPathComponent("riftlet-source-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: actual, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: actual) }
        XCTAssertTrue(SourceAccessSelection.matches(selected: actual.appendingPathComponent("."), actualSource: actual))
        XCTAssertTrue(SourceAccessSelection.matches(selected: actual, actualSource: URL(fileURLWithPath: actual.path, isDirectory: false)))
        XCTAssertFalse(SourceAccessSelection.matches(selected: actual.deletingLastPathComponent(), actualSource: actual))
        XCTAssertFalse(SourceAccessSelection.matches(selected: URL(string: "https://example.org")!, actualSource: actual))
        XCTAssertThrowsError(try SourceAccessSelection.validate(selected: actual, actualSource: nil))
    }

    @MainActor func testWrongFolderPreservesTheSelectedScreenshotBookmarkAcrossRelaunch() throws {
        let manager = FileManager.default
        let folder = manager.temporaryDirectory.appendingPathComponent("RiftletFolder-\(UUID())", isDirectory: true)
        let screenshots = folder.appendingPathComponent("Screenshots", isDirectory: true)
        let other = folder.appendingPathComponent("Other", isDirectory: true)
        try manager.createDirectory(at: screenshots, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: folder) }
        try manager.createDirectory(at: other, withIntermediateDirectories: false)
        let suite = "Riftlet.FirstUseFolder.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let access = ScreenshotFolderAccess(defaults: defaults, modeName: "fixture")
        defer { access.stop() }
        try access.accept(screenshots, actualSource: screenshots)
        let key = "Riftlet.sourceAccess.v1.fixture"
        let bookmark = try XCTUnwrap(defaults.data(forKey: key))
        XCTAssertThrowsError(try access.accept(other, actualSource: screenshots)) { error in
            XCTAssertEqual(error as? SourceAccessError, .differentFolder)
        }
        access.stop()
        let restored = ScreenshotFolderAccess(defaults: defaults, modeName: "fixture")
        defer { restored.stop() }
        restored.restore(for: screenshots)
        XCTAssertEqual(defaults.data(forKey: key), bookmark)
        var stale = false
        let resolved = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI, .withoutMounting],
                               relativeTo: nil, bookmarkDataIsStale: &stale)
        XCTAssertTrue(SourceAccessSelection.matches(selected: resolved, actualSource: screenshots))
    }

    @MainActor func testRecreatedFolderCannotRenewAnOldBookmarkWithoutANewSelection() throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent("RiftletBookmark-\(UUID())", isDirectory: true)
        let selected = root.appendingPathComponent("Shots", isDirectory: true)
        let moved = root.appendingPathComponent("Moved", isDirectory: true)
        let unrelated = root.appendingPathComponent("Other", isDirectory: true)
        try manager.createDirectory(at: selected, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }
        try manager.createDirectory(at: unrelated, withIntermediateDirectories: false)
        let suite = "Riftlet.RecreatedBookmark.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let access = ScreenshotFolderAccess(defaults: defaults, modeName: "fixture")
        defer { access.stop() }
        let key = "Riftlet.sourceAccess.v1.fixture"
        XCTAssertEqual(access.restore(for: selected), .noApplicableBookmark)
        try access.accept(selected, actualSource: selected)
        let original = try XCTUnwrap(defaults.data(forKey: key))
        XCTAssertEqual(access.restore(for: selected), .matchingBookmark)
        XCTAssertTrue(access.permitsRead(of: selected))
        access.stop()
        try manager.moveItem(at: selected, to: moved)
        try manager.createDirectory(at: selected, withIntermediateDirectories: false)
        XCTAssertEqual(access.restore(for: unrelated), .noApplicableBookmark)
        XCTAssertTrue(access.permitsRead(of: unrelated))
        XCTAssertFalse(access.permitsRead(of: selected))
        XCTAssertEqual(access.restore(for: selected), .needsSelection)
        XCTAssertEqual(try manager.contentsOfDirectory(atPath: selected.path), [])
        XCTAssertEqual(defaults.data(forKey: key), original)
        try access.accept(selected, actualSource: selected)
        XCTAssertEqual(access.restore(for: selected), .matchingBookmark)
        XCTAssertTrue(access.permitsRead(of: selected))
        XCTAssertNotEqual(defaults.data(forKey: key), original)
        let invalid = Data([0x01, 0x02, 0x03])
        defaults.set(invalid, forKey: key)
        XCTAssertEqual(access.restore(for: selected), .needsSelection)
        XCTAssertEqual(defaults.data(forKey: key), invalid)
        defaults.set("unrecognized fixture value", forKey: key)
        XCTAssertEqual(access.restore(for: selected), .needsSelection)
        XCTAssertEqual(defaults.string(forKey: key), "unrecognized fixture value")
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

    func testOnlyChromeJavaScriptRejectionGetsTheScriptPermissionMessage() {
        let disabled = WebAdapterError.nativeEventFailed(12)
        XCTAssertEqual(ProductStatus.clickIssue(disabled, frontmostBundleID: "com.google.Chrome", webAcceptance: true),
                       .chromeJavaScriptDisabled)
        XCTAssertNil(ProductStatus.clickFeedback(disabled), "A generic target message must not override the setup issue")
        XCTAssertNil(ProductStatus.clickIssue(disabled, frontmostBundleID: "com.google.Chrome", webAcceptance: false))
        for error: Error in [WebAdapterError.nativeEventFailed(-1712), URLError(.notConnectedToInternet)] {
            XCTAssertEqual(ProductStatus.clickIssue(error, frontmostBundleID: "com.google.Chrome", webAcceptance: true),
                           .targetUnavailable)
        }
    }

    func testClickFeedbackCannotBlamePermissionForDisabledProduction() {
        XCTAssertNil(ProductStatus.clickIssue(WebAdapterError.disabled, frontmostBundleID: "com.apple.Safari", webAcceptance: false))
        XCTAssertEqual(ProductStatus.clickIssue(WebAdapterError.browserNotFrontmost, frontmostBundleID: "com.apple.Safari", webAcceptance: true), .unsupportedBrowser)
        XCTAssertEqual(ProductStatus.clickIssue(WebAdapterError.invalidTarget, frontmostBundleID: "com.google.Chrome", webAcceptance: true), .targetUnavailable)
        XCTAssertEqual(ProductStatus.clickIssue(WebAdapterError.nativeEventFailed(-1743), frontmostBundleID: "com.google.Chrome", webAcceptance: true), .permissionDenied)
        XCTAssertEqual(ProductStatus.clickIssue(WebAdapterError.invalidPrivateFile, frontmostBundleID: nil, webAcceptance: true), .imageUnavailable)
    }
}
