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
        .sheet(isPresented: $appState.isPresentingNewSignature) {
            NewSignatureView()
                .environmentObject(appState)
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
