//
//  PDFMerger.swift
//  PDFHandler
//
//  Combines multiple PDFs into a single document using PDFKit only.
//  Output lives next to the first source PDF.
//

import Foundation
import PDFKit

/// A queued merge input. Wrapping the URL gives every list row a
/// stable identity (the same file can be queued twice, and offsets
/// change on every reorder — neither works as a ForEach id).
struct MergeItem: Identifiable, Equatable {
    let id = UUID()
    let url: URL
}

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

        // Never overwrite an existing file — in particular not one of
        // the inputs (merging "merged.pdf + C.pdf" with the default
        // output name used to clobber the first input mid-read).
        let dir = pdfURLs[0].deletingLastPathComponent()
        var outputURL = dir.appendingPathComponent("\(outputName).pdf")
        var counter = 2
        while FileManager.default.fileExists(atPath: outputURL.path)
            || pdfURLs.contains(where: { $0.standardizedFileURL == outputURL.standardizedFileURL }) {
            outputURL = dir.appendingPathComponent("\(outputName)-\(counter).pdf")
            counter += 1
        }

        guard merged.write(to: outputURL) else {
            throw PDFMergeError.cannotWrite(outputURL)
        }
        progressHandler(1.0)
        return outputURL
    }
}
