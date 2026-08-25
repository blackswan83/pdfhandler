//
//  PDFFlattener.swift
//  PDFHandler
//
//  Burns Placement overlays into a copy of the PDF by re-drawing every
//  page into a fresh CGPDF context and compositing the overlays on
//  top. This produces genuinely flattened output: page content stays
//  vector, signatures are embedded bitmaps, text and checkboxes are
//  drawn as vector art — all visible in any PDF viewer.
//
//  (The previous implementation stamped a custom PDFAnnotation
//  subclass whose drawing only existed as a draw(with:in:) override.
//  PDFKit never serializes an appearance stream for that, so the saved
//  file showed empty stamps in Preview / Acrobat / Chrome.)
//

import Foundation
import PDFKit
import AppKit
import CoreText

enum PDFFlattenerError: LocalizedError {
    case cannotOpen
    case unknownSignature(UUID)
    case unreadableSignature(String)
    case writeFailed(URL)

    var errorDescription: String? {
        switch self {
        case .cannotOpen: return "Could not open the PDF."
        case .unknownSignature(let id): return "Signature \(id) is not in the library."
        case .unreadableSignature(let name): return "The signature \"\(name)\" could not be read. Re-add it to the library."
        case .writeFailed(let url): return "Failed to write signed PDF to \(url.path)."
        }
    }
}

struct PDFFlattener {

    /// Geometry / styling shared with the on-screen preview. Text is
    /// sized off the box height so preview and burn-in stay WYSIWYG.
    enum Style {
        static let textFontFactor: CGFloat = 0.6
        static let textInsetFactor: CGFloat = 0.12
    }

    /// Writes a copy of the (in-memory) `document` — the exact pages
    /// the user previewed — with every `placement` drawn into the
    /// page. Output name: `<original>_signed.pdf` next to the original.
    func flatten(
        document: PDFDocument,
        sourceURL: URL,
        placements: [Placement],
        signatures: [SavedSignature],
        outputSuffix: String = "_signed"
    ) throws -> URL {
        let byID = Dictionary(uniqueKeysWithValues: signatures.map { ($0.id, $0) })

        // Fail fast on dangling or unreadable signature references so a
        // field can never silently vanish from the signed output.
        for placement in placements {
            if let sigID = placement.content.referencedSignatureID {
                guard let entry = byID[sigID] else {
                    throw PDFFlattenerError.unknownSignature(sigID)
                }
                guard let image = entry.image,
                      image.cgImage(forProposedRect: nil, context: nil, hints: nil) != nil else {
                    throw PDFFlattenerError.unreadableSignature(entry.name)
                }
            }
        }

        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        let outputURL = sourceURL
            .deletingLastPathComponent()
            .appendingPathComponent("\(baseName)\(outputSuffix).pdf")

        let placementsByPage = Dictionary(grouping: placements, by: \.pageIndex)

        guard let ctx = CGContext(outputURL as CFURL, mediaBox: nil, nil) else {
            throw PDFFlattenerError.writeFailed(outputURL)
        }

        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            let display = page.displaySize
            guard display.width > 0, display.height > 0 else { continue }

            var mediaBox = CGRect(origin: .zero, size: display)
            ctx.beginPage(mediaBox: &mediaBox)
            page.drawDisplayOriented(in: ctx)
            for placement in placementsByPage[pageIndex] ?? [] {
                draw(placement, displaySize: display, library: byID, in: ctx)
            }
            ctx.endPage()
        }
        ctx.closePDF()

        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            throw PDFFlattenerError.writeFailed(outputURL)
        }
        return outputURL
    }

    /// Convert a normalized rect (top-left origin, 0…1) to PDF page
    /// coordinates (bottom-left origin, points) for a page displayed
    /// at `displaySize`.
    static func pdfRect(for normalized: CGRect, displaySize: CGSize) -> CGRect {
        CGRect(
            x: normalized.minX * displaySize.width,
            y: (1.0 - normalized.minY - normalized.height) * displaySize.height,
            width: normalized.width * displaySize.width,
            height: normalized.height * displaySize.height
        )
    }

    // MARK: - Drawing

    private func draw(
        _ placement: Placement,
        displaySize: CGSize,
        library: [UUID: SavedSignature],
        in ctx: CGContext
    ) {
        let rect = Self.pdfRect(for: placement.normalizedRect, displaySize: displaySize)
        guard rect.width > 0, rect.height > 0 else { return }

        switch placement.content {
        case .signature(let id), .initials(let id):
            guard let image = library[id]?.image,
                  let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
            else { return }
            ctx.saveGState()
            ctx.interpolationQuality = .high
            ctx.draw(cg, in: aspectFitRect(imageSize: CGSize(width: cg.width, height: cg.height), in: rect))
            ctx.restoreGState()

        case .date(let text, let style), .freeText(let text, let style):
            drawText(text, style: style, in: rect, context: ctx)

        case .checkbox(let isChecked):
            drawCheckbox(isChecked: isChecked, in: rect, context: ctx)
        }
    }

    /// The preview shows images aspect-fit inside their frame; mirror
    /// that here instead of stretching to the frame.
    private func aspectFitRect(imageSize: CGSize, in rect: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return rect }
        let imageAspect = imageSize.width / imageSize.height
        let rectAspect = rect.width / rect.height
        if imageAspect > rectAspect {
            let height = rect.width / imageAspect
            return CGRect(x: rect.minX, y: rect.midY - height / 2, width: rect.width, height: height)
        } else {
            let width = rect.height * imageAspect
            return CGRect(x: rect.midX - width / 2, y: rect.minY, width: width, height: rect.height)
        }
    }

    /// Vector text, left-aligned and vertically centered — exactly how
    /// PlacementView previews it. `rect` is already in page points, so
    /// a manual style size (also page points) is used unscaled.
    private func drawText(_ text: String, style: TextStyle, in rect: CGRect, context: CGContext) {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        let fontSize = style.resolvedSize(boxHeight: rect.height)
        let font = style.font.nsFont(size: fontSize)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): NSColor.black.cgColor,
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let line = CTLineCreateWithAttributedString(attributed as CFAttributedString)

        context.saveGState()
        context.clip(to: rect)
        let ascent = font.ascender
        let descent = -font.descender
        let baselineY = rect.midY - (ascent + descent) / 2 + descent
        context.textPosition = CGPoint(
            x: rect.minX + rect.height * Style.textInsetFactor,
            y: baselineY
        )
        CTLineDraw(line, context)
        context.restoreGState()
    }

    private func drawCheckbox(isChecked: Bool, in rect: CGRect, context: CGContext) {
        let side = min(rect.width, rect.height)
        guard side > 1 else { return }
        let inset = max(0.5, side * 0.08)
        let box = CGRect(
            x: rect.midX - side / 2 + inset,
            y: rect.midY - side / 2 + inset,
            width: side - inset * 2,
            height: side - inset * 2
        )

        context.saveGState()
        context.setStrokeColor(NSColor.black.cgColor)
        context.setLineWidth(max(0.75, side * 0.05))
        let radius = side * 0.08
        context.addPath(CGPath(roundedRect: box, cornerWidth: radius, cornerHeight: radius, transform: nil))
        context.strokePath()

        if isChecked {
            context.setLineWidth(max(1, side * 0.09))
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.move(to: CGPoint(x: box.minX + box.width * 0.18, y: box.minY + box.height * 0.52))
            context.addLine(to: CGPoint(x: box.minX + box.width * 0.42, y: box.minY + box.height * 0.30))
            context.addLine(to: CGPoint(x: box.minX + box.width * 0.82, y: box.minY + box.height * 0.72))
            context.strokePath()
        }
        context.restoreGState()
    }
}
