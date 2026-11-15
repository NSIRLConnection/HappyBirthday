import SwiftUI
import UIKit

/// The app's opening screen: title, editable name, birthday, picture, and the
/// button that presents the full-screen birthday screen.
///
/// Editing and persistence are driven by an injected `DetailsStore`, so previews
/// and tests can supply isolated storage. Styling is intentionally minimal —
/// this screen is a working surface, not a finished design.
struct DetailsView: View {
    @ObservedObject var store: DetailsStore

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @FocusState private var nameFieldFocused: Bool

    @State private var isEditingBirthday = false
    @State private var showBirthday = false

    // The shared add/change-photo flow (dialog, picker, camera, import
    // coordination). The birthday screen owns its own instance.
    @StateObject private var photoSelection = PhotoSelection()

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
                    nameField
                    birthdayField
                    showBirthdayButton
                }
                .padding()
                // Keep content readable on wide iPad layouts while filling the
                // available width on phones.
                .frame(maxWidth: 480)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Happy Birthday")
            // Keep the large title at default sizes; switch to inline at
            // accessibility sizes so it stays readable instead of truncating.
            .navigationBarTitleDisplayMode(
                dynamicTypeSize.isAccessibilitySize ? .inline : .large
            )
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { nameFieldFocused = false }
                }
            }
        }
        // Dialog, library picker, camera, and the camera/store error alerts. The
        // store-error alert is suppressed while the birthday screen covers this
        // one, so the birthday screen presents those errors instead.
        .photoSelection(photoSelection, store: store, presentsStoreErrors: !showBirthday)
        .sheet(isPresented: $isEditingBirthday) {
            BirthdayPickerSheet(
                // Seed from the canonical stored day at GMT so the picker opens
                // on exactly the displayed date, even in a zone that skips it.
                initialDate: store.storedBirthday
                    .flatMap(BirthdayDateOnly.presentationDate) ?? BirthdayDateOnly.localToday(),
                onCancel: { isEditingBirthday = false },
                onConfirm: { date in
                    // The picker is GMT-anchored, so capture the day in GMT too.
                    store.selectBirthday(date, timeZone: BirthdayDateOnly.timeZone)
                    isEditingBirthday = false
                }
            )
        }
        .fullScreenCover(isPresented: $showBirthday) {
            BirthdayView(store: store, onClose: { showBirthday = false })
        }
    }

    // MARK: - Picture

    private var picture: some View {
        Button {
            nameFieldFocused = false
            photoSelection.begin()
        } label: {
            pictureContent
                .overlay {
                    if photoSelection.isImporting {
                        ProgressView()
                            .controlSize(.large)
                            .padding(24)
                            .background(.ultraThinMaterial, in: Circle())
                            .accessibilityLabel("Importing photo")
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(photoSelection.isImporting)
        .accessibilityLabel(store.image == nil ? "Add photo" : "Change photo")
        .accessibilityIdentifier("photoButton")
    }

    @ViewBuilder
    private var pictureContent: some View {
        if let image = store.image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 180, height: 180)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(.quaternary, lineWidth: 1))
        } else {
            Image(systemName: "photo")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 160)
                .padding(40)
                .foregroundStyle(.secondary)
                .background(.quaternary, in: Circle())
        }
    }

    // MARK: - Name

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Name")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("Child’s name", text: $store.name)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
                .focused($nameFieldFocused)
                .onSubmit { nameFieldFocused = false }
                .accessibilityLabel("Name")
                .accessibilityIdentifier("nameField")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Birthday

    private var birthdayField: some View {
        Button {
            nameFieldFocused = false
            isEditingBirthday = true
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text("Birthday")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(displayBirthday ?? "Set birthday")
                    .font(.body)
                    .foregroundStyle(displayBirthday == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            displayBirthday.map { "Birthday, \($0)" } ?? "Birthday, not set"
        )
        .accessibilityHint("Opens a date picker")
        .accessibilityIdentifier("birthdayButton")
    }

    private var displayBirthday: String? {
        guard let birthday = store.storedBirthday,
              let date = BirthdayDateOnly.presentationDate(for: birthday) else { return nil }
        // Format the canonical day at GMT so the label always reads as the stored
        // day — a zone that skips that calendar day can't shift it.
        let formatter = Self.birthdayFormatter
        formatter.timeZone = BirthdayDateOnly.timeZone
        return formatter.string(from: date)
    }

    // MARK: - Action

    private var showBirthdayButton: some View {
        Button {
            nameFieldFocused = false
            // A library import started on this screen must not overwrite a photo
            // the user later picks on the birthday screen, so supersede it here.
            photoSelection.invalidate()
            showBirthday = true
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
        .disabled(!store.isReadyToShowBirthday)
        .accessibilityIdentifier("showBirthdayButton")
    }
}

#Preview("Empty — button disabled") {
    DetailsView(store: DetailsStore(persistence: .previewEmpty()))
}

#Preview("Ready — button enabled") {
    DetailsView(store: DetailsStore(persistence: .previewReady()))
}

private extension DetailsPersistence {
    /// An ephemeral store under a unique temporary directory, used only by
    /// previews so they never read or write real user data.
    static func previewEmpty() -> DetailsPersistence {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("preview-\(UUID().uuidString)", isDirectory: true)
        let defaults = UserDefaults(suiteName: "preview-\(UUID().uuidString)") ?? .standard
        return DetailsPersistence(defaults: defaults, photoFileURL: directory.appendingPathComponent("photo.jpg"))
    }

    static func previewReady() -> DetailsPersistence {
        let persistence = previewEmpty()
        persistence.save(name: "Ada Lovelace")
        persistence.save(birthday: StoredBirthday(year: 2024, month: 3, day: 9))
        return persistence
    }
}
