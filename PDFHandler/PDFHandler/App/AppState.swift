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
    /// Changes on every (re)open; used to invalidate the preview cache.
    @Published private(set) var documentID = UUID()
    @Published var currentPageIndex: Int = 0 {
        didSet {
            guard oldValue != currentPageIndex else { return }
            // Leaving a page ends any text edit and drops a selection
            // that would otherwise be invisibly acted on (Delete key,
            // nudges) from another page.
            editingPlacementID = nil
            if let id = selectedPlacementID,
               let placement = placements.first(where: { $0.id == id }),
               placement.pageIndex != currentPageIndex {
                selectedPlacementID = nil
            }
            // Re-center the new page when zoomed in.
            zoomToken &+= 1
        }
    }

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
    @Published var selectedPlacementID: UUID? {
        didSet {
            guard oldValue != selectedPlacementID else { return }
            // Selecting a different placement (or nothing) ends an
            // in-progress text edit on the previous one.
            if let editing = editingPlacementID, editing != selectedPlacementID {
                editingPlacementID = nil
            }
        }
    }

    /// The text placement currently being edited inline (nil when no
    /// edit session is active). Setting it manages the undo snapshot:
    /// the whole edit session becomes a single undo step.
    @Published var editingPlacementID: UUID? {
        didSet {
            guard oldValue != editingPlacementID else { return }
            if oldValue == nil, editingPlacementID != nil {
                textEditSnapshot = placements
            } else if editingPlacementID == nil {
                if let snapshot = textEditSnapshot {
                    finishInteraction(label: "Edit Text", before: snapshot)
                }
                textEditSnapshot = nil
            } else {
                // Switched directly from one edit to another: close
                // out the previous session and start a fresh one.
                if let snapshot = textEditSnapshot {
                    finishInteraction(label: "Edit Text", before: snapshot)
                }
                textEditSnapshot = placements
            }
        }
    }
    private var textEditSnapshot: [Placement]?

    // MARK: Zoom (Sign mode)

    /// Absolute page-point → screen-point scale, used once the user
    /// takes manual control of the zoom level.
    @Published private(set) var zoom: Double = 1.0
    /// While true the preview uses the fit-to-window scale and follows
    /// window resizes; any explicit zoom action turns it off.
    @Published private(set) var isZoomFitted: Bool = true
    /// Bumped by every discrete zoom action (and page change) so the
    /// preview re-centers on the focus point. Pinch-zoom deliberately
    /// does not bump it — the pinch already tracks the gesture.
    @Published private(set) var zoomToken: Int = 0

    /// The latest fit-to-window scale, recorded by the preview so that
    /// stepping up from "Fit" starts at the right place. Deliberately
    /// not @Published: it is derived from layout and must never
    /// re-trigger layout.
    private(set) var fittedScale: Double = 1.0

    /// The scale actually on screen right now.
    var effectiveZoom: Double { isZoomFitted ? fittedScale : zoom }

    var zoomLabel: String {
        isZoomFitted ? "Fit" : "\(Int((zoom * 100).rounded()))%"
    }

    var canZoomIn:  Bool { document != nil && effectiveZoom < ZoomScale.max - 0.001 }
    var canZoomOut: Bool { document != nil && effectiveZoom > ZoomScale.min + 0.001 }

    func recordFittedScale(_ scale: Double) {
        guard scale > 0 else { return }
        fittedScale = scale
    }

    /// Set an absolute zoom level. `recenter: false` is for continuous
    /// gestures, which must not fight the scroll position mid-pinch.
    func setZoom(_ value: Double, recenter: Bool = true) {
        zoom = ZoomScale.clamp(value)
        isZoomFitted = false
        if recenter { zoomToken &+= 1 }
    }

    func zoomIn()  { setZoom(ZoomScale.stop(above: effectiveZoom)) }
    func zoomOut() { setZoom(ZoomScale.stop(below: effectiveZoom)) }
    func zoomToActualSize() { setZoom(1.0) }

    func zoomToFit() {
        isZoomFitted = true
        zoom = fittedScale
        zoomToken &+= 1
    }

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
    // Checkbox height is always derived from width + page aspect so
    // the box stays square in page points.
    @AppStorage("lastSize.checkbox.w")  private var lastSizeCheckboxW:  Double = 0.03

    // MARK: Text styling (persisted; new text fields inherit it)
    @AppStorage("text.font")     private var storedTextFont: String = TextFont.system.rawValue
    @AppStorage("text.size")     private var storedTextSize: Double = 12
    @AppStorage("text.autoFit")  private var storedTextAutoFit: Bool = true

    /// Style applied to newly placed text fields, and the target of
    /// the inspector when nothing is selected.
    var defaultTextStyle: TextStyle {
        get {
            TextStyle(
                font: TextFont(rawValue: storedTextFont) ?? .system,
                size: CGFloat(storedTextSize),
                autoFit: storedTextAutoFit
            )
        }
        set {
            storedTextFont = newValue.font.rawValue
            storedTextSize = Double(newValue.size)
            storedTextAutoFit = newValue.autoFit
        }
    }

    /// Style shown in the inspector: the selected field's if a text
    /// field is selected, otherwise the default for the next one.
    var inspectorTextStyle: TextStyle {
        selectedTextPlacement?.content.textPayload?.style ?? defaultTextStyle
    }

    /// The point size the selected text field is actually rendering
    /// at. With "fit to box" on this is derived from the box, so the
    /// inspector would otherwise display a stored default that is not
    /// the size in effect.
    var effectiveTextPointSize: CGFloat? {
        guard let placement = selectedTextPlacement,
              let style = placement.content.textPayload?.style,
              let page = document?.page(at: placement.pageIndex)
        else { return nil }
        let boxHeightInPoints = placement.normalizedRect.height * page.displaySize.height
        return style.resolvedSize(boxHeight: boxHeightInPoints)
    }

    var selectedTextPlacement: Placement? {
        guard let id = selectedPlacementID,
              let placement = placements.first(where: { $0.id == id }),
              placement.content.textPayload != nil
        else { return nil }
        return placement
    }

    /// Apply a style to the selected text field, or set the default
    /// for future ones when nothing is selected.
    func applyTextStyle(_ style: TextStyle) {
        defaultTextStyle = style
        guard let placement = selectedTextPlacement,
              let idx = placements.firstIndex(where: { $0.id == placement.id })
        else {
            objectWillChange.send()
            return
        }
        undoCoordinator.apply("Text Style") {
            placements[idx].content = placements[idx].content.withStyle(style)
        }
    }

    // MARK: Save options
    /// Also write a copy with every field except the signature and
    /// initials images — the "filled but not yet signed" version.
    @AppStorage("save.alsoUnsignedCopy") var alsoSaveUnsignedCopy: Bool = false

    // MARK: Compress mode
    @Published var compressSourceURL: URL? {
        didSet {
            compressSourceIsSigned = compressSourceURL.map {
                CompressionService.carriesDigitalSignature(url: $0)
            } ?? false
            compressSourceSize = compressSourceURL.map {
                CompressionService.fileSize($0)
            } ?? 0
            compressResult = nil
            compressError = nil
        }
    }
    @Published var compressMode: CompressMode = .ebook
    @Published var compressGrayscale: Bool = false
    @Published var compressTargetFraction: Double = 0.5
    /// Size of the chosen source, read once on selection so the pane
    /// can show what the output is being compared against.
    @Published private(set) var compressSourceSize: Int64 = 0
    /// The chosen PDF carries a cryptographic signature, which no
    /// re-compressor can preserve.
    @Published private(set) var compressSourceIsSigned: Bool = false
    @Published var compressIsRunning: Bool = false
    @Published var compressProgress: Double = 0
    @Published var compressResult: CompressionResult?
    @Published var compressError: String?
    @Published var compressGhostscriptMissing: Bool = false

    // MARK: Merge mode
    @Published var mergeItems: [MergeItem] = []
    @Published var mergeOutputName: String = "merged"
    @Published var mergeIsRunning: Bool = false
    @Published var mergeProgress: Double = 0
    @Published var mergeResultURL: URL?
    @Published var mergeError: String?

    // MARK: Convert mode
    @Published var convertSourceURL: URL?
    @Published var convertIncludeYAMLFrontmatter: Bool = true
    @Published var convertExtractImages: Bool = false
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
            replace:    { [weak self] new in
                guard let self else { return }
                self.placements = new
                // Undo/redo can remove the selected or edited
                // placement; drop dangling references so keyboard
                // actions don't silently no-op.
                if let selected = self.selectedPlacementID,
                   !new.contains(where: { $0.id == selected }) {
                    self.selectedPlacementID = nil
                }
                if let editing = self.editingPlacementID,
                   !new.contains(where: { $0.id == editing }) {
                    self.editingPlacementID = nil
                }
            }
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
        documentID = UUID()
        currentPageIndex = 0
        placements.removeAll()
        selectedPlacementID = nil
        editingPlacementID = nil
        textEditSnapshot = nil
        lastSavedURL = nil
        errorMessage = nil
        isZoomFitted = true
        zoom = 1.0
        zoomToken &+= 1
        undoCoordinator.reset()
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
        // A freshly added asset is what the user wants to place next.
        switch role {
        case .signature: activeSignatureID = entry.id
        case .initials:  activeInitialsID  = entry.id
        }
    }

    /// Replaces the in-memory library without touching the on-disk
    /// index. Used only by the --screenshot-demo development mode, so
    /// running it can never disturb a real user's saved signatures.
    /// Where the signature library lives on disk. Outside the app
    /// bundle, which is why it survives deleting and reinstalling the
    /// app — standard macOS behaviour for user data.
    var signatureLibraryURL: URL { library.indexURL }

    func revealSignatureLibrary() {
        NSWorkspace.shared.activateFileViewerSelecting([library.indexURL])
    }

    /// Erase every saved signature and initials entry, on disk too.
    func eraseSignatureLibrary() {
        signatures = []
        activeSignatureID = nil
        activeInitialsID = nil
        placements.removeAll { $0.content.referencedSignatureID != nil }
        library.save([])
        undoCoordinator.reset()
    }

    func replaceLibraryInMemory(_ entries: [SavedSignature]) {
        signatures = entries
        activeSignatureID = entries.first(where: { $0.role == .signature })?.id
        activeInitialsID  = entries.first(where: { $0.role == .initials  })?.id
    }

    /// Entry currently being re-processed by `isolateSignatureInk`,
    /// so its row can show progress instead of a second button press.
    @Published private(set) var isolatingSignatureID: UUID?

    /// Re-run ink isolation on an existing library entry. This is the
    /// fix for signatures imported before extraction existed (they
    /// survive reinstalls by design): they still sit on an opaque
    /// white card and blank out whatever they are placed over.
    func isolateSignatureInk(id: UUID) {
        guard isolatingSignatureID == nil,
              let entry = signatures.first(where: { $0.id == id }),
              let image = entry.image else { return }
        let options = SignatureExtractor.Options()
        guard let raster = SignatureExtractor.raster(from: image, maxDimension: options.maxDimension) else {
            errorMessage = "Could not read \"\(entry.name)\"."
            return
        }
        isolatingSignatureID = id
        Task { [weak self] in
            let output = await Task.detached(priority: .userInitiated) {
                SignatureExtractor.extract(raster, options: options)
            }.value
            guard let self else { return }
            self.isolatingSignatureID = nil
            guard let output,
                  let extracted = SignatureExtractor.image(from: output),
                  let data = extracted.pngData() else {
                self.errorMessage = "No clear ink found in \"\(entry.name)\" — try re-importing it from a sharper photo."
                return
            }
            // Re-find by id: the library may have changed meanwhile.
            guard let idx = self.signatures.firstIndex(where: { $0.id == id }) else { return }
            let old = self.signatures[idx]
            self.signatures[idx] = SavedSignature(
                id: old.id, name: old.name, imageData: data,
                createdAt: old.createdAt, role: old.role
            )
            self.library.save(self.signatures)
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
        // Undo could otherwise restore placements that reference the
        // deleted image; the flattener would then refuse to save.
        undoCoordinator.reset()
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
                guard let id = activeSignatureID else { return (.freeText(text: "", style: defaultTextStyle), .zero) }
                return (.signature(signatureID: id),
                        imageSize(widthFraction: lastSizeSignatureW, signatureID: id))
            case .initials:
                guard let id = activeInitialsID else { return (.freeText(text: "", style: defaultTextStyle), .zero) }
                return (.initials(signatureID: id),
                        imageSize(widthFraction: lastSizeInitialsW, signatureID: id))
            case .date:
                return (.date(text: todayText(), style: defaultTextStyle),
                        CGSize(width: lastSizeDateW, height: lastSizeDateH))
            case .freeText:
                // Empty text: the preview shows a placeholder and the
                // flattener skips empty fields, so an untouched box
                // never burns literal filler into the document.
                return (.freeText(text: "", style: defaultTextStyle),
                        CGSize(width: lastSizeFreeTextW, height: lastSizeFreeTextH))
            case .checkbox:
                // Height derived from width so the box is square in
                // page points regardless of the page's aspect ratio.
                let aspect = currentPageAspect()
                return (.checkbox(isChecked: false),
                        CGSize(width: lastSizeCheckboxW, height: lastSizeCheckboxW * aspect))
            }
        }()

        if size == .zero { return } // active tool has no asset selected

        let w = min(size.width, 1)
        let h = min(size.height, 1)
        let x = min(max(normalizedPoint.x - w / 2, 0), 1 - w)
        let y = min(max(normalizedPoint.y - h / 2, 0), 1 - h)

        let placement = Placement(
            content: content,
            pageIndex: pageIndex,
            normalizedRect: CGRect(x: x, y: y, width: w, height: h)
        )

        undoCoordinator.apply("Add \(activeTool.displayName)") {
            placements.append(placement)
            selectedPlacementID = placement.id
        }
    }

    /// Live mutation during a drag / resize. Registers NO undo step —
    /// the owning gesture captures a snapshot when it starts and calls
    /// finishInteraction(label:before:) once when it ends.
    func updatePlacementLive(id: UUID, normalizedRect: CGRect) {
        guard let idx = placements.firstIndex(where: { $0.id == id }) else { return }
        placements[idx].normalizedRect = normalizedRect
    }

    /// Close out a live interaction (drag, resize, text-edit session)
    /// as a single undo step. No-op if nothing actually changed.
    func finishInteraction(label: String, before snapshot: [Placement]) {
        guard snapshot != placements else { return }
        undoCoordinator.commit(label, before: snapshot)
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
        case .checkbox:  lastSizeCheckboxW = w
        }
    }

    /// One-shot content change (checkbox toggle): registers an undo step.
    func updateContent(id: UUID, content: PlacementContent) {
        guard let idx = placements.firstIndex(where: { $0.id == id }) else { return }
        undoCoordinator.apply("Edit Field") {
            placements[idx].content = content
        }
    }

    /// Live content change during a text-edit session; undo for the
    /// whole session is handled by editingPlacementID's snapshot.
    func updateContentLive(id: UUID, content: PlacementContent) {
        guard let idx = placements.firstIndex(where: { $0.id == id }) else { return }
        placements[idx].content = content
    }

    func removePlacement(id: UUID) {
        if editingPlacementID == id { editingPlacementID = nil }
        undoCoordinator.apply("Delete") {
            placements.removeAll { $0.id == id }
            if selectedPlacementID == id { selectedPlacementID = nil }
        }
    }

    func removeSelectedPlacement() {
        guard let id = selectedPlacementID else { return }
        removePlacement(id: id)
    }

    /// Arrow-key nudge of the selected placement, in page points.
    func nudgeSelectedPlacement(dxPoints: CGFloat, dyPoints: CGFloat) {
        guard let id = selectedPlacementID,
              let idx = placements.firstIndex(where: { $0.id == id }),
              let page = document?.page(at: placements[idx].pageIndex)
        else { return }
        let size = page.displaySize
        guard size.width > 0, size.height > 0 else { return }

        var rect = placements[idx].normalizedRect
        rect.origin.x = min(max(rect.origin.x + dxPoints / size.width, 0), max(0, 1 - rect.width))
        rect.origin.y = min(max(rect.origin.y + dyPoints / size.height, 0), max(0, 1 - rect.height))
        guard rect != placements[idx].normalizedRect else { return }
        undoCoordinator.apply("Nudge") {
            placements[idx].normalizedRect = rect
        }
    }

    /// Copy a placement to every page of the document. Useful for
    /// initials or a date stamp on multi-page contracts. Idempotent:
    /// pages that already carry an identical copy are skipped.
    func applyToEveryPage(id: UUID) {
        guard let original = placements.first(where: { $0.id == id }),
              let pageCount = document?.pageCount else { return }
        let targets = (0..<pageCount).filter { pageIndex in
            pageIndex != original.pageIndex && !placements.contains {
                $0.pageIndex == pageIndex
                    && $0.content == original.content
                    && $0.normalizedRect == original.normalizedRect
            }
        }
        guard !targets.isEmpty else { return }
        undoCoordinator.apply("Apply to Every Page") {
            for pageIndex in targets {
                placements.append(Placement(
                    content: original.content,
                    pageIndex: pageIndex,
                    normalizedRect: original.normalizedRect
                ))
            }
        }
    }

    func placements(onPage pageIndex: Int) -> [Placement] {
        placements.filter { $0.pageIndex == pageIndex }
    }

    // MARK: - Save (Sign mode)

    /// Save the flattened PDF. By default it lands next to the source
    /// as `<name>_signed.pdf`; `askingWhere` forces a save panel. When
    /// the source folder cannot take new files — a PDF opened straight
    /// out of another app's container ("Mail Downloads" is the everyday
    /// case), a read-only volume — the panel appears automatically
    /// instead of failing with nowhere to go.
    func saveSignedPDF(askingWhere: Bool = false) {
        guard let source = documentURL, let document else {
            errorMessage = "No document open."
            return
        }
        guard !placements.isEmpty else {
            errorMessage = "Place at least one field before saving."
            return
        }
        editingPlacementID = nil // commit any in-progress text edit

        // Flatten into temporary files first: rendering problems
        // surface before any destination question, and a half-written
        // file can never be left in the user's folder.
        let fm = FileManager.default
        let signedTemp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        var filledTemp: URL?
        do {
            try flattener.flatten(
                document: document, placements: placements,
                signatures: signatures, to: signedTemp
            )
            // Optional "filled but not signed" companion: every field
            // except the signature and initials images. The untouched
            // original remains the third copy.
            if alsoSaveUnsignedCopy {
                let unsigned = placements.filter { !$0.content.isImageBacked }
                if !unsigned.isEmpty {
                    let temp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
                    try flattener.flatten(
                        document: document, placements: unsigned,
                        signatures: signatures, to: temp
                    )
                    filledTemp = temp
                }
            }
        } catch {
            errorMessage = error.localizedDescription
            lastSavedURL = nil
            return
        }
        defer {
            // No-ops for temps that were successfully moved into place.
            try? fm.removeItem(at: signedTemp)
            if let filledTemp { try? fm.removeItem(at: filledTemp) }
        }

        // Where should the signed copy go?
        let sourceDir = source.deletingLastPathComponent()
        let suggestedName = source.deletingPathExtension().lastPathComponent + "_signed.pdf"
        var signedURL = sourceDir.appendingPathComponent(suggestedName)
        var userPicked = false

        if askingWhere || Self.needsSavePrompt(directory: sourceDir) {
            let startDir = Self.needsSavePrompt(directory: sourceDir) ? nil : sourceDir
            guard let chosen = promptForSaveDestination(
                suggestedName: suggestedName, startingIn: startDir
            ) else { return } // user cancelled — not an error
            signedURL = chosen
            userPicked = true
        }

        do {
            try Self.place(fileAt: signedTemp, at: signedURL)
        } catch _ where !userPicked {
            // The write failed even though the folder looked fine — TCC
            // denials are invisible to a writability check. Ask instead
            // of failing.
            guard let chosen = promptForSaveDestination(
                suggestedName: suggestedName, startingIn: nil
            ) else { return }
            signedURL = chosen
            userPicked = true
            do {
                try Self.place(fileAt: signedTemp, at: signedURL)
            } catch {
                errorMessage = "Could not save \(signedURL.lastPathComponent): \(error.localizedDescription)"
                lastSavedURL = nil
                return
            }
        } catch {
            errorMessage = "Could not save \(signedURL.lastPathComponent): \(error.localizedDescription)"
            lastSavedURL = nil
            return
        }

        // The filled companion goes wherever the signed copy went.
        errorMessage = nil
        var revealed = [signedURL]
        if let filledTemp {
            let filledURL = PDFFlattener.companionURL(besides: signedURL, suffix: "_filled")
            do {
                try Self.place(fileAt: filledTemp, at: filledURL)
                revealed.append(filledURL)
            } catch {
                errorMessage = "The signed copy was saved, but the filled copy was not: \(error.localizedDescription)"
            }
        }

        lastSavedURL = signedURL
        // Reveal in Finder only when the app picked the location. When
        // the user chose it in the panel they know exactly where it
        // went, and yanking focus over to Finder is just noise.
        if !userPicked {
            NSWorkspace.shared.activateFileViewerSelecting(revealed)
        }
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if let self, self.lastSavedURL == signedURL {
                self.lastSavedURL = nil
            }
        }
    }

    /// True when creating files in `directory` is known not to work:
    /// no write permission, or the folder belongs to another app's
    /// sandbox container, where TCC blocks new files even though a
    /// plain writability check says yes (opening the PDF only granted
    /// access to that one file, not its folder).
    private static func needsSavePrompt(directory: URL) -> Bool {
        let fm = FileManager.default
        if !fm.isWritableFile(atPath: directory.path) { return true }
        let home = fm.homeDirectoryForCurrentUser.standardizedFileURL.path
        let path = directory.standardizedFileURL.path
        return path.hasPrefix(home + "/Library/Containers/")
            || path.hasPrefix(home + "/Library/Mail")
    }

    private func promptForSaveDestination(suggestedName: String, startingIn directory: URL?) -> URL? {
        let panel = NSSavePanel()
        panel.title = "Save Signed PDF"
        panel.nameFieldStringValue = suggestedName
        panel.allowedContentTypes = [.pdf]
        panel.canCreateDirectories = true
        panel.directoryURL = directory
            ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// Move a finished temp file into its destination, replacing any
    /// existing file — matching the long-standing behaviour of
    /// overwriting `<name>_signed.pdf` on every save.
    private static func place(fileAt temp: URL, at destination: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }
        do {
            try fm.moveItem(at: temp, to: destination)
        } catch {
            // Cross-volume oddities: a copy can succeed where the move
            // failed; the temp is cleaned up by the caller either way.
            try fm.copyItem(at: temp, to: destination)
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

        let preset = compressMode.preset
        let grayscale = compressGrayscale
        let target = compressMode.isTargetSize ? compressTargetFraction : nil

        Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await compressor.compress(
                    pdfURL: url,
                    preset: preset,
                    grayscale: grayscale,
                    targetFraction: target,
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
        guard mergeItems.count >= 2 else {
            mergeError = "Add at least two PDFs."
            return
        }
        let urls = mergeItems.map(\.url)
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
        let heightFraction = CGFloat(clampedW) / imageAspect * currentPageAspect()
        return CGSize(width: CGFloat(clampedW), height: min(heightFraction, 1.0))
    }

    /// Width / height of the current page as displayed (rotation
    /// applied). Falls back to US-letter portrait.
    private func currentPageAspect() -> CGFloat {
        guard let page = document?.page(at: currentPageIndex) else { return 8.5 / 11.0 }
        let size = page.displaySize
        return (size.width > 0 && size.height > 0) ? size.width / size.height : 8.5 / 11.0
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
