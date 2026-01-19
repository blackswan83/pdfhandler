//
//  RotateView.swift
//  PDFHandler
//
//  View for rotating PDF pages
//

import SwiftUI
import PDFKit

struct RotateOptionsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.colorScheme) var colorScheme
    @State private var selectedAngle: RotationAngle = .clockwise90
    @State private var specificPages = ""
    @State private var statusMessage = ""
    @State private var isSuccess = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("$ ./rotate")
                        .font(SumiTypography.monoLarge)
                        .foregroundStyle(colorScheme == .dark ? Color.phosphorGreen : Color.terminalGreen)
                    Text("Rotate PDF pages")
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

                    // Rotation angle
                    VStack(alignment: .leading, spacing: 12) {
                        Text("--angle")
                            .font(SumiTypography.mono)
                            .foregroundStyle(colorScheme == .dark ? .white : Color.inkBlack)

                        HStack(spacing: 16) {
                            ForEach(RotationAngle.allCases) { angle in
                                Button(action: { selectedAngle = angle }) {
                                    VStack(spacing: 8) {
                                        Image(systemName: angle.icon)
                                            .font(.system(size: 24))
                                        Text(angle.displayName)
                                            .font(SumiTypography.monoSmall)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(
                                        selectedAngle == angle
                                            ? (colorScheme == .dark ? Color.phosphorGreen : Color.terminalGreen).opacity(0.2)
                                            : Color.stonegrey.opacity(0.1)
                                    )
                                    .cornerRadius(4)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4)
                                            .stroke(
                                                selectedAngle == angle
                                                    ? (colorScheme == .dark ? Color.phosphorGreen : Color.terminalGreen)
                                                    : Color.clear,
                                                lineWidth: 1
                                            )
                                    )
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(
                                    selectedAngle == angle
                                        ? (colorScheme == .dark ? Color.phosphorGreen : Color.terminalGreen)
                                        : (colorScheme == .dark ? .white : Color.inkBlack)
                                )
                            }
                        }
                    }

                    Divider()
                        .background(Color.stonegrey.opacity(0.3))

                    // Page selection
                    VStack(alignment: .leading, spacing: 12) {
                        Text("--pages")
                            .font(SumiTypography.mono)
                            .foregroundStyle(colorScheme == .dark ? .white : Color.inkBlack)

                        Button(action: { appState.rotateAllPages = true }) {
                            HStack(spacing: 12) {
                                Text(appState.rotateAllPages ? "[●]" : "[ ]")
                                    .font(SumiTypography.mono)
                                    .foregroundStyle(
                                        appState.rotateAllPages
                                            ? (colorScheme == .dark ? Color.phosphorGreen : Color.terminalGreen)
                                            : Color.stonegrey
                                    )
                                Text("All pages")
                                    .font(SumiTypography.mono)
                                    .foregroundStyle(colorScheme == .dark ? .white : Color.inkBlack)
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)

                        Button(action: { appState.rotateAllPages = false }) {
                            HStack(spacing: 12) {
                                Text(!appState.rotateAllPages ? "[●]" : "[ ]")
                                    .font(SumiTypography.mono)
                                    .foregroundStyle(
                                        !appState.rotateAllPages
                                            ? (colorScheme == .dark ? Color.phosphorGreen : Color.terminalGreen)
                                            : Color.stonegrey
                                    )
                                Text("Specific pages")
                                    .font(SumiTypography.mono)
                                    .foregroundStyle(colorScheme == .dark ? .white : Color.inkBlack)
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)

                        if !appState.rotateAllPages {
                            TextField("e.g., 1, 3, 5-7", text: $specificPages)
                                .font(SumiTypography.mono)
                                .textFieldStyle(.plain)
                                .padding(8)
                                .background(Color.stonegrey.opacity(0.1))
                                .cornerRadius(4)
                        }
                    }

                    Divider()
                        .background(Color.stonegrey.opacity(0.3))

                    // Progress
                    if appState.isRotating {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("rotating...")
                                .font(SumiTypography.mono)
                                .foregroundStyle(colorScheme == .dark ? Color.phosphorGreen : Color.terminalGreen)

                            ProgressView(value: appState.rotateProgress)
                                .tint(colorScheme == .dark ? Color.phosphorGreen : Color.terminalGreen)

                            Text("\(Int(appState.rotateProgress * 100))%")
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

                    // Rotate button
                    Button(action: performRotate) {
                        Text("[rotate pdf]")
                            .font(SumiTypography.mono)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                    .background(colorScheme == .dark ? Color.phosphorGreen : Color.terminalGreen)
                    .foregroundStyle(Color.inkBlack)
                    .cornerRadius(4)
                    .disabled(appState.isRotating || appState.currentPDF == nil)
                }
            }
            .padding(20)
        }
    }

    private func performRotate() {
        guard let url = appState.currentPDFURL else { return }

        Task {
            appState.isRotating = true
            appState.rotateProgress = 0
            statusMessage = ""

            do {
                var options = RotateOptions(
                    angle: selectedAngle,
                    applyToAllPages: appState.rotateAllPages
                )

                if !appState.rotateAllPages {
                    options.specificPages = parsePages(specificPages)
                }

                let result = try await appState.pdfToolsService.rotate(
                    pdfURL: url,
                    options: options,
                    progressHandler: { progress in
                        Task { @MainActor in
                            appState.rotateProgress = progress
                        }
                    }
                )
                statusMessage = "✓ rotated \(result.pagesRotated) pages → \(result.outputURL.lastPathComponent)"
                isSuccess = true
            } catch {
                statusMessage = "✗ error: \(error.localizedDescription)"
                isSuccess = false
            }

            appState.isRotating = false
        }
    }

    private func parsePages(_ input: String) -> [Int] {
        var pages: [Int] = []
        let components = input.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }

        for component in components {
            if component.contains("-") {
                let parts = component.components(separatedBy: "-")
                if parts.count == 2,
                   let start = Int(parts[0].trimmingCharacters(in: .whitespaces)),
                   let end = Int(parts[1].trimmingCharacters(in: .whitespaces)) {
                    pages.append(contentsOf: Array(start...end))
                }
            } else if let page = Int(component) {
                pages.append(page)
            }
        }

        return pages
    }
}
