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

// MARK: - NSImage helpers

extension NSImage {
    /// PNG-encoded bitmap of the receiver, or nil if encoding fails.
    func pngData() -> Data? {
        guard let tiff = self.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    /// Returns a copy of the image with near-white pixels made fully
    /// transparent. Useful for scanned/JPEG signatures that arrive on
    /// an opaque white background — DocuSign does the same chroma-key
    /// when you upload a scanned signature.
    ///
    /// `threshold` is the minimum brightness (0…1) at which a pixel is
    /// considered "white background". 0.90 catches typical scanner
    /// off-white without eating dark ink.
    func knockingOutWhiteBackground(threshold: CGFloat = 0.90) -> NSImage? {
        guard let tiff = self.tiffRepresentation,
              let inputRep = NSBitmapImageRep(data: tiff),
              let inputCG = inputRep.cgImage else { return nil }

        let width  = inputCG.width
        let height = inputCG.height
        guard width > 0, height > 0,
              let cs = CGColorSpace(name: CGColorSpace.sRGB)
        else { return nil }

        let bytesPerRow = width * 4
        let bitmapInfo  = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue).rawValue
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: cs,
            bitmapInfo: bitmapInfo
        ) else { return nil }

        ctx.draw(inputCG, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = ctx.data else { return nil }

        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        let cutoff = UInt8(min(max(threshold, 0), 1) * 255)
        for i in stride(from: 0, to: width * height * 4, by: 4) {
            let r = pixels[i]
            let g = pixels[i + 1]
            let b = pixels[i + 2]
            if r >= cutoff && g >= cutoff && b >= cutoff {
                pixels[i]     = 0  // premultiplied: zero RGB so anti-aliased edges blend cleanly
                pixels[i + 1] = 0
                pixels[i + 2] = 0
                pixels[i + 3] = 0
            }
        }

        guard let outCG = ctx.makeImage() else { return nil }
        return NSImage(cgImage: outCG, size: self.size)
    }
}
