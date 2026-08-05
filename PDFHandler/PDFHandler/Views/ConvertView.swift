//
//  ConvertView.swift
//  PDFHandler
//
//  Convert-mode detail pane. Pick a PDF, toggle options, run. OCR
//  uses Vision on pages whose text layer is empty.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ConvertView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                pickFileSection
                optionsSection
                runSection
                if let result = appState.convertResult { resultCard(result) }
                if let error = appState.convertError { errorBanner(error) }
            }
            .padding(20)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Convert to Markdown", systemImage: "doc.richtext").font(.title2.bold())
            Text("Extract text from a PDF into a .md file. For scanned pages with no text layer, we fall back to OCR (Apple Vision).")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Pick file

    private var pickFileSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button {
                    pickPDF()
                } label: {
                    Label("Choose PDF…", systemImage: "folder")
                }
                if let url = appState.convertSourceURL {
                    Text(url.lastPathComponent)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .onDrop(of: [.pdf, .fileURL], isTargeted: nil) { providers in
                loadFirstPDF(providers) { url in appState.convertSourceURL = url }
            }
            Text("Or drag a PDF onto this panel.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Options

    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Include YAML frontmatter", isOn: $appState.convertIncludeYAMLFrontmatter)
            Toggle("Save each page as an image next to the Markdown", isOn: $appState.convertExtractImages)

            Picker("Image format", selection: $appState.convertImageFormat) {
                ForEach(ConvertImageFormat.allCases) { format in
                    Text(format.displayName).tag(format)
                }
            }
            .pickerStyle(.segmented)
            .disabled(!appState.convertExtractImages)

            Toggle("Preserve hyperlinks", isOn: $appState.convertPreserveLinks)
            Toggle("OCR scanned / empty-text pages", isOn: $appState.convertPerformOCR)

            HStack {
                Text("OCR languages:")
                TextField("en-US, es-ES", text: $appState.convertOCRLanguages)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)
                    .disabled(!appState.convertPerformOCR)
            }
        }
    }

    // MARK: - Run

    private var runSection: some View {
        HStack(spacing: 12) {
            Button {
                appState.runConversion()
            } label: {
                if appState.convertIsRunning {
                    Label("Converting…", systemImage: "gearshape")
                } else {
                    Label("Convert", systemImage: "doc.richtext.fill")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(appState.convertSourceURL == nil || appState.convertIsRunning)

            if appState.convertIsRunning {
                ProgressView(value: appState.convertProgress).frame(maxWidth: 220)
            }
            Spacer()
        }
    }

    // MARK: - Result

    private func resultCard(_ result: MarkdownConversionResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Converted", systemImage: "checkmark.seal.fill")
                .font(.headline)
                .foregroundStyle(Color.green)
            Text(result.markdownURL.lastPathComponent).font(.subheadline)
            if result.ocrPagesCount > 0 {
                Text("\(result.pageCount) pages  •  \(result.ocrPagesCount) OCRed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("\(result.pageCount) pages")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color.green.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Errors

    private func errorBanner(_ message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.red)
            Text(message).font(.callout)
            Spacer()
        }
        .padding(12)
        .background(Color.red.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Helpers

    private func pickPDF() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            appState.convertSourceURL = url
        }
    }

    private func loadFirstPDF(_ providers: [NSItemProvider], onLoaded: @escaping (URL) -> Void) -> Bool {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
                    guard let data = data as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil),
                          url.pathExtension.lowercased() == "pdf" else { return }
                    Task { @MainActor in onLoaded(url) }
                }
                return true
            }
        }
        return false
    }
}
