//
//  PDFHandlerTests.swift
//  PDFHandlerTests
//

import XCTest
import PDFKit
@testable import PDFHandler

final class PDFHandlerTests: XCTestCase {

    // MARK: - Coordinate mapping

    func testPdfRectFlipsYAndScales() {
        let display = CGSize(width: 600, height: 800)
        let normalized = CGRect(x: 0.25, y: 0.10, width: 0.5, height: 0.05)

        let rect = PDFFlattener.pdfRect(for: normalized, displaySize: display)

        XCTAssertEqual(rect.minX, 150, accuracy: 0.001)
        XCTAssertEqual(rect.width, 300, accuracy: 0.001)
        XCTAssertEqual(rect.height, 40, accuracy: 0.001)
        // Top-left normalized y=0.10 → bottom-left PDF y = (1 - 0.10 - 0.05) * 800
        XCTAssertEqual(rect.minY, 680, accuracy: 0.001)
    }

    func testPdfRectRoundTripsFullPage() {
        let display = CGSize(width: 612, height: 792)
        let rect = PDFFlattener.pdfRect(
            for: CGRect(x: 0, y: 0, width: 1, height: 1),
            displaySize: display
        )
        XCTAssertEqual(rect, CGRect(origin: .zero, size: display))
    }

    // MARK: - Page display geometry

    /// PDFKit's bounds(for:) is RAW — it does not apply /Rotate. So
    /// displaySize has to swap, and this test is what proves it rather
    /// than assuming: asserting the opposite shipped a real bug.
    func testPDFKitBoundsAreRawAndDoNotApplyPageRotation() {
        let page = PDFPage()
        let upright = page.bounds(for: .mediaBox).size

        page.rotation = 90
        XCTAssertEqual(page.bounds(for: .mediaBox).size, upright,
                       "bounds(for:) is raw; if this changes, displaySize must stop swapping")
    }

    func testDisplaySizeSwapsForQuarterTurns() {
        let page = PDFPage()
        let box = page.bounds(for: .mediaBox)

        page.rotation = 0
        XCTAssertEqual(page.displaySize, box.size)
        page.rotation = 180
        XCTAssertEqual(page.displaySize, box.size)

        for quarter in [90, 270] {
            page.rotation = quarter
            XCTAssertEqual(page.displaySize,
                           CGSize(width: box.height, height: box.width),
                           "\(quarter)° must swap width and height")
        }
    }

    func testDisplayRotationNormalizesNegativeValues() {
        let page = PDFPage()
        page.rotation = -90
        XCTAssertEqual(page.displayRotation, 270)
    }

    /// The test that would have caught the sideways-page bug: render a
    /// page whose bottom half is black, rotate it a quarter turn, and
    /// check where the black actually lands.
    ///
    /// After a quarter turn the split must run vertically — black on
    /// one side, white on the other. If rotation is applied twice the
    /// split stays horizontal (black ends up top instead of bottom),
    /// which is exactly the failure this pins. Deliberately agnostic
    /// about WHICH side, so it tests the invariant rather than a guess.
    func testQuarterTurnedPageIsRotatedExactlyOnce() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("rotation-probe-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: url) }

        var box = CGRect(x: 0, y: 0, width: 200, height: 400)
        guard let pdf = CGContext(url as CFURL, mediaBox: &box, nil) else {
            return XCTFail("could not create the probe PDF")
        }
        pdf.beginPage(mediaBox: &box)
        pdf.setFillColor(CGColor(gray: 0, alpha: 1))
        pdf.fill(CGRect(x: 0, y: 0, width: 200, height: 200))   // bottom half
        pdf.endPage()
        pdf.closePDF()

        guard let document = PDFDocument(url: url), let page = document.page(at: 0) else {
            return XCTFail("could not reopen the probe PDF")
        }
        page.rotation = 90

        let display = page.displaySize
        XCTAssertEqual(display.width, 400, accuracy: 0.5, "quarter turn should report landscape")
        XCTAssertEqual(display.height, 200, accuracy: 0.5)

        guard let image = page.renderedDisplayImage(pixelSize: display, pointSize: display),
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let samples = Self.brightness(of: cg)
        else { return XCTFail("could not rasterize the probe page") }

        let w = cg.width, h = cg.height
        let left   = samples(w / 4,     h / 2)
        let right  = samples(3 * w / 4, h / 2)
        let top    = samples(w / 2,     h / 4)
        let bottom = samples(w / 2,     3 * h / 4)

        XCTAssertGreaterThan(abs(left - right), 0.5,
                             "a quarter turn must put the black half on one SIDE")
        XCTAssertLessThan(abs(top - bottom), 0.25,
                          "the split must not still be horizontal — that means rotation was applied twice")
    }

    /// Returns a sampler giving 0…1 brightness at a pixel.
    private static func brightness(of image: CGImage) -> ((Int, Int) -> Double)? {
        let w = image.width, h = image.height
        guard w > 0, h > 0, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        let drew: Bool = bytes.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress,
                  let ctx = CGContext(data: base, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: w * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
            else { return false }
            ctx.setFillColor(CGColor(gray: 1, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drew else { return nil }
        return { x, y in
            let px = min(max(x, 0), w - 1), py = min(max(y, 0), h - 1)
            let i = (py * w + px) * 4
            return (Double(bytes[i]) + Double(bytes[i + 1]) + Double(bytes[i + 2])) / (3 * 255)
        }
    }

    // MARK: - Placement equality (drives one-undo-per-gesture)

    func testPlacementEquatable() {
        let placement = Placement(
            content: .freeText(text: "hello", style: .default),
            pageIndex: 0,
            normalizedRect: CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.05)
        )
        var moved = placement
        XCTAssertEqual(placement, moved)

        moved.normalizedRect.origin.x = 0.5
        XCTAssertNotEqual(placement, moved)

        var retyped = placement
        retyped.content = .freeText(text: "changed", style: .default)
        XCTAssertNotEqual(placement, retyped)
    }

    // MARK: - Zoom stepping

    func testZoomStepsWalkTheStopsFromAnArbitraryFitScale() {
        // Typical fit scale for a Letter page in a laptop-sized pane.
        XCTAssertEqual(ZoomScale.stop(above: 0.78), 1.0)
        XCTAssertEqual(ZoomScale.stop(below: 0.78), 0.75)

        XCTAssertEqual(ZoomScale.stop(above: 1.0), 1.25)
        XCTAssertEqual(ZoomScale.stop(below: 1.0), 0.75)
    }

    func testZoomStepsClampAtTheEnds() {
        XCTAssertEqual(ZoomScale.stop(above: ZoomScale.max), ZoomScale.max)
        XCTAssertEqual(ZoomScale.stop(below: ZoomScale.min), ZoomScale.min)
    }

    func testZoomStepsDoNotStickOnAnExactStop() {
        // Landing exactly on a stop must still advance, not return the
        // same value (the tolerance guards float noise, not progress).
        for stop in ZoomScale.stops where stop < ZoomScale.max {
            XCTAssertGreaterThan(ZoomScale.stop(above: stop), stop)
        }
        for stop in ZoomScale.stops where stop > ZoomScale.min {
            XCTAssertLessThan(ZoomScale.stop(below: stop), stop)
        }
    }

    func testZoomClampBoundsBothEnds() {
        XCTAssertEqual(ZoomScale.clamp(0.01), ZoomScale.min)
        XCTAssertEqual(ZoomScale.clamp(99), ZoomScale.max)
        XCTAssertEqual(ZoomScale.clamp(1.5), 1.5)
    }

    // MARK: - Ghostscript argument construction

    /// Ghostscript applies options left to right and -dPDFSETTINGS
    /// assigns a whole bundle of Distiller parameters when read, so an
    /// override placed before it is silently discarded. This ordering
    /// is the whole reason the presets used to leave images untouched.
    func testEveryOverrideFollowsThePreset() {
        let args = CompressionService.buildArguments(
            input: "/tmp/in.pdf",
            output: "/tmp/out.pdf",
            preset: .ebook,
            grayscale: true,
            imageDPI: nil
        )
        guard let presetIndex = args.firstIndex(where: { $0.hasPrefix("-dPDFSETTINGS=") }) else {
            return XCTFail("no preset argument emitted")
        }
        for override in [
            "-dCompatibilityLevel=1.7",
            "-dDownsampleColorImages=true",
            "-dColorImageResolution=150",
            "-dDetectDuplicateImages=true",
            "-dAutoRotatePages=/None",
            "-sColorConversionStrategy=Gray",
        ] {
            guard let index = args.firstIndex(of: override) else {
                return XCTFail("missing argument \(override)")
            }
            XCTAssertGreaterThan(index, presetIndex, "\(override) must come after -dPDFSETTINGS")
        }
    }

    func testImageDPIOverridesThePresetResolution() {
        let args = CompressionService.buildArguments(
            input: "/tmp/in.pdf",
            output: "/tmp/out.pdf",
            preset: .printer,          // 300 DPI preset
            grayscale: false,
            imageDPI: 90               // target-size search picked 90
        )
        XCTAssertTrue(args.contains("-dColorImageResolution=90"))
        XCTAssertTrue(args.contains("-dGrayImageResolution=90"))
        // Bilevel scanned text keeps its own floor so it stays legible.
        XCTAssertTrue(args.contains("-dMonoImageResolution=300"))
    }

    func testInputIsTheFinalArgumentAndOutputIsFlagged() {
        let args = CompressionService.buildArguments(
            input: "/tmp/in.pdf",
            output: "/tmp/out.pdf",
            preset: .screen,
            grayscale: false,
            imageDPI: nil
        )
        XCTAssertEqual(args.last, "/tmp/in.pdf")
        XCTAssertTrue(args.contains("-sOutputFile=/tmp/out.pdf"))
        XCTAssertTrue(args.contains("-dSAFER"))
    }

    func testGrayscaleFlagsOnlyAppearWhenRequested() {
        let colour = CompressionService.buildArguments(
            input: "/tmp/in.pdf", output: "/tmp/out.pdf",
            preset: .ebook, grayscale: false, imageDPI: nil
        )
        XCTAssertFalse(colour.contains("-sColorConversionStrategy=Gray"))
    }

    func testContentTraits() {
        XCTAssertTrue(PlacementContent.signature(signatureID: UUID()).keepsAspectRatio)
        XCTAssertTrue(PlacementContent.checkbox(isChecked: false).keepsAspectRatio)
        XCTAssertFalse(PlacementContent.freeText(text: "", style: .default).keepsAspectRatio)
        XCTAssertTrue(PlacementContent.date(text: "x", style: .default).isTextEditable)
        XCTAssertFalse(PlacementContent.checkbox(isChecked: true).isTextEditable)
    }

    // MARK: - Text styling

    func testAutoFitTracksBoxHeightAndManualDoesNot() {
        var style = TextStyle(font: .system, size: 12, autoFit: true)
        // The factor is shared with the flattener, so preview and
        // export agree by construction.
        XCTAssertEqual(style.resolvedSize(boxHeight: 40),
                       40 * PDFFlattener.Style.textFontFactor, accuracy: 0.001)
        XCTAssertEqual(style.resolvedSize(boxHeight: 20),
                       20 * PDFFlattener.Style.textFontFactor, accuracy: 0.001)

        style.autoFit = false
        XCTAssertEqual(style.resolvedSize(boxHeight: 40), 12)
        XCTAssertEqual(style.resolvedSize(boxHeight: 20), 12)
    }

    func testManualSizeIsClamped() {
        var style = TextStyle(font: .system, size: 500, autoFit: false)
        XCTAssertEqual(style.resolvedSize(boxHeight: 30), TextStyle.maxSize)
        style.size = 0.1
        XCTAssertEqual(style.resolvedSize(boxHeight: 30), TextStyle.minSize)
    }

    func testEditingTextPreservesTypographyAndViceVersa() {
        let content = PlacementContent.freeText(text: "Nuraxi Ltd", style: .default)

        var style = TextStyle.default
        style.font = .courier
        style.autoFit = false
        let restyled = content.withStyle(style)
        XCTAssertEqual(restyled.textPayload?.text, "Nuraxi Ltd")
        XCTAssertEqual(restyled.textPayload?.style.font, .courier)

        let retexted = restyled.withText("Acme")
        XCTAssertEqual(retexted.textPayload?.text, "Acme")
        XCTAssertEqual(retexted.textPayload?.style.font, .courier,
                       "typing must not reset typography")
        XCTAssertEqual(retexted.textPayload?.style.autoFit, false)
    }

    func testStyleHelpersAreNoOpsForNonTextContent() {
        let checkbox = PlacementContent.checkbox(isChecked: true)
        XCTAssertNil(checkbox.textPayload)
        XCTAssertEqual(checkbox.withText("x"), checkbox)
        XCTAssertEqual(checkbox.withStyle(.default), checkbox)
    }

    func testEveryTypefaceResolvesToARealFont() {
        for choice in TextFont.allCases {
            let font = choice.nsFont(size: 14)
            XCTAssertEqual(font.pointSize, 14, accuracy: 0.001, "\(choice) lost its size")
        }
    }

    // MARK: - Compress modes

    func testTargetSizeIsItsOwnModeStartingFromHighQuality() {
        XCTAssertTrue(CompressMode.targetSize.isTargetSize)
        XCTAssertNil(CompressMode.targetSize.typicalRange,
                     "target size names an exact figure, not a typical range")
        // The search walks down from a high ceiling, buying back as
        // much quality as the target allows.
        XCTAssertEqual(CompressMode.targetSize.preset.imageResolution, 300)

        for mode in CompressMode.allCases where !mode.isTargetSize {
            XCTAssertNotNil(mode.typicalRange, "\(mode) should advertise a typical range")
        }
    }
}
