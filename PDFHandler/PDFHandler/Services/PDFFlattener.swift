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
        case .writeFailed(let url): return "Could not write the PDF to \(url.path)."
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

    /// Writes a copy of the (in-memory) `document` in which the added
    /// text fields are REAL, editable PDF form fields instead of being
    /// burned into the page: signature / initials images and checkboxes
    /// are still flattened (an image can't be "editable"), but every
    /// date / freeText placement becomes an AcroForm text widget
    /// carrying the same text, font size, and rect as the preview, so
    /// the recipient can tweak the wording in Preview / Acrobat.
    /// Empty text boxes are included as blank fillable fields.
    ///
    /// Two passes by necessity: the flatten pass renders through a
    /// CGPDF context, which drops annotations, so the widgets are
    /// attached afterwards to the flattened copy.
    func writeEditable(
        document: PDFDocument,
        placements: [Placement],
        signatures: [SavedSignature],
        to outputURL: URL
    ) throws {
        let textPlacements = placements.filter { $0.content.textPayload != nil }
        let visualPlacements = placements.filter { $0.content.textPayload == nil }

        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".pdf")
        defer { try? FileManager.default.removeItem(at: temp) }
        try flatten(
            document: document,
            placements: visualPlacements,
            signatures: signatures,
            to: temp
        )

        guard let editable = PDFDocument(url: temp) else {
            throw PDFFlattenerError.cannotOpen
        }
        for placement in textPlacements {
            guard let page = editable.page(at: placement.pageIndex) else { continue }
            page.addAnnotation(textWidget(for: placement, on: page))
        }

        guard editable.write(to: outputURL) else {
            throw PDFFlattenerError.writeFailed(outputURL)
        }
    }

    /// An AcroForm text widget mirroring a text placement. PDFKit
    /// expects annotation bounds in RAW media-box space and applies
    /// /Rotate itself at render and write time — the same split
    /// documented in PDFPageGeometry — so the display-space rect is
    /// converted back through `rawRect`.
    private func textWidget(for placement: Placement, on page: PDFPage) -> PDFAnnotation {
        let display = Self.pdfRect(for: placement.normalizedRect, displaySize: page.displaySize)
        guard let payload = placement.content.textPayload else {
            // Unreachable: callers filter to text placements first.
            return PDFAnnotation(bounds: .zero, forType: .widget, withProperties: nil)
        }

        let annotation = PDFAnnotation(
            bounds: Self.rawRect(forDisplayRect: display, page: page),
            forType: .widget,
            withProperties: nil
        )
        annotation.widgetFieldType = .text
        annotation.widgetStringValue = payload.text
        annotation.fieldName = "pdfhandler-text-\(placement.id.uuidString)"
        // Same sizing math as drawText: auto-fit derives from the box
        // height in page points; a manual size is used unscaled.
        let fontSize = payload.style.autoFit
            ? payload.style.resolvedSize(boxHeight: display.height)
            : payload.style.size
        annotation.font = payload.style.font.nsFont(size: fontSize)
        annotation.fontColor = .black
        annotation.backgroundColor = .clear
        annotation.alignment = .left
        return annotation
    }

    /// Convert a display-space rect (bottom-left origin, /Rotate
    /// applied) back to RAW media-box space — the coordinate system
    /// PDFKit stores annotation bounds in. Exact inverse of
    /// `displayRect(forRawRect:page:)`.
    static func rawRect(forDisplayRect rect: CGRect, page: PDFPage) -> CGRect {
        let raw = page.bounds(for: .mediaBox)
        let o = raw.origin
        switch page.displayRotation {
        case 90:
            return CGRect(
                x: o.x + raw.width - rect.maxY,
                y: o.y + rect.minX,
                width: rect.height,
                height: rect.width
            )
        case 180:
            return CGRect(
                x: o.x + raw.width - rect.maxX,
                y: o.y + raw.height - rect.maxY,
                width: rect.width,
                height: rect.height
            )
        case 270:
            return CGRect(
                x: o.x + rect.minY,
                y: o.y + raw.height - rect.maxX,
                width: rect.height,
                height: rect.width
            )
        default:
            return CGRect(
                x: o.x + rect.minX,
                y: o.y + rect.minY,
                width: rect.width,
                height: rect.height
            )
        }
    }

    /// Forward direction of `rawRect`: raw media-box space → display
    /// space. Used by the probe tests to verify a stored widget's
    /// bounds land where the preview showed the field.
    static func displayRect(forRawRect rect: CGRect, page: PDFPage) -> CGRect {
        let raw = page.bounds(for: .mediaBox)
        let o = raw.origin
        switch page.displayRotation {
        case 90:
            return CGRect(
                x: rect.minY - o.y,
                y: o.x + raw.width - rect.maxX,
                width: rect.height,
                height: rect.width
            )
        case 180:
            return CGRect(
                x: o.x + raw.width - rect.maxX,
                y: o.y + raw.height - rect.maxY,
                width: rect.width,
                height: rect.height
            )
        case 270:
            return CGRect(
                x: o.y + raw.height - rect.maxY,
                y: rect.minX - o.x,
                width: rect.height,
                height: rect.width
            )
        default:
            return CGRect(
                x: rect.minX - o.x,
                y: rect.minY - o.y,
                width: rect.width,
                height: rect.height
            )
        }
    }

    /// Writes a copy of the (in-memory) `document` — the exact pages
    /// the user previewed — with every `placement` drawn into the
    /// page, to exactly `outputURL`. Choosing where that is (next to
    /// the original, a save panel, a temp file) is the caller's
    /// business: baking `<source dir>/<name>_signed.pdf` in here is
    /// what made saving fail with no way out whenever the source sat
    /// somewhere unwritable, like Mail's downloads container.
    func flatten(
        document: PDFDocument,
        placements: [Placement],
        signatures: [SavedSignature],
        to outputURL: URL
    ) throws {
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
    }

    /// Destination for the "filled but unsigned" companion, derived
    /// from wherever the signed copy actually went — including a name
    /// the user chose freely in a save panel.
    /// `…/Offer_signed.pdf` → `…/Offer_filled.pdf`;
    /// `…/Any Name.pdf` → `…/Any Name_filled.pdf`.
    static func companionURL(besides signedURL: URL, suffix: String) -> URL {
        var base = signedURL.deletingPathExtension().lastPathComponent
        if base.hasSuffix("_signed") {
            base = String(base.dropLast("_signed".count))
        }
        return signedURL
            .deletingLastPathComponent()
            .appendingPathComponent(base + suffix + ".pdf")
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
