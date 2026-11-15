import XCTest

/// Covers editing name and birthday, the readiness rule, deliberate birthday
/// confirmation vs. cancellation, and that details survive terminating and
/// relaunching the app. All runs use the isolated UI-test store so real user
/// data is never touched.
final class EditingPersistenceUITests: XCTestCase {
    private func launchFresh() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["--uitest", "--uitest-reset"]
        app.launch()
        return app
    }

    private func dismissKeyboard(_ app: XCUIApplication) {
        // Submit the focused name field: its .submitLabel(.done)/.onSubmit
        // clears focus. Sending a newline avoids the ambiguous "Done" button
        // that matches both the Return key and the keyboard-toolbar button.
        let nameField = app.textFields["nameField"]
        if nameField.exists { nameField.typeText("\n") }
    }

    /// The TextField's SwiftUI placeholder. XCUIElement.value returns this
    /// prompt (not "") when the field is empty, so emptiness checks must treat
    /// it the same as an empty string. Note the typographic apostrophe.
    private static let namePlaceholder = "Child’s name"

    /// Returns true when the name field holds no user text — either an empty
    /// string or the placeholder prompt that XCUI reports for empty fields.
    private func nameIsEmpty(_ field: XCUIElement) -> Bool {
        let value = field.value as? String ?? ""
        return value.isEmpty || value == Self.namePlaceholder
    }

    /// Clears the name field without assuming caret position. Long-pressing the
    /// field raises the native editing menu; "Select All" then "delete" wipes
    /// the whole value in one reliable interaction instead of issuing one
    /// backspace per presumed character.
    private func clearName(_ app: XCUIApplication, _ field: XCUIElement) {
        field.tap()
        field.press(forDuration: 1.0)
        let selectAll = app.menuItems["Select All"]
        if selectAll.waitForExistence(timeout: 3) {
            selectAll.tap()
        }
        field.typeText(XCUIKeyboardKey.delete.rawValue)
    }

    private func setBirthday(_ app: XCUIApplication) {
        app.buttons["birthdayButton"].tap()
        let confirm = app.buttons["confirmBirthday"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "Expected the birthday picker to appear.")
        confirm.tap()
    }

    func testEditingNameAndBirthdayEnablesReadiness() {
        let app = launchFresh()

        let button = app.buttons["showBirthdayButton"]
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        XCTAssertFalse(button.isEnabled, "Fresh launch should start not ready.")

        let nameField = app.textFields["nameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText("Ada")
        dismissKeyboard(app)

        // Name alone must not enable the button — a birthday is still required.
        XCTAssertFalse(button.isEnabled, "Name without a birthday should stay not ready.")

        setBirthday(app)

        XCTAssertTrue(button.isEnabled, "Name plus a chosen birthday should be ready.")
    }

    func testCancellingBirthdayDoesNotAssignDate() {
        let app = launchFresh()

        let nameField = app.textFields["nameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 10))
        nameField.tap()
        nameField.typeText("Ada")
        dismissKeyboard(app)

        app.buttons["birthdayButton"].tap()
        let cancel = app.buttons["cancelBirthday"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        cancel.tap()

        // No birthday assigned: still not ready, placeholder intact.
        XCTAssertFalse(app.buttons["showBirthdayButton"].isEnabled)
        XCTAssertEqual(app.buttons["birthdayButton"].label, "Birthday, not set")
    }

    func testDetailsPersistAfterRelaunch() {
        let app = launchFresh()

        let nameField = app.textFields["nameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 10))
        nameField.tap()
        nameField.typeText("Grace")
        dismissKeyboard(app)
        setBirthday(app)

        XCTAssertTrue(app.buttons["showBirthdayButton"].isEnabled)
        // Capture the exact birthday shown so we can confirm the same day — not
        // just "a birthday" — survives relaunch.
        let birthdayLabelBefore = app.buttons["birthdayButton"].label
        XCTAssertNotEqual(birthdayLabelBefore, "Birthday, not set")

        app.terminate()

        // Relaunch WITHOUT reset: the isolated store should still hold the
        // previously entered details.
        let relaunched = XCUIApplication()
        relaunched.launchArguments += ["--uitest"]
        relaunched.launch()

        let reloadedName = relaunched.textFields["nameField"]
        XCTAssertTrue(reloadedName.waitForExistence(timeout: 10))
        XCTAssertEqual(reloadedName.value as? String, "Grace", "Name should persist across relaunch.")
        XCTAssertEqual(
            relaunched.buttons["birthdayButton"].label,
            birthdayLabelBefore,
            "The same birthday day should persist across relaunch."
        )
        XCTAssertTrue(
            relaunched.buttons["showBirthdayButton"].isEnabled,
            "Readiness should persist across relaunch because the birthday was saved."
        )
    }

    func testClearingNameDisablesReadinessAndPersists() {
        let app = launchFresh()

        let nameField = app.textFields["nameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 10))
        nameField.tap()
        nameField.typeText("Ada")
        dismissKeyboard(app)
        setBirthday(app)

        let button = app.buttons["showBirthdayButton"]
        XCTAssertTrue(button.isEnabled)

        // Clear the name robustly (Select All + delete), not by guessing the
        // caret position and issuing one backspace per character.
        clearName(app, nameField)
        XCTAssertTrue(nameIsEmpty(nameField), "The name field should be empty after clearing.")
        dismissKeyboard(app)

        XCTAssertFalse(button.isEnabled, "An empty name must disable readiness even with a birthday set.")

        app.terminate()

        let relaunched = XCUIApplication()
        relaunched.launchArguments += ["--uitest"]
        relaunched.launch()

        XCTAssertTrue(relaunched.buttons["showBirthdayButton"].waitForExistence(timeout: 10))
        let reloadedName = relaunched.textFields["nameField"]
        XCTAssertTrue(reloadedName.waitForExistence(timeout: 5))
        XCTAssertTrue(nameIsEmpty(reloadedName), "The cleared name should persist as empty after relaunch.")
        XCTAssertFalse(
            relaunched.buttons["showBirthdayButton"].isEnabled,
            "The cleared name should persist, leaving the app not ready after relaunch."
        )
    }
}
