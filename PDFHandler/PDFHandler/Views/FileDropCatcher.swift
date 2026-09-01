//
//  FileDropCatcher.swift
//  PDFHandler
//
//  Window-wide drag-and-drop for PDFs, at the AppKit level.
//
//  SwiftUI's .onDrop only understands providers that resolve to a
//  file URL, which covers Finder — but dragging an attachment straight
//  out of Mail (or a download out of Safari) delivers a *file
//  promise*: the file does not exist anywhere yet, so there is no URL
//  to load and the drop silently did nothing. That is exactly what
//  "drag and drop doesn't work" looks like to someone whose PDFs
//  arrive by email.
//
//  An NSView drag destination accepts both plain file URLs and
//  NSFilePromiseReceiver promises (received into a temp folder before
//  opening). hitTest returns nil so the view never swallows clicks;
//  drag-destination lookup goes by type registration, not hitTest, so
//  drops still land here. The SwiftUI .onDrop handlers underneath are
//  deliberately kept: if this view is ever bypassed, Finder drags
//  still work the old way.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct FileDropCatcher: NSViewRepresentable {
    @Binding var isTargeted: Bool
    let onURLs: ([URL]) -> Void

    func makeNSView(context: Context) -> DropCatcherNSView {
        let view = DropCatcherNSView()
        configure(view)
        return view
    }

    func updateNSView(_ nsView: DropCatcherNSView, context: Context) {
        configure(nsView)
    }

    private func configure(_ view: DropCatcherNSView) {
        view.onTargeted = { isTargeted = $0 }
        view.onURLs = onURLs
    }
}

final class DropCatcherNSView: NSView {
    var onURLs: (([URL]) -> Void)?
    var onTargeted: ((Bool) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        var types = NSFilePromiseReceiver.readableDraggedTypes
            .map { NSPasteboard.PasteboardType(rawValue: $0) }
        types.append(.fileURL)
        registerForDraggedTypes(types)
    }

    required init?(coder: NSCoder) { nil }

    /// Invisible to the mouse: clicks fall through to the SwiftUI
    /// content underneath.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    // MARK: - NSDraggingDestination

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard carriesPDF(sender.draggingPasteboard) else { return [] }
        onTargeted?(true)
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onTargeted?(false)
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        onTargeted?(false)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        onTargeted?(false)
        let pasteboard = sender.draggingPasteboard

        // Plain file URLs: Finder, the Desktop, most document apps.
        let urls = fileURLs(on: pasteboard).filter { $0.pathExtension.lowercased() == "pdf" }

        // File promises: Mail attachments, Safari downloads, Photos.
        // The file does not exist yet — ask the dragging source to
        // write it into a temp folder, then open from there.
        let receivers = (pasteboard.readObjects(forClasses: [NSFilePromiseReceiver.self], options: nil)
                            as? [NSFilePromiseReceiver] ?? [])
            .filter(Self.promisesPDF)

        guard !urls.isEmpty || !receivers.isEmpty else { return false }
        guard !receivers.isEmpty else {
            onURLs?(urls)
            return true
        }

        let dropFolder = FileManager.default.temporaryDirectory
            .appendingPathComponent("DroppedPDFs-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dropFolder, withIntermediateDirectories: true)

        let queue = OperationQueue()
        let group = DispatchGroup()
        var promised: [URL] = [] // appended on the main queue only

        for receiver in receivers {
            group.enter()
            receiver.receivePromisedFiles(atDestination: dropFolder, options: [:], operationQueue: queue) { url, error in
                DispatchQueue.main.async {
                    if error == nil, url.pathExtension.lowercased() == "pdf" {
                        promised.append(url)
                    }
                    group.leave()
                }
            }
        }
        group.notify(queue: .main) { [weak self] in
            let all = urls + promised
            if !all.isEmpty { self?.onURLs?(all) }
        }
        return true
    }

    // MARK: - Pasteboard inspection

    private func carriesPDF(_ pasteboard: NSPasteboard) -> Bool {
        if fileURLs(on: pasteboard).contains(where: { $0.pathExtension.lowercased() == "pdf" }) {
            return true
        }
        // Reading promise objects only reads their metadata; nothing
        // is received until receivePromisedFiles.
        let receivers = pasteboard.readObjects(forClasses: [NSFilePromiseReceiver.self], options: nil)
            as? [NSFilePromiseReceiver] ?? []
        return receivers.contains(where: Self.promisesPDF)
    }

    private static func promisesPDF(_ receiver: NSFilePromiseReceiver) -> Bool {
        let types = receiver.fileTypes
        // Some sources advertise no content type up front; accept and
        // filter by extension once the file actually arrives.
        guard !types.isEmpty else { return true }
        return types.contains { type in
            UTType(type)?.conforms(to: .pdf) == true || type.lowercased() == "pdf"
        }
    }

    private func fileURLs(on pasteboard: NSPasteboard) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        return pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL] ?? []
    }
}
