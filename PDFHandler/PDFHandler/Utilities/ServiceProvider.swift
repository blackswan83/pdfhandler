//
//  ServiceProvider.swift
//  PDFHandler
//
//  macOS Services integration for right-click context menu
//

import Foundation
import AppKit
import PDFKit

class ServiceProvider: NSObject {
    static let shared = ServiceProvider()

    private override init() {
        super.init()
    }

    /// Convert PDF to Markdown - available in Services menu
    @objc func convertToMarkdown(_ pboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        guard let urls = pboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true,
            .urlReadingContentsConformToTypes: ["com.adobe.pdf"]
        ]) as? [URL] else {
            error.pointee = "No PDF files found" as NSString
            return
        }

        Task { @MainActor in
            await processFiles(urls, mode: .convert)
        }
    }

    /// Compress PDF - available in Services menu
    @objc func compressPDF(_ pboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        guard let urls = pboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true,
            .urlReadingContentsConformToTypes: ["com.adobe.pdf"]
        ]) as? [URL] else {
            error.pointee = "No PDF files found" as NSString
            return
        }

        Task { @MainActor in
            await processFiles(urls, mode: .compress)
        }
    }

    private enum ProcessingMode {
        case convert
        case compress
    }

    @MainActor
    private func processFiles(_ urls: [URL], mode: ProcessingMode) async {
        // Activate the app
        NSApp.activate(ignoringOtherApps: true)

        // Notify to load files
        NotificationCenter.default.post(
            name: .openPDFFiles,
            object: nil,
            userInfo: ["urls": urls, "mode": mode == .convert ? "convert" : "compress"]
        )
    }
}

// MARK: - Quick Actions Support

enum QuickActionType: String {
    case convert = "com.pdfhandler.convert"
    case compress = "com.pdfhandler.compress"
}

class QuickActionHandler {
    static let shared = QuickActionHandler()

    func handleAction(_ type: QuickActionType, fileURL: URL) async throws {
        guard let pdf = PDFDocument(url: fileURL) else {
            throw QuickActionError.invalidPDF
        }

        switch type {
        case .convert:
            let converter = MarkdownConverter()
            _ = try await converter.convert(
                pdf: pdf,
                sourceURL: fileURL,
                options: ConversionOptions(),
                progressHandler: { _ in }
            )
        case .compress:
            let service = CompressionService()
            _ = try await service.compress(
                pdfURL: fileURL,
                targetRatio: 0.5,
                options: CompressionOptions(),
                progressHandler: { _ in }
            )
        }
    }
}

enum QuickActionError: Error {
    case invalidPDF
    case conversionFailed
    case compressionFailed
}
