//
//  CompressView.swift
//  PDFHandler
//
//  Compress-mode detail pane. Pick a PDF, pick a preset, tune the
//  target ratio, toggle grayscale / preserve-metadata, press
//  Compress. Shows a friendly "Install Ghostscript" card if the
//  gs binary is not found at any of the known paths.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct CompressView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if appState.compressGhostscriptMissing {
                    missingGhostscriptCard
                }
                pickFileSection
                optionsSection
                runSection
                if let result = appState.compressResult { resultCard(result) }
                if let error = appState.compressError { errorBanner(error) }
            }
            .padding(20)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Compress PDF", systemImage: "arrow.down.circle").font(.title2.bold())
            Text("Shrink a PDF using Ghostscript presets. Original is untouched; result saves next to it as \"<name>_compressed.pdf\".")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Missing Ghostscript

    private var missingGhostscriptCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Ghostscript is not installed", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(Color.orange)
            Text("PDF Handler uses Ghostscript for compression. Install it once with Homebrew:")
                .font(.callout)
            HStack(spacing: 8) {
                Text("brew install ghostscript")
                    .font(.system(.body, design: .monospaced))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                Button {
                    copyToClipboard("brew install ghostscript")
                } label: { Label("Copy", systemImage: "doc.on.doc") }
            }
            Text("Once installed, click Compress again — no app restart needed.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(Color.orange.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.orange.opacity(0.4), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
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
                if let url = appState.compressSourceURL {
                    Text(url.lastPathComponent)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .onDrop(of: [.pdf, .fileURL], isTargeted: nil) { providers in
                loadFirstPDF(providers) { url in appState.compressSourceURL = url }
            }
            Text("Or drag a PDF onto this panel.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Options

    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Preset").font(.headline)
            Picker("", selection: $appState.compressPreset) {
                ForEach(GhostscriptPreset.allCases) { preset in
                    Text(preset.displayName).tag(preset)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Text(appState.compressPreset.summary)
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle("Convert to grayscale", isOn: $appState.compressGrayscale)
        }
    }

    // MARK: - Run

    private var runSection: some View {
        HStack(spacing: 12) {
            Button {
                appState.runCompression()
            } label: {
                if appState.compressIsRunning {
                    Label("Compressing…", systemImage: "gearshape").labelStyle(.titleAndIcon)
                } else {
                    Label("Compress", systemImage: "arrow.down.circle.fill").labelStyle(.titleAndIcon)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(appState.compressSourceURL == nil || appState.compressIsRunning)

            if appState.compressIsRunning {
                ProgressView(value: appState.compressProgress)
                    .frame(maxWidth: 220)
            }
            Spacer()
        }
    }

    // MARK: - Result

    private func resultCard(_ result: CompressionResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Compressed", systemImage: "checkmark.seal.fill")
                .font(.headline)
                .foregroundStyle(Color.green)
            Text(result.outputURL.lastPathComponent)
                .font(.subheadline)
            Text("\(byteString(result.originalSize)) → \(byteString(result.compressedSize))  (\(Int(result.savingsPercent * 100))% smaller)")
                .font(.caption)
                .foregroundStyle(.secondary)
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
            appState.compressSourceURL = url
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

    private func byteString(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func copyToClipboard(_ s: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(s, forType: .string)
    }
}
