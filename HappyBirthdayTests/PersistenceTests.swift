import XCTest
@testable import HappyBirthday

/// Isolated persistence tests. Each test gets a fresh `UserDefaults` suite and a
/// unique temporary directory, so nothing here touches real user app data.
final class DetailsPersistenceTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var directory: URL!

    private func makePersistence() -> DetailsPersistence {
        DetailsPersistence(
            defaults: defaults,
            photoFileURL: directory.appendingPathComponent("birthday-photo.jpg")
        )
    }

    override func setUp() {
        super.setUp()
        suiteName = "DetailsPersistenceTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(suiteName, isDirectory: true)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directory)
        defaults = nil
        directory = nil
        suiteName = nil
        super.tearDown()
    }

    func testFreshStateIsEmpty() {
        let persistence = makePersistence()
        XCTAssertEqual(persistence.loadName(), "")
        XCTAssertNil(persistence.loadBirthday())
        XCTAssertNil(persistence.loadPhotoData())
    }

    func testNameRoundTrip() {
        makePersistence().save(name: "Ada")
        // A second instance mirrors a fresh launch reading the same storage.
        XCTAssertEqual(makePersistence().loadName(), "Ada")
    }

    func testBirthdayRoundTrip() {
        let birthday = StoredBirthday(year: 2024, month: 3, day: 9)
        makePersistence().save(birthday: birthday)
        XCTAssertEqual(makePersistence().loadBirthday(), birthday)
    }

    func testPhotoRoundTrip() throws {
        let data = Data([0x01, 0x02, 0x03, 0x04])
        try makePersistence().savePhoto(data: data)
        XCTAssertEqual(makePersistence().loadPhotoData(), data)
    }

    func testEditsOverwritePreviousValues() throws {
        let first = makePersistence()
        first.save(name: "Ada")
        first.save(birthday: StoredBirthday(year: 2020, month: 1, day: 1))
        try first.savePhoto(data: Data([0x01]))

        let second = makePersistence()
        second.save(name: "Grace")
        second.save(birthday: StoredBirthday(year: 2024, month: 3, day: 9))
        try second.savePhoto(data: Data([0x02, 0x03]))

        let reloaded = makePersistence()
        XCTAssertEqual(reloaded.loadName(), "Grace")
        XCTAssertEqual(reloaded.loadBirthday(), StoredBirthday(year: 2024, month: 3, day: 9))
        XCTAssertEqual(reloaded.loadPhotoData(), Data([0x02, 0x03]))
    }

    func testRemovingBirthdayClearsIt() {
        let persistence = makePersistence()
        persistence.save(birthday: StoredBirthday(year: 2024, month: 3, day: 9))
        persistence.save(birthday: nil)
        XCTAssertNil(makePersistence().loadBirthday())
    }

    func testRemovingPhotoClearsIt() throws {
        let persistence = makePersistence()
        try persistence.savePhoto(data: Data([0x09]))
        try persistence.removePhoto()
        XCTAssertNil(makePersistence().loadPhotoData())
    }

    func testRemovingPhotoWhenNoneExistsDoesNotThrow() {
        XCTAssertNoThrow(try makePersistence().removePhoto())
    }

    func testCorruptBirthdayIsTreatedAsMissingWithoutLosingName() {
        let persistence = makePersistence()
        persistence.save(name: "Ada")
        // Write garbage into the birthday key, as a format change or partial
        // write might leave behind.
        defaults.set(Data([0xFF, 0x00, 0xAB]), forKey: DetailsPersistence.Key.birthday)

        let reloaded = makePersistence()
        XCTAssertNil(reloaded.loadBirthday())
        XCTAssertEqual(reloaded.loadName(), "Ada", "A corrupt birthday must not discard the name.")
    }

    func testImpossibleStoredBirthdayIsTreatedAsMissing() {
        let persistence = makePersistence()
        persistence.save(name: "Ada")
        // Well-formed JSON, but an impossible day (Feb 29 in a non-leap year).
        // It must decode to "no birthday" rather than a normalized Mar 1.
        let impossible = #"{"year":2023,"month":2,"day":29}"#.data(using: .utf8)!
        defaults.set(impossible, forKey: DetailsPersistence.Key.birthday)

        let reloaded = makePersistence()
        XCTAssertNil(reloaded.loadBirthday())
        XCTAssertEqual(reloaded.loadName(), "Ada")
    }

    func testMissingPhotoFileReturnsNilWithoutLosingDetails() throws {
        let persistence = makePersistence()
        persistence.save(name: "Ada")
        persistence.save(birthday: StoredBirthday(year: 2024, month: 3, day: 9))
        try persistence.savePhoto(data: Data([0x01, 0x02]))

        // Simulate the photo file disappearing underneath us.
        try FileManager.default.removeItem(at: directory.appendingPathComponent("birthday-photo.jpg"))

        let reloaded = makePersistence()
        XCTAssertNil(reloaded.loadPhotoData())
        XCTAssertEqual(reloaded.loadName(), "Ada")
        XCTAssertEqual(reloaded.loadBirthday(), StoredBirthday(year: 2024, month: 3, day: 9))
    }
}

/// Verifies the Gregorian calendar-day semantics that keep a chosen birthday
/// stable across reloads, device time-zone changes, and preferred-calendar
/// changes.
final class StoredBirthdayTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!
    private let tokyo = TimeZone(identifier: "Asia/Tokyo")!
    private let la = TimeZone(identifier: "America/Los_Angeles")!

    private func day(of date: Date, in timeZone: TimeZone) -> [Int?] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return [components.year, components.month, components.day]
    }

    func testCapturesTheGregorianDayOfAnInstant() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = tokyo
        let instant = calendar.date(from: DateComponents(year: 2024, month: 3, day: 9, hour: 8))!
        let stored = try XCTUnwrap(StoredBirthday(date: instant, timeZone: tokyo))
        XCTAssertEqual(stored, StoredBirthday(year: 2024, month: 3, day: 9))
    }

    /// The decisive calendar-independence case: a `Date` created through a
    /// Buddhist calendar (year 2567) must still be captured as its Gregorian
    /// year (2024), never the preferred-calendar year.
    func testCapturesGregorianYearRegardlessOfPreferredCalendar() throws {
        var buddhist = Calendar(identifier: .buddhist)
        buddhist.timeZone = utc
        let instant = buddhist.date(from: DateComponents(year: 2567, month: 3, day: 9))!

        let stored = try XCTUnwrap(StoredBirthday(date: instant, timeZone: utc))
        XCTAssertEqual(stored, StoredBirthday(year: 2024, month: 3, day: 9),
                       "The Gregorian year must be stored, not the preferred-calendar year.")
    }

    func testReconstructedDateReportsTheStoredGregorianDay() throws {
        let date = try XCTUnwrap(StoredBirthday(year: 2024, month: 3, day: 9).date(timeZone: la))
        XCTAssertEqual(day(of: date, in: la), [2024, 3, 9])
    }

    func testDayIsStableWhenDeviceTimeZoneChanges() throws {
        // A just-after-midnight instant whose day differs from the day the
        // *instant* would report in a western time zone. Storing components, not
        // the instant, is what keeps the day from shifting.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = tokyo
        let instant = calendar.date(from: DateComponents(year: 2024, month: 3, day: 9, hour: 0, minute: 30))!

        // Chosen while the device is in Tokyo.
        let stored = try XCTUnwrap(StoredBirthday(date: instant, timeZone: tokyo))
        XCTAssertEqual(stored, StoredBirthday(year: 2024, month: 3, day: 9))

        // Read back later while the device is in Los Angeles.
        let reconstructed = try XCTUnwrap(stored.date(timeZone: la))
        XCTAssertEqual(day(of: reconstructed, in: la), [2024, 3, 9])
    }

    func testLeapDayRoundTripsAcrossTimeZones() throws {
        let stored = StoredBirthday(year: 2024, month: 2, day: 29)
        XCTAssertTrue(StoredBirthday.isValid(year: 2024, month: 2, day: 29))

        let inTokyo = try XCTUnwrap(stored.date(timeZone: tokyo))
        XCTAssertEqual(day(of: inTokyo, in: tokyo), [2024, 2, 29])

        let inLA = try XCTUnwrap(stored.date(timeZone: la))
        XCTAssertEqual(day(of: inLA, in: la), [2024, 2, 29])
    }

    func testImpossibleDaysAreRejected() {
        // Feb 29 in a non-leap year and an out-of-range month must not be
        // silently normalized into a neighbouring real date.
        XCTAssertFalse(StoredBirthday.isValid(year: 2023, month: 2, day: 29))
        XCTAssertFalse(StoredBirthday.isValid(year: 2024, month: 13, day: 1))
        XCTAssertNil(StoredBirthday(year: 2023, month: 2, day: 29).date())
    }

    func testDecodingImpossibleDayFails() {
        let leapInNonLeapYear = #"{"year":2023,"month":2,"day":29}"#.data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode(StoredBirthday.self, from: leapInNonLeapYear))

        let outOfRangeMonth = #"{"year":2024,"month":13,"day":1}"#.data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode(StoredBirthday.self, from: outOfRangeMonth))
    }
}
