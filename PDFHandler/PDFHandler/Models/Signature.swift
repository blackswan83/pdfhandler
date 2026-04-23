//
//  Signature.swift
//  PDFHandler
//
//  The user's saved signature / initials assets. Persisted as PNG
//  bytes inside a JSON index; see Services/SignatureLibrary.swift.
//

import Foundation
import AppKit

/// Whether a saved entry is a full signature or a compact set of
/// initials. Surfaced as two sub-lists in the library sidebar.
enum SavedSignatureRole: String, Codable, CaseIterable, Identifiable {
    case signature
    case initials
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .signature: return "Signature"
        case .initials:  return "Initials"
        }
    }
}

/// A signature or initials image saved in the user's library.
struct SavedSignature: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    let imageData: Data   // PNG bytes
    let createdAt: Date
    var role: SavedSignatureRole

    init(
        id: UUID = UUID(),
        name: String,
        imageData: Data,
        createdAt: Date = Date(),
        role: SavedSignatureRole = .signature
    ) {
        self.id = id
        self.name = name
        self.imageData = imageData
        self.createdAt = createdAt
        self.role = role
    }

    var image: NSImage? { NSImage(data: imageData) }

    // Backwards-compatible decoding: older library files have no role.
    enum CodingKeys: String, CodingKey {
        case id, name, imageData, createdAt, role
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id         = try c.decode(UUID.self,   forKey: .id)
        self.name       = try c.decode(String.self, forKey: .name)
        self.imageData  = try c.decode(Data.self,   forKey: .imageData)
        self.createdAt  = try c.decode(Date.self,   forKey: .createdAt)
        self.role       = try c.decodeIfPresent(SavedSignatureRole.self, forKey: .role) ?? .signature
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
