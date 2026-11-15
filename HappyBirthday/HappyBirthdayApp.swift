import SwiftUI

@main
struct HappyBirthdayApp: App {
    @StateObject private var store = DetailsStore(persistence: AppPersistenceFactory.make())

    var body: some Scene {
        WindowGroup {
            DetailsView(store: store)
        }
    }
}

/// Chooses which persistence the app runs against.
///
/// Normal launches use the real store. UI tests pass launch arguments to route
/// through an isolated store (a separate defaults suite and photo directory) so
/// they never read or overwrite real user data. The isolated path is
/// debug-only.
enum AppPersistenceFactory {
    static func make() -> DetailsPersistence {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--uitest") {
            return makeUITestPersistence(reset: arguments.contains("--uitest-reset"))
        }
        #endif
        return .makeDefault()
    }

    #if DEBUG
    /// An isolated store for UI tests. `reset` clears it so a test can start
    /// from a known-empty state; a relaunch without `reset` keeps the data,
    /// which is how persistence-across-launch is exercised.
    private static func makeUITestPersistence(reset: Bool) -> DetailsPersistence {
        let suiteName = "com.nanit.HappyBirthday.uitests"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard

        let directory = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("UITests", isDirectory: true)
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("UITests", isDirectory: true)
        let photoURL = directory.appendingPathComponent("birthday-photo.jpg")

        if reset {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directory)
        }

        return DetailsPersistence(defaults: defaults, photoFileURL: photoURL)
    }
    #endif
}
