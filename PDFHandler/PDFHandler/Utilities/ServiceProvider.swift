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

        // Show notification
        showNotification(
            title: mode == .convert ? "Converting PDF" : "Compressing PDF",
            message: urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) files"
        )
    }

    private func showNotification(title: String, message: String) {
        let notification = NSUserNotification()
        notification.title = title
        notification.informativeText = message
        notification.soundName = nil

        NSUserNotificationCenter.default.deliver(notification)
    }
}

// MARK: - Quick Actions (Shortcuts.app integration)

import Intents

@available(macOS 12.0, *)
class ConvertPDFIntent: INIntent {
    @NSManaged var inputFile: INFile?
}

@available(macOS 12.0, *)
class ConvertPDFIntentHandler: NSObject, ConvertPDFIntentHandling {
    func handle(intent: ConvertPDFIntent, completion: @escaping (ConvertPDFIntentResponse) -> Void) {
        guard let inputFile = intent.inputFile,
              let data = inputFile.data else {
            completion(ConvertPDFIntentResponse(code: .failure, userActivity: nil))
            return
        }

        Task {
            do {
                // Create temp file
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension("pdf")

                try data.write(to: tempURL)

                // Convert
                guard let pdf = PDFDocument(url: tempURL) else {
                    completion(ConvertPDFIntentResponse(code: .failure, userActivity: nil))
                    return
                }

                let converter = MarkdownConverter()
                let result = try await converter.convert(
                    pdf: pdf,
                    sourceURL: tempURL,
                    options: ConversionOptions(),
                    progressHandler: { _ in }
                )

                // Read output
                let outputData = try Data(contentsOf: result.outputURL)
                let outputFile = INFile(
                    data: outputData,
                    filename: result.outputURL.lastPathComponent,
                    typeIdentifier: "public.plain-text"
                )

                let response = ConvertPDFIntentResponse(code: .success, userActivity: nil)
                response.outputFile = outputFile
                completion(response)

                // Cleanup
                try? FileManager.default.removeItem(at: tempURL)

            } catch {
                completion(ConvertPDFIntentResponse(code: .failure, userActivity: nil))
            }
        }
    }

    func resolveInputFile(for intent: ConvertPDFIntent, with completion: @escaping (INFileResolutionResult) -> Void) {
        if let file = intent.inputFile {
            completion(.success(with: file))
        } else {
            completion(.needsValue())
        }
    }
}

@available(macOS 12.0, *)
class ConvertPDFIntentResponse: INIntentResponse {
    @NSManaged var outputFile: INFile?
}

@available(macOS 12.0, *)
protocol ConvertPDFIntentHandling {
    func handle(intent: ConvertPDFIntent, completion: @escaping (ConvertPDFIntentResponse) -> Void)
    func resolveInputFile(for intent: ConvertPDFIntent, with completion: @escaping (INFileResolutionResult) -> Void)
}

// MARK: - Drag and Drop Extension

extension NSItemProvider {
    func loadPDFURL() async -> URL? {
        await withCheckedContinuation { continuation in
            if hasItemConformingToTypeIdentifier("com.adobe.pdf") {
                loadItem(forTypeIdentifier: "com.adobe.pdf", options: nil) { item, error in
                    if let url = item as? URL {
                        continuation.resume(returning: url)
                    } else {
                        continuation.resume(returning: nil)
                    }
                }
            } else {
                continuation.resume(returning: nil)
            }
        }
    }
}

// MARK: - File Bookmark Handling

class FileBookmarkManager {
    static let shared = FileBookmarkManager()

    private let bookmarksKey = "securityScopedBookmarks"

    func saveBookmark(for url: URL) throws {
        let bookmark = try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )

        var bookmarks = loadBookmarks()
        bookmarks[url.path] = bookmark
        saveBookmarks(bookmarks)
    }

    func resolveBookmark(for path: String) -> URL? {
        guard let bookmarks = loadBookmarks()[path] else { return nil }

        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmarks,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return nil }

        if isStale {
            try? saveBookmark(for: url)
        }

        return url
    }

    private func loadBookmarks() -> [String: Data] {
        guard let data = UserDefaults.standard.data(forKey: bookmarksKey),
              let bookmarks = try? JSONDecoder().decode([String: Data].self, from: data) else {
            return [:]
        }
        return bookmarks
    }

    private func saveBookmarks(_ bookmarks: [String: Data]) {
        if let data = try? JSONEncoder().encode(bookmarks) {
            UserDefaults.standard.set(data, forKey: bookmarksKey)
        }
    }
}
