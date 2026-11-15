import Foundation

/// Presents and edits a birthday as a *date-only* value anchored to GMT.
///
/// The store keeps the canonical day as `StoredBirthday` components. For the age
/// arithmetic that is enough, but the details UI needs a concrete `Date` to
/// format and to seed the picker — and reconstructing the stored day in the
/// *current* zone is unsafe for a zone that skips a calendar day. Pacific/Apia
/// crossing the date line at the end of 2011 is the real case: local Dec 30 2011
/// never existed there, so rebuilding `StoredBirthday(2011, 12, 30)` in that
/// zone normalizes to Dec 31. The UI would then display Dec 31 and, on a no-op
/// "Done", persist Dec 31 — a silent, rare data loss.
///
/// GMT never skips or repeats a day, so every valid Gregorian birthday has a
/// faithful date-only representation here. The current time zone is used only to
/// find *today* for the picker's upper bound, never to reconstruct the stored
/// day.
enum BirthdayDateOnly {
    /// The fixed zone every date-only value is anchored to. GMT has no DST and
    /// no historical date-line skips, so the numeric day round-trips unchanged.
    static let timeZone = TimeZone(secondsFromGMT: 0)!

    /// A Gregorian calendar pinned to `timeZone`, shared by formatting, the
    /// picker environment, and today's bound so they all agree on the day.
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    /// The stored day as a concrete `Date` at GMT noon, for display and for
    /// seeding the GMT-anchored picker. `nil` for an impossible day.
    static func presentationDate(for birthday: StoredBirthday) -> Date? {
        birthday.date(timeZone: timeZone)
    }

    /// The stored day captured from a GMT-anchored picker selection, so the day
    /// the user sees is the day that is persisted.
    static func storedBirthday(from date: Date) -> StoredBirthday? {
        StoredBirthday(date: date, timeZone: timeZone)
    }

    /// Today — as seen in `timeZone` — expressed as a GMT-noon date so it can
    /// bound a GMT-anchored picker to "not in the future".
    ///
    /// The local year/month/day is derived first because a device just before or
    /// after local midnight is on a different calendar day than GMT; that local
    /// day is then re-encoded at GMT noon. `now` and the zone are injected so the
    /// boundary is testable without touching system state.
    static func localToday(now: Date = Date(), timeZone: TimeZone = .current) -> Date {
        var localCalendar = Calendar(identifier: .gregorian)
        localCalendar.timeZone = timeZone
        let components = localCalendar.dateComponents([.year, .month, .day], from: now)
        var gmtComponents = DateComponents()
        gmtComponents.year = components.year
        gmtComponents.month = components.month
        gmtComponents.day = components.day
        gmtComponents.hour = 12
        // A real calendar day always rebuilds; fall back to `now` only to stay
        // total.
        return calendar.date(from: gmtComponents) ?? now
    }
}
