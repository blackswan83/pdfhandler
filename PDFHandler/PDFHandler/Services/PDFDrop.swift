//
//  PDFDrop.swift
//  PDFHandler
//
//  One implementation of "accept PDFs dropped from Finder", shared by
//  every pane. Previously each view had its own copy, and each one
//  only understood a provider that hands back Data — Finder can also
//  supply an NSURL or a plain string, in which case the drop silently
//  did nothing.
//

import Foundation
import AppKit
import UniformTypeIdentifiers

enum PDFDrop {

    static let acceptedTypes: [UTType] = [.pdf, .fileURL]

    /// Extracts every dropped PDF, preserving the order they were
    /// dropped in, and delivers them on the main actor.
    @discardableResult
    static func receive(
        _ providers: [NSItemProvider],
        onLoaded: @escaping ([URL]) -> Void
    ) -> Bool {
        let candidates = providers.filter {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
                || $0.hasItemConformingToTypeIdentifier(UTType.pdf.identifier)
        }
        guard !candidates.isEmpty else { return false }

        var collected: [(Int, URL)] = []
        let group = DispatchGroup()

        for (order, provider) in candidates.enumerated() {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let url = Self.url(from: item)
                DispatchQueue.main.async {
                    if let url, url.pathExtension.lowercased() == "pdf" {
                        collected.append((order, url))
                    }
                    group.leave()
                }
            }
        }

        group.notify(queue: .main) {
            let urls = collected.sorted { $0.0 < $1.0 }.map(\.1)
            if !urls.isEmpty { onLoaded(urls) }
        }
        return true
    }

    /// Finder hands back Data, NSURL or String depending on the source
    /// and macOS version. Handle all three rather than the one.
    private static func url(from item: NSSecureCoding?) -> URL? {
        if let data = item as? Data {
            if let url = URL(dataRepresentation: data, relativeTo: nil) { return url }
            if let text = String(data: data, encoding: .utf8) { return URL(string: text) }
            return nil
        }
        if let url = item as? URL { return url }
        if let text = item as? String { return URL(string: text) }
        return nil
    }
}
