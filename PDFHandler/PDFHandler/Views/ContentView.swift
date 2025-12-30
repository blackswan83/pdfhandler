//
//  ContentView.swift
//  PDFHandler
//
//  Main application view
//  Design: Terminal precision meets calligraphic craft
//

import SwiftUI
import PDFKit
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.colorScheme) var colorScheme
    @State private var isDragging = false

    var body: some View {
        NavigationSplitView {
            SumiSidebarView()
                .frame(minWidth: 200)
        } detail: {
            ZStack {
                // Background
                (colorScheme == .dark ? Color.charcoal : Color.paperBackground)
                    .ignoresSafeArea()

                if appState.selectedPDFs.isEmpty {
                    SumiDropZoneView(isDragging: $isDragging)
                } else {
                    SumiWorkspaceView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                // Minimal text buttons
                Button(action: { appState.showFilePicker = true }) {
                    Text("open")
                        .font(SumiTypography.mono)
                }
                .buttonStyle(.plain)
                .foregroundStyle(colorScheme == .dark ? .white : Color.stonegrey)
                .keyboardShortcut("o", modifiers: .command)

                if !appState.selectedPDFs.isEmpty {
                    Text("·")
                        .foregroundStyle(Color.stonegrey)

                    Button(action: { appState.convertCurrentPDF() }) {
                        Text("convert")
                            .font(SumiTypography.mono)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(colorScheme == .dark ? Color.phosphorGreen : Color.terminalGreen)
                    .disabled(appState.isConverting)

                    Button(action: { appState.compressCurrentPDF() }) {
                        Text("compress")
                            .font(SumiTypography.mono)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(colorScheme == .dark ? .white : Color.stonegrey)
                    .disabled(appState.isCompressing)
                }
            }
        }
        .fileImporter(
            isPresented: $appState.showFilePicker,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                appState.loadPDFs(from: urls)
            case .failure(let error):
                print("File selection failed: \(error)")
            }
        }
        .onDrop(of: [.pdf, .fileURL], isTargeted: $isDragging) { providers in
            handleDrop(providers: providers)
            return true
        }
        .onReceive(NotificationCenter.default.publisher(for: .openPDFFiles)) { notification in
            if let urls = notification.userInfo?["urls"] as? [URL] {
                appState.loadPDFs(from: urls)
            }
        }
        .sheet(isPresented: $appState.showPreview) {
            SumiMarkdownPreviewSheet()
        }
    }

    private func handleDrop(providers: [NSItemProvider]) {
        var urls: [URL] = []
        let group = DispatchGroup()

        for provider in providers {
            group.enter()

            if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.pdf.identifier, options: nil) { item, _ in
                    defer { group.leave() }
                    if let url = item as? URL {
                        urls.append(url)
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    defer { group.leave() }
                    if let data = item as? Data,
                       let path = String(data: data, encoding: .utf8),
                       let url = URL(string: path),
                       url.pathExtension.lowercased() == "pdf" {
                        urls.append(url)
                    }
                }
            } else {
                group.leave()
            }
        }

        group.notify(queue: .main) {
            if !urls.isEmpty {
                appState.loadPDFs(from: urls)
            }
        }
    }
}

// MARK: - Sumi Drop Zone

struct SumiDropZoneView: View {
    @Binding var isDragging: Bool
    @EnvironmentObject var appState: AppState
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ZStack {
            // Calligraphic watermark - visible when no file loaded
            EnsoMark(opacity: 0.08, size: 300)
                .opacity(isDragging ? 0 : 1)
                .animation(.easeOut(duration: 0.3), value: isDragging)

            // Drop zone
            VStack(spacing: 0) {
                Spacer()

                // Command prompt style
                HStack(spacing: 4) {
                    Text("drop")
                        .font(SumiTypography.command)
                        .foregroundStyle(colorScheme == .dark ? .white : Color.inkBlack)

                    Text(".pdf")
                        .font(SumiTypography.command)
                        .foregroundStyle(colorScheme == .dark ? Color.phosphorGreen : Color.terminalGreen)

                    CursorBlinkView(color: colorScheme == .dark ? Color.phosphorGreen : Color.terminalGreen)
                        .opacity(isDragging ? 0 : 1)
                }

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                RoundedRectangle(cornerRadius: 2)
                    .strokeBorder(
                        isDragging
                            ? (colorScheme == .dark ? Color.phosphorGreen : Color.terminalGreen)
                            : (colorScheme == .dark ? Color(hex: "3A3A3C") : Color.mist),
                        style: StrokeStyle(lineWidth: 1, dash: isDragging ? [] : [8, 4])
                    )
                    .padding(60)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                appState.showFilePicker = true
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isDragging)
    }
}

// MARK: - Sumi Sidebar

struct SumiSidebarView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        List(selection: $appState.selectedTab) {
            Section {
                ForEach(AppTab.allCases, id: \.self) { tab in
                    HStack(spacing: 8) {
                        Text(commandForTab(tab))
                            .font(SumiTypography.mono)
                            .foregroundStyle(
                                appState.selectedTab == tab
                                    ? (colorScheme == .dark ? Color.phosphorGreen : Color.terminalGreen)
                                    : (colorScheme == .dark ? .white : Color.inkBlack)
                            )
                    }
                    .tag(tab)
                }
            } header: {
                Text("commands")
                    .font(SumiTypography.monoSmall)
                    .foregroundStyle(Color.stonegrey)
            }

            if !appState.selectedPDFURLs.isEmpty {
                Section {
                    ForEach(Array(appState.selectedPDFURLs.enumerated()), id: \.element) { index, url in
                        HStack(spacing: 8) {
                            Text("→")
                                .font(SumiTypography.mono)
                                .foregroundStyle(Color.stonegrey)

                            Text(url.lastPathComponent)
                                .font(SumiTypography.mono)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .tag(index)
                        .onTapGesture {
                            Task { @MainActor in
                                appState.currentPDFIndex = index
                            }
                        }
                    }
                } header: {
                    Text("open")
                        .font(SumiTypography.monoSmall)
                        .foregroundStyle(Color.stonegrey)
                }
            }

            if !appState.conversionResults.isEmpty {
                Section {
                    ForEach(appState.conversionResults.suffix(5)) { result in
                        HStack(spacing: 8) {
                            Text("✓")
                                .font(SumiTypography.mono)
                                .foregroundStyle(colorScheme == .dark ? Color.phosphorGreen : Color.terminalGreen)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(result.outputURL.lastPathComponent)
                                    .font(SumiTypography.monoSmall)
                                    .lineLimit(1)

                                Text("\(result.processingTime, specifier: "%.1f")s")
                                    .font(SumiTypography.monoSmall)
                                    .foregroundStyle(Color.stonegrey)
                            }
                        }
                    }
                } header: {
                    Text("history")
                        .font(SumiTypography.monoSmall)
                        .foregroundStyle(Color.stonegrey)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("sumi")
    }

    private func commandForTab(_ tab: AppTab) -> String {
        switch tab {
        case .convert: return "./convert"
        case .compress: return "./compress"
        case .batch: return "./batch"
        }
    }
}

// MARK: - Sumi Workspace

struct SumiWorkspaceView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        HSplitView {
            // PDF Preview
            SumiPDFPreviewView()
                .frame(minWidth: 400)

            // Options Panel
            ScrollView {
                VStack {
                    switch appState.selectedTab {
                    case .convert:
                        ConversionOptionsView()
                    case .compress:
                        CompressionOptionsView()
                    case .batch:
                        BatchProcessingView()
                    }
                }
                .frame(minWidth: 300, maxWidth: 400)
                .padding()
            }
            .background(colorScheme == .dark ? Color.charcoal : Color.paperBackground)
        }
    }
}

// MARK: - Sumi PDF Preview

struct SumiPDFPreviewView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            // Header - monospace file info
            HStack {
                if let url = appState.currentPDFURL {
                    Text(url.lastPathComponent)
                        .font(SumiTypography.mono)
                        .foregroundStyle(colorScheme == .dark ? .white : Color.inkBlack)
                        .lineLimit(1)

                    Spacer()

                    if let pdf = appState.currentPDF {
                        Text("\(pdf.pageCount)p")
                            .font(SumiTypography.monoSmall)
                            .foregroundStyle(Color.stonegrey)

                        if let size = fileSize(for: url) {
                            Text("·")
                                .foregroundStyle(Color.stonegrey)
                            Text(size)
                                .font(SumiTypography.monoSmall)
                                .foregroundStyle(Color.stonegrey)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(colorScheme == .dark ? Color.sumiGrey : Color.surface)

            Rectangle()
                .fill(colorScheme == .dark ? Color(hex: "3A3A3C") : Color.mist)
                .frame(height: 1)

            // PDF View
            if let pdf = appState.currentPDF {
                PDFKitView(document: pdf)
            } else {
                VStack {
                    Text("no file")
                        .font(SumiTypography.mono)
                        .foregroundStyle(Color.stonegrey)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(colorScheme == .dark ? Color.charcoal : Color.paperBackground)
    }

    private func fileSize(for url: URL) -> String? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? Int64 else {
            return nil
        }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

// MARK: - PDFKit SwiftUI Wrapper

struct PDFKitView: NSViewRepresentable {
    let document: PDFDocument

    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.backgroundColor = .clear
        return pdfView
    }

    func updateNSView(_ pdfView: PDFView, context: Context) {
        pdfView.document = document
    }
}

// MARK: - Sumi Markdown Preview Sheet

struct SumiMarkdownPreviewSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("output.md")
                    .font(SumiTypography.mono)
                    .foregroundStyle(colorScheme == .dark ? .white : Color.inkBlack)

                Spacer()

                Button("copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(appState.previewMarkdown, forType: .string)
                }
                .buttonStyle(SumiTextButtonStyle())

                Button("done") {
                    dismiss()
                }
                .buttonStyle(SumiTextButtonStyle(accent: true))
                .keyboardShortcut(.defaultAction)
            }
            .padding()
            .background(colorScheme == .dark ? Color.sumiGrey : Color.surface)

            Rectangle()
                .fill(colorScheme == .dark ? Color(hex: "3A3A3C") : Color.mist)
                .frame(height: 1)

            // Content
            ScrollView {
                Text(appState.previewMarkdown)
                    .font(SumiTypography.mono)
                    .foregroundStyle(colorScheme == .dark ? .white : Color.inkBlack)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .background(colorScheme == .dark ? Color.charcoal : Color.paperBackground)
        }
        .frame(minWidth: 600, minHeight: 400)
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
}
