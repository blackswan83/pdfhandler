//
//  PDFHandlerApp.swift
//  PDFHandler
//
//  Single-window macOS app for signing PDFs with a persistent
//  signature library and DocuSign-style drag/resize placements.
//

import SwiftUI

@main
struct PDFHandlerApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup("PDF Handler") {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 900, minHeight: 600)
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
        }
    }
}

extension Notification.Name {
    static let requestOpenPanel  = Notification.Name("pdfhandler.requestOpenPanel")
    static let requestSaveSigned = Notification.Name("pdfhandler.requestSaveSigned")
}
