//
//  WatermarkView.swift
//  PDFHandler
//
//  View for adding watermarks to PDFs
//

import SwiftUI
import PDFKit
import AppKit

struct WatermarkOptionsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.colorScheme) var colorScheme
    @State private var watermarkType: WatermarkType = .text
    @State private var watermarkImage: NSImage?
    @State private var applyToAllPages = true
    @State private var specificPages = ""
    @State private var statusMessage = ""
    @State private var isSuccess = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("$ ./watermark")
                        .font(SumiTypography.monoLarge)
                        .foregroundStyle(colorScheme == .dark ? Color.phosphorGreen : Color.terminalGreen)
                    Text("Add watermark to PDF document")
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

                    // Watermark type
                    VStack(alignment: .leading, spacing: 12) {
                        Text("--type")
                            .font(SumiTypography.mono)
                            .foregroundStyle(colorScheme == .dark ? .white : Color.inkBlack)

                        HStack(spacing: 16) {
                            ForEach(WatermarkType.allCases) { type in
                                Button(action: { watermarkType = type }) {
                                    VStack(spacing: 8) {
                                        Image(systemName: type == .text ? "textformat" : "photo")
                                            .font(.system(size: 20))
                                        Text(type.displayName)
                                            .font(SumiTypography.monoSmall)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(
                                        watermarkType == type
                                            ? (colorScheme == .dark ? Color.phosphorGreen : Color.terminalGreen).opacity(0.2)
                                            : Color.stonegrey.opacity(0.1)
                                    )
                                    .cornerRadius(4)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4)
                                            .stroke(
                                                watermarkType == type
                                                    ? (colorScheme == .dark ? Color.phosphorGreen : Color.terminalGreen)
                                                    : Color.clear,
                                                lineWidth: 1
                                            )
                                    )
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(
                                    watermarkType == type
                                        ? (colorScheme == .dark ? Color.phosphorGreen : Color.terminalGreen)
                                        : (colorScheme == .dark ? .white : Color.inkBlack)
                                )
                            }
                        }
                    }

                    Divider()
                        .background(Color.stonegrey.opacity(0.3))

                    // Type-specific options
                    if watermarkType == .text {
                        // Text watermark options
                        VStack(alignment: .leading, spacing: 16) {
                            // Text input
                            VStack(alignment: .leading, spacing: 8) {
                                Text("--text")
                                    .font(SumiTypography.mono)
                                    .foregroundStyle(colorScheme == .dark ? .white : Color.inkBlack)

                                TextField("CONFIDENTIAL", text: $appState.watermarkText)
                                    .font(SumiTypography.mono)
                                    .textFieldStyle(.plain)
                                    .padding(8)
                                    .background(Color.stonegrey.opacity(0.1))
                                    .cornerRadius(4)

                                // Preset texts
                                HStack(spacing: 8) {
                                    ForEach(["CONFIDENTIAL", "DRAFT", "COPY", "SAMPLE"], id: \.self) { preset in
                                        Button(action: { appState.watermarkText = preset }) {
                                            Text(preset)
                                                .font(SumiTypography.monoSmall)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(Color.stonegrey.opacity(0.1))
                                                .cornerRadius(2)
                                        }
                                        .buttonStyle(.plain)
                                        .foregroundStyle(Color.stonegrey)
                                    }
                                }
                            }

                            // Font size
                            VStack(alignment: .leading, spacing: 8) {
                                Text("--font-size \(Int(appState.watermarkFontSize))pt")
                                    .font(SumiTypography.mono)
                                    .foregroundStyle(colorScheme == .dark ? .white : Color.inkBlack)

                                Slider(value: $appState.watermarkFontSize, in: 24...144, step: 4)
                                    .tint(colorScheme == .dark ? Color.phosphorGreen : Color.terminalGreen)
                            }

                            // Rotation
                            VStack(alignment: .leading, spacing: 8) {
                                Text("--rotation \(Int(appState.watermarkRotation))°")
                                    .font(SumiTypography.mono)
                                    .foregroundStyle(colorScheme == .dark ? .white : Color.inkBlack)

                                Slider(value: $appState.watermarkRotation, in: -90...90, step: 5)
                                    .tint(colorScheme == .dark ? Color.phosphorGreen : Color.terminalGreen)
                            }
                        }
                    } else {
                        // Image watermark options
                        VStack(alignment: .leading, spacing: 12) {
                            Text("--image")
                                .font(SumiTypography.mono)
                                .foregroundStyle(colorScheme == .dark ? .white : Color.inkBlack)

                            Button(action: importWatermarkImage) {
                                HStack {
                                    Image(systemName: "photo.badge.plus")
                                    Text("Select image")
                                        .font(SumiTypography.mono)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.stonegrey.opacity(0.1))
                                .cornerRadius(4)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(colorScheme == .dark ? .white : Color.inkBlack)

                            if let image = watermarkImage {
                                HStack {
                                    Image(nsImage: image)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(height: 60)
                                        .padding(8)
                                        .background(Color.white.opacity(0.5))
                                        .cornerRadius(4)

                                    Spacer()

                                    Button(action: { watermarkImage = nil }) {
                                        Text("[clear]")
                                            .font(SumiTypography.monoSmall)
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(Color.red.opacity(0.8))
                                }
                            }
                        }
                    }

                    Divider()
                        .background(Color.stonegrey.opacity(0.3))

                    // Opacity
                    VStack(alignment: .leading, spacing: 8) {
                        Text("--opacity \(Int(appState.watermarkOpacity * 100))%")
                            .font(SumiTypography.mono)
                            .foregroundStyle(colorScheme == .dark ? .white : Color.inkBlack)

                        Slider(value: $appState.watermarkOpacity, in: 0.1...1.0, step: 0.05)
                            .tint(colorScheme == .dark ? Color.phosphorGreen : Color.terminalGreen)
                    }

                    Divider()
                        .background(Color.stonegrey.opacity(0.3))

                    // Page selection
                    VStack(alignment: .leading, spacing: 12) {
                        Text("--pages")
                            .font(SumiTypography.mono)
                            .foregroundStyle(colorScheme == .dark ? .white : Color.inkBlack)

                        Toggle(isOn: $applyToAllPages) {
                            Text("Apply to all pages")
                                .font(SumiTypography.mono)
                        }
                        .toggleStyle(.checkbox)

                        if !applyToAllPages {
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

                    // Preview
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Preview:")
                            .font(SumiTypography.monoSmall)
                            .foregroundStyle(Color.stonegrey)

                        ZStack {
                            Rectangle()
                                .fill(Color.white)
                                .frame(height: 100)
                                .cornerRadius(4)

                            if watermarkType == .text {
                                Text(appState.watermarkText)
                                    .font(.system(size: appState.watermarkFontSize / 3))
                                    .foregroundStyle(Color.gray.opacity(appState.watermarkOpacity))
                                    .rotationEffect(.degrees(appState.watermarkRotation))
                            } else if let image = watermarkImage {
                                Image(nsImage: image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(height: 60)
                                    .opacity(appState.watermarkOpacity)
                            }
                        }
                    }

                    Divider()
                        .background(Color.stonegrey.opacity(0.3))

                    // Progress
                    if appState.isApplyingWatermark {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("applying watermark...")
                                .font(SumiTypography.mono)
                                .foregroundStyle(colorScheme == .dark ? Color.phosphorGreen : Color.terminalGreen)

                            ProgressView(value: appState.watermarkProgress)
                                .tint(colorScheme == .dark ? Color.phosphorGreen : Color.terminalGreen)

                            Text("\(Int(appState.watermarkProgress * 100))%")
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

                    // Watermark button
                    Button(action: performWatermark) {
                        Text("[apply watermark]")
                            .font(SumiTypography.mono)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                    .background(
                        canApplyWatermark
                            ? (colorScheme == .dark ? Color.phosphorGreen : Color.terminalGreen)
                            : Color.stonegrey.opacity(0.3)
                    )
                    .foregroundStyle(canApplyWatermark ? Color.inkBlack : Color.stonegrey)
                    .cornerRadius(4)
                    .disabled(!canApplyWatermark || appState.isApplyingWatermark)
                }
            }
            .padding(20)
        }
    }

    private var canApplyWatermark: Bool {
        guard appState.currentPDF != nil else { return false }
        if watermarkType == .text {
            return !appState.watermarkText.isEmpty
        } else {
            return watermarkImage != nil
        }
    }

    private func importWatermarkImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            if let image = NSImage(contentsOf: url) {
                watermarkImage = image
            }
        }
    }

    private func performWatermark() {
        guard let url = appState.currentPDFURL else { return }

        Task {
            appState.isApplyingWatermark = true
            appState.watermarkProgress = 0
            statusMessage = ""

            do {
                var options = WatermarkOptions(
                    type: watermarkType,
                    text: appState.watermarkText,
                    image: watermarkImage,
                    opacity: appState.watermarkOpacity,
                    rotation: appState.watermarkRotation,
                    fontSize: appState.watermarkFontSize,
                    applyToAllPages: applyToAllPages
                )

                if !applyToAllPages {
                    options.specificPages = parsePages(specificPages)
                }

                let result = try await appState.pdfToolsService.addWatermark(
                    pdfURL: url,
                    options: options,
                    progressHandler: { progress in
                        Task { @MainActor in
                            appState.watermarkProgress = progress
                        }
                    }
                )
                statusMessage = "✓ watermarked \(result.pagesModified) page(s) → \(result.outputURL.lastPathComponent)"
                isSuccess = true
            } catch {
                statusMessage = "✗ error: \(error.localizedDescription)"
                isSuccess = false
            }

            appState.isApplyingWatermark = false
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
