//
//  CompressionOptionsView.swift
//  PDFHandler
//
//  Options panel for PDF compression
//

import SwiftUI

struct CompressionOptionsView: View {
    @EnvironmentObject var appState: AppState
    @State private var compressionOptions = CompressionOptions()
    @State private var showAdvancedOptions = false
    @State private var preview: CompressionPreview?
    @State private var ghostscriptAvailable = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                Text("Compress PDF")
                    .font(.title2)
                    .fontWeight(.semibold)

                // Ghostscript status
                if !ghostscriptAvailable {
                    GhostscriptWarningView()
                }

                // Document Info
                if let url = appState.currentPDFURL {
                    CompressionInfoCard(url: url, preview: preview)
                }

                Divider()

                // Compression Slider
                VStack(alignment: .leading, spacing: 12) {
                    Text("Target Size")
                        .font(.headline)

                    CompressionSlider(
                        value: $appState.targetCompressionRatio,
                        preview: preview
                    )
                    .onChange(of: appState.targetCompressionRatio) { _, newValue in
                        updatePreview()
                        compressionOptions.preset = GhostscriptPreset.forRatio(newValue)
                    }

                    // Preset indicator
                    HStack {
                        Text("Preset:")
                            .foregroundStyle(.secondary)

                        Text(GhostscriptPreset.forRatio(appState.targetCompressionRatio).displayName)
                            .fontWeight(.medium)
                    }
                    .font(.caption)
                }

                // Quick Presets
                VStack(alignment: .leading, spacing: 8) {
                    Text("Quick Presets")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        ForEach(GhostscriptPreset.allCases, id: \.self) { preset in
                            PresetButton(
                                preset: preset,
                                isSelected: compressionOptions.preset == preset
                            ) {
                                compressionOptions.preset = preset
                                appState.targetCompressionRatio = preset.typicalRatioRange.lowerBound +
                                    (preset.typicalRatioRange.upperBound - preset.typicalRatioRange.lowerBound) / 2
                            }
                        }
                    }
                }

                // Advanced Options
                DisclosureGroup("Advanced Options", isExpanded: $showAdvancedOptions) {
                    VStack(alignment: .leading, spacing: 16) {
                        // DPI Setting
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Image DPI")
                                Spacer()
                                Text("\(compressionOptions.imageDPI)")
                                    .foregroundStyle(.secondary)
                            }

                            Slider(
                                value: Binding(
                                    get: { Double(compressionOptions.imageDPI) },
                                    set: { compressionOptions.imageDPI = Int($0) }
                                ),
                                in: 50...300,
                                step: 10
                            )

                            HStack {
                                Text("50 DPI")
                                Spacer()
                                Text("300 DPI")
                            }
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }

                        Divider()

                        // Color Image Compression
                        Picker("Color Compression", selection: $compressionOptions.colorImageCompression) {
                            ForEach(ColorImageCompression.allCases) { compression in
                                Text(compression.displayName).tag(compression)
                            }
                        }

                        // Grayscale Toggle
                        Toggle("Convert to Grayscale", isOn: $compressionOptions.convertToGrayscale)
                            .help("Convert color images to grayscale for smaller file size")

                        Divider()

                        // Font Handling
                        Picker("Font Handling", selection: $compressionOptions.fontHandling) {
                            ForEach(FontHandling.allCases) { handling in
                                Text(handling.displayName).tag(handling)
                            }
                        }

                        // Metadata
                        Toggle("Preserve Metadata", isOn: $compressionOptions.preserveMetadata)
                            .help("Keep document title, author, and other metadata")
                    }
                    .padding(.top, 8)
                }

                Divider()

                // Progress and Action
                if appState.isCompressing {
                    VStack(spacing: 8) {
                        ProgressView(value: appState.compressionProgress) {
                            Text("Compressing...")
                        }

                        Text("\(Int(appState.compressionProgress * 100))%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Button(action: {
                        appState.compressCurrentPDF()
                    }) {
                        Label("Compress PDF", systemImage: "arrow.down.right.and.arrow.up.left")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(appState.currentPDF == nil || !ghostscriptAvailable)
                }

                // Last Result
                if let lastResult = appState.compressionResults.last {
                    CompressionResultCard(result: lastResult)
                }

                Spacer()
            }
            .padding()
        }
        .task {
            await checkGhostscript()
            updatePreview()
        }
    }

    private func checkGhostscript() async {
        let service = CompressionService()
        ghostscriptAvailable = await service.isGhostscriptAvailable()
    }

    private func updatePreview() {
        guard let url = appState.currentPDFURL else { return }

        Task {
            let service = CompressionService()
            preview = await service.estimateCompression(
                pdfURL: url,
                targetRatio: appState.targetCompressionRatio
            )
        }
    }
}

// MARK: - Compression Slider

struct CompressionSlider: View {
    @Binding var value: Double
    let preview: CompressionPreview?

    var body: some View {
        VStack(spacing: 12) {
            // Size indicators
            HStack {
                VStack(alignment: .leading) {
                    Text("Original")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let preview = preview {
                        Text(ByteCountFormatter.string(fromByteCount: preview.originalSize, countStyle: .file))
                            .font(.headline)
                    } else {
                        Text("--")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)

                Spacer()

                VStack(alignment: .trailing) {
                    Text("Target")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let preview = preview {
                        Text(ByteCountFormatter.string(fromByteCount: preview.estimatedSize, countStyle: .file))
                            .font(.headline)
                            .foregroundStyle(.blue)
                    } else {
                        Text("--")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Slider
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background gradient
                    LinearGradient(
                        gradient: Gradient(colors: [.green, .yellow, .orange, .red]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(height: 8)
                    .cornerRadius(4)

                    // Slider track overlay
                    Slider(value: $value, in: 0.1...1.0)
                        .tint(.clear)
                }
            }
            .frame(height: 30)

            // Labels
            HStack {
                Text("Maximum\nCompression")
                    .multilineTextAlignment(.leading)

                Spacer()

                Text("\(Int(value * 100))%")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(.blue)

                Spacer()

                Text("Maximum\nQuality")
                    .multilineTextAlignment(.trailing)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            // Quality indicator
            if let preview = preview {
                HStack {
                    Circle()
                        .fill(colorForQuality(preview.qualityIndicator))
                        .frame(width: 8, height: 8)

                    Text("Expected quality: \(preview.qualityIndicator.rawValue)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    private func colorForQuality(_ indicator: CompressionPreview.QualityIndicator) -> Color {
        switch indicator {
        case .excellent: return .green
        case .good: return .blue
        case .acceptable: return .orange
        case .noticeable: return .red
        }
    }
}

// MARK: - Preset Button

struct PresetButton: View {
    let preset: GhostscriptPreset
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: iconForPreset(preset))
                    .font(.title3)

                Text(shortName(preset))
                    .font(.caption2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(isSelected ? Color.blue.opacity(0.2) : Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    private func iconForPreset(_ preset: GhostscriptPreset) -> String {
        switch preset {
        case .prepress: return "printer.filled.and.paper"
        case .printer: return "printer"
        case .ebook: return "ipad"
        case .screen: return "globe"
        }
    }

    private func shortName(_ preset: GhostscriptPreset) -> String {
        switch preset {
        case .prepress: return "Prepress"
        case .printer: return "Printer"
        case .ebook: return "eBook"
        case .screen: return "Screen"
        }
    }
}

// MARK: - Compression Info Card

struct CompressionInfoCard: View {
    let url: URL
    let preview: CompressionPreview?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "doc.fill")
                    .foregroundStyle(.red)

                Text(url.lastPathComponent)
                    .font(.headline)
                    .lineLimit(1)

                Spacer()

                if let preview = preview {
                    VStack(alignment: .trailing) {
                        Text(ByteCountFormatter.string(fromByteCount: preview.originalSize, countStyle: .file))
                            .font(.headline)

                        Text("current size")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }
}

// MARK: - Compression Result Card

struct CompressionResultCard: View {
    let result: CompressionResult

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)

                Text("Compression Complete")
                    .font(.headline)

                Spacer()

                Text(String(format: "%.1fs", result.processingTime))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            // Size comparison
            HStack(spacing: 20) {
                VStack {
                    Text(result.formattedOriginalSize)
                        .font(.title3)

                    Text("Original")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)

                VStack {
                    Text(result.formattedCompressedSize)
                        .font(.title3)
                        .foregroundStyle(.green)

                    Text("Compressed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack {
                    Text("-\(Int(result.savedPercentage))%")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundStyle(.green)

                    Text("Saved \(result.formattedSavedSize)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !result.warnings.isEmpty {
                Divider()

                ForEach(result.warnings) { warning in
                    Label(warning.message, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            HStack {
                Button("Show in Finder") {
                    NSWorkspace.shared.selectFile(result.outputURL.path, inFileViewerRootedAtPath: "")
                }
                .buttonStyle(.link)

                Spacer()

                Button("Open") {
                    NSWorkspace.shared.open(result.outputURL)
                }
                .buttonStyle(.link)
            }
            .font(.caption)
        }
        .padding()
        .background(Color.green.opacity(0.1))
        .cornerRadius(8)
    }
}

// MARK: - Ghostscript Warning

struct GhostscriptWarningView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Ghostscript Not Found", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.orange)

            Text("PDF compression requires Ghostscript to be installed.")
                .font(.subheadline)

            Text("Install via Homebrew:")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Text("brew install ghostscript")
                    .font(.system(.caption, design: .monospaced))
                    .padding(8)
                    .background(Color(nsColor: .textBackgroundColor))
                    .cornerRadius(4)

                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("brew install ghostscript", forType: .string)
                }) {
                    Image(systemName: "doc.on.clipboard")
                }
                .buttonStyle(.borderless)
            }
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(8)
    }
}

#Preview {
    CompressionOptionsView()
        .environmentObject(AppState())
        .frame(width: 350, height: 700)
}
