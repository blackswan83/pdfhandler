//
//  MenuBarView.swift
//  PDFHandler
//
//  Menu bar extra for quick conversions
//

import SwiftUI
import PDFKit
import UniformTypeIdentifiers

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @State private var recentFiles: [URL] = []
    @State private var isDragging = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "doc.richtext")
                    .font(.title2)
                    .foregroundStyle(.blue)

                Text("PDF Handler")
                    .font(.headline)

                Spacer()
            }
            .padding()
            .background(.bar)

            Divider()

            // Quick Actions
            VStack(spacing: 8) {
                // Drop Zone
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(
                            isDragging ? Color.blue : Color.secondary.opacity(0.3),
                            style: StrokeStyle(lineWidth: 2, dash: [5])
                        )
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(isDragging ? Color.blue.opacity(0.1) : Color.clear)
                        )

                    VStack(spacing: 4) {
                        Image(systemName: "arrow.down.doc")
                            .font(.title2)
                            .foregroundStyle(isDragging ? .blue : .secondary)

                        Text("Drop PDF here")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(height: 80)
                .onDrop(of: [.pdf, .fileURL], isTargeted: $isDragging) { providers in
                    handleDrop(providers: providers)
                    return true
                }

                // Quick Actions Buttons
                HStack(spacing: 8) {
                    QuickActionButton(
                        title: "Convert",
                        icon: "doc.text",
                        color: .blue
                    ) {
                        openFileAndConvert()
                    }

                    QuickActionButton(
                        title: "Compress",
                        icon: "arrow.down.right.and.arrow.up.left",
                        color: .green
                    ) {
                        openFileAndCompress()
                    }
                }
            }
            .padding()

            Divider()

            // Recent Files
            if !recentFiles.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Recent")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                        .padding(.top, 8)

                    ForEach(recentFiles.prefix(5), id: \.self) { url in
                        RecentFileRow(url: url) {
                            openFile(url)
                        }
                    }
                }

                Divider()
            }

            // Footer
            HStack {
                Button("Open App") {
                    NSApp.activate(ignoringOtherApps: true)
                    if let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
                        window.makeKeyAndOrderFront(nil)
                    }
                }

                Spacer()

                Button("Quit") {
                    NSApp.terminate(nil)
                }
            }
            .buttonStyle(.borderless)
            .font(.caption)
            .padding()
        }
        .frame(width: 280)
        .onAppear {
            loadRecentFiles()
        }
    }

    private func handleDrop(providers: [NSItemProvider]) {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.pdf.identifier, options: nil) { item, error in
                    if let url = item as? URL {
                        DispatchQueue.main.async {
                            openFile(url)
                        }
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                    if let data = item as? Data,
                       let path = String(data: data, encoding: .utf8),
                       let url = URL(string: path),
                       url.pathExtension.lowercased() == "pdf" {
                        DispatchQueue.main.async {
                            openFile(url)
                        }
                    }
                }
            }
        }
    }

    private func openFileAndConvert() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]

        if panel.runModal() == .OK, let url = panel.url {
            appState.loadPDFs(from: [url])
            appState.selectedTab = .convert
            appState.convertCurrentPDF()
            activateMainWindow()
        }
    }

    private func openFileAndCompress() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]

        if panel.runModal() == .OK, let url = panel.url {
            appState.loadPDFs(from: [url])
            appState.selectedTab = .compress
            appState.compressCurrentPDF()
            activateMainWindow()
        }
    }

    private func openFile(_ url: URL) {
        appState.loadPDFs(from: [url])
        addToRecentFiles(url)
        activateMainWindow()
    }

    private func activateMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
            window.makeKeyAndOrderFront(nil)
        }
    }

    private func loadRecentFiles() {
        // Load from UserDefaults
        if let data = UserDefaults.standard.data(forKey: "recentPDFFiles"),
           let urls = try? JSONDecoder().decode([URL].self, from: data) {
            recentFiles = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
        }
    }

    private func addToRecentFiles(_ url: URL) {
        recentFiles.removeAll { $0 == url }
        recentFiles.insert(url, at: 0)
        recentFiles = Array(recentFiles.prefix(10))

        if let data = try? JSONEncoder().encode(recentFiles) {
            UserDefaults.standard.set(data, forKey: "recentPDFFiles")
        }
    }
}

// MARK: - Quick Action Button

struct QuickActionButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title2)

                Text(title)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(color.opacity(0.1))
            .foregroundStyle(color)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Recent File Row

struct RecentFileRow: View {
    let url: URL
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: "doc.fill")
                    .foregroundStyle(.red)

                Text(url.lastPathComponent)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    MenuBarView()
        .environmentObject(AppState())
}
