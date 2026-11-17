import SwiftUI
import UIKit

/// The celebratory birthday screen presented from the details screen.
///
/// The themed content — two-line-capable title, decorative age artwork flanked by
/// swirls, the singular/plural unit caption, the child's ringed photo, the Nanit
/// logo, and a bottom-pinned illustration — is drawn by the shared, content-only
/// `BirthdayContent` composition. This view layers the interactive controls on
/// top: a top-left close button, the single camera control on the photo ring, and
/// the bottom "Share the news" button. Because the share export reuses the same
/// `BirthdayContent` with an empty control overlay, the shared image omits the
/// share, camera, and close controls by construction.
struct BirthdayView: View {
    @ObservedObject var store: DetailsStore
    let onClose: () -> Void

    @StateObject private var model: BirthdayScreenModel
    // The birthday screen runs its own add/change-photo flow (dialog, picker,
    // camera, import coordination) independently of the details screen behind it.
    @StateObject private var photoSelection = PhotoSelection()
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.displayScale) private var displayScale

    @ScaledMetric(relativeTo: .body) private var shareFontSize: CGFloat = 16
    @ScaledMetric(relativeTo: .body) private var shareIconHeight: CGFloat = 33.6378

    /// The latest measured viewport, captured so a share tap can render the
    /// composition at the same width/height the screen is showing. Seeded with the
    /// 375×667 reference so a share before the first layout still renders.
    @State private var canvasSize: CGSize = CGSize(width: 375, height: 667)
    /// The latest measured safe-area insets, captured alongside the size so the
    /// export reproduces the full physical canvas (status-bar and home-indicator
    /// strips painted as themed content) rather than only the inset content rect.
    @State private var canvasInsets: EdgeInsets = EdgeInsets()
    /// The prepared image handed to the system share sheet; non-nil presents it.
    @State private var shareImage: UIImage?
    @State private var shareError: String?

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

    // MARK: - Share button geometry

    /// Intrinsic aspect of the original share arrow (30.2802 × 33.6378).
    private let shareIconAspect: CGFloat = 30.2802 / 33.6378
    private let shareCoral = Color(hex: 0xEF7B7B)

    private var theme: BirthdayTheme { model.theme }

    private var age: BirthdayAge {
        model.age(for: store.storedBirthday) ?? BirthdayAge(value: 0, unit: .months)
    }

    private var trimmedName: String {
        store.name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                theme.backgroundColor
                    .ignoresSafeArea()

                if prefersScrollLayout(geo) {
                    BirthdayIllustration(theme: theme)
                    scrollLayout(in: geo)
                } else {
                    BirthdayContent(
                        size: geo.size,
                        safeAreaBottom: geo.safeAreaInsets.bottom,
                        theme: theme,
                        age: age,
                        trimmedName: trimmedName,
                        image: store.image,
                        photoOverlay: { diameter in photoControls(diameter: diameter) }
                    )
                    bottomShareBar(geo)
                }

                closeButton
            }
            .onAppear { canvasSize = geo.size; canvasInsets = geo.safeAreaInsets }
            .onChange(of: geo.size) { _, newValue in canvasSize = newValue }
            .onChange(of: geo.safeAreaInsets) { _, newValue in canvasInsets = newValue }
        }
        // Dialog, library picker, camera, and the camera/import error alerts —
        // presented from the birthday screen itself so they appear above it
        // rather than on the hidden details screen underneath.
        .photoSelection(photoSelection, store: store)
        // The system share sheet is presented from a controller embedded here, so
        // it appears above the full-screen birthday cover.
        .background(ActivityShareSheet(image: $shareImage))
        .alert("Couldn’t share", isPresented: shareErrorBinding) {
            Button("OK", role: .cancel) { shareError = nil }
        } message: {
            Text(shareError ?? "")
        }
    }

    /// Fall back to a scrollable, single-stack layout when the design's fixed
    /// composition cannot hold the content. Shares the exact decision the export
    /// uses (`BirthdayLayout.prefersFullContentLayout`) so the live screen and the
    /// shared image never diverge on which layout they draw.
    private func prefersScrollLayout(_ geo: GeometryProxy) -> Bool {
        BirthdayLayout.prefersFullContentLayout(size: geo.size, dynamicTypeSize: dynamicTypeSize)
    }

    // MARK: - Scroll (fallback) layout

    private func scrollLayout(in geo: GeometryProxy) -> some View {
        let diameter = BirthdayLayout.circleDiameter(width: geo.size.width, height: geo.size.height)
        let contentWidth = BirthdayLayout.contentWidth(width: geo.size.width)
        return ScrollView {
            VStack(spacing: 0) {
                BirthdayHeader(trimmedName: trimmedName, age: age,
                               availableWidth: contentWidth, decorative: false)
                Spacer().frame(height: 28)
                BirthdayPhoto(theme: theme, image: store.image, diameter: diameter)
                    // Overlaid as a sibling of the photo (not inside its clip or
                    // its combined accessibility element) so the single camera
                    // control stays tappable and separately labelled.
                    .overlay(alignment: .center) { cameraButton(diameter: diameter) }
                    .overlay { importingIndicator }
                Spacer().frame(height: BirthdayLayout.photoToLogoGap)
                BirthdayLogo()
                // Keep the share button after the logo with a comfortable gap, so
                // it stays reachable by scrolling at large text sizes.
                Spacer().frame(height: 32)
                shareButton
            }
            .padding(.horizontal, BirthdayLayout.horizontalPadding)
            .padding(.top, 72)
            .padding(.bottom, 48)
            .frame(maxWidth: .infinity)
            .frame(minHeight: geo.size.height, alignment: .center)
        }
    }

    // MARK: - Camera control

    /// The camera control and the import spinner, injected into the foreground
    /// photo slot of the fixed composition.
    private func photoControls(diameter: CGFloat) -> some View {
        ZStack {
            importingIndicator
            cameraButton(diameter: diameter)
        }
    }

    /// The theme-matched camera button, pinned to the photo ring at 45° in the
    /// upper-right. It keeps a fixed 36pt visual / 44pt tap target regardless of
    /// how far the photo shrinks on small screens, and its artwork is hidden from
    /// accessibility so the button surfaces a single "Add photo"/"Change photo".
    private func cameraButton(diameter: CGFloat) -> some View {
        Button {
            photoSelection.begin()
        } label: {
            Image(theme.cameraAssetName)
                .resizable()
                .scaledToFit()
                .frame(width: 36, height: 36)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                .accessibilityHidden(true)
        }
        .buttonStyle(.plain)
        .disabled(photoSelection.isImporting)
        .accessibilityLabel(store.image == nil ? "Add photo" : "Change photo")
        .accessibilityIdentifier("birthdayPhotoButton")
        // Place the control's centre on the ring: the nominal 222pt circle inside
        // the 229pt outer bounds, resolved to a 45° offset on each axis.
        .offset(x: cameraOffset(diameter: diameter), y: -cameraOffset(diameter: diameter))
    }

    /// Per-axis distance from the photo centre to the ring at 45°:
    /// `diameter × (222/229) / (2√2)`. Uses the live rendered diameter so the
    /// control tracks the ring as the photo scales.
    private func cameraOffset(diameter: CGFloat) -> CGFloat {
        diameter * (222.0 / 229.0) / (2 * CGFloat(2).squareRoot())
    }

    /// A centred spinner shown over the photo slot while a selection is being
    /// imported; selection is disabled meanwhile, but the close button stays
    /// reachable above it.
    @ViewBuilder
    private var importingIndicator: some View {
        if photoSelection.isImporting {
            ProgressView()
                .controlSize(.large)
                .padding(24)
                .background(.ultraThinMaterial, in: Circle())
                .accessibilityLabel("Importing photo")
        }
    }

    // MARK: - Share control

    /// A bottom-pinned bar holding the share button in the reserved lower band,
    /// its bottom edge ~56pt above the physical bottom (per design), without
    /// moving the existing composition above it.
    private func bottomShareBar(_ geo: GeometryProxy) -> some View {
        VStack {
            Spacer()
            shareButton
                .padding(.bottom, max(56 - geo.safeAreaInsets.bottom, 12))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The coral "Share the news" capsule with the original curved share arrow.
    /// The capsule renders at the 179×42 reference but grows for larger text and
    /// keeps at least a 44pt tap target; the words are never dropped.
    private var shareButton: some View {
        Button {
            beginShare()
        } label: {
            // No explicit gap: the original share glyph already carries a built-in
            // ~5.89pt left inset, matching the Figma near-zero text-to-icon gap.
            HStack(spacing: 0) {
                Text("Share the news")
                    .font(.system(size: shareFontSize, weight: .regular))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Image(BirthdayAsset.shareIcon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: shareIconHeight * shareIconAspect, height: shareIconHeight)
                    .accessibilityHidden(true)
            }
            // Snug horizontal padding so the default capsule resolves to the
            // 179pt reference width (minWidth) instead of overflowing past it,
            // while larger text sizes can still grow the capsule.
            .padding(.horizontal, 16)
            .frame(minWidth: 179, minHeight: 42)
            .background(Capsule().fill(shareCoral))
            // Keep at least a 44pt tap target even though the capsule is 42pt tall.
            .frame(minHeight: 44)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isShareDisabled)
        .accessibilityLabel("Share the news")
        .accessibilityIdentifier("birthdayShareButton")
    }

    /// Prevent duplicate share requests while a sheet is up, and avoid sharing a
    /// stale photo while a newer selection is still importing.
    private var isShareDisabled: Bool {
        shareImage != nil || photoSelection.isImporting
    }

    /// Build the share image from an immutable snapshot of the current theme,
    /// derived age, name, and photo at tap time. A failed render surfaces a
    /// concise error rather than presenting an empty share sheet.
    private func beginShare() {
        guard !isShareDisabled else { return }
        let size = canvasSize == .zero ? CGSize(width: 375, height: 667) : canvasSize
        if let rendered = BirthdayShareRenderer.render(
            theme: model.theme,
            age: age,
            name: store.name,
            image: store.image,
            size: size,
            safeAreaInsets: canvasInsets,
            scale: displayScale,
            dynamicTypeSize: dynamicTypeSize
        ) {
            shareImage = rendered
        } else {
            shareError = "We couldn’t prepare the image to share. Please try again."
        }
    }

    private var shareErrorBinding: Binding<Bool> {
        Binding(get: { shareError != nil }, set: { if !$0 { shareError = nil } })
    }

    // MARK: - Close

    private var closeButton: some View {
        Button {
            // Explicitly cancel any in-flight import and pending authorization so
            // a late result from the dismissed screen cannot mutate the store or
            // try to present. (We never cancel on `onDisappear`, which also fires
            // when this screen presents its own camera cover.)
            photoSelection.invalidate()
            onClose()
        } label: {
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
