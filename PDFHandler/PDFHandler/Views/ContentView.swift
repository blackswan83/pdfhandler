//
//  ContentView.swift
//  PDFHandler
//
//  Root layout. NavigationSplitView with a mode-switcher sidebar on
//  the left and the per-mode workspace on the right.
//
//  The menu/notification plumbing lives in ViewModifiers below rather
//  than chained onto `body`. A dozen modifiers on one expression blew
//  past the SwiftUI type-checker's budget ("unable to type-check this
//  expression in reasonable time"); each modifier now type-checks on
//  its own.
//

import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var isDropTargeted = false

    /// Visible confirmation that a drag is over a live target. Without
    /// it a drop that silently fails is indistinguishable from one the
    /// app never saw.
    private var dropBanner: some View {
        Label("Drop to open", systemImage: "arrow.down.doc")
            .font(.headline)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().stroke(Color.accentColor, lineWidth: 1.5))
            .padding(.top, 16)
            .transition(.opacity)
    }

    var body: some View {
        // Drop targets go on the panes, NOT on the NavigationSplitView.
        // A split view is a container without a drawing area of its
        // own, and an .onDrop attached to it never fires — which is
        // exactly how drag-and-drop got broken when the per-pane
        // handlers were consolidated onto the root.
        NavigationSplitView {
            sidebar
                .onDrop(of: PDFDrop.acceptedTypes, isTargeted: nil) { providers in
                    PDFDrop.receive(providers, onLoaded: openURLs)
                }
        } detail: {
            detailPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onDrop(of: PDFDrop.acceptedTypes, isTargeted: $isDropTargeted) { providers in
                    PDFDrop.receive(providers, onLoaded: openURLs)
                }
                .overlay(alignment: .top) {
                    if isDropTargeted { dropBanner }
                }
        }
        .navigationSplitViewStyle(.balanced)
        .sheet(isPresented: $appState.isPresentingNewSignature) {
            NewSignatureView()
                .environmentObject(appState)
        }
        .modifier(FileCommandRouting(openURLs: openURLs, openPanel: openPDFInCurrentMode))
        .modifier(ZoomCommandRouting())
        .onAppear {
            // Development scaffolding for CI screenshot capture; a
            // no-op unless --screenshot-demo was passed at launch.
            if ScreenshotDemo.isEnabled, appState.document == nil {
                appState.loadScreenshotDemo()
                if let mode = ScreenshotDemo.initialMode { appState.mode = mode }
            }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $appState.mode) {
            Section("Tools") {
                ForEach(AppMode.allCases) { mode in
                    Label(mode.displayName, systemImage: mode.systemImage).tag(mode)
                }
            }
            if appState.mode == .sign {
                LibrarySidebarSections()
                    .environmentObject(appState)
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 220, idealWidth: 240)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailPane: some View {
        switch appState.mode {
        case .sign:     SignWorkspaceView()
        case .compress: CompressView()
        case .merge:    MergeView()
        case .convert:  ConvertView()
        }
    }

    // MARK: - Opening files

    /// Routes incoming PDFs — dropped, or opened from Finder / the
    /// Dock — to whichever mode makes sense. Merge accumulates a
    /// queue; everything else takes the first file.
    private func openURLs(_ urls: [URL]) {
        guard let first = urls.first else { return }
        switch appState.mode {
        case .merge:
            appState.mergeItems.append(contentsOf: urls.map { MergeItem(url: $0) })
        case .compress:
            appState.compressSourceURL = first
        case .convert:
            appState.convertSourceURL = first
        case .sign:
            appState.openDocument(at: first)
        }
    }

    private func openPDFInCurrentMode() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = (appState.mode == .merge)
        guard panel.runModal() == .OK else { return }
        openURLs(panel.urls)
    }
}

// MARK: - Command routing

private struct FileCommandRouting: ViewModifier {
    @EnvironmentObject var appState: AppState
    let openURLs: ([URL]) -> Void
    let openPanel: () -> Void

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .requestOpenPanel)) { _ in
                openPanel()
            }
            .onReceive(NotificationCenter.default.publisher(for: .openDocumentURLs)) { note in
                if let urls = note.object as? [URL] { openURLs(urls) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .requestSaveSigned)) { _ in
                if appState.mode == .sign { appState.saveSignedPDF() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .requestUndo)) { _ in
                appState.undoCoordinator.undo()
            }
            .onReceive(NotificationCenter.default.publisher(for: .requestRedo)) { _ in
                appState.undoCoordinator.redo()
            }
    }
}

private struct ZoomCommandRouting: ViewModifier {
    @EnvironmentObject var appState: AppState

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .requestZoomIn)) { _ in
                if appState.mode == .sign { appState.zoomIn() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .requestZoomOut)) { _ in
                if appState.mode == .sign { appState.zoomOut() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .requestZoomActual)) { _ in
                if appState.mode == .sign { appState.zoomToActualSize() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .requestZoomFit)) { _ in
                if appState.mode == .sign { appState.zoomToFit() }
            }
    }
}
