//
//  NewSignatureView.swift
//  PDFHandler
//
//  Modal sheet for creating a new library entry. Four input methods
//  (Type / Draw / Import / Paste) and a role toggle (Signature vs
//  Initials) chosen by the sidebar before opening this sheet.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct NewSignatureView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    enum InputMode: String, CaseIterable, Identifiable {
        case type, draw, upload, paste
        var id: String { rawValue }
        var label: String {
            switch self {
            case .type:   return "Type"
            case .draw:   return "Draw"
            case .upload: return "Import"
            case .paste:  return "Paste"
            }
        }
        var systemImage: String {
            switch self {
            case .type:   return "character.cursor.ibeam"
            case .draw:   return "pencil.tip"
            case .upload: return "square.and.arrow.up"
            case .paste:  return "doc.on.clipboard"
            }
        }
    }

    @State private var inputMode: InputMode = .type
    @State private var name: String = ""
    @State private var typedText: String = ""
    @State private var typedFont: TypedFont = .elegant
    @State private var candidateImage: NSImage?
    @State private var statusMessage: String?
    @State private var showCanvas = false
    /// For Import / Paste: the untouched original, kept so the ink
    /// extraction can be re-run at a different sensitivity without
    /// compounding on its own output.
    @State private var originalImage: NSImage?
    @State private var isolateInk: Bool = true
    @State private var inkSensitivity: Double = 0.5
    @State private var extractionTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New \(appState.newSignatureRole.displayName.lowercased())")
                .font(.title2.bold())

            Picker("", selection: $inputMode) {
                ForEach(InputMode.allCases) { m in
                    Label(m.label, systemImage: m.systemImage).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Divider()

            Group {
                switch inputMode {
                case .type:   typeEditor
                case .draw:   drawEditor
                case .upload: uploadEditor
                case .paste:  pasteEditor
                }
            }

            Divider()

            HStack(alignment: .center, spacing: 12) {
                if let image = candidateImage {
                    // Previewed over a ruled line, which is the whole
                    // point: it shows at a glance whether the
                    // background is genuinely transparent or just white.
                    SignaturePreview(image: image)
                } else {
                    Text("No \(appState.newSignatureRole.displayName.lowercased()) yet.")
                        .foregroundStyle(.secondary)
                        .frame(width: 220, alignment: .leading)
                }

                VStack(alignment: .leading, spacing: 8) {
                    TextField("Name (optional)", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 240)
                    if let status = statusMessage {
                        Text(status)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Add to library") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(candidateImage == nil)
            }
        }
        .padding(24)
        .frame(width: 620)
        .onChange(of: typedText) { _ in renderTyped() }
        .onChange(of: typedFont) { _ in renderTyped() }
    }

    // MARK: - Type

    private var typeEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField(appState.newSignatureRole == .initials ? "Your initials (e.g. JD)" : "Your name",
                      text: $typedText)
                .textFieldStyle(.roundedBorder)
                .font(.title3)
            HStack(spacing: 10) {
                ForEach(TypedFont.allCases) { font in
                    Button {
                        typedFont = font
                    } label: {
                        Text("Aa")
                            .font(.custom(font.fontName, size: 22))
                            .frame(width: 56, height: 36)
                            .background(typedFont == font ? Color.accentColor.opacity(0.15) : Color.gray.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(typedFont == font ? Color.accentColor : Color.clear, lineWidth: 1.5)
                            )
                            .foregroundStyle(Color.black)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
        }
    }

    private func renderTyped() {
        let trimmed = typedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { candidateImage = nil; return }
        candidateImage = Self.renderTypedSignature(trimmed, font: typedFont)
    }

    // MARK: - Draw

    private var drawEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                showCanvas = true
            } label: {
                Label("Open drawing canvas", systemImage: "pencil.tip")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .background(Color.gray.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        }
        .sheet(isPresented: $showCanvas) {
            SignatureCanvasView(
                onComplete: { image in
                    candidateImage = image
                    showCanvas = false
                },
                onCancel: { showCanvas = false }
            )
        }
    }

    // MARK: - Upload

    private var uploadEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                openImagePicker()
            } label: {
                Label("Choose image file…", systemImage: "folder")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .background(Color.gray.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            inkControls
            Text("PNG, JPEG, TIFF or HEIC — a photo of a signature on paper works.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Ink isolation controls, shared by Import and Paste.
    @ViewBuilder
    private var inkControls: some View {
        Toggle("Isolate ink from the paper", isOn: $isolateInk)
            .font(.caption)
            .onChange(of: isolateInk) { _ in reextract() }

        if isolateInk {
            // Low sensitivity keeps only strong strokes ("Clean");
            // high sensitivity admits fainter ink at the cost of some
            // paper texture. Labels match the ends of the value range.
            HStack(spacing: 8) {
                Text("Clean")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Slider(value: $inkSensitivity, in: 0...1)
                    .frame(maxWidth: 200)
                    .onChange(of: inkSensitivity) { _ in reextract() }
                Text("Faint ink")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text("Estimates the paper brightness locally, so shadows and uneven lighting are handled. Slide right to catch faint strokes, left to reject paper texture.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Re-runs extraction from the pristine original. Cancels any run
    /// still in flight so dragging the slider does not queue work.
    private func reextract() {
        guard let original = originalImage else { return }
        extractionTask?.cancel()
        guard isolateInk else {
            candidateImage = original
            statusMessage = "Using the image as-is."
            return
        }
        let options = SignatureExtractor.Options(sensitivity: inkSensitivity)
        // NSImage cannot cross an actor boundary, so the conversion
        // happens here and only the Sendable raster is handed off.
        guard let input = SignatureExtractor.raster(from: original, maxDimension: options.maxDimension) else {
            candidateImage = original
            statusMessage = "Could not read that image."
            return
        }

        statusMessage = "Isolating ink…"
        extractionTask = Task {
            let output = await Task.detached(priority: .userInitiated) {
                SignatureExtractor.extract(input, options: options)
            }.value
            if Task.isCancelled { return }
            if let output, let extracted = SignatureExtractor.image(from: output) {
                candidateImage = extracted
                statusMessage = "Ink isolated onto a transparent background."
            } else {
                candidateImage = original
                statusMessage = "No clear ink found — using the image as-is."
            }
        }
    }

    private func openImagePicker() {
        let panel = NSOpenPanel()
        panel.title = "Choose image"
        // HEIC included: photographing a signature with an iPhone is
        // the expected route, and that is what it produces.
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .heic, .image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url, let image = NSImage(contentsOf: url) {
            originalImage = image
            candidateImage = image
            if name.isEmpty { name = url.deletingPathExtension().lastPathComponent }
            reextract()
        }
    }

    // MARK: - Paste

    private var pasteEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                pasteFromClipboard()
            } label: {
                Label("Paste from clipboard", systemImage: "doc.on.clipboard")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .background(Color.gray.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .keyboardShortcut("v", modifiers: .command)

            inkControls
            Text("Copy any image (Preview, Photos, Mail, Screenshot), then click here (or press ⌘V).")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func pasteFromClipboard() {
        if let image = NSImage(pasteboard: NSPasteboard.general) {
            originalImage = image
            candidateImage = image
            statusMessage = "Pasted image from clipboard."
            reextract()
        } else {
            statusMessage = "Clipboard does not contain an image."
        }
    }

    // MARK: - Save

    private func save() {
        // candidateImage already carries the extraction result — what
        // is previewed is exactly what is saved, so the preview cannot
        // disagree with the stored asset.
        guard let image = candidateImage else { return }
        appState.addSignature(image: image, name: name, role: appState.newSignatureRole)
        dismiss()
    }

    // MARK: - Typed signature rendering

    static func renderTypedSignature(_ text: String, font: TypedFont) -> NSImage {
        let ns = NSFont(name: font.fontName, size: font.pointSize) ?? NSFont.systemFont(ofSize: font.pointSize)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: ns,
            .foregroundColor: NSColor.black
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        let padded = NSSize(width: size.width + 40, height: size.height + 20)
        let image = NSImage(size: padded)
        image.lockFocus()
        // No background fill — glyphs paint onto a transparent canvas so
        // the rendered signature drops cleanly onto document content.
        (text as NSString).draw(at: NSPoint(x: 20, y: 10), withAttributes: attrs)
        image.unlockFocus()
        return image
    }
}

/// Shows a candidate signature over a ruled line and body text, which
/// is the only way to tell an isolated signature from one still
/// sitting on a white card — against a plain background they look
/// identical.
private struct SignaturePreview: View {
    let image: NSImage

    var body: some View {
        ZStack {
            Rectangle().fill(Color.white)
            VStack(alignment: .leading, spacing: 5) {
                Spacer()
                ForEach(0..<2, id: \.self) { _ in
                    Rectangle()
                        .fill(Color.black.opacity(0.30))
                        .frame(height: 1.5)
                        .padding(.trailing, 30)
                }
                Rectangle()
                    .fill(Color.black.opacity(0.55))
                    .frame(height: 1)
                Spacer()
            }
            .padding(.horizontal, 10)

            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .padding(6)
        }
        .frame(width: 220, height: 74)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.gray.opacity(0.4), lineWidth: 1)
        )
    }
}

enum TypedFont: String, CaseIterable, Identifiable, Codable {
    case elegant, classic, casual, marker

    var id: String { rawValue }

    var fontName: String {
        switch self {
        case .elegant: return "Snell Roundhand"
        case .classic: return "Brush Script MT"
        case .casual:  return "Bradley Hand"
        case .marker:  return "Marker Felt"
        }
    }

    var pointSize: CGFloat {
        switch self {
        case .elegant: return 56
        case .classic: return 52
        case .casual:  return 46
        case .marker:  return 44
        }
    }
}
