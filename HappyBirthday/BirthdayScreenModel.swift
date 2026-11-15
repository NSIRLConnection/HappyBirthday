import SwiftUI
import UIKit

/// Backs a single presentation of the birthday screen.
///
/// The theme is drawn once when the model is created and retained for the whole
/// presentation, so SwiftUI redraws, rotation, and backgrounding never reshuffle
/// it — the next entry constructs a new model and draws again (consecutive
/// repeats are valid). The age is derived on demand from the canonical
/// `StoredBirthday` against the current local calendar day, and the reference
/// date refreshes on a day change, time-zone change, or return to the
/// foreground so a long-lived presentation stays correct without extra
/// machinery.
final class BirthdayScreenModel: ObservableObject {
    /// The visual option chosen for this presentation. Immutable for its
    /// lifetime.
    let theme: BirthdayTheme

    /// The "now" the age is measured against. Published so a day/zone change
    /// refreshes the displayed age.
    @Published private(set) var referenceDate: Date

    private let timeZoneProvider: () -> TimeZone
    private var observers: [NSObjectProtocol] = []

    init(theme: BirthdayTheme,
         referenceDate: Date = Date(),
         timeZoneProvider: @escaping () -> TimeZone = { .current }) {
        self.theme = theme
        self.referenceDate = referenceDate
        self.timeZoneProvider = timeZoneProvider
        observeDayChanges()
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    /// The age for the given stored birthday as of the current reference date,
    /// or `nil` when no birthday is set (the screen is only reachable when one
    /// is, but this stays defensive).
    func age(for storedBirthday: StoredBirthday?) -> BirthdayAge? {
        guard let storedBirthday else { return nil }
        return AgeCalculator.age(
            for: storedBirthday,
            asOf: referenceDate,
            timeZone: timeZoneProvider()
        )
    }

    private func observeDayChanges() {
        let names: [Notification.Name] = [
            .NSCalendarDayChanged,
            .NSSystemTimeZoneDidChange,
            UIApplication.willEnterForegroundNotification,
        ]
        observers = names.map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.referenceDate = Date()
            }
        }
    }
}
