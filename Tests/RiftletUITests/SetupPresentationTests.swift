import XCTest
@testable import RiftletUI

final class SetupPresentationTests: XCTestCase {
    func testOnboardingChromeRecipeUsesRequestedLanguageAndPreservesCustomDetails() {
        for input: ProductCopy in [.english, .simplifiedChinese] {
            let snapshot = SetupSnapshot(attachment: .available,
                permissionDetail: ChromeAttachmentSetup.instructions(in: input))
            let presentation = SetupPresentation(snapshot: snapshot, copy: input)
            for output: ProductCopy in [.english, .simplifiedChinese] {
                XCTAssertEqual(output.chromeInstructions(presentation),
                    ChromeAttachmentSetup.instructions(in: output))
            }
        }
        let custom = SetupPresentation(snapshot: .init(attachment: .available,
            permissionDetail: "Custom local detail"))
        XCTAssertEqual(ProductCopy.english.chromeInstructions(custom), "Custom local detail")
        XCTAssertEqual(ProductCopy.simplifiedChinese.chromeInstructions(custom), "Custom local detail")
        XCTAssertEqual(ProductCopy.english.chromeInstructions(
            SetupPresentation(snapshot: .init(attachment: .productionDisabled))), "")
    }

    func testEnglishStorageReportDistinguishesOccupiedSpaceFromReclaimableSpace() {
        let model = SetupPresentation(snapshot: .init(storage: .measured(bytes: 4096, complete: false, screenshotCopies: 2048)), copy: .english)
        XCTAssertTrue(model.storageText.contains("at least"))
        XCTAssertTrue(model.storageText.contains("Screenshot copies"))
        XCTAssertTrue(model.storageText.contains("Archiving keeps"))
        XCTAssertTrue(model.storageText.contains("do not measure reclaimable"))
    }

    func testDisabledProductionCannotBePresentedAsPermissionFailure() {
        for state in [SetupPermissionState.notChecked, .notRequested, .granted, .denied, .unavailable] {
            let model = SetupPresentation(snapshot: .init(attachment: .productionDisabled,
                permission: state, permissionDetail: "仅供测试的权限说明", issue: .permissionDenied), copy: .simplifiedChinese)
            XCTAssertTrue(model.attachmentText.contains("尚未启用真实截图附加"))
            XCTAssertTrue(model.attachmentText.contains("授权不会开启"))
            XCTAssertNil(model.permissionText)
            XCTAssertNil(model.issueText)
            XCTAssertFalse(model.canRequestPermission)
            XCTAssertTrue(model.firstUseDescription.contains("当前仅本地收录"))
            XCTAssertEqual(model.firstUseFlow, "截图 → 收录 → 查看")
            XCTAssertTrue(model.firstUseNextStep.contains("当前不会上传"))
        }
    }

    func testFirstUseDoesNotPromiseRealAttachmentInSimulationOrUnavailableModes() {
        let offline = SetupPresentation(snapshot: .init(attachment: .offlineSimulation), copy: .simplifiedChinese)
        XCTAssertTrue(offline.firstUseDescription.contains("离线演示"))
        XCTAssertTrue(offline.firstUseNextStep.contains("不会上传"))
        let synthetic = SetupPresentation(snapshot: .init(attachment: .syntheticWeb), copy: .simplifiedChinese)
        XCTAssertTrue(synthetic.firstUseDescription.contains("不收录真实截图"))
        XCTAssertTrue(synthetic.firstUseNextStep.contains("不会上传真实截图"))
        for state in [SetupAttachmentState.unsupportedBrowser, .targetUnavailable] {
            let value = SetupPresentation(snapshot: .init(attachment: state), copy: .simplifiedChinese)
            XCTAssertTrue(value.firstUseDescription.contains("附加目标不可用"))
            XCTAssertTrue(value.firstUseNextStep.contains("不会切换"))
        }
        let candidate = SetupPresentation(snapshot: .init(attachment: .systemScreenshotCandidate, permission: .granted), copy: .simplifiedChinese)
        XCTAssertTrue(candidate.firstUseDescription.contains("目标与图片均通过核验"))
        XCTAssertTrue(candidate.firstUseNextStep.contains("仍须通过核验"))
    }

    func testUnknownIsPendingAndDoesNotAuthorizeAnotherInput() {
        let model = SetupPresentation(snapshot: .init(visibleCount: 0, pendingCount: 2), copy: .simplifiedChinese)
        XCTAssertTrue(model.riftText.contains("没有可见截图"))
        XCTAssertTrue(model.pendingText?.contains("结果待核实") == true)
        XCTAssertTrue(model.pendingText?.contains("不会自动再次附加") == true)
        XCTAssertFalse(model.pendingText?.contains("失败") == true)
        XCTAssertFalse(model.pendingText?.contains("成功") == true)
        XCTAssertNil(SetupPresentation(snapshot: .init(), copy: .simplifiedChinese).pendingText)
    }

    func testHiddenPauseEmptyAndBackgroundCollectionAreSeparate() {
        let collectingHidden = SetupPresentation(snapshot: .init(source: .accessible,
            collection: .collecting, isHidden: true, visibleCount: 3), copy: .simplifiedChinese)
        XCTAssertTrue(collectingHidden.collectionText.contains("正在收录"))
        XCTAssertTrue(collectingHidden.riftText.contains("桌面截图已隐藏"))
        XCTAssertTrue(collectingHidden.riftText.contains("3 张待显示"))
        XCTAssertEqual(collectingHidden.hideActionTitle, "显示桌面截图")
        XCTAssertEqual(collectingHidden.collectionActionTitle, "暂停收录")
        let paused = SetupPresentation(snapshot: .init(source: .accessible, collection: .paused, visibleCount: 3), copy: .simplifiedChinese)
        XCTAssertTrue(paused.collectionText.contains("收录已暂停"))
        XCTAssertEqual(paused.riftText, "桌面边缘有 3 张截图。")
        XCTAssertEqual(paused.collectionActionTitle, "继续收录")
        XCTAssertFalse(paused.riftText.contains("隐藏"))
        let pausedUnchecked = SetupPresentation(snapshot: .init(source: .notChecked, collection: .paused), copy: .simplifiedChinese)
        XCTAssertTrue(pausedUnchecked.sourceText.contains("尚未检查"))
        XCTAssertFalse(pausedUnchecked.sourceText.contains("不可访问"))
        XCTAssertFalse(pausedUnchecked.sourceText.contains("正在检查"))
        XCTAssertNil(pausedUnchecked.issueText)
        let waiting = SetupPresentation(snapshot: .init(source: .unavailable, collection: .waitingForSource), copy: .simplifiedChinese)
        XCTAssertTrue(waiting.collectionText.contains("收录开关已开启"))
        XCTAssertFalse(waiting.collectionText.contains("收录已暂停"))
        XCTAssertFalse(waiting.collectionText.contains("正在收录新截图"))
        XCTAssertEqual(waiting.collectionActionTitle, "暂停收录")
        let simulation = SetupPresentation(snapshot: .init(source: .notApplicable, collection: .stopped,
            attachment: .offlineSimulation), copy: .simplifiedChinese)
        XCTAssertEqual(simulation.sourceText, "此模式不读取系统截图文件夹。")
        XCTAssertFalse(simulation.sourceText.contains("权限"))
    }

    func testAutomationRecoveryIsActionableOnlyForTheCurrentCapability() {
        let unchecked = SetupPresentation(snapshot: .init(attachment: .available, permission: .notChecked), copy: .simplifiedChinese)
        XCTAssertTrue(unchecked.automationStatusText?.contains(unchecked.permissionActionTitle) == true)
        XCTAssertFalse(unchecked.automationStatusText?.contains("macOS 会") == true)
        let denied = SetupPresentation(snapshot: .init(attachment: .syntheticWeb, permission: .denied), copy: .simplifiedChinese)
        XCTAssertTrue(denied.canRequestPermission)
        XCTAssertEqual(denied.permissionActionTitle, "打开自动化设置…")
        XCTAssertTrue(denied.permissionText?.contains("系统设置 → 隐私与安全性 → 自动化") == true)
        XCTAssertTrue(denied.permissionText?.contains("Riftlet 下允许 Google Chrome") == true)
        let granted = SetupPresentation(snapshot: .init(attachment: .syntheticWeb, permission: .granted,
            permissionDetail: "还需在 Chrome 菜单中检查 Apple Events JavaScript 设置。"), copy: .simplifiedChinese)
        XCTAssertFalse(granted.canRequestPermission)
        XCTAssertEqual(granted.automationStatusText, "macOS 已允许 Riftlet 与 Chrome 通信。")
        XCTAssertTrue(granted.permissionText?.contains("Apple Events JavaScript") == true)
        for state in [SetupPermissionState.notRunning, .browserUnavailable] {
            XCTAssertFalse(SetupPresentation(snapshot: .init(attachment: .syntheticWeb, permission: state), copy: .simplifiedChinese).canRequestPermission)
        }
        XCTAssertFalse(SetupPresentation(snapshot: .init(attachment: .offlineSimulation, permission: .notRequested), copy: .simplifiedChinese).canRequestPermission)
    }

    func testUnconfirmedBookmarkOffersSelectionEvenWhenTheFolderWasReadable() {
        let p = SetupPresentation(snapshot: .init(sourceLocation: "/fixture", source: .accessible,
                                                  issue: .screenshotFolderNeedsSelection), copy: .simplifiedChinese)
        XCTAssertTrue(p.needsSourceAccess)
        XCTAssertEqual(p.sourceText, SetupIssue.screenshotFolderNeedsSelection.text(in: .simplifiedChinese))
        XCTAssertFalse(p.sourceText.contains("权限被拒"))
    }

    func testAttachmentHelpReportsAnObservedMissingChatOnlyWhenThisModeConnects() {
        let target = SetupPresentation(snapshot: .init(attachment: .available, issue: .targetUnavailable), copy: .simplifiedChinese)
        XCTAssertEqual(target.attachmentText, SetupIssue.targetUnavailable.text(in: .simplifiedChinese))
        XCTAssertTrue(target.attachmentText.contains("Chrome 前台"))
        let local = SetupPresentation(snapshot: .init(attachment: .productionDisabled, issue: .targetUnavailable), copy: .simplifiedChinese)
        XCTAssertFalse(local.attachmentText.contains("Chrome 前台"))
    }

    func testSupportScopeComesFromHostAndLocalStringsAreBounded() {
        let model = SetupPresentation(snapshot: .init(sourceLocation: "/Users/local/\u{202E}Screenshots\u{0000}",
            source: .accessible, visibleCount: -1, pendingCount: -2,
            supportDescription: "CI: macOS 14.8.9；最低构建版本 13.0，不代表全版本验收。"), copy: .simplifiedChinese)
        XCTAssertEqual(model.sourcePath, "/Users/local/Screenshots")
        XCTAssertEqual(model.snapshot.visibleCount, 0)
        XCTAssertNil(model.pendingText)
        XCTAssertTrue(model.supportText.contains("不代表全版本验收"))
        let long = SetupPresentation(snapshot: .init(sourceLocation: String(repeating: "a", count: 8_000),
            supportDescription: String(repeating: "b", count: 5_000)), copy: .simplifiedChinese)
        XCTAssertEqual(long.sourcePath.count, 4_097)
        XCTAssertEqual(long.supportText.count, 1_201)
        XCTAssertFalse(SetupPresentation(snapshot: .init(sourceLocation: " \n\u{0000}"), copy: .simplifiedChinese).hasSourceLocation)
    }

    func testStorageAndFormatFailuresKeepTheirDistinctRecoveryMeaning() {
        XCTAssertNotEqual(SetupIssue.unsupportedFormat.text(in: .simplifiedChinese), SetupIssue.unsupportedSize.text(in: .simplifiedChinese))
        XCTAssertTrue(SetupIssue.insufficientSpace.text(in: .simplifiedChinese).contains("释放磁盘空间"))
        XCTAssertTrue(SetupIssue.privateWriteFailed.text(in: .simplifiedChinese).contains("访问权限"))
        let partial = SetupPresentation(snapshot: .init(storage: .measured(bytes: 1_024, complete: false)), copy: .simplifiedChinese)
        XCTAssertTrue(partial.storageText.contains("已统计至少"))
        XCTAssertTrue(partial.storageText.contains("不代表可释放"))
        let huge = SetupPresentation(snapshot: .init(storage: .measured(bytes: UInt64.max, complete: true)), copy: .simplifiedChinese)
        XCTAssertTrue(huge.storageText.contains(String(UInt64.max)))
        let stopped = SetupPresentation(snapshot: .init(source: .unavailable, collection: .stopped,
            issue: .sourceAccess), copy: .simplifiedChinese)
        XCTAssertTrue(stopped.sourceText.contains("不可访问"))
        XCTAssertTrue(stopped.collectionText.contains("当前未收录"))
        XCTAssertTrue(stopped.issueText?.contains("原截图没有被删除") == true)
    }
}
