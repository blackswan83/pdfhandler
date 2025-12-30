//
//  MarkdownConverter.swift
//  PDFHandler
//
//  Converts parsed PDF content to Markdown format
//

import Foundation
import PDFKit
import AppKit

actor MarkdownConverter {
    private let pdfService = PDFService()
    private let ocrService = OCRService()

    // MARK: - Main Conversion

    func convert(
        pdf: PDFDocument,
        sourceURL: URL,
        options: ConversionOptions,
        progressHandler: @escaping (Double) -> Void
    ) async throws -> ConversionResult {
        let startTime = Date()
        var warnings: [ConversionWarning] = []

        // Analyze document
        progressHandler(0.1)
        let metadata = await pdfService.analyzeDocument(pdf)

        // Determine output locations
        let outputDirectory = options.outputDirectory ?? sourceURL.deletingLastPathComponent()
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        let markdownURL = outputDirectory.appendingPathComponent("\(baseName).md")
        let imagesDirectory = outputDirectory.appendingPathComponent("\(baseName)_images")

        // Create images directory if needed
        if options.extractImages {
            try? FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        }

        // Extract content from PDF
        progressHandler(0.2)
        var parsedContent = try await pdfService.extractContent(from: pdf, options: options)

        // Perform OCR if needed
        var ocrApplied = false
        var ocrConfidence: Double?

        if parsedContent.requiresOCR {
            progressHandler(0.3)
            let ocrResults = try await performOCR(on: pdf, options: options)
            ocrApplied = true

            // Merge OCR results into parsed content
            for (index, ocrResult) in ocrResults.enumerated() {
                if index < parsedContent.pages.count {
                    parsedContent.pages[index].ocrText = ocrResult.text
                    parsedContent.pages[index].ocrConfidence = ocrResult.confidence

                    if ocrResult.confidence < 0.8 {
                        warnings.append(ConversionWarning(
                            type: .lowOCRConfidence,
                            message: "OCR confidence is low (\(Int(ocrResult.confidence * 100))%) on page \(index + 1)",
                            page: index + 1
                        ))
                    }
                }
            }

            ocrConfidence = ocrResults.map { $0.confidence }.reduce(0, +) / Double(max(1, ocrResults.count))
        }

        // Extract and save images
        progressHandler(0.5)
        var extractedImages: [ExtractedImage] = []

        if options.extractImages {
            extractedImages = try await extractAndSaveImages(
                from: pdf,
                to: imagesDirectory,
                baseName: baseName,
                options: options,
                warnings: &warnings
            )
        }

        // Generate Markdown
        progressHandler(0.7)
        let markdown = generateMarkdown(
            from: parsedContent,
            extractedImages: extractedImages,
            imagesDirectory: imagesDirectory,
            options: options,
            warnings: &warnings
        )

        // Write output file
        progressHandler(0.9)
        try markdown.write(to: markdownURL, atomically: true, encoding: .utf8)

        progressHandler(1.0)

        let processingTime = Date().timeIntervalSince(startTime)

        return ConversionResult(
            sourceURL: sourceURL,
            outputURL: markdownURL,
            markdown: markdown,
            extractedImages: extractedImages,
            metadata: metadata,
            ocrApplied: ocrApplied,
            ocrConfidence: ocrConfidence,
            warnings: warnings,
            processingTime: processingTime
        )
    }

    // MARK: - OCR

    private func performOCR(
        on pdf: PDFDocument,
        options: ConversionOptions
    ) async throws -> [(text: String, confidence: Double)] {
        var results: [(text: String, confidence: Double)] = []

        for pageIndex in 0..<pdf.pageCount {
            guard let page = pdf.page(at: pageIndex) else { continue }

            let result = try await ocrService.recognizeText(
                in: page,
                languages: options.ocrLanguages
            )
            results.append(result)
        }

        return results
    }

    // MARK: - Image Extraction

    private func extractAndSaveImages(
        from pdf: PDFDocument,
        to directory: URL,
        baseName: String,
        options: ConversionOptions,
        warnings: inout [ConversionWarning]
    ) async throws -> [ExtractedImage] {
        var extractedImages: [ExtractedImage] = []
        var imageCounter = 1

        for pageIndex in 0..<pdf.pageCount {
            guard let page = pdf.page(at: pageIndex) else { continue }

            // Render page as image to extract visual content
            let pageImages = await pdfService.extractImagesSimple(
                from: page,
                pageNumber: pageIndex + 1
            )

            for (imageIndex, nsImage) in pageImages.enumerated() {
                let filename: String
                switch options.imageNamingConvention {
                case .sequential:
                    filename = String(format: "image_%03d", imageCounter)
                case .pageNumber:
                    filename = "page\(pageIndex + 1)_img\(imageIndex + 1)"
                case .descriptive:
                    filename = "figure_\(imageCounter)"
                }

                let fileExtension = options.imageOutputFormat.fileExtension
                let imageURL = directory.appendingPathComponent("\(filename).\(fileExtension)")

                // Convert and save image
                if let imageData = imageData(from: nsImage, format: options.imageOutputFormat) {
                    do {
                        try imageData.write(to: imageURL)

                        let extractedImage = ExtractedImage(
                            originalPage: pageIndex + 1,
                            outputURL: imageURL,
                            format: options.imageOutputFormat,
                            dimensions: nsImage.size,
                            markdownReference: "![Image \(imageCounter)](\(baseName)_images/\(filename).\(fileExtension))"
                        )
                        extractedImages.append(extractedImage)
                        imageCounter += 1
                    } catch {
                        warnings.append(ConversionWarning(
                            type: .imageTooLarge,
                            message: "Failed to save image on page \(pageIndex + 1): \(error.localizedDescription)",
                            page: pageIndex + 1
                        ))
                    }
                }
            }
        }

        return extractedImages
    }

    private func imageData(from image: NSImage, format: ImageFormat) -> Data? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }

        switch format {
        case .png:
            return bitmap.representation(using: .png, properties: [:])
        case .jpeg:
            return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.85])
        }
    }

    // MARK: - Markdown Generation

    private func generateMarkdown(
        from content: ParsedPDFContent,
        extractedImages: [ExtractedImage],
        imagesDirectory: URL,
        options: ConversionOptions,
        warnings: inout [ConversionWarning]
    ) -> String {
        var markdown = ""

        // Add YAML frontmatter if requested
        if options.includeYAMLFrontmatter {
            let frontmatter = YAMLFrontmatter(
                title: content.metadata.title,
                author: content.metadata.author,
                date: content.metadata.creationDate,
                source: nil,
                tags: content.metadata.keywords,
                custom: [:]
            )
            markdown += frontmatter.toString() + "\n\n"
        }

        // Process each page
        var currentImageIndex = 0

        for page in content.pages {
            // Use OCR text if available and original text is empty
            let textElements: [PageElement]
            if page.elements.isEmpty, let ocrText = page.ocrText {
                textElements = parseOCRText(ocrText)
            } else {
                textElements = page.elements
            }

            for element in textElements {
                markdown += renderElement(element, options: options, warnings: &warnings)
                markdown += "\n\n"
            }

            // Insert image references for this page
            while currentImageIndex < extractedImages.count &&
                  extractedImages[currentImageIndex].originalPage == page.pageNumber {
                markdown += extractedImages[currentImageIndex].markdownReference + "\n\n"
                currentImageIndex += 1
            }

            // Add page break comment for multi-page documents
            if content.pages.count > 1 && page.pageNumber < content.pages.count {
                markdown += "<!-- Page \(page.pageNumber) -->\n\n"
            }
        }

        return markdown.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func parseOCRText(_ text: String) -> [PageElement] {
        // Simple parsing of OCR text into paragraphs
        let paragraphs = text.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return paragraphs.map { .paragraph(text: $0) }
    }

    private func renderElement(
        _ element: PageElement,
        options: ConversionOptions,
        warnings: inout [ConversionWarning]
    ) -> String {
        switch element {
        case .heading(let level, let text):
            let prefix = String(repeating: "#", count: min(level, 6))
            return "\(prefix) \(cleanText(text))"

        case .paragraph(let text):
            return cleanText(text)

        case .bulletList(let items):
            return items.map { "- \(cleanText($0))" }.joined(separator: "\n")

        case .numberedList(let items):
            return items.enumerated()
                .map { "\($0.offset + 1). \(cleanText($0.element))" }
                .joined(separator: "\n")

        case .table(let table):
            if table.isComplex {
                warnings.append(ConversionWarning(
                    type: .complexTable,
                    message: "Complex table detected, using fallback rendering",
                    page: nil
                ))

                switch options.tableFallbackMode {
                case .codeBlock:
                    return table.toCodeBlock()
                case .csv:
                    return "```csv\n\(table.toCSV())\n```"
                case .html:
                    return renderTableAsHTML(table)
                }
            }
            return table.toMarkdown()

        case .codeBlock(let text):
            return "```\n\(text)\n```"

        case .blockquote(let text):
            return text.components(separatedBy: .newlines)
                .map { "> \(cleanText($0))" }
                .joined(separator: "\n")

        case .horizontalRule:
            return "---"

        case .image(let reference):
            return reference

        case .link(let text, let url):
            if options.preserveLinks {
                return "[\(cleanText(text))](\(url))"
            } else {
                return cleanText(text)
            }
        }
    }

    private func cleanText(_ text: String) -> String {
        var result = text

        // Normalize whitespace
        result = result.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        )

        // Escape Markdown special characters in regular text
        let specialChars = ["\\", "`", "*", "_", "{", "}", "[", "]", "(", ")", "#", "+", "-", ".", "!"]
        for char in specialChars {
            // Only escape if it's not part of intended formatting
            // This is a simple approach; more sophisticated handling would be needed
        }

        return result.trimmingCharacters(in: .whitespaces)
    }

    private func renderTableAsHTML(_ table: Table) -> String {
        var html = "<table>\n"

        if !table.headers.isEmpty {
            html += "  <thead>\n    <tr>\n"
            for header in table.headers {
                html += "      <th>\(escapeHTML(header))</th>\n"
            }
            html += "    </tr>\n  </thead>\n"
        }

        html += "  <tbody>\n"
        for row in table.rows {
            html += "    <tr>\n"
            for cell in row {
                html += "      <td>\(escapeHTML(cell))</td>\n"
            }
            html += "    </tr>\n"
        }
        html += "  </tbody>\n</table>"

        return html
    }

    private func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
