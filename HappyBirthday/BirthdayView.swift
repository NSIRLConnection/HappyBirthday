import SwiftUI
import UIKit

/// The celebratory birthday screen presented from the details screen.
///
/// Layout follows the supplied design and exported artwork: a centered,
/// two-line-capable title; the age number rendered from the decorative digit
/// assets and flanked by the swirl artwork; the singular/plural unit caption;
/// the child's photo framed by the theme's ringed placeholder; and the Nanit
/// logo — all above a bottom-pinned, aspect-preserving illustration. A top-left
/// close button returns to the details screen unchanged.
///
/// Layer order matters: the photo sits beneath the illustration (the animal and
/// foliage cross its lower edges), while the title, age, logo, and close button
/// sit above it.
struct BirthdayView: View {
    @ObservedObject var store: DetailsStore
    let onClose: () -> Void

    @StateObject private var model: BirthdayScreenModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .title2) private var titleFontSize: CGFloat = 21
    @ScaledMetric(relativeTo: .title2) private var unitFontSize: CGFloat = 21

    init(store: DetailsStore,
         themeProvider: @escaping () -> BirthdayTheme = BirthdayTheme.presentationProvider(),
         timeZoneProvider: @escaping () -> TimeZone = { .current },
         onClose: @escaping () -> Void) {
        self.store = store
        self.onClose = onClose
        // The autoclosure runs once per presentation, so the theme is drawn a
        // single time and retained for the model's lifetime.
        _model = StateObject(wrappedValue: BirthdayScreenModel(
            theme: themeProvider(),
            timeZoneProvider: timeZoneProvider
        ))
    }

    // MARK: - Reference geometry (375×667 frame)

    private let horizontalPadding: CGFloat = 24
    /// Outer diameter of the ringed placeholder (its full render bounds).
    private let referenceDiameter: CGFloat = 229
    /// The photo sits inside the 7pt ring: 229 − 2×7 = 215.
    private let photoInsetRatio: CGFloat = 215.0 / 229.0
    private let swirlSize = CGSize(width: 51.2, height: 44.53)
    private let digitHeight: CGFloat = 87.95
    private let swirlToDigitGap: CGFloat = 22
    private let logoSize = CGSize(width: 58.68, height: 19.63)
    private let photoToLogoGap: CGFloat = 15
    /// Reference distance from the logo's bottom to the physical screen bottom
    /// (the lower band reserved for the step-5 share button).
    private let logoBottomReference: CGFloat = 149.37

    private var theme: BirthdayTheme { model.theme }

    private var age: BirthdayAge {
        model.age(for: store.storedBirthday) ?? BirthdayAge(value: 0, unit: .months)
    }

    private var trimmedName: String {
        store.name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var titleString: String {
        "TODAY \(trimmedName) IS".uppercased()
    }

    private var accessibleAgeLabel: String {
        "Today \(trimmedName) is \(age.accessibleDescription)"
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                theme.backgroundColor
                    .ignoresSafeArea()

                if prefersScrollLayout(geo) {
                    illustration()
                    scrollLayout(in: geo)
                } else {
                    layeredLayout(in: geo)
                }

                closeButton
            }
        }
    }

    /// Fall back to a scrollable, single-stack layout when the design's fixed
    /// composition cannot hold the content: accessibility text sizes, or a short
    /// (e.g. landscape) height.
    private func prefersScrollLayout(_ geo: GeometryProxy) -> Bool {
        // Wide/landscape viewports (e.g. unfolded Duo) would let a width-sized
        // illustration grow tall enough to cover the photo in the fixed
        // composition, so fall back to the adaptive scroll layout where the age
        // and photo stay visible over the backdrop.
        dynamicTypeSize.isAccessibilitySize
            || geo.size.height < 600
            || geo.size.width > geo.size.height
    }

    // MARK: - Layered (design) layout

    private func layeredLayout(in geo: GeometryProxy) -> some View {
        let diameter = circleDiameter(for: geo)
        let contentWidth = contentWidth(for: geo)
        return ZStack {
            // Photo beneath the illustration…
            skeleton(in: geo, diameter: diameter, contentWidth: contentWidth,
                     showPhoto: true, showText: false)
            illustration()
            // …title, age, and logo above it.
            skeleton(in: geo, diameter: diameter, contentWidth: contentWidth,
                     showPhoto: false, showText: true)
        }
        // Pin the composition to the actual viewport so no child can enlarge it.
        .frame(width: geo.size.width, height: geo.size.height)
    }

    /// The shared layout skeleton. Both passes render every element (hidden ones
    /// via opacity) so the photo in the lower layer lines up exactly with its
    /// transparent slot in the upper layer.
    private func skeleton(in geo: GeometryProxy,
                          diameter: CGFloat,
                          contentWidth: CGFloat,
                          showPhoto: Bool,
                          showText: Bool) -> some View {
        VStack(spacing: 0) {
            // Two flexible spacers (here and below the header) split the space
            // above the circle, centering the header between the status bar and
            // the circle instead of top-anchoring it on tall devices.
            Spacer(minLength: 0)
            header(availableWidth: contentWidth, decorative: !showText)
                .opacity(showText ? 1 : 0)
            Spacer(minLength: 20)

            Group {
                if showPhoto {
                    photoView(diameter: diameter)
                } else {
                    Color.clear.frame(width: diameter, height: diameter)
                }
            }

            Spacer().frame(height: photoToLogoGap)
            // The logo is decorative and always hidden from accessibility (see
            // `logo`); only its visibility toggles between the two passes.
            logo
                .opacity(showText ? 1 : 0)

            Spacer().frame(height: logoBottomReserve(geo))
        }
        .padding(.horizontal, horizontalPadding)
        .frame(width: geo.size.width, height: geo.size.height)
    }

    // MARK: - Scroll (fallback) layout

    private func scrollLayout(in geo: GeometryProxy) -> some View {
        let diameter = circleDiameter(for: geo)
        let contentWidth = contentWidth(for: geo)
        return ScrollView {
            VStack(spacing: 0) {
                header(availableWidth: contentWidth, decorative: false)
                Spacer().frame(height: 28)
                photoView(diameter: diameter)
                Spacer().frame(height: photoToLogoGap)
                logo
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.top, 72)
            .padding(.bottom, 48)
            .frame(maxWidth: .infinity)
            .frame(minHeight: geo.size.height, alignment: .center)
        }
    }

    // MARK: - Illustration

    private func illustration() -> some View {
        // A dedicated reader that ignores the safe area FIRST, so it measures the
        // actual full-screen canvas (physical display) instead of the inset
        // content rect — this is what makes the backdrop reach the right/bottom
        // physical edges on folded Duo rather than ending at the safe-area edge.
        GeometryReader { canvas in
            let width = max(0, canvas.size.width)
            let height = max(0, canvas.size.height)
            // Width-driven, full-bleed decoration: the art's pixels fill the
            // canvas width exactly, with the height derived from the intrinsic
            // aspect ratio so nothing is stretched. A zero width draws nothing.
            let drawHeight = width > 0 ? width * backgroundAspectRatio : 0
            Image(theme.backgroundAssetName)
                .resizable()
                .frame(width: width, height: drawHeight)
                // Pin into the EXPLICIT, finite canvas frame and clip, so the
                // huge intrinsic draw height never inflates layout; bottom
                // alignment crops overflow at the (transparent) top.
                .frame(width: width, height: height, alignment: .bottom)
                .clipped()
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Intrinsic height-to-width ratio of the current theme's illustration, read
    /// from the bundled image so the full-bleed draw height stays exact without
    /// hard-coded pixel dimensions. Falls back to a square if the image is
    /// somehow unavailable.
    private var backgroundAspectRatio: CGFloat {
        guard let image = UIImage(named: theme.backgroundAssetName),
              image.size.width > 0 else { return 1 }
        return image.size.height / image.size.width
    }

    // MARK: - Header (title + age + unit)

    /// - Parameter decorative: the lower (photo) pass renders an identical but
    ///   hidden header purely to reserve space for alignment. It must expose no
    ///   age label or `birthdayAge` identifier, so only the single visible header
    ///   surfaces one combined spoken phrase to VoiceOver and UI tests.
    private func header(availableWidth: CGFloat, decorative: Bool) -> some View {
        // At accessibility text sizes use the full available width so a long
        // name completes across two lines instead of truncating against the
        // 226pt reference cap that the normal-size design relies on.
        let titleMaxWidth = dynamicTypeSize.isAccessibilitySize
            ? availableWidth
            : min(226, availableWidth)
        return VStack(spacing: 0) {
            titleText(maxWidth: titleMaxWidth)
            Spacer().frame(height: 13)
            ageRow(maxWidth: availableWidth)
            Spacer().frame(height: 14)
            unitText
        }
        .frame(maxWidth: .infinity)
        .modifier(HeaderAccessibility(decorative: decorative, label: accessibleAgeLabel))
    }

    private func titleText(maxWidth: CGFloat) -> some View {
        // One Text wraps the complete title across up to two lines for a long
        // name, scaling down before it would overflow, rather than splitting the
        // name into a separate label.
        Text(titleString)
            .font(.system(size: titleFontSize, weight: .medium))
            .tracking(-0.4201)
            .foregroundStyle(BirthdayTheme.titleColor)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.6)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: maxWidth)
    }

    private func ageRow(maxWidth: CGFloat) -> some View {
        HStack(spacing: swirlToDigitGap) {
            Image(BirthdayAsset.swirlLeft)
                .resizable()
                .scaledToFit()
                .frame(width: swirlSize.width, height: swirlSize.height)
            digits
            Image(BirthdayAsset.swirlRight)
                .resizable()
                .scaledToFit()
                .frame(width: swirlSize.width, height: swirlSize.height)
        }
        .fixedSize()
        // Preserve every glyph's aspect ratio, shrinking the whole block to fit
        // a narrow width (or a multi-digit age) instead of distorting it.
        .modifier(FitToWidth(maxWidth: maxWidth))
    }

    private var digits: some View {
        let characters = Array(String(age.value))
        return HStack(spacing: 2) {
            ForEach(characters.indices, id: \.self) { index in
                Image(BirthdayAsset.digit(characters[index]))
                    .resizable()
                    .scaledToFit()
                    .frame(height: digitHeight)
            }
        }
    }

    private var unitText: some View {
        Text(age.unitLabel)
            .font(.system(size: unitFontSize, weight: .medium))
            .tracking(-0.4201)
            .foregroundStyle(BirthdayTheme.titleColor)
            .multilineTextAlignment(.center)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }

    // MARK: - Photo

    private func photoView(diameter: CGFloat) -> some View {
        ZStack {
            // The complete ringed placeholder (ring + face). Its ring also frames
            // a selected photo, so no separate frame/colour is drawn.
            Image(theme.placeholderAssetName)
                .resizable()
                .scaledToFit()
                .frame(width: diameter, height: diameter)

            if let image = store.image {
                // Read-only use of the stored photo: viewing, opening, and
                // closing never rewrite or remove it. It is clipped to a circle
                // that sits just inside the ring.
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: diameter * photoInsetRatio, height: diameter * photoInsetRatio)
                    .clipShape(Circle())
            }
        }
        .frame(width: diameter, height: diameter)
        .accessibilityElement()
        .accessibilityLabel(store.image == nil ? "No photo yet" : "Birthday photo")
    }

    // MARK: - Logo

    private var logo: some View {
        Image(BirthdayAsset.logo)
            .resizable()
            .scaledToFit()
            .frame(width: logoSize.width, height: logoSize.height)
            .accessibilityHidden(true)
    }

    // MARK: - Close

    private var closeButton: some View {
        Button(action: onClose) {
            Image(BirthdayAsset.closeArrow)
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Close birthday screen")
        .accessibilityIdentifier("closeBirthday")
        .padding(.leading, 8)
        .padding(.top, 8)
    }

    // MARK: - Metrics

    /// The circle keeps a minimum 50pt horizontal margin on each side, never
    /// exceeds its reference ~229pt diameter, and leaves room on short screens.
    /// A transient zero/unmeasured geometry yields 0 rather than a negative
    /// (invalid) frame dimension.
    private func circleDiameter(for geo: GeometryProxy) -> CGFloat {
        max(0, min(referenceDiameter, geo.size.width - 100, geo.size.height * 0.45))
    }

    /// Horizontal space for content after the side padding, never negative.
    private func contentWidth(for geo: GeometryProxy) -> CGFloat {
        max(0, geo.size.width - horizontalPadding * 2)
    }

    /// Keeps the logo's bottom ~149pt above the physical bottom (the reserved
    /// share band), while never letting it drop into the bottom safe area.
    private func logoBottomReserve(_ geo: GeometryProxy) -> CGFloat {
        max(logoBottomReference - geo.safeAreaInsets.bottom, 24)
    }
}

/// Folds the title, numeric artwork, and unit into one spoken phrase for the
/// visible header, and makes the duplicate (decorative) header completely
/// invisible to accessibility — carrying no label or identifier — so exactly one
/// `birthdayAge` element is ever exposed.
private struct HeaderAccessibility: ViewModifier {
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

/// Scales its content down uniformly so its intrinsic width fits `maxWidth`,
/// preserving aspect ratios. Used for the age block so a narrow screen or a
/// multi-digit age shrinks the glyphs rather than distorting or clipping them.
private struct FitToWidth: ViewModifier {
    let maxWidth: CGFloat
    @State private var intrinsic: CGSize = .zero

    func body(content: Content) -> some View {
        // Only scale when both the intrinsic width and the target width are
        // valid, positive, finite numbers; an unmeasured/zero geometry leaves
        // the block at its natural size rather than producing a zero/negative
        // (invalid) frame.
        let canScale = intrinsic.width > 0 && maxWidth > 0 && maxWidth.isFinite
        let scale = (canScale && intrinsic.width > maxWidth)
            ? maxWidth / intrinsic.width
            : 1
        content
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: SizeKey.self, value: proxy.size)
                }
            )
            .onPreferenceChange(SizeKey.self) { intrinsic = $0 }
            .scaleEffect(scale, anchor: .center)
            .frame(
                width: intrinsic == .zero ? nil : intrinsic.width * scale,
                height: intrinsic == .zero ? nil : intrinsic.height * scale
            )
    }

    private struct SizeKey: PreferenceKey {
        static var defaultValue: CGSize = .zero
        static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
            let next = nextValue()
            if next != .zero { value = next }
        }
    }
}

#Preview("Fox — 1 month") {
    BirthdayView(
        store: DetailsStore(persistence: .birthdayPreview(monthsAgo: 1)),
        themeProvider: { .fox },
        onClose: {}
    )
}

#Preview("Elephant — long name, 2 years") {
    BirthdayView(
        store: DetailsStore(persistence: .birthdayPreview(name: "Cristiano Ronaldo", yearsAgo: 2)),
        themeProvider: { .elephant },
        onClose: {}
    )
}

private extension DetailsPersistence {
    /// An ephemeral store seeded for birthday-screen previews only; it never
    /// touches real user data.
    static func birthdayPreview(name: String = "Ada",
                                monthsAgo: Int = 0,
                                yearsAgo: Int = 0) -> DetailsPersistence {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("preview-\(UUID().uuidString)", isDirectory: true)
        let defaults = UserDefaults(suiteName: "preview-\(UUID().uuidString)") ?? .standard
        let persistence = DetailsPersistence(
            defaults: defaults,
            photoFileURL: directory.appendingPathComponent("photo.jpg")
        )
        persistence.save(name: name)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let date = calendar.date(byAdding: DateComponents(year: -yearsAgo, month: -monthsAgo), to: Date()) ?? Date()
        if let stored = StoredBirthday(date: date, timeZone: .current) {
            persistence.save(birthday: stored)
        }
        return persistence
    }
}
