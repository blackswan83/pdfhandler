//
//  PDFMerger.swift
//  PDFHandler
//
//  Combines multiple PDFs into a single document using PDFKit only.
//  Output lives next to the first source PDF.
//

import Foundation
import PDFKit

enum PDFMergeError: LocalizedError {
    case insufficientFiles
    case cannotOpen(URL)
    case cannotWrite(URL)

    var errorDescription: String? {
        switch self {
        case .insufficientFiles: return "Add at least two PDFs to merge."
        case .cannotOpen(let url): return "Could not open \(url.lastPathComponent)."
        case .cannotWrite(let url): return "Could not write merged PDF to \(url.path)."
        }
    }
}

actor PDFMerger {

    /// Merges the supplied PDFs into one document named
    /// `<outputName>.pdf` next to the first source. Progress callbacks
    /// are hopped to the main actor by the caller; this function only
    /// invokes the handler from the actor it's running on.
    func merge(
        pdfURLs: [URL],
        outputName: String,
        progressHandler: @escaping (Double) -> Void
    ) async throws -> URL {

        guard pdfURLs.count >= 2 else { throw PDFMergeError.insufficientFiles }

        let merged = PDFDocument()
        for (index, url) in pdfURLs.enumerated() {
            guard let source = PDFDocument(url: url) else {
                throw PDFMergeError.cannotOpen(url)
            }
            for pageIndex in 0..<source.pageCount {
                if let page = source.page(at: pageIndex) {
                    merged.insert(page, at: merged.pageCount)
                }
            }
            progressHandler(Double(index + 1) / Double(pdfURLs.count) * 0.95)
        }

        let first = pdfURLs[0]
        let outputURL = first
            .deletingLastPathComponent()
            .appendingPathComponent("\(outputName).pdf")

        guard merged.write(to: outputURL) else {
            throw PDFMergeError.cannotWrite(outputURL)
        }
        progressHandler(1.0)
        return outputURL
    }
}
