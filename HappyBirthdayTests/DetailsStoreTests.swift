import XCTest
import UIKit
import CoreGraphics
@testable import HappyBirthday

/// Exercises the store's behaviour against isolated storage: loading a fresh
/// state, round-tripping each detail through a simulated relaunch, and the
/// failure handling that must never discard previously saved data.
final class DetailsStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var directory: URL!

    private func makePersistence() -> DetailsPersistence {
        DetailsPersistence(
            defaults: defaults,
            photoFileURL: directory.appendingPathComponent("birthday-photo.jpg")
        )
    }

    private func makeImage(_ color: UIColor = .systemTeal,
                           size: CGSize = CGSize(width: 40, height: 30)) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    /// Averages an image down to a single pixel so tests can tell one solid
    /// colour from another after a lossy JPEG round trip.
    private func dominantColor(of image: UIImage) -> (r: Int, g: Int, b: Int)? {
        guard let cgImage = image.cgImage else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return (Int(pixel[0]), Int(pixel[1]), Int(pixel[2]))
    }

    override func setUp() {
        super.setUp()
        suiteName = "DetailsStoreTests.\(UUID().uuidString)"
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

    func testFreshStoreIsEmptyAndNotReady() {
        let store = DetailsStore(persistence: makePersistence())
        XCTAssertEqual(store.name, "")
        XCTAssertNil(store.birthday)
        XCTAssertNil(store.image)
        XCTAssertFalse(store.isReadyToShowBirthday)
    }

    func testNamePersistsAcrossReload() {
        let store = DetailsStore(persistence: makePersistence())
        store.name = "Ada"

        let reloaded = DetailsStore(persistence: makePersistence())
        XCTAssertEqual(reloaded.name, "Ada")
    }

    func testSelectingBirthdayPersistsTheChosenDay() {
        let store = DetailsStore(persistence: makePersistence())
        store.name = "Ada"
        let chosen = DateComponents(calendar: .current, year: 2024, month: 3, day: 9).date!
        store.selectBirthday(chosen)

        XCTAssertTrue(store.isReadyToShowBirthday)

        let reloaded = DetailsStore(persistence: makePersistence())
        let components = Calendar.current.dateComponents([.year, .month, .day], from: reloaded.birthday!)
        XCTAssertEqual([components.year, components.month, components.day], [2024, 3, 9])
    }

    func testFreshStoreHasNoBirthdayUntilSelected() {
        // A fresh launch must not silently assume today's date.
        let store = DetailsStore(persistence: makePersistence())
        XCTAssertNil(store.birthday)
    }

    func testBirthdayDayUnchangedWhenTimeZoneChangesOnLiveStore() throws {
        func gregorian(_ identifier: String) -> Calendar {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: identifier)!
            return calendar
        }

        // The injected provider lets us simulate device travel without touching
        // system settings or leaking a global time-zone change between tests.
        var timeZone = TimeZone(identifier: "America/New_York")!
        let store = DetailsStore(persistence: makePersistence(), timeZoneProvider: { timeZone })

        // Choose March 9, 2024 at noon in New York.
        let chosen = gregorian("America/New_York")
            .date(from: DateComponents(year: 2024, month: 3, day: 9, hour: 12))!
        store.selectBirthday(chosen)
        XCTAssertEqual(store.storedBirthday, StoredBirthday(year: 2024, month: 3, day: 9))

        // Device travels to Tokyo while the store stays alive. The reconstructed
        // display/picker date must still read as March 9 in the new zone — the
        // fixed instant (NY noon) would otherwise land on March 10 there.
        timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let tokyo = gregorian("Asia/Tokyo")
        let seed = try XCTUnwrap(store.birthday)
        XCTAssertEqual(tokyo.dateComponents([.year, .month, .day], from: seed).day, 9)

        // Confirming the already-displayed date (Done without changing) must not
        // shift the stored day.
        store.selectBirthday(seed)
        XCTAssertEqual(store.storedBirthday, StoredBirthday(year: 2024, month: 3, day: 9))
        let after = try XCTUnwrap(store.birthday)
        XCTAssertEqual(tokyo.dateComponents([.year, .month, .day], from: after).day, 9)
    }

    func testPhotoPersistsAcrossReload() {
        let store = DetailsStore(persistence: makePersistence())
        store.setPhoto(makeImage())
        XCTAssertNotNil(store.image)
        XCTAssertNil(store.errorMessage)

        let reloaded = DetailsStore(persistence: makePersistence())
        XCTAssertNotNil(reloaded.image)
    }

    func testReplacingPhotoKeepsLatestImage() throws {
        let store = DetailsStore(persistence: makePersistence())
        store.setPhoto(makeImage(.red))
        store.setPhoto(makeImage(.green))

        let reloaded = DetailsStore(persistence: makePersistence())
        let color = try XCTUnwrap(reloaded.image.flatMap(dominantColor))
        XCTAssertGreaterThan(color.g, color.r,
                             "The reloaded photo should be the latest (green) image, not the first (red).")
        XCTAssertGreaterThan(color.g, color.b)
    }

    func testFailedSaveKeepsPreviousPhotoAndSurfacesError() throws {
        let photosDirectory = directory.appendingPathComponent("photos", isDirectory: true)
        let persistence = DetailsPersistence(
            defaults: defaults,
            photoFileURL: photosDirectory.appendingPathComponent("photo.jpg")
        )
        let store = DetailsStore(persistence: persistence)

        store.setPhoto(makeImage(.green))
        XCTAssertNil(store.errorMessage)
        let previous = try XCTUnwrap(store.image)

        // Replace the photos directory with a regular file so the next atomic
        // write to photos/photo.jpg cannot succeed.
        try FileManager.default.removeItem(at: photosDirectory)
        try Data([0x00]).write(to: photosDirectory)

        store.setPhoto(makeImage(.red))

        XCTAssertNotNil(store.errorMessage, "A failed save must surface an error.")
        XCTAssertTrue(store.image === previous, "A failed save must keep the previous photo.")
    }

    func testImportFailureKeepsExistingPhoto() {
        let store = DetailsStore(persistence: makePersistence())
        store.setPhoto(makeImage())
        let saved = store.image

        store.reportImportFailure()

        XCTAssertNotNil(store.errorMessage)
        XCTAssertTrue(store.image === saved, "A failed import must not clear the saved photo.")
    }

    func testEditingAllDetailsRoundTripsTogether() {
        let store = DetailsStore(persistence: makePersistence())
        store.name = "Grace Hopper"
        store.selectBirthday(DateComponents(calendar: .current, year: 2023, month: 12, day: 9).date!)
        store.setPhoto(makeImage())

        let reloaded = DetailsStore(persistence: makePersistence())
        XCTAssertEqual(reloaded.name, "Grace Hopper")
        let components = Calendar.current.dateComponents([.year, .month, .day], from: reloaded.birthday!)
        XCTAssertEqual([components.year, components.month, components.day], [2023, 12, 9])
        XCTAssertNotNil(reloaded.image)
        XCTAssertTrue(reloaded.isReadyToShowBirthday)
    }

    func testCorruptPhotoDataDoesNotLoseNameOrBirthday() throws {
        let persistence = makePersistence()
        persistence.save(name: "Ada")
        persistence.save(birthday: StoredBirthday(year: 2024, month: 3, day: 9))
        // Non-image bytes on disk: the image should fail to decode to nil while
        // the other details survive.
        try persistence.savePhoto(data: Data([0x00, 0x01, 0x02, 0x03]))

        let store = DetailsStore(persistence: persistence)
        XCTAssertNil(store.image)
        XCTAssertEqual(store.name, "Ada")
        XCTAssertNotNil(store.birthday)
    }
}
