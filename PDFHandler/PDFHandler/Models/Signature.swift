//
//  Signature.swift
//  PDFHandler
//
//  Model types for stored signatures and their placement on PDF pages.
//

import Foundation
import AppKit

/// A signature image saved in the user's library.
struct SavedSignature: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    let imageData: Data   // PNG bytes
    let createdAt: Date

    init(id: UUID = UUID(), name: String, imageData: Data, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.imageData = imageData
        self.createdAt = createdAt
    }

    var image: NSImage? {
        NSImage(data: imageData)
    }
}

/// A single placement of a saved signature on a specific page.
/// Coordinates are normalized 0…1 against the page's mediaBox so the
/// same placement renders correctly at any preview size and maps
/// cleanly to PDF coordinates at export time.
///
/// Note: intentionally not Hashable — CGRect is not Hashable on
/// macOS 13, and Identifiable is all SwiftUI needs here.
struct SignaturePlacement: Identifiable {
    let id: UUID
    let signatureID: UUID
    var pageIndex: Int        // 0-based
    var normalizedRect: CGRect // origin + size, all in 0…1 (top-left origin)

    init(
        id: UUID = UUID(),
        signatureID: UUID,
        pageIndex: Int,
        normalizedRect: CGRect
    ) {
        self.id = id
        self.signatureID = signatureID
        self.pageIndex = pageIndex
        self.normalizedRect = normalizedRect
    }
}

// MARK: - NSImage PNG helper

extension NSImage {
    /// PNG-encoded bitmap of the receiver, or nil if encoding fails.
    func pngData() -> Data? {
        guard let tiff = self.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
