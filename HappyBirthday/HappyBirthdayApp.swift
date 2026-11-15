import SwiftUI
import UIKit

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
            let persistence = makeUITestPersistence(reset: arguments.contains("--uitest-reset"))
            seedIfRequested(into: persistence, arguments: arguments)
            return persistence
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

    /// Debug-only fixtures for repeatable birthday-screen design checks. These
    /// write into the isolated UI-test store only — never the real store — and
    /// only when explicitly requested by a launch argument.
    ///
    /// - `--uitest-seed` seeds a ready child (long name + a birthday one month
    ///   ago, so the screen reads "1 MONTH OLD!" on any run date).
    /// - `--uitest-months-ago <0...1200>` overrides how many months ago the
    ///   seeded birthday falls (default 1), for multi-digit age design checks.
    /// - `--uitest-seed-photo` additionally seeds a solid-colour photo.
    private static func seedIfRequested(into persistence: DetailsPersistence, arguments: [String]) {
        guard arguments.contains("--uitest-seed") else { return }

        let name = value(for: "--uitest-name", in: arguments) ?? "Cristiano Ronaldo"
        persistence.save(name: name)

        // Bounded so a malformed/extreme fixture value cannot build an invalid
        // or absurd date; defaults to one month ago.
        let monthsAgo = min(1200, max(0, value(for: "--uitest-months-ago", in: arguments).flatMap(Int.init) ?? 1))

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let seededDate = calendar.date(byAdding: .month, value: -monthsAgo, to: Date()) ?? Date()
        if let stored = StoredBirthday(date: seededDate, timeZone: .current) {
            persistence.save(birthday: stored)
        }

        if arguments.contains("--uitest-seed-photo") {
            let size = CGSize(width: 240, height: 240)
            let image = UIGraphicsImageRenderer(size: size).image { context in
                UIColor.systemTeal.setFill()
                context.fill(CGRect(origin: .zero, size: size))
            }
            if let data = image.jpegData(compressionQuality: 0.8) {
                try? persistence.savePhoto(data: data)
            }
        }
    }

    private static func value(for flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag),
              arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }
    #endif
}
