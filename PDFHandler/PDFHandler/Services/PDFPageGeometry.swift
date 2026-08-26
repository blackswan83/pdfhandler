//
//  PDFPageGeometry.swift
//  PDFHandler
//
//  Shared page-geometry helpers so the on-screen preview and the
//  flattener use the exact same notion of "the page as displayed":
//  same size, same orientation. Anything the user positions against
//  the preview then lands identically in the exported PDF.
//
//  IMPORTANT — PDFKit splits /Rotate handling, and the two halves do
//  NOT behave the same way. Both facts below are measured by probe
//  tests in PDFHandlerTests, not assumed:
//    • bounds(for:) is RAW. A 612x792 page with /Rotate 90 still
//      reports 612x792, so the swap has to be done here.
//    • draw(with:to:) ALREADY applies the rotation transform, so
//      rotating the context by hand as well double-applies it.
//
//  Getting this backwards has now caused a real bug in each direction:
//  first a hand-rolled rotation on top of PDFKit's, which rendered
//  straight scanned contracts sideways; then, over-correcting, trusting
//  bounds(for:) to swap when it does not. Do not change this without a
//  failing probe test in front of you.
//

import PDFKit
import CoreGraphics
import AppKit

extension PDFPage {
    /// The page's /Rotate value normalized into 0 / 90 / 180 / 270.
    var displayRotation: Int {
        ((rotation % 360) + 360) % 360
    }

    /// Size of the page as displayed. bounds(for:) is raw, so quarter
    /// turns swap width and height here.
    var displaySize: CGSize {
        let box = bounds(for: .mediaBox)
        return displayRotation % 180 == 0
            ? CGSize(width: box.width, height: box.height)
            : CGSize(width: box.height, height: box.width)
    }

    /// Draws the page content (including its existing annotations)
    /// into a bottom-left-origin context, filling
    /// (0, 0, displaySize.width, displaySize.height).
    ///
    /// No rotation transform: draw(with:to:) performs it already.
    func drawDisplayOriented(in ctx: CGContext) {
        ctx.saveGState()
        draw(with: .mediaBox, to: ctx)
        ctx.restoreGState()
    }

    /// Rasterize the displayed page (white background, correctly
    /// oriented) into a bitmap of exactly `pixelSize` pixels, returned
    /// as an NSImage reporting `pointSize`. Pure CGBitmapContext: the
    /// scale is deterministic (lockFocus silently picks the main
    /// screen's backing factor) and it is safe off the main thread,
    /// which the OCR path relies on.
    func renderedDisplayImage(pixelSize: CGSize, pointSize: CGSize) -> NSImage? {
        let width = max(1, Int(pixelSize.width.rounded()))
        let height = max(1, Int(pixelSize.height.rounded()))
        let display = displaySize
        guard display.width > 0, display.height > 0,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }

        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        ctx.interpolationQuality = .high
        ctx.scaleBy(x: CGFloat(width) / display.width, y: CGFloat(height) / display.height)
        drawDisplayOriented(in: ctx)

        guard let cgImage = ctx.makeImage() else { return nil }
        return NSImage(cgImage: cgImage, size: pointSize)
    }
}
