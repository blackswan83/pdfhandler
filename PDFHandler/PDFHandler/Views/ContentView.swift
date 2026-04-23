//
//  ContentView.swift
//  PDFHandler
//
//  Root layout: library sidebar on the left, toolbar + PDF preview on
//  the right. Wires up the Open / Save keyboard commands and the
//  "new signature" sheet.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        NavigationSplitView {
            LibrarySidebarView()
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
        .sheet(isPresented: $appState.isPresentingNewSignature) {
            NewSignatureView()
                .environmentObject(appState)
        }
        .onReceive(NotificationCenter.default.publisher(for: .requestOpenPanel)) { _ in
            openPDF()
        }
        .onReceive(NotificationCenter.default.publisher(for: .requestSaveSigned)) { _ in
            appState.saveSignedPDF()
        }
    }

    // MARK: - Detail

    private var detail: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            PDFPreviewView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onDrop(of: [.pdf, .fileURL], isTargeted: nil, perform: handleDrop)
            if let message = appState.errorMessage {
                banner(message: message, style: .error)
            } else if let saved = appState.lastSavedURL {
                banner(message: "Saved to \(saved.lastPathComponent)", style: .info)
            }
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            Button {
                openPDF()
            } label: {
                Label("Open PDF", systemImage: "folder")
            }

            if let url = appState.documentURL {
                Text(url.lastPathComponent)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            pagePicker

            Button {
                appState.saveSignedPDF()
            } label: {
                Label("Save signed PDF", systemImage: "square.and.arrow.down")
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(appState.document == nil || appState.placements.isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var pagePicker: some View {
        if let pdf = appState.document, pdf.pageCount > 1 {
            HStack(spacing: 6) {
                Button {
                    appState.currentPageIndex = max(0, appState.currentPageIndex - 1)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(appState.currentPageIndex <= 0)
                .buttonStyle(.borderless)

                Text("Page \(appState.currentPageIndex + 1) of \(pdf.pageCount)")
                    .font(.subheadline.monospacedDigit())
                    .frame(minWidth: 120)

                Button {
                    appState.currentPageIndex = min(pdf.pageCount - 1, appState.currentPageIndex + 1)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(appState.currentPageIndex >= pdf.pageCount - 1)
                .buttonStyle(.borderless)
            }
        }
    }

    // MARK: - Banner

    private enum BannerStyle { case info, error }

    @ViewBuilder
    private func banner(message: String, style: BannerStyle) -> some View {
        HStack(spacing: 8) {
            Image(systemName: style == .error ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(style == .error ? Color.red : Color.green)
            Text(message)
                .font(.callout)
            Spacer()
            Button("Dismiss") {
                appState.errorMessage = nil
                appState.lastSavedURL = nil
            }
            .buttonStyle(.borderless)
        }
        .padding(10)
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    // MARK: - Actions

    private func openPDF() {
        let panel = NSOpenPanel()
        panel.title = "Open PDF"
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            appState.openDocument(at: url)
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
                    guard let data = data as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil),
                          url.pathExtension.lowercased() == "pdf"
                    else { return }
                    Task { @MainActor in
                        appState.openDocument(at: url)
                    }
                }
                return true
            }
        }
        return false
    }
}
