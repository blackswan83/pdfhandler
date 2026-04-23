//
//  AppState.swift
//  PDFHandler
//
//  Central observable state: the currently open PDF, the persistent
//  signature library, the signature the user is placing, and the
//  placements they have dropped onto pages.
//

import Foundation
import SwiftUI
import PDFKit
import AppKit

@MainActor
final class AppState: ObservableObject {

    // MARK: - Document

    @Published var documentURL: URL?
    @Published var document: PDFDocument?
    @Published var currentPageIndex: Int = 0

    // MARK: - Signature library

    @Published private(set) var signatures: [SavedSignature] = []

    /// The signature the user currently has "picked up" from the library.
    /// Clicking on the PDF preview drops a placement using this signature.
    @Published var activeSignatureID: UUID?

    // MARK: - Placements (signatures dropped on pages)

    @Published var placements: [SignaturePlacement] = []

    @Published var isPresentingNewSignature = false

    // MARK: - Save result

    @Published var lastSavedURL: URL?
    @Published var errorMessage: String?

    // MARK: - Services

    private let library = SignatureLibrary()
    private let signer = PDFSigner()

    init() {
        signatures = library.load()
        activeSignatureID = signatures.first?.id
    }

    // MARK: - Document loading

    func openDocument(at url: URL) {
        guard let pdf = PDFDocument(url: url) else {
            errorMessage = "Could not open \(url.lastPathComponent)."
            return
        }
        documentURL = url
        document = pdf
        currentPageIndex = 0
        placements.removeAll()
        lastSavedURL = nil
        errorMessage = nil
    }

    // MARK: - Signature library

    func addSignature(image: NSImage, name: String) {
        guard let data = image.pngData() else {
            errorMessage = "Could not encode signature image."
            return
        }
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let entry = SavedSignature(
            name: cleanName.isEmpty ? defaultSignatureName() : cleanName,
            imageData: data
        )
        signatures.insert(entry, at: 0)
        library.save(signatures)
        if activeSignatureID == nil {
            activeSignatureID = entry.id
        }
    }

    func deleteSignature(id: UUID) {
        signatures.removeAll { $0.id == id }
        placements.removeAll { $0.signatureID == id }
        library.save(signatures)
        if activeSignatureID == id {
            activeSignatureID = signatures.first?.id
        }
    }

    func renameSignature(id: UUID, to newName: String) {
        guard let idx = signatures.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        signatures[idx].name = trimmed.isEmpty ? defaultSignatureName() : trimmed
        library.save(signatures)
    }

    func signature(id: UUID) -> SavedSignature? {
        signatures.first(where: { $0.id == id })
    }

    // MARK: - Placements

    func addPlacement(at normalizedPoint: CGPoint, pageIndex: Int) {
        guard let signatureID = activeSignatureID,
              signatures.contains(where: { $0.id == signatureID }) else { return }

        // Default size: ~20% of page width, aspect from the saved image.
        let width: CGFloat = 0.25
        let aspect = aspectRatio(forSignatureID: signatureID)
        let height = width / aspect

        // Center the placement on the clicked point, clamped to page.
        let halfW = width / 2
        let halfH = height / 2
        let x = min(max(normalizedPoint.x - halfW, 0), 1 - width)
        let y = min(max(normalizedPoint.y - halfH, 0), 1 - height)

        let placement = SignaturePlacement(
            signatureID: signatureID,
            pageIndex: pageIndex,
            normalizedRect: CGRect(x: x, y: y, width: width, height: height)
        )
        placements.append(placement)
    }

    func updatePlacement(id: UUID, normalizedRect: CGRect) {
        guard let idx = placements.firstIndex(where: { $0.id == id }) else { return }
        placements[idx].normalizedRect = normalizedRect
    }

    func removePlacement(id: UUID) {
        placements.removeAll { $0.id == id }
    }

    func placements(onPage pageIndex: Int) -> [SignaturePlacement] {
        placements.filter { $0.pageIndex == pageIndex }
    }

    // MARK: - Save

    func saveSignedPDF() {
        guard let source = documentURL else {
            errorMessage = "No document open."
            return
        }
        do {
            let output = try signer.sign(
                source: source,
                placements: placements,
                signatures: signatures
            )
            lastSavedURL = output
            errorMessage = nil
            NSWorkspace.shared.activateFileViewerSelecting([output])
        } catch {
            errorMessage = error.localizedDescription
            lastSavedURL = nil
        }
    }

    // MARK: - Helpers

    private func aspectRatio(forSignatureID id: UUID) -> CGFloat {
        guard let image = signature(id: id)?.image else { return 3.0 }
        let size = image.size
        guard size.width > 0, size.height > 0 else { return 3.0 }
        return size.width / size.height
    }

    private func defaultSignatureName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return "Signature \(formatter.string(from: Date()))"
    }
}
