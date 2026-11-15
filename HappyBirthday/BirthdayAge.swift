import Foundation

/// A child's age the way the birthday screen presents it: whole completed
/// Gregorian months below one year, whole completed years from the first
/// anniversary onward.
struct BirthdayAge: Equatable {
    enum Unit: Equatable { case months, years }

    /// The number shown as decorative digit artwork.
    let value: Int
    let unit: Unit
}

extension BirthdayAge {
    /// The singular/plural unit caption beneath the number, e.g. `MONTH OLD!`
    /// vs `MONTHS OLD!` or `YEAR OLD!` vs `YEARS OLD!`.
    var unitLabel: String {
        switch unit {
        case .months:
            return value == 1 ? "MONTH OLD!" : "MONTHS OLD!"
        case .years:
            return value == 1 ? "YEAR OLD!" : "YEARS OLD!"
        }
    }

    /// A spoken description that folds the numeric artwork and unit into one
    /// understandable phrase, e.g. "1 month old" — used by the combined
    /// accessibility element so VoiceOver never reads a lone digit image.
    var accessibleDescription: String {
        let noun: String
        switch unit {
        case .months:
            noun = value == 1 ? "month" : "months"
        case .years:
            noun = value == 1 ? "year" : "years"
        }
        return "\(value) \(noun) old"
    }
}

/// Computes a child's age from the canonical `StoredBirthday` (year/month/day),
/// never from arbitrary seconds, a /30 month, or a /365 year.
///
/// The only thing the device time zone is used for is reading **today's** local
/// calendar day. The month/year arithmetic is then done purely on calendar days
/// in a fixed **UTC** Gregorian calendar, where every day exists. This avoids
/// two classes of bug that a "reconstruct an instant in the local zone" approach
/// has: a historical time-zone transition that skips a whole calendar day (e.g.
/// Pacific/Apia crossing the date line at the end of 2011, where local Dec 30
/// 2011 does not exist and would normalize to Dec 31), and a spring-forward
/// midnight that does not exist. Because only date components are compared, the
/// time of day in `asOf` can never nudge a boundary either.
enum AgeCalculator {
    static func age(for birthday: StoredBirthday,
                    asOf now: Date = Date(),
                    timeZone: TimeZone = .current) -> BirthdayAge {
        // A birthday that is not a real Gregorian day (e.g. a manually built
        // Feb 29 in a non-leap year, or month 13) is treated as 0 months rather
        // than being silently normalized.
        guard StoredBirthday.isValid(year: birthday.year, month: birthday.month, day: birthday.day) else {
            return BirthdayAge(value: 0, unit: .months)
        }

        // Read today's calendar day in the device's time zone.
        var localCalendar = Calendar(identifier: .gregorian)
        localCalendar.timeZone = timeZone
        let today = localCalendar.dateComponents([.year, .month, .day], from: now)
        guard let todayYear = today.year,
              let todayMonth = today.month,
              let todayDay = today.day else {
            return BirthdayAge(value: 0, unit: .months)
        }

        // Do all the arithmetic on bare calendar days in UTC, where no day is
        // skipped and there is no DST.
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let birthDate = utc.date(from: DateComponents(
                  year: birthday.year, month: birthday.month, day: birthday.day)),
              let todayDate = utc.date(from: DateComponents(
                  year: todayYear, month: todayMonth, day: todayDay)) else {
            return BirthdayAge(value: 0, unit: .months)
        }

        // Born today, or a birthday in the future, both clamp to 0 months.
        guard todayDate > birthDate else {
            return BirthdayAge(value: 0, unit: .months)
        }

        let difference = utc.dateComponents([.year, .month], from: birthDate, to: todayDate)
        let years = difference.year ?? 0
        let months = difference.month ?? 0
        let completedMonths = years * 12 + months

        if completedMonths < 12 {
            return BirthdayAge(value: completedMonths, unit: .months)
        } else {
            return BirthdayAge(value: years, unit: .years)
        }
    }
}
