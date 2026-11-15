import PhotosUI
import SwiftUI
import UIKit

/// Coordinates the shared "add / change photo" flow used by both the details
/// screen and the birthday screen: a confirmation dialog offering the library or
/// camera, the modern out-of-process `PhotosPicker`, the camera via the existing
/// `CameraPicker`, and the generation-based coordination that lets the newest
/// selection supersede a slower earlier one.
///
/// Each screen owns its own instance (`@StateObject`), so the birthday screen can
/// run its selection independently of the details screen behind it. All state is
/// `@MainActor`-isolated; results are only applied when they still belong to the
/// current generation, so a cancelled or superseded import leaves the existing
/// photo untouched and is never reported as a failure.
@MainActor
final class PhotoSelection: ObservableObject {
    @Published var showOptions = false
    @Published var showLibraryPicker = false
    @Published var selectedItem: PhotosPickerItem?
    @Published var presentCamera = false
    @Published var cameraMessage: String?
    @Published private(set) var isImporting = false

    private var importTask: Task<Void, Never>?
    /// Bumped whenever a new selection starts, a camera photo is taken, or the
    /// flow is invalidated. A result must present the generation it started with
    /// to be accepted, so stale work is dropped silently.
    private var generation = 0

    /// A camera capture awaiting the camera cover's actual dismissal. Persisting
    /// (and any resulting error alert) is deferred until `onDismiss` fires, so an
    /// error can never be requested while the full-screen cover is still on
    /// screen. Carries the generation it was staged under so an invalidation
    /// between capture and dismissal drops it.
    private var stagedCapture: (image: UIImage, generation: Int)?

    /// Present the choice of library or camera.
    func begin() {
        showOptions = true
    }

    /// Cancel any in-flight import and pending camera authorization, and bump the
    /// generation so a late result is ignored. Used when a newer context takes
    /// over (e.g. opening the birthday screen while a details import is pending)
    /// or when the owning screen closes. A superseded import is not a failure, so
    /// no error is surfaced and the existing photo is preserved.
    func invalidate() {
        importTask?.cancel()
        importTask = nil
        generation += 1
        isImporting = false
        selectedItem = nil
        stagedCapture = nil
    }

    // MARK: - Library

    /// Load a library selection off the main actor, applying the result only if
    /// it still belongs to the current generation.
    func importLibrarySelection(_ item: PhotosPickerItem?, into store: DetailsStore) {
        guard let item else { return }
        let token = beginImport()
        importTask = Task {
            let image = try? await item.loadTransferable(type: Data.self).flatMap { UIImage(data: $0) }
            await MainActor.run {
                applyImportResult(image, generation: token, into: store)
            }
        }
    }

    /// Begin a new import, superseding any earlier in-flight one. Returns the
    /// generation token the eventual result must present to be accepted. Exposed
    /// so the coordination can be exercised deterministically in tests.
    func beginImport() -> Int {
        importTask?.cancel()
        importTask = nil
        generation += 1
        isImporting = true
        selectedItem = nil
        return generation
    }

    /// Apply (or discard) an import result. A result from a superseded or
    /// cancelled generation is ignored and is never reported as a failure, so a
    /// late completion leaves the existing photo and shows no error. A `nil`
    /// image from the *current* generation is a genuine import failure.
    func applyImportResult(_ image: UIImage?, generation token: Int, into store: DetailsStore) {
        guard token == generation else { return }
        if let image {
            store.setPhoto(image)
        } else {
            store.reportImportFailure()
        }
        isImporting = false
        selectedItem = nil
    }

    // MARK: - Camera

    func startCamera() {
        guard CameraAccess.isAvailable else {
            cameraMessage = "The camera isn’t available on this device."
            return
        }
        // Capture the generation so a late authorization callback for a flow that
        // has since been invalidated does not pop the camera unexpectedly.
        let token = generation
        CameraAccess.requestAccess { [weak self] granted in
            guard let self, token == self.generation else { return }
            if granted {
                self.presentCamera = true
            } else {
                self.cameraMessage = "Camera access is off. You can turn it on in Settings › Privacy › Camera."
            }
        }
    }

    /// Stage a camera capture and begin dismissing the camera cover. The capture
    /// supersedes any pending library import *immediately* (so a late import
    /// result cannot win), but persistence and any error alert are deferred to
    /// `commitStagedCapture(into:)` — called from the cover's `onDismiss` — so an
    /// alert is never requested while the full-screen camera is still dismissing.
    func stageCapture(_ image: UIImage) {
        let token = beginImport()
        // No asynchronous import is in flight; the work is the pending commit.
        isImporting = false
        stagedCapture = (image, token)
        presentCamera = false
    }

    /// Persist a staged capture once the camera cover is actually gone. Does
    /// nothing if there is no staged capture (a cancelled camera) or if the flow
    /// was invalidated after staging, so the previous photo is preserved. Clears
    /// the staged capture first, so a repeated `onDismiss` cannot save twice.
    func commitStagedCapture(into store: DetailsStore) {
        guard let staged = stagedCapture else { return }
        stagedCapture = nil
        guard staged.generation == generation else { return }
        store.setPhoto(staged.image)
    }
}

/// Attaches the shared photo-selection surfaces (dialog, picker, camera, and the
/// camera/import error alerts) to a screen that drives a `PhotoSelection`.
///
/// `presentsStoreErrors` lets the hidden details screen suppress the store's
/// import/save error alert while the birthday screen covers it, so exactly one
/// alert is ever active and the error appears on the screen the user is looking
/// at.
struct PhotoSelectionModifier: ViewModifier {
    @ObservedObject var selection: PhotoSelection
    @ObservedObject var store: DetailsStore
    var presentsStoreErrors: Bool = true

    /// Local mirror of `selection.showOptions` that backs the confirmation dialog.
    /// SwiftUI writes this binding to `false` as part of reconciling a tap-outside
    /// or action-button dismissal; driving that write into local `@State` rather
    /// than straight into the `@Published` property keeps the dismissal from
    /// publishing an `ObservableObject` change during a view update. The two are
    /// kept in sync below via `onChange`, which runs after the update completes.
    @State private var showOptions = false

    func body(content: Content) -> some View {
        content
            .confirmationDialog("Add a photo", isPresented: $showOptions, titleVisibility: .visible) {
                Button("Choose from Library") { selection.showLibraryPicker = true }
                Button("Take Photo") { selection.startCamera() }
                Button("Cancel", role: .cancel) {}
            }
            .onChange(of: selection.showOptions) { _, requested in
                if showOptions != requested { showOptions = requested }
            }
            .onChange(of: showOptions) { _, presented in
                if selection.showOptions != presented { selection.showOptions = presented }
            }
            // The default (out-of-process) picker needs no photo-library permission.
            .photosPicker(
                isPresented: $selection.showLibraryPicker,
                selection: $selection.selectedItem,
                matching: .images
            )
            .onChange(of: selection.selectedItem) { _, newItem in
                selection.importLibrarySelection(newItem, into: store)
            }
            .fullScreenCover(
                isPresented: $selection.presentCamera,
                onDismiss: { selection.commitStagedCapture(into: store) }
            ) {
                CameraPicker(
                    onImage: { selection.stageCapture($0) },
                    onCancel: { selection.presentCamera = false }
                )
                .ignoresSafeArea()
            }
            .alert(
                "Camera",
                isPresented: Binding(
                    get: { selection.cameraMessage != nil },
                    set: { if !$0 { selection.cameraMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { selection.cameraMessage = nil }
            } message: {
                Text(selection.cameraMessage ?? "")
            }
            .alert(
                "Something went wrong",
                isPresented: Binding(
                    get: { presentsStoreErrors && store.errorMessage != nil },
                    set: { if !$0 { store.errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { store.errorMessage = nil }
            } message: {
                Text(store.errorMessage ?? "")
            }
    }
}

extension View {
    /// Attach the shared photo-selection flow driven by `selection`.
    func photoSelection(
        _ selection: PhotoSelection,
        store: DetailsStore,
        presentsStoreErrors: Bool = true
    ) -> some View {
        modifier(PhotoSelectionModifier(
            selection: selection,
            store: store,
            presentsStoreErrors: presentsStoreErrors
        ))
    }
}
