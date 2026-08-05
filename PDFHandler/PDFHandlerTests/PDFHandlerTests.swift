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

    func testDisplaySizeSwapsForQuarterRotations() {
        let page = PDFPage()
        let box = page.bounds(for: .mediaBox)

        page.rotation = 0
        XCTAssertEqual(page.displaySize, box.size)

        page.rotation = 90
        XCTAssertEqual(page.displaySize, CGSize(width: box.height, height: box.width))

        page.rotation = 270
        XCTAssertEqual(page.displaySize, CGSize(width: box.height, height: box.width))

        page.rotation = -90
        XCTAssertEqual(page.displayRotation, 270)
    }

    // MARK: - Placement equality (drives one-undo-per-gesture)

    func testPlacementEquatable() {
        let placement = Placement(
            content: .freeText(text: "hello"),
            pageIndex: 0,
            normalizedRect: CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.05)
        )
        var moved = placement
        XCTAssertEqual(placement, moved)

        moved.normalizedRect.origin.x = 0.5
        XCTAssertNotEqual(placement, moved)

        var retyped = placement
        retyped.content = .freeText(text: "changed")
        XCTAssertNotEqual(placement, retyped)
    }

    // MARK: - Zoom stepping

    func testZoomStepsWalkTheStopsFromAnArbitraryFitScale() {
        // Typical fit scale for a Letter page in a laptop-sized pane.
        XCTAssertEqual(AppState.zoomStop(above: 0.78), 1.0)
        XCTAssertEqual(AppState.zoomStop(below: 0.78), 0.75)

        XCTAssertEqual(AppState.zoomStop(above: 1.0), 1.25)
        XCTAssertEqual(AppState.zoomStop(below: 1.0), 0.75)
    }

    func testZoomStepsClampAtTheEnds() {
        XCTAssertEqual(AppState.zoomStop(above: AppState.maxZoom), AppState.maxZoom)
        XCTAssertEqual(AppState.zoomStop(below: AppState.minZoom), AppState.minZoom)
    }

    func testZoomStepsDoNotStickOnAnExactStop() {
        // Landing exactly on a stop must still advance, not return the
        // same value (the tolerance guards float noise, not progress).
        for stop in AppState.zoomStops where stop < AppState.maxZoom {
            XCTAssertGreaterThan(AppState.zoomStop(above: stop), stop)
        }
        for stop in AppState.zoomStops where stop > AppState.minZoom {
            XCTAssertLessThan(AppState.zoomStop(below: stop), stop)
        }
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
        XCTAssertFalse(PlacementContent.freeText(text: "").keepsAspectRatio)
        XCTAssertTrue(PlacementContent.date(text: "x").isTextEditable)
        XCTAssertFalse(PlacementContent.checkbox(isChecked: true).isTextEditable)
    }
}
