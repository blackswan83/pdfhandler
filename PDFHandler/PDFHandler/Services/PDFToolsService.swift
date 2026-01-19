//
//  PDFToolsService.swift
//  PDFHandler
//
//  Service for PDF manipulation tools (merge, split, rotate, sign, watermark, security)
//

import Foundation
import PDFKit
import AppKit

actor PDFToolsService {

    // MARK: - Merge PDFs

    func merge(
        pdfURLs: [URL],
        options: MergeOptions,
        progressHandler: @escaping (Double) -> Void
    ) async throws -> MergeResult {
        let startTime = Date()

        guard pdfURLs.count >= 2 else {
            throw PDFToolsError.insufficientFiles("Need at least 2 PDFs to merge")
        }

        let mergedDocument = PDFDocument()
        var totalPages = 0

        for (index, url) in pdfURLs.enumerated() {
            guard let document = PDFDocument(url: url) else {
                throw PDFToolsError.invalidPDF("Could not open: \(url.lastPathComponent)")
            }

            for pageIndex in 0..<document.pageCount {
                if let page = document.page(at: pageIndex) {
                    mergedDocument.insert(page, at: mergedDocument.pageCount)
                    totalPages += 1
                }
            }

            await MainActor.run {
                progressHandler(Double(index + 1) / Double(pdfURLs.count) * 0.9)
            }
        }

        // Save merged document
        let outputDirectory = options.outputDirectory ?? pdfURLs[0].deletingLastPathComponent()
        let outputURL = outputDirectory.appendingPathComponent("\(options.outputName).pdf")

        guard mergedDocument.write(to: outputURL) else {
            throw PDFToolsError.saveFailed("Could not save merged PDF")
        }

        await MainActor.run {
            progressHandler(1.0)
        }

        return MergeResult(
            sourceURLs: pdfURLs,
            outputURL: outputURL,
            totalPages: totalPages,
            processingTime: Date().timeIntervalSince(startTime)
        )
    }

    // MARK: - Split PDF

    func split(
        pdfURL: URL,
        options: SplitOptions,
        progressHandler: @escaping (Double) -> Void
    ) async throws -> SplitResult {
        let startTime = Date()

        guard let document = PDFDocument(url: pdfURL) else {
            throw PDFToolsError.invalidPDF("Could not open PDF")
        }

        let outputDirectory = options.outputDirectory ?? pdfURL.deletingLastPathComponent()
        let baseName = options.outputNamePrefix ?? pdfURL.deletingPathExtension().lastPathComponent

        var outputURLs: [URL] = []

        switch options.mode {
        case .allPages:
            for pageIndex in 0..<document.pageCount {
                let singlePageDoc = PDFDocument()
                if let page = document.page(at: pageIndex) {
                    singlePageDoc.insert(page, at: 0)
                    let outputURL = outputDirectory.appendingPathComponent("\(baseName)_page\(pageIndex + 1).pdf")
                    if singlePageDoc.write(to: outputURL) {
                        outputURLs.append(outputURL)
                    }
                }
                await MainActor.run {
                    progressHandler(Double(pageIndex + 1) / Double(document.pageCount))
                }
            }

        case .pageRanges:
            let ranges = parsePageRanges(options.pageRanges, maxPage: document.pageCount)
            for (rangeIndex, range) in ranges.enumerated() {
                let rangeDoc = PDFDocument()
                for pageIndex in range {
                    if let page = document.page(at: pageIndex - 1) { // Convert to 0-indexed
                        rangeDoc.insert(page, at: rangeDoc.pageCount)
                    }
                }
                let outputURL = outputDirectory.appendingPathComponent("\(baseName)_pages\(range.first ?? 0)-\(range.last ?? 0).pdf")
                if rangeDoc.write(to: outputURL) {
                    outputURLs.append(outputURL)
                }
                await MainActor.run {
                    progressHandler(Double(rangeIndex + 1) / Double(ranges.count))
                }
            }

        case .everyNPages:
            let n = options.pagesPerSplit
            var chunkIndex = 0
            for startPage in stride(from: 0, to: document.pageCount, by: n) {
                let chunkDoc = PDFDocument()
                let endPage = min(startPage + n, document.pageCount)
                for pageIndex in startPage..<endPage {
                    if let page = document.page(at: pageIndex) {
                        chunkDoc.insert(page, at: chunkDoc.pageCount)
                    }
                }
                chunkIndex += 1
                let outputURL = outputDirectory.appendingPathComponent("\(baseName)_part\(chunkIndex).pdf")
                if chunkDoc.write(to: outputURL) {
                    outputURLs.append(outputURL)
                }
                await MainActor.run {
                    progressHandler(Double(endPage) / Double(document.pageCount))
                }
            }

        case .byFileSize:
            // Simplified: split when estimated size exceeds limit
            var currentDoc = PDFDocument()
            var partIndex = 0
            let maxBytes = Int64(options.maxFileSizeMB * 1024 * 1024)

            for pageIndex in 0..<document.pageCount {
                if let page = document.page(at: pageIndex) {
                    currentDoc.insert(page, at: currentDoc.pageCount)

                    // Estimate size (rough approximation)
                    if let data = currentDoc.dataRepresentation(), Int64(data.count) > maxBytes {
                        // Remove last page and save
                        if currentDoc.pageCount > 1 {
                            currentDoc.removePage(at: currentDoc.pageCount - 1)
                        }
                        partIndex += 1
                        let outputURL = outputDirectory.appendingPathComponent("\(baseName)_part\(partIndex).pdf")
                        if currentDoc.write(to: outputURL) {
                            outputURLs.append(outputURL)
                        }
                        // Start new document with the page we removed
                        currentDoc = PDFDocument()
                        currentDoc.insert(page, at: 0)
                    }
                }
                await MainActor.run {
                    progressHandler(Double(pageIndex + 1) / Double(document.pageCount))
                }
            }

            // Save remaining pages
            if currentDoc.pageCount > 0 {
                partIndex += 1
                let outputURL = outputDirectory.appendingPathComponent("\(baseName)_part\(partIndex).pdf")
                if currentDoc.write(to: outputURL) {
                    outputURLs.append(outputURL)
                }
            }
        }

        return SplitResult(
            sourceURL: pdfURL,
            outputURLs: outputURLs,
            pageCount: document.pageCount,
            processingTime: Date().timeIntervalSince(startTime)
        )
    }

    // MARK: - Rotate PDF

    func rotate(
        pdfURL: URL,
        options: RotateOptions,
        progressHandler: @escaping (Double) -> Void
    ) async throws -> RotateResult {
        let startTime = Date()

        guard let document = PDFDocument(url: pdfURL) else {
            throw PDFToolsError.invalidPDF("Could not open PDF")
        }

        var pagesRotated = 0
        let pagesToRotate: [Int]

        if options.applyToAllPages {
            pagesToRotate = Array(0..<document.pageCount)
        } else {
            pagesToRotate = options.specificPages.map { $0 - 1 } // Convert to 0-indexed
        }

        for (index, pageIndex) in pagesToRotate.enumerated() {
            if let page = document.page(at: pageIndex) {
                let currentRotation = page.rotation
                let newRotation = (currentRotation + options.angle.rawValue) % 360
                page.rotation = newRotation
                pagesRotated += 1
            }
            await MainActor.run {
                progressHandler(Double(index + 1) / Double(pagesToRotate.count) * 0.9)
            }
        }

        // Save rotated document
        let outputDirectory = options.outputDirectory ?? pdfURL.deletingLastPathComponent()
        let baseName = options.customOutputName ?? "\(pdfURL.deletingPathExtension().lastPathComponent)_rotated"
        let outputURL = outputDirectory.appendingPathComponent("\(baseName).pdf")

        guard document.write(to: outputURL) else {
            throw PDFToolsError.saveFailed("Could not save rotated PDF")
        }

        await MainActor.run {
            progressHandler(1.0)
        }

        return RotateResult(
            sourceURL: pdfURL,
            outputURL: outputURL,
            pagesRotated: pagesRotated,
            angle: options.angle,
            processingTime: Date().timeIntervalSince(startTime)
        )
    }

    // MARK: - Add Signature

    func addSignature(
        pdfURL: URL,
        options: SignatureOptions,
        progressHandler: @escaping (Double) -> Void
    ) async throws -> SignatureResult {
        let startTime = Date()

        guard let document = PDFDocument(url: pdfURL) else {
            throw PDFToolsError.invalidPDF("Could not open PDF")
        }

        guard let signatureImage = options.signatureImage else {
            throw PDFToolsError.missingResource("No signature image provided")
        }

        var pagesModified = 0
        let pagesToSign: [Int]

        if options.applyToAllPages {
            pagesToSign = Array(0..<document.pageCount)
        } else {
            pagesToSign = [options.page - 1] // Convert to 0-indexed
        }

        for (index, pageIndex) in pagesToSign.enumerated() {
            guard let page = document.page(at: pageIndex) else { continue }

            let pageBounds = page.bounds(for: .mediaBox)
            let signatureRect = calculateSignatureRect(
                position: options.position,
                pageBounds: pageBounds,
                signatureSize: CGSize(width: options.width, height: options.height),
                customX: options.customX,
                customY: options.customY
            )

            // Create image annotation
            let annotation = PDFAnnotation(bounds: signatureRect, forType: .stamp, withProperties: nil)
            annotation.contents = "Signature"

            // Create image stamp
            if let cgImage = signatureImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                let stampImage = NSImage(cgImage: cgImage, size: NSSize(width: options.width, height: options.height))
                let imageAnnotation = ImageStampAnnotation(bounds: signatureRect, image: stampImage)
                page.addAnnotation(imageAnnotation)
                pagesModified += 1
            }

            await MainActor.run {
                progressHandler(Double(index + 1) / Double(pagesToSign.count) * 0.9)
            }
        }

        // Save signed document
        let outputDirectory = options.outputDirectory ?? pdfURL.deletingLastPathComponent()
        let baseName = options.customOutputName ?? "\(pdfURL.deletingPathExtension().lastPathComponent)_signed"
        let outputURL = outputDirectory.appendingPathComponent("\(baseName).pdf")

        guard document.write(to: outputURL) else {
            throw PDFToolsError.saveFailed("Could not save signed PDF")
        }

        await MainActor.run {
            progressHandler(1.0)
        }

        return SignatureResult(
            sourceURL: pdfURL,
            outputURL: outputURL,
            pagesModified: pagesModified,
            processingTime: Date().timeIntervalSince(startTime)
        )
    }

    // MARK: - Add Watermark

    func addWatermark(
        pdfURL: URL,
        options: WatermarkOptions,
        progressHandler: @escaping (Double) -> Void
    ) async throws -> WatermarkResult {
        let startTime = Date()

        guard let document = PDFDocument(url: pdfURL) else {
            throw PDFToolsError.invalidPDF("Could not open PDF")
        }

        var pagesModified = 0
        let pagesToWatermark: [Int]

        if options.applyToAllPages {
            pagesToWatermark = Array(0..<document.pageCount)
        } else {
            pagesToWatermark = options.specificPages.map { $0 - 1 }
        }

        for (index, pageIndex) in pagesToWatermark.enumerated() {
            guard let page = document.page(at: pageIndex) else { continue }

            let pageBounds = page.bounds(for: .mediaBox)

            if options.type == .text {
                // Create text watermark annotation
                let watermarkAnnotation = TextWatermarkAnnotation(
                    bounds: pageBounds,
                    text: options.text,
                    fontSize: options.fontSize,
                    rotation: options.rotation,
                    opacity: options.opacity,
                    color: options.textColor
                )
                page.addAnnotation(watermarkAnnotation)
                pagesModified += 1
            } else if let watermarkImage = options.image {
                // Image watermark
                let imageAnnotation = ImageStampAnnotation(
                    bounds: pageBounds,
                    image: watermarkImage,
                    opacity: options.opacity
                )
                page.addAnnotation(imageAnnotation)
                pagesModified += 1
            }

            await MainActor.run {
                progressHandler(Double(index + 1) / Double(pagesToWatermark.count) * 0.9)
            }
        }

        // Save watermarked document
        let outputDirectory = options.outputDirectory ?? pdfURL.deletingLastPathComponent()
        let baseName = options.customOutputName ?? "\(pdfURL.deletingPathExtension().lastPathComponent)_watermarked"
        let outputURL = outputDirectory.appendingPathComponent("\(baseName).pdf")

        guard document.write(to: outputURL) else {
            throw PDFToolsError.saveFailed("Could not save watermarked PDF")
        }

        await MainActor.run {
            progressHandler(1.0)
        }

        return WatermarkResult(
            sourceURL: pdfURL,
            outputURL: outputURL,
            pagesModified: pagesModified,
            processingTime: Date().timeIntervalSince(startTime)
        )
    }

    // MARK: - Apply Security (Password Protection)

    func applySecurity(
        pdfURL: URL,
        options: SecurityOptions,
        progressHandler: @escaping (Double) -> Void
    ) async throws -> SecurityResult {
        let startTime = Date()

        guard let document = PDFDocument(url: pdfURL) else {
            throw PDFToolsError.invalidPDF("Could not open PDF")
        }

        await MainActor.run {
            progressHandler(0.3)
        }

        // Prepare encryption options
        var encryptionOptions: [PDFDocumentWriteOption: Any] = [:]

        if !options.ownerPassword.isEmpty {
            encryptionOptions[.ownerPasswordOption] = options.ownerPassword
        }

        if !options.userPassword.isEmpty {
            encryptionOptions[.userPasswordOption] = options.userPassword
        }

        await MainActor.run {
            progressHandler(0.6)
        }

        // Save secured document
        let outputDirectory = options.outputDirectory ?? pdfURL.deletingLastPathComponent()
        let baseName = options.customOutputName ?? "\(pdfURL.deletingPathExtension().lastPathComponent)_protected"
        let outputURL = outputDirectory.appendingPathComponent("\(baseName).pdf")

        guard document.write(to: outputURL, withOptions: encryptionOptions) else {
            throw PDFToolsError.saveFailed("Could not save protected PDF")
        }

        await MainActor.run {
            progressHandler(1.0)
        }

        return SecurityResult(
            sourceURL: pdfURL,
            outputURL: outputURL,
            isEncrypted: !options.ownerPassword.isEmpty || !options.userPassword.isEmpty,
            processingTime: Date().timeIntervalSince(startTime)
        )
    }

    // MARK: - Unlock PDF

    func unlock(
        pdfURL: URL,
        password: String,
        outputDirectory: URL?,
        progressHandler: @escaping (Double) -> Void
    ) async throws -> SecurityResult {
        let startTime = Date()

        guard let document = PDFDocument(url: pdfURL) else {
            throw PDFToolsError.invalidPDF("Could not open PDF")
        }

        if document.isLocked {
            guard document.unlock(withPassword: password) else {
                throw PDFToolsError.securityError("Invalid password")
            }
        }

        await MainActor.run {
            progressHandler(0.5)
        }

        // Save unlocked document
        let outputDir = outputDirectory ?? pdfURL.deletingLastPathComponent()
        let baseName = "\(pdfURL.deletingPathExtension().lastPathComponent)_unlocked"
        let outputURL = outputDir.appendingPathComponent("\(baseName).pdf")

        guard document.write(to: outputURL) else {
            throw PDFToolsError.saveFailed("Could not save unlocked PDF")
        }

        await MainActor.run {
            progressHandler(1.0)
        }

        return SecurityResult(
            sourceURL: pdfURL,
            outputURL: outputURL,
            isEncrypted: false,
            processingTime: Date().timeIntervalSince(startTime)
        )
    }

    // MARK: - Private Helpers

    private func parsePageRanges(_ rangeString: String, maxPage: Int) -> [[Int]] {
        var ranges: [[Int]] = []
        let components = rangeString.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }

        for component in components {
            if component.contains("-") {
                let parts = component.components(separatedBy: "-")
                if parts.count == 2,
                   let start = Int(parts[0].trimmingCharacters(in: .whitespaces)),
                   let end = Int(parts[1].trimmingCharacters(in: .whitespaces)) {
                    let validStart = max(1, min(start, maxPage))
                    let validEnd = max(1, min(end, maxPage))
                    if validStart <= validEnd {
                        ranges.append(Array(validStart...validEnd))
                    }
                }
            } else if let page = Int(component) {
                let validPage = max(1, min(page, maxPage))
                ranges.append([validPage])
            }
        }

        return ranges
    }

    private func calculateSignatureRect(
        position: SignaturePosition,
        pageBounds: CGRect,
        signatureSize: CGSize,
        customX: CGFloat,
        customY: CGFloat
    ) -> CGRect {
        let margin: CGFloat = 20
        let x: CGFloat
        let y: CGFloat

        switch position {
        case .topLeft:
            x = margin
            y = pageBounds.height - signatureSize.height - margin
        case .topCenter:
            x = (pageBounds.width - signatureSize.width) / 2
            y = pageBounds.height - signatureSize.height - margin
        case .topRight:
            x = pageBounds.width - signatureSize.width - margin
            y = pageBounds.height - signatureSize.height - margin
        case .centerLeft:
            x = margin
            y = (pageBounds.height - signatureSize.height) / 2
        case .center:
            x = (pageBounds.width - signatureSize.width) / 2
            y = (pageBounds.height - signatureSize.height) / 2
        case .centerRight:
            x = pageBounds.width - signatureSize.width - margin
            y = (pageBounds.height - signatureSize.height) / 2
        case .bottomLeft:
            x = margin
            y = margin
        case .bottomCenter:
            x = (pageBounds.width - signatureSize.width) / 2
            y = margin
        case .bottomRight:
            x = pageBounds.width - signatureSize.width - margin
            y = margin
        case .custom:
            x = customX
            y = customY
        }

        return CGRect(x: x, y: y, width: signatureSize.width, height: signatureSize.height)
    }
}

// MARK: - Custom Annotations

class ImageStampAnnotation: PDFAnnotation {
    var stampImage: NSImage?
    var stampOpacity: CGFloat = 1.0

    init(bounds: CGRect, image: NSImage, opacity: CGFloat = 1.0) {
        self.stampImage = image
        self.stampOpacity = opacity
        super.init(bounds: bounds, forType: .stamp, withProperties: nil)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func draw(with box: PDFDisplayBox, in context: CGContext) {
        guard let image = stampImage,
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return
        }

        context.saveGState()
        context.setAlpha(stampOpacity)
        context.draw(cgImage, in: bounds)
        context.restoreGState()
    }
}

class TextWatermarkAnnotation: PDFAnnotation {
    var watermarkText: String
    var watermarkFontSize: CGFloat
    var watermarkRotation: CGFloat
    var watermarkOpacity: CGFloat
    var watermarkColor: NSColor

    init(bounds: CGRect, text: String, fontSize: CGFloat, rotation: CGFloat, opacity: CGFloat, color: NSColor) {
        self.watermarkText = text
        self.watermarkFontSize = fontSize
        self.watermarkRotation = rotation
        self.watermarkOpacity = opacity
        self.watermarkColor = color
        super.init(bounds: bounds, forType: .freeText, withProperties: nil)
    }

    required init?(coder: NSCoder) {
        self.watermarkText = ""
        self.watermarkFontSize = 72
        self.watermarkRotation = -45
        self.watermarkOpacity = 0.3
        self.watermarkColor = .gray
        super.init(coder: coder)
    }

    override func draw(with box: PDFDisplayBox, in context: CGContext) {
        context.saveGState()

        // Move to center of page
        let centerX = bounds.width / 2
        let centerY = bounds.height / 2
        context.translateBy(x: centerX, y: centerY)

        // Rotate
        let radians = watermarkRotation * .pi / 180
        context.rotate(by: radians)

        // Set text attributes
        let font = NSFont(name: "Helvetica-Bold", size: watermarkFontSize) ?? NSFont.systemFont(ofSize: watermarkFontSize)
        let colorWithOpacity = watermarkColor.withAlphaComponent(watermarkOpacity)

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: colorWithOpacity
        ]

        let textSize = (watermarkText as NSString).size(withAttributes: attributes)

        // Draw text centered
        let textRect = CGRect(
            x: -textSize.width / 2,
            y: -textSize.height / 2,
            width: textSize.width,
            height: textSize.height
        )

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        (watermarkText as NSString).draw(in: textRect, withAttributes: attributes)
        NSGraphicsContext.restoreGraphicsState()

        context.restoreGState()
    }
}

// MARK: - Errors

enum PDFToolsError: LocalizedError {
    case invalidPDF(String)
    case insufficientFiles(String)
    case saveFailed(String)
    case missingResource(String)
    case securityError(String)

    var errorDescription: String? {
        switch self {
        case .invalidPDF(let message): return "Invalid PDF: \(message)"
        case .insufficientFiles(let message): return "Insufficient files: \(message)"
        case .saveFailed(let message): return "Save failed: \(message)"
        case .missingResource(let message): return "Missing resource: \(message)"
        case .securityError(let message): return "Security error: \(message)"
        }
    }
}
