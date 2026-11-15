import SwiftUI
import UIKit

/// Owns the editable details and keeps them in sync with persistent storage.
///
/// The view binds to `name` directly; `birthday` and `image` are read-only to
/// the view and only change through deliberate methods, so an accidental write
/// can never slip in. All mutations happen on the main thread (SwiftUI bindings,
/// `MainActor.run`, or a main-queue hop from the camera callback).
final class DetailsStore: ObservableObject {
    /// The child's name. Persisted on each edit; `isLoading` suppresses the
    /// write while the initial value is being restored.
    @Published var name: String = "" {
        didSet {
            guard !isLoading, oldValue != name else { return }
            persistence.save(name: name)
        }
    }

    /// The canonical Gregorian source of truth for the birthday. The displayed
    /// `Date` is always reconstructed from this for the *current* time zone, so
    /// a time-zone change while the app is alive can never shift the stored day.
    @Published private(set) var storedBirthday: StoredBirthday?
    @Published private(set) var image: UIImage?

    /// A concise, user-facing message for a failed import or save. The view
    /// surfaces it in an alert and clears it on dismissal.
    @Published var errorMessage: String?

    private let persistence: DetailsPersistence
    private let timeZoneProvider: () -> TimeZone
    private var isLoading = false
    private var observers: [NSObjectProtocol] = []

    init(persistence: DetailsPersistence,
         timeZoneProvider: @escaping () -> TimeZone = { .current }) {
        self.persistence = persistence
        self.timeZoneProvider = timeZoneProvider
        load()
        observeEnvironmentChanges()
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    /// The birthday rebuilt as a `Date` for the current time zone, suitable for
    /// display and for seeding the picker. `nil` when no birthday is set.
    var birthday: Date? {
        storedBirthday?.date(timeZone: timeZoneProvider())
    }

    var details: BirthdayDetails {
        BirthdayDetails(name: name, birthday: birthday)
    }

    var isReadyToShowBirthday: Bool {
        details.isReadyToShowBirthday
    }

    // MARK: - Loading

    private func load() {
        isLoading = true
        defer { isLoading = false }

        name = persistence.loadName()
        storedBirthday = persistence.loadBirthday()
        // Corrupt or unreadable image data simply yields no photo; the name and
        // birthday are never discarded because of it.
        if let data = persistence.loadPhotoData() {
            image = UIImage(data: data)
        }
    }

    /// Refresh the derived `birthday` display when the time zone changes or the
    /// app returns to the foreground (the stored day is unchanged; only its
    /// reconstructed `Date` depends on the current time zone).
    private func observeEnvironmentChanges() {
        let names: [Notification.Name] = [
            .NSSystemTimeZoneDidChange,
            UIApplication.willEnterForegroundNotification,
        ]
        observers = names.map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.objectWillChange.send()
            }
        }
    }

    // MARK: - Birthday

    /// Commit a deliberately chosen birthday. The view only calls this from the
    /// picker's confirm action, never on cancel, so a cancelled picker leaves
    /// the birthday untouched.
    ///
    /// `date` is interpreted in `timeZone` to read its calendar day. Callers that
    /// omit it default to the injected current zone, preserving the existing
    /// capture semantics; the details UI, whose picker is GMT-anchored, passes
    /// `BirthdayDateOnly.timeZone` so a date-line-skipping zone cannot shift the
    /// captured day.
    func selectBirthday(_ date: Date, timeZone: TimeZone? = nil) {
        let zone = timeZone ?? timeZoneProvider()
        guard let stored = StoredBirthday(date: date, timeZone: zone) else { return }
        persistence.save(birthday: stored)
        storedBirthday = stored
    }

    // MARK: - Photo

    /// Process and persist a newly picked image. On any failure the previously
    /// saved photo is left in place and a concise error is surfaced.
    func setPhoto(_ newImage: UIImage) {
        guard let data = newImage.normalizedForStorage().jpegData(compressionQuality: 0.8) else {
            errorMessage = "That image couldn’t be processed. Your previous photo is unchanged."
            return
        }
        do {
            try persistence.savePhoto(data: data)
            image = UIImage(data: data) ?? newImage
        } catch {
            errorMessage = "The photo couldn’t be saved. Your previous photo is unchanged."
        }
    }

    /// Report that an import failed before any image was produced, without
    /// disturbing the current photo.
    func reportImportFailure() {
        errorMessage = "That photo couldn’t be imported. Your previous photo is unchanged."
    }
}
