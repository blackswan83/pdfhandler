//
//  AppState.swift
//  PDFHandler
//
//  Global application state management
//

import SwiftUI
import Combine
import PDFKit
import AppKit
import UniformTypeIdentifiers

@MainActor
class AppState: ObservableObject {
    // MARK: - Navigation State
    @Published var showFilePicker = false
    @Published var showSidebar = true
    @Published var selectedTab: AppTab = .convert

    // MARK: - PDF State
    @Published var selectedPDFs: [PDFDocument] = []
    @Published var selectedPDFURLs: [URL] = []
    @Published var currentPDFIndex: Int = 0

    // MARK: - Conversion State
    @Published var conversionProgress: Double = 0
    @Published var isConverting = false
    @Published var conversionResults: [ConversionResult] = []

    // MARK: - Compression State
    @Published var compressionProgress: Double = 0
    @Published var isCompressing = false
    @Published var compressionResults: [CompressionResult] = []
    @Published var targetCompressionRatio: Double = 0.5 // 50% of original

    // MARK: - Preview State
    @Published var showPreview = false
    @Published var previewMarkdown: String = ""

    // MARK: - Services
    let pdfService = PDFService()
    let markdownConverter = MarkdownConverter()
    let compressionService = CompressionService()
    let ocrService = OCRService()

    // MARK: - Preferences
    @AppStorage("outputDirectory") var outputDirectory: String = ""
    @AppStorage("includeYAMLFrontmatter") var includeYAMLFrontmatter = true
    @AppStorage("imageOutputFormat") var imageOutputFormat: String = "png"
    @AppStorage("defaultCompressionPreset") var defaultCompressionPreset: String = "ebook"

    var currentPDF: PDFDocument? {
        guard !selectedPDFs.isEmpty, currentPDFIndex < selectedPDFs.count else { return nil }
        return selectedPDFs[currentPDFIndex]
    }

    var currentPDFURL: URL? {
        guard !selectedPDFURLs.isEmpty, currentPDFIndex < selectedPDFURLs.count else { return nil }
        return selectedPDFURLs[currentPDFIndex]
    }

    // MARK: - Actions

    func loadPDFs(from urls: [URL]) {
        Task { @MainActor in
            selectedPDFURLs = urls
            selectedPDFs = urls.compactMap { url in
                PDFDocument(url: url)
            }
            currentPDFIndex = 0
        }
    }

    /// Show save panel and return selected URL
    private func showSavePanel(
        suggestedName: String,
        allowedTypes: [String],
        title: String
    ) async -> URL? {
        await withCheckedContinuation { continuation in
            let panel = NSSavePanel()
            panel.title = title
            panel.nameFieldStringValue = suggestedName
            panel.canCreateDirectories = true

            var contentTypes: [UTType] = []
            for ext in allowedTypes {
                if ext == "md" {
                    if let mdType = UTType(filenameExtension: "md") {
                        contentTypes.append(mdType)
                    }
                } else if ext == "pdf" {
                    contentTypes.append(.pdf)
                }
            }
            panel.allowedContentTypes = contentTypes

            panel.begin { response in
                if response == .OK {
                    continuation.resume(returning: panel.url)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    func convertCurrentPDF() {
        guard let pdf = currentPDF, let url = currentPDFURL else { return }

        let baseName = url.deletingPathExtension().lastPathComponent

        Task {
            // Show save dialog
            guard let outputURL = await showSavePanel(
                suggestedName: "\(baseName).md",
                allowedTypes: ["md"],
                title: "Save Markdown As"
            ) else {
                return // User cancelled
            }

            isConverting = true
            conversionProgress = 0

            do {
                let result = try await markdownConverter.convert(
                    pdf: pdf,
                    sourceURL: url,
                    options: ConversionOptions(
                        includeYAMLFrontmatter: includeYAMLFrontmatter,
                        imageOutputFormat: ImageFormat(rawValue: imageOutputFormat) ?? .png,
                        outputDirectory: outputURL.deletingLastPathComponent(),
                        customOutputName: outputURL.deletingPathExtension().lastPathComponent
                    ),
                    progressHandler: { [weak self] progress in
                        Task { @MainActor in
                            self?.conversionProgress = progress
                        }
                    }
                )
                conversionResults.append(result)
                previewMarkdown = result.markdown
                showPreview = true
            } catch {
                print("Conversion failed: \(error)")
            }

            isConverting = false
            conversionProgress = 1.0
        }
    }

    func compressCurrentPDF() {
        guard let url = currentPDFURL else { return }

        let baseName = url.deletingPathExtension().lastPathComponent

        Task {
            // Show save dialog
            guard let outputURL = await showSavePanel(
                suggestedName: "\(baseName)_compressed.pdf",
                allowedTypes: ["pdf"],
                title: "Save Compressed PDF As"
            ) else {
                return // User cancelled
            }

            isCompressing = true
            compressionProgress = 0

            do {
                let options = CompressionOptions(
                    preset: GhostscriptPreset.forRatio(targetCompressionRatio),
                    targetRatio: targetCompressionRatio,
                    outputDirectory: outputURL.deletingLastPathComponent(),
                    customOutputName: outputURL.deletingPathExtension().lastPathComponent
                )

                let result = try await compressionService.compress(
                    pdfURL: url,
                    targetRatio: targetCompressionRatio,
                    options: options,
                    progressHandler: { [weak self] progress in
                        Task { @MainActor in
                            self?.compressionProgress = progress
                        }
                    }
                )
                compressionResults.append(result)
            } catch {
                print("Compression failed: \(error)")
            }

            isCompressing = false
            compressionProgress = 1.0
        }
    }

    func convertAllPDFs() {
        Task {
            isConverting = true

            for (index, pdf) in selectedPDFs.enumerated() {
                currentPDFIndex = index
                conversionProgress = Double(index) / Double(selectedPDFs.count)

                guard let url = selectedPDFURLs[safe: index] else { continue }

                do {
                    let result = try await markdownConverter.convert(
                        pdf: pdf,
                        sourceURL: url,
                        options: ConversionOptions(
                            includeYAMLFrontmatter: includeYAMLFrontmatter,
                            imageOutputFormat: ImageFormat(rawValue: imageOutputFormat) ?? .png,
                            outputDirectory: outputDirectory.isEmpty ? nil : URL(fileURLWithPath: outputDirectory)
                        ),
                        progressHandler: { _ in }
                    )
                    conversionResults.append(result)
                } catch {
                    print("Conversion failed for \(url.lastPathComponent): \(error)")
                }
            }

            isConverting = false
            conversionProgress = 1.0
        }
    }
}

// MARK: - Supporting Types

enum AppTab: String, CaseIterable {
    case convert = "Convert to Markdown"
    case compress = "Compress PDF"
    case batch = "Batch Processing"
}

extension Collection {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
