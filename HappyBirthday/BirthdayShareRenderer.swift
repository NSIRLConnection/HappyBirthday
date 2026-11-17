import SwiftUI
import UIKit

/// Produces the shareable birthday image from an immutable snapshot of the
/// on-screen state, reusing the exact production content components the live
/// screen draws — but with no control overlay, so the result excludes the
/// close, camera, share, and spinner controls by construction.
///
/// It is a plain function of its inputs (theme, already-derived age, trimmed
/// name, current photo, captured geometry/insets, scale, text size), so a tap
/// captures a frozen snapshot and tests can exercise the real renderer directly
/// rather than mirroring a flag.
///
/// Canvas policy (explicit and deterministic, no ScrollView, no delays):
/// * The renderer reproduces the *full physical canvas*: the captured content
///   rect plus every captured safe-area inset, with those inset margins painted
///   as themed backdrop and bottom illustration (never status bar or controls),
///   so the export matches what the screen actually shows instead of the cropped
///   inset content rect.
/// * The renderer makes the *same layout choice* the live screen made for the
///   captured geometry and text size (`BirthdayLayout.prefersFullContentLayout`).
///   - Fixed path: the design's layered `BirthdayContent` is rendered at the full
///     canvas size, with the content stack inset by the captured safe areas,
///     exactly as the screen composed it — the full card, not a clipped viewport.
///   - Full-content path (accessibility text / short / wide viewports, where the
///     screen scrolls): a deterministic, non-scrolling `BirthdayShareContent`
///     stacks header, photo, and logo *above* the backdrop and grows vertically
///     to its complete content height, so nothing clips and the width-driven
///     illustration can never cover the fixed-size photo.
/// * Geometry is actually bounded: raw width/height are validated before any
///   `max()` so NaN/∞/negative can't be masked, width is capped and height is
///   clamped to a point budget, and the render scale is reduced predictably so
///   no pixel dimension exceeds the pixel budget.
enum BirthdayShareRenderer {
    /// Largest canvas edge, in points, we will ever lay out or grow to. Width
    /// beyond this fails rather than attempting an enormous allocation; height is
    /// clamped to it (the composition stays complete because it is measured).
    private static let maxPointDimension: CGFloat = 4096
    /// Largest single canvas edge, in pixels. Neither axis of the final bitmap is
    /// allowed past this.
    private static let maxPixelDimension: CGFloat = 8192
    /// Practical ceiling on the *total* pixel count of the largest canvas the
    /// layout can grow to (~24 MP ⇒ ~96 MiB RGBA). This is what actually bounds
    /// allocation: a 4096-square request is reduced in scale until it fits here
    /// rather than demanding hundreds of megabytes.
    private static let maxPixelBudget: CGFloat = 24_000_000

    /// A deterministic, allocation-free description of what the renderer will
    /// draw: the captured content rect, the validated safe-area insets, the full
    /// *physical* canvas (content rect plus those insets) the bitmap actually
    /// covers, the height the full-content layout may grow to, which layout path
    /// is taken, and the resolved render scale. `plan` returns nil for geometry
    /// that must be rejected, so the sizing and total-pixel-budget math can be
    /// unit-tested without allocating a bitmap.
    struct RenderPlan: Equatable {
        /// The safe content rect captured from the live `GeometryReader`.
        let contentSize: CGSize
        /// The validated (finite, non-negative) safe-area insets painted as themed
        /// margins around the content.
        let insets: EdgeInsets
        /// Full physical canvas width: content width plus horizontal insets.
        let canvasWidth: CGFloat
        /// Full physical canvas height (fixed path renders at exactly this).
        let viewportHeight: CGFloat
        let maxHeight: CGFloat
        let fullContent: Bool
        let scale: CGFloat

        /// Passed to `BirthdayContent` so the logo keeps its reference distance to
        /// the physical bottom even though the canvas now includes the inset.
        var safeAreaBottom: CGFloat { insets.bottom }

        /// The largest final bitmap the plan can produce (the full-content path
        /// may grow height to `maxHeight`; the fixed path stays at the viewport).
        var maxPixelWidth: CGFloat { canvasWidth * scale }
        var maxPixelHeight: CGFloat { maxHeight * scale }
        var maxPixelCount: CGFloat { maxPixelWidth * maxPixelHeight }
    }

    /// Validates the raw inputs and resolves the full physical canvas and render
    /// scale without touching any bitmap. Rejects non-finite/degenerate geometry
    /// (before any `max()` can mask it) and over-wide requests; clamps each inset
    /// to a finite, non-negative value; and reduces the scale predictably —
    /// preserving aspect — so no pixel edge exceeds the dimension cap and the
    /// largest possible canvas (insets included) stays within the total-pixel
    /// budget.
    static func plan(size: CGSize,
                     safeAreaInsets: EdgeInsets = EdgeInsets(),
                     scale: CGFloat,
                     dynamicTypeSize: DynamicTypeSize) -> RenderPlan? {
        let contentWidth = size.width
        let contentHeight = size.height
        // Validate the RAW content geometry first so a negative/NaN/∞ input can
        // never be hidden by a later max()/fallback.
        guard contentWidth.isFinite, contentHeight.isFinite,
              contentWidth > 1, contentHeight > 1 else { return nil }

        // A NaN/∞/negative inset falls back to flush (0) on that edge rather than
        // corrupting the composition or the budget math.
        func cleanInset(_ value: CGFloat) -> CGFloat {
            (value.isFinite && value > 0) ? value : 0
        }
        let insets = EdgeInsets(top: cleanInset(safeAreaInsets.top),
                                leading: cleanInset(safeAreaInsets.leading),
                                bottom: cleanInset(safeAreaInsets.bottom),
                                trailing: cleanInset(safeAreaInsets.trailing))

        // The full physical canvas the export reproduces: the content rect plus
        // the themed safe-area margins. Cap the width so a huge finite request
        // fails instead of attempting an enormous bitmap.
        let canvasWidth = contentWidth + insets.leading + insets.trailing
        let canvasHeight = contentHeight + insets.top + insets.bottom
        guard canvasWidth <= maxPointDimension else { return nil }

        // The captured canvas height, clamped into the point budget. The
        // full-content path may grow above this (up to the budget); the fixed path
        // renders at exactly this height.
        let viewportHeight = min(canvasHeight, maxPointDimension)
        let fullContent = BirthdayLayout.prefersFullContentLayout(size: size, dynamicTypeSize: dynamicTypeSize)
        let maxHeight = fullContent ? maxPointDimension : viewportHeight

        // Clamp to a sane device scale, then reduce predictably so no pixel edge
        // exceeds the dimension cap and the largest canvas stays within the
        // total-pixel budget. A single scalar scales both axes, so aspect holds.
        let base = (scale.isFinite && scale > 0) ? min(scale, 3) : 3
        let dimensionLimit = min(maxPixelDimension / canvasWidth, maxPixelDimension / maxHeight)
        let budgetLimit = (maxPixelBudget / (canvasWidth * maxHeight)).squareRoot()
        let resolved = max(1, min(base, dimensionLimit, budgetLimit))

        return RenderPlan(contentSize: CGSize(width: contentWidth, height: contentHeight),
                          insets: insets, canvasWidth: canvasWidth,
                          viewportHeight: viewportHeight, maxHeight: maxHeight,
                          fullContent: fullContent, scale: resolved)
    }

    @MainActor
    static func render(theme: BirthdayTheme,
                       age: BirthdayAge,
                       name: String,
                       image: UIImage?,
                       size: CGSize,
                       safeAreaInsets: EdgeInsets = EdgeInsets(),
                       scale: CGFloat,
                       dynamicTypeSize: DynamicTypeSize = .large) -> UIImage? {
        guard let plan = plan(size: size,
                              safeAreaInsets: safeAreaInsets,
                              scale: scale,
                              dynamicTypeSize: dynamicTypeSize) else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)

        let content: AnyView
        if plan.fullContent {
            content = AnyView(
                BirthdayShareContent(
                    width: plan.canvasWidth,
                    minHeight: plan.viewportHeight,
                    maxHeight: plan.maxHeight,
                    safeAreaInsets: plan.insets,
                    theme: theme,
                    age: age,
                    trimmedName: trimmed,
                    image: image
                )
                .environment(\.dynamicTypeSize, dynamicTypeSize)
            )
        } else {
            let canvas = CGSize(width: plan.canvasWidth, height: plan.viewportHeight)
            content = AnyView(
                BirthdayContent(
                    size: canvas,
                    safeAreaBottom: plan.safeAreaBottom,
                    safeAreaInsets: plan.insets,
                    theme: theme,
                    age: age,
                    trimmedName: trimmed,
                    image: image,
                    photoOverlay: { _ in EmptyView() }
                )
                .frame(width: canvas.width, height: canvas.height)
                .environment(\.dynamicTypeSize, dynamicTypeSize)
            )
        }

        let renderer = ImageRenderer(content: content)
        renderer.isOpaque = true
        renderer.scale = plan.scale
        return renderer.uiImage
    }
}

/// A deterministic, non-scrolling full-content composition used by the share
/// renderer for exactly the cases the live screen scrolls (accessibility text,
/// short, or wide viewports). It stacks the production header, photo, and logo
/// *above* the themed backdrop and bottom illustration — the same element order
/// and shared components as the on-screen scroll layout — and grows vertically
/// to its complete content height, never below the captured viewport height and
/// never above the point budget. Because it has a single, finite layout pass and
/// draws the photo above the backdrop, nothing clips and the width-driven
/// illustration can never cover the fixed-size photo.
private struct BirthdayShareContent: View {
    let width: CGFloat
    let minHeight: CGFloat
    let maxHeight: CGFloat
    /// Themed safe-area margins painted around the inset content (see
    /// `BirthdayContent.safeAreaInsets`).
    var safeAreaInsets: EdgeInsets = EdgeInsets()
    let theme: BirthdayTheme
    let age: BirthdayAge
    let trimmedName: String
    let image: UIImage?

    var body: some View {
        let diameter = BirthdayLayout.circleDiameter(width: width, height: minHeight)
        let contentWidth = BirthdayLayout.contentWidth(width: width)
        ZStack {
            theme.backgroundColor
            BirthdayIllustration(theme: theme)
            VStack(spacing: 0) {
                BirthdayHeader(trimmedName: trimmedName, age: age,
                               availableWidth: contentWidth, decorative: false)
                Spacer().frame(height: 28)
                BirthdayPhoto(theme: theme, image: image, diameter: diameter)
                Spacer().frame(height: BirthdayLayout.photoToLogoGap)
                BirthdayLogo()
            }
            .padding(.horizontal, BirthdayLayout.horizontalPadding)
            .padding(.top, 72)
            .padding(.bottom, 48)
            // Keep the content inside the captured safe-area rect; the backdrop
            // and illustration below still fill the whole canvas.
            .padding(safeAreaInsets)
            .frame(maxWidth: .infinity)
        }
        .frame(width: width)
        // `fixedSize` makes the stack report its ideal content height; the frame
        // then clamps that into [viewport, budget], so a small card still fills
        // the captured viewport and a tall one grows instead of clipping.
        .frame(minHeight: minHeight, maxHeight: maxHeight)
        .fixedSize(horizontal: false, vertical: true)
    }
}
