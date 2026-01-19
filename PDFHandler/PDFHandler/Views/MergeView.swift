//
//  MergeView.swift
//  PDFHandler
//
//  View for merging multiple PDFs
//

import SwiftUI
import PDFKit
import UniformTypeIdentifiers

struct MergeOptionsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.colorScheme) var colorScheme
    @State private var showFilePicker = false
    @State private var outputName = "merged"
    @State private var statusMessage = ""
    @State private var isSuccess = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("$ ./merge")
                        .font(SumiTypography.monoLarge)
                        .foregroundStyle(colorScheme == .dark ? Color.phosphorGreen : Color.terminalGreen)
                    Text("Combine multiple PDFs into one document")
                        .font(SumiTypography.monoSmall)
                        .foregroundStyle(Color.stonegrey)
                }
                .padding(.bottom, 8)

                Divider()
                    .background(Color.stonegrey.opacity(0.3))

                // Files to merge
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("--files")
                            .font(SumiTypography.mono)
                            .foregroundStyle(colorScheme == .dark ? .white : Color.inkBlack)

                        Spacer()

                        Button(action: { showFilePicker = true }) {
                            Text("[add files]")
                                .font(SumiTypography.mono)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(colorScheme == .dark ? Color.phosphorGreen : Color.terminalGreen)
                    }

                    if appState.pdfFilesToMerge.isEmpty {
                        Text("No files selected. Add at least 2 PDFs to merge.")
                            .font(SumiTypography.monoSmall)
                            .foregroundStyle(Color.stonegrey)
                            .padding(.vertical, 8)
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(appState.pdfFilesToMerge.enumerated()), id: \.element) { index, url in
                                HStack {
                                    Text("\(index + 1).")
                                        .font(SumiTypography.monoSmall)
                                        .foregroundStyle(Color.stonegrey)
                                        .frame(width: 24, alignment: .trailing)

                                    Text(url.lastPathComponent)
                                        .font(SumiTypography.monoSmall)
                                        .foregroundStyle(colorScheme == .dark ? .white : Color.inkBlack)
                                        .lineLimit(1)

                                    Spacer()

                                    Button(action: {
                                        appState.pdfFilesToMerge.remove(at: index)
                                    }) {
                                        Text("[x]")
                                            .font(SumiTypography.monoSmall)
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(Color.red.opacity(0.8))
                                }
                            }
                        }
                        .padding(12)
                        .background(Color.stonegrey.opacity(0.1))
                        .cornerRadius(4)
                    }
                }

                Divider()
                    .background(Color.stonegrey.opacity(0.3))

                // Output name
                VStack(alignment: .leading, spacing: 8) {
                    Text("--output")
                        .font(SumiTypography.mono)
                        .foregroundStyle(colorScheme == .dark ? .white : Color.inkBlack)

                    TextField("merged", text: $outputName)
                        .font(SumiTypography.mono)
                        .textFieldStyle(.plain)
                        .padding(8)
                        .background(Color.stonegrey.opacity(0.1))
                        .cornerRadius(4)
                }

                Divider()
                    .background(Color.stonegrey.opacity(0.3))

                // Progress
                if appState.isMerging {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("merging...")
                            .font(SumiTypography.mono)
                            .foregroundStyle(colorScheme == .dark ? Color.phosphorGreen : Color.terminalGreen)

                        ProgressView(value: appState.mergeProgress)
                            .tint(colorScheme == .dark ? Color.phosphorGreen : Color.terminalGreen)

                        Text("\(Int(appState.mergeProgress * 100))%")
                            .font(SumiTypography.monoSmall)
                            .foregroundStyle(Color.stonegrey)
                    }
                }

                // Status message
                if !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(SumiTypography.monoSmall)
                        .foregroundStyle(isSuccess ? (colorScheme == .dark ? Color.phosphorGreen : Color.terminalGreen) : Color.red)
                }

                Spacer()

                // Merge button
                Button(action: performMerge) {
                    Text("[merge \(appState.pdfFilesToMerge.count) files]")
                        .font(SumiTypography.mono)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                .background(
                    appState.pdfFilesToMerge.count >= 2
                        ? (colorScheme == .dark ? Color.phosphorGreen : Color.terminalGreen)
                        : Color.stonegrey.opacity(0.3)
                )
                .foregroundStyle(
                    appState.pdfFilesToMerge.count >= 2
                        ? Color.inkBlack
                        : Color.stonegrey
                )
                .cornerRadius(4)
                .disabled(appState.pdfFilesToMerge.count < 2 || appState.isMerging)
            }
            .padding(20)
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                appState.pdfFilesToMerge.append(contentsOf: urls)
            }
        }
    }

    private func performMerge() {
        guard appState.pdfFilesToMerge.count >= 2 else { return }

        Task {
            appState.isMerging = true
            appState.mergeProgress = 0
            statusMessage = ""

            do {
                let options = MergeOptions(outputName: outputName)
                let result = try await appState.pdfToolsService.merge(
                    pdfURLs: appState.pdfFilesToMerge,
                    options: options,
                    progressHandler: { progress in
                        Task { @MainActor in
                            appState.mergeProgress = progress
                        }
                    }
                )
                statusMessage = "✓ merged \(result.totalPages) pages → \(result.outputURL.lastPathComponent)"
                isSuccess = true
                appState.pdfFilesToMerge = []
            } catch {
                statusMessage = "✗ error: \(error.localizedDescription)"
                isSuccess = false
            }

            appState.isMerging = false
        }
    }
}
