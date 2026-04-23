//
//  SignatureLibrary.swift
//  PDFHandler
//
//  JSON persistence helper for the signature library. Stored at
//    ~/Library/Application Support/PDFHandler/signatures.json
//

import Foundation

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
