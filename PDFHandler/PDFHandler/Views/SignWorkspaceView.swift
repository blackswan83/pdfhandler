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
            if showsTextInspector {
                TextInspectorView()
                    .environmentObject(appState)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                Divider()
            }
            PDFPreviewView()
                .environmentObject(appState)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if let message = appState.errorMessage {
                banner(message, style: .error)
            } else if let saved = appState.lastSavedURL {
                banner("Saved to \(saved.lastPathComponent)", style: .info)
            }
        }
        .onAppear { installKeyMonitor() }
        .onDisappear { removeKeyMonitor() }
    }

    /// Shown while a text field is selected, or while the text tools
    /// are armed so the style can be set before placing anything.
    private var showsTextInspector: Bool {
        appState.selectedTextPlacement != nil
            || appState.activeTool == .freeText
            || appState.activeTool == .date
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
        // Stay out of the way while a sheet is up.
        guard event.window?.sheetParent == nil else { return false }

        // Zoom. Command-modified keys never insert text, so these are
        // safe to handle even while a field is being edited. Local
        // monitors see the event before menu key equivalents, which is
        // how ⌘= works as an alias for the menu's ⌘+.
        if event.modifierFlags.contains(.command), appState.document != nil {
            switch event.charactersIgnoringModifiers {
            case "=", "+": appState.zoomIn();          return true
            case "-":      appState.zoomOut();         return true
            case "0":      appState.zoomToActualSize(); return true
            case "9":      appState.zoomToFit();       return true
            default: break
            }
        }

        // Everything below drives the selected placement, so stay clear
        // of the window's field editor.
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
        HStack(spacing: 10) {
            Button {
                openPDF()
            } label: {
                Label("Open PDF", systemImage: "folder")
            }
            .layoutPriority(1)

            if let url = appState.documentURL {
                // Lowest layout priority and a hard cap: at the 960pt
                // minimum window width something has to give, and the
                // filename is the one thing here that is disposable.
                // Without this the Save button truncated instead.
                Text(url.lastPathComponent)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 200)
                    .layoutPriority(-1)
                    .help(url.path)
            }

            Spacer(minLength: 4)

            zoomControls
            pagePicker

            Menu {
                Toggle("Also save an unsigned filled copy", isOn: $appState.alsoSaveUnsignedCopy)
                Divider()
                Text("The original is never modified.")
            } label: {
                Label("Save signed PDF", systemImage: "square.and.arrow.down")
            } primaryAction: {
                appState.saveSignedPDF()
            }
            .menuStyle(.borderlessButton)
            .keyboardShortcut("s", modifiers: .command)
            .disabled(appState.document == nil || appState.placements.isEmpty)
            .fixedSize()
            .layoutPriority(2)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var zoomControls: some View {
        if appState.document != nil {
            HStack(spacing: 2) {
                Button {
                    appState.zoomOut()
                } label: {
                    Image(systemName: "minus.magnifyingglass")
                }
                .buttonStyle(.borderless)
                .disabled(!appState.canZoomOut)
                .help("Zoom out (⌘−)")

                Menu(appState.zoomLabel) {
                    Button("Zoom to Fit") { appState.zoomToFit() }
                    Button("Actual Size") { appState.zoomToActualSize() }
                    Divider()
                    ForEach(ZoomScale.stops, id: \.self) { stop in
                        Button("\(Int(stop * 100))%") { appState.setZoom(stop) }
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .frame(minWidth: 62)
                .help("Zoom level")

                Button {
                    appState.zoomIn()
                } label: {
                    Image(systemName: "plus.magnifyingglass")
                }
                .buttonStyle(.borderless)
                .disabled(!appState.canZoomIn)
                .help("Zoom in (⌘+)")
            }
            Divider().frame(height: 16)
        }
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
                    .fixedSize()
                    .frame(minWidth: 92)

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

}
