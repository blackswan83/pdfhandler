//
//  ContentView.swift
//  PDFHandler
//
//  Root layout. NavigationSplitView with a mode-switcher sidebar on
//  the left and the per-mode workspace on the right.
//

import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailPane
        }
        .navigationSplitViewStyle(.balanced)
        // Whole-window drop target: dropping a PDF anywhere opens it,
        // switching to Sign mode. Previously only the preview area
        // accepted drops, so dropping on the sidebar or toolbar — or
        // on the empty-state pane in another mode — did nothing.
        .onDrop(of: PDFDrop.acceptedTypes, isTargeted: nil) { providers in
            PDFDrop.receive(providers) { urls in
                openDropped(urls)
            }
        }
        .sheet(isPresented: $appState.isPresentingNewSignature) {
            NewSignatureView()
                .environmentObject(appState)
        }
        .onReceive(NotificationCenter.default.publisher(for: .openDocumentURLs)) { note in
            if let urls = note.object as? [URL] { openDropped(urls) }
        }
        .onAppear {
            // Development scaffolding for CI screenshot capture; a
            // no-op unless --screenshot-demo was passed at launch.
            if ScreenshotDemo.isEnabled, appState.document == nil {
                appState.loadScreenshotDemo()
                if let mode = ScreenshotDemo.initialMode { appState.mode = mode }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .requestOpenPanel)) { _ in
            openPDFInCurrentMode()
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

    // MARK: - Opening dropped / externally-opened files

    /// Routes dropped PDFs to whichever mode makes sense: Merge
    /// accumulates a queue, everything else takes the first file and
    /// switches to Sign, since that is what dropping a contract onto
    /// a signing app is asking for.
    private func openDropped(_ urls: [URL]) {
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

    // MARK: - Keyboard command routing

    private func openPDFInCurrentMode() {
        switch appState.mode {
        case .sign:
            pickPDF { url in appState.openDocument(at: url) }
        case .compress:
            pickPDF { url in appState.compressSourceURL = url }
        case .merge:
            pickPDFs(multi: true) { urls in
                appState.mergeItems.append(contentsOf: urls.map { MergeItem(url: $0) })
            }
        case .convert:
            pickPDF { url in appState.convertSourceURL = url }
        }
    }

    private func pickPDF(_ onPick: (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url { onPick(url) }
    }

    private func pickPDFs(multi: Bool, _ onPick: ([URL]) -> Void) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = multi
        panel.canChooseDirectories = false
        if panel.runModal() == .OK { onPick(panel.urls) }
    }
}
