//
//  BatchProcessingView.swift
//  PDFHandler
//
//  Batch processing for multiple PDFs
//

import SwiftUI
import UniformTypeIdentifiers
import PDFKit

struct BatchProcessingView: View {
    @EnvironmentObject var appState: AppState
    @State private var batchMode: BatchMode = .convert
    @State private var selectedFiles: [URL] = []
    @State private var processingStatus: [URL: ProcessingStatus] = [:]
    @State private var isProcessing = false
    @State private var overallProgress: Double = 0

    enum BatchMode: String, CaseIterable {
        case convert = "Convert to Markdown"
        case compress = "Compress PDFs"
    }

    enum ProcessingStatus {
        case pending
        case processing
        case completed
        case failed(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            Text("Batch Processing")
                .font(.title2)
                .fontWeight(.semibold)

            // Mode Selection
            Picker("Operation", selection: $batchMode) {
                ForEach(BatchMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            // File List
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Files")
                        .font(.headline)

                    Spacer()

                    Button(action: addFiles) {
                        Label("Add Files", systemImage: "plus")
                    }
                    .buttonStyle(.borderless)

                    if !selectedFiles.isEmpty {
                        Button(action: clearFiles) {
                            Label("Clear", systemImage: "trash")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.red)
                    }
                }

                if selectedFiles.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        Text("No Files Selected")
                            .font(.headline)
                        Text("Add PDF files to process in batch")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Button("Select Files", action: addFiles)
                            .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 200)
                } else {
                    List {
                        ForEach(selectedFiles, id: \.self) { url in
                            BatchFileRow(
                                url: url,
                                status: processingStatus[url] ?? .pending
                            )
                        }
                        .onDelete(perform: deleteFiles)
                    }
                    .listStyle(.bordered)
                    .frame(height: 200)
                }
            }

            // Options
            if batchMode == .convert {
                BatchConversionOptions()
            } else {
                BatchCompressionOptions(targetRatio: $appState.targetCompressionRatio)
            }

            Divider()

            // Progress
            if isProcessing {
                VStack(spacing: 8) {
                    ProgressView(value: overallProgress) {
                        Text("Processing \(completedCount)/\(selectedFiles.count) files...")
                    }

                    Text("\(Int(overallProgress * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button("Cancel") {
                        cancelProcessing()
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                Button(action: startBatchProcessing) {
                    Label(
                        batchMode == .convert ? "Convert All" : "Compress All",
                        systemImage: batchMode == .convert ? "doc.text" : "arrow.down.right.and.arrow.up.left"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(selectedFiles.isEmpty)
            }

            // Summary
            if !processingStatus.isEmpty && !isProcessing {
                BatchSummaryView(status: processingStatus)
            }

            Spacer()
        }
        .padding()
        .onAppear {
            // Pre-populate with already loaded PDFs
            if selectedFiles.isEmpty {
                selectedFiles = appState.selectedPDFURLs
            }
        }
    }

    private var completedCount: Int {
        processingStatus.values.filter {
            if case .completed = $0 { return true }
            if case .failed = $0 { return true }
            return false
        }.count
    }

    private func addFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.pdf]

        if panel.runModal() == .OK {
            let newFiles = panel.urls.filter { !selectedFiles.contains($0) }
            selectedFiles.append(contentsOf: newFiles)
        }
    }

    private func clearFiles() {
        selectedFiles = []
        processingStatus = [:]
    }

    private func deleteFiles(at offsets: IndexSet) {
        for index in offsets {
            let url = selectedFiles[index]
            processingStatus.removeValue(forKey: url)
        }
        selectedFiles.remove(atOffsets: offsets)
    }

    private func startBatchProcessing() {
        isProcessing = true
        overallProgress = 0

        // Initialize status
        for url in selectedFiles {
            processingStatus[url] = .pending
        }

        Task {
            for (index, url) in selectedFiles.enumerated() {
                processingStatus[url] = .processing

                do {
                    if batchMode == .convert {
                        try await convertFile(url)
                    } else {
                        try await compressFile(url)
                    }
                    processingStatus[url] = .completed
                } catch {
                    processingStatus[url] = .failed(error.localizedDescription)
                }

                overallProgress = Double(index + 1) / Double(selectedFiles.count)
            }

            isProcessing = false
        }
    }

    private func convertFile(_ url: URL) async throws {
        guard let pdf = PDFDocument(url: url) else {
            throw NSError(domain: "BatchProcessing", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Could not open PDF"
            ])
        }

        let converter = MarkdownConverter()
        _ = try await converter.convert(
            pdf: pdf,
            sourceURL: url,
            options: ConversionOptions(
                includeYAMLFrontmatter: appState.includeYAMLFrontmatter,
                imageOutputFormat: ImageFormat(rawValue: appState.imageOutputFormat) ?? .png
            ),
            progressHandler: { _ in }
        )
    }

    private func compressFile(_ url: URL) async throws {
        let service = CompressionService()
        _ = try await service.compress(
            pdfURL: url,
            targetRatio: appState.targetCompressionRatio,
            progressHandler: { _ in }
        )
    }

    private func cancelProcessing() {
        isProcessing = false
        // Note: In a real implementation, you'd want to cancel the current task
    }
}

// MARK: - Batch File Row

struct BatchFileRow: View {
    let url: URL
    let status: BatchProcessingView.ProcessingStatus

    var body: some View {
        HStack {
            Image(systemName: "doc.fill")
                .foregroundStyle(.red)

            VStack(alignment: .leading) {
                Text(url.lastPathComponent)
                    .lineLimit(1)

                Text(formattedSize)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            statusIcon
        }
    }

    private var formattedSize: String {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? Int64 else {
            return ""
        }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch status {
        case .pending:
            Image(systemName: "circle")
                .foregroundStyle(.secondary)
        case .processing:
            ProgressView()
                .scaleEffect(0.7)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed(let message):
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
                .help(message)
        }
    }
}

// MARK: - Batch Conversion Options

struct BatchConversionOptions: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Conversion Options")
                .font(.headline)

            Toggle("Include YAML Frontmatter", isOn: $appState.includeYAMLFrontmatter)
            Toggle("Extract Images", isOn: .constant(true))
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }
}

// MARK: - Batch Compression Options

struct BatchCompressionOptions: View {
    @Binding var targetRatio: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Compression Options")
                .font(.headline)

            HStack {
                Text("Target Size:")
                Slider(value: $targetRatio, in: 0.1...1.0)
                Text("\(Int(targetRatio * 100))%")
                    .frame(width: 40)
            }

            Text("Preset: \(GhostscriptPreset.forRatio(targetRatio).displayName)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }
}

// MARK: - Batch Summary View

struct BatchSummaryView: View {
    let status: [URL: BatchProcessingView.ProcessingStatus]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Summary")
                .font(.headline)

            HStack(spacing: 20) {
                StatView(
                    value: completedCount,
                    label: "Completed",
                    color: .green
                )

                StatView(
                    value: failedCount,
                    label: "Failed",
                    color: .red
                )

                StatView(
                    value: status.count,
                    label: "Total",
                    color: .blue
                )
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    private var completedCount: Int {
        status.values.filter {
            if case .completed = $0 { return true }
            return false
        }.count
    }

    private var failedCount: Int {
        status.values.filter {
            if case .failed = $0 { return true }
            return false
        }.count
    }
}

struct StatView: View {
    let value: Int
    let label: String
    let color: Color

    var body: some View {
        VStack {
            Text("\(value)")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundStyle(color)

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    BatchProcessingView()
        .environmentObject(AppState())
        .frame(width: 350, height: 600)
}
