import XCTest
import RiftletUI
@testable import RiftletApp

final class ApplicationUpdaterTests: XCTestCase {
    func testValidationErrorsKeepIdentityAndOfferOfficialRecoveryInBothLanguages() {
        for (language, descriptions) in [
            (ProductCopy.english, [
                "This version cannot upgrade your current Riftlet installation. Visit riftlet.com for official releases.",
                "The update feed signature could not be verified. Visit riftlet.com for official releases."]),
            (.simplifiedChinese, [
                "这个版本不能用于升级当前的 Riftlet。请前往 riftlet.com 查看正式版本。",
                "无法验证更新清单的签名。请前往 riftlet.com 查看正式版本。"])
        ] {
            for invalid in [false, true] {
                let error = ApplicationUpdater.validationError(signatureInvalid: invalid, copy: language)
                XCTAssertEqual(error.domain, "com.riftlet.update")
                XCTAssertEqual(error.code, invalid ? 2 : 1)
                XCTAssertEqual(error.localizedDescription, descriptions[invalid ? 1 : 0])
            }
        }
    }

    func testBothPublicVersionAndBuildAdvanceForAnUpgrade() {
        for (oldVersion, oldBuild, newVersion, newBuild, expected) in [
            ("1.0.0", "22", "1.0.1", "23", true),
            ("1.9.9", "29", "1.10.0", "31", true),
            ("1.0.1", "23", "1.0.1", "24", false),
            ("1.0.1", "23", "1.0.0", "24", false),
            ("1.0.1", "23", "1.1.0", "23", false),
            ("1.0.1", "23", "1.1.0", "22", false),
            ("1.0.0", "22", "1.0.1-beta", "23", false),
            ("1.0.0", "22", "1..1", "23", false),
            ("1.0.0", "22", "1.0.1", "999999999999999999999999", false),
            ("1.0.0", "22", "1.0.01", "23", false)
        ] {
            XCTAssertEqual(ApplicationUpdater.isUpgrade(from: oldVersion, build: oldBuild,
                to: newVersion, build: newBuild), expected)
        }
    }
}
