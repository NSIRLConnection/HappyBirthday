import XCTest
@testable import HappyBirthday

/// Exercises the age model's month/year boundaries and its calendar, time-zone,
/// DST, end-of-month, and leap-day behaviour. All cases pin an explicit `asOf`
/// instant so they are deterministic rather than dependent on the clock.
final class AgeCalculatorTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!

    /// Builds the noon instant of a Gregorian calendar day in `timeZone`, the
    /// same anchoring the calculator uses, so "today" is unambiguous.
    private func noon(_ year: Int, _ month: Int, _ day: Int, in timeZone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    private func age(born: StoredBirthday,
                     on year: Int, _ month: Int, _ day: Int,
                     timeZone: TimeZone? = nil) -> BirthdayAge {
        let zone = timeZone ?? utc
        return AgeCalculator.age(for: born, asOf: noon(year, month, day, in: zone), timeZone: zone)
    }

    // MARK: - Month boundaries

    func testBornTodayIsZeroMonths() {
        let age = age(born: StoredBirthday(year: 2026, month: 11, day: 15), on: 2026, 11, 15)
        XCTAssertEqual(age, BirthdayAge(value: 0, unit: .months))
    }

    func testFutureBirthdayClampsToZeroMonths() {
        let age = age(born: StoredBirthday(year: 2026, month: 12, day: 25), on: 2026, 11, 15)
        XCTAssertEqual(age, BirthdayAge(value: 0, unit: .months))
    }

    func testOneMonthOld() {
        let age = age(born: StoredBirthday(year: 2026, month: 1, day: 10), on: 2026, 2, 10)
        XCTAssertEqual(age, BirthdayAge(value: 1, unit: .months))
    }

    func testDayBeforeOneMonthIsZeroMonths() {
        let age = age(born: StoredBirthday(year: 2026, month: 1, day: 10), on: 2026, 2, 9)
        XCTAssertEqual(age, BirthdayAge(value: 0, unit: .months))
    }

    func testElevenMonthsStaysInMonths() {
        let age = age(born: StoredBirthday(year: 2025, month: 1, day: 10), on: 2025, 12, 10)
        XCTAssertEqual(age, BirthdayAge(value: 11, unit: .months))
    }

    // MARK: - Year boundaries

    func testFirstAnniversaryBecomesOneYear() {
        let age = age(born: StoredBirthday(year: 2025, month: 3, day: 9), on: 2026, 3, 9)
        XCTAssertEqual(age, BirthdayAge(value: 1, unit: .years))
    }

    func testDayBeforeFirstAnniversaryIsElevenMonths() {
        let age = age(born: StoredBirthday(year: 2025, month: 3, day: 9), on: 2026, 3, 8)
        XCTAssertEqual(age, BirthdayAge(value: 11, unit: .months))
    }

    func testTwoYearsOld() {
        let age = age(born: StoredBirthday(year: 2024, month: 3, day: 9), on: 2026, 3, 9)
        XCTAssertEqual(age, BirthdayAge(value: 2, unit: .years))
    }

    // MARK: - End of month and leap day

    func testEndOfMonthClampsForwardOnShortMonth() {
        // Born Jan 31; one month lands on the last day of February (clamped), so
        // the child is one month old on Feb 28 of a non-leap year.
        let age = age(born: StoredBirthday(year: 2023, month: 1, day: 31), on: 2023, 2, 28)
        XCTAssertEqual(age, BirthdayAge(value: 1, unit: .months))
    }

    func testEndOfMonthNotYetReachedIsZeroMonths() {
        // Feb 27 is before the clamped Feb-28 anniversary, so still zero months.
        let age = age(born: StoredBirthday(year: 2023, month: 1, day: 31), on: 2023, 2, 27)
        XCTAssertEqual(age, BirthdayAge(value: 0, unit: .months))
    }

    func testLeapDayBirthdayReachesOneYearOnFeb28OfNonLeapYear() {
        // Born Feb 29 2020; the first anniversary clamps to Feb 28 2021.
        let age = age(born: StoredBirthday(year: 2020, month: 2, day: 29), on: 2021, 2, 28)
        XCTAssertEqual(age, BirthdayAge(value: 1, unit: .years))
    }

    func testLeapDayBirthdayDayBeforeAnniversaryIsElevenMonths() {
        let age = age(born: StoredBirthday(year: 2020, month: 2, day: 29), on: 2021, 2, 27)
        XCTAssertEqual(age, BirthdayAge(value: 11, unit: .months))
    }

    // MARK: - Time of day, DST, and time-zone independence

    func testTimeOfDayDoesNotShiftTheMonthBoundary() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        let born = StoredBirthday(year: 2026, month: 1, day: 10)

        // Just after midnight and just before midnight on the anniversary day
        // must both read as exactly one month.
        let earlyMorning = calendar.date(from: DateComponents(year: 2026, month: 2, day: 10, hour: 0, minute: 1))!
        let lateNight = calendar.date(from: DateComponents(year: 2026, month: 2, day: 10, hour: 23, minute: 59))!

        XCTAssertEqual(AgeCalculator.age(for: born, asOf: earlyMorning, timeZone: utc),
                       BirthdayAge(value: 1, unit: .months))
        XCTAssertEqual(AgeCalculator.age(for: born, asOf: lateNight, timeZone: utc),
                       BirthdayAge(value: 1, unit: .months))
    }

    func testMonthCountIsCorrectAcrossSpringForwardDST() {
        // New York springs forward on Mar 10 2024. A born-Feb-15 child is still
        // exactly one month old on Mar 15, with no off-by-one from the 23-hour
        // day.
        let ny = TimeZone(identifier: "America/New_York")!
        let age = age(born: StoredBirthday(year: 2024, month: 2, day: 15), on: 2024, 3, 15, timeZone: ny)
        XCTAssertEqual(age, BirthdayAge(value: 1, unit: .months))
    }

    func testHistoricalTimeZoneTransitionDoesNotSkipADay() {
        // Samoa (Pacific/Apia) crossed the date line at the end of 2011, so local
        // Dec 30 2011 never existed there. Reconstructing the birthday as a local
        // instant would normalize it to Dec 31 and later read as 11 months; the
        // UTC date-only arithmetic must still give exactly one year.
        let apiaZone = TimeZone(identifier: "Pacific/Apia")!
        var apia = Calendar(identifier: .gregorian)
        apia.timeZone = apiaZone
        let now = apia.date(from: DateComponents(year: 2012, month: 12, day: 30, hour: 12))!

        let result = AgeCalculator.age(
            for: StoredBirthday(year: 2011, month: 12, day: 30),
            asOf: now,
            timeZone: apiaZone
        )
        XCTAssertEqual(result, BirthdayAge(value: 1, unit: .years))
    }

    func testInvalidBirthdayClampsToZeroMonths() {
        // Manually built impossible days (month 13, Feb 29 in a non-leap year)
        // must be treated as 0 months rather than silently normalized.
        XCTAssertEqual(
            AgeCalculator.age(for: StoredBirthday(year: 2024, month: 13, day: 1),
                              asOf: noon(2026, 1, 1, in: utc), timeZone: utc),
            BirthdayAge(value: 0, unit: .months)
        )
        XCTAssertEqual(
            AgeCalculator.age(for: StoredBirthday(year: 2023, month: 2, day: 29),
                              asOf: noon(2026, 1, 1, in: utc), timeZone: utc),
            BirthdayAge(value: 0, unit: .months)
        )
    }

    func testPreferredCalendarDoesNotAffectResult() {
        // The calculator always works in Gregorian. Capturing a birthday through
        // a Buddhist calendar (year 2567) still ages as Gregorian 2024.
        var buddhist = Calendar(identifier: .buddhist)
        buddhist.timeZone = utc
        let instant = buddhist.date(from: DateComponents(year: 2567, month: 3, day: 9))!
        let born = StoredBirthday(date: instant, timeZone: utc)!
        XCTAssertEqual(born, StoredBirthday(year: 2024, month: 3, day: 9))

        let age = age(born: born, on: 2026, 3, 9)
        XCTAssertEqual(age, BirthdayAge(value: 2, unit: .years))
    }

    // MARK: - Captions and accessibility

    func testUnitLabelSingularAndPlural() {
        XCTAssertEqual(BirthdayAge(value: 1, unit: .months).unitLabel, "MONTH OLD!")
        XCTAssertEqual(BirthdayAge(value: 0, unit: .months).unitLabel, "MONTHS OLD!")
        XCTAssertEqual(BirthdayAge(value: 2, unit: .months).unitLabel, "MONTHS OLD!")
        XCTAssertEqual(BirthdayAge(value: 1, unit: .years).unitLabel, "YEAR OLD!")
        XCTAssertEqual(BirthdayAge(value: 3, unit: .years).unitLabel, "YEARS OLD!")
    }

    func testAccessibleDescription() {
        XCTAssertEqual(BirthdayAge(value: 1, unit: .months).accessibleDescription, "1 month old")
        XCTAssertEqual(BirthdayAge(value: 5, unit: .months).accessibleDescription, "5 months old")
        XCTAssertEqual(BirthdayAge(value: 1, unit: .years).accessibleDescription, "1 year old")
        XCTAssertEqual(BirthdayAge(value: 4, unit: .years).accessibleDescription, "4 years old")
    }
}
