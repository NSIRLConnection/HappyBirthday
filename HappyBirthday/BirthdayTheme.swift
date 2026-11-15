import SwiftUI

/// One of the three birthday-screen visual options (fox / elephant / pelican).
///
/// Each entry to the birthday screen draws one of these uniformly at random and
/// retains it for the whole presentation. The enum carries the theme's flat
/// background colour and the names of its exported artwork in the asset catalog.
enum BirthdayTheme: String, CaseIterable, Equatable {
    case fox
    case elephant
    case pelican

    /// The flat colour behind the illustration (fills the whole screen).
    var backgroundColor: Color {
        switch self {
        case .fox:      return Color(hex: 0xC5E8DF)
        case .elephant: return Color(hex: 0xFEEFCB)
        case .pelican:  return Color(hex: 0xDAF1F6)
        }
    }

    /// The bottom-pinned illustration for this theme (transparent PNG at 2x).
    var backgroundAssetName: String { "birthday-\(rawValue)-background" }

    /// The complete baby placeholder: a 229pt ringed circle (ring + face) shown
    /// when there is no photo, and whose ring frames the photo when there is one.
    var placeholderAssetName: String { "birthday-baby-\(rawValue)" }

    /// The theme-matched camera control artwork (white camera + plus) that sits
    /// on the photo ring. Each theme uses the colour that matches its animal.
    var cameraAssetName: String {
        switch self {
        case .fox:      return BirthdayAsset.cameraGreen
        case .elephant: return BirthdayAsset.cameraYellow
        case .pelican:  return BirthdayAsset.cameraBlue
        }
    }

    // MARK: - Shared tokens

    /// Title and unit-caption colour, shared across the three themes (#394562).
    static let titleColor = Color(hex: 0x394562)

    // MARK: - Random draw

    /// Draw a theme uniformly at random using an injectable generator, so tests
    /// can make the choice deterministic instead of probabilistic.
    static func random(using generator: inout some RandomNumberGenerator) -> BirthdayTheme {
        // `allCases` is never empty, so the force-unwrap cannot fail.
        allCases.randomElement(using: &generator)!
    }

    static func random() -> BirthdayTheme {
        var generator = SystemRandomNumberGenerator()
        return random(using: &generator)
    }

    /// The provider the details screen uses when presenting the birthday screen.
    /// A debug-only launch argument can pin the theme for repeatable design
    /// checks; production always draws at random.
    static func presentationProvider() -> () -> BirthdayTheme {
        #if DEBUG
        if let forced = uiTestOverride() {
            return { forced }
        }
        #endif
        return { random() }
    }

    #if DEBUG
    /// Reads `--uitest-theme <fox|elephant|pelican>`, but only when `--uitest`
    /// is also present, so the override can never affect the normal app or the
    /// real store. Strictly for UI-test and screenshot fixtures.
    static func uiTestOverride(arguments: [String] = ProcessInfo.processInfo.arguments) -> BirthdayTheme? {
        guard arguments.contains("--uitest"),
              let index = arguments.firstIndex(of: "--uitest-theme"),
              arguments.indices.contains(index + 1) else { return nil }
        return BirthdayTheme(rawValue: arguments[index + 1])
    }
    #endif
}

/// Names of the exported birthday-screen artwork in the asset catalog, kept in
/// one place so the view and the asset-presence test cannot drift apart.
enum BirthdayAsset {
    static let swirlLeft = "birthday-swirl-left"
    static let swirlRight = "birthday-swirl-right"
    static let logo = "nanit-logo"
    static let closeArrow = "birthday-close-arrow"

    // The theme-matched camera controls (white camera + plus on the ring),
    // mapped per theme in `BirthdayTheme.cameraAssetName`.
    static let cameraGreen = "camera-green"
    static let cameraBlue = "camera-blue"
    static let cameraYellow = "camera-yellow"

    static func digit(_ character: Character) -> String { "birthday-digit-\(character)" }

    /// Every asset the birthday screen requires at runtime; the test asserts all
    /// of these are bundled.
    static let allRequired: [String] = {
        var names = [
            "birthday-fox-background",
            "birthday-elephant-background",
            "birthday-pelican-background",
            "birthday-baby-fox",
            "birthday-baby-elephant",
            "birthday-baby-pelican",
            swirlLeft, swirlRight, logo, closeArrow,
            cameraGreen, cameraBlue, cameraYellow,
        ]
        names += (0...9).map { "birthday-digit-\($0)" }
        return names
    }()
}

extension Color {
    /// Builds a colour from a 24-bit RGB hex literal (e.g. `0xC5E8DF`).
    init(hex: UInt32) {
        let red = Double((hex >> 16) & 0xFF) / 255
        let green = Double((hex >> 8) & 0xFF) / 255
        let blue = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: 1)
    }
}
