//
//  QuickSignView.swift
//  PDFHandler
//
//  Simple, accessible signature view - type your name, get a cursive signature
//  Drag to position anywhere on the page
//

import SwiftUI
import PDFKit
import AppKit

struct QuickSignView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.colorScheme) var colorScheme
    @State private var statusMessage = ""
    @State private var isSuccess = false
    @State private var selectedPage: Int = 1
    @State private var signLastPage: Bool = true

    // Signature position as percentage of page (0.0 - 1.0)
    @State private var sigX: CGFloat = 0.65
    @State private var sigY: CGFloat = 0.85
    @State private var sigWidth: CGFloat = 200
    @State private var sigHeight: CGFloat = 70

    var body: some View {
        HStack(spacing: 0) {
            // Left: PDF page preview with draggable signature
            pagePreviewPanel
                .frame(minWidth: 350)

            Divider()

            // Right: Controls
            controlsPanel
                .frame(width: 300)
        }
    }

    // MARK: - Page Preview with Draggable Signature

    private var pagePreviewPanel: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Position your signature")
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(colorScheme == .dark ? .white : Color.inkBlack)
                Spacer()
                if let pdf = appState.currentPDF {
                    let pageNum = signLastPage ? pdf.pageCount : selectedPage
                    Text("Page \(pageNum) of \(pdf.pageCount)")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(Color.stonegrey)
                }
            }
            .padding(16)

            // PDF Page with signature overlay
            if let pdf = appState.currentPDF {
                let pageIndex = signLastPage ? pdf.pageCount - 1 : selectedPage - 1
                if let page = pdf.page(at: pageIndex) {
                    GeometryReader { geometry in
                        let pageImage = renderPageImage(page: page, targetSize: geometry.size)
                        let previewSize = calculatePreviewSize(pageBounds: page.bounds(for: .mediaBox), containerSize: geometry.size)

                        ZStack {
                            // PDF page image
                            if let image = pageImage {
                                Image(nsImage: image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: previewSize.width, height: previewSize.height)
                                    .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                            }

                            // Draggable signature overlay
                            if !appState.quickSignName.isEmpty {
                                signatureOverlay(previewSize: previewSize)
                            }
                        }
                        .frame(width: geometry.size.width, height: geometry.size.height)
                    }
                    .padding(16)
                } else {
                    noPageView
                }
            } else {
                noPageView
            }
        }
        .background(colorScheme == .dark ? Color.charcoal.opacity(0.5) : Color.stonegrey.opacity(0.05))
    }

    private func signatureOverlay(previewSize: CGSize) -> some View {
        let scaledWidth = sigWidth * previewSize.width / 612 // Scale relative to standard page
        let scaledHeight = sigHeight * previewSize.height / 792

        return VStack(spacing: 2) {
            Text(appState.quickSignName)
                .font(.custom(appState.quickSignFontStyle.fontName, size: min(scaledHeight * 0.6, 32)))
                .foregroundStyle(Color.black)
                .lineLimit(1)
                .minimumScaleFactor(0.5)

            if appState.quickSignIncludeDate {
                Text(formattedDate())
                    .font(.system(size: max(scaledHeight * 0.2, 8)))
                    .foregroundStyle(Color.gray)
            }
        }
        .frame(width: scaledWidth, height: scaledHeight)
        .background(Color.white.opacity(0.7))
        .border(Color.blue.opacity(0.6), width: 1)
        .overlay(
            // Resize handle
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 10))
                .foregroundStyle(Color.blue)
                .padding(3)
                .background(Color.white)
                .cornerRadius(2)
                .offset(x: 2, y: 2),
            alignment: .bottomTrailing
        )
        .position(
            x: sigX * previewSize.width,
            y: sigY * previewSize.height
        )
        .gesture(
            DragGesture()
                .onChanged { value in
                    // Update position based on drag, clamped to page bounds
                    let newX = value.location.x / previewSize.width
                    let newY = value.location.y / previewSize.height
                    sigX = max(0.05, min(0.95, newX))
                    sigY = max(0.05, min(0.95, newY))
                }
        )
    }

    private var noPageView: some View {
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
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(colorScheme == .dark ? Color.phosphorGreen : Color.terminalGreen)
                .foregroundStyle(Color.inkBlack)
                .cornerRadius(10)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Controls Panel

    private var controlsPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("Quick Sign")
                        .font(.system(size: 24, weight: .medium, design: .rounded))
                        .foregroundStyle(colorScheme == .dark ? .white : Color.inkBlack)
                    Text("Type, position, sign")
                        .font(.system(size: 14, design: .rounded))
                        .foregroundStyle(Color.stonegrey)
                }

                // File info
                if let url = appState.currentPDFURL {
                    HStack {
                        Image(systemName: "doc.fill")
                            .foregroundStyle(colorScheme == .dark ? Color.phosphorGreen : Color.terminalGreen)
                        Text(url.lastPathComponent)
                            .font(.system(size: 13, design: .rounded))
                            .lineLimit(1)
                        Spacer()
                        Button(action: { appState.showFilePicker = true }) {
                            Text("Change")
                                .font(.system(size: 12, design: .rounded))
                                .foregroundStyle(colorScheme == .dark ? Color.phosphorGreen : Color.terminalGreen)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(10)
                    .background(Color.stonegrey.opacity(0.1))
                    .cornerRadius(8)
                }

                Divider()

                // Name input
                VStack(alignment: .leading, spacing: 8) {
                    Label("Your name", systemImage: "keyboard")
                        .font(.system(size: 15, weight: .medium, design: .rounded))

                    TextField("Full name", text: $appState.quickSignName)
                        .font(.system(size: 18, design: .rounded))
                        .textFieldStyle(.plain)
                        .padding(14)
                        .background(Color.stonegrey.opacity(0.1))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(
                                    appState.quickSignName.isEmpty
                                        ? Color.stonegrey.opacity(0.3)
                                        : (colorScheme == .dark ? Color.phosphorGreen : Color.terminalGreen),
                                    lineWidth: 1.5
                                )
                        )
                }

                // Font style
                if !appState.quickSignName.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Style", systemImage: "textformat")
                            .font(.system(size: 15, weight: .medium, design: .rounded))

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            ForEach(SignatureFontStyle.allCases) { style in
                                Button(action: { appState.quickSignFontStyle = style }) {
                                    VStack(spacing: 4) {
                                        Text("Aa")
                                            .font(.custom(style.fontName, size: 20))
                                            .foregroundStyle(Color.inkBlack)
                                            .frame(height: 26)
                                        Text(style.displayName)
                                            .font(.system(size: 11, design: .rounded))
                                            .foregroundStyle(
                                                appState.quickSignFontStyle == style
                                                    ? (colorScheme == .dark ? Color.phosphorGreen : Color.terminalGreen)
                                                    : Color.stonegrey
                                            )
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(
                                        appState.quickSignFontStyle == style
                                            ? (colorScheme == .dark ? Color.phosphorGreen : Color.terminalGreen).opacity(0.15)
                                            : Color.stonegrey.opacity(0.1)
                                    )
                                    .cornerRadius(8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(
                                                appState.quickSignFontStyle == style
                                                    ? (colorScheme == .dark ? Color.phosphorGreen : Color.terminalGreen)
                                                    : Color.clear,
                                                lineWidth: 1.5
                                            )
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    Divider()

                    // Signature size
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Size", systemImage: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 15, weight: .medium, design: .rounded))

                        HStack {
                            Text("Width")
                                .font(.system(size: 13, design: .rounded))
                                .foregroundStyle(Color.stonegrey)
                                .frame(width: 45, alignment: .leading)
                            Slider(value: $sigWidth, in: 80...400, step: 10)
                                .tint(colorScheme == .dark ? Color.phosphorGreen : Color.terminalGreen)
                            Text("\(Int(sigWidth))")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(Color.stonegrey)
                                .frame(width: 30)
                        }

                        HStack {
                            Text("Height")
                                .font(.system(size: 13, design: .rounded))
                                .foregroundStyle(Color.stonegrey)
                                .frame(width: 45, alignment: .leading)
                            Slider(value: $sigHeight, in: 30...200, step: 5)
                                .tint(colorScheme == .dark ? Color.phosphorGreen : Color.terminalGreen)
                            Text("\(Int(sigHeight))")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(Color.stonegrey)
                                .frame(width: 30)
                        }
                    }

                    Divider()

                    // Options
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle(isOn: $appState.quickSignIncludeDate) {
                            HStack(spacing: 8) {
                                Image(systemName: "calendar")
                                Text("Include date")
                                    .font(.system(size: 14, design: .rounded))
                            }
                        }
                        .toggleStyle(.checkbox)

                        // Page selection
                        if let pdf = appState.currentPDF, pdf.pageCount > 1 {
                            Toggle(isOn: $signLastPage) {
                                HStack(spacing: 8) {
                                    Image(systemName: "doc.on.doc")
                                    Text("Sign last page")
                                        .font(.system(size: 14, design: .rounded))
                                }
                            }
                            .toggleStyle(.checkbox)

                            if !signLastPage {
                                Picker("Page", selection: $selectedPage) {
                                    ForEach(1...pdf.pageCount, id: \.self) { page in
                                        Text("Page \(page)").tag(page)
                                    }
                                }
                                .pickerStyle(.menu)
                            }
                        }
                    }

                    Divider()

                    // Progress
                    if appState.isQuickSigning {
                        VStack(spacing: 8) {
                            ProgressView(value: appState.quickSignProgress)
                                .tint(colorScheme == .dark ? Color.phosphorGreen : Color.terminalGreen)
                            Text("Signing...")
                                .font(.system(size: 14, design: .rounded))
                                .foregroundStyle(Color.stonegrey)
                        }
                    }

                    // Status
                    if !statusMessage.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: isSuccess ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            Text(statusMessage)
                                .font(.system(size: 14, design: .rounded))
                        }
                        .foregroundStyle(isSuccess ? (colorScheme == .dark ? Color.phosphorGreen : Color.terminalGreen) : Color.red)
                    }

                    // Sign button
                    Button(action: performQuickSign) {
                        HStack(spacing: 10) {
                            Image(systemName: "signature")
                                .font(.system(size: 20))
                            Text("Sign Document")
                                .font(.system(size: 18, weight: .semibold, design: .rounded))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            canSign
                                ? (colorScheme == .dark ? Color.phosphorGreen : Color.terminalGreen)
                                : Color.stonegrey.opacity(0.3)
                        )
                        .foregroundStyle(canSign ? Color.inkBlack : Color.stonegrey)
                        .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSign || appState.isQuickSigning)
                }
            }
            .padding(20)
        }
        .background(colorScheme == .dark ? Color.charcoal : Color.paperBackground)
    }

    // MARK: - Helpers

    private var canSign: Bool {
        appState.currentPDF != nil && !appState.quickSignName.isEmpty
    }

    private func formattedDate() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        return formatter.string(from: Date())
    }

    private func renderPageImage(page: PDFPage, targetSize: CGSize) -> NSImage? {
        let pageBounds = page.bounds(for: .mediaBox)
        let scale = min(targetSize.width / pageBounds.width, targetSize.height / pageBounds.height) * 0.9
        let imageSize = NSSize(width: pageBounds.width * scale, height: pageBounds.height * scale)

        let image = NSImage(size: imageSize)
        image.lockFocus()

        if let context = NSGraphicsContext.current?.cgContext {
            // White background
            context.setFillColor(NSColor.white.cgColor)
            context.fill(CGRect(origin: .zero, size: imageSize))

            // Scale and draw the page
            context.scaleBy(x: scale, y: scale)
            page.draw(with: .mediaBox, to: context)
        }

        image.unlockFocus()
        return image
    }

    private func calculatePreviewSize(pageBounds: CGRect, containerSize: CGSize) -> CGSize {
        let scale = min(containerSize.width / pageBounds.width, containerSize.height / pageBounds.height) * 0.9
        return CGSize(width: pageBounds.width * scale, height: pageBounds.height * scale)
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
                let signatureImage = createSignatureImage(
                    name: appState.quickSignName,
                    style: appState.quickSignFontStyle,
                    includeDate: appState.quickSignIncludeDate
                )

                appState.quickSignProgress = 0.3

                let pageToSign = signLastPage ? pdf.pageCount : selectedPage
                let page = pdf.page(at: pageToSign - 1)
                let pageBounds = page?.bounds(for: .mediaBox) ?? CGRect(x: 0, y: 0, width: 612, height: 792)

                // Convert percentage position to PDF coordinates
                // PDF origin is bottom-left, SwiftUI origin is top-left
                let pdfX = sigX * pageBounds.width - sigWidth / 2
                let pdfY = (1.0 - sigY) * pageBounds.height - sigHeight / 2

                let options = SignatureOptions(
                    signatureImage: signatureImage,
                    position: .custom,
                    customX: pdfX,
                    customY: pdfY,
                    width: sigWidth,
                    height: sigHeight,
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

                statusMessage = "Signed!"
                isSuccess = true

                NSWorkspace.shared.selectFile(result.outputURL.path, inFileViewerRootedAtPath: result.outputURL.deletingLastPathComponent().path)

            } catch {
                statusMessage = "Failed: \(error.localizedDescription)"
                isSuccess = false
            }

            appState.isQuickSigning = false
            appState.quickSignProgress = 1.0
        }
    }

    private func createSignatureImage(name: String, style: SignatureFontStyle, includeDate: Bool) -> NSImage {
        let font = NSFont(name: style.fontName, size: style.fontSize) ?? NSFont.systemFont(ofSize: style.fontSize)
        let dateFont = NSFont.systemFont(ofSize: 12)

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

        NSColor.clear.setFill()
        NSRect(origin: .zero, size: size).fill()

        let nameRect = NSRect(
            x: (size.width - nameSize.width) / 2,
            y: includeDate ? (dateSize.height + 16) : 10,
            width: nameSize.width,
            height: nameSize.height
        )
        (name as NSString).draw(in: nameRect, withAttributes: nameAttributes)

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
        .frame(width: 800, height: 600)
}
