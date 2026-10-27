import XCTest
@testable import RiftletUI

final class SetupPresentationTests: XCTestCase {
    func testDisabledProductionCannotBePresentedAsPermissionFailure() {
        for state in [SetupPermissionState.notChecked, .notRequested, .granted, .denied, .unavailable] {
            let model = SetupPresentation(snapshot: .init(attachment: .productionDisabled,
                permission: state, permissionDetail: "仅供测试的权限说明", issue: .permissionDenied))
            XCTAssertTrue(model.attachmentText.contains("尚未启用真实截图附加"))
            XCTAssertTrue(model.attachmentText.contains("授权不会开启"))
            XCTAssertNil(model.permissionText)
            XCTAssertNil(model.issueText)
            XCTAssertFalse(model.canRequestPermission)
        }
    }

    func testUnknownIsPendingAndDoesNotAuthorizeAnotherInput() {
        let model = SetupPresentation(snapshot: .init(visibleCount: 0, pendingCount: 2))
        XCTAssertTrue(model.riftText.contains("没有可见截图"))
        XCTAssertTrue(model.pendingText?.contains("结果待核实") == true)
        XCTAssertTrue(model.pendingText?.contains("不会自动再次附加") == true)
        XCTAssertFalse(model.pendingText?.contains("失败") == true)
        XCTAssertFalse(model.pendingText?.contains("成功") == true)
        XCTAssertNil(SetupPresentation(snapshot: .init()).pendingText)
    }

    func testHiddenPauseEmptyAndBackgroundCollectionAreSeparate() {
        let collectingHidden = SetupPresentation(snapshot: .init(source: .accessible,
            collection: .collecting, isHidden: true, visibleCount: 3))
        XCTAssertTrue(collectingHidden.collectionText.contains("正在收录"))
        XCTAssertTrue(collectingHidden.riftText.contains("裂缝已隐藏"))
        XCTAssertTrue(collectingHidden.riftText.contains("3 张待显示"))
        XCTAssertEqual(collectingHidden.hideActionTitle, "显示裂缝")
        XCTAssertEqual(collectingHidden.collectionActionTitle, "暂停收录")
        let paused = SetupPresentation(snapshot: .init(source: .accessible, collection: .paused, visibleCount: 3))
        XCTAssertTrue(paused.collectionText.contains("收录已暂停"))
        XCTAssertEqual(paused.riftText, "裂缝中有 3 张截图。")
        XCTAssertEqual(paused.collectionActionTitle, "继续收录")
        XCTAssertFalse(paused.riftText.contains("隐藏"))
        let pausedUnchecked = SetupPresentation(snapshot: .init(source: .notChecked, collection: .paused))
        XCTAssertTrue(pausedUnchecked.sourceText.contains("尚未检查"))
        XCTAssertFalse(pausedUnchecked.sourceText.contains("不可访问"))
        XCTAssertFalse(pausedUnchecked.sourceText.contains("正在检查"))
        XCTAssertNil(pausedUnchecked.issueText)
        let waiting = SetupPresentation(snapshot: .init(source: .unavailable, collection: .waitingForSource))
        XCTAssertTrue(waiting.collectionText.contains("收录开关已开启"))
        XCTAssertFalse(waiting.collectionText.contains("收录已暂停"))
        XCTAssertFalse(waiting.collectionText.contains("正在收录新截图"))
        XCTAssertEqual(waiting.collectionActionTitle, "暂停收录")
        let simulation = SetupPresentation(snapshot: .init(source: .notApplicable, collection: .stopped,
            attachment: .offlineSimulation))
        XCTAssertEqual(simulation.sourceText, "此模式不读取系统截图文件夹。")
        XCTAssertFalse(simulation.sourceText.contains("权限"))
    }

    func testAutomationRecoveryIsActionableOnlyForTheCurrentCapability() {
        let denied = SetupPresentation(snapshot: .init(attachment: .syntheticWeb, permission: .denied))
        XCTAssertTrue(denied.canRequestPermission)
        XCTAssertEqual(denied.permissionActionTitle, "打开自动化设置…")
        XCTAssertTrue(denied.permissionText?.contains("被拒绝") == true)
        let granted = SetupPresentation(snapshot: .init(attachment: .syntheticWeb, permission: .granted,
            permissionDetail: "还需在 Chrome 菜单中检查 Apple Events JavaScript 设置。"))
        XCTAssertFalse(granted.canRequestPermission)
        XCTAssertTrue(granted.permissionText?.contains("不代表页面附件能力") == true)
        XCTAssertTrue(granted.permissionText?.contains("Apple Events JavaScript") == true)
        for state in [SetupPermissionState.notRunning, .browserUnavailable] {
            XCTAssertFalse(SetupPresentation(snapshot: .init(attachment: .syntheticWeb, permission: state)).canRequestPermission)
        }
        XCTAssertFalse(SetupPresentation(snapshot: .init(attachment: .offlineSimulation, permission: .notRequested)).canRequestPermission)
    }

    func testSupportScopeComesFromHostAndLocalStringsAreBounded() {
        let model = SetupPresentation(snapshot: .init(sourceLocation: "/Users/local/\u{202E}Screenshots\u{0000}",
            source: .accessible, visibleCount: -1, pendingCount: -2,
            supportDescription: "CI: macOS 14.8.9；最低构建版本 13.0，不代表全版本验收。"))
        XCTAssertEqual(model.sourcePath, "/Users/local/Screenshots")
        XCTAssertEqual(model.snapshot.visibleCount, 0)
        XCTAssertNil(model.pendingText)
        XCTAssertTrue(model.supportText.contains("不代表全版本验收"))
        let long = SetupPresentation(snapshot: .init(sourceLocation: String(repeating: "a", count: 8_000),
            supportDescription: String(repeating: "b", count: 5_000)))
        XCTAssertEqual(long.sourcePath.count, 4_097)
        XCTAssertEqual(long.supportText.count, 1_201)
        XCTAssertFalse(SetupPresentation(snapshot: .init(sourceLocation: " \n\u{0000}")).hasSourceLocation)
    }

    func testStorageAndFormatFailuresKeepTheirDistinctRecoveryMeaning() {
        XCTAssertNotEqual(SetupIssue.unsupportedFormat.text, SetupIssue.unsupportedSize.text)
        XCTAssertTrue(SetupIssue.insufficientSpace.text.contains("释放磁盘空间"))
        XCTAssertTrue(SetupIssue.privateWriteFailed.text.contains("访问权限"))
        let partial = SetupPresentation(snapshot: .init(storage: .measured(bytes: 1_024, complete: false)))
        XCTAssertTrue(partial.storageText.contains("已统计至少"))
        XCTAssertTrue(partial.storageText.contains("不代表可释放"))
        let huge = SetupPresentation(snapshot: .init(storage: .measured(bytes: UInt64.max, complete: true)))
        XCTAssertTrue(huge.storageText.contains(String(UInt64.max)))
        let stopped = SetupPresentation(snapshot: .init(source: .unavailable, collection: .stopped,
            issue: .sourceAccess))
        XCTAssertTrue(stopped.sourceText.contains("不可访问"))
        XCTAssertTrue(stopped.collectionText.contains("当前未收录"))
        XCTAssertTrue(stopped.issueText?.contains("原截图没有被删除") == true)
    }
}
