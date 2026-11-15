import SwiftUI

/// A date-only picker presented modally so a birthday is only ever assigned by
/// an explicit "Done". Cancelling dismisses without committing anything, which
/// keeps the birthday optional until the user deliberately chooses one.
struct BirthdayPickerSheet: View {
    let initialDate: Date
    let maximumDate: Date
    let onCancel: () -> Void
    let onConfirm: (Date) -> Void

    @State private var selection: Date

    init(initialDate: Date,
         maximumDate: Date = BirthdayDateOnly.localToday(),
         onCancel: @escaping () -> Void,
         onConfirm: @escaping (Date) -> Void) {
        self.initialDate = initialDate
        self.maximumDate = maximumDate
        self.onCancel = onCancel
        self.onConfirm = onConfirm
        _selection = State(initialValue: initialDate)
    }

    var body: some View {
        NavigationStack {
            DatePicker(
                "Birthday",
                selection: $selection,
                // A birthday cannot be in the future. The bound is today encoded
                // at GMT noon to match the picker's GMT anchoring below.
                in: ...maximumDate,
                displayedComponents: .date
            )
            // Interpret the selection in GMT so the graphical picker shows and
            // captures the same date-only day in every zone, including ones that
            // skip a calendar day.
            .environment(\.timeZone, BirthdayDateOnly.timeZone)
            .datePickerStyle(.graphical)
            .labelsHidden()
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .navigationTitle("Birthday")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                        .accessibilityIdentifier("cancelBirthday")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onConfirm(selection) }
                        .accessibilityIdentifier("confirmBirthday")
                }
            }
        }
    }
}

#Preview {
    BirthdayPickerSheet(
        initialDate: Date(),
        onCancel: {},
        onConfirm: { _ in }
    )
}
