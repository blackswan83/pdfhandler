//
//  PDFPageRenderer.swift
//  PDFHandler
//
//  Renders a PDFPage into an NSImage at a specified DPI. Used by the
//  Markdown converter for OCR input and image extraction.
//

import Foundation
import PDFKit
import AppKit

enum PDFPageRenderer {
    /// Render the page *as displayed* (page /Rotate applied — scanned
    /// PDFs are very often rotated, and OCR on sideways glyphs returns
    /// garbage) at the given DPI. The bitmap scale is exact and
    /// machine-independent, unlike lockFocus which silently adopts the
    /// main screen's backing factor. Returns nil for degenerate bounds.
    static func render(page: PDFPage, dpi: CGFloat = 150) throws -> NSImage? {
        let display = page.displaySize
        guard display.width > 0, display.height > 0 else { return nil }
        let scale = dpi / 72.0
        let pixelSize = CGSize(
            width: display.width * scale,
            height: display.height * scale
        )
        return page.renderedDisplayImage(pixelSize: pixelSize, pointSize: display)
    }
}
