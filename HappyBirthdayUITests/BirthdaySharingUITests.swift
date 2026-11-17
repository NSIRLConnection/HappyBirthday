import XCTest

/// Covers the "Share the news" control: that tapping it presents the system share
/// sheet over the birthday screen, that dismissing it returns to the unchanged
/// birthday screen (same theme/data), that it can be reopened, and that it stays
/// reachable at the largest accessibility text size. All runs use the isolated
/// UI-test store so real user data is never touched, and no external message is
/// ever actually sent — the sheet is only presented and then dismissed.
final class BirthdaySharingUITests: XCTestCase {
    private func launchSeeded(extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["--uitest", "--uitest-reset", "--uitest-seed"] + extraArguments
        app.launch()
        return app
    }

    func testShareButtonOpensSystemShareSheetAndDismissReturnsUnchanged() {
        let app = launchSeeded(extraArguments: ["--uitest-theme", "fox"])

        let showButton = app.buttons["showBirthdayButton"]
        XCTAssertTrue(showButton.waitForExistence(timeout: 10))
        showButton.tap()

        let share = app.buttons["birthdayShareButton"]
        XCTAssertTrue(share.waitForExistence(timeout: 5), "Expected the share button.")
        XCTAssertEqual(share.label, "Share the news")

        let ageBefore = app.descendants(matching: .any)["birthdayAge"].label

        share.tap()
        // The native sheet is presented over the birthday screen: the app button
        // underneath is covered, AND the real activity-sheet container surfaces in
        // the app process. Both are asserted so a passing test genuinely saw the
        // share UI, not just a disabled button.
        let covered = expectation(for: NSPredicate(format: "isHittable == false"), evaluatedWith: share)
        wait(for: [covered], timeout: 10)
        assertSystemShareSheetPresented(in: app)

        dismissShareSheet(in: app)

        // Back on the unchanged birthday screen: share button enabled and
        // reachable again, close button present, and the age unchanged.
        let reachable = expectation(for: NSPredicate(format: "isEnabled == true AND isHittable == true"),
                                    evaluatedWith: share)
        wait(for: [reachable], timeout: 10)
        XCTAssertTrue(share.isEnabled && share.isHittable,
                      "Share must be re-enabled and hittable after dismissal.")
        XCTAssertTrue(app.buttons["closeBirthday"].exists,
                      "Expected to remain on the birthday screen after dismissing the share sheet.\n\(app.debugDescription)")
        XCTAssertEqual(app.descendants(matching: .any)["birthdayAge"].label, ageBefore,
                       "Dismissing the share sheet must leave the birthday data unchanged.")

        // The share sheet can be reopened, and dismissing it a second time again
        // returns to an enabled, hittable share button.
        share.tap()
        let coveredAgain = expectation(for: NSPredicate(format: "isHittable == false"), evaluatedWith: share)
        wait(for: [coveredAgain], timeout: 10)
        assertSystemShareSheetPresented(in: app)
        dismissShareSheet(in: app)
        let reachableAgain = expectation(for: NSPredicate(format: "isEnabled == true AND isHittable == true"),
                                         evaluatedWith: share)
        wait(for: [reachableAgain], timeout: 10)
        XCTAssertTrue(share.isEnabled && share.isHittable,
                      "Share must be enabled and hittable after the second dismissal.")
    }

    func testShareButtonReachableAtLargestAccessibilitySize() {
        let app = launchSeeded(extraArguments: [
            "--uitest-theme", "fox",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL",
        ])

        let showButton = app.buttons["showBirthdayButton"]
        XCTAssertTrue(showButton.waitForExistence(timeout: 10))
        let detailsScroll = app.scrollViews.firstMatch
        var attempts = 0
        while !showButton.isHittable && attempts < 6 {
            detailsScroll.swipeUp()
            attempts += 1
        }
        showButton.tap()

        let share = app.buttons["birthdayShareButton"]
        XCTAssertTrue(share.waitForExistence(timeout: 5))

        // At accessibility sizes the birthday screen uses the scroll fallback, so
        // the share button may sit below the fold; scroll until it is reachable.
        let birthdayScroll = app.scrollViews.firstMatch
        attempts = 0
        while !share.isHittable && attempts < 8 {
            birthdayScroll.swipeUp()
            attempts += 1
        }
        XCTAssertTrue(share.isHittable,
                      "The share button must stay reachable at the largest accessibility size.\n\(app.debugDescription)")
    }

    // MARK: - Helpers

    /// On this runtime the system share sheet is hosted inside the app process
    /// (not SpringBoard): the decoded UI snapshot for the HappyBirthday pid exposes
    /// the concrete `ActivityListView` and `ShareSheet.RemoteContainerView` nodes,
    /// while the SpringBoard hierarchy contains neither. Verify one of those real
    /// native-sheet nodes is on screen, and attach the app hierarchy on failure so
    /// Codex can refine identifiers for the runtime.
    private func shareSheetNodes(in app: XCUIApplication) -> [XCUIElement] {
        [app.otherElements["ActivityListView"],
         app.otherElements["ShareSheet.RemoteContainerView"]]
    }

    private func assertSystemShareSheetPresented(in app: XCUIApplication,
                                                 file: StaticString = #filePath, line: UInt = #line) {
        let nodes = shareSheetNodes(in: app)
        let deadline = Date().addingTimeInterval(10)
        var found = false
        while Date() < deadline {
            if nodes.contains(where: { $0.exists }) { found = true; break }
            usleep(200_000)
        }
        if !found {
            let attachment = XCTAttachment(string: app.debugDescription)
            attachment.name = "app-hierarchy"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        XCTAssertTrue(found,
                      "Expected the native share sheet (ActivityListView / ShareSheet.RemoteContainerView) in the app.",
                      file: file, line: line)
    }

    /// Dismisses the presented system share sheet using the gesture that actually
    /// works on iOS 27.2 (verified manually): a downward drag and a top-centre tap
    /// do NOT dismiss, but tapping the unobscured upper-right birthday card —
    /// safely below the status area and above the sheet — does (and lands outside
    /// an iPad popover). Prefers an exposed native dismiss control when present,
    /// then waits for the native container to actually disappear.
    private func dismissShareSheet(in app: XCUIApplication) {
        let cancel = app.buttons["Cancel"]
        if cancel.exists && cancel.isHittable {
            cancel.tap()
        } else {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.22)).tap()
        }
        let gone = NSPredicate(format: "exists == false")
        let expectations = shareSheetNodes(in: app).map {
            expectation(for: gone, evaluatedWith: $0)
        }
        wait(for: expectations, timeout: 10)
    }
}
