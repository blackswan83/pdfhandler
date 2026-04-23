//
//  PDFHandlerApp.swift
//  PDFHandler
//
//  Single-window macOS app with four modes (Sign / Compress / Merge
//  / Convert to Markdown). File, Edit and per-mode commands live in
//  the menu bar.
//

import SwiftUI

@main
struct PDFHandlerApp: App {
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
            CommandGroup(replacing: .undoRedo) {
                Button("Undo") {
                    NotificationCenter.default.post(name: .requestUndo, object: nil)
                }
                .keyboardShortcut("z", modifiers: .command)
                Button("Redo") {
                    NotificationCenter.default.post(name: .requestRedo, object: nil)
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
}
