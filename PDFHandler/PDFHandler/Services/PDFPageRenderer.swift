//
//  PDFPageRenderer.swift
//  PDFHandler
//
//  Renders a PDFPage into an NSImage at a specified DPI. Used by the
//  Markdown converter (for OCR input and image extraction) and by the
//  sign-mode preview.
//

import Foundation
import PDFKit
import AppKit

enum PDFPageRenderer {
    /// Render a page at the given DPI (default 150). Returns nil if
    /// the page has a degenerate bounds.
    static func render(page: PDFPage, dpi: CGFloat = 150) throws -> NSImage? {
        let pointBounds = page.bounds(for: .mediaBox)
        guard pointBounds.width > 0, pointBounds.height > 0 else { return nil }

        let scale = dpi / 72.0
        let pixelSize = NSSize(
            width:  pointBounds.width  * scale,
            height: pointBounds.height * scale
        )

        let image = NSImage(size: pixelSize)
        image.lockFocus()
        defer { image.unlockFocus() }

        guard let ctx = NSGraphicsContext.current?.cgContext else { return nil }
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(CGRect(origin: .zero, size: pixelSize))
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: -pointBounds.origin.x, y: -pointBounds.origin.y)
        page.draw(with: .mediaBox, to: ctx)
        return image
    }
}
