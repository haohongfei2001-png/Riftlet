import XCTest
@testable import RiftletApp
import RiftletCore
import RiftletAdapters

final class ProductStatusTests: XCTestCase {
    func testPreparedCancellationReasonsHaveSpecificFeedback() {
        let cases: [(String, ProductStatus.AttachmentFeedback)] = [
            ("Accepted selection expired before input", .expiredBeforeInput),
            ("Original target changed before input", .targetChangedBeforeInput),
            ("Target validation unavailable before input", .targetValidationUnavailableBeforeInput),
            ("Original draft has an unresolved upload; no input occurred", .unresolvedDraftBeforeInput),
            ("Private image is missing; no input occurred", .imageMissingBeforeInput),
            ("Selection revoked during preparation; no input occurred", .cancelledBeforeInput),
            ("Original selection no longer authorized; no input occurred", .cancelledBeforeInput),
            ("Original selection revoked before intent; no input occurred", .cancelledBeforeInput),
            ("Selection retired before input intent", .cancelledBeforeInput),
            ("Removed before external input intent", .cancelledBeforeInput),
            ("Restart before dispatch intent; no input occurred", .cancelledBeforeInput)
        ]
        for (reason, expected) in cases {
            XCTAssertEqual(ProductStatus.operationFeedback(reason), expected, reason)
            XCTAssertFalse(expected.text.contains(reason))
        }
        for reason in ["termination", "observationLimit", "submissionCancelled", "submissionLimit",
                       "selectionRejected", "permissionUnavailable", "activation", "wake",
                       "removed", "clearVisible", "hidden"] {
            XCTAssertEqual(ProductStatus.operationFeedback(reason), .cancelledBeforeInput, reason)
        }
    }

    func testUnknownAndPostIntentReasonsNeverClaimNoInputOrExposeRawText() {
        let reasons: [String?] = [nil, "", "Restart after dispatch intent; reconcile original operation",
            "Recovery observation unavailable", "Input observed; conclusive completion is unavailable",
            "No trustworthy completion after input intent", "Background observation unavailable; original operation retained",
            "Identity-correlated late error; termination not proved", "dispatch-intent committed",
            "PRIVATE_SENTINEL /private/path https://example.invalid/session",
            "Accepted selection expired before input PRIVATE_SENTINEL"]
        for reason in reasons {
            let feedback = ProductStatus.operationFeedback(reason)
            XCTAssertEqual(feedback, .resultUnconfirmed)
            XCTAssertFalse(feedback.text.contains("未上传"))
            XCTAssertFalse(feedback.text.contains("PRIVATE_SENTINEL"))
            XCTAssertFalse(feedback.text.contains("失败"))
            XCTAssertTrue(feedback.text.contains("不会自动再次附加"))
        }
    }

    func testNoClickTimeACKIsOnlyRecognizedByExactTypedCoreError() {
        let reason = "No verified target existed at selection; image retained"
        XCTAssertEqual(ProductStatus.clickFeedback(RiftletError.adapterUnavailable(reason)), .noClickTimeTarget)
        XCTAssertEqual(ProductStatus.clickFeedback(WebAdapterError.invalidTarget), .targetUnavailable)
        XCTAssertNotEqual(ProductStatus.AttachmentFeedback.noClickTimeTarget.text,
                          ProductStatus.AttachmentFeedback.targetUnavailable.text)
        XCTAssertNil(ProductStatus.clickFeedback(RiftletError.adapterUnavailable(reason + " changed")))
        XCTAssertNil(ProductStatus.clickFeedback(NSError(domain: reason, code: 1)))
        XCTAssertNil(ProductStatus.clickFeedback(WebAdapterError.nativeEventFailed(-1743)))
        XCTAssertNil(ProductStatus.clickFeedback(SystemScreenshotInputError.unsupportedFormat))
        XCTAssertEqual(ProductStatus.operationFeedback(reason), .resultUnconfirmed,
                       "An untyped stored reason must not become the click-time ACK error")
    }

    func testWaitingIsPresentationOnlyAndNeverInferredFromGenericReason() {
        XCTAssertTrue(ProductStatus.AttachmentFeedback.waiting.text.contains("尚未上传"))
        XCTAssertFalse(ProductStatus.AttachmentFeedback.preparing.text.contains("未上传"),
                       "A prepared snapshot can advance to input before the next UI refresh")
        XCTAssertEqual(ProductStatus.operationFeedback("waiting"), .resultUnconfirmed)
        XCTAssertEqual(ProductStatus.operationFeedback("targetBusy"), .resultUnconfirmed)
        XCTAssertNil(ProductStatus.clickFeedback(RiftletError.targetBusy))
        for feedback in ProductStatus.AttachmentFeedback.allCases {
            XCTAssertFalse(feedback.text.contains("重试"))
            XCTAssertFalse(feedback.text.contains("ACK"))
            XCTAssertFalse(feedback.text.contains("UNKNOWN"))
        }
    }

    func testSupportDescriptionKeepsRestrictedAdmissionAndUnverifiedScopesSeparate() {
        let text = ProductStatus.supportDescription
        for scope in ["普通启动仅本地收录", "v2", "仅适用于新登记操作", "不补资格、不重传",
                      "安全失败与重试仍未开放", "Chrome 156.0.8078.73", "普通已有聊天",
                      "点击前已验证", "不是物理鼠标、冷首击或全场景支持", "非交错 8-bit RGBA PNG",
                      "≤8 MiB", "≤16,777,216 像素", "不自动转换"] {
            XCTAssertTrue(text.contains(scope), scope)
        }
        XCTAssertFalse(text.contains("开始、成功与重试均待"))
    }
}
