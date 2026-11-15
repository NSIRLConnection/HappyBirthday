import SwiftUI

/// The app's opening screen: title, name, birthday, picture, and the button
/// that will present the birthday screen in a later step.
///
/// Details are injected so previews and tests can exercise each readiness
/// state directly. Styling is intentionally minimal — this screen is a working
/// surface, not a finished design.
struct DetailsView: View {
    let details: BirthdayDetails

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private static let birthdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter
    }()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    picture
                    valueRows
                    showBirthdayButton
                }
                .padding()
                // Keep content readable on wide iPad layouts while filling
                // the available width on phones.
                .frame(maxWidth: 480)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Happy Birthday")
            // Keep the large title at default sizes; switch to inline at
            // accessibility sizes so it stays readable instead of truncating.
            .navigationBarTitleDisplayMode(
                dynamicTypeSize.isAccessibilitySize ? .inline : .large
            )
        }
    }

    // MARK: - Picture

    private var picture: some View {
        Image(systemName: "photo")
            .resizable()
            .scaledToFit()
            .frame(maxWidth: 160)
            .padding(40)
            .foregroundStyle(.secondary)
            .background(.quaternary, in: Circle())
            .accessibilityLabel("No picture selected")
    }

    // MARK: - Values

    private var valueRows: some View {
        VStack(spacing: 16) {
            detailRow(
                label: "Name",
                value: displayName,
                placeholder: "No name yet"
            )
            detailRow(
                label: "Birthday",
                value: displayBirthday,
                placeholder: "No birthday yet"
            )
        }
    }

    private var displayName: String? {
        let trimmed = details.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var displayBirthday: String? {
        details.birthday.map { Self.birthdayFormatter.string(from: $0) }
    }

    private func detailRow(label: String, value: String?, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value ?? placeholder)
                .font(.body)
                .foregroundStyle(value == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Action

    private var showBirthdayButton: some View {
        // Navigation itself is step 3; here the button only reflects readiness.
        Button {
        } label: {
            // Fill the available width and wrap centered at large sizes rather
            // than growing into a tall single-line capsule.
            Text("Show birthday screen")
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .buttonBorderShape(.roundedRectangle)
        .disabled(!details.isReadyToShowBirthday)
        .accessibilityIdentifier("showBirthdayButton")
    }
}

#Preview("Empty — button disabled") {
    DetailsView(details: BirthdayDetails())
}

#Preview("Ready — button enabled") {
    DetailsView(
        details: BirthdayDetails(
            name: "Ada Lovelace",
            birthday: DateComponents(
                calendar: .current,
                year: 2024,
                month: 3,
                day: 9
            ).date
        )
    )
}
