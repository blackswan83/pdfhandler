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

    func testContentTraits() {
        XCTAssertTrue(PlacementContent.signature(signatureID: UUID()).keepsAspectRatio)
        XCTAssertTrue(PlacementContent.checkbox(isChecked: false).keepsAspectRatio)
        XCTAssertFalse(PlacementContent.freeText(text: "").keepsAspectRatio)
        XCTAssertTrue(PlacementContent.date(text: "x").isTextEditable)
        XCTAssertFalse(PlacementContent.checkbox(isChecked: true).isTextEditable)
    }
}
