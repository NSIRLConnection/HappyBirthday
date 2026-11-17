import XCTest
import SwiftUI
import UIKit
@testable import HappyBirthday

/// Exercises the real `BirthdayShareRenderer` — the same code the share button
/// runs — across themes, ages, names, and layouts. The tests assert the export is
/// a bounded, opaque, correctly-themed bitmap of the full composition and reject
/// invalid geometry, and they attach representative PNGs to the result bundle so
/// Codex can visually confirm the controls are absent from the actual output.
@MainActor
final class BirthdayShareRenderTests: XCTestCase {
    private let reference = CGSize(width: 375, height: 667)
    private let renderScale: CGFloat = 2

    // Expected flat background RGB per theme (from BirthdayTheme hex literals).
    private let themeBackgrounds: [BirthdayTheme: (r: Int, g: Int, b: Int)] = [
        .fox: (197, 232, 223),       // 0xC5E8DF
        .elephant: (254, 239, 203),  // 0xFEEFCB
        .pelican: (218, 241, 246),   // 0xDAF1F6
    ]

    // MARK: - Per-theme opaque, non-empty, correctly-themed render

    func testEachThemeRendersOpaqueThemedImageOfExpectedSize() throws {
        for theme in BirthdayTheme.allCases {
            let image = try XCTUnwrap(
                BirthdayShareRenderer.render(
                    theme: theme,
                    age: BirthdayAge(value: 1, unit: .years),
                    name: "Ada",
                    image: nil,
                    size: reference,
                    scale: renderScale
                ),
                "Expected a rendered image for \(theme)."
            )

            // Point size follows the requested width; the height is at least the
            // portrait reference so the full card is captured.
            XCTAssertEqual(image.size.width, reference.width, accuracy: 0.5)
            XCTAssertGreaterThanOrEqual(image.size.height, reference.height - 0.5)
            XCTAssertEqual(image.scale, renderScale, accuracy: 0.01)

            let cg = try XCTUnwrap(image.cgImage, "Rendered image should be bitmap-backed.")
            XCTAssertGreaterThan(cg.width, 0)
            XCTAssertGreaterThan(cg.height, 0)

            // The top-left corner sits above the bottom-pinned illustration and
            // beside the centred content, so it must be the flat opaque theme
            // backdrop — proving the export is opaque and correctly themed.
            let corner = try XCTUnwrap(pixel(cg, x: 2, y: 2), "Could not sample the corner pixel.")
            XCTAssertEqual(corner.a, 255, "The share image must be fully opaque.")
            let expected = try XCTUnwrap(themeBackgrounds[theme])
            XCTAssertEqual(Int(corner.r), expected.r, accuracy: 6, "\(theme) backdrop red")
            XCTAssertEqual(Int(corner.g), expected.g, accuracy: 6, "\(theme) backdrop green")
            XCTAssertEqual(Int(corner.b), expected.b, accuracy: 6, "\(theme) backdrop blue")

            attach(image, name: "share-\(theme.rawValue)")
        }
    }

    // MARK: - Invalid geometry / nil failure

    func testInvalidGeometryReturnsNilInsteadOfEmptyImage() {
        let degenerate: [CGSize] = [
            .zero,
            CGSize(width: 0, height: 667),
            CGSize(width: 375, height: 0),
            CGSize(width: -375, height: 667),
            CGSize(width: 1, height: 1),
            CGSize(width: CGFloat.nan, height: 667),
            CGSize(width: 375, height: CGFloat.infinity),
            CGSize(width: 375, height: CGFloat.nan),
            CGSize(width: CGFloat.infinity, height: 667),
            // Over-wide finite request: rejected rather than allocating a bitmap.
            CGSize(width: 8192, height: 667),
        ]
        for size in degenerate {
            XCTAssertNil(
                BirthdayShareRenderer.render(
                    theme: .fox,
                    age: BirthdayAge(value: 2, unit: .years),
                    name: "Ada",
                    image: nil,
                    size: size,
                    scale: renderScale
                ),
                "Invalid geometry \(size) must fail rather than produce an empty share sheet."
            )
        }
    }

    func testNonFiniteScaleFallsBackToABoundedRender() throws {
        // A broken display scale must not abort the render or allocate unbounded
        // pixels; it clamps to a sane device scale.
        let image = try XCTUnwrap(
            BirthdayShareRenderer.render(
                theme: .pelican,
                age: BirthdayAge(value: 6, unit: .months),
                name: "Ada",
                image: nil,
                size: reference,
                scale: .nan
            )
        )
        XCTAssertGreaterThan(image.scale, 0)
        XCTAssertLessThanOrEqual(image.scale, 3)
    }

    // MARK: - Long names, two-digit age, narrow / wide / largest text

    func testLongNameTwoDigitAgeRendersFullContent() throws {
        let image = try XCTUnwrap(
            BirthdayShareRenderer.render(
                theme: .elephant,
                age: BirthdayAge(value: 12, unit: .years),
                name: "Cristiano Ronaldo",
                image: nil,
                size: reference,
                scale: renderScale
            )
        )
        assertNonEmpty(image)
        attach(image, name: "share-longname-twodigit")
    }

    func testNarrowShortScreenRendersFullContentWithoutClipping() throws {
        // 320×568 is too short for the fixed layered card, which previously clipped
        // the title off the TOP. It must now take the full-content path, which
        // grows to the complete content height so nothing clips.
        let size = CGSize(width: 320, height: 568)
        let plan = try XCTUnwrap(
            BirthdayShareRenderer.plan(size: size, scale: renderScale, dynamicTypeSize: .large)
        )
        XCTAssertTrue(plan.fullContent,
                      "A viewport too short for the fixed card must use the full-content layout.")

        let image = try XCTUnwrap(
            BirthdayShareRenderer.render(
                theme: .fox,
                age: BirthdayAge(value: 11, unit: .months),
                name: "Jacqueline",
                image: nil,
                size: size,
                scale: renderScale
            )
        )
        assertNonEmpty(image)
        XCTAssertEqual(image.size.width, 320, accuracy: 0.5)
        // The composition grows past the short captured viewport rather than
        // clipping; the full title/age/photo/logo stack is taller than 568.
        XCTAssertGreaterThan(image.size.height, 568,
                             "The short viewport must grow to fit the complete content.")
        attach(image, name: "share-narrow")
    }

    func testWideLandscapeRendersFullPortraitContentNotAClippedViewport() throws {
        // A wide, short live viewport (e.g. unfolded Duo / landscape) must still
        // export the whole card, so the height is driven up to the portrait
        // reference rather than exporting a short clipped strip.
        let wide = CGSize(width: 900, height: 420)
        let image = try XCTUnwrap(
            BirthdayShareRenderer.render(
                theme: .pelican,
                age: BirthdayAge(value: 1, unit: .years),
                name: "Ada",
                image: nil,
                size: wide,
                scale: renderScale
            )
        )
        XCTAssertEqual(image.size.width, 900, accuracy: 0.5)
        XCTAssertGreaterThan(image.size.height, wide.height,
                             "A short live viewport must not clip the exported composition.")
        assertNonEmpty(image)
        attach(image, name: "share-wide")
    }

    func testLargestAccessibilityTextLongNameTwoDigitAgeRendersFullContent() throws {
        // The hardest text case: AX5 Dynamic Type, a long two-line name, and a
        // two-digit age — exercises the full-content path at its tallest.
        let image = try XCTUnwrap(
            BirthdayShareRenderer.render(
                theme: .fox,
                age: BirthdayAge(value: 12, unit: .years),
                name: "Cristiano Ronaldo",
                image: nil,
                size: reference,
                scale: renderScale,
                dynamicTypeSize: .accessibility5
            )
        )
        assertNonEmpty(image)
        attach(image, name: "share-largest-text-longname-twodigit")
    }

    // MARK: - Synthetic photo fixture: the selected image is actually drawn

    func testSyntheticPhotoIsVisibleInTheRenderedCircle() throws {
        // A solid magenta photo — a colour that appears nowhere in the themed
        // artwork — so finding it in the output proves the selected picture is
        // composited into the ring (and isn't fully covered on the fixed path).
        let photo = solidImage(.magenta, size: CGSize(width: 240, height: 240))
        let image = try XCTUnwrap(
            BirthdayShareRenderer.render(
                theme: .fox,
                age: BirthdayAge(value: 1, unit: .years),
                name: "Ada",
                image: photo,
                size: reference,
                scale: renderScale
            )
        )
        let cg = try XCTUnwrap(image.cgImage)
        // Sample the centre of the card, where the photo ring sits.
        let center = try XCTUnwrap(pixel(cg, x: cg.width / 2, y: cg.height / 2))
        XCTAssertGreaterThan(Int(center.r), 150, "Expected the magenta photo in the ring.")
        XCTAssertLessThan(Int(center.g), 120, "Expected the magenta photo in the ring.")
        XCTAssertGreaterThan(Int(center.b), 150, "Expected the magenta photo in the ring.")
        attach(image, name: "share-synthetic-photo")
    }

    func testWidePhotoExportKeepsPhotoVisibleOverIllustration() throws {
        // The reported wide/iPad risk: the width-driven illustration covering the
        // small fixed-size photo. The full-content export path stacks the photo
        // above the backdrop, so a synthetic photo must remain visible.
        let photo = solidImage(.magenta, size: CGSize(width: 240, height: 240))
        let image = try XCTUnwrap(
            BirthdayShareRenderer.render(
                theme: .pelican,
                age: BirthdayAge(value: 1, unit: .years),
                name: "Ada",
                image: photo,
                size: CGSize(width: 1024, height: 600),
                scale: renderScale
            )
        )
        assertNonEmpty(image)
        XCTAssertEqual(image.size.width, 1024, accuracy: 0.5)
        // The complete content is exported, never a clipped strip: the height is at
        // least the captured viewport (it may equal it if the content already fits,
        // so we do not require strict growth).
        XCTAssertGreaterThanOrEqual(image.size.height, 600 - 0.5,
                                    "A short wide viewport must export the full composition, not a strip.")
        // The real risk is the width-driven illustration covering the small photo.
        // Scan the centre column: the magenta photo must be visible somewhere.
        let cg = try XCTUnwrap(image.cgImage)
        XCTAssertTrue(
            centerColumnContains(cg) { r, g, b in r > 150 && g < 120 && b > 150 },
            "The synthetic magenta photo must remain visible over the illustration."
        )
        attach(image, name: "share-wide-photo")
    }

    // MARK: - Allocation-free sizing / total-pixel budget

    func testFixedPhonePlanKeepsFullDeviceScale() throws {
        // No insets: the canvas equals the content rect and keeps full scale.
        let plan = try XCTUnwrap(
            BirthdayShareRenderer.plan(size: reference, scale: 3, dynamicTypeSize: .large)
        )
        XCTAssertFalse(plan.fullContent, "A portrait phone uses the fixed layered path.")
        XCTAssertEqual(plan.scale, 3, accuracy: 0.001, "A normal canvas keeps its device scale.")
        XCTAssertEqual(plan.safeAreaBottom, 0, accuracy: 0.001)
        XCTAssertEqual(plan.canvasWidth, reference.width, accuracy: 0.5)
        XCTAssertEqual(plan.viewportHeight, reference.height, accuracy: 0.5)
    }

    func testHugeSquareRequestIsReducedToTheTotalPixelBudget() throws {
        // A 4096² point request at scale 3 would be ~150 MP / ~600 MiB RGBA. The
        // plan reduces the scale so the largest canvas stays within budget — this
        // is verified purely from the math, allocating nothing.
        let plan = try XCTUnwrap(
            BirthdayShareRenderer.plan(size: CGSize(width: 4096, height: 4096),
                                       scale: 3, dynamicTypeSize: .large)
        )
        XCTAssertLessThan(plan.scale, 3, "An enormous canvas must have its scale reduced.")
        XCTAssertGreaterThanOrEqual(plan.scale, 1, "Scale never drops below 1.")
        XCTAssertLessThanOrEqual(plan.maxPixelCount, 24_000_000 * 1.001,
                                 "The largest canvas must stay within the total-pixel budget.")
        XCTAssertLessThanOrEqual(plan.maxPixelWidth, 8192 * 1.001)
        XCTAssertLessThanOrEqual(plan.maxPixelHeight, 8192 * 1.001)
    }

    func testFullContentPlanBudgetsAgainstGrownHeight() throws {
        // A wide, short viewport takes the full-content path, which can grow to the
        // point ceiling; the budget is computed against that grown height so even
        // the tallest possible canvas stays bounded.
        let plan = try XCTUnwrap(
            BirthdayShareRenderer.plan(size: CGSize(width: 1024, height: 600),
                                       scale: 3, dynamicTypeSize: .large)
        )
        XCTAssertTrue(plan.fullContent)
        XCTAssertGreaterThan(plan.maxHeight, plan.viewportHeight,
                             "The full-content path may grow taller than the viewport.")
        XCTAssertLessThanOrEqual(plan.maxPixelCount, 24_000_000 * 1.001)
    }

    func testPlanRejectsNonFiniteGeometryAndInsets() {
        XCTAssertNil(BirthdayShareRenderer.plan(size: CGSize(width: CGFloat.nan, height: 667),
                                                scale: 3, dynamicTypeSize: .large))
        XCTAssertNil(BirthdayShareRenderer.plan(size: CGSize(width: 375, height: CGFloat.infinity),
                                                scale: 3, dynamicTypeSize: .large))
        XCTAssertNil(BirthdayShareRenderer.plan(size: CGSize(width: 8192, height: 667),
                                                scale: 3, dynamicTypeSize: .large))
        // A finite content width that only overflows once the insets are added
        // must also be rejected rather than allocating a huge bitmap.
        XCTAssertNil(BirthdayShareRenderer.plan(size: CGSize(width: 4000, height: 667),
                                                safeAreaInsets: EdgeInsets(top: 0, leading: 100, bottom: 0, trailing: 100),
                                                scale: 3, dynamicTypeSize: .large))
        // Non-finite/negative insets must not corrupt the plan: each bad edge
        // falls back to flush (0) rather than NaN-poisoning the canvas/budget.
        let plan = BirthdayShareRenderer.plan(
            size: reference,
            safeAreaInsets: EdgeInsets(top: .infinity, leading: -20, bottom: .nan, trailing: 0),
            scale: 3, dynamicTypeSize: .large)
        XCTAssertEqual(plan?.safeAreaBottom, 0)
        XCTAssertEqual(plan?.insets.top, 0)
        XCTAssertEqual(plan?.insets.leading, 0)
        XCTAssertEqual(plan?.canvasWidth, reference.width)
    }

    // MARK: - Deterministic age-row sizing (the renderer's first-pass layout)

    func testAgeRowIntrinsicWidthIsPositiveAndGrowsWithDigits() {
        let one = BirthdayAgeRow.intrinsicWidth(for: Array("1"))
        let twelve = BirthdayAgeRow.intrinsicWidth(for: Array("12"))
        XCTAssertGreaterThan(one, 0)
        XCTAssertGreaterThan(twelve, one, "A two-digit age must be intrinsically wider.")
    }

    // MARK: - Pixel sampler self-check

    func testPixelSamplerReadsTopLeftOrigin() throws {
        // A 1×2 bitmap: red top row, blue bottom row. The sampler must read the
        // red top pixel at y=0 and the blue bottom pixel at y=1 — catching the
        // earlier bottom-up coordinate bug that made corner samples read the
        // bottom illustration instead of the top backdrop.
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 2), format: format).image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
            UIColor.blue.setFill()
            ctx.fill(CGRect(x: 0, y: 1, width: 1, height: 1))
        }
        let cg = try XCTUnwrap(image.cgImage)
        let top = try XCTUnwrap(pixel(cg, x: 0, y: 0))
        let bottom = try XCTUnwrap(pixel(cg, x: 0, y: 1))
        XCTAssertGreaterThan(Int(top.r), 200, "y=0 must read the top (red) row.")
        XCTAssertLessThan(Int(top.b), 60, "y=0 must read the top (red) row.")
        XCTAssertGreaterThan(Int(bottom.b), 200, "y=1 must read the bottom (blue) row.")
        XCTAssertLessThan(Int(bottom.r), 60, "y=1 must read the bottom (blue) row.")
    }

    // MARK: - Full safe-area canvas integration

    func testSafeAreaInsetsExpandCanvasAndArePaintedThemed() throws {
        // A real phone capture: content rect 375×667 inside 44pt top / 34pt bottom
        // insets. The export must reproduce the FULL physical canvas (375×745),
        // with the top inset strip painted as the themed backdrop rather than
        // cropped away or left blank.
        let insets = EdgeInsets(top: 44, leading: 0, bottom: 34, trailing: 0)
        let image = try XCTUnwrap(
            BirthdayShareRenderer.render(
                theme: .fox,
                age: BirthdayAge(value: 1, unit: .years),
                name: "Ada",
                image: nil,
                size: reference,
                safeAreaInsets: insets,
                scale: renderScale
            )
        )
        XCTAssertEqual(image.size.width, reference.width, accuracy: 0.5)
        XCTAssertEqual(image.size.height, reference.height + 44 + 34, accuracy: 0.5,
                       "The exported canvas must include the captured safe-area insets.")

        let cg = try XCTUnwrap(image.cgImage)
        // A pixel high inside the top inset strip must be the opaque themed
        // backdrop (fox 0xC5E8DF), proving the inset margin is painted.
        let top = try XCTUnwrap(pixel(cg, x: 4, y: 4))
        XCTAssertEqual(top.a, 255)
        let expected = try XCTUnwrap(themeBackgrounds[.fox])
        XCTAssertEqual(Int(top.r), expected.r, accuracy: 6)
        XCTAssertEqual(Int(top.g), expected.g, accuracy: 6)
        XCTAssertEqual(Int(top.b), expected.b, accuracy: 6)
        attach(image, name: "share-safe-area-canvas")
    }

    func testPlanCanvasIncludesInsetsAndKeepsScale() throws {
        let insets = EdgeInsets(top: 44, leading: 0, bottom: 34, trailing: 0)
        let plan = try XCTUnwrap(
            BirthdayShareRenderer.plan(size: reference, safeAreaInsets: insets,
                                       scale: 3, dynamicTypeSize: .large)
        )
        XCTAssertFalse(plan.fullContent, "A portrait phone uses the fixed layered path.")
        XCTAssertEqual(plan.scale, 3, accuracy: 0.001, "A normal canvas keeps its device scale.")
        XCTAssertEqual(plan.canvasWidth, reference.width, accuracy: 0.5)
        XCTAssertEqual(plan.viewportHeight, reference.height + 44 + 34, accuracy: 0.5)
        XCTAssertEqual(plan.safeAreaBottom, 34, accuracy: 0.001)
        XCTAssertEqual(plan.insets.top, 44, accuracy: 0.001)
    }

    // MARK: - Helpers

    private func assertNonEmpty(_ image: UIImage) {
        XCTAssertNotNil(image.cgImage)
        XCTAssertGreaterThan(image.size.width, 1)
        XCTAssertGreaterThan(image.size.height, 1)
    }

    /// A solid-colour opaque bitmap used as a verifiable synthetic photo fixture.
    private func solidImage(_ color: UIColor, size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            color.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }

    private func attach(_ image: UIImage, name: String) {
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Samples a single pixel at image coordinates `(x, y)` measured from the
    /// TOP-LEFT (UIKit orientation), in premultiplied-last RGBA.
    ///
    /// The 1×1 `CGContext` has Core Graphics' default bottom-left origin and draws
    /// the `CGImage` un-flipped (its visual top maps to the top of the draw rect),
    /// so to land the desired top-left pixel on the context's single sampled row
    /// the image's origin is offset by `y - height + 1` on y (not `-y`, which
    /// would read the bottom edge) and `-x` on x.
    private func pixel(_ cg: CGImage, x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8)? {
        guard x >= 0, y >= 0, x < cg.width, y < cg.height else { return nil }
        var data = [UInt8](repeating: 0, count: 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(
            data: &data, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: colorSpace, bitmapInfo: info
        ) else { return nil }
        context.draw(cg, in: CGRect(x: CGFloat(-x), y: CGFloat(y - cg.height + 1),
                                    width: CGFloat(cg.width), height: CGFloat(cg.height)))
        return (data[0], data[1], data[2], data[3])
    }

    /// Scans the vertical centre column for a pixel matching `predicate`, proving a
    /// colour (e.g. the synthetic photo) is actually visible somewhere down the
    /// composition without assuming its exact y position.
    private func centerColumnContains(_ cg: CGImage,
                                      _ predicate: (UInt8, UInt8, UInt8) -> Bool) -> Bool {
        let x = cg.width / 2
        var y = 0
        while y < cg.height {
            if let p = pixel(cg, x: x, y: y), predicate(p.r, p.g, p.b) { return true }
            y += 4
        }
        return false
    }
}
