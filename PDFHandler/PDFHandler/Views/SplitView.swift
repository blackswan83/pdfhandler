//
//  SplitView.swift
//  PDFHandler
//
//  View for splitting PDFs
//

import SwiftUI
import PDFKit

struct SplitOptionsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.colorScheme) var colorScheme
    @State private var pagesPerSplit = 1
    @State private var maxFileSizeMB = 10.0
    @State private var statusMessage = ""
    @State private var isSuccess = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("$ ./split")
                        .font(SumiTypography.monoLarge)
                        .foregroundStyle(colorScheme == .dark ? Color.phosphorGreen : Color.terminalGreen)
                    Text("Split PDF into multiple documents")
                        .font(SumiTypography.monoSmall)
                        .foregroundStyle(Color.stonegrey)
                }
                .padding(.bottom, 8)

                if appState.currentPDF == nil {
                    Text("No PDF selected. Open a file first.")
                        .font(SumiTypography.mono)
                        .foregroundStyle(Color.stonegrey)
                        .padding(.vertical, 20)
                } else {
                    // Current file info
                    if let url = appState.currentPDFURL, let pdf = appState.currentPDF {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("--input")
                                .font(SumiTypography.mono)
                                .foregroundStyle(colorScheme == .dark ? .white : Color.inkBlack)
                            Text(url.lastPathComponent)
                                .font(SumiTypography.monoSmall)
                                .foregroundStyle(Color.stonegrey)
                            Text("\(pdf.pageCount) pages")
                                .font(SumiTypography.monoSmall)
                                .foregroundStyle(Color.stonegrey)
                        }
                    }

                    Divider()
                        .background(Color.stonegrey.opacity(0.3))

                    // Split mode
                    VStack(alignment: .leading, spacing: 12) {
                        Text("--mode")
                            .font(SumiTypography.mono)
                            .foregroundStyle(colorScheme == .dark ? .white : Color.inkBlack)

                        ForEach(SplitMode.allCases) { mode in
                            Button(action: { appState.splitMode = mode }) {
                                HStack(spacing: 12) {
                                    Text(appState.splitMode == mode ? "[●]" : "[ ]")
                                        .font(SumiTypography.mono)
                                        .foregroundStyle(
                                            appState.splitMode == mode
                                                ? (colorScheme == .dark ? Color.phosphorGreen : Color.terminalGreen)
                                                : Color.stonegrey
                                        )

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(mode.displayName)
                                            .font(SumiTypography.mono)
                                            .foregroundStyle(colorScheme == .dark ? .white : Color.inkBlack)
                                        Text(mode.description)
                                            .font(SumiTypography.monoSmall)
                                            .foregroundStyle(Color.stonegrey)
                                    }

                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Divider()
                        .background(Color.stonegrey.opacity(0.3))

                    // Mode-specific options
                    switch appState.splitMode {
                    case .pageRanges:
                        VStack(alignment: .leading, spacing: 8) {
                            Text("--pages")
                                .font(SumiTypography.mono)
                                .foregroundStyle(colorScheme == .dark ? .white : Color.inkBlack)
                            TextField("e.g., 1-3, 5, 7-10", text: $appState.splitPageRanges)
                                .font(SumiTypography.mono)
                                .textFieldStyle(.plain)
                                .padding(8)
                                .background(Color.stonegrey.opacity(0.1))
                                .cornerRadius(4)
                        }

                    case .everyNPages:
                        VStack(alignment: .leading, spacing: 8) {
                            Text("--pages-per-file \(pagesPerSplit)")
                                .font(SumiTypography.mono)
                                .foregroundStyle(colorScheme == .dark ? .white : Color.inkBlack)
                            Slider(value: Binding(
                                get: { Double(pagesPerSplit) },
                                set: { pagesPerSplit = Int($0) }
                            ), in: 1...20, step: 1)
                            .tint(colorScheme == .dark ? Color.phosphorGreen : Color.terminalGreen)
                        }

                    case .byFileSize:
                        VStack(alignment: .leading, spacing: 8) {
                            Text("--max-size \(Int(maxFileSizeMB))MB")
                                .font(SumiTypography.mono)
                                .foregroundStyle(colorScheme == .dark ? .white : Color.inkBlack)
                            Slider(value: $maxFileSizeMB, in: 1...50, step: 1)
                                .tint(colorScheme == .dark ? Color.phosphorGreen : Color.terminalGreen)
                        }

                    case .allPages:
                        Text("Each page will be saved as a separate PDF.")
                            .font(SumiTypography.monoSmall)
                            .foregroundStyle(Color.stonegrey)
                    }

                    Divider()
                        .background(Color.stonegrey.opacity(0.3))

                    // Progress
                    if appState.isSplitting {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("splitting...")
                                .font(SumiTypography.mono)
                                .foregroundStyle(colorScheme == .dark ? Color.phosphorGreen : Color.terminalGreen)

                            ProgressView(value: appState.splitProgress)
                                .tint(colorScheme == .dark ? Color.phosphorGreen : Color.terminalGreen)

                            Text("\(Int(appState.splitProgress * 100))%")
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

                    // Split button
                    Button(action: performSplit) {
                        Text("[split pdf]")
                            .font(SumiTypography.mono)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                    .background(colorScheme == .dark ? Color.phosphorGreen : Color.terminalGreen)
                    .foregroundStyle(Color.inkBlack)
                    .cornerRadius(4)
                    .disabled(appState.isSplitting || appState.currentPDF == nil)
                }
            }
            .padding(20)
        }
    }

    private func performSplit() {
        guard let url = appState.currentPDFURL else { return }

        Task {
            appState.isSplitting = true
            appState.splitProgress = 0
            statusMessage = ""

            do {
                let options = SplitOptions(
                    mode: appState.splitMode,
                    pageRanges: appState.splitPageRanges,
                    pagesPerSplit: pagesPerSplit,
                    maxFileSizeMB: maxFileSizeMB
                )

                let result = try await appState.pdfToolsService.split(
                    pdfURL: url,
                    options: options,
                    progressHandler: { progress in
                        Task { @MainActor in
                            appState.splitProgress = progress
                        }
                    }
                )
                statusMessage = "✓ created \(result.outputURLs.count) files"
                isSuccess = true
            } catch {
                statusMessage = "✗ error: \(error.localizedDescription)"
                isSuccess = false
            }

            appState.isSplitting = false
        }
    }
}
