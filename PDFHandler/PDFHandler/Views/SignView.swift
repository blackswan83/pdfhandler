//
//  SignView.swift
//  PDFHandler
//
//  View for adding signatures to PDFs
//

import SwiftUI
import PDFKit
import AppKit

struct SignOptionsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.colorScheme) var colorScheme
    @State private var showImagePicker = false
    @State private var signatureWidth: Double = 150
    @State private var signatureHeight: Double = 50
    @State private var applyToAllPages = false
    @State private var statusMessage = ""
    @State private var isSuccess = false
    @State private var isDrawing = false
    @State private var drawingPath = Path()
    @State private var currentPoint: CGPoint = .zero

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("$ ./sign")
                        .font(SumiTypography.monoLarge)
                        .foregroundStyle(colorScheme == .dark ? Color.phosphorGreen : Color.terminalGreen)
                    Text("Add signature to PDF document")
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

                    // Signature input methods
                    VStack(alignment: .leading, spacing: 12) {
                        Text("--signature")
                            .font(SumiTypography.mono)
                            .foregroundStyle(colorScheme == .dark ? .white : Color.inkBlack)

                        HStack(spacing: 12) {
                            // Draw button
                            Button(action: { isDrawing = true }) {
                                VStack(spacing: 8) {
                                    Image(systemName: "pencil.tip")
                                        .font(.system(size: 20))
                                    Text("Draw")
                                        .font(SumiTypography.monoSmall)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.stonegrey.opacity(0.1))
                                .cornerRadius(4)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(colorScheme == .dark ? .white : Color.inkBlack)

                            // Import button
                            Button(action: importSignatureImage) {
                                VStack(spacing: 8) {
                                    Image(systemName: "photo")
                                        .font(.system(size: 20))
                                    Text("Import")
                                        .font(SumiTypography.monoSmall)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.stonegrey.opacity(0.1))
                                .cornerRadius(4)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(colorScheme == .dark ? .white : Color.inkBlack)
                        }

                        // Signature preview
                        if let image = appState.currentSignatureImage {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Preview:")
                                    .font(SumiTypography.monoSmall)
                                    .foregroundStyle(Color.stonegrey)

                                HStack {
                                    Image(nsImage: image)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(height: 60)
                                        .padding(8)
                                        .background(Color.white)
                                        .cornerRadius(4)

                                    Spacer()

                                    Button(action: { appState.currentSignatureImage = nil }) {
                                        Text("[clear]")
                                            .font(SumiTypography.monoSmall)
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(Color.red.opacity(0.8))
                                }
                            }
                        }
                    }

                    // Drawing canvas (shown when drawing mode is active)
                    if isDrawing {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Draw your signature:")
                                .font(SumiTypography.monoSmall)
                                .foregroundStyle(Color.stonegrey)

                            SignatureCanvasView(
                                path: $drawingPath,
                                onComplete: { image in
                                    appState.currentSignatureImage = image
                                    isDrawing = false
                                    drawingPath = Path()
                                },
                                onCancel: {
                                    isDrawing = false
                                    drawingPath = Path()
                                }
                            )
                            .frame(height: 150)
                        }
                    }

                    Divider()
                        .background(Color.stonegrey.opacity(0.3))

                    // Position selection
                    VStack(alignment: .leading, spacing: 12) {
                        Text("--position")
                            .font(SumiTypography.mono)
                            .foregroundStyle(colorScheme == .dark ? .white : Color.inkBlack)

                        // 3x3 grid for position
                        VStack(spacing: 4) {
                            HStack(spacing: 4) {
                                positionButton(.topLeft)
                                positionButton(.topCenter)
                                positionButton(.topRight)
                            }
                            HStack(spacing: 4) {
                                positionButton(.centerLeft)
                                positionButton(.center)
                                positionButton(.centerRight)
                            }
                            HStack(spacing: 4) {
                                positionButton(.bottomLeft)
                                positionButton(.bottomCenter)
                                positionButton(.bottomRight)
                            }
                        }
                    }

                    Divider()
                        .background(Color.stonegrey.opacity(0.3))

                    // Size controls
                    VStack(alignment: .leading, spacing: 12) {
                        Text("--size")
                            .font(SumiTypography.mono)
                            .foregroundStyle(colorScheme == .dark ? .white : Color.inkBlack)

                        HStack {
                            Text("Width: \(Int(signatureWidth))px")
                                .font(SumiTypography.monoSmall)
                                .foregroundStyle(Color.stonegrey)
                            Slider(value: $signatureWidth, in: 50...300, step: 10)
                                .tint(colorScheme == .dark ? Color.phosphorGreen : Color.terminalGreen)
                        }

                        HStack {
                            Text("Height: \(Int(signatureHeight))px")
                                .font(SumiTypography.monoSmall)
                                .foregroundStyle(Color.stonegrey)
                            Slider(value: $signatureHeight, in: 20...150, step: 5)
                                .tint(colorScheme == .dark ? Color.phosphorGreen : Color.terminalGreen)
                        }
                    }

                    Divider()
                        .background(Color.stonegrey.opacity(0.3))

                    // Page selection
                    VStack(alignment: .leading, spacing: 12) {
                        Text("--page")
                            .font(SumiTypography.mono)
                            .foregroundStyle(colorScheme == .dark ? .white : Color.inkBlack)

                        Toggle(isOn: $applyToAllPages) {
                            Text("Apply to all pages")
                                .font(SumiTypography.mono)
                        }
                        .toggleStyle(.checkbox)

                        if !applyToAllPages {
                            Stepper(
                                "Page \(appState.signaturePage)",
                                value: $appState.signaturePage,
                                in: 1...(appState.currentPDF?.pageCount ?? 1)
                            )
                            .font(SumiTypography.mono)
                        }
                    }

                    Divider()
                        .background(Color.stonegrey.opacity(0.3))

                    // Progress
                    if appState.isSigning {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("signing...")
                                .font(SumiTypography.mono)
                                .foregroundStyle(colorScheme == .dark ? Color.phosphorGreen : Color.terminalGreen)

                            ProgressView(value: appState.signatureProgress)
                                .tint(colorScheme == .dark ? Color.phosphorGreen : Color.terminalGreen)

                            Text("\(Int(appState.signatureProgress * 100))%")
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

                    // Sign button
                    Button(action: performSign) {
                        Text("[sign document]")
                            .font(SumiTypography.mono)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                    .background(
                        appState.currentSignatureImage != nil
                            ? (colorScheme == .dark ? Color.phosphorGreen : Color.terminalGreen)
                            : Color.stonegrey.opacity(0.3)
                    )
                    .foregroundStyle(
                        appState.currentSignatureImage != nil
                            ? Color.inkBlack
                            : Color.stonegrey
                    )
                    .cornerRadius(4)
                    .disabled(appState.isSigning || appState.currentPDF == nil || appState.currentSignatureImage == nil)
                }
            }
            .padding(20)
        }
    }

    @ViewBuilder
    private func positionButton(_ position: SignaturePosition) -> some View {
        Button(action: { appState.signaturePosition = position }) {
            Rectangle()
                .fill(
                    appState.signaturePosition == position
                        ? (colorScheme == .dark ? Color.phosphorGreen : Color.terminalGreen)
                        : Color.stonegrey.opacity(0.2)
                )
                .frame(width: 40, height: 30)
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(Color.stonegrey.opacity(0.5), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func importSignatureImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            if let image = NSImage(contentsOf: url) {
                appState.currentSignatureImage = image
            }
        }
    }

    private func performSign() {
        guard let url = appState.currentPDFURL,
              let signatureImage = appState.currentSignatureImage else { return }

        Task {
            appState.isSigning = true
            appState.signatureProgress = 0
            statusMessage = ""

            do {
                let options = SignatureOptions(
                    signatureImage: signatureImage,
                    position: appState.signaturePosition,
                    width: signatureWidth,
                    height: signatureHeight,
                    page: appState.signaturePage,
                    applyToAllPages: applyToAllPages
                )

                let result = try await appState.pdfToolsService.addSignature(
                    pdfURL: url,
                    options: options,
                    progressHandler: { progress in
                        Task { @MainActor in
                            appState.signatureProgress = progress
                        }
                    }
                )
                statusMessage = "✓ signed \(result.pagesModified) page(s) → \(result.outputURL.lastPathComponent)"
                isSuccess = true
            } catch {
                statusMessage = "✗ error: \(error.localizedDescription)"
                isSuccess = false
            }

            appState.isSigning = false
        }
    }
}

// MARK: - Signature Canvas

struct SignatureCanvasView: View {
    @Binding var path: Path
    @Environment(\.colorScheme) var colorScheme
    var onComplete: (NSImage) -> Void
    var onCancel: () -> Void

    @State private var currentPath = Path()
    @State private var paths: [Path] = []

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Rectangle()
                    .fill(Color.white)
                    .border(Color.stonegrey.opacity(0.5), width: 1)

                // Draw all paths
                ForEach(0..<paths.count, id: \.self) { index in
                    paths[index]
                        .stroke(Color.black, lineWidth: 2)
                }

                // Current path being drawn
                currentPath
                    .stroke(Color.black, lineWidth: 2)
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let point = value.location
                        if currentPath.isEmpty {
                            currentPath.move(to: point)
                        } else {
                            currentPath.addLine(to: point)
                        }
                    }
                    .onEnded { _ in
                        paths.append(currentPath)
                        currentPath = Path()
                    }
            )

            HStack {
                Button(action: {
                    paths = []
                    currentPath = Path()
                }) {
                    Text("[clear]")
                        .font(SumiTypography.monoSmall)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.stonegrey)

                Spacer()

                Button(action: onCancel) {
                    Text("[cancel]")
                        .font(SumiTypography.monoSmall)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.stonegrey)

                Button(action: saveSignature) {
                    Text("[save]")
                        .font(SumiTypography.monoSmall)
                }
                .buttonStyle(.plain)
                .foregroundStyle(colorScheme == .dark ? Color.phosphorGreen : Color.terminalGreen)
            }
        }
    }

    private func saveSignature() {
        // Create an image from the paths
        let size = NSSize(width: 300, height: 150)
        let image = NSImage(size: size)

        image.lockFocus()

        // White background
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()

        // Draw paths
        NSColor.black.setStroke()
        for path in paths {
            let bezierPath = NSBezierPath()
            bezierPath.lineWidth = 2

            path.forEach { element in
                switch element {
                case .move(to: let point):
                    bezierPath.move(to: point)
                case .line(to: let point):
                    bezierPath.line(to: point)
                case .quadCurve(to: let point, control: let control):
                    bezierPath.curve(to: point, controlPoint1: control, controlPoint2: control)
                case .curve(to: let point, control1: let c1, control2: let c2):
                    bezierPath.curve(to: point, controlPoint1: c1, controlPoint2: c2)
                case .closeSubpath:
                    bezierPath.close()
                }
            }

            bezierPath.stroke()
        }

        image.unlockFocus()

        onComplete(image)
    }
}
