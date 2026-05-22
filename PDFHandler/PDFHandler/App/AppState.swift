//
//  AppState.swift
//  PDFHandler
//
//  Central observable state. Tracks which mode the user is in
//  (Sign / Compress / Merge / Convert), the currently-open PDF, the
//  persistent signature + initials library, the active field tool
//  and its placements, and per-mode progress / result state for
//  the three batch features.
//

import Foundation
import SwiftUI
import PDFKit
import AppKit

// MARK: - Mode

enum AppMode: String, CaseIterable, Identifiable, Hashable {
    case sign, compress, merge, convert
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sign:     return "Sign"
        case .compress: return "Compress"
        case .merge:    return "Merge"
        case .convert:  return "To Markdown"
        }
    }

    var systemImage: String {
        switch self {
        case .sign:     return "signature"
        case .compress: return "arrow.down.circle"
        case .merge:    return "doc.on.doc"
        case .convert:  return "doc.richtext"
        }
    }
}

// MARK: - App State

@MainActor
final class AppState: ObservableObject {

    // MARK: Navigation
    @Published var mode: AppMode = .sign

    // MARK: PDF (Sign mode)
    @Published var documentURL: URL?
    @Published var document: PDFDocument?
    @Published var currentPageIndex: Int = 0

    // MARK: Signature library (Sign mode)
    @Published private(set) var signatures: [SavedSignature] = []
    @Published var activeSignatureID: UUID?
    @Published var activeInitialsID: UUID?
    @Published var isPresentingNewSignature = false
    /// The role a new library entry will be saved under when the
    /// "Add" sheet is dismissed.
    @Published var newSignatureRole: SavedSignatureRole = .signature

    // MARK: Placements (Sign mode)
    @Published var placements: [Placement] = []
    @Published var activeTool: FieldTool = .signature
    @Published var selectedPlacementID: UUID?

    // MARK: Remembered placement sizes (persisted across launches)
    // Normalized 0…1 against page bounds. Width is enough for image-
    // backed kinds (height is derived from the asset's aspect ratio
    // and the page aspect). Date / freeText / checkbox store both.
    @AppStorage("lastSize.signature.w") private var lastSizeSignatureW: Double = 0.25
    @AppStorage("lastSize.initials.w")  private var lastSizeInitialsW:  Double = 0.12
    @AppStorage("lastSize.date.w")      private var lastSizeDateW:      Double = 0.20
    @AppStorage("lastSize.date.h")      private var lastSizeDateH:      Double = 0.035
    @AppStorage("lastSize.freeText.w")  private var lastSizeFreeTextW:  Double = 0.22
    @AppStorage("lastSize.freeText.h")  private var lastSizeFreeTextH:  Double = 0.04
    @AppStorage("lastSize.checkbox.w")  private var lastSizeCheckboxW:  Double = 0.03
    @AppStorage("lastSize.checkbox.h")  private var lastSizeCheckboxH:  Double = 0.03

    // MARK: Compress mode
    @Published var compressSourceURL: URL?
    @Published var compressPreset: GhostscriptPreset = .ebook
    @Published var compressTargetRatio: Double = 0.5
    @Published var compressGrayscale: Bool = false
    @Published var compressPreserveMetadata: Bool = true
    @Published var compressIsRunning: Bool = false
    @Published var compressProgress: Double = 0
    @Published var compressResult: CompressionResult?
    @Published var compressError: String?
    @Published var compressGhostscriptMissing: Bool = false

    // MARK: Merge mode
    @Published var mergeSourceURLs: [URL] = []
    @Published var mergeOutputName: String = "merged"
    @Published var mergeIsRunning: Bool = false
    @Published var mergeProgress: Double = 0
    @Published var mergeResultURL: URL?
    @Published var mergeError: String?

    // MARK: Convert mode
    @Published var convertSourceURL: URL?
    @Published var convertIncludeYAMLFrontmatter: Bool = true
    @Published var convertExtractImages: Bool = true
    @Published var convertImageFormat: ConvertImageFormat = .png
    @Published var convertPerformOCR: Bool = true
    @Published var convertOCRLanguages: String = "en-US"
    @Published var convertPreserveLinks: Bool = true
    @Published var convertIsRunning: Bool = false
    @Published var convertProgress: Double = 0
    @Published var convertResult: MarkdownConversionResult?
    @Published var convertError: String?

    // MARK: Shared banners
    @Published var lastSavedURL: URL?
    @Published var errorMessage: String?

    // MARK: Services
    private let library = SignatureLibrary()
    private let flattener = PDFFlattener()
    private let compressor = CompressionService()
    private let merger = PDFMerger()
    private let converter = MarkdownConverter()

    private(set) lazy var undoCoordinator: UndoCoordinator = {
        UndoCoordinator(
            placements: { [weak self] in self?.placements ?? [] },
            replace:    { [weak self] new in self?.placements = new }
        )
    }()

    init() {
        signatures = library.load()
        activeSignatureID = signatures.first(where: { $0.role == .signature })?.id
        activeInitialsID  = signatures.first(where: { $0.role == .initials  })?.id
    }

    // MARK: - Derived

    var documentPageCount: Int {
        document?.pageCount ?? 0
    }

    func signature(id: UUID) -> SavedSignature? {
        signatures.first(where: { $0.id == id })
    }

    func signatures(role: SavedSignatureRole) -> [SavedSignature] {
        signatures.filter { $0.role == role }
    }

    // MARK: - Document loading (Sign mode)

    func openDocument(at url: URL) {
        guard let pdf = PDFDocument(url: url) else {
            errorMessage = "Could not open \(url.lastPathComponent)."
            return
        }
        documentURL = url
        document = pdf
        currentPageIndex = 0
        placements.removeAll()
        selectedPlacementID = nil
        lastSavedURL = nil
        errorMessage = nil
    }

    // MARK: - Library

    func addSignature(image: NSImage, name: String, role: SavedSignatureRole) {
        guard let data = image.pngData() else {
            errorMessage = "Could not encode signature image."
            return
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let entry = SavedSignature(
            name: trimmed.isEmpty ? defaultSignatureName(role: role) : trimmed,
            imageData: data,
            role: role
        )
        signatures.insert(entry, at: 0)
        library.save(signatures)
        switch role {
        case .signature: if activeSignatureID == nil { activeSignatureID = entry.id }
        case .initials:  if activeInitialsID  == nil { activeInitialsID  = entry.id }
        }
    }

    func deleteSignature(id: UUID) {
        let role = signatures.first(where: { $0.id == id })?.role ?? .signature
        signatures.removeAll { $0.id == id }
        placements.removeAll { $0.content.referencedSignatureID == id }
        library.save(signatures)
        switch role {
        case .signature: if activeSignatureID == id { activeSignatureID = signatures(role: .signature).first?.id }
        case .initials:  if activeInitialsID  == id { activeInitialsID  = signatures(role: .initials ).first?.id }
        }
    }

    // MARK: - Placements

    /// Drop a new placement of the active tool type at a normalized
    /// page-relative point (top-left origin, 0…1). Uses the size the
    /// user last left this kind of field at — so initialing 30 pages
    /// in a row is consistent without re-resizing every drop.
    func addPlacement(at normalizedPoint: CGPoint) {
        guard document != nil else { return }
        let pageIndex = currentPageIndex

        let (content, size): (PlacementContent, CGSize) = {
            switch activeTool {
            case .signature:
                guard let id = activeSignatureID else { return (.freeText(text: "", fontSize: 14), .zero) }
                return (.signature(signatureID: id),
                        imageSize(widthFraction: lastSizeSignatureW, signatureID: id))
            case .initials:
                guard let id = activeInitialsID else { return (.freeText(text: "", fontSize: 14), .zero) }
                return (.initials(signatureID: id),
                        imageSize(widthFraction: lastSizeInitialsW, signatureID: id))
            case .date:
                return (.date(text: todayText()),
                        CGSize(width: lastSizeDateW, height: lastSizeDateH))
            case .freeText:
                return (.freeText(text: "Text", fontSize: 14),
                        CGSize(width: lastSizeFreeTextW, height: lastSizeFreeTextH))
            case .checkbox:
                return (.checkbox(isChecked: false),
                        CGSize(width: lastSizeCheckboxW, height: lastSizeCheckboxH))
            }
        }()

        if size == .zero { return } // active tool has no asset selected

        let halfW = size.width / 2
        let halfH = size.height / 2
        let x = min(max(normalizedPoint.x - halfW, 0), 1 - size.width)
        let y = min(max(normalizedPoint.y - halfH, 0), 1 - size.height)

        let placement = Placement(
            content: content,
            pageIndex: pageIndex,
            normalizedRect: CGRect(x: x, y: y, width: size.width, height: size.height)
        )

        undoCoordinator.apply("Add \(activeTool.displayName)") {
            placements.append(placement)
            selectedPlacementID = placement.id
        }
    }

    func updatePlacement(id: UUID, normalizedRect: CGRect) {
        guard let idx = placements.firstIndex(where: { $0.id == id }) else { return }
        undoCoordinator.apply("Move / Resize") {
            placements[idx].normalizedRect = normalizedRect
        }
    }

    /// Called when a drag/resize finishes. Persists the new size so the
    /// next placement of the same kind uses it. No-op if the placement
    /// was deleted before commit.
    func commitPlacementSize(id: UUID) {
        guard let p = placements.first(where: { $0.id == id }) else { return }
        let w = Double(p.normalizedRect.width)
        let h = Double(p.normalizedRect.height)
        switch p.content {
        case .signature: lastSizeSignatureW = w
        case .initials:  lastSizeInitialsW  = w
        case .date:      lastSizeDateW = w; lastSizeDateH = h
        case .freeText:  lastSizeFreeTextW = w; lastSizeFreeTextH = h
        case .checkbox:  lastSizeCheckboxW = w; lastSizeCheckboxH = h
        }
    }

    func updateContent(id: UUID, content: PlacementContent) {
        guard let idx = placements.firstIndex(where: { $0.id == id }) else { return }
        undoCoordinator.apply("Edit Field") {
            placements[idx].content = content
        }
    }

    func removePlacement(id: UUID) {
        undoCoordinator.apply("Delete") {
            placements.removeAll { $0.id == id }
            if selectedPlacementID == id { selectedPlacementID = nil }
        }
    }

    /// Copy a placement to every page of the document. Useful for
    /// initials or a date stamp on multi-page contracts.
    func applyToEveryPage(id: UUID) {
        guard let original = placements.first(where: { $0.id == id }),
              let pageCount = document?.pageCount else { return }
        undoCoordinator.apply("Apply to Every Page") {
            for pageIndex in 0..<pageCount where pageIndex != original.pageIndex {
                let copy = Placement(
                    content: original.content,
                    pageIndex: pageIndex,
                    normalizedRect: original.normalizedRect
                )
                placements.append(copy)
            }
        }
    }

    func placements(onPage pageIndex: Int) -> [Placement] {
        placements.filter { $0.pageIndex == pageIndex }
    }

    // MARK: - Save (Sign mode)

    func saveSignedPDF() {
        guard let source = documentURL else {
            errorMessage = "No document open."
            return
        }
        do {
            let output = try flattener.flatten(source: source, placements: placements, signatures: signatures)
            lastSavedURL = output
            errorMessage = nil
            NSWorkspace.shared.activateFileViewerSelecting([output])
        } catch {
            errorMessage = error.localizedDescription
            lastSavedURL = nil
        }
    }

    // MARK: - Compress mode

    func runCompression() {
        guard let url = compressSourceURL else {
            compressError = "Pick a PDF first."
            return
        }
        compressError = nil
        compressIsRunning = true
        compressProgress = 0
        compressResult = nil
        compressGhostscriptMissing = false

        let preset = compressPreset
        let ratio = compressTargetRatio
        let grayscale = compressGrayscale
        let preserveMetadata = compressPreserveMetadata

        Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await compressor.compress(
                    pdfURL: url,
                    preset: preset,
                    targetRatio: ratio,
                    grayscale: grayscale,
                    preserveMetadata: preserveMetadata,
                    progressHandler: { progress in
                        Task { @MainActor in
                            self.compressProgress = progress
                        }
                    }
                )
                await MainActor.run {
                    self.compressResult = result
                    self.compressProgress = 1.0
                    self.compressIsRunning = false
                    NSWorkspace.shared.activateFileViewerSelecting([result.outputURL])
                }
            } catch CompressionError.ghostscriptNotFound {
                await MainActor.run {
                    self.compressGhostscriptMissing = true
                    self.compressError = nil
                    self.compressIsRunning = false
                }
            } catch {
                await MainActor.run {
                    self.compressError = error.localizedDescription
                    self.compressIsRunning = false
                }
            }
        }
    }

    // MARK: - Merge mode

    func runMerge() {
        guard mergeSourceURLs.count >= 2 else {
            mergeError = "Add at least two PDFs."
            return
        }
        let urls = mergeSourceURLs
        let outputName = mergeOutputName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "merged" : mergeOutputName
        mergeError = nil
        mergeIsRunning = true
        mergeProgress = 0
        mergeResultURL = nil

        Task { [weak self] in
            guard let self else { return }
            do {
                let outURL = try await merger.merge(
                    pdfURLs: urls,
                    outputName: outputName,
                    progressHandler: { progress in
                        Task { @MainActor in self.mergeProgress = progress }
                    }
                )
                await MainActor.run {
                    self.mergeResultURL = outURL
                    self.mergeProgress = 1.0
                    self.mergeIsRunning = false
                    NSWorkspace.shared.activateFileViewerSelecting([outURL])
                }
            } catch {
                await MainActor.run {
                    self.mergeError = error.localizedDescription
                    self.mergeIsRunning = false
                }
            }
        }
    }

    // MARK: - Convert mode

    func runConversion() {
        guard let url = convertSourceURL else {
            convertError = "Pick a PDF first."
            return
        }
        convertError = nil
        convertIsRunning = true
        convertProgress = 0
        convertResult = nil

        let options = MarkdownConversionOptions(
            includeYAMLFrontmatter: convertIncludeYAMLFrontmatter,
            extractImages: convertExtractImages,
            imageFormat: convertImageFormat,
            performOCR: convertPerformOCR,
            ocrLanguages: convertOCRLanguages
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty },
            preserveLinks: convertPreserveLinks
        )

        Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await converter.convert(
                    pdfURL: url,
                    options: options,
                    progressHandler: { progress in
                        Task { @MainActor in self.convertProgress = progress }
                    }
                )
                await MainActor.run {
                    self.convertResult = result
                    self.convertProgress = 1.0
                    self.convertIsRunning = false
                    NSWorkspace.shared.activateFileViewerSelecting([result.markdownURL])
                }
            } catch {
                await MainActor.run {
                    self.convertError = error.localizedDescription
                    self.convertIsRunning = false
                }
            }
        }
    }

    // MARK: - Helpers

    /// Compute the normalized rect size for an image-backed placement
    /// so the frame matches the image's aspect ratio on the current
    /// page. Normalized width and height live in different "axes"
    /// (fractions of page width vs. page height respectively), so the
    /// height fraction must include the page's own aspect ratio —
    /// otherwise the frame is taller than the visible signature and
    /// the resize handle ends up below a band of empty space.
    private func imageSize(widthFraction: Double, signatureID: UUID) -> CGSize {
        let clampedW = min(max(widthFraction, 0.02), 1.0)
        let imageAspect: CGFloat = {
            guard let image = signature(id: signatureID)?.image else { return 3.0 }
            let s = image.size
            return (s.width > 0 && s.height > 0) ? s.width / s.height : 3.0
        }()
        let pageAspect: CGFloat = {
            guard let page = document?.page(at: currentPageIndex) else { return 8.5 / 11.0 }
            let b = page.bounds(for: .mediaBox)
            return (b.width > 0 && b.height > 0) ? b.width / b.height : 8.5 / 11.0
        }()
        let heightFraction = CGFloat(clampedW) / imageAspect * pageAspect
        return CGSize(width: CGFloat(clampedW), height: heightFraction)
    }

    private func defaultSignatureName(role: SavedSignatureRole) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return "\(role.displayName) \(formatter.string(from: Date()))"
    }

    private func todayText() -> String {
        let df = DateFormatter()
        df.dateStyle = .long
        return df.string(from: Date())
    }
}
