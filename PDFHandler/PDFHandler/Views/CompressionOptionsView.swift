//
//  CompressionOptionsView.swift
//  PDFHandler
//
//  Options panel for PDF compression
//  Design: CLI precision with minimal aesthetics
//

import SwiftUI
import PDFKit

struct CompressionOptionsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.colorScheme) var colorScheme
    @State private var compressionOptions = CompressionOptions()
    @State private var showAdvancedOptions = false
    @State private var preview: CompressionPreview?
    @State private var ghostscriptAvailable = false
    @State private var showCompletionAnimation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Header
            Text("./compress")
                .font(SumiTypography.monoTitle)
                .foregroundStyle(colorScheme == .dark ? .white : .inkBlack)

            // Ghostscript status
            if !ghostscriptAvailable {
                SumiGhostscriptWarning()
            }

            // File info
            if let url = appState.currentPDFURL {
                SumiFileInfo(url: url, preview: preview)
            }

            // Compression Slider
            VStack(alignment: .leading, spacing: 16) {
                // Size display
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("original")
                            .font(SumiTypography.monoSmall)
                            .foregroundStyle(.stonegrey)

                        if let preview = preview {
                            Text(ByteCountFormatter.string(fromByteCount: preview.originalSize, countStyle: .file))
                                .font(SumiTypography.mono)
                                .foregroundStyle(colorScheme == .dark ? .white : .inkBlack)
                        } else {
                            Text("--")
                                .font(SumiTypography.mono)
                                .foregroundStyle(.stonegrey)
                        }
                    }

                    Spacer()

                    Text("→")
                        .font(SumiTypography.mono)
                        .foregroundStyle(.stonegrey)

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        Text("target")
                            .font(SumiTypography.monoSmall)
                            .foregroundStyle(.stonegrey)

                        if let preview = preview {
                            Text(ByteCountFormatter.string(fromByteCount: preview.estimatedSize, countStyle: .file))
                                .font(SumiTypography.mono)
                                .foregroundStyle(colorScheme == .dark ? .phosphorGreen : .terminalGreen)
                        } else {
                            Text("--")
                                .font(SumiTypography.mono)
                                .foregroundStyle(.stonegrey)
                        }
                    }
                }

                // Sumi Slider
                SumiSlider(
                    value: $appState.targetCompressionRatio,
                    range: 0.1...1.0,
                    label: "compression"
                )
                .onChange(of: appState.targetCompressionRatio) { _, newValue in
                    updatePreview()
                    compressionOptions.preset = GhostscriptPreset.forRatio(newValue)
                }

                // Preset label
                HStack {
                    Text("preset:")
                        .font(SumiTypography.monoSmall)
                        .foregroundStyle(.stonegrey)

                    Text(presetName(for: appState.targetCompressionRatio))
                        .font(SumiTypography.monoSmall)
                        .foregroundStyle(colorScheme == .dark ? .white : .inkBlack)
                }
            }
            .padding(16)
            .background(colorScheme == .dark ? Color.sumiGrey : Color.surface)
            .cornerRadius(4)

            // Quick presets
            VStack(alignment: .leading, spacing: 8) {
                Text("presets")
                    .font(SumiTypography.monoSmall)
                    .foregroundStyle(.stonegrey)

                HStack(spacing: 0) {
                    ForEach(GhostscriptPreset.allCases, id: \.self) { preset in
                        SumiPresetButton(
                            preset: preset,
                            isSelected: compressionOptions.preset == preset
                        ) {
                            compressionOptions.preset = preset
                            let midpoint = preset.typicalRatioRange.lowerBound +
                                (preset.typicalRatioRange.upperBound - preset.typicalRatioRange.lowerBound) / 2
                            appState.targetCompressionRatio = midpoint
                        }
                    }
                }
            }

            // Advanced options
            DisclosureGroup(
                isExpanded: $showAdvancedOptions,
                content: {
                    VStack(alignment: .leading, spacing: 12) {
                        // DPI
                        HStack {
                            Text("dpi")
                                .font(SumiTypography.monoSmall)
                                .foregroundStyle(.stonegrey)
                                .frame(width: 60, alignment: .leading)

                            Slider(
                                value: Binding(
                                    get: { Double(compressionOptions.imageDPI) },
                                    set: { compressionOptions.imageDPI = Int($0) }
                                ),
                                in: 50...300,
                                step: 10
                            )
                            .tint(colorScheme == .dark ? .phosphorGreen : .terminalGreen)

                            Text("\(compressionOptions.imageDPI)")
                                .font(SumiTypography.monoSmall)
                                .foregroundStyle(colorScheme == .dark ? .white : .inkBlack)
                                .frame(width: 40, alignment: .trailing)
                        }

                        // Grayscale
                        HStack {
                            Text("grayscale")
                                .font(SumiTypography.monoSmall)
                                .foregroundStyle(.stonegrey)

                            Spacer()

                            Toggle("", isOn: $compressionOptions.convertToGrayscale)
                                .labelsHidden()
                                .tint(colorScheme == .dark ? .phosphorGreen : .terminalGreen)
                        }

                        // Metadata
                        HStack {
                            Text("keep metadata")
                                .font(SumiTypography.monoSmall)
                                .foregroundStyle(.stonegrey)

                            Spacer()

                            Toggle("", isOn: $compressionOptions.preserveMetadata)
                                .labelsHidden()
                                .tint(colorScheme == .dark ? .phosphorGreen : .terminalGreen)
                        }
                    }
                    .padding(.top, 12)
                },
                label: {
                    Text("--options")
                        .font(SumiTypography.monoSmall)
                        .foregroundStyle(.stonegrey)
                }
            )

            Spacer()

            // Progress or Action
            if appState.isCompressing {
                VStack(alignment: .leading, spacing: 8) {
                    CLIProgressBar(
                        progress: appState.compressionProgress,
                        label: "compressing → \(Int(appState.compressionProgress * 100))%"
                    )
                }
            } else {
                // Action buttons - text only
                HStack(spacing: 16) {
                    Button(action: {
                        appState.compressCurrentPDF()
                    }) {
                        Text("[compress]")
                            .font(SumiTypography.mono)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(colorScheme == .dark ? .phosphorGreen : .terminalGreen)
                    .disabled(appState.currentPDF == nil || !ghostscriptAvailable)

                    Button(action: {
                        appState.targetCompressionRatio = 0.5
                        compressionOptions = CompressionOptions()
                    }) {
                        Text("[reset]")
                            .font(SumiTypography.mono)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.stonegrey)
                }
            }

            // Last result
            if let lastResult = appState.compressionResults.last {
                SumiCompressionResult(result: lastResult)
                    .inkDissolve(isActive: showCompletionAnimation)
            }
        }
        .task {
            await checkGhostscript()
            updatePreview()
        }
        .onChange(of: appState.compressionResults.count) { _, _ in
            showCompletionAnimation = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                showCompletionAnimation = false
            }
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

    private func presetName(for ratio: Double) -> String {
        switch ratio {
        case 0.90...1.0: return "prepress"
        case 0.60..<0.90: return "printer"
        case 0.30..<0.60: return "ebook"
        default: return "screen"
        }
    }
}

// MARK: - Sumi File Info

struct SumiFileInfo: View {
    let url: URL
    let preview: CompressionPreview?
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        HStack {
            Text(url.lastPathComponent)
                .font(SumiTypography.mono)
                .foregroundStyle(colorScheme == .dark ? .white : .inkBlack)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            if let preview = preview {
                Text(ByteCountFormatter.string(fromByteCount: preview.originalSize, countStyle: .file))
                    .font(SumiTypography.monoSmall)
                    .foregroundStyle(.stonegrey)
            }
        }
        .padding(12)
        .background(colorScheme == .dark ? Color.sumiGrey : Color.surface)
        .cornerRadius(4)
    }
}

// MARK: - Sumi Preset Button

struct SumiPresetButton: View {
    let preset: GhostscriptPreset
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        Button(action: action) {
            Text(shortName)
                .font(SumiTypography.monoSmall)
                .foregroundStyle(
                    isSelected
                        ? (colorScheme == .dark ? Color.phosphorGreen : Color.terminalGreen)
                        : .stonegrey
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    isSelected
                        ? (colorScheme == .dark ? Color.phosphorGreen.opacity(0.1) : Color.terminalGreen.opacity(0.1))
                        : Color.clear
                )
        }
        .buttonStyle(.plain)
    }

    private var shortName: String {
        switch preset {
        case .prepress: return "prepress"
        case .printer: return "printer"
        case .ebook: return "ebook"
        case .screen: return "screen"
        }
    }
}

// MARK: - Sumi Compression Result

struct SumiCompressionResult: View {
    let result: CompressionResult
    @Environment(\.colorScheme) var colorScheme
    @State private var cursorBlink = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Success line
            HStack(spacing: 4) {
                Text("✓")
                    .foregroundStyle(colorScheme == .dark ? .phosphorGreen : .terminalGreen)

                Text("done")
                    .foregroundStyle(colorScheme == .dark ? .phosphorGreen : .terminalGreen)

                Text("in \(String(format: "%.1f", result.processingTime))s")
                    .foregroundStyle(.stonegrey)

                // Blinking cursor
                Rectangle()
                    .fill(colorScheme == .dark ? Color.phosphorGreen : Color.terminalGreen)
                    .frame(width: 2, height: 12)
                    .opacity(cursorBlink ? 1 : 0)
                    .onAppear {
                        // Blink twice then stop
                        withAnimation(.easeInOut(duration: 0.3).repeatCount(4, autoreverses: true)) {
                            cursorBlink = false
                        }
                    }
            }
            .font(SumiTypography.mono)

            // Size comparison
            HStack(spacing: 8) {
                Text(result.formattedOriginalSize)
                    .foregroundStyle(.stonegrey)

                Text("→")
                    .foregroundStyle(.stonegrey)

                Text(result.formattedCompressedSize)
                    .foregroundStyle(colorScheme == .dark ? .white : .inkBlack)

                Text("(-\(Int(result.savedPercentage))%)")
                    .foregroundStyle(colorScheme == .dark ? .phosphorGreen : .terminalGreen)
            }
            .font(SumiTypography.monoSmall)

            // Actions
            HStack(spacing: 12) {
                Button(action: {
                    NSWorkspace.shared.selectFile(result.outputURL.path, inFileViewerRootedAtPath: "")
                }) {
                    Text("[reveal]")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.stonegrey)

                Button(action: {
                    NSWorkspace.shared.open(result.outputURL)
                }) {
                    Text("[open]")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.stonegrey)
            }
            .font(SumiTypography.monoSmall)
        }
        .padding(12)
        .background(
            (colorScheme == .dark ? Color.phosphorGreen : Color.terminalGreen)
                .opacity(0.05)
        )
        .cornerRadius(4)
    }
}

// MARK: - Sumi Ghostscript Warning

struct SumiGhostscriptWarning: View {
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Text("!")
                    .foregroundStyle(.orange)
                Text("ghostscript not found")
                    .foregroundStyle(.orange)
            }
            .font(SumiTypography.mono)

            Text("brew install ghostscript")
                .font(SumiTypography.monoSmall)
                .foregroundStyle(colorScheme == .dark ? .white : .inkBlack)
                .padding(8)
                .background(colorScheme == .dark ? Color.sumiGrey : Color.ashGrey.opacity(0.5))
                .cornerRadius(2)
                .onTapGesture {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("brew install ghostscript", forType: .string)
                }
        }
        .padding(12)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(4)
    }
}

#Preview {
    CompressionOptionsView()
        .environmentObject(AppState())
        .frame(width: 350, height: 700)
        .background(Color.paperBackground)
}
