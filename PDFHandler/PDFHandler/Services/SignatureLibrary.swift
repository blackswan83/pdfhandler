//
//  SignatureLibrary.swift
//  PDFHandler
//
//  Persistent on-disk store for saved signatures and initials. Pure
//  persistence helper (no ObservableObject / no MainActor) — AppState
//  owns the observable array and delegates load/save to this type.
//  Stored at:
//    ~/Library/Application Support/PDFHandler/signatures.json
//

import Foundation
import AppKit

struct SignatureLibrary {

    let indexURL: URL

    init(fileManager: FileManager = .default) {
        let appSupport = (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fileManager.temporaryDirectory

        let dir = appSupport.appendingPathComponent("PDFHandler", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        self.indexURL = dir.appendingPathComponent("signatures.json")
    }

    func load() -> [SavedSignature] {
        guard FileManager.default.fileExists(atPath: indexURL.path),
              let data = try? Data(contentsOf: indexURL),
              let decoded = try? JSONDecoder().decode([SavedSignature].self, from: data)
        else {
            return []
        }
        return decoded
    }

    func save(_ entries: [SavedSignature]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(entries) {
            try? data.write(to: indexURL, options: .atomic)
        }
    }
}

// MARK: - NSImage PNG helper

extension NSImage {
    /// PNG-encoded bitmap of the receiver, or nil if encoding fails.
    func pngData() -> Data? {
        guard let tiff = self.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }
}

// MARK: - Default-name helper

enum SavedSignatureNaming {
    static func defaultName(for role: SavedSignatureRole, now: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return "\(role.displayName) \(formatter.string(from: now))"
    }
}
