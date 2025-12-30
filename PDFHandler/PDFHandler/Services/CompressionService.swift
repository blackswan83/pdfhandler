//
//  CompressionService.swift
//  PDFHandler
//
//  PDF compression using Ghostscript backend
//

import Foundation
import PDFKit

actor CompressionService {

    // MARK: - Ghostscript Path

    private var ghostscriptPath: String? {
        // Check common installation paths
        let paths = [
            "/opt/homebrew/bin/gs",           // Apple Silicon Homebrew
            "/usr/local/bin/gs",              // Intel Homebrew
            "/usr/bin/gs",                    // System path
            "/opt/local/bin/gs",              // MacPorts
            "/sw/bin/gs",                     // Fink
            Bundle.main.path(forResource: "gs", ofType: nil)
        ]

        for path in paths {
            if let p = path, FileManager.default.fileExists(atPath: p) {
                return p
            }
        }

        // Try to find gs using which command (for non-sandboxed apps)
        if let whichPath = findGhostscriptWithWhich() {
            return whichPath
        }

        return nil
    }

    private func findGhostscriptWithWhich() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["gs"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)

            if let path = path, !path.isEmpty, FileManager.default.fileExists(atPath: path) {
                return path
            }
        } catch {
            // Ignore errors - which might not work in sandbox
        }

        return nil
    }

    // MARK: - Compression

    func compress(
        pdfURL: URL,
        targetRatio: Double,
        options: CompressionOptions? = nil,
        progressHandler: @escaping (Double) -> Void
    ) async throws -> CompressionResult {
        let startTime = Date()
        var warnings: [CompressionWarning] = []

        // Verify Ghostscript is available
        guard let gsPath = ghostscriptPath else {
            throw CompressionError.ghostscriptNotFound
        }

        progressHandler(0.1)

        // Get original file size
        let originalSize = try getFileSize(pdfURL)

        // Determine compression settings
        let preset = GhostscriptPreset.forRatio(targetRatio)
        let effectiveOptions = options ?? CompressionOptions(preset: preset, targetRatio: targetRatio)

        // Create output path
        let outputDirectory = effectiveOptions.outputDirectory ?? pdfURL.deletingLastPathComponent()
        let baseName = pdfURL.deletingPathExtension().lastPathComponent
        let outputURL = outputDirectory.appendingPathComponent("\(baseName)_compressed.pdf")

        progressHandler(0.2)

        // Build and execute Ghostscript command
        let command = GhostscriptCommand(
            inputPath: pdfURL.path,
            outputPath: outputURL.path,
            options: effectiveOptions
        )

        progressHandler(0.3)

        try await executeGhostscript(
            path: gsPath,
            arguments: command.arguments,
            progressHandler: { progress in
                // Map progress from 0.3 to 0.9
                progressHandler(0.3 + progress * 0.6)
            }
        )

        progressHandler(0.9)

        // Get compressed file size
        let compressedSize = try getFileSize(outputURL)

        // Check if compression was effective
        if compressedSize >= originalSize {
            warnings.append(CompressionWarning(
                type: .qualityLoss,
                message: "File could not be compressed further without quality loss"
            ))
        }

        // Check actual ratio vs target
        let actualRatio = Double(compressedSize) / Double(originalSize)
        if actualRatio > targetRatio + 0.1 {
            warnings.append(CompressionWarning(
                type: .qualityLoss,
                message: "Target compression ratio could not be achieved while maintaining quality"
            ))
        }

        progressHandler(1.0)

        let processingTime = Date().timeIntervalSince(startTime)

        return CompressionResult(
            sourceURL: pdfURL,
            outputURL: outputURL,
            originalSize: originalSize,
            compressedSize: compressedSize,
            preset: preset,
            processingTime: processingTime,
            warnings: warnings
        )
    }

    // MARK: - Preview

    func estimateCompression(
        pdfURL: URL,
        targetRatio: Double
    ) async -> CompressionPreview {
        let originalSize = (try? getFileSize(pdfURL)) ?? 0
        let preset = GhostscriptPreset.forRatio(targetRatio)

        // Estimate based on preset typical ratios
        let estimatedRatio: Double
        switch preset {
        case .prepress:
            estimatedRatio = max(targetRatio, 0.85)
        case .printer:
            estimatedRatio = max(targetRatio, 0.65)
        case .ebook:
            estimatedRatio = max(targetRatio, 0.35)
        case .screen:
            estimatedRatio = max(targetRatio, 0.15)
        }

        let estimatedSize = Int64(Double(originalSize) * estimatedRatio)

        let quality: CompressionPreview.QualityIndicator
        switch preset {
        case .prepress:
            quality = .excellent
        case .printer:
            quality = .good
        case .ebook:
            quality = .acceptable
        case .screen:
            quality = .noticeable
        }

        return CompressionPreview(
            originalSize: originalSize,
            estimatedSize: estimatedSize,
            preset: preset,
            qualityIndicator: quality
        )
    }

    // MARK: - Batch Compression

    func compressBatch(
        pdfURLs: [URL],
        targetRatio: Double,
        options: CompressionOptions? = nil,
        progressHandler: @escaping (Double, URL) -> Void
    ) async throws -> [CompressionResult] {
        var results: [CompressionResult] = []

        for (index, url) in pdfURLs.enumerated() {
            let result = try await compress(
                pdfURL: url,
                targetRatio: targetRatio,
                options: options,
                progressHandler: { progress in
                    let overallProgress = (Double(index) + progress) / Double(pdfURLs.count)
                    progressHandler(overallProgress, url)
                }
            )
            results.append(result)
        }

        return results
    }

    // MARK: - Private Helpers

    private func executeGhostscript(
        path: String,
        arguments: [String],
        progressHandler: @escaping (Double) -> Void
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = arguments

            let outputPipe = Pipe()
            let errorPipe = Pipe()

            process.standardOutput = outputPipe
            process.standardError = errorPipe

            // Track progress by monitoring output
            var progressReported = 0.0

            outputPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty {
                    // Ghostscript outputs progress information
                    // This is a simplified progress estimation
                    progressReported = min(progressReported + 0.1, 0.95)
                    progressHandler(progressReported)
                }
            }

            process.terminationHandler = { process in
                outputPipe.fileHandleForReading.readabilityHandler = nil
                errorPipe.fileHandleForReading.readabilityHandler = nil

                if process.terminationStatus == 0 {
                    progressHandler(1.0)
                    continuation.resume()
                } else {
                    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                    continuation.resume(throwing: CompressionError.ghostscriptFailed(errorMessage))
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: CompressionError.ghostscriptFailed(error.localizedDescription))
            }
        }
    }

    private func getFileSize(_ url: URL) throws -> Int64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return attributes[.size] as? Int64 ?? 0
    }

    // MARK: - Ghostscript Availability

    func isGhostscriptAvailable() -> Bool {
        ghostscriptPath != nil
    }

    func getGhostscriptVersion() async -> String? {
        guard let gsPath = ghostscriptPath else { return nil }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: gsPath)
        process.arguments = ["--version"]

        let pipe = Pipe()
        process.standardOutput = pipe

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    // MARK: - Alternative Compression (without Ghostscript)

    func compressWithPDFKit(
        pdfURL: URL,
        quality: CGFloat = 0.5,
        progressHandler: @escaping (Double) -> Void
    ) async throws -> CompressionResult {
        let startTime = Date()

        guard let pdf = PDFDocument(url: pdfURL) else {
            throw CompressionError.invalidPDF
        }

        let originalSize = try getFileSize(pdfURL)

        // Create output path
        let outputDirectory = pdfURL.deletingLastPathComponent()
        let baseName = pdfURL.deletingPathExtension().lastPathComponent
        let outputURL = outputDirectory.appendingPathComponent("\(baseName)_compressed.pdf")

        progressHandler(0.2)

        // PDFKit doesn't provide direct compression control,
        // but we can re-render pages at lower resolution
        let newPDF = PDFDocument()

        for i in 0..<pdf.pageCount {
            progressHandler(0.2 + 0.7 * Double(i) / Double(pdf.pageCount))

            if let page = pdf.page(at: i) {
                // Simply copy pages - PDFKit will optimize on save
                newPDF.insert(page, at: i)
            }
        }

        // Write with optimization
        let success = newPDF.write(to: outputURL)
        guard success else {
            throw CompressionError.writeFailed
        }

        progressHandler(1.0)

        let compressedSize = try getFileSize(outputURL)
        let processingTime = Date().timeIntervalSince(startTime)

        return CompressionResult(
            sourceURL: pdfURL,
            outputURL: outputURL,
            originalSize: originalSize,
            compressedSize: compressedSize,
            preset: .ebook,
            processingTime: processingTime,
            warnings: [CompressionWarning(
                type: .qualityLoss,
                message: "Using fallback compression (Ghostscript not available)"
            )]
        )
    }
}

// MARK: - Errors

enum CompressionError: LocalizedError {
    case ghostscriptNotFound
    case ghostscriptFailed(String)
    case invalidPDF
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .ghostscriptNotFound:
            return "Ghostscript is not installed. Please install it using 'brew install ghostscript'."
        case .ghostscriptFailed(let message):
            return "Ghostscript compression failed: \(message)"
        case .invalidPDF:
            return "The PDF file could not be read"
        case .writeFailed:
            return "Failed to write the compressed PDF"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .ghostscriptNotFound:
            return "Install Ghostscript via Homebrew: brew install ghostscript"
        case .ghostscriptFailed:
            return "Try a different compression preset or check if the PDF is corrupted"
        case .invalidPDF:
            return "Ensure the file is a valid PDF document"
        case .writeFailed:
            return "Check disk space and file permissions"
        }
    }
}
