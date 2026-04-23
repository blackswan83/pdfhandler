//
//  PDFSigner.swift
//  PDFHandler
//
//  Burns SignaturePlacements into a copy of a PDF by adding image
//  stamp annotations and writing the result next to the original.
//

import Foundation
import PDFKit
import AppKit

enum PDFSignerError: LocalizedError {
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

struct PDFSigner {

    /// Writes a signed copy of `source` and returns the output URL.
    /// Output name: `<original>_signed.pdf` next to the original.
    func sign(
        source: URL,
        placements: [SignaturePlacement],
        signatures: [SavedSignature]
    ) throws -> URL {
        guard let document = PDFDocument(url: source) else {
            throw PDFSignerError.cannotOpen
        }

        let byID = Dictionary(uniqueKeysWithValues: signatures.map { ($0.id, $0) })

        for placement in placements {
            guard let saved = byID[placement.signatureID] else {
                throw PDFSignerError.unknownSignature(placement.signatureID)
            }
            guard let image = saved.image,
                  placement.pageIndex >= 0,
                  placement.pageIndex < document.pageCount,
                  let page = document.page(at: placement.pageIndex)
            else { continue }

            let rect = Self.pdfRect(for: placement.normalizedRect, in: page)
            let annotation = StampImageAnnotation(bounds: rect, image: image)
            annotation.contents = "Signature"
            page.addAnnotation(annotation)
        }

        let baseName = source.deletingPathExtension().lastPathComponent
        let outputURL = source
            .deletingLastPathComponent()
            .appendingPathComponent("\(baseName)_signed.pdf")

        guard document.write(to: outputURL) else {
            throw PDFSignerError.writeFailed(outputURL)
        }
        return outputURL
    }

    /// Convert a normalized rect (top-left origin, 0…1) to the page's
    /// PDF coordinate space (bottom-left origin, points).
    static func pdfRect(for normalized: CGRect, in page: PDFPage) -> CGRect {
        let bounds = page.bounds(for: .mediaBox)
        let w = normalized.width * bounds.width
        let h = normalized.height * bounds.height
        let x = normalized.minX * bounds.width + bounds.minX
        // Flip Y: top-left normalized → bottom-left PDF.
        let y = bounds.minY + (1.0 - normalized.minY - normalized.height) * bounds.height
        return CGRect(x: x, y: y, width: w, height: h)
    }
}

/// PDFAnnotation that draws a bitmap image in its bounds. The stock
/// .stamp annotation does not render a supplied NSImage directly, so
/// we override draw(with:in:) to composite the bitmap ourselves.
final class StampImageAnnotation: PDFAnnotation {
    private let stampImage: NSImage

    init(bounds: CGRect, image: NSImage) {
        self.stampImage = image
        super.init(bounds: bounds, forType: .stamp, withProperties: nil)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func draw(with box: PDFDisplayBox, in context: CGContext) {
        guard let cg = stampImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return
        }
        context.saveGState()
        context.setShouldAntialias(true)
        context.interpolationQuality = .high
        context.draw(cg, in: bounds)
        context.restoreGState()
    }
}
