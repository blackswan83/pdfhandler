//
//  PDFPreviewView.swift
//  PDFHandler
//
//  Shows a single PDF page rendered to an NSImage and overlays any
//  signature placements for that page. Clicking on empty space drops
//  a new placement using the currently-active signature.
//

import SwiftUI
import PDFKit
import AppKit

struct PDFPreviewView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        GeometryReader { geo in
            if let pdf = appState.document,
               pdf.pageCount > 0,
               let page = pdf.page(at: clampedPageIndex(pageCount: pdf.pageCount)) {
                let box = PDFDisplayBox.mediaBox
                let bounds = page.bounds(for: box)
                let fit = fittedSize(pageSize: bounds.size, container: geo.size)

                ZStack(alignment: .topLeading) {
                    Color(nsColor: .windowBackgroundColor)

                    ZStack(alignment: .topLeading) {
                        Image(nsImage: renderPage(page, targetSize: fit))
                            .resizable()
                            .frame(width: fit.width, height: fit.height)
                            .shadow(color: .black.opacity(0.2), radius: 6, y: 2)

                        // Click-to-place hit layer, behind the placement overlays.
                        Color.white.opacity(0.001)
                            .frame(width: fit.width, height: fit.height)
                            .contentShape(Rectangle())
                            .gesture(
                                SpatialTapGesture()
                                    .onEnded { event in
                                        placeAtClick(location: event.location, pageSize: fit)
                                    }
                            )

                        // Existing placements on this page.
                        ForEach(appState.placements(onPage: appState.currentPageIndex)) { placement in
                            if let sig = appState.signature(id: placement.signatureID) {
                                SignaturePlacementView(
                                    placement: placement,
                                    signature: sig,
                                    pageSize: fit,
                                    onUpdate: { newRect in
                                        appState.updatePlacement(id: placement.id, normalizedRect: newRect)
                                    },
                                    onDelete: {
                                        appState.removePlacement(id: placement.id)
                                    }
                                )
                            }
                        }
                    }
                    .frame(width: fit.width, height: fit.height)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                emptyState
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.badge.plus")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.secondary)
            Text("Open a PDF to start signing")
                .font(.title3)
                .foregroundStyle(.secondary)
            Button("Open PDF…") {
                NotificationCenter.default.post(name: .requestOpenPanel, object: nil)
            }
            .keyboardShortcut("o", modifiers: .command)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Rendering

    private func renderPage(_ page: PDFPage, targetSize: CGSize) -> NSImage {
        let image = NSImage(size: targetSize)
        image.lockFocus()
        if let ctx = NSGraphicsContext.current?.cgContext {
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fill(CGRect(origin: .zero, size: targetSize))
            let bounds = page.bounds(for: .mediaBox)
            let sx = targetSize.width / bounds.width
            let sy = targetSize.height / bounds.height
            ctx.scaleBy(x: sx, y: sy)
            page.draw(with: .mediaBox, to: ctx)
        }
        image.unlockFocus()
        return image
    }

    private func fittedSize(pageSize: CGSize, container: CGSize) -> CGSize {
        guard pageSize.width > 0, pageSize.height > 0,
              container.width > 0, container.height > 0 else {
            return .zero
        }
        let scale = min(
            (container.width  - 32) / pageSize.width,
            (container.height - 32) / pageSize.height
        )
        let s = max(scale, 0.01)
        return CGSize(width: pageSize.width * s, height: pageSize.height * s)
    }

    private func clampedPageIndex(pageCount: Int) -> Int {
        min(max(appState.currentPageIndex, 0), pageCount - 1)
    }

    private func placeAtClick(location: CGPoint, pageSize: CGSize) {
        guard pageSize.width > 0, pageSize.height > 0 else { return }
        let normalized = CGPoint(
            x: min(max(location.x / pageSize.width, 0), 1),
            y: min(max(location.y / pageSize.height, 0), 1)
        )
        appState.addPlacement(at: normalized, pageIndex: appState.currentPageIndex)
    }
}
