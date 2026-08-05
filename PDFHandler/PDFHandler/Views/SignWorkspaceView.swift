//
//  SignWorkspaceView.swift
//  PDFHandler
//
//  The Sign-mode detail pane: top-of-pane toolbar (open / save /
//  page nav), a field-type palette, the PDF preview with placement
//  overlays, and an info banner.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct SignWorkspaceView: View {
    @EnvironmentObject var appState: AppState
    @State private var keyMonitor: Any?

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            FieldToolbarView()
                .environmentObject(appState)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            Divider()
            PDFPreviewView()
                .environmentObject(appState)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onDrop(of: [.pdf, .fileURL], isTargeted: nil, perform: handleDrop)
            if let message = appState.errorMessage {
                banner(message, style: .error)
            } else if let saved = appState.lastSavedURL {
                banner("Saved to \(saved.lastPathComponent)", style: .info)
            }
        }
        .onAppear { installKeyMonitor() }
        .onDisappear { removeKeyMonitor() }
    }

    // MARK: - Keyboard (⌫ delete, Esc deselect, arrow nudge)

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            assumingMainActor { handleKeyDown(event) } ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    @MainActor
    private func handleKeyDown(_ event: NSEvent) -> Bool {
        guard appState.mode == .sign else { return false }
        // Stay out of the way while a sheet is up or while any text
        // field (the window's field editor) has focus.
        guard event.window?.sheetParent == nil else { return false }
        if NSApp.keyWindow?.firstResponder is NSTextView { return false }
        guard appState.selectedPlacementID != nil else { return false }

        switch event.keyCode {
        case 51, 117: // delete / forward delete
            appState.removeSelectedPlacement()
            return true
        case 53: // escape
            appState.selectedPlacementID = nil
            return true
        case 123, 124, 125, 126: // ← → ↓ ↑
            let step: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
            let (dx, dy): (CGFloat, CGFloat)
            switch event.keyCode {
            case 123: (dx, dy) = (-step, 0)
            case 124: (dx, dy) = (step, 0)
            case 125: (dx, dy) = (0, step)
            default:  (dx, dy) = (0, -step)
            }
            appState.nudgeSelectedPlacement(dxPoints: dx, dyPoints: dy)
            return true
        default:
            return false
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
    private func banner(_ message: String, style: BannerStyle) -> some View {
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
                          url.pathExtension.lowercased() == "pdf" else { return }
                    Task { @MainActor in appState.openDocument(at: url) }
                }
                return true
            }
        }
        return false
    }
}
