//
//  PDFHandlerApp.swift
//  PDFHandler
//
//  A native Mac application for converting PDFs to Markdown
//  and compressing PDF files with precise size targeting.
//

import SwiftUI

@main
struct PDFHandlerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open PDF...") {
                    appState.showFilePicker = true
                }
                .keyboardShortcut("o", modifiers: .command)

                Divider()

                Button("Convert to Markdown") {
                    appState.convertCurrentPDF()
                }
                .keyboardShortcut("m", modifiers: [.command, .shift])
                .disabled(appState.selectedPDFs.isEmpty)

                Button("Compress PDF") {
                    appState.compressCurrentPDF()
                }
                .keyboardShortcut("k", modifiers: [.command, .shift])
                .disabled(appState.selectedPDFs.isEmpty)
            }

            CommandGroup(after: .sidebar) {
                Button("Toggle Sidebar") {
                    appState.showSidebar.toggle()
                }
                .keyboardShortcut("s", modifiers: [.command, .control])
            }
        }

        Settings {
            PreferencesView()
                .environmentObject(appState)
        }

        MenuBarExtra("PDF Handler", systemImage: "doc.richtext") {
            MenuBarView()
                .environmentObject(appState)
        }
        .menuBarExtraStyle(.window)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Register for Services menu
        NSApp.servicesProvider = ServiceProvider.shared
        NSUpdateDynamicServices()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false // Keep running for menu bar
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        // Handle files opened via Finder or context menu
        NotificationCenter.default.post(
            name: .openPDFFiles,
            object: nil,
            userInfo: ["urls": urls]
        )
    }
}

extension Notification.Name {
    static let openPDFFiles = Notification.Name("openPDFFiles")
}
