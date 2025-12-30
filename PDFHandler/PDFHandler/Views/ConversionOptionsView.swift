//
//  ConversionOptionsView.swift
//  PDFHandler
//
//  Options panel for PDF to Markdown conversion
//

import SwiftUI

struct ConversionOptionsView: View {
    @EnvironmentObject var appState: AppState
    @State private var showAdvancedOptions = false
    @State private var conversionOptions = ConversionOptions()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                Text("Convert to Markdown")
                    .font(.title2)
                    .fontWeight(.semibold)

                // Document Info
                if let pdf = appState.currentPDF, let url = appState.currentPDFURL {
                    DocumentInfoCard(pdf: pdf, url: url)
                }

                Divider()

                // Basic Options
                VStack(alignment: .leading, spacing: 16) {
                    Text("Output Options")
                        .font(.headline)

                    Toggle("Include YAML Frontmatter", isOn: $conversionOptions.includeYAMLFrontmatter)
                        .help("Add metadata (title, author, date) at the beginning of the Markdown file")

                    Toggle("Extract Images", isOn: $conversionOptions.extractImages)
                        .help("Save embedded images to a companion folder")

                    Toggle("Preserve Hyperlinks", isOn: $conversionOptions.preserveLinks)
                        .help("Convert PDF links to Markdown links")

                    Toggle("Perform OCR on Scanned Pages", isOn: $conversionOptions.performOCR)
                        .help("Use optical character recognition for image-based pages")
                }

                if conversionOptions.extractImages {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Image Settings")
                            .font(.headline)

                        Picker("Format", selection: $conversionOptions.imageOutputFormat) {
                            ForEach(ImageFormat.allCases) { format in
                                Text(format.displayName).tag(format)
                            }
                        }
                        .pickerStyle(.segmented)

                        Picker("Naming", selection: $conversionOptions.imageNamingConvention) {
                            ForEach(ImageNamingConvention.allCases) { convention in
                                Text(convention.displayName).tag(convention)
                            }
                        }
                    }
                    .padding()
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(8)
                }

                // Advanced Options
                DisclosureGroup("Advanced Options", isExpanded: $showAdvancedOptions) {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("Table Fallback", selection: $conversionOptions.tableFallbackMode) {
                            ForEach(TableFallbackMode.allCases) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .help("How to render complex tables that don't convert cleanly to Markdown")

                        if conversionOptions.performOCR {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("OCR Languages")
                                    .font(.subheadline)

                                TextField("Languages", text: Binding(
                                    get: { conversionOptions.ocrLanguages.joined(separator: ", ") },
                                    set: { conversionOptions.ocrLanguages = $0.components(separatedBy: ", ").map { $0.trimmingCharacters(in: .whitespaces) } }
                                ))
                                .textFieldStyle(.roundedBorder)

                                Text("e.g., en-US, de-DE, fr-FR")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.top, 8)
                }

                Divider()

                // Progress and Action
                if appState.isConverting {
                    VStack(spacing: 8) {
                        ProgressView(value: appState.conversionProgress) {
                            Text("Converting...")
                        }

                        Text("\(Int(appState.conversionProgress * 100))%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Button(action: {
                        startConversion()
                    }) {
                        Label("Convert to Markdown", systemImage: "doc.text")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(appState.currentPDF == nil)
                }

                // Last Result
                if let lastResult = appState.conversionResults.last {
                    ConversionResultCard(result: lastResult)
                }

                Spacer()
            }
            .padding()
        }
    }

    private func startConversion() {
        // Apply current options to AppState
        appState.includeYAMLFrontmatter = conversionOptions.includeYAMLFrontmatter
        appState.imageOutputFormat = conversionOptions.imageOutputFormat.rawValue

        appState.convertCurrentPDF()
    }
}

// MARK: - Document Info Card

struct DocumentInfoCard: View {
    let pdf: PDFDocument
    let url: URL

    @State private var metadata: DocumentMetadata?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "doc.fill")
                    .foregroundStyle(.red)
                    .font(.title2)

                VStack(alignment: .leading) {
                    Text(url.lastPathComponent)
                        .font(.headline)
                        .lineLimit(1)

                    Text(formattedFileSize)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing) {
                    Text("\(pdf.pageCount)")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text("pages")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let metadata = metadata {
                Divider()

                VStack(alignment: .leading, spacing: 4) {
                    if let title = metadata.title, !title.isEmpty {
                        Label(title, systemImage: "text.quote")
                            .font(.caption)
                    }

                    if let author = metadata.author, !author.isEmpty {
                        Label(author, systemImage: "person")
                            .font(.caption)
                    }

                    HStack {
                        if metadata.hasText {
                            Label("Has Text", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            Label("No Text", systemImage: "xmark.circle.fill")
                                .foregroundStyle(.orange)
                        }

                        if metadata.isScanned {
                            Label("Scanned", systemImage: "doc.viewfinder")
                                .foregroundStyle(.blue)
                        }
                    }
                    .font(.caption)
                }
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
        .task {
            await loadMetadata()
        }
    }

    private var formattedFileSize: String {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? Int64 else {
            return "Unknown size"
        }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    private func loadMetadata() async {
        let service = PDFService()
        metadata = await service.analyzeDocument(pdf)
    }
}

// MARK: - Conversion Result Card

struct ConversionResultCard: View {
    let result: ConversionResult

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)

                Text("Conversion Complete")
                    .font(.headline)

                Spacer()

                Text(String(format: "%.1fs", result.processingTime))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Output:")
                    Text(result.outputURL.lastPathComponent)
                        .foregroundStyle(.secondary)
                }

                if !result.extractedImages.isEmpty {
                    HStack {
                        Text("Images:")
                        Text("\(result.extractedImages.count) extracted")
                            .foregroundStyle(.secondary)
                    }
                }

                if result.ocrApplied, let confidence = result.ocrConfidence {
                    HStack {
                        Text("OCR Confidence:")
                        Text("\(Int(confidence * 100))%")
                            .foregroundStyle(confidence > 0.8 ? .green : .orange)
                    }
                }
            }
            .font(.caption)

            if !result.warnings.isEmpty {
                Divider()

                VStack(alignment: .leading, spacing: 4) {
                    Text("Warnings")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.orange)

                    ForEach(result.warnings) { warning in
                        Label(warning.message, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
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

#Preview {
    ConversionOptionsView()
        .environmentObject(AppState())
        .frame(width: 350, height: 600)
}
