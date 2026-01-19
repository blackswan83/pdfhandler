//
//  ConversionOptionsView.swift
//  PDFHandler
//
//  Options panel for PDF to Markdown conversion
//  Design: CLI precision meets calligraphic craft
//

import SwiftUI
import PDFKit

struct ConversionOptionsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.colorScheme) var colorScheme
    @State private var showAdvancedOptions = false
    @State private var conversionOptions = ConversionOptions()
    @State private var showCompletionAnimation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Header
            Text("./convert")
                .font(SumiTypography.monoTitle)
                .foregroundStyle(colorScheme == .dark ? .white : Color.inkBlack)

            // Document Info
            if let pdf = appState.currentPDF, let url = appState.currentPDFURL {
                SumiDocumentInfo(pdf: pdf, url: url)
            }

            // Basic Options
            VStack(alignment: .leading, spacing: 12) {
                Text("--flags")
                    .font(SumiTypography.monoSmall)
                    .foregroundStyle(Color.stonegrey)

                SumiToggleOption(
                    label: "yaml frontmatter",
                    isOn: $conversionOptions.includeYAMLFrontmatter
                )

                SumiToggleOption(
                    label: "extract images",
                    isOn: $conversionOptions.extractImages
                )

                SumiToggleOption(
                    label: "preserve links",
                    isOn: $conversionOptions.preserveLinks
                )

                SumiToggleOption(
                    label: "ocr scanned pages",
                    isOn: $conversionOptions.performOCR
                )
            }
            .padding(16)
            .background(colorScheme == .dark ? Color.sumiGrey : Color.surface)
            .cornerRadius(4)

            // Image settings (if extracting)
            if conversionOptions.extractImages {
                VStack(alignment: .leading, spacing: 12) {
                    Text("--image-format")
                        .font(SumiTypography.monoSmall)
                        .foregroundStyle(Color.stonegrey)

                    HStack(spacing: 0) {
                        ForEach(ImageFormat.allCases) { format in
                            Button(action: {
                                conversionOptions.imageOutputFormat = format
                            }) {
                                Text(format.rawValue)
                                    .font(SumiTypography.monoSmall)
                                    .foregroundStyle(
                                        conversionOptions.imageOutputFormat == format
                                            ? (colorScheme == .dark ? Color.phosphorGreen : Color.terminalGreen)
                                            : Color.stonegrey
                                    )
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(
                                        conversionOptions.imageOutputFormat == format
                                            ? (colorScheme == .dark ? Color.phosphorGreen : Color.terminalGreen).opacity(0.1)
                                            : Color.clear
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .background(colorScheme == .dark ? Color.charcoal : Color.ashGrey.opacity(0.3))
                    .cornerRadius(4)
                }
                .padding(16)
                .background(colorScheme == .dark ? Color.sumiGrey : Color.surface)
                .cornerRadius(4)
            }

            // Advanced Options
            DisclosureGroup(
                isExpanded: $showAdvancedOptions,
                content: {
                    VStack(alignment: .leading, spacing: 12) {
                        // Table fallback
                        VStack(alignment: .leading, spacing: 8) {
                            Text("table fallback")
                                .font(SumiTypography.monoSmall)
                                .foregroundStyle(Color.stonegrey)

                            HStack(spacing: 0) {
                                ForEach(TableFallbackMode.allCases) { mode in
                                    Button(action: {
                                        conversionOptions.tableFallbackMode = mode
                                    }) {
                                        Text(shortModeName(mode))
                                            .font(SumiTypography.monoSmall)
                                            .foregroundStyle(
                                                conversionOptions.tableFallbackMode == mode
                                                    ? (colorScheme == .dark ? Color.phosphorGreen : Color.terminalGreen)
                                                    : Color.stonegrey
                                            )
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 6)
                                            .background(
                                                conversionOptions.tableFallbackMode == mode
                                                    ? (colorScheme == .dark ? Color.phosphorGreen : Color.terminalGreen).opacity(0.1)
                                                    : Color.clear
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        // OCR Languages
                        if conversionOptions.performOCR {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("ocr languages")
                                    .font(SumiTypography.monoSmall)
                                    .foregroundStyle(Color.stonegrey)

                                TextField(
                                    "en-US",
                                    text: Binding(
                                        get: { conversionOptions.ocrLanguages.joined(separator: ", ") },
                                        set: {
                                            conversionOptions.ocrLanguages = $0
                                                .components(separatedBy: ",")
                                                .map { $0.trimmingCharacters(in: .whitespaces) }
                                        }
                                    )
                                )
                                .font(SumiTypography.mono)
                                .textFieldStyle(.plain)
                                .padding(8)
                                .background(colorScheme == .dark ? Color.charcoal : Color.ashGrey.opacity(0.3))
                                .cornerRadius(2)
                            }
                        }
                    }
                    .padding(.top, 12)
                },
                label: {
                    Text("--advanced")
                        .font(SumiTypography.monoSmall)
                        .foregroundStyle(Color.stonegrey)
                }
            )

            Spacer()

            // Progress or Action
            if appState.isConverting {
                VStack(alignment: .leading, spacing: 8) {
                    CLIProgressBar(
                        progress: appState.conversionProgress,
                        label: "converting → \(Int(appState.conversionProgress * 100))%"
                    )
                }
            } else {
                // Action buttons - text only
                HStack(spacing: 16) {
                    Button(action: {
                        startConversion()
                    }) {
                        Text("[convert]")
                            .font(SumiTypography.mono)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(colorScheme == .dark ? Color.phosphorGreen : Color.terminalGreen)
                    .disabled(appState.currentPDF == nil)

                    Button(action: {
                        conversionOptions = ConversionOptions()
                    }) {
                        Text("[reset]")
                            .font(SumiTypography.mono)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.stonegrey)
                }
            }

            // Last Result
            if let lastResult = appState.conversionResults.last {
                SumiConversionResult(result: lastResult)
            }
        }
        .onChange(of: appState.conversionResults.count) { _ in
            showCompletionAnimation = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                showCompletionAnimation = false
            }
        }
    }

    private func startConversion() {
        appState.includeYAMLFrontmatter = conversionOptions.includeYAMLFrontmatter
        appState.imageOutputFormat = conversionOptions.imageOutputFormat.rawValue
        appState.convertCurrentPDF()
    }

    private func shortModeName(_ mode: TableFallbackMode) -> String {
        switch mode {
        case .codeBlock: return "code"
        case .csv: return "csv"
        case .html: return "html"
        }
    }
}

// MARK: - Sumi Document Info

struct SumiDocumentInfo: View {
    let pdf: PDFDocument
    let url: URL
    @Environment(\.colorScheme) var colorScheme
    @State private var metadata: DocumentMetadata?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // File name
            HStack {
                Text(url.lastPathComponent)
                    .font(SumiTypography.mono)
                    .foregroundStyle(colorScheme == .dark ? .white : Color.inkBlack)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                Text("\(pdf.pageCount)p")
                    .font(SumiTypography.monoSmall)
                    .foregroundStyle(Color.stonegrey)

                Text("·")
                    .foregroundStyle(Color.stonegrey)

                Text(formattedFileSize)
                    .font(SumiTypography.monoSmall)
                    .foregroundStyle(Color.stonegrey)
            }

            // Metadata indicators
            if let metadata = metadata {
                HStack(spacing: 12) {
                    if metadata.hasText {
                        HStack(spacing: 4) {
                            Text("✓")
                                .foregroundStyle(colorScheme == .dark ? Color.phosphorGreen : Color.terminalGreen)
                            Text("text")
                                .foregroundStyle(Color.stonegrey)
                        }
                    } else {
                        HStack(spacing: 4) {
                            Text("×")
                                .foregroundStyle(.orange)
                            Text("no text")
                                .foregroundStyle(Color.stonegrey)
                        }
                    }

                    if metadata.isScanned {
                        HStack(spacing: 4) {
                            Text("◎")
                                .foregroundStyle(Color.stonegrey)
                            Text("scanned")
                                .foregroundStyle(Color.stonegrey)
                        }
                    }
                }
                .font(SumiTypography.monoSmall)
            }
        }
        .padding(12)
        .background(colorScheme == .dark ? Color.sumiGrey : Color.surface)
        .cornerRadius(4)
        .task {
            await loadMetadata()
        }
    }

    private var formattedFileSize: String {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? Int64 else {
            return "--"
        }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    private func loadMetadata() async {
        let service = PDFService()
        metadata = await service.analyzeDocument(pdf)
    }
}

// MARK: - Sumi Toggle Option

struct SumiToggleOption: View {
    let label: String
    @Binding var isOn: Bool
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        HStack {
            Text(isOn ? "[x]" : "[ ]")
                .font(SumiTypography.mono)
                .foregroundStyle(
                    isOn
                        ? (colorScheme == .dark ? Color.phosphorGreen : Color.terminalGreen)
                        : Color.stonegrey
                )

            Text(label)
                .font(SumiTypography.monoSmall)
                .foregroundStyle(colorScheme == .dark ? .white : Color.inkBlack)

            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            isOn.toggle()
        }
    }
}

// MARK: - Sumi Conversion Result

struct SumiConversionResult: View {
    let result: ConversionResult
    @EnvironmentObject var appState: AppState
    @Environment(\.colorScheme) var colorScheme
    @State private var cursorBlink = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Success line
            HStack(spacing: 4) {
                Text("✓")
                    .foregroundStyle(colorScheme == .dark ? Color.phosphorGreen : Color.terminalGreen)

                Text("done")
                    .foregroundStyle(colorScheme == .dark ? Color.phosphorGreen : Color.terminalGreen)

                Text("in \(String(format: "%.1f", result.processingTime))s")
                    .foregroundStyle(Color.stonegrey)

                Rectangle()
                    .fill(colorScheme == .dark ? Color.phosphorGreen : Color.terminalGreen)
                    .frame(width: 2, height: 12)
                    .opacity(cursorBlink ? 1 : 0)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 0.3).repeatCount(4, autoreverses: true)) {
                            cursorBlink = false
                        }
                    }
            }
            .font(SumiTypography.mono)

            // Output info
            HStack(spacing: 8) {
                Text("→")
                    .foregroundStyle(Color.stonegrey)

                Text(result.outputURL.lastPathComponent)
                    .foregroundStyle(colorScheme == .dark ? .white : Color.inkBlack)
            }
            .font(SumiTypography.monoSmall)

            // Stats
            HStack(spacing: 16) {
                if !result.extractedImages.isEmpty {
                    Text("\(result.extractedImages.count) images")
                        .foregroundStyle(Color.stonegrey)
                }

                if result.ocrApplied, let confidence = result.ocrConfidence {
                    HStack(spacing: 4) {
                        Text("ocr")
                            .foregroundStyle(Color.stonegrey)
                        Text("\(Int(confidence * 100))%")
                            .foregroundStyle(
                                confidence > 0.8
                                    ? (colorScheme == .dark ? Color.phosphorGreen : Color.terminalGreen)
                                    : .orange
                            )
                    }
                }
            }
            .font(SumiTypography.monoSmall)

            // Warnings
            if !result.warnings.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(result.warnings.prefix(3)) { warning in
                        HStack(spacing: 4) {
                            Text("!")
                                .foregroundStyle(.orange)
                            Text(warning.message)
                                .foregroundStyle(Color.stonegrey)
                                .lineLimit(1)
                        }
                        .font(SumiTypography.monoSmall)
                    }
                }
            }

            // Actions
            HStack(spacing: 12) {
                Button(action: {
                    NSWorkspace.shared.selectFile(result.outputURL.path, inFileViewerRootedAtPath: "")
                }) {
                    Text("[reveal]")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.stonegrey)

                Button(action: {
                    NSWorkspace.shared.open(result.outputURL)
                }) {
                    Text("[open]")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.stonegrey)

                Button(action: {
                    appState.showPreview = true
                }) {
                    Text("[preview]")
                }
                .buttonStyle(.plain)
                .foregroundStyle(colorScheme == .dark ? Color.phosphorGreen : Color.terminalGreen)
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

#Preview {
    ConversionOptionsView()
        .environmentObject(AppState())
        .frame(width: 350, height: 600)
        .background(Color.paperBackground)
}
