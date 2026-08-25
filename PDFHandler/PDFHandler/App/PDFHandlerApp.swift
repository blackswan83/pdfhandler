//
//  PDFHandlerApp.swift
//  PDFHandler
//
//  Single-window macOS app with four modes (Sign / Compress / Merge
//  / Convert to Markdown). File, Edit and per-mode commands live in
//  the menu bar.
//

import SwiftUI
import AppKit

/// Handles PDFs opened from outside the app: double-clicked in Finder,
/// dropped on the Dock icon, or passed via `open -a`. Without this,
/// the Info.plist document-type declaration makes the app *offerable*
/// as a PDF handler while it silently ignores the file.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        let pdfs = urls.filter { $0.pathExtension.lowercased() == "pdf" }
        guard !pdfs.isEmpty else { return }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .openDocumentURLs, object: pdfs)
        }
    }
}

@main
struct PDFHandlerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup("PDF Handler") {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 960, minHeight: 640)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open PDF…") {
                    NotificationCenter.default.post(name: .requestOpenPanel, object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)
            }
            CommandGroup(after: .saveItem) {
                Button("Save Signed PDF…") {
                    NotificationCenter.default.post(name: .requestSaveSigned, object: nil)
                }
                .keyboardShortcut("s", modifiers: .command)
            }
            CommandGroup(after: .toolbar) {
                Button("Zoom In") {
                    NotificationCenter.default.post(name: .requestZoomIn, object: nil)
                }
                .keyboardShortcut("+", modifiers: .command)
                Button("Zoom Out") {
                    NotificationCenter.default.post(name: .requestZoomOut, object: nil)
                }
                .keyboardShortcut("-", modifiers: .command)
                Button("Actual Size") {
                    NotificationCenter.default.post(name: .requestZoomActual, object: nil)
                }
                .keyboardShortcut("0", modifiers: .command)
                Button("Zoom to Fit") {
                    NotificationCenter.default.post(name: .requestZoomFit, object: nil)
                }
                .keyboardShortcut("9", modifiers: .command)
                Divider()
            }
            CommandGroup(replacing: .undoRedo) {
                // While a text field is being edited, ⌘Z belongs to the
                // field editor; otherwise it drives placement undo.
                Button("Undo") {
                    if let textView = NSApp.keyWindow?.firstResponder as? NSTextView,
                       let undoManager = textView.undoManager, undoManager.canUndo {
                        undoManager.undo()
                    } else {
                        NotificationCenter.default.post(name: .requestUndo, object: nil)
                    }
                }
                .keyboardShortcut("z", modifiers: .command)
                Button("Redo") {
                    if let textView = NSApp.keyWindow?.firstResponder as? NSTextView,
                       let undoManager = textView.undoManager, undoManager.canRedo {
                        undoManager.redo()
                    } else {
                        NotificationCenter.default.post(name: .requestRedo, object: nil)
                    }
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])
            }
        }
    }
}

extension Notification.Name {
    static let requestOpenPanel  = Notification.Name("pdfhandler.requestOpenPanel")
    static let requestSaveSigned = Notification.Name("pdfhandler.requestSaveSigned")
    static let requestUndo       = Notification.Name("pdfhandler.requestUndo")
    static let requestRedo       = Notification.Name("pdfhandler.requestRedo")
    static let requestZoomIn     = Notification.Name("pdfhandler.requestZoomIn")
    static let requestZoomOut    = Notification.Name("pdfhandler.requestZoomOut")
    static let requestZoomActual = Notification.Name("pdfhandler.requestZoomActual")
    static let requestZoomFit    = Notification.Name("pdfhandler.requestZoomFit")
    /// Object is `[URL]` of PDFs to open, from Finder / Dock / open(1).
    static let openDocumentURLs  = Notification.Name("pdfhandler.openDocumentURLs")
}
