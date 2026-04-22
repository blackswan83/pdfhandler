//
//  SignView.swift
//  PDFHandler
//
//  View for adding signatures to PDFs. Accepts signatures via drawing,
//  file import, clipboard paste, drag-and-drop, or a persistent library
//  of previously-saved signatures (separate roles for full signature
//  vs. initials, per DocuSign convention).
//

import SwiftUI
import PDFKit
import AppKit
import UniformTypeIdentifiers

struct SignOptionsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.colorScheme) var colorScheme

    @State private var signatureWidth: Double = 150
    @State private var signatureHeight: Double = 50
    @State private var applyToAllPages = false
    @State private var statusMessage = ""
    @State private var isSuccess = false
    @State private var isDrawing = false
    @State private var drawingPath = Path()
    @State private var isDropTargeted = false
    @State private var pendingSaveName: String = ""
    @State private var showSaveNameSheet = false

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

                    Divider().background(Color.stonegrey.opacity(0.3))

                    roleSection
                    librarySection
                    inputMethodsSection
                    previewSection

                    if isDrawing {
                        drawingSection
                    }

                    Divider().background(Color.stonegrey.opacity(0.3))

                    // Position selection
                    VStack(alignment: .leading, spacing: 12) {
                        Text("--position")
                            .font(SumiTypography.mono)
                            .foregroundStyle(colorScheme == .dark ? .white : Color.inkBlack)

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

                    Divider().background(Color.stonegrey.opacity(0.3))

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

                    Divider().background(Color.stonegrey.opacity(0.3))

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

                    Divider().background(Color.stonegrey.opacity(0.3))

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

                    if !statusMessage.isEmpty {
                        Text(statusMessage)
                            .font(SumiTypography.monoSmall)
                            .foregroundStyle(isSuccess ? (colorScheme == .dark ? Color.phosphorGreen : Color.terminalGreen) : Color.red)
                    }

                    Spacer()

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
                    .foregroundStyle(appState.currentSignatureImage != nil ? Color.inkBlack : Color.stonegrey)
                    .cornerRadius(4)
                    .disabled(appState.isSigning || appState.currentPDF == nil || appState.currentSignatureImage == nil)
                }
            }
            .padding(20)
        }
        // Accept images dropped anywhere on the sign pane.
        .onDrop(of: [.image, .fileURL], isTargeted: $isDropTargeted, perform: handleDrop)
        .overlay(dropOverlay)
        .sheet(isPresented: $showSaveNameSheet) { saveNameSheet() }
    }

    // MARK: - Role toggle (Signature vs Initials)

    private var roleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("--role")
                .font(SumiTypography.mono)
                .foregroundStyle(colorScheme == .dark ? .white : Color.inkBlack)

            Picker("", selection: $appState.signatureRole) {
                ForEach(SavedSignatureRole.allCases, id: \.self) { role in
                    Text(role.displayName).tag(role)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    // MARK: - Saved signature library

    private var librarySection: some View {
        let entries = appState.signatures(for: appState.signatureRole)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("--library")
                    .font(SumiTypography.mono)
                    .foregroundStyle(colorScheme == .dark ? .white : Color.inkBlack)
                Spacer()
                Text("\(entries.count) saved")
                    .font(SumiTypography.monoSmall)
                    .foregroundStyle(Color.stonegrey)
            }

            if entries.isEmpty {
                Text("No saved \(appState.signatureRole.displayName.lowercased())s yet.")
                    .font(SumiTypography.monoSmall)
                    .foregroundStyle(Color.stonegrey)
                    .padding(.vertical, 8)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(entries) { entry in
                            libraryThumb(entry)
                        }
                    }
                }
                .frame(height: 86)
            }
        }
    }

    private func libraryThumb(_ entry: SavedSignature) -> some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                Button(action: { useSavedSignature(entry) }) {
                    thumbImage(for: entry)
                }
                .buttonStyle(.plain)

                Button(action: { appState.deleteSignature(entry) }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.red.opacity(0.8))
                        .background(Circle().fill(Color.white))
                }
                .buttonStyle(.plain)
                .offset(x: 4, y: -4)
            }

            thumbLabel(for: entry)
        }
    }

    @ViewBuilder
    private func thumbImage(for entry: SavedSignature) -> some View {
        if let image = entry.image {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 120, height: 44)
                .padding(4)
                .background(Color.white)
                .cornerRadius(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.stonegrey.opacity(0.3), lineWidth: 1)
                )
        } else {
            Color.gray.opacity(0.2)
                .frame(width: 120, height: 44)
                .cornerRadius(4)
        }
    }

    @ViewBuilder
    private func thumbLabel(for entry: SavedSignature) -> some View {
        HStack(spacing: 4) {
            if entry.isDefault {
                Image(systemName: "star.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(Color.yellow)
            } else {
                Button(action: { appState.setDefaultSignature(entry) }) {
                    Image(systemName: "star")
                        .font(.system(size: 8))
                        .foregroundStyle(Color.stonegrey)
                }
                .buttonStyle(.plain)
            }
            Text(entry.name)
                .font(SumiTypography.monoSmall)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(Color.stonegrey)
                .frame(maxWidth: 100)
        }
    }

    // MARK: - Input methods (Draw / Import / Paste)

    private var inputMethodsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("--signature")
                .font(SumiTypography.mono)
                .foregroundStyle(colorScheme == .dark ? .white : Color.inkBlack)

            HStack(spacing: 12) {
                inputTile(icon: "pencil.tip", label: "Draw", action: { isDrawing = true })
                inputTile(icon: "photo", label: "Import", action: importSignatureImage)
                inputTile(icon: "doc.on.clipboard", label: "Paste", action: pasteFromClipboard)
                    .keyboardShortcut("v", modifiers: .command)
                    .disabled(!canPaste)
                    .opacity(canPaste ? 1.0 : 0.45)
            }

            Text("Tip: ⌘V to paste, or drag an image onto this pane.")
                .font(SumiTypography.monoSmall)
                .foregroundStyle(Color.stonegrey)
        }
    }

    private func inputTile(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 20))
                Text(label).font(SumiTypography.monoSmall)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.stonegrey.opacity(0.1))
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .foregroundStyle(colorScheme == .dark ? .white : Color.inkBlack)
    }

    // MARK: - Current signature preview + save to library

    @ViewBuilder
    private var previewSection: some View {
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

                    VStack(alignment: .trailing, spacing: 6) {
                        Button(action: openSaveNameSheet) {
                            Text("[save to library]")
                                .font(SumiTypography.monoSmall)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(colorScheme == .dark ? Color.phosphorGreen : Color.terminalGreen)

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
    }

    // MARK: - Drawing canvas (with ink color)

    private var drawingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Draw your signature:")
                    .font(SumiTypography.monoSmall)
                    .foregroundStyle(Color.stonegrey)
                Spacer()
                ForEach(SignatureInkColor.allCases) { color in
                    inkSwatch(color)
                }
            }

            SignatureCanvasView(
                path: $drawingPath,
                inkColor: appState.signatureInkColor,
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

    private func inkSwatch(_ color: SignatureInkColor) -> some View {
        Button(action: { appState.signatureInkColor = color }) {
            Circle()
                .fill(Color(nsColor: color.nsColor))
                .frame(width: 18, height: 18)
                .overlay(
                    Circle().stroke(
                        appState.signatureInkColor == color
                            ? (colorScheme == .dark ? Color.phosphorGreen : Color.terminalGreen)
                            : Color.stonegrey.opacity(0.5),
                        lineWidth: appState.signatureInkColor == color ? 2 : 1
                    )
                )
        }
        .buttonStyle(.plain)
        .help(color.displayName)
    }

    // MARK: - Drop feedback overlay

    @ViewBuilder
    private var dropOverlay: some View {
        if isDropTargeted {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.blue.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.blue.opacity(0.6), style: StrokeStyle(lineWidth: 2, dash: [6]))
                )
                .allowsHitTesting(false)
                .padding(6)
        }
    }

    // MARK: - Save-to-library sheet

    private func saveNameSheet() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Save \(appState.signatureRole.displayName.lowercased()) to library")
                .font(SumiTypography.mono)
            TextField("Name", text: $pendingSaveName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 260)
            HStack {
                Spacer()
                Button("Cancel") { showSaveNameSheet = false }
                Button("Save") {
                    if let image = appState.currentSignatureImage {
                        appState.saveSignature(
                            image: image,
                            name: pendingSaveName,
                            role: appState.signatureRole
                        )
                    }
                    showSaveNameSheet = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
    }

    private func openSaveNameSheet() {
        pendingSaveName = ""
        showSaveNameSheet = true
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

    // MARK: - Input actions

    private var canPaste: Bool {
        NSImage(pasteboard: NSPasteboard.general) != nil
    }

    private func pasteFromClipboard() {
        if let image = NSImage(pasteboard: NSPasteboard.general) {
            appState.currentSignatureImage = image
            statusMessage = "Pasted signature from clipboard"
            isSuccess = true
            return
        }
        statusMessage = "Clipboard does not contain an image"
        isSuccess = false
    }

    private func importSignatureImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url, let image = NSImage(contentsOf: url) {
            appState.currentSignatureImage = image
        }
    }

    private func useSavedSignature(_ entry: SavedSignature) {
        if let image = entry.image {
            appState.currentSignatureImage = image
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.canLoadObject(ofClass: NSImage.self) {
                provider.loadObject(ofClass: NSImage.self) { object, _ in
                    if let image = object as? NSImage {
                        Task { @MainActor in
                            appState.currentSignatureImage = image
                        }
                    }
                }
                return true
            }
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
                    if let data = data as? Data,
                       let url = URL(dataRepresentation: data, relativeTo: nil),
                       let image = NSImage(contentsOf: url) {
                        Task { @MainActor in
                            appState.currentSignatureImage = image
                        }
                    }
                }
                return true
            }
        }
        return false
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
    var inkColor: SignatureInkColor = .black
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

                ForEach(0..<paths.count, id: \.self) { index in
                    paths[index]
                        .stroke(Color(nsColor: inkColor.nsColor), lineWidth: 2)
                }

                currentPath
                    .stroke(Color(nsColor: inkColor.nsColor), lineWidth: 2)
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
        let size = NSSize(width: 300, height: 150)
        let image = NSImage(size: size)

        image.lockFocus()

        NSColor.clear.setFill()
        NSRect(origin: .zero, size: size).fill()

        inkColor.nsColor.setStroke()
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
