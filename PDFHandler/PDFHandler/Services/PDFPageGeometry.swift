//
//  PDFPageGeometry.swift
//  PDFHandler
//
//  Shared page-geometry helpers so the on-screen preview and the
//  flattener use the exact same notion of "the page as displayed":
//  same size, same /Rotate handling, same origin. Anything the user
//  positions against the preview then lands identically in the
//  exported PDF.
//

import PDFKit
import CoreGraphics

extension PDFPage {
    /// The page's /Rotate value normalized into 0 / 90 / 180 / 270.
    var displayRotation: Int {
        ((rotation % 360) + 360) % 360
    }

    /// Size of the page as displayed: the mediaBox with /Rotate
    /// applied (90° / 270° swap width and height).
    var displaySize: CGSize {
        let box = bounds(for: .mediaBox)
        return displayRotation % 180 == 0
            ? CGSize(width: box.width, height: box.height)
            : CGSize(width: box.height, height: box.width)
    }

    /// Draws the page content (including its existing annotations)
    /// into a bottom-left-origin context so it occupies the rect
    /// (0, 0, displaySize.width, displaySize.height).
    ///
    /// PDFPage.draw(with:to:) renders raw page space: it neither
    /// applies /Rotate nor normalizes a non-zero mediaBox origin, so
    /// both are compensated here.
    func drawDisplayOriented(in ctx: CGContext) {
        let box = bounds(for: .mediaBox)
        let display = displaySize
        ctx.saveGState()
        switch displayRotation {
        case 90:
            ctx.translateBy(x: 0, y: display.height)
            ctx.rotate(by: -.pi / 2)
        case 180:
            ctx.translateBy(x: display.width, y: display.height)
            ctx.rotate(by: .pi)
        case 270:
            ctx.translateBy(x: display.width, y: 0)
            ctx.rotate(by: .pi / 2)
        default:
            break
        }
        ctx.translateBy(x: -box.minX, y: -box.minY)
        draw(with: .mediaBox, to: ctx)
        ctx.restoreGState()
    }
}
