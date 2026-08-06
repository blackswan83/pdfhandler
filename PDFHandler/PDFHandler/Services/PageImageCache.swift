//
//  PageImageCache.swift
//  PDFHandler
//
//  Cache for rendered page previews. PDFPreviewView's body is
//  re-evaluated on every placement drag tick and every keystroke;
//  without this cache the entire PDF page would be re-rasterized each
//  time, which is what made dragging feel janky. Zooming multiplies
//  the stakes — a zoomed page bitmap is tens of megabytes — so entries
//  are bounded by real byte cost, not just count.
//

import AppKit

@MainActor
final class PageImageCache {
    static let shared = PageImageCache()

    private let cache = NSCache<NSString, NSImage>()

    private init() {
        cache.countLimit = 6
        cache.totalCostLimit = 256 * 1024 * 1024
    }

    /// Returns the cached bitmap for (documentID, pageIndex, pixelSize),
    /// rendering and storing it on a miss. `documentID` changes whenever
    /// a document is (re)opened, which implicitly invalidates stale
    /// entries.
    func image(
        documentID: UUID,
        pageIndex: Int,
        pixelSize: CGSize,
        render: () -> NSImage
    ) -> NSImage {
        let key = "\(documentID.uuidString)|\(pageIndex)|\(Int(pixelSize.width))x\(Int(pixelSize.height))" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        let rendered = render()
        let cost = Int(pixelSize.width * pixelSize.height) * 4  // RGBA bytes
        cache.setObject(rendered, forKey: key, cost: cost)
        return rendered
    }
}
