//
//  ContentView.swift
//  PDFHandler
//
//  Main application view
//

import SwiftUI
import PDFKit
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var isDragging = false

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .frame(minWidth: 200)
        } detail: {
            ZStack {
                if appState.selectedPDFs.isEmpty {
                    DropZoneView(isDragging: $isDragging)
                } else {
                    MainWorkspaceView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: { appState.showFilePicker = true }) {
                    Label("Open PDF", systemImage: "doc.badge.plus")
                }
                .keyboardShortcut("o", modifiers: .command)

                if !appState.selectedPDFs.isEmpty {
                    Divider()

                    Button(action: { appState.convertCurrentPDF() }) {
                        Label("Convert to Markdown", systemImage: "doc.text")
                    }
                    .disabled(appState.isConverting)

                    Button(action: { appState.compressCurrentPDF() }) {
                        Label("Compress", systemImage: "arrow.down.right.and.arrow.up.left")
                    }
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
            MarkdownPreviewSheet()
        }
    }

    private func handleDrop(providers: [NSItemProvider]) {
        var urls: [URL] = []

        let group = DispatchGroup()

        for provider in providers {
            group.enter()

            if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.pdf.identifier, options: nil) { item, error in
                    defer { group.leave() }

                    if let url = item as? URL {
                        urls.append(url)
                    } else if let data = item as? Data {
                        // Handle data if needed
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                    defer { group.leave() }

                    if let data = item as? Data,
                       let path = String(data: data, encoding: .utf8),
                       let url = URL(string: path) {
                        if url.pathExtension.lowercased() == "pdf" {
                            urls.append(url)
                        }
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

// MARK: - Drop Zone View

struct DropZoneView: View {
    @Binding var isDragging: Bool
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "doc.richtext")
                .font(.system(size: 80))
                .foregroundStyle(isDragging ? .blue : .secondary)
                .symbolEffect(.bounce, value: isDragging)

            Text("Drop PDF files here")
                .font(.title2)
                .fontWeight(.medium)

            Text("or click to browse")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button("Select PDFs") {
                appState.showFilePicker = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(
                    isDragging ? Color.blue : Color.secondary.opacity(0.3),
                    style: StrokeStyle(lineWidth: 3, dash: [10])
                )
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(isDragging ? Color.blue.opacity(0.1) : Color.clear)
                )
                .padding(40)
        }
        .animation(.easeInOut(duration: 0.2), value: isDragging)
    }
}

// MARK: - Sidebar View

struct SidebarView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        List(selection: $appState.selectedTab) {
            Section("Actions") {
                ForEach(AppTab.allCases, id: \.self) { tab in
                    Label(tab.rawValue, systemImage: iconForTab(tab))
                        .tag(tab)
                }
            }

            if !appState.selectedPDFURLs.isEmpty {
                Section("Open PDFs") {
                    ForEach(Array(appState.selectedPDFURLs.enumerated()), id: \.element) { index, url in
                        HStack {
                            Image(systemName: "doc.fill")
                                .foregroundStyle(.red)

                            Text(url.lastPathComponent)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .tag(index)
                        .onTapGesture {
                            appState.currentPDFIndex = index
                        }
                    }
                }
            }

            if !appState.conversionResults.isEmpty {
                Section("Recent Conversions") {
                    ForEach(appState.conversionResults.suffix(5)) { result in
                        HStack {
                            Image(systemName: "doc.text.fill")
                                .foregroundStyle(.blue)

                            VStack(alignment: .leading) {
                                Text(result.outputURL.lastPathComponent)
                                    .lineLimit(1)

                                Text("\(result.processingTime, specifier: "%.1f")s")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            if !appState.compressionResults.isEmpty {
                Section("Recent Compressions") {
                    ForEach(appState.compressionResults.suffix(5)) { result in
                        HStack {
                            Image(systemName: "arrow.down.right.and.arrow.up.left")
                                .foregroundStyle(.green)

                            VStack(alignment: .leading) {
                                Text(result.outputURL.lastPathComponent)
                                    .lineLimit(1)

                                Text("Saved \(result.formattedSavedSize)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("PDF Handler")
    }

    private func iconForTab(_ tab: AppTab) -> String {
        switch tab {
        case .convert:
            return "doc.text"
        case .compress:
            return "arrow.down.right.and.arrow.up.left"
        case .batch:
            return "square.stack.3d.up"
        }
    }
}

// MARK: - Main Workspace View

struct MainWorkspaceView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        HSplitView {
            // PDF Preview
            PDFPreviewView()
                .frame(minWidth: 400)

            // Options Panel
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
    }
}

// MARK: - PDF Preview View

struct PDFPreviewView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                if let url = appState.currentPDFURL {
                    Text(url.lastPathComponent)
                        .font(.headline)
                        .lineLimit(1)

                    Spacer()

                    if let pdf = appState.currentPDF {
                        Text("\(pdf.pageCount) pages")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
            .background(.bar)

            Divider()

            // PDF View
            if let pdf = appState.currentPDF {
                PDFKitView(document: pdf)
            } else {
                ContentUnavailableView(
                    "No PDF Selected",
                    systemImage: "doc.questionmark",
                    description: Text("Select a PDF from the sidebar")
                )
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
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
        pdfView.backgroundColor = .controlBackgroundColor
        return pdfView
    }

    func updateNSView(_ pdfView: PDFView, context: Context) {
        pdfView.document = document
    }
}

// MARK: - Markdown Preview Sheet

struct MarkdownPreviewSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Markdown Preview")
                    .font(.headline)

                Spacer()

                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(appState.previewMarkdown, forType: .string)
                }

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
            .background(.bar)

            Divider()

            // Content
            ScrollView {
                Text(appState.previewMarkdown)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
        }
        .frame(minWidth: 600, minHeight: 400)
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
}
