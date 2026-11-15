import XCTest
@testable import HappyBirthday

/// Validates the single step 1 rule: the button is ready only when BOTH a
/// non-whitespace name AND a birthday are present.
final class ReadinessTests: XCTestCase {
    private let someBirthday = DateComponents(
        calendar: .current,
        year: 2024,
        month: 3,
        day: 9
    ).date

    func testEmptyDetailsAreNotReady() {
        XCTAssertFalse(BirthdayDetails().isReadyToShowBirthday)
    }

    func testNameOnlyIsNotReady() {
        let details = BirthdayDetails(name: "Ada", birthday: nil)
        XCTAssertFalse(details.isReadyToShowBirthday)
    }

    func testBirthdayOnlyIsNotReady() {
        let details = BirthdayDetails(name: "", birthday: someBirthday)
        XCTAssertFalse(details.isReadyToShowBirthday)
    }

    func testWhitespaceOnlyNameIsNotReady() {
        let details = BirthdayDetails(name: "   \n\t", birthday: someBirthday)
        XCTAssertFalse(details.isReadyToShowBirthday)
    }

    func testNameAndBirthdayAreReady() {
        let details = BirthdayDetails(name: "Ada", birthday: someBirthday)
        XCTAssertTrue(details.isReadyToShowBirthday)
    }

    func testSurroundingWhitespaceDoesNotBlockReadiness() {
        let details = BirthdayDetails(name: "  Ada  ", birthday: someBirthday)
        XCTAssertTrue(details.isReadyToShowBirthday)
    }
}
