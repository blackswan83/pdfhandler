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
import AppKit

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

    /// Rasterize the displayed page (white background, /Rotate applied)
    /// into a bitmap of exactly `pixelSize` pixels, returned as an
    /// NSImage reporting `pointSize`. Pure CGBitmapContext: the scale
    /// is deterministic (lockFocus silently picks the main screen's
    /// backing factor) and it is safe off the main thread, which the
    /// OCR path relies on.
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
