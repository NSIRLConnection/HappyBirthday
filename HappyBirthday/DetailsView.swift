import PhotosUI
import SwiftUI
import UIKit

/// The app's opening screen: title, editable name, birthday, picture, and the
/// button that will present the birthday screen in a later step.
///
/// Editing and persistence are driven by an injected `DetailsStore`, so previews
/// and tests can supply isolated storage. Styling is intentionally minimal —
/// this screen is a working surface, not a finished design.
struct DetailsView: View {
    @ObservedObject var store: DetailsStore

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @FocusState private var nameFieldFocused: Bool

    @State private var isEditingBirthday = false
    @State private var showPhotoOptions = false
    @State private var showLibraryPicker = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var presentCamera = false
    @State private var cameraMessage: String?

    // A camera capture awaiting the camera cover's actual dismissal. Persisting
    // (and any resulting save-error alert) is deferred to the cover's onDismiss
    // so the alert is never requested while the full-screen camera is still on
    // screen. Cleared on commit, so a repeat dismissal can't save twice and no
    // stale capture survives into the next presentation.
    @State private var stagedCameraImage: UIImage?

    // Photo-import coordination: a generation counter lets a newer selection or
    // a camera capture supersede a slower in-flight library import so stale
    // results can never overwrite the latest choice.
    @State private var isImportingPhoto = false
    @State private var photoImportTask: Task<Void, Never>?
    @State private var photoGeneration = 0

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
        .confirmationDialog("Add a photo", isPresented: $showPhotoOptions, titleVisibility: .visible) {
            Button("Choose from Library") { showLibraryPicker = true }
            Button("Take Photo") { startCamera() }
            Button("Cancel", role: .cancel) {}
        }
        // The default (out-of-process) picker needs no photo-library permission.
        .photosPicker(
            isPresented: $showLibraryPicker,
            selection: $selectedPhotoItem,
            matching: .images
        )
        .onChange(of: selectedPhotoItem) { _, newItem in
            importLibrarySelection(newItem)
        }
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
        .fullScreenCover(isPresented: $presentCamera, onDismiss: commitStagedCapture) {
            CameraPicker(
                onImage: { image in
                    // Supersede any in-flight library import immediately so a late
                    // import result can't win, then stage the capture and begin
                    // dismissing. The save itself is deferred to onDismiss.
                    photoImportTask?.cancel()
                    photoGeneration += 1
                    isImportingPhoto = false
                    selectedPhotoItem = nil
                    stagedCameraImage = image
                    presentCamera = false
                },
                onCancel: { presentCamera = false }
            )
            .ignoresSafeArea()
        }
        .alert(
            "Camera",
            isPresented: Binding(
                get: { cameraMessage != nil },
                set: { if !$0 { cameraMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { cameraMessage = nil }
        } message: {
            Text(cameraMessage ?? "")
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(
                get: { store.errorMessage != nil },
                set: { if !$0 { store.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
    }

    // MARK: - Picture

    private var picture: some View {
        Button {
            nameFieldFocused = false
            showPhotoOptions = true
        } label: {
            pictureContent
                .overlay {
                    if isImportingPhoto {
                        ProgressView()
                            .controlSize(.large)
                            .padding(24)
                            .background(.ultraThinMaterial, in: Circle())
                            .accessibilityLabel("Importing photo")
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(isImportingPhoto)
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
        .disabled(!store.isReadyToShowBirthday)
        .accessibilityIdentifier("showBirthdayButton")
    }

    // MARK: - Photo import

    private func importLibrarySelection(_ item: PhotosPickerItem?) {
        guard let item else { return }

        // Cancel a slower earlier import and claim the newest generation.
        photoImportTask?.cancel()
        photoGeneration += 1
        let generation = photoGeneration
        isImportingPhoto = true

        photoImportTask = Task {
            let image = try? await item.loadTransferable(type: Data.self).flatMap { UIImage(data: $0) }
            await MainActor.run {
                // A newer selection or a camera photo has superseded this one:
                // discard the result and leave the existing photo untouched.
                guard generation == photoGeneration else { return }
                if let image {
                    store.setPhoto(image)
                } else {
                    store.reportImportFailure()
                }
                isImportingPhoto = false
                selectedPhotoItem = nil
            }
        }
    }

    // MARK: - Camera

    private func startCamera() {
        guard CameraAccess.isAvailable else {
            cameraMessage = "The camera isn’t available on this device."
            return
        }
        CameraAccess.requestAccess { granted in
            if granted {
                presentCamera = true
            } else {
                cameraMessage = "Camera access is off. You can turn it on in Settings › Privacy › Camera."
            }
        }
    }

    /// Persist a staged camera capture once the camera cover is actually gone, so
    /// a save-error alert can appear over the details screen rather than being
    /// requested behind the dismissing cover. A cancelled camera stages nothing,
    /// so the previous photo is preserved. The staged image is cleared first so a
    /// repeated dismissal can't save twice.
    private func commitStagedCapture() {
        guard let image = stagedCameraImage else { return }
        stagedCameraImage = nil
        store.setPhoto(image)
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
