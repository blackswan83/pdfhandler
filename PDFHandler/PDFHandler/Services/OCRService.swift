//
//  OCRService.swift
//  PDFHandler
//
//  OCR service using macOS Vision framework
//

import Foundation
import Vision
import PDFKit
import AppKit

actor OCRService {

    // MARK: - Text Recognition

    func recognizeText(
        in page: PDFPage,
        languages: [String] = ["en-US"]
    ) async throws -> (text: String, confidence: Double) {
        // Render page to image
        let image = renderPageToImage(page)

        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw OCRError.imageConversionFailed
        }

        return try await performOCR(on: cgImage, languages: languages)
    }

    func recognizeText(
        in image: NSImage,
        languages: [String] = ["en-US"]
    ) async throws -> (text: String, confidence: Double) {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw OCRError.imageConversionFailed
        }

        return try await performOCR(on: cgImage, languages: languages)
    }

    // MARK: - Private Implementation

    private func renderPageToImage(_ page: PDFPage, dpi: CGFloat = 300) -> NSImage {
        let bounds = page.bounds(for: .mediaBox)
        let scale = dpi / 72.0 // PDF uses 72 DPI

        let size = CGSize(
            width: bounds.width * scale,
            height: bounds.height * scale
        )

        let image = NSImage(size: size)
        image.lockFocus()

        if let context = NSGraphicsContext.current?.cgContext {
            // White background
            context.setFillColor(NSColor.white.cgColor)
            context.fill(CGRect(origin: .zero, size: size))

            // Scale and draw PDF page
            context.scaleBy(x: scale, y: scale)
            context.translateBy(x: -bounds.origin.x, y: -bounds.origin.y)

            page.draw(with: .mediaBox, to: context)
        }

        image.unlockFocus()
        return image
    }

    private func performOCR(
        on image: CGImage,
        languages: [String]
    ) async throws -> (text: String, confidence: Double) {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: OCRError.recognitionFailed(error.localizedDescription))
                    return
                }

                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(throwing: OCRError.noResults)
                    return
                }

                // Extract text and calculate average confidence
                var texts: [String] = []
                var totalConfidence: Float = 0
                var count: Int = 0

                for observation in observations {
                    if let topCandidate = observation.topCandidates(1).first {
                        texts.append(topCandidate.string)
                        totalConfidence += topCandidate.confidence
                        count += 1
                    }
                }

                let averageConfidence = count > 0 ? Double(totalConfidence) / Double(count) : 0

                // Sort observations by position (top to bottom, left to right)
                let sortedTexts = self.sortTextByPosition(observations)

                continuation.resume(returning: (
                    text: sortedTexts.joined(separator: "\n"),
                    confidence: averageConfidence
                ))
            }

            // Configure the request
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            // Set recognition languages
            if #available(macOS 13.0, *) {
                request.automaticallyDetectsLanguage = true
            }

            do {
                let supportedLanguages = try request.supportedRecognitionLanguages()
                let filteredLanguages = languages.filter { supportedLanguages.contains($0) }
                if !filteredLanguages.isEmpty {
                    request.recognitionLanguages = filteredLanguages
                }
            } catch {
                // Use default languages if filtering fails
            }

            // Perform recognition
            let handler = VNImageRequestHandler(cgImage: image, options: [:])

            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: OCRError.recognitionFailed(error.localizedDescription))
            }
        }
    }

    private func sortTextByPosition(_ observations: [VNRecognizedTextObservation]) -> [String] {
        // Sort by Y position (top to bottom) then X position (left to right)
        let sorted = observations.sorted { obs1, obs2 in
            let y1 = obs1.boundingBox.origin.y
            let y2 = obs2.boundingBox.origin.y

            // If Y positions are similar (same line), sort by X
            if abs(y1 - y2) < 0.02 {
                return obs1.boundingBox.origin.x < obs2.boundingBox.origin.x
            }

            // Otherwise sort by Y (higher Y = lower on page in Vision coordinates)
            return y1 > y2
        }

        return sorted.compactMap { $0.topCandidates(1).first?.string }
    }

    // MARK: - Language Support

    func supportedLanguages() -> [String] {
        do {
            let request = VNRecognizeTextRequest { _, _ in }
            return try request.supportedRecognitionLanguages()
        } catch {
            return ["en-US"]
        }
    }

    // MARK: - Document Analysis

    func analyzeDocumentStructure(
        in page: PDFPage
    ) async throws -> DocumentStructure {
        let image = renderPageToImage(page)

        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw OCRError.imageConversionFailed
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: OCRError.recognitionFailed(error.localizedDescription))
                    return
                }

                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: DocumentStructure(
                        textBlocks: [],
                        columns: 1,
                        hasHeaders: false,
                        hasFooters: false
                    ))
                    return
                }

                let structure = self.analyzeLayout(observations)
                continuation.resume(returning: structure)
            }

            request.recognitionLevel = .accurate

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: OCRError.recognitionFailed(error.localizedDescription))
            }
        }
    }

    private func analyzeLayout(_ observations: [VNRecognizedTextObservation]) -> DocumentStructure {
        var textBlocks: [TextBlock] = []

        // Group observations into blocks based on proximity
        var currentBlock: [VNRecognizedTextObservation] = []
        var lastY: CGFloat = 1.0

        let sorted = observations.sorted { $0.boundingBox.origin.y > $1.boundingBox.origin.y }

        for observation in sorted {
            let y = observation.boundingBox.origin.y

            // If there's a significant gap, start a new block
            if lastY - y > 0.05 && !currentBlock.isEmpty {
                if let block = createTextBlock(from: currentBlock) {
                    textBlocks.append(block)
                }
                currentBlock = []
            }

            currentBlock.append(observation)
            lastY = y
        }

        // Don't forget the last block
        if let block = createTextBlock(from: currentBlock) {
            textBlocks.append(block)
        }

        // Detect columns
        let columns = detectColumnCount(observations)

        // Detect headers (text in top 10% with larger font or different style)
        let hasHeaders = observations.contains { $0.boundingBox.origin.y > 0.9 }

        // Detect footers (text in bottom 10%)
        let hasFooters = observations.contains { $0.boundingBox.origin.y < 0.1 }

        return DocumentStructure(
            textBlocks: textBlocks,
            columns: columns,
            hasHeaders: hasHeaders,
            hasFooters: hasFooters
        )
    }

    private func createTextBlock(from observations: [VNRecognizedTextObservation]) -> TextBlock? {
        guard !observations.isEmpty else { return nil }

        let texts = observations.compactMap { $0.topCandidates(1).first?.string }
        let text = texts.joined(separator: " ")

        // Calculate bounding box
        let minX = observations.map { $0.boundingBox.minX }.min() ?? 0
        let minY = observations.map { $0.boundingBox.minY }.min() ?? 0
        let maxX = observations.map { $0.boundingBox.maxX }.max() ?? 1
        let maxY = observations.map { $0.boundingBox.maxY }.max() ?? 1

        let bounds = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)

        // Determine block type
        let type: TextBlockType
        if bounds.width < 0.5 && bounds.height < 0.05 && text.count < 50 {
            type = .heading
        } else if text.hasPrefix("•") || text.hasPrefix("-") || text.hasPrefix("*") {
            type = .listItem
        } else {
            type = .paragraph
        }

        return TextBlock(
            text: text,
            bounds: bounds,
            type: type,
            confidence: Double(observations.compactMap { $0.topCandidates(1).first?.confidence }.reduce(0, +)) /
                       Double(max(1, observations.count))
        )
    }

    private func detectColumnCount(_ observations: [VNRecognizedTextObservation]) -> Int {
        // Analyze X positions to detect columns
        let xPositions = observations.map { $0.boundingBox.midX }
        guard !xPositions.isEmpty else { return 1 }

        // Simple heuristic: if there are clusters of X positions, we have multiple columns
        let sorted = xPositions.sorted()
        var gaps: [CGFloat] = []

        for i in 1..<sorted.count {
            let gap = sorted[i] - sorted[i - 1]
            if gap > 0.1 { // Significant gap
                gaps.append(sorted[i - 1] + gap / 2)
            }
        }

        // Number of columns = number of gaps + 1
        return min(gaps.count + 1, 4) // Cap at 4 columns
    }
}

// MARK: - Supporting Types

enum OCRError: LocalizedError {
    case imageConversionFailed
    case recognitionFailed(String)
    case noResults

    var errorDescription: String? {
        switch self {
        case .imageConversionFailed:
            return "Failed to convert PDF page to image for OCR"
        case .recognitionFailed(let message):
            return "Text recognition failed: \(message)"
        case .noResults:
            return "No text was recognized in the image"
        }
    }
}

struct DocumentStructure {
    let textBlocks: [TextBlock]
    let columns: Int
    let hasHeaders: Bool
    let hasFooters: Bool
}

struct TextBlock {
    let text: String
    let bounds: CGRect
    let type: TextBlockType
    let confidence: Double
}

enum TextBlockType {
    case heading
    case paragraph
    case listItem
    case table
    case caption
    case footer
    case header
}
