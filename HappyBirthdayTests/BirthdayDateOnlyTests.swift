import XCTest
@testable import HappyBirthday

/// Regressions for the date-only presentation boundary: a stored birthday must
/// display, seed, confirm, and reload as the day the user chose, even in a time
/// zone that skips that calendar day, and the picker's "today" bound must follow
/// the device's *local* day around UTC midnight.
///
/// These exercise the production `BirthdayDateOnly` helper and `DetailsStore`
/// directly rather than re-deriving the arithmetic in the test.
final class BirthdayDateOnlyTests: XCTestCase {
    private func gregorian(_ identifier: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: identifier)!
        return calendar
    }

    private func makePersistence() -> (DetailsPersistence, String, UserDefaults) {
        let suiteName = "BirthdayDateOnlyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(suiteName, isDirectory: true)
        let persistence = DetailsPersistence(
            defaults: defaults,
            photoFileURL: directory.appendingPathComponent("birthday-photo.jpg")
        )
        return (persistence, suiteName, defaults)
    }

    // MARK: - Skipped-day presentation

    /// Pacific/Apia skipped local Dec 30, 2011 when it crossed the date line.
    /// The date-only helper keeps that day intact where the current-zone
    /// reconstruction would normalize it to Dec 31.
    func testApiaSkippedDayPresentationKeepsStoredDay() throws {
        let skipped = StoredBirthday(year: 2011, month: 12, day: 30)

        // The hazard the fix removes: reconstructing the stored day in Apia
        // lands on Dec 31 because local Dec 30 never existed.
        let apia = gregorian("Pacific/Apia")
        let apiaReconstruction = try XCTUnwrap(skipped.date(timeZone: TimeZone(identifier: "Pacific/Apia")!))
        XCTAssertEqual(apia.dateComponents([.day], from: apiaReconstruction).day, 31,
                       "Precondition: Apia reconstruction shifts the skipped day to Dec 31.")

        // The fix: the GMT-anchored presentation date keeps Dec 30.
        let presentation = try XCTUnwrap(BirthdayDateOnly.presentationDate(for: skipped))
        let components = BirthdayDateOnly.calendar.dateComponents([.year, .month, .day], from: presentation)
        XCTAssertEqual([components.year, components.month, components.day], [2011, 12, 30])
    }

    /// Formatting, seeding, confirming without edits, and reloading a skipped
    /// day on a device "in" Apia all preserve 2011-12-30.
    func testApiaSkippedDayUIBoundaryRoundTripsUnchanged() throws {
        let (persistence, suiteName, defaults) = makePersistence()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        persistence.save(birthday: StoredBirthday(year: 2011, month: 12, day: 30))

        let apiaProvider: () -> TimeZone = { TimeZone(identifier: "Pacific/Apia")! }
        let store = DetailsStore(persistence: persistence, timeZoneProvider: apiaProvider)

        // Display: format the canonical day at GMT, as DetailsView does.
        let stored = try XCTUnwrap(store.storedBirthday)
        let seed = try XCTUnwrap(BirthdayDateOnly.presentationDate(for: stored))
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = BirthdayDateOnly.calendar
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        formatter.timeZone = BirthdayDateOnly.timeZone
        let label = formatter.string(from: seed)
        XCTAssertTrue(label.contains("30"), "Display should read the stored day (30): \(label)")
        XCTAssertTrue(label.contains("2011"), "Display should read the stored year: \(label)")

        // Confirm without editing (GMT-anchored "Done") must not shift the day.
        store.selectBirthday(seed, timeZone: BirthdayDateOnly.timeZone)
        XCTAssertEqual(store.storedBirthday, StoredBirthday(year: 2011, month: 12, day: 30))

        // Reload on the same simulated device keeps the day.
        let reloaded = DetailsStore(persistence: persistence, timeZoneProvider: apiaProvider)
        XCTAssertEqual(reloaded.storedBirthday, StoredBirthday(year: 2011, month: 12, day: 30))
    }

    // MARK: - Today bound around UTC midnight

    /// A device in Tokyo (ahead of UTC) just past local midnight is a day ahead
    /// of UTC; the bound must follow the *local* day, not the UTC day.
    func testLocalTodayFollowsLocalDayWhenAheadOfUTC() {
        // UTC 2024-03-09 20:00 == Tokyo 2024-03-10 05:00.
        let now = gregorian("UTC")
            .date(from: DateComponents(year: 2024, month: 3, day: 9, hour: 20))!
        let today = BirthdayDateOnly.localToday(now: now, timeZone: TimeZone(identifier: "Asia/Tokyo")!)

        let components = BirthdayDateOnly.calendar.dateComponents([.year, .month, .day], from: today)
        XCTAssertEqual([components.year, components.month, components.day], [2024, 3, 10])
        // Capture of the bound is consistent with the local day.
        XCTAssertEqual(BirthdayDateOnly.storedBirthday(from: today),
                       StoredBirthday(year: 2024, month: 3, day: 10))
    }

    /// A device in Los Angeles (behind UTC) before local midnight is a day
    /// behind UTC; the bound must still follow the local day.
    func testLocalTodayFollowsLocalDayWhenBehindUTC() {
        // UTC 2024-03-10 03:00 == Los Angeles 2024-03-09 19:00.
        let now = gregorian("UTC")
            .date(from: DateComponents(year: 2024, month: 3, day: 10, hour: 3))!
        let today = BirthdayDateOnly.localToday(now: now, timeZone: TimeZone(identifier: "America/Los_Angeles")!)

        let components = BirthdayDateOnly.calendar.dateComponents([.year, .month, .day], from: today)
        XCTAssertEqual([components.year, components.month, components.day], [2024, 3, 9])
        XCTAssertEqual(BirthdayDateOnly.storedBirthday(from: today),
                       StoredBirthday(year: 2024, month: 3, day: 9))
    }

    // MARK: - Default capture semantics preserved

    /// The defaulted `selectBirthday(_:)` still captures the day in the store's
    /// injected zone, so existing travel semantics are untouched.
    func testDefaultSelectBirthdayStillUsesInjectedZone() {
        let (persistence, suiteName, defaults) = makePersistence()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = DetailsStore(persistence: persistence,
                                 timeZoneProvider: { TimeZone(identifier: "America/New_York")! })
        // Noon in New York on March 9 — captured in the injected zone as March 9.
        let chosen = gregorian("America/New_York")
            .date(from: DateComponents(year: 2024, month: 3, day: 9, hour: 12))!
        store.selectBirthday(chosen)
        XCTAssertEqual(store.storedBirthday, StoredBirthday(year: 2024, month: 3, day: 9))
    }
}
