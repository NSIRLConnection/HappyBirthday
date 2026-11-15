import XCTest

/// Launch and accessibility smoke coverage. These tests run the app against an
/// isolated, reset store (via launch arguments) so they are deterministic and
/// never read or modify real user app data.
final class LaunchSmokeTests: XCTestCase {
    private func makeApp(extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["--uitest", "--uitest-reset"] + extraArguments
        return app
    }

    func testDetailsScreenLaunchesWithDisabledButton() {
        let app = makeApp()
        app.launch()

        XCTAssertTrue(
            app.staticTexts["Happy Birthday"].waitForExistence(timeout: 10),
            "Expected the app title to appear on launch."
        )

        let button = app.buttons["showBirthdayButton"]
        XCTAssertTrue(
            button.waitForExistence(timeout: 5),
            "Expected the Show birthday screen button to exist."
        )
        XCTAssertFalse(
            button.isEnabled,
            "Button should be disabled when name and birthday are empty."
        )
    }

    /// At the largest accessibility text size the screen must stay usable: the
    /// title is reachable, and the disabled button can be scrolled to and is
    /// still both reachable (hittable) and disabled.
    func testDisabledButtonStaysReachableAtLargestAccessibilitySize() {
        let app = makeApp(extraArguments: [
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL",
        ])
        app.launch()

        XCTAssertTrue(
            app.staticTexts["Happy Birthday"].waitForExistence(timeout: 10),
            "Expected the app title to appear at accessibility sizes."
        )

        let button = app.buttons["showBirthdayButton"]
        XCTAssertTrue(
            button.waitForExistence(timeout: 5),
            "Expected the Show birthday screen button to exist."
        )

        // Scroll the content until the button is hittable (it may start below
        // the fold at this text size).
        let scrollView = app.scrollViews.firstMatch
        var attempts = 0
        while !button.isHittable && attempts < 6 {
            scrollView.swipeUp()
            attempts += 1
        }

        XCTAssertTrue(
            button.isHittable,
            "Button should be reachable after scrolling at accessibility sizes."
        )
        XCTAssertFalse(
            button.isEnabled,
            "Button should remain disabled when name and birthday are empty."
        )
    }
}
