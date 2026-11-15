import Foundation

/// The editable details shown on the first screen.
///
/// Editing, persistence, and photo picking arrive in later milestones. For
/// step 1 this value type simply models the fields and the single rule that
/// decides whether the "Show birthday screen" button is enabled.
struct BirthdayDetails: Equatable {
    /// The child's name. May contain leading/trailing whitespace while typing.
    var name: String

    /// The chosen birthday. Optional so a fresh launch does not silently
    /// default to today's date.
    var birthday: Date?

    init(name: String = "", birthday: Date? = nil) {
        self.name = name
        self.birthday = birthday
    }

    /// Step 1 readiness: a non-whitespace name AND a chosen birthday.
    /// A photo is optional and never gates the button.
    var isReadyToShowBirthday: Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedName.isEmpty && birthday != nil
    }
}
