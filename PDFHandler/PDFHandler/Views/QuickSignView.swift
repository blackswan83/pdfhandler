//
//  QuickSignView.swift
//  PDFHandler
//
//  Simple, accessible signature view - type your name, get a cursive signature
//  Designed for ease of use
//

import SwiftUI
import PDFKit
import AppKit

struct QuickSignView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.colorScheme) var colorScheme
    @State private var statusMessage = ""
    @State private var isSuccess = false
    @State private var selectedPosition: SignaturePosition = .bottomRight
    @State private var selectedPage: Int = 1
    @State private var signLastPage: Bool = true

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                // Header - Large and clear
                VStack(spacing: 8) {
                    Text("Quick Sign")
                        .font(.system(size: 32, weight: .medium, design: .rounded))
                        .foregroundStyle(colorScheme == .dark ? .white : Color.inkBlack)

                    Text("Type your name to create a signature")
                        .font(.system(size: 16, design: .rounded))
                        .foregroundStyle(Color.stonegrey)
                }
                .padding(.top, 20)

                // Step 1: Open a PDF (if not already open)
                if appState.currentPDF == nil {
                    VStack(spacing: 16) {
                        Image(systemName: "doc.badge.plus")
                            .font(.system(size: 48))
                            .foregroundStyle(Color.stonegrey)

                        Text("Open a PDF to sign")
                            .font(.system(size: 18, design: .rounded))
                            .foregroundStyle(Color.stonegrey)

                        Button(action: { appState.showFilePicker = true }) {
                            HStack {
                                Image(systemName: "folder")
                                Text("Choose PDF")
                            }
                            .font(.system(size: 18, weight: .medium, design: .rounded))
                            .padding(.horizontal, 32)
                            .padding(.vertical, 16)
                            .background(colorScheme == .dark ? Color.phosphorGreen : Color.terminalGreen)
                            .foregroundStyle(Color.inkBlack)
                            .cornerRadius(12)
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(40)
                    .background(Color.stonegrey.opacity(0.1))
                    .cornerRadius(16)
                } else {
                    // Show current file
                    if let url = appState.currentPDFURL {
                        HStack {
                            Image(systemName: "doc.fill")
                                .font(.system(size: 24))
                                .foregroundStyle(colorScheme == .dark ? Color.phosphorGreen : Color.terminalGreen)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(url.lastPathComponent)
                                    .font(.system(size: 16, weight: .medium, design: .rounded))
                                    .lineLimit(1)
                                if let pdf = appState.currentPDF {
                                    Text("\(pdf.pageCount) pages")
                                        .font(.system(size: 14, design: .rounded))
                                        .foregroundStyle(Color.stonegrey)
                                }
                            }

                            Spacer()

                            Button(action: { appState.showFilePicker = true }) {
                                Text("Change")
                                    .font(.system(size: 14, design: .rounded))
                                    .foregroundStyle(colorScheme == .dark ? Color.phosphorGreen : Color.terminalGreen)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(16)
                        .background(Color.stonegrey.opacity(0.1))
                        .cornerRadius(12)
                    }

                    Divider()
                        .padding(.vertical, 8)

                    // Step 2: Type your name
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Type your name", systemImage: "keyboard")
                            .font(.system(size: 18, weight: .medium, design: .rounded))
                            .foregroundStyle(colorScheme == .dark ? .white : Color.inkBlack)

                        TextField("Your full name", text: $appState.quickSignName)
                            .font(.system(size: 24, design: .rounded))
                            .textFieldStyle(.plain)
                            .padding(20)
                            .background(Color.stonegrey.opacity(0.1))
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(
                                        appState.quickSignName.isEmpty
                                            ? Color.stonegrey.opacity(0.3)
                                            : (colorScheme == .dark ? Color.phosphorGreen : Color.terminalGreen),
                                        lineWidth: 2
                                    )
                            )
                    }

                    // Step 3: Preview signature
                    if !appState.quickSignName.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Your signature", systemImage: "signature")
                                .font(.system(size: 18, weight: .medium, design: .rounded))
                                .foregroundStyle(colorScheme == .dark ? .white : Color.inkBlack)

                            // Signature preview
                            VStack(spacing: 8) {
                                Text(appState.quickSignName)
                                    .font(.custom(appState.quickSignFontStyle.fontName, size: appState.quickSignFontStyle.fontSize))
                                    .foregroundStyle(Color.inkBlack)
                                    .padding(.vertical, 20)

                                if appState.quickSignIncludeDate {
                                    Text(formattedDate())
                                        .font(.system(size: 14, design: .rounded))
                                        .foregroundStyle(Color.stonegrey)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(24)
                            .background(Color.white)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.stonegrey.opacity(0.3), lineWidth: 1)
                            )
                        }

                        // Step 4: Choose style
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Choose style", systemImage: "textformat")
                                .font(.system(size: 18, weight: .medium, design: .rounded))
                                .foregroundStyle(colorScheme == .dark ? .white : Color.inkBlack)

                            HStack(spacing: 12) {
                                ForEach(SignatureFontStyle.allCases) { style in
                                    Button(action: { appState.quickSignFontStyle = style }) {
                                        VStack(spacing: 8) {
                                            Text("Aa")
                                                .font(.custom(style.fontName, size: 24))
                                                .foregroundStyle(Color.inkBlack)
                                                .frame(height: 32)

                                            Text(style.displayName)
                                                .font(.system(size: 12, design: .rounded))
                                                .foregroundStyle(
                                                    appState.quickSignFontStyle == style
                                                        ? (colorScheme == .dark ? Color.phosphorGreen : Color.terminalGreen)
                                                        : Color.stonegrey
                                                )
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 16)
                                        .background(
                                            appState.quickSignFontStyle == style
                                                ? (colorScheme == .dark ? Color.phosphorGreen : Color.terminalGreen).opacity(0.15)
                                                : Color.stonegrey.opacity(0.1)
                                        )
                                        .cornerRadius(12)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(
                                                    appState.quickSignFontStyle == style
                                                        ? (colorScheme == .dark ? Color.phosphorGreen : Color.terminalGreen)
                                                        : Color.clear,
                                                    lineWidth: 2
                                                )
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        // Options
                        VStack(alignment: .leading, spacing: 16) {
                            Toggle(isOn: $appState.quickSignIncludeDate) {
                                HStack {
                                    Image(systemName: "calendar")
                                        .font(.system(size: 20))
                                    Text("Include today's date")
                                        .font(.system(size: 16, design: .rounded))
                                }
                            }
                            .toggleStyle(.checkbox)
                            .padding(.vertical, 4)
                        }
                        .padding(16)
                        .background(Color.stonegrey.opacity(0.05))
                        .cornerRadius(12)

                        // Position selection
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Where to sign", systemImage: "square.grid.3x3")
                                .font(.system(size: 18, weight: .medium, design: .rounded))
                                .foregroundStyle(colorScheme == .dark ? .white : Color.inkBlack)

                            // 3x3 position grid
                            VStack(spacing: 6) {
                                HStack(spacing: 6) {
                                    positionButton(.topLeft, label: "↖")
                                    positionButton(.topCenter, label: "↑")
                                    positionButton(.topRight, label: "↗")
                                }
                                HStack(spacing: 6) {
                                    positionButton(.centerLeft, label: "←")
                                    positionButton(.center, label: "●")
                                    positionButton(.centerRight, label: "→")
                                }
                                HStack(spacing: 6) {
                                    positionButton(.bottomLeft, label: "↙")
                                    positionButton(.bottomCenter, label: "↓")
                                    positionButton(.bottomRight, label: "↘")
                                }
                            }
                            .padding(12)
                            .background(Color.stonegrey.opacity(0.05))
                            .cornerRadius(12)

                            Text("Selected: \(selectedPosition.displayName)")
                                .font(.system(size: 14, design: .rounded))
                                .foregroundStyle(Color.stonegrey)
                        }

                        // Page selection
                        if let pdf = appState.currentPDF, pdf.pageCount > 1 {
                            VStack(alignment: .leading, spacing: 12) {
                                Label("Which page", systemImage: "doc.on.doc")
                                    .font(.system(size: 18, weight: .medium, design: .rounded))
                                    .foregroundStyle(colorScheme == .dark ? .white : Color.inkBlack)

                                VStack(spacing: 12) {
                                    Toggle(isOn: $signLastPage) {
                                        Text("Sign last page (\(pdf.pageCount))")
                                            .font(.system(size: 16, design: .rounded))
                                    }
                                    .toggleStyle(.checkbox)

                                    if !signLastPage {
                                        HStack {
                                            Text("Page:")
                                                .font(.system(size: 16, design: .rounded))

                                            Picker("", selection: $selectedPage) {
                                                ForEach(1...pdf.pageCount, id: \.self) { page in
                                                    Text("\(page)").tag(page)
                                                }
                                            }
                                            .pickerStyle(.menu)
                                            .frame(width: 80)
                                        }
                                    }
                                }
                                .padding(12)
                                .background(Color.stonegrey.opacity(0.05))
                                .cornerRadius(12)
                            }
                        }

                        Divider()
                            .padding(.vertical, 8)

                        // Progress
                        if appState.isQuickSigning {
                            VStack(spacing: 12) {
                                ProgressView(value: appState.quickSignProgress)
                                    .tint(colorScheme == .dark ? Color.phosphorGreen : Color.terminalGreen)

                                Text("Signing document...")
                                    .font(.system(size: 16, design: .rounded))
                                    .foregroundStyle(Color.stonegrey)
                            }
                            .padding(.vertical, 16)
                        }

                        // Status message
                        if !statusMessage.isEmpty {
                            HStack {
                                Image(systemName: isSuccess ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                                    .font(.system(size: 20))
                                Text(statusMessage)
                                    .font(.system(size: 16, design: .rounded))
                            }
                            .foregroundStyle(isSuccess ? (colorScheme == .dark ? Color.phosphorGreen : Color.terminalGreen) : Color.red)
                            .padding(.vertical, 8)
                        }

                        // Sign button - Large and prominent
                        Button(action: performQuickSign) {
                            HStack(spacing: 12) {
                                Image(systemName: "signature")
                                    .font(.system(size: 24))
                                Text("Sign Document")
                                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                            .background(colorScheme == .dark ? Color.phosphorGreen : Color.terminalGreen)
                            .foregroundStyle(Color.inkBlack)
                            .cornerRadius(16)
                        }
                        .buttonStyle(.plain)
                        .disabled(appState.quickSignName.isEmpty || appState.isQuickSigning)
                        .opacity(appState.quickSignName.isEmpty ? 0.5 : 1)
                    }
                }

                Spacer()
            }
            .padding(24)
        }
        .frame(maxWidth: 500)
    }

    private func formattedDate() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        return formatter.string(from: Date())
    }

    @ViewBuilder
    private func positionButton(_ position: SignaturePosition, label: String) -> some View {
        Button(action: { selectedPosition = position }) {
            Text(label)
                .font(.system(size: 16, weight: .medium))
                .frame(width: 44, height: 36)
                .background(
                    selectedPosition == position
                        ? (colorScheme == .dark ? Color.phosphorGreen : Color.terminalGreen)
                        : Color.stonegrey.opacity(0.2)
                )
                .foregroundStyle(
                    selectedPosition == position
                        ? Color.inkBlack
                        : (colorScheme == .dark ? .white : Color.inkBlack)
                )
                .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }

    private func performQuickSign() {
        guard let url = appState.currentPDFURL,
              let pdf = appState.currentPDF,
              !appState.quickSignName.isEmpty else { return }

        Task {
            appState.isQuickSigning = true
            appState.quickSignProgress = 0
            statusMessage = ""

            do {
                // Generate signature image from text
                let signatureImage = createSignatureImage(
                    name: appState.quickSignName,
                    style: appState.quickSignFontStyle,
                    includeDate: appState.quickSignIncludeDate
                )

                appState.quickSignProgress = 0.3

                // Apply signature to selected position and page
                let pageToSign = signLastPage ? pdf.pageCount : selectedPage
                let options = SignatureOptions(
                    signatureImage: signatureImage,
                    position: selectedPosition,
                    width: 200,
                    height: appState.quickSignIncludeDate ? 80 : 60,
                    page: pageToSign,
                    applyToAllPages: false
                )

                appState.quickSignProgress = 0.5

                let result = try await appState.pdfToolsService.addSignature(
                    pdfURL: url,
                    options: options,
                    progressHandler: { progress in
                        Task { @MainActor in
                            appState.quickSignProgress = 0.5 + (progress * 0.5)
                        }
                    }
                )

                statusMessage = "Document signed successfully!"
                isSuccess = true

                // Show in Finder
                NSWorkspace.shared.selectFile(result.outputURL.path, inFileViewerRootedAtPath: result.outputURL.deletingLastPathComponent().path)

            } catch {
                statusMessage = "Failed to sign: \(error.localizedDescription)"
                isSuccess = false
            }

            appState.isQuickSigning = false
            appState.quickSignProgress = 1.0
        }
    }

    private func createSignatureImage(name: String, style: SignatureFontStyle, includeDate: Bool) -> NSImage {
        let font = NSFont(name: style.fontName, size: style.fontSize) ?? NSFont.systemFont(ofSize: style.fontSize)
        let dateFont = NSFont.systemFont(ofSize: 12)

        // Calculate sizes
        let nameAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black
        ]
        let nameSize = (name as NSString).size(withAttributes: nameAttributes)

        var totalHeight = nameSize.height + 20
        var dateSize = CGSize.zero

        if includeDate {
            let dateString = formattedDate()
            let dateAttributes: [NSAttributedString.Key: Any] = [
                .font: dateFont,
                .foregroundColor: NSColor.darkGray
            ]
            dateSize = (dateString as NSString).size(withAttributes: dateAttributes)
            totalHeight += dateSize.height + 8
        }

        let width = max(nameSize.width, dateSize.width) + 40
        let size = NSSize(width: width, height: totalHeight)

        let image = NSImage(size: size)
        image.lockFocus()

        // Transparent background
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: size).fill()

        // Draw signature name
        let nameRect = NSRect(
            x: (size.width - nameSize.width) / 2,
            y: includeDate ? (dateSize.height + 16) : 10,
            width: nameSize.width,
            height: nameSize.height
        )
        (name as NSString).draw(in: nameRect, withAttributes: nameAttributes)

        // Draw date if included
        if includeDate {
            let dateString = formattedDate()
            let dateAttributes: [NSAttributedString.Key: Any] = [
                .font: dateFont,
                .foregroundColor: NSColor.darkGray
            ]
            let dateRect = NSRect(
                x: (size.width - dateSize.width) / 2,
                y: 8,
                width: dateSize.width,
                height: dateSize.height
            )
            (dateString as NSString).draw(in: dateRect, withAttributes: dateAttributes)
        }

        image.unlockFocus()
        return image
    }
}

#Preview {
    QuickSignView()
        .environmentObject(AppState())
        .frame(width: 500, height: 700)
}
