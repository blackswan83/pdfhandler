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
    /// For Import / Paste modes: knock out near-white pixels so a
    /// scanned signature drops onto the PDF without an opaque card.
    @State private var removeWhiteBackground: Bool = true

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
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 180, height: 60)
                        .padding(6)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.gray.opacity(0.4), lineWidth: 1)
                        )
                } else {
                    Text("No \(appState.newSignatureRole.displayName.lowercased()) yet.")
                        .foregroundStyle(.secondary)
                        .frame(width: 180, alignment: .leading)
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
            Toggle("Remove white background automatically", isOn: $removeWhiteBackground)
                .font(.caption)
            Text("PNG, JPEG or TIFF. Toggle on (default) to chroma-key the white out of scanned signatures.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func openImagePicker() {
        let panel = NSOpenPanel()
        panel.title = "Choose image"
        panel.allowedContentTypes = [.png, .jpeg, .tiff]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url, let image = NSImage(contentsOf: url) {
            candidateImage = image
            if name.isEmpty { name = url.deletingPathExtension().lastPathComponent }
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

            Toggle("Remove white background automatically", isOn: $removeWhiteBackground)
                .font(.caption)
            Text("Copy any image (Preview, Photos, Mail, Screenshot), then click here (or press ⌘V).")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func pasteFromClipboard() {
        if let image = NSImage(pasteboard: NSPasteboard.general) {
            candidateImage = image
            statusMessage = "Pasted image from clipboard."
        } else {
            statusMessage = "Clipboard does not contain an image."
        }
    }

    // MARK: - Save

    private func save() {
        guard let image = candidateImage else { return }
        // For Import / Paste modes, knock out white background when
        // requested. Type / Draw already render onto a transparent
        // canvas so they need no post-processing.
        let needsKnockout = (inputMode == .upload || inputMode == .paste) && removeWhiteBackground
        let finalImage = needsKnockout
            ? (image.knockingOutWhiteBackground() ?? image)
            : image
        appState.addSignature(image: finalImage, name: name, role: appState.newSignatureRole)
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

        // Same trick as SignatureCanvasView.render: draw into an
        // explicit RGBA CGContext so the glyphs land on a guaranteed-
        // transparent bitmap. NSImage(size:).lockFocus() can hand back
        // an opaque RGB rep that quietly produces white-boxed PNGs.
        let width  = Int(padded.width)
        let height = Int(padded.height)
        if width > 0, height > 0,
           let cs = CGColorSpace(name: CGColorSpace.sRGB),
           let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
           ) {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
            (text as NSString).draw(at: NSPoint(x: 20, y: 10), withAttributes: attrs)
            NSGraphicsContext.restoreGraphicsState()
            if let cgImage = ctx.makeImage() {
                return NSImage(cgImage: cgImage, size: padded)
            }
        }
        // Fallback (shouldn't hit unless CG init failed): the old
        // lockFocus path, may produce opaque background.
        let image = NSImage(size: padded)
        image.lockFocus()
        (text as NSString).draw(at: NSPoint(x: 20, y: 10), withAttributes: attrs)
        image.unlockFocus()
        return image
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
