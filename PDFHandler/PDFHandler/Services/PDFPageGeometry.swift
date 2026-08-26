//
//  PDFPageGeometry.swift
//  PDFHandler
//
//  Shared page-geometry helpers so the on-screen preview and the
//  flattener use the exact same notion of "the page as displayed":
//  same size, same orientation. Anything the user positions against
//  the preview then lands identically in the exported PDF.
//
//  IMPORTANT — PDFKit already handles /Rotate, in both directions:
//    • bounds(for:) returns rotation-adjusted bounds, so a page with
//      /Rotate 90 already reports swapped width and height.
//    • draw(with:to:) already applies the rotation transform.
//
//  An earlier version of this file asserted the opposite and
//  compensated for rotation by hand. That double-applied it: the size
//  was swapped back to portrait while the content was rotated a second
//  time, so a perfectly straight scanned contract rendered sideways in
//  the preview and would have exported that way too. Do not "fix"
//  rotation here again without a rotated PDF in front of you — the
//  probe test in PDFHandlerTests pins the real behaviour.
//

import PDFKit
import CoreGraphics
import AppKit

extension PDFPage {
    /// The page's /Rotate value normalized into 0 / 90 / 180 / 270.
    /// Informational only: the geometry below must not act on it.
    var displayRotation: Int {
        ((rotation % 360) + 360) % 360
    }

    /// Size of the page as displayed. PDFKit has already applied
    /// /Rotate to these bounds.
    var displaySize: CGSize {
        bounds(for: .mediaBox).size
    }

    /// Draws the page content (including its existing annotations)
    /// into a bottom-left-origin context, filling
    /// (0, 0, displaySize.width, displaySize.height).
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
