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

    // MARK: - Camera control

    /// Exactly one camera button is exposed on the birthday screen — the layered
    /// layout renders the photo slot twice, but the control must live only in the
    /// visible foreground pass, never duplicated in the hidden one.
    func testBirthdayScreenExposesASingleCameraButton() {
        let app = launchSeeded(extraArguments: ["--uitest-theme", "fox"])

        app.buttons["showBirthdayButton"].tap()

        let cameraButton = app.buttons["birthdayPhotoButton"]
        XCTAssertTrue(cameraButton.waitForExistence(timeout: 5), "Expected the birthday camera button.")
        let matches = app.descendants(matching: .any).matching(identifier: "birthdayPhotoButton")
        XCTAssertEqual(matches.count, 1, "The hidden skeleton pass must not duplicate the camera button.")
    }

    /// Tapping the camera button offers Library, Camera, and Cancel; cancelling
    /// returns to the birthday screen with the seeded photo and age unchanged.
    func testCameraButtonOffersOptionsAndCancelKeepsState() {
        let app = launchSeeded(extraArguments: ["--uitest-theme", "fox", "--uitest-seed-photo"])

        app.buttons["showBirthdayButton"].tap()

        let cameraButton = app.buttons["birthdayPhotoButton"]
        XCTAssertTrue(cameraButton.waitForExistence(timeout: 5))
        // The seeded photo makes this the "Change photo" affordance.
        XCTAssertEqual(cameraButton.label, "Change photo")
        cameraButton.tap()

        let library = app.buttons["Choose from Library"]
        XCTAssertTrue(library.waitForExistence(timeout: 5), "Expected the library option.")
        let takePhoto = app.buttons["Take Photo"]
        XCTAssertTrue(takePhoto.exists, "Expected the camera option.")

        // On iOS 27.2 the native confirmationDialog presents as a compact popover
        // that omits an explicit Cancel button; tapping outside it cancels. Use the
        // native Cancel when present, otherwise dismiss by tapping a deterministic
        // point outside the source popover — the age header, which sits above the
        // photo/menu — derived from the existing birthdayAge element's frame.
        let cancel = app.buttons["Cancel"]
        if cancel.exists {
            cancel.tap()
        } else {
            let ageHeader = app.descendants(matching: .any)["birthdayAge"]
            XCTAssertTrue(ageHeader.exists, "Expected the age header to anchor an outside-popover tap.")
            ageHeader.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }

        // The source menu controls must disappear once the dialog is dismissed.
        XCTAssertTrue(app.buttons["closeBirthday"].waitForExistence(timeout: 5))
        let menuGone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: library)
        wait(for: [menuGone], timeout: 5)
        XCTAssertFalse(takePhoto.exists, "The camera option must disappear after cancelling.")

        // Still on the birthday screen with the control, its "Change photo" label,
        // and age intact; cancelling never disturbs the existing photo.
        XCTAssertTrue(cameraButton.isHittable, "The camera button must stay reachable after cancel.")
        XCTAssertEqual(cameraButton.label, "Change photo",
                       "Cancelling with a seeded photo must keep the Change photo label.")
        XCTAssertEqual(app.descendants(matching: .any)["birthdayAge"].label,
                       "Today Cristiano Ronaldo is 1 month old")
    }

    /// Choosing the library genuinely presents the system picker over the
    /// birthday screen; cancelling it returns to the unchanged birthday screen
    /// (camera button hittable again, still the "Add photo" placeholder state)
    /// rather than back to details.
    func testChoosingLibraryPresentsPickerAndCancelReturnsToBirthday() {
        let app = launchSeeded(extraArguments: ["--uitest-theme", "fox"])

        app.buttons["showBirthdayButton"].tap()
        let cameraButton = app.buttons["birthdayPhotoButton"]
        XCTAssertTrue(cameraButton.waitForExistence(timeout: 5))
        XCTAssertEqual(cameraButton.label, "Add photo", "No seeded photo: placeholder state.")
        cameraButton.tap()

        let library = app.buttons["Choose from Library"]
        XCTAssertTrue(library.waitForExistence(timeout: 5))
        library.tap()

        // Prove the picker actually presented: the system photo picker covers the
        // birthday screen, so the camera button is no longer hittable even though
        // it still exists underneath. (A failure here means the picker never
        // opened — it must not be masked.)
        let covered = expectation(for: NSPredicate(format: "isHittable == false"),
                                  evaluatedWith: cameraButton)
        wait(for: [covered], timeout: 10)

        // Prove it is the system photo picker specifically — not a lingering source
        // confirmationDialog — by asserting a picker-specific Photos/Collections
        // segmented control is present while the source menu controls are gone.
        // app.debugDescription is surfaced on failure so Codex can refine the
        // selector if it differs on this OS.
        let photosControl = app.buttons["Photos"]
        let collectionsControl = app.buttons["Collections"]
        let pickerPresent = expectation(
            for: NSPredicate(format: "exists == true"), evaluatedWith: photosControl)
        wait(for: [pickerPresent], timeout: 10)
        XCTAssertTrue(photosControl.exists || collectionsControl.exists,
                      "Expected the system picker's Photos/Collections control.\n\(app.debugDescription)")
        XCTAssertFalse(app.buttons["Choose from Library"].exists,
                       "The source menu must be gone once the picker is presented.")

        // Dismiss the picker via its native Cancel control. If the exact system
        // selector differs on this OS, this fails loudly for Codex to inspect
        // rather than passing on an unverified gesture.
        let pickerCancel = app.buttons["Cancel"]
        XCTAssertTrue(pickerCancel.waitForExistence(timeout: 10),
                      "Expected the system photo picker's Cancel control.")
        pickerCancel.tap()

        // Back on the unchanged birthday screen: camera button reachable again and
        // still the placeholder "Add photo".
        let reachable = expectation(for: NSPredicate(format: "isHittable == true"),
                                    evaluatedWith: cameraButton)
        wait(for: [reachable], timeout: 10)
        XCTAssertEqual(cameraButton.label, "Add photo",
                       "Cancelling the library picker must leave the placeholder unchanged.")
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

    /// At the largest accessibility size the birthday screen falls back to the
    /// scroll layout; the camera button must remain present and reachable there.
    func testCameraButtonReachableAtLargestAccessibilitySize() {
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

        let cameraButton = app.buttons["birthdayPhotoButton"]
        XCTAssertTrue(cameraButton.waitForExistence(timeout: 5))

        // Scroll the fallback layout until the control is hittable.
        let birthdayScroll = app.scrollViews.firstMatch
        attempts = 0
        while !cameraButton.isHittable && attempts < 6 {
            birthdayScroll.swipeUp()
            attempts += 1
        }
        XCTAssertTrue(cameraButton.isHittable,
                      "The camera button must stay reachable at the largest accessibility size.")
    }
}
