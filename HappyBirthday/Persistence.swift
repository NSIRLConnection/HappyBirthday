import Foundation

/// A birthday expressed as a **Gregorian** calendar day (year / month / day)
/// rather than an absolute instant.
///
/// Both capture and reconstruction always use a canonical Gregorian calendar,
/// independent of the user's *preferred* calendar. If conversion used
/// `Calendar.current`, a device set to the Buddhist or Japanese calendar would
/// record a different year (e.g. 2567) and later reinterpret it as Gregorian,
/// producing a far-future birthday. Pinning to Gregorian keeps the stored
/// numbers meaning the same thing on every device.
///
/// Persisting the day — not a `Date` — also keeps the chosen day stable across
/// relaunches and device time-zone changes, because the day label is rebuilt
/// from the stored components rather than re-derived from a moving instant.
struct StoredBirthday: Codable, Equatable {
    let year: Int
    let month: Int
    let day: Int

    enum CodingKeys: String, CodingKey {
        case year, month, day
    }

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// Capture the Gregorian calendar day that `date` falls on in `timeZone`.
    /// Fails if the instant somehow has no day components or resolves to an
    /// impossible day.
    init?(date: Date, timeZone: TimeZone = .current) {
        let components = Self.gregorianCalendar(timeZone: timeZone)
            .dateComponents([.year, .month, .day], from: date)
        guard let year = components.year,
              let month = components.month,
              let day = components.day,
              Self.isValid(year: year, month: month, day: day) else { return nil }
        self.year = year
        self.month = month
        self.day = day
    }

    /// Reject impossible days (e.g. Feb 29 in a non-leap year, month 13) when
    /// decoding persisted data, so a corrupt or out-of-range value is treated as
    /// "no birthday" rather than being silently normalized into a real date.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let year = try container.decode(Int.self, forKey: .year)
        let month = try container.decode(Int.self, forKey: .month)
        let day = try container.decode(Int.self, forKey: .day)
        guard Self.isValid(year: year, month: month, day: day) else {
            throw DecodingError.dataCorruptedError(
                forKey: .day,
                in: container,
                debugDescription: "Impossible calendar day \(year)-\(month)-\(day)."
            )
        }
        self.year = year
        self.month = month
        self.day = day
    }

    /// Rebuild a concrete `Date` for the stored day at noon in `timeZone`.
    ///
    /// Reconstruction is always Gregorian, so the day label matches what was
    /// stored. Noon is used only to avoid a spring-forward DST gap where
    /// midnight may not exist; it does not, on its own, guarantee the same day
    /// under an arbitrary time zone — that guarantee comes from rebuilding from
    /// the stored components rather than from a fixed instant. Returns `nil` for
    /// an impossible day instead of normalizing it.
    func date(timeZone: TimeZone = .current) -> Date? {
        guard Self.isValid(year: year, month: month, day: day) else { return nil }
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        return Self.gregorianCalendar(timeZone: timeZone).date(from: components)
    }

    private static func gregorianCalendar(timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    /// True only if `year/month/day` is a real Gregorian date. A lenient
    /// calendar would turn month 13 or Feb 30 into a neighbouring date; we catch
    /// that by requiring the components to survive a round trip unchanged.
    static func isValid(year: Int, month: Int, day: Int) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        guard let date = calendar.date(from: components) else { return false }
        let roundTrip = calendar.dateComponents([.year, .month, .day], from: date)
        return roundTrip.year == year && roundTrip.month == month && roundTrip.day == day
    }
}

/// Reads and writes the editable details.
///
/// Name and birthday are tiny and live in `UserDefaults`; the photo is stored
/// as a JPEG file in Application Support so a large blob never bloats defaults.
/// Both storage locations are injected so tests can use an isolated suite and a
/// temporary directory without touching real user data.
struct DetailsPersistence {
    enum Key {
        static let name = "details.name"
        static let birthday = "details.birthday"
    }

    private let defaults: UserDefaults
    private let photoFileURL: URL
    private let fileManager: FileManager

    init(defaults: UserDefaults, photoFileURL: URL, fileManager: FileManager = .default) {
        self.defaults = defaults
        self.photoFileURL = photoFileURL
        self.fileManager = fileManager
    }

    // MARK: - Name

    func loadName() -> String {
        defaults.string(forKey: Key.name) ?? ""
    }

    func save(name: String) {
        defaults.set(name, forKey: Key.name)
    }

    // MARK: - Birthday

    func loadBirthday() -> StoredBirthday? {
        guard let data = defaults.data(forKey: Key.birthday) else { return nil }
        // Corrupt or outdated data is treated as "no birthday" rather than
        // crashing or discarding the rest of the saved details.
        return try? JSONDecoder().decode(StoredBirthday.self, from: data)
    }

    func save(birthday: StoredBirthday?) {
        guard let birthday else {
            defaults.removeObject(forKey: Key.birthday)
            return
        }
        guard let data = try? JSONEncoder().encode(birthday) else { return }
        defaults.set(data, forKey: Key.birthday)
    }

    // MARK: - Photo

    func loadPhotoData() -> Data? {
        guard fileManager.fileExists(atPath: photoFileURL.path) else { return nil }
        return try? Data(contentsOf: photoFileURL)
    }

    func savePhoto(data: Data) throws {
        try ensurePhotoDirectoryExists()
        // Atomic write so a failure mid-save never corrupts the existing photo.
        try data.write(to: photoFileURL, options: .atomic)
    }

    func removePhoto() throws {
        guard fileManager.fileExists(atPath: photoFileURL.path) else { return }
        try fileManager.removeItem(at: photoFileURL)
    }

    private func ensurePhotoDirectoryExists() throws {
        let directory = photoFileURL.deletingLastPathComponent()
        guard !fileManager.fileExists(atPath: directory.path) else { return }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }
}

extension DetailsPersistence {
    /// The production store: standard defaults plus a photo file in Application
    /// Support.
    static func makeDefault() -> DetailsPersistence {
        let photoURL = applicationSupportDirectory()
            .appendingPathComponent("birthday-photo.jpg")
        return DetailsPersistence(defaults: .standard, photoFileURL: photoURL)
    }

    private static func applicationSupportDirectory() -> URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
    }
}
