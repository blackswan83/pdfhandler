//
//  SignatureIdentity.swift
//  PDFHandler
//
//  Persisted signature + initials pair. DocuSign-style identity:
//  the user sets these once and reuses them across documents.
//

import Foundation
import AppKit
import SwiftUI

enum SignatureSource: String, Codable {
    case drawn
    case typed
    case image
}

struct SignatureAsset: Codable, Equatable {
    let source: SignatureSource
    let imageData: Data
    let createdAt: Date
    let typedName: String?
    let typedStyle: String?

    init(
        source: SignatureSource,
        imageData: Data,
        typedName: String? = nil,
        typedStyle: String? = nil,
        createdAt: Date = Date()
    ) {
        self.source = source
        self.imageData = imageData
        self.typedName = typedName
        self.typedStyle = typedStyle
        self.createdAt = createdAt
    }

    var image: NSImage? { NSImage(data: imageData) }

    var aspectRatio: CGFloat {
        guard let size = image?.size, size.height > 0 else { return 3 }
        return size.width / size.height
    }
}

struct SignatureIdentity: Codable, Equatable {
    var signature: SignatureAsset?
    var initials: SignatureAsset?

    enum Slot { case signature, initials }

    var isEmpty: Bool { signature == nil && initials == nil }
}

@MainActor
final class SignatureIdentityStore: ObservableObject {
    @Published private(set) var identity = SignatureIdentity()

    private let fileURL: URL = {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = base.appendingPathComponent("PDFHandler", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("identity.json")
    }()

    init() { load() }

    func set(_ asset: SignatureAsset, for slot: SignatureIdentity.Slot) {
        switch slot {
        case .signature: identity.signature = asset
        case .initials:  identity.initials  = asset
        }
        save()
    }

    func clear(_ slot: SignatureIdentity.Slot) {
        switch slot {
        case .signature: identity.signature = nil
        case .initials:  identity.initials  = nil
        }
        save()
    }

    func clearAll() {
        identity = SignatureIdentity()
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(SignatureIdentity.self, from: data)
        else { return }
        identity = decoded
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(identity)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            #if DEBUG
            print("SignatureIdentityStore save failed: \(error)")
            #endif
        }
    }
}

// MARK: - Rendering

enum SignatureRenderer {

    /// Render a typed name to a transparent-background PNG-ready NSImage.
    static func renderTyped(_ name: String, style: SignatureFontStyle) -> NSImage {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let font = NSFont(name: style.fontName, size: style.fontSize)
            ?? NSFont.systemFont(ofSize: style.fontSize)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black
        ]

        let textSize = (trimmed as NSString).size(withAttributes: attrs)
        let pad: CGFloat = 16
        let canvas = NSSize(
            width: max(64, ceil(textSize.width) + pad * 2),
            height: max(32, ceil(textSize.height) + pad * 2)
        )

        let image = NSImage(size: canvas)
        image.lockFocus()
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: canvas).fill()
        (trimmed as NSString).draw(
            at: NSPoint(x: pad, y: pad),
            withAttributes: attrs
        )
        image.unlockFocus()
        return trimmedToContent(image) ?? image
    }

    /// Render accumulated strokes to a transparent-background NSImage, cropped to ink bounds.
    static func renderStrokes(
        _ paths: [Path],
        canvasSize: CGSize,
        lineWidth: CGFloat = 2.4
    ) -> NSImage? {
        guard !paths.isEmpty, canvasSize.width > 0, canvasSize.height > 0 else { return nil }

        let image = NSImage(size: canvasSize)
        image.lockFocus()
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: canvasSize).fill()

        // Flip the coordinate system: SwiftUI paths use top-left origin;
        // AppKit drawing uses bottom-left. Mirror Y so strokes appear right-side up.
        let ctx = NSGraphicsContext.current?.cgContext
        ctx?.saveGState()
        ctx?.translateBy(x: 0, y: canvasSize.height)
        ctx?.scaleBy(x: 1, y: -1)

        NSColor.black.setStroke()
        for path in paths {
            let bezier = NSBezierPath()
            bezier.lineWidth = lineWidth
            bezier.lineCapStyle = .round
            bezier.lineJoinStyle = .round
            path.forEach { element in
                switch element {
                case .move(to: let p):
                    bezier.move(to: p)
                case .line(to: let p):
                    bezier.line(to: p)
                case .quadCurve(to: let p, control: let c):
                    bezier.curve(to: p, controlPoint1: c, controlPoint2: c)
                case .curve(to: let p, control1: let c1, control2: let c2):
                    bezier.curve(to: p, controlPoint1: c1, controlPoint2: c2)
                case .closeSubpath:
                    bezier.close()
                }
            }
            bezier.stroke()
        }
        ctx?.restoreGState()
        image.unlockFocus()
        return trimmedToContent(image) ?? image
    }

    /// Best-effort background removal for imported photos of a signature on paper.
    /// Converts near-white pixels to transparent, preserves ink.
    static func removeWhiteBackground(_ image: NSImage, threshold: UInt8 = 220) -> NSImage {
        let size = image.size
        let w = Int(size.width), h = Int(size.height)
        guard w > 0, h > 0 else { return image }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerRow = w * 4
        var buffer = [UInt8](repeating: 0, count: bytesPerRow * h)

        guard let ctx = CGContext(
            data: &buffer,
            width: w, height: h,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return image }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        image.draw(in: NSRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()

        for i in stride(from: 0, to: buffer.count, by: 4) {
            let r = buffer[i], g = buffer[i + 1], b = buffer[i + 2]
            if r >= threshold && g >= threshold && b >= threshold {
                buffer[i + 3] = 0
            } else {
                let darkness = 255 - min(r, min(g, b))
                let alpha = UInt8(min(255, Int(darkness) * 2))
                buffer[i]     = 0
                buffer[i + 1] = 0
                buffer[i + 2] = 0
                buffer[i + 3] = alpha
            }
        }

        guard let cg = ctx.makeImage() else { return image }
        let result = NSImage(cgImage: cg, size: size)
        return trimmedToContent(result) ?? result
    }

    /// Crop an image to the bounding box of its non-transparent pixels.
    static func trimmedToContent(_ image: NSImage) -> NSImage? {
        let size = image.size
        let w = Int(size.width), h = Int(size.height)
        guard w > 0, h > 0 else { return nil }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerRow = w * 4
        var buffer = [UInt8](repeating: 0, count: bytesPerRow * h)

        guard let ctx = CGContext(
            data: &buffer,
            width: w, height: h,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        image.draw(in: NSRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()

        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h {
            let rowStart = y * bytesPerRow
            for x in 0..<w {
                let alpha = buffer[rowStart + x * 4 + 3]
                if alpha > 8 {
                    if x < minX { minX = x }
                    if x > maxX { maxX = x }
                    if y < minY { minY = y }
                    if y > maxY { maxY = y }
                }
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }

        let cropRect = CGRect(
            x: minX,
            y: minY,
            width: maxX - minX + 1,
            height: maxY - minY + 1
        )
        guard let cg = ctx.makeImage()?.cropping(to: cropRect) else { return nil }
        return NSImage(cgImage: cg, size: cropRect.size)
    }

    static func pngData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    static func asset(
        source: SignatureSource,
        image: NSImage,
        typedName: String? = nil,
        typedStyle: SignatureFontStyle? = nil
    ) -> SignatureAsset? {
        guard let png = pngData(from: image) else { return nil }
        return SignatureAsset(
            source: source,
            imageData: png,
            typedName: typedName,
            typedStyle: typedStyle?.rawValue
        )
    }
}
