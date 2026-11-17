import SwiftUI
import UIKit

/// Reference geometry and style tokens for the birthday composition, kept in one
/// place so the live screen (`BirthdayView`) and the off-screen share renderer
/// (`BirthdayShareRenderer`) never drift apart on a constant.
enum BirthdayLayout {
    static let horizontalPadding: CGFloat = 24
    /// Outer diameter of the ringed placeholder (its full render bounds).
    static let referenceDiameter: CGFloat = 229
    /// The photo sits inside the 7pt ring: 229 − 2×7 = 215.
    static let photoInsetRatio: CGFloat = 215.0 / 229.0
    static let swirlSize = CGSize(width: 51.2, height: 44.53)
    static let digitHeight: CGFloat = 87.95
    /// The age row's natural (unscaled) height: the taller of the digit and swirl.
    static let ageRowHeight: CGFloat = 87.95
    static let swirlToDigitGap: CGFloat = 22
    static let logoSize = CGSize(width: 58.68, height: 19.63)
    static let photoToLogoGap: CGFloat = 15
    /// Reference distance from the logo's bottom to the physical screen bottom
    /// (the lower band reserved for the step-5 share button).
    static let logoBottomReference: CGFloat = 149.37

    /// The circle keeps a minimum 50pt horizontal margin on each side, never
    /// exceeds its reference ~229pt diameter, and leaves room on short screens. A
    /// transient zero/unmeasured geometry yields 0 rather than a negative frame.
    static func circleDiameter(width: CGFloat, height: CGFloat) -> CGFloat {
        max(0, min(referenceDiameter, width - 100, height * 0.45))
    }

    /// Horizontal space for content after the side padding, never negative.
    static func contentWidth(width: CGFloat) -> CGFloat {
        max(0, width - horizontalPadding * 2)
    }

    /// Keeps the logo's bottom ~149pt above the physical bottom (the reserved
    /// share band), while never letting it drop into the bottom safe area.
    static func logoBottomReserve(height: CGFloat, safeAreaBottom: CGFloat) -> CGFloat {
        max(logoBottomReference - safeAreaBottom, 24)
    }

    /// The single layout decision shared by the live screen (`BirthdayView`) and
    /// the off-screen share renderer, so they can never drift: fall back to the
    /// adaptive, non-clipping full-content layout when the design's fixed layered
    /// composition cannot hold everything — accessibility text sizes, a viewport
    /// too short to fit the complete fixed card (which otherwise clips the title
    /// off the top), or a wide/landscape viewport where a width-driven
    /// illustration would grow tall enough to cover the photo.
    static func prefersFullContentLayout(size: CGSize, dynamicTypeSize: DynamicTypeSize) -> Bool {
        dynamicTypeSize.isAccessibilitySize
            || size.height < 600
            || size.width > size.height
    }
}

/// The pure, content-only birthday composition: themed backdrop, bottom-pinned
/// illustration, header (title + age + unit), the child's photo in its ring, and
/// the Nanit logo — laid out deterministically from an EXPLICIT size with no
/// GeometryReader `@State` settling, so the same code drives both the live
/// layered screen and the off-screen share renderer identically (the renderer
/// has only a single layout pass).
///
/// No control (close, camera, share, spinner) is ever part of this composition.
/// The live screen injects its single camera control through `photoOverlay`; the
/// share renderer passes an empty overlay, so the exported image excludes every
/// control by construction rather than by hiding live views.
struct BirthdayContent<PhotoOverlay: View>: View {
    let size: CGSize
    let safeAreaBottom: CGFloat
    /// Margins to paint as themed content around the inset text/photo stack. The
    /// live screen leaves these zero (its real safe areas are handled by the
    /// hosting `GeometryReader`); the share renderer passes the captured insets so
    /// the export reproduces the full physical canvas — status-bar and
    /// home-indicator strips included — painted with the backdrop and bottom
    /// illustration rather than cropped away.
    var safeAreaInsets: EdgeInsets = EdgeInsets()
    let theme: BirthdayTheme
    let age: BirthdayAge
    let trimmedName: String
    let image: UIImage?
    /// Placed centred on the transparent photo slot of the foreground pass; it
    /// receives the resolved photo diameter so a control can track the ring.
    @ViewBuilder var photoOverlay: (CGFloat) -> PhotoOverlay

    var body: some View {
        let diameter = BirthdayLayout.circleDiameter(width: size.width, height: size.height)
        let contentWidth = BirthdayLayout.contentWidth(width: size.width)
        // Photo beneath the illustration; title/age/logo and the control slot
        // above it — the same layer order the design relies on.
        ZStack {
            theme.backgroundColor.ignoresSafeArea()
            skeleton(diameter: diameter, contentWidth: contentWidth, showPhoto: true, showText: false)
            BirthdayIllustration(theme: theme)
            skeleton(diameter: diameter, contentWidth: contentWidth, showPhoto: false, showText: true)
        }
        // Pin the composition to the explicit, finite size so no child can
        // enlarge it and the renderer gets bounded dimensions.
        .frame(width: size.width, height: size.height)
    }

    /// The shared layout skeleton. Both passes render every element (hidden ones
    /// via opacity) so the photo in the lower layer lines up exactly with its
    /// transparent slot in the upper layer.
    private func skeleton(diameter: CGFloat,
                          contentWidth: CGFloat,
                          showPhoto: Bool,
                          showText: Bool) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            BirthdayHeader(trimmedName: trimmedName, age: age,
                           availableWidth: contentWidth, decorative: !showText)
                .opacity(showText ? 1 : 0)
            Spacer(minLength: 20)

            Group {
                if showPhoto {
                    // Lower pass: the photo only, which sits beneath the art.
                    BirthdayPhoto(theme: theme, image: image, diameter: diameter)
                } else {
                    // Upper (foreground) pass: a transparent slot aligned with
                    // the photo below, carrying the injected control overlay.
                    Color.clear
                        .frame(width: diameter, height: diameter)
                        .overlay(alignment: .center) { photoOverlay(diameter) }
                }
            }

            Spacer().frame(height: BirthdayLayout.photoToLogoGap)
            BirthdayLogo().opacity(showText ? 1 : 0)
            Spacer().frame(height: BirthdayLayout.logoBottomReserve(height: size.height, safeAreaBottom: safeAreaBottom))
        }
        .padding(.horizontal, BirthdayLayout.horizontalPadding)
        // Inset the text/photo stack by the captured safe areas so it sits in the
        // same content rect as the live screen, while the backdrop and
        // illustration below fill the full canvas. Zero on the live screen.
        .padding(safeAreaInsets)
        .frame(width: size.width, height: size.height)
    }
}

// MARK: - Shared leaf components

/// The title, numeric age artwork, and unit caption folded into one spoken
/// phrase. The `decorative` (lower, photo) pass renders an identical but
/// accessibility-hidden header purely to reserve space for alignment, so exactly
/// one `birthdayAge` element is ever exposed.
struct BirthdayHeader: View {
    let trimmedName: String
    let age: BirthdayAge
    let availableWidth: CGFloat
    let decorative: Bool

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .title2) private var titleFontSize: CGFloat = 21
    @ScaledMetric(relativeTo: .title2) private var unitFontSize: CGFloat = 21

    private var titleString: String { "TODAY \(trimmedName) IS".uppercased() }
    private var accessibleAgeLabel: String {
        "Today \(trimmedName) is \(age.accessibleDescription)"
    }

    var body: some View {
        // At accessibility text sizes use the full available width so a long name
        // completes across two lines instead of truncating against the 226pt
        // reference cap the normal-size design relies on.
        let titleMaxWidth = dynamicTypeSize.isAccessibilitySize
            ? availableWidth
            : min(226, availableWidth)
        VStack(spacing: 0) {
            BirthdayTitle(text: titleString, fontSize: titleFontSize, maxWidth: titleMaxWidth)
            Spacer().frame(height: 13)
            BirthdayAgeRow(value: age.value, maxWidth: availableWidth)
            Spacer().frame(height: 14)
            BirthdayUnit(text: age.unitLabel, fontSize: unitFontSize)
        }
        .frame(maxWidth: .infinity)
        .modifier(HeaderAccessibility(decorative: decorative, label: accessibleAgeLabel))
    }
}

/// One `Text` wraps the complete title across up to two lines for a long name,
/// scaling down before it would overflow, rather than splitting the name out.
struct BirthdayTitle: View {
    let text: String
    let fontSize: CGFloat
    let maxWidth: CGFloat

    var body: some View {
        Text(text)
            .font(.system(size: fontSize, weight: .medium))
            .tracking(-0.4201)
            .foregroundStyle(BirthdayTheme.titleColor)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.6)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: maxWidth)
    }
}

struct BirthdayUnit: View {
    let text: String
    let fontSize: CGFloat

    var body: some View {
        Text(text)
            .font(.system(size: fontSize, weight: .medium))
            .tracking(-0.4201)
            .foregroundStyle(BirthdayTheme.titleColor)
            .multilineTextAlignment(.center)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }
}

/// The swirl-flanked numeric age built from the decorative digit artwork. It
/// scales uniformly to fit `maxWidth` using a deterministic intrinsic width read
/// from the bundled image sizes — not a GeometryReader/`@State` feedback loop —
/// so a single off-screen render pass lays it out correctly and a narrow screen
/// or a two-digit age shrinks the block instead of distorting or clipping it.
struct BirthdayAgeRow: View {
    let value: Int
    let maxWidth: CGFloat

    var body: some View {
        let characters = Array(String(value))
        let intrinsic = Self.intrinsicWidth(for: characters)
        // Only scale when both widths are positive, finite numbers; an unmeasured
        // target leaves the block at its natural size rather than collapsing it.
        let canScale = intrinsic > 0 && maxWidth > 0 && maxWidth.isFinite
        let scale = canScale ? min(1, maxWidth / intrinsic) : 1
        HStack(spacing: BirthdayLayout.swirlToDigitGap) {
            swirl(BirthdayAsset.swirlLeft)
            HStack(spacing: 2) {
                ForEach(characters.indices, id: \.self) { index in
                    Image(BirthdayAsset.digit(characters[index]))
                        .resizable()
                        .scaledToFit()
                        .frame(height: BirthdayLayout.digitHeight)
                }
            }
            swirl(BirthdayAsset.swirlRight)
        }
        .fixedSize()
        .scaleEffect(scale, anchor: .center)
        // Reserve exactly the scaled footprint so centring and the surrounding
        // spacers stay correct.
        .frame(width: intrinsic * scale, height: BirthdayLayout.ageRowHeight * scale)
    }

    private func swirl(_ name: String) -> some View {
        Image(name)
            .resizable()
            .scaledToFit()
            .frame(width: BirthdayLayout.swirlSize.width, height: BirthdayLayout.swirlSize.height)
    }

    /// The row's natural width: both fixed-size swirls, the two gaps, and each
    /// digit rendered at `digitHeight` keeping its intrinsic aspect ratio.
    static func intrinsicWidth(for characters: [Character]) -> CGFloat {
        let swirls = BirthdayLayout.swirlSize.width * 2 + BirthdayLayout.swirlToDigitGap * 2
        let digits = characters.reduce(CGFloat(0)) { $0 + digitWidth($1) }
            + CGFloat(max(0, characters.count - 1)) * 2
        return swirls + digits
    }

    static func digitWidth(_ character: Character) -> CGFloat {
        guard let image = UIImage(named: BirthdayAsset.digit(character)),
              image.size.height > 0 else {
            // Fall back to a square footprint if the glyph is somehow unavailable.
            return BirthdayLayout.digitHeight
        }
        return BirthdayLayout.digitHeight * image.size.width / image.size.height
    }
}

/// The complete ringed placeholder (ring + face) whose ring also frames a
/// selected photo, so no separate frame/colour is drawn. Read-only use of the
/// stored photo: rendering here never rewrites or removes it.
struct BirthdayPhoto: View {
    let theme: BirthdayTheme
    let image: UIImage?
    let diameter: CGFloat

    var body: some View {
        ZStack {
            Image(theme.placeholderAssetName)
                .resizable()
                .scaledToFit()
                .frame(width: diameter, height: diameter)

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: diameter * BirthdayLayout.photoInsetRatio,
                           height: diameter * BirthdayLayout.photoInsetRatio)
                    .clipShape(Circle())
            }
        }
        .frame(width: diameter, height: diameter)
        .accessibilityElement()
        .accessibilityLabel(image == nil ? "No photo yet" : "Birthday photo")
    }
}

struct BirthdayLogo: View {
    var body: some View {
        Image(BirthdayAsset.logo)
            .resizable()
            .scaledToFit()
            .frame(width: BirthdayLayout.logoSize.width, height: BirthdayLayout.logoSize.height)
            .accessibilityHidden(true)
    }
}

/// The bottom-pinned, width-driven full-bleed illustration. A dedicated reader
/// ignores the safe area FIRST, so it measures the actual canvas (physical
/// display, or the explicit render frame) rather than the inset content rect.
struct BirthdayIllustration: View {
    let theme: BirthdayTheme

    var body: some View {
        GeometryReader { canvas in
            let width = max(0, canvas.size.width)
            let height = max(0, canvas.size.height)
            // Width-driven full-bleed decoration: the art's pixels fill the canvas
            // width exactly, the height derived from the intrinsic aspect so
            // nothing is stretched. A zero width draws nothing.
            let drawHeight = width > 0 ? width * aspectRatio : 0
            Image(theme.backgroundAssetName)
                .resizable()
                .frame(width: width, height: drawHeight)
                // Pin into the EXPLICIT, finite canvas frame and clip, so the huge
                // intrinsic draw height never inflates layout; bottom alignment
                // crops overflow at the (transparent) top.
                .frame(width: width, height: height, alignment: .bottom)
                .clipped()
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Intrinsic height-to-width ratio of the current theme's illustration, read
    /// from the bundled image so the draw height stays exact without hard-coded
    /// pixels. Falls back to a square if the image is somehow unavailable.
    private var aspectRatio: CGFloat {
        guard let image = UIImage(named: theme.backgroundAssetName),
              image.size.width > 0 else { return 1 }
        return image.size.height / image.size.width
    }
}

/// Folds the title, numeric artwork, and unit into one spoken phrase for the
/// visible header, and makes the duplicate (decorative) header completely
/// invisible to accessibility — carrying no label or identifier — so exactly one
/// `birthdayAge` element is ever exposed.
struct HeaderAccessibility: ViewModifier {
    let decorative: Bool
    let label: String

    func body(content: Content) -> some View {
        if decorative {
            content.accessibilityHidden(true)
        } else {
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(label)
                .accessibilityIdentifier("birthdayAge")
        }
    }
}
