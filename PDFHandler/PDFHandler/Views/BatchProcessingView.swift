//
//  BatchProcessingView.swift
//  PDFHandler
//
//  Batch processing for multiple PDFs
//  Design: CLI precision meets calligraphic craft
//

import SwiftUI
import UniformTypeIdentifiers
import PDFKit

struct BatchProcessingView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.colorScheme) var colorScheme
    @State private var batchMode: BatchMode = .convert
    @State private var selectedFiles: [URL] = []
    @State private var processingStatus: [URL: ProcessingStatus] = [:]
    @State private var isProcessing = false
    @State private var overallProgress: Double = 0

    enum BatchMode: String, CaseIterable {
        case convert = "convert"
        case compress = "compress"
    }

    enum ProcessingStatus {
        case pending
        case processing
        case completed
        case failed(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Header
            Text("./batch")
                .font(SumiTypography.monoTitle)
                .foregroundStyle(colorScheme == .dark ? .white : Color.inkBlack)

            // Mode Selection
            HStack(spacing: 0) {
                ForEach(BatchMode.allCases, id: \.self) { mode in
                    Button(action: { batchMode = mode }) {
                        Text(mode.rawValue)
                            .font(SumiTypography.mono)
                            .foregroundStyle(
                                batchMode == mode
                                    ? (colorScheme == .dark ? Color.phosphorGreen : Color.terminalGreen)
                                    : Color.stonegrey
                            )
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                batchMode == mode
                                    ? (colorScheme == .dark ? Color.phosphorGreen : Color.terminalGreen).opacity(0.1)
                                    : Color.clear
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(colorScheme == .dark ? Color.sumiGrey : Color.surface)
            .cornerRadius(4)

            // File List
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("--files")
                        .font(SumiTypography.monoSmall)
                        .foregroundStyle(Color.stonegrey)

                    Spacer()

                    Button(action: addFiles) {
                        Text("[+ add]")
                            .font(SumiTypography.monoSmall)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(colorScheme == .dark ? Color.phosphorGreen : Color.terminalGreen)

                    if !selectedFiles.isEmpty {
                        Button(action: clearFiles) {
                            Text("[clear]")
                                .font(SumiTypography.monoSmall)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.stonegrey)
                    }
                }

                if selectedFiles.isEmpty {
                    // Empty state - Sumi style
                    VStack(spacing: 12) {
                        Text("_")
                            .font(SumiTypography.commandLarge)
                            .foregroundStyle(Color.stonegrey.opacity(0.5))

                        Text("no files selected")
                            .font(SumiTypography.mono)
                            .foregroundStyle(Color.stonegrey)

                        Button(action: addFiles) {
                            Text("[select files]")
                                .font(SumiTypography.mono)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(colorScheme == .dark ? Color.phosphorGreen : Color.terminalGreen)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 150)
                    .background(colorScheme == .dark ? Color.sumiGrey : Color.surface)
                    .cornerRadius(4)
                } else {
                    // File list
                    VStack(spacing: 0) {
                        ForEach(selectedFiles, id: \.self) { url in
                            SumiBatchFileRow(
                                url: url,
                                status: processingStatus[url] ?? .pending,
                                colorScheme: colorScheme
                            )

                            if url != selectedFiles.last {
                                Divider()
                                    .background(colorScheme == .dark ? Color.sumiGrey : Color.mist)
                            }
                        }
                    }
                    .background(colorScheme == .dark ? Color.sumiGrey : Color.surface)
                    .cornerRadius(4)
                }
            }

            // Options
            VStack(alignment: .leading, spacing: 8) {
                Text("--options")
                    .font(SumiTypography.monoSmall)
                    .foregroundStyle(Color.stonegrey)

                if batchMode == .convert {
                    SumiToggleOption(
                        label: "yaml frontmatter",
                        isOn: $appState.includeYAMLFrontmatter
                    )
                    SumiToggleOption(
                        label: "extract images",
                        isOn: .constant(true)
                    )
                } else {
                    SumiSlider(
                        value: $appState.targetCompressionRatio,
                        range: 0.1...1.0,
                        label: "target size"
                    )

                    HStack {
                        Text("preset:")
                            .font(SumiTypography.monoSmall)
                            .foregroundStyle(Color.stonegrey)
                        Text(GhostscriptPreset.forRatio(appState.targetCompressionRatio).displayName)
                            .font(SumiTypography.monoSmall)
                            .foregroundStyle(colorScheme == .dark ? .white : Color.inkBlack)
                    }
                }
            }
            .padding(16)
            .background(colorScheme == .dark ? Color.sumiGrey : Color.surface)
            .cornerRadius(4)

            Spacer()

            // Progress or Action
            if isProcessing {
                VStack(alignment: .leading, spacing: 8) {
                    CLIProgressBar(
                        progress: overallProgress,
                        label: "processing → \(completedCount)/\(selectedFiles.count) files"
                    )

                    Button(action: cancelProcessing) {
                        Text("[cancel]")
                            .font(SumiTypography.mono)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.stonegrey)
                }
            } else {
                HStack(spacing: 16) {
                    Button(action: startBatchProcessing) {
                        Text(batchMode == .convert ? "[convert all]" : "[compress all]")
                            .font(SumiTypography.mono)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(
                        selectedFiles.isEmpty
                            ? Color.stonegrey
                            : (colorScheme == .dark ? Color.phosphorGreen : Color.terminalGreen)
                    )
                    .disabled(selectedFiles.isEmpty)

                    if !selectedFiles.isEmpty {
                        Text("\(selectedFiles.count) files")
                            .font(SumiTypography.monoSmall)
                            .foregroundStyle(Color.stonegrey)
                    }
                }
            }

            // Summary
            if !processingStatus.isEmpty && !isProcessing {
                SumiBatchSummary(status: processingStatus, colorScheme: colorScheme)
            }
        }
        .padding(20)
        .background(colorScheme == .dark ? Color.charcoal : Color.paperBackground)
        .onAppear {
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
        DispatchQueue.main.async {
            let panel = NSOpenPanel()
            panel.allowsMultipleSelection = true
            panel.canChooseDirectories = false
            panel.canChooseFiles = true
            panel.allowedContentTypes = [.pdf]
            panel.message = "Select PDF files to process"
            panel.prompt = "Select"

            if panel.runModal() == .OK {
                let newFiles = panel.urls.filter { !selectedFiles.contains($0) }
                selectedFiles.append(contentsOf: newFiles)
            }
        }
    }

    private func clearFiles() {
        selectedFiles = []
        processingStatus = [:]
    }

    private func startBatchProcessing() {
        isProcessing = true
        overallProgress = 0

        for url in selectedFiles {
            processingStatus[url] = .pending
        }

        Task {
            for (index, url) in selectedFiles.enumerated() {
                await MainActor.run {
                    processingStatus[url] = .processing
                }

                do {
                    if batchMode == .convert {
                        try await convertFile(url)
                    } else {
                        try await compressFile(url)
                    }
                    await MainActor.run {
                        processingStatus[url] = .completed
                    }
                } catch {
                    await MainActor.run {
                        processingStatus[url] = .failed(error.localizedDescription)
                    }
                }

                await MainActor.run {
                    overallProgress = Double(index + 1) / Double(selectedFiles.count)
                }
            }

            await MainActor.run {
                isProcessing = false
            }
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
    }
}

// MARK: - Sumi Batch File Row

struct SumiBatchFileRow: View {
    let url: URL
    let status: BatchProcessingView.ProcessingStatus
    let colorScheme: ColorScheme

    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            statusIndicator

            // File info
            VStack(alignment: .leading, spacing: 2) {
                Text(url.lastPathComponent)
                    .font(SumiTypography.mono)
                    .foregroundStyle(colorScheme == .dark ? .white : Color.inkBlack)
                    .lineLimit(1)

                Text(formattedSize)
                    .font(SumiTypography.monoSmall)
                    .foregroundStyle(Color.stonegrey)
            }

            Spacer()

            // Status text
            statusText
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var formattedSize: String {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? Int64 else {
            return "--"
        }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch status {
        case .pending:
            Text("○")
                .font(SumiTypography.mono)
                .foregroundStyle(Color.stonegrey)
        case .processing:
            Text("◐")
                .font(SumiTypography.mono)
                .foregroundStyle(colorScheme == .dark ? Color.phosphorGreen : Color.terminalGreen)
        case .completed:
            Text("✓")
                .font(SumiTypography.mono)
                .foregroundStyle(colorScheme == .dark ? Color.phosphorGreen : Color.terminalGreen)
        case .failed:
            Text("×")
                .font(SumiTypography.mono)
                .foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private var statusText: some View {
        switch status {
        case .pending:
            Text("pending")
                .font(SumiTypography.monoSmall)
                .foregroundStyle(Color.stonegrey)
        case .processing:
            Text("processing...")
                .font(SumiTypography.monoSmall)
                .foregroundStyle(colorScheme == .dark ? Color.phosphorGreen : Color.terminalGreen)
        case .completed:
            Text("done")
                .font(SumiTypography.monoSmall)
                .foregroundStyle(colorScheme == .dark ? Color.phosphorGreen : Color.terminalGreen)
        case .failed(let message):
            Text("failed")
                .font(SumiTypography.monoSmall)
                .foregroundStyle(.orange)
                .help(message)
        }
    }
}

// MARK: - Sumi Batch Summary

struct SumiBatchSummary: View {
    let status: [URL: BatchProcessingView.ProcessingStatus]
    let colorScheme: ColorScheme

    var body: some View {
        HStack(spacing: 24) {
            // Completed
            HStack(spacing: 4) {
                Text("✓")
                    .foregroundStyle(colorScheme == .dark ? Color.phosphorGreen : Color.terminalGreen)
                Text("\(completedCount)")
                    .foregroundStyle(colorScheme == .dark ? .white : Color.inkBlack)
                Text("done")
                    .foregroundStyle(Color.stonegrey)
            }

            // Failed
            if failedCount > 0 {
                HStack(spacing: 4) {
                    Text("×")
                        .foregroundStyle(.orange)
                    Text("\(failedCount)")
                        .foregroundStyle(colorScheme == .dark ? .white : Color.inkBlack)
                    Text("failed")
                        .foregroundStyle(Color.stonegrey)
                }
            }

            Spacer()

            // Total
            Text("\(status.count) total")
                .foregroundStyle(Color.stonegrey)
        }
        .font(SumiTypography.mono)
        .padding(12)
        .background(
            (colorScheme == .dark ? Color.phosphorGreen : Color.terminalGreen)
                .opacity(0.05)
        )
        .cornerRadius(4)
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

#Preview {
    BatchProcessingView()
        .environmentObject(AppState())
        .frame(width: 350, height: 600)
        .background(Color.paperBackground)
}
