import XCTest

/// Covers presenting the birthday screen, its content, closing back to an
/// unchanged details screen, and that the seeded details survive the round
/// trip. All runs use the isolated UI-test store (and debug-only seed/theme
/// fixtures) so real user data is never touched.
final class BirthdayScreenUITests: XCTestCase {
    private func launchSeeded(extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["--uitest", "--uitest-reset", "--uitest-seed"] + extraArguments
        app.launch()
        return app
    }

    func testPresentingAndClosingReturnsToUnchangedDetails() {
        let app = launchSeeded()

        let showButton = app.buttons["showBirthdayButton"]
        XCTAssertTrue(showButton.waitForExistence(timeout: 10))
        XCTAssertTrue(showButton.isEnabled, "Seeded details should be ready.")

        // Capture the seeded name so we can confirm it is unchanged after close.
        let nameBefore = app.textFields["nameField"].value as? String
        XCTAssertEqual(nameBefore, "Cristiano Ronaldo")

        showButton.tap()

        let close = app.buttons["closeBirthday"]
        XCTAssertTrue(close.waitForExistence(timeout: 5), "Expected the close button on the birthday screen.")

        close.tap()

        // Back on details with the same seeded values.
        let nameField = app.textFields["nameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        XCTAssertEqual(nameField.value as? String, "Cristiano Ronaldo",
                       "Closing the birthday screen must return to unchanged details.")
        XCTAssertTrue(app.buttons["showBirthdayButton"].isEnabled)
    }

    func testBirthdayScreenShowsCombinedAge() {
        let app = launchSeeded(extraArguments: ["--uitest-theme", "fox"])

        let showButton = app.buttons["showBirthdayButton"]
        XCTAssertTrue(showButton.waitForExistence(timeout: 10))
        showButton.tap()

        // The seed is one month ago, so the combined accessibility element reads
        // the name and "1 month old". Match by identifier across element types,
        // since a combined SwiftUI element may surface as a generic element.
        let age = app.descendants(matching: .any)["birthdayAge"]
        XCTAssertTrue(age.waitForExistence(timeout: 5), "Expected the combined age element.")
        XCTAssertEqual(age.label, "Today Cristiano Ronaldo is 1 month old")

        // The layered layout renders the header twice (a hidden decorative pass
        // reserves space for alignment). Only the visible pass may expose the
        // age, so exactly one `birthdayAge` element must be present — otherwise
        // VoiceOver would announce the phrase twice.
        let matches = app.descendants(matching: .any).matching(identifier: "birthdayAge")
        XCTAssertEqual(matches.count, 1, "The decorative header pass must not expose a second age element.")
    }

    func testCloseRemainsReachableAtLargestAccessibilitySize() {
        let app = launchSeeded(extraArguments: [
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL",
        ])

        let showButton = app.buttons["showBirthdayButton"]
        XCTAssertTrue(showButton.waitForExistence(timeout: 10))

        // The button may sit below the fold at accessibility sizes.
        let scrollView = app.scrollViews.firstMatch
        var attempts = 0
        while !showButton.isHittable && attempts < 6 {
            scrollView.swipeUp()
            attempts += 1
        }
        showButton.tap()

        let close = app.buttons["closeBirthday"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        XCTAssertTrue(close.isHittable, "Close must stay reachable at the largest accessibility size.")
    }
}
