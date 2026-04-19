//
//  SignatureCaptureView.swift
//  PDFHandler
//
//  Unified signature capture: Draw / Type / Image (paste + drop + file).
//  Produces a SignatureAsset which the caller saves into identity or uses directly.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

enum SignatureCaptureMode: String, CaseIterable, Identifiable {
    case draw, type, image
    var id: String { rawValue }

    var title: String {
        switch self {
        case .draw: return "Draw"
        case .type: return "Type"
        case .image: return "Image"
        }
    }

    var icon: String {
        switch self {
        case .draw: return "pencil.tip"
        case .type: return "textformat"
        case .image: return "photo.on.rectangle"
        }
    }
}

struct SignatureCaptureView: View {
    @Environment(\.colorScheme) var colorScheme

    /// Called when the user commits a captured signature.
    var onCapture: (SignatureAsset) -> Void

    @State private var mode: SignatureCaptureMode = .draw

    // Draw
    @State private var strokes: [Path] = []
    @State private var canvasSize: CGSize = .zero

    // Type
    @State private var typedName: String = ""
    @State private var typedStyle: SignatureFontStyle = .elegant

    // Image
    @State private var importedImage: NSImage?
    @State private var isTargetedForDrop = false
    @State private var removeBackground = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            modeTabs

            Group {
                switch mode {
                case .draw:  drawPane
                case .type:  typePane
                case .image: imagePane
                }
            }
            .frame(height: 180)

            HStack(spacing: 12) {
                Button(action: clear) {
                    Text("[clear]")
                        .font(SumiTypography.monoSmall)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.stonegrey)
                .disabled(!hasContent)

                Spacer()

                Button(action: commit) {
                    Text("[use signature]")
                        .font(SumiTypography.mono)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(accent.opacity(hasContent ? 1 : 0.25))
                        .foregroundStyle(hasContent ? Color.inkBlack : Color.stonegrey)
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!hasContent)
            }
        }
    }

    // MARK: Mode tabs

    private var modeTabs: some View {
        HStack(spacing: 4) {
            ForEach(SignatureCaptureMode.allCases) { m in
                Button(action: { mode = m }) {
                    HStack(spacing: 6) {
                        Image(systemName: m.icon)
                            .font(.system(size: 12))
                        Text(m.title)
                            .font(SumiTypography.mono)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(mode == m ? accent.opacity(0.15) : Color.clear)
                    .foregroundStyle(mode == m ? accent : Color.stonegrey)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(mode == m ? accent : Color.stonegrey.opacity(0.25), lineWidth: 1)
                    )
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Draw

    private var drawPane: some View {
        GeometryReader { geo in
            ZStack {
                Color.white
                ForEach(0..<strokes.count, id: \.self) { i in
                    strokes[i].stroke(Color.black, style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                }
                if strokes.isEmpty {
                    VStack(spacing: 4) {
                        Image(systemName: "hand.draw")
                            .font(.system(size: 20))
                            .foregroundStyle(Color.stonegrey)
                        Text("draw with mouse or trackpad")
                            .font(SumiTypography.monoSmall)
                            .foregroundStyle(Color.stonegrey)
                    }
                }

                // Baseline guide
                Path { p in
                    let y = geo.size.height * 0.75
                    p.move(to: CGPoint(x: 12, y: y))
                    p.addLine(to: CGPoint(x: geo.size.width - 12, y: y))
                }
                .stroke(Color.stonegrey.opacity(0.15), style: StrokeStyle(lineWidth: 0.5, dash: [3, 4]))
            }
            .onAppear { canvasSize = geo.size }
            .onChange(of: geo.size) { canvasSize = $0 }
            .contentShape(Rectangle())
            .gesture(drawGesture)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.mist, lineWidth: 1)
            )
        }
    }

    private var drawGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if strokes.isEmpty || isNewStrokeNeeded(at: value.startLocation) {
                    strokes.append(Path { $0.move(to: value.startLocation) })
                }
                strokes[strokes.count - 1].addLine(to: value.location)
            }
            .onEnded { _ in
                // Mark end of stroke by appending a sentinel empty path next drag.
                strokes.append(Path())
            }
    }

    private func isNewStrokeNeeded(at _: CGPoint) -> Bool {
        guard let last = strokes.last else { return true }
        return last.isEmpty
    }

    // MARK: Type

    private var typePane: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Your full name", text: $typedName)
                .font(SumiTypography.mono)
                .textFieldStyle(.plain)
                .padding(10)
                .background(Color.stonegrey.opacity(0.08))
                .cornerRadius(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(typedName.isEmpty ? Color.mist : accent, lineWidth: 1)
                )

            // Style chooser
            HStack(spacing: 8) {
                ForEach(SignatureFontStyle.allCases) { style in
                    Button(action: { typedStyle = style }) {
                        Text(typedName.isEmpty ? "Aa" : typedName)
                            .font(.custom(style.fontName, size: 22))
                            .foregroundStyle(Color.inkBlack)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(Color.white)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(typedStyle == style ? accent : Color.mist, lineWidth: typedStyle == style ? 2 : 1)
                            )
                            .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Image

    private var imagePane: some View {
        ZStack {
            if let img = importedImage {
                VStack(spacing: 10) {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(12)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.white)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.mist, lineWidth: 1)
                        )

                    Toggle(isOn: $removeBackground) {
                        Text("Remove white background")
                            .font(SumiTypography.monoSmall)
                    }
                    .toggleStyle(.checkbox)
                    .foregroundStyle(Color.stonegrey)
                }
            } else {
                VStack(spacing: 10) {
                    Image(systemName: isTargetedForDrop ? "tray.and.arrow.down.fill" : "photo.on.rectangle.angled")
                        .font(.system(size: 28))
                        .foregroundStyle(isTargetedForDrop ? accent : Color.stonegrey)

                    Text(isTargetedForDrop ? "drop to import" : "drop · paste (⌘V) · choose file")
                        .font(SumiTypography.monoSmall)
                        .foregroundStyle(Color.stonegrey)

                    HStack(spacing: 12) {
                        Button(action: pickImageFile) {
                            Text("[choose file]")
                                .font(SumiTypography.monoSmall)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(colorScheme == .dark ? .white : Color.inkBlack)

                        Button(action: pasteImageFromClipboard) {
                            Text("[paste]")
                                .font(SumiTypography.monoSmall)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(colorScheme == .dark ? .white : Color.inkBlack)
                        .keyboardShortcut("v", modifiers: .command)
                    }
                    .padding(.top, 4)

                    Text("Tip: photograph a signed paper on iPhone, copy, paste here.")
                        .font(SumiTypography.monoSmall)
                        .foregroundStyle(Color.stonegrey.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.stonegrey.opacity(isTargetedForDrop ? 0.12 : 0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(
                            isTargetedForDrop ? accent : Color.mist,
                            style: StrokeStyle(lineWidth: 1, dash: isTargetedForDrop ? [] : [6, 4])
                        )
                )
                .cornerRadius(6)
            }
        }
        .onDrop(of: [.image, .fileURL], isTargeted: $isTargetedForDrop, perform: handleDrop)
    }

    // MARK: Actions

    private var hasContent: Bool {
        switch mode {
        case .draw:  return strokes.contains { !$0.isEmpty }
        case .type:  return !typedName.trimmingCharacters(in: .whitespaces).isEmpty
        case .image: return importedImage != nil
        }
    }

    private func clear() {
        switch mode {
        case .draw:  strokes = []
        case .type:  typedName = ""
        case .image: importedImage = nil
        }
    }

    private func commit() {
        guard let asset = currentAsset() else { return }
        onCapture(asset)
        clear()
    }

    private func currentAsset() -> SignatureAsset? {
        switch mode {
        case .draw:
            guard let image = SignatureRenderer.renderStrokes(
                strokes.filter { !$0.isEmpty },
                canvasSize: canvasSize
            ) else { return nil }
            return SignatureRenderer.asset(source: .drawn, image: image)
        case .type:
            let trimmed = typedName.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }
            let image = SignatureRenderer.renderTyped(trimmed, style: typedStyle)
            return SignatureRenderer.asset(
                source: .typed,
                image: image,
                typedName: trimmed,
                typedStyle: typedStyle
            )
        case .image:
            guard let raw = importedImage else { return nil }
            let processed = removeBackground
                ? SignatureRenderer.removeWhiteBackground(raw)
                : raw
            return SignatureRenderer.asset(source: .image, image: processed)
        }
    }

    // MARK: Image sourcing

    private func pickImageFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .heic, .image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url, let image = NSImage(contentsOf: url) {
            importedImage = image
        }
    }

    private func pasteImageFromClipboard() {
        let pb = NSPasteboard.general
        if let image = NSImage(pasteboard: pb) {
            importedImage = image
            return
        }
        if let urlString = pb.string(forType: .fileURL),
           let url = URL(string: urlString),
           let image = NSImage(contentsOf: url) {
            importedImage = image
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        if provider.canLoadObject(ofClass: NSImage.self) {
            _ = provider.loadObject(ofClass: NSImage.self) { item, _ in
                if let image = item as? NSImage {
                    DispatchQueue.main.async { self.importedImage = image }
                }
            }
            return true
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                if let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil),
                   let image = NSImage(contentsOf: url) {
                    DispatchQueue.main.async { self.importedImage = image }
                } else if let url = item as? URL,
                          let image = NSImage(contentsOf: url) {
                    DispatchQueue.main.async { self.importedImage = image }
                }
            }
            return true
        }
        return false
    }

    private var accent: Color {
        colorScheme == .dark ? Color.phosphorGreen : Color.terminalGreen
    }
}
