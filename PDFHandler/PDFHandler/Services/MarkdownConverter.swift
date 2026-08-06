//
//  MarkdownConverter.swift
//  PDFHandler
//
//  Converts a PDF into a Markdown file next to the source, optionally
//  with an `<name>_images/` companion directory for figures. Uses
//  PDFKit's text extraction first; falls back to Vision OCR page-by-
//  page when the text layer is empty or near-empty.
//

import Foundation
import PDFKit
import Vision
import AppKit

// MARK: - Options + result

enum ConvertImageFormat: String, CaseIterable, Identifiable, Codable {
    case png, jpeg
    var id: String { rawValue }
    var displayName: String { rawValue.uppercased() }
    var fileExtension: String { rawValue }
}

struct MarkdownConversionOptions {
    var includeYAMLFrontmatter: Bool = true
    /// Renders every page as a full-page image next to the Markdown.
    /// Off by default: it multiplies output size on large documents.
    var extractImages: Bool = false
    var imageFormat: ConvertImageFormat = .png
    var performOCR: Bool = true
    var ocrLanguages: [String] = ["en-US"]
    var preserveLinks: Bool = true
}

struct MarkdownConversionResult {
    let sourceURL: URL
    let markdownURL: URL
    let imagesDirectoryURL: URL?
    let pageCount: Int
    let ocrPagesCount: Int
    let processingTime: TimeInterval
}

enum MarkdownConversionError: LocalizedError {
    case cannotOpen
    case cannotWriteMarkdown(URL)
    case cannotWriteImage(URL)

    var errorDescription: String? {
        switch self {
        case .cannotOpen: return "Could not open the PDF."
        case .cannotWriteMarkdown(let url): return "Could not write Markdown to \(url.path)."
        case .cannotWriteImage(let url): return "Could not write image to \(url.path)."
        }
    }
}

// MARK: - Service

actor MarkdownConverter {

    func convert(
        pdfURL: URL,
        options: MarkdownConversionOptions,
        progressHandler: @escaping (Double) -> Void
    ) async throws -> MarkdownConversionResult {

        let start = Date()

        guard let document = PDFDocument(url: pdfURL) else {
            throw MarkdownConversionError.cannotOpen
        }

        let baseName = pdfURL.deletingPathExtension().lastPathComponent
        let folder = pdfURL.deletingLastPathComponent()
        // Never overwrite an existing .md (it may carry hand edits).
        var markdownURL = folder.appendingPathComponent("\(baseName).md")
        var counter = 2
        while FileManager.default.fileExists(atPath: markdownURL.path) {
            markdownURL = folder.appendingPathComponent("\(baseName)-\(counter).md")
            counter += 1
        }

        var imagesDirURL: URL?
        if options.extractImages {
            let dir = folder.appendingPathComponent("\(baseName)_images", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            imagesDirURL = dir
        }

        var markdown = ""

        if options.includeYAMLFrontmatter {
            markdown += renderFrontmatter(for: document, sourceURL: pdfURL)
        }

        // Per-page: prefer the text layer; fall back to OCR on pages
        // with < 20 chars of extractable text when OCR is enabled.
        var ocrPagesCount = 0
        let pageCount = document.pageCount

        for pageIndex in 0..<pageCount {
            guard let page = document.page(at: pageIndex) else { continue }

            let rawText = page.string ?? ""
            let needsOCR = options.performOCR && rawText.trimmingCharacters(in: .whitespacesAndNewlines).count < 20

            let pageText: String
            if needsOCR {
                pageText = (try? await ocr(page: page, languages: options.ocrLanguages)) ?? rawText
                ocrPagesCount += 1
            } else {
                pageText = rawText
            }

            markdown += "\n## Page \(pageIndex + 1)\n\n"
            markdown += normalize(pageText)
            markdown += "\n"

            if options.preserveLinks {
                markdown += renderLinks(for: page)
            }

            if options.extractImages, let imagesDir = imagesDirURL {
                let imagePaths = try extractImages(
                    page: page,
                    pageIndex: pageIndex,
                    into: imagesDir,
                    format: options.imageFormat
                )
                for relativePath in imagePaths {
                    markdown += "\n![](\(relativePath))\n"
                }
            }

            progressHandler(Double(pageIndex + 1) / Double(pageCount) * 0.95)
        }

        try markdown.write(to: markdownURL, atomically: true, encoding: .utf8)
        progressHandler(1.0)

        return MarkdownConversionResult(
            sourceURL: pdfURL,
            markdownURL: markdownURL,
            imagesDirectoryURL: imagesDirURL,
            pageCount: pageCount,
            ocrPagesCount: ocrPagesCount,
            processingTime: Date().timeIntervalSince(start)
        )
    }

    // MARK: - Text normalization (uses a bare-slash regex literal)

    private func normalize(_ text: String) -> String {
        // Collapse runs of whitespace into a single space but keep
        // paragraph breaks. Requires the BareSlashRegexLiterals
        // upcoming-feature flag in Package.swift.
        let pattern = /[ \t]+/
        var lines: [String] = []
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let collapsed = String(rawLine).replacing(pattern, with: " ").trimmingCharacters(in: .whitespaces)
            lines.append(collapsed)
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - OCR via Vision

    private func ocr(page: PDFPage, languages: [String]) async throws -> String {
        guard let image = try PDFPageRenderer.render(page: page, dpi: 300) else { return "" }
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return "" }

        // Vision can invoke the request's completion handler with an
        // error AND then throw from perform(_:) for the same failure;
        // resuming a CheckedContinuation twice crashes, so gate it.
        let gate = OneShot()
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            let request = VNRecognizeTextRequest { request, error in
                guard gate.claim() else { return }
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                let lines = observations.compactMap { $0.topCandidates(1).first?.string }
                continuation.resume(returning: lines.joined(separator: "\n"))
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            let supported = (try? VNRecognizeTextRequest.supportedRecognitionLanguages(
                for: .accurate, revision: VNRecognizeTextRequestRevision3
            )) ?? []
            request.recognitionLanguages = languages.filter { supported.contains($0) }.isEmpty
                ? ["en-US"] : languages.filter { supported.contains($0) }

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                if gate.claim() {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Image extraction

    private func extractImages(
        page: PDFPage,
        pageIndex: Int,
        into dir: URL,
        format: ConvertImageFormat
    ) throws -> [String] {
        // PDFKit doesn't expose individual embedded image resources
        // cleanly; render the full page as a high-DPI PNG/JPEG
        // instead — simple, robust, and matches what users see.
        guard let pageImage = try PDFPageRenderer.render(page: page, dpi: 200) else {
            return []
        }
        let fileName = "page_\(pageIndex + 1).\(format.fileExtension)"
        let url = dir.appendingPathComponent(fileName)

        guard let tiff = pageImage.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else {
            throw MarkdownConversionError.cannotWriteImage(url)
        }
        let type: NSBitmapImageRep.FileType = (format == .png) ? .png : .jpeg
        let properties: [NSBitmapImageRep.PropertyKey: Any] = (format == .jpeg)
            ? [.compressionFactor: 0.85] : [:]
        guard let data = rep.representation(using: type, properties: properties) else {
            throw MarkdownConversionError.cannotWriteImage(url)
        }
        try data.write(to: url)
        return ["\(dir.lastPathComponent)/\(fileName)"]
    }

    // MARK: - Frontmatter + links

    private func renderFrontmatter(for document: PDFDocument, sourceURL: URL) -> String {
        var lines: [String] = ["---"]
        if let attrs = document.documentAttributes {
            if let title = attrs[PDFDocumentAttribute.titleAttribute] as? String, !title.isEmpty {
                lines.append("title: \(yaml(title))")
            }
            if let author = attrs[PDFDocumentAttribute.authorAttribute] as? String, !author.isEmpty {
                lines.append("author: \(yaml(author))")
            }
            if let subject = attrs[PDFDocumentAttribute.subjectAttribute] as? String, !subject.isEmpty {
                lines.append("subject: \(yaml(subject))")
            }
        }
        lines.append("source: \(yaml(sourceURL.lastPathComponent))")
        lines.append("pages: \(document.pageCount)")
        lines.append("---\n")
        return lines.joined(separator: "\n")
    }

    private func yaml(_ value: String) -> String {
        // Backslashes must be escaped before quotes, and embedded
        // newlines would split the scalar and break the frontmatter.
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        return "\"\(escaped)\""
    }

    private func renderLinks(for page: PDFPage) -> String {
        var out = ""
        guard let annotations = page.annotations as [PDFAnnotation]? else { return out }
        for annotation in annotations where annotation.type == "Link" {
            if let url = annotation.url {
                out += "\n<\(url.absoluteString)>\n"
            }
        }
        return out
    }
}

/// Thread-safe one-shot flag guarding a CheckedContinuation against
/// being resumed from more than one callback path.
private final class OneShot: @unchecked Sendable {
    private let lock = NSLock()
    private var used = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if used { return false }
        used = true
        return true
    }
}
