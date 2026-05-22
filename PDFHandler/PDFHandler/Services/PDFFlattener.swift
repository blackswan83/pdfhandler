//
//  PDFFlattener.swift
//  PDFHandler
//
//  Burns Placement overlays into a PDF copy, one image-stamp
//  annotation per placement. Handles all content kinds (signature,
//  initials, date, freeText, checkbox) by rasterizing whatever they
//  represent to an NSImage first and then stamping a single
//  annotation type — keeps the burn-in path narrow and predictable.
//

import Foundation
import PDFKit
import AppKit

enum PDFFlattenerError: LocalizedError {
    case cannotOpen
    case unknownSignature(UUID)
    case writeFailed(URL)

    var errorDescription: String? {
        switch self {
        case .cannotOpen: return "Could not open the PDF."
        case .unknownSignature(let id): return "Signature \(id) is not in the library."
        case .writeFailed(let url): return "Failed to write signed PDF to \(url.path)."
        }
    }
}

struct PDFFlattener {

    /// Writes a copy of `source` with every `placement` rendered as
    /// an image stamp annotation. Output name: `<original>_signed.pdf`
    /// next to the original.
    func flatten(
        source: URL,
        placements: [Placement],
        signatures: [SavedSignature]
    ) throws -> URL {
        guard let document = PDFDocument(url: source) else {
            throw PDFFlattenerError.cannotOpen
        }

        let byID = Dictionary(uniqueKeysWithValues: signatures.map { ($0.id, $0) })

        for placement in placements {
            guard placement.pageIndex >= 0,
                  placement.pageIndex < document.pageCount,
                  let page = document.page(at: placement.pageIndex)
            else { continue }

            guard let image = try renderImage(for: placement, pageSize: page.bounds(for: .mediaBox).size, library: byID) else {
                continue
            }

            let rect = Self.pdfRect(for: placement.normalizedRect, in: page)
            let annotation = StampImageAnnotation(bounds: rect, image: image)
            annotation.contents = placement.content.annotationContents
            page.addAnnotation(annotation)
        }

        let baseName = source.deletingPathExtension().lastPathComponent
        let outputURL = source
            .deletingLastPathComponent()
            .appendingPathComponent("\(baseName)_signed.pdf")

        guard document.write(to: outputURL) else {
            throw PDFFlattenerError.writeFailed(outputURL)
        }
        return outputURL
    }

    // MARK: - Rendering

    private func renderImage(
        for placement: Placement,
        pageSize: CGSize,
        library: [UUID: SavedSignature]
    ) throws -> NSImage? {
        switch placement.content {
        case .signature(let id), .initials(let id):
            guard let entry = library[id] else {
                throw PDFFlattenerError.unknownSignature(id)
            }
            return entry.image

        case .date(let text):
            let width = placement.normalizedRect.width * pageSize.width
            let height = placement.normalizedRect.height * pageSize.height
            return TextStampRenderer.render(text: text, targetSize: CGSize(width: width, height: height), fontSize: nil)

        case .freeText(let text, let fontSize):
            let width = placement.normalizedRect.width * pageSize.width
            let height = placement.normalizedRect.height * pageSize.height
            return TextStampRenderer.render(text: text, targetSize: CGSize(width: width, height: height), fontSize: fontSize)

        case .checkbox(let isChecked):
            let width = placement.normalizedRect.width * pageSize.width
            let height = placement.normalizedRect.height * pageSize.height
            return CheckboxStampRenderer.render(isChecked: isChecked, targetSize: CGSize(width: width, height: height))
        }
    }

    /// Convert a normalized rect (top-left origin, 0…1) to the page's
    /// PDF coordinate space (bottom-left origin, points).
    static func pdfRect(for normalized: CGRect, in page: PDFPage) -> CGRect {
        let bounds = page.bounds(for: .mediaBox)
        let w = normalized.width * bounds.width
        let h = normalized.height * bounds.height
        let x = normalized.minX * bounds.width + bounds.minX
        let y = bounds.minY + (1.0 - normalized.minY - normalized.height) * bounds.height
        return CGRect(x: x, y: y, width: w, height: h)
    }
}

// MARK: - Content extensions

private extension PlacementContent {
    var annotationContents: String {
        switch self {
        case .signature: return "Signature"
        case .initials:  return "Initials"
        case .date:      return "Date"
        case .freeText:  return "Text"
        case .checkbox:  return "Checkbox"
        }
    }
}

// MARK: - NSImage stamp annotation

/// Draws a bitmap image in the annotation's bounds. The stock
/// .stamp annotation can't directly render an NSImage, so we
/// override draw(with:in:) and composite the bitmap ourselves.
final class StampImageAnnotation: PDFAnnotation {
    private let stampImage: NSImage

    init(bounds: CGRect, image: NSImage) {
        self.stampImage = image
        super.init(bounds: bounds, forType: .stamp, withProperties: nil)
    }

    required init?(coder: NSCoder) { return nil }

    override func draw(with box: PDFDisplayBox, in context: CGContext) {
        guard let cg = stampImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        context.saveGState()
        context.interpolationQuality = .high
        context.draw(cg, in: bounds)
        context.restoreGState()
    }
}

// MARK: - Text stamp renderer

enum TextStampRenderer {
    /// Rasterizes `text` centered into an NSImage of the given size.
    /// Auto-picks a font size if `fontSize` is nil (scaled to fit).
    static func render(text: String, targetSize: CGSize, fontSize: CGFloat?) -> NSImage? {
        guard targetSize.width > 1, targetSize.height > 1 else { return nil }
        let image = NSImage(size: targetSize)
        image.lockFocus()
        defer { image.unlockFocus() }

        // Transparent background — PDF page shows through.
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: targetSize).fill()

        let resolvedSize: CGFloat
        if let fontSize = fontSize {
            resolvedSize = fontSize
        } else {
            // Fit-to-height: use ~60% of height as cap height, clamp.
            resolvedSize = max(10, min(targetSize.height * 0.6, 96))
        }

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byClipping

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: resolvedSize, weight: .regular),
            .foregroundColor: NSColor.black,
            .paragraphStyle: paragraph
        ]

        let attributed = NSAttributedString(string: text, attributes: attributes)
        let bounding = attributed.boundingRect(
            with: NSSize(width: targetSize.width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        let yOffset = max(0, (targetSize.height - bounding.height) / 2)
        attributed.draw(in: NSRect(
            x: 0,
            y: yOffset,
            width: targetSize.width,
            height: bounding.height
        ))
        return image
    }
}

// MARK: - Checkbox stamp renderer

enum CheckboxStampRenderer {
    static func render(isChecked: Bool, targetSize: CGSize) -> NSImage? {
        guard targetSize.width > 1, targetSize.height > 1 else { return nil }
        let image = NSImage(size: targetSize)
        image.lockFocus()
        defer { image.unlockFocus() }

        NSColor.clear.setFill()
        NSRect(origin: .zero, size: targetSize).fill()

        let side = min(targetSize.width, targetSize.height)
        let inset: CGFloat = max(1, side * 0.08)
        let rect = NSRect(
            x: (targetSize.width - side) / 2 + inset,
            y: (targetSize.height - side) / 2 + inset,
            width: side - inset * 2,
            height: side - inset * 2
        )

        NSColor.black.setStroke()
        let box = NSBezierPath(roundedRect: rect, xRadius: side * 0.08, yRadius: side * 0.08)
        box.lineWidth = max(1, side * 0.05)
        box.stroke()

        if isChecked {
            let checkmark = NSBezierPath()
            checkmark.move(to: NSPoint(x: rect.minX + rect.width * 0.18, y: rect.minY + rect.height * 0.52))
            checkmark.line(to: NSPoint(x: rect.minX + rect.width * 0.42, y: rect.minY + rect.height * 0.30))
            checkmark.line(to: NSPoint(x: rect.minX + rect.width * 0.82, y: rect.minY + rect.height * 0.72))
            checkmark.lineWidth = max(1.5, side * 0.09)
            checkmark.lineCapStyle = .round
            checkmark.lineJoinStyle = .round
            NSColor.black.setStroke()
            checkmark.stroke()
        }

        return image
    }
}
