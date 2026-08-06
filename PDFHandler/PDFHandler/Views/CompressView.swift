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
                if appState.compressSourceIsSigned {
                    signedWarningCard
                }
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
            .onDrop(of: PDFDrop.acceptedTypes, isTargeted: nil) { providers in
                PDFDrop.receive(providers) { urls in
                    if let first = urls.first { appState.compressSourceURL = first }
                }
            }
            Text("Or drag a PDF onto this panel.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Options

    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Mode").font(.headline)
            Picker("", selection: $appState.compressMode) {
                ForEach(CompressMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Text(appState.compressMode.summary)
                .font(.caption)
                .foregroundStyle(.secondary)

            if appState.compressMode.isTargetSize {
                targetSizeControls
            }

            estimateRow

            Toggle("Convert to grayscale", isOn: $appState.compressGrayscale)
        }
    }

    private var targetSizeControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            Slider(value: $appState.compressTargetFraction, in: 0.1...0.9, step: 0.05) {
                Text("Target size")
            } minimumValueLabel: {
                Text("10%").font(.caption2)
            } maximumValueLabel: {
                Text("90%").font(.caption2)
            }
            Text("Runs up to five passes, searching image resolution for the highest quality that still fits.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Source size against the expected output, updating live as the
    /// target slider moves. For the quality presets there is no honest
    /// single number — the outcome depends entirely on what is inside
    /// the file — so a clearly-labelled typical range is shown instead
    /// of a figure that would look authoritative and often be wrong.
    @ViewBuilder
    private var estimateRow: some View {
        let source = appState.compressSourceSize
        if source > 0 {
            HStack(spacing: 8) {
                Image(systemName: "arrow.right.circle")
                    .foregroundStyle(.secondary)
                Text(byteString(source))
                    .font(.system(.body, design: .monospaced))
                Text("→")
                    .foregroundStyle(.secondary)

                if appState.compressMode.isTargetSize {
                    let target = Int64(Double(source) * appState.compressTargetFraction)
                    Text(byteString(target))
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(Color.accentColor)
                    Text("target")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let range = appState.compressMode.typicalRange {
                    let low = Int64(Double(source) * range.lowerBound)
                    let high = Int64(Double(source) * range.upperBound)
                    Text("\(byteString(low)) – \(byteString(high))")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text("typical for image-heavy PDFs")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(10)
            .background(Color.secondary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    // MARK: - Digitally signed source

    private var signedWarningCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("This PDF is digitally signed", systemImage: "checkmark.seal.trianglebadge.exclamationmark")
                .font(.headline)
                .foregroundStyle(Color.orange)
            Text("Compressing rewrites the file, which invalidates its cryptographic signature — no compressor can avoid this. The original stays untouched, but the compressed copy will show as unsigned.")
                .font(.callout)
        }
        .padding(14)
        .background(Color.orange.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.orange.opacity(0.4), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Run

    private var runSection: some View {
        HStack(spacing: 12) {
            Button {
                appState.runCompression()
            } label: {
                if appState.compressIsRunning {
                    Label(appState.compressMode.isTargetSize ? "Searching…" : "Compressing…",
                          systemImage: "gearshape").labelStyle(.titleAndIcon)
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
            Label(result.missedTarget ? "Compressed as far as it goes" : "Compressed",
                  systemImage: result.missedTarget ? "exclamationmark.circle.fill" : "checkmark.seal.fill")
                .font(.headline)
                .foregroundStyle(result.missedTarget ? Color.orange : Color.green)
            Text(result.outputURL.lastPathComponent)
                .font(.subheadline)
            Text("\(byteString(result.originalSize)) → \(byteString(result.compressedSize))  (\(Int(result.savingsPercent * 100))% smaller)")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let dpi = result.resolvedDPI {
                Text(result.missedTarget
                     ? "Could not reach the target even at \(dpi) DPI images — this PDF is mostly text or already optimized."
                     : "Best quality that fit: \(dpi) DPI images.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background((result.missedTarget ? Color.orange : Color.green).opacity(0.08))
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

    private func byteString(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func copyToClipboard(_ s: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(s, forType: .string)
    }
}
