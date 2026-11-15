import XCTest
import UIKit
import CoreGraphics
@testable import HappyBirthday

/// Covers the generation-based coordination that lets the newest photo selection
/// win and ensures a superseded or invalidated import neither overwrites the
/// existing photo nor surfaces a spurious error. The async library/camera UI is
/// exercised indirectly through the deterministic `beginImport` /
/// `applyImportResult` seam rather than through a real `PhotosPickerItem`.
@MainActor
final class PhotoSelectionTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var directory: URL!

    override func setUp() {
        super.setUp()
        suiteName = "PhotoSelectionTests.\(UUID().uuidString)"
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

    private func makeStore() -> DetailsStore {
        DetailsStore(persistence: DetailsPersistence(
            defaults: defaults,
            photoFileURL: directory.appendingPathComponent("photo.jpg")
        ))
    }

    private func makeImage(_ color: UIColor) -> UIImage {
        let size = CGSize(width: 24, height: 24)
        return UIGraphicsImageRenderer(size: size).image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    private func dominantColor(of image: UIImage) -> (r: Int, g: Int, b: Int)? {
        guard let cgImage = image.cgImage else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(
            data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return (Int(pixel[0]), Int(pixel[1]), Int(pixel[2]))
    }

    func testLatestSelectionWins() throws {
        let store = makeStore()
        let selection = PhotoSelection()

        // Two overlapping imports: the second supersedes the first.
        let first = selection.beginImport()
        let second = selection.beginImport()
        XCTAssertNotEqual(first, second)

        // The slower first import completes last but must be discarded.
        selection.applyImportResult(makeImage(.green), generation: second, into: store)
        selection.applyImportResult(makeImage(.red), generation: first, into: store)

        let color = try XCTUnwrap(store.image.flatMap(dominantColor))
        XCTAssertGreaterThan(color.g, color.r, "The newest (green) selection must win over the stale (red) one.")
        XCTAssertNil(store.errorMessage, "A superseded import is not a failure.")
        XCTAssertFalse(selection.isImporting)
    }

    func testInvalidateSuppressesLateCompletionAndError() {
        let store = makeStore()
        store.setPhoto(makeImage(.blue))
        let existing = store.image
        let selection = PhotoSelection()

        let token = selection.beginImport()
        XCTAssertTrue(selection.isImporting)

        // The owning screen closes (or hands off) before the import finishes.
        selection.invalidate()
        XCTAssertFalse(selection.isImporting)

        // A late success must not replace the photo…
        selection.applyImportResult(makeImage(.red), generation: token, into: store)
        XCTAssertTrue(store.image === existing, "An invalidated import must not overwrite the existing photo.")

        // …and a late failure must not surface an error alert.
        selection.applyImportResult(nil, generation: token, into: store)
        XCTAssertNil(store.errorMessage, "A cancelled import is not an import failure.")
    }

    func testCameraCaptureDefersSaveUntilDismissalThenSavesExactlyOnce() throws {
        let store = makeStore()
        let selection = PhotoSelection()

        // Capturing stages the image and begins dismissing the camera cover, but
        // must not save or error while the cover is still on screen.
        selection.stageCapture(makeImage(.red))
        XCTAssertNil(store.image, "A staged capture must not save before dismissal.")
        XCTAssertNil(store.errorMessage, "No error may be requested before dismissal.")
        XCTAssertFalse(selection.isImporting)

        // onDismiss commits exactly once.
        selection.commitStagedCapture(into: store)
        let color = try XCTUnwrap(store.image.flatMap(dominantColor))
        XCTAssertGreaterThan(color.r, color.g)

        // A repeated onDismiss (or spurious callback) must not re-apply the stale
        // staged capture over a subsequently changed photo.
        store.setPhoto(makeImage(.blue))
        selection.commitStagedCapture(into: store)
        let after = try XCTUnwrap(store.image.flatMap(dominantColor))
        XCTAssertGreaterThan(after.b, after.r, "Commit must not re-apply an already-committed capture.")
    }

    func testCameraCaptureSupersedesPendingLibraryImportImmediately() throws {
        let store = makeStore()
        let selection = PhotoSelection()

        // A library import is in flight when the user instead takes a photo.
        let pending = selection.beginImport()
        selection.stageCapture(makeImage(.red))

        // The pending library result is already stale and must be dropped, even
        // though the capture itself has not been persisted yet.
        selection.applyImportResult(makeImage(.green), generation: pending, into: store)
        XCTAssertNil(store.image, "A superseded library import must not save.")

        selection.commitStagedCapture(into: store)
        let color = try XCTUnwrap(store.image.flatMap(dominantColor))
        XCTAssertGreaterThan(color.r, color.g, "The camera capture must win over the superseded import.")
    }

    func testInvalidationDropsStagedCaptureAndCancelKeepsPreviousPhoto() {
        let store = makeStore()
        store.setPhoto(makeImage(.blue))
        let existing = store.image
        let selection = PhotoSelection()

        // Captured, then the screen is closed (invalidate) before the cover's
        // onDismiss commits: the staged capture must be dropped.
        selection.stageCapture(makeImage(.red))
        selection.invalidate()
        selection.commitStagedCapture(into: store)
        XCTAssertTrue(store.image === existing, "An invalidated staged capture must not apply.")
        XCTAssertNil(store.errorMessage)

        // A cancelled camera stages nothing, so its dismissal is a no-op that
        // keeps the previous photo.
        selection.commitStagedCapture(into: store)
        XCTAssertTrue(store.image === existing, "Cancelling the camera must keep the previous photo.")
        XCTAssertNil(store.errorMessage)
    }

    func testStagedCaptureFailedSaveSurfacesErrorOnlyAfterDismissal() throws {
        // Reuse the failed-save setup: a regular file where the photos directory
        // should be, so the atomic write cannot succeed.
        let photosDirectory = directory.appendingPathComponent("photos", isDirectory: true)
        let persistence = DetailsPersistence(
            defaults: defaults,
            photoFileURL: photosDirectory.appendingPathComponent("photo.jpg")
        )
        let store = DetailsStore(persistence: persistence)
        store.setPhoto(makeImage(.green))
        let previous = try XCTUnwrap(store.image)

        try FileManager.default.removeItem(at: photosDirectory)
        try Data([0x00]).write(to: photosDirectory)

        let selection = PhotoSelection()
        selection.stageCapture(makeImage(.red))
        XCTAssertNil(store.errorMessage, "The failure must not be surfaced before the cover dismisses.")

        selection.commitStagedCapture(into: store)
        XCTAssertNotNil(store.errorMessage, "A failed save must surface its error after dismissal.")
        XCTAssertTrue(store.image === previous, "A failed save must keep the previous photo.")
    }

    func testCurrentGenerationNilResultReportsFailureWithoutLosingPhoto() {
        let store = makeStore()
        store.setPhoto(makeImage(.blue))
        let existing = store.image
        let selection = PhotoSelection()

        let token = selection.beginImport()
        // A genuine decode failure on the current import surfaces an error while
        // keeping the previous photo.
        selection.applyImportResult(nil, generation: token, into: store)

        XCTAssertNotNil(store.errorMessage)
        XCTAssertTrue(store.image === existing, "A failed import must keep the previous photo.")
    }
}
