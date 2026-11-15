import XCTest
import SwiftUI
import UIKit
import Combine
@testable import HappyBirthday

/// Deterministic coverage for theme selection and the presentation model's
/// lifecycle. The random draw is exercised through an injected generator rather
/// than probabilistically.
final class BirthdayThemeTests: XCTestCase {
    /// A deterministic, well-distributed generator (SplitMix64) seeded by the
    /// test, so the random draw is reproducible without being probabilistic.
    /// A constant generator is deliberately avoided: it can trap
    /// `randomElement(using:)` in its rejection-sampling loop.
    private struct SplitMix64: RandomNumberGenerator {
        private var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    func testThreeDistinctThemesExist() {
        XCTAssertEqual(Set(BirthdayTheme.allCases).count, 3)
    }

    func testInjectedGeneratorMakesTheDrawDeterministic() {
        // The same seed must always pick the same theme, and the mapping must
        // cover more than one option across seeds.
        var first = SplitMix64(seed: 42)
        var alsoFirst = SplitMix64(seed: 42)
        XCTAssertEqual(
            BirthdayTheme.random(using: &first),
            BirthdayTheme.random(using: &alsoFirst)
        )

        var drawn: Set<BirthdayTheme> = []
        for seed in UInt64(0)..<30 {
            var generator = SplitMix64(seed: seed)
            drawn.insert(BirthdayTheme.random(using: &generator))
        }
        XCTAssertGreaterThan(drawn.count, 1, "The draw should not be stuck on a single theme.")
    }

    func testEachThemeHasDistinctAssetNames() {
        let backgrounds = Set(BirthdayTheme.allCases.map(\.backgroundAssetName))
        let placeholders = Set(BirthdayTheme.allCases.map(\.placeholderAssetName))
        XCTAssertEqual(backgrounds.count, 3)
        XCTAssertEqual(placeholders.count, 3)

        XCTAssertEqual(BirthdayTheme.fox.backgroundAssetName, "birthday-fox-background")
        XCTAssertEqual(BirthdayTheme.elephant.backgroundAssetName, "birthday-elephant-background")
        XCTAssertEqual(BirthdayTheme.pelican.backgroundAssetName, "birthday-pelican-background")
    }

    func testEachThemeMapsToItsMatchingCameraArtwork() {
        // The camera control is colour-matched to the animal: fox→green,
        // elephant→yellow, pelican→blue, and the three are distinct.
        XCTAssertEqual(BirthdayTheme.fox.cameraAssetName, "camera-green")
        XCTAssertEqual(BirthdayTheme.elephant.cameraAssetName, "camera-yellow")
        XCTAssertEqual(BirthdayTheme.pelican.cameraAssetName, "camera-blue")
        XCTAssertEqual(Set(BirthdayTheme.allCases.map(\.cameraAssetName)).count, 3)
    }

    func testPresentationProviderOverrideRequiresBothFlags() {
        // The theme override only applies when --uitest is present too, so it can
        // never affect the normal app.
        XCTAssertEqual(
            BirthdayTheme.uiTestOverride(arguments: ["--uitest", "--uitest-theme", "pelican"]),
            .pelican
        )
        XCTAssertEqual(
            BirthdayTheme.uiTestOverride(arguments: ["--uitest", "--uitest-theme", "fox"]),
            .fox
        )
        // Missing --uitest, unknown theme, or missing value all yield nil.
        XCTAssertNil(BirthdayTheme.uiTestOverride(arguments: ["--uitest-theme", "pelican"]))
        XCTAssertNil(BirthdayTheme.uiTestOverride(arguments: ["--uitest", "--uitest-theme", "giraffe"]))
        XCTAssertNil(BirthdayTheme.uiTestOverride(arguments: ["--uitest", "--uitest-theme"]))
        XCTAssertNil(BirthdayTheme.uiTestOverride(arguments: ["--uitest"]))
    }

    // MARK: - Presentation model lifecycle

    func testModelRefreshesReferenceDateButKeepsThemeOnDayChange() {
        let model = BirthdayScreenModel(theme: .elephant)
        let before = model.referenceDate

        let refreshed = expectation(description: "referenceDate refreshes")
        let cancellable = model.objectWillChange
            .sink { _ in refreshed.fulfill() }

        // A day-change notification must refresh the reference date so the age
        // stays current, without reshuffling the retained theme.
        NotificationCenter.default.post(name: .NSCalendarDayChanged, object: nil)
        wait(for: [refreshed], timeout: 2)
        cancellable.cancel()

        XCTAssertGreaterThanOrEqual(model.referenceDate, before)
        XCTAssertEqual(model.theme, .elephant, "The drawn theme must not change during the presentation.")
    }

    func testModelDerivesAgeFromStoredBirthday() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let reference = calendar.date(from: DateComponents(year: 2026, month: 3, day: 9, hour: 12))!
        let model = BirthdayScreenModel(theme: .fox, referenceDate: reference)

        XCTAssertEqual(
            model.age(for: StoredBirthday(year: 2025, month: 3, day: 9)),
            BirthdayAge(value: 1, unit: .years)
        )
        XCTAssertNil(model.age(for: nil))
    }
}

/// Verifies every piece of birthday-screen artwork is actually bundled, so a
/// missing or mis-named resource fails the build's test run rather than
/// silently rendering nothing.
final class BirthdayAssetTests: XCTestCase {
    func testAllRequiredAssetsAreBundled() {
        for name in BirthdayAsset.allRequired {
            XCTAssertNotNil(UIImage(named: name), "Missing bundled asset: \(name)")
        }
    }
}
