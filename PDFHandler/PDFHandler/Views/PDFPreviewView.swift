//
//  PDFPreviewView.swift
//  PDFHandler
//
//  Shows the current page rendered to a cached NSImage and overlays
//  any placements for that page. Clicking empty space drops a new
//  placement using the active tool.
//

import SwiftUI
import PDFKit
import AppKit

struct PDFPreviewView: View {
    @EnvironmentObject var appState: AppState

    /// Stable coordinate space for placement drag gestures. Measuring
    /// drags here (instead of in the moving placement's own space)
    /// is what keeps moves and resizes steady.
    static let pageSpaceName = "pdfhandler.pageSpace"

    var body: some View {
        GeometryReader { geo in
            if let pdf = appState.document, pdf.pageCount > 0 {
                let pageIndex = clampedPageIndex(pageCount: pdf.pageCount)
                if let page = pdf.page(at: pageIndex) {
                    let fit = fittedSize(pageSize: page.displaySize, container: geo.size)

                    ZStack(alignment: .topLeading) {
                        Color(nsColor: .windowBackgroundColor)
                        pageStack(page: page, pageIndex: pageIndex, fit: fit)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                emptyState
            }
        }
    }

    private func pageStack(page: PDFPage, pageIndex: Int, fit: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            Image(nsImage: pageImage(page: page, pageIndex: pageIndex, fit: fit))
                .resizable()
                .interpolation(.high)
                .frame(width: fit.width, height: fit.height)
                .shadow(color: .black.opacity(0.2), radius: 6, y: 2)

            // Click-to-place hit layer, behind the placement overlays.
            Color.white.opacity(0.001)
                .frame(width: fit.width, height: fit.height)
                .contentShape(Rectangle())
                .gesture(
                    SpatialTapGesture()
                        .onEnded { event in
                            handlePageClick(location: event.location, pageSize: fit)
                        }
                )

            ForEach(appState.placements(onPage: pageIndex)) { placement in
                PlacementView(placement: placement, pageSize: fit)
                    .environmentObject(appState)
            }
        }
        .frame(width: fit.width, height: fit.height)
        .coordinateSpace(name: Self.pageSpaceName)
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

    private func pageImage(page: PDFPage, pageIndex: Int, fit: CGSize) -> NSImage {
        let display = page.displaySize
        guard fit.width >= 1, fit.height >= 1, display.width > 0, display.height > 0 else {
            return NSImage(size: NSSize(width: 1, height: 1))
        }
        // Render at the window's actual backing scale (mixed-DPI safe),
        // bucketing the pixel width so live window resizing reuses the
        // cached bitmap instead of re-rasterizing on every tick. Height
        // follows the page aspect exactly, so nothing distorts.
        let scale = NSApp.keyWindow?.backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor ?? 2
        let pixelW = (ceil(fit.width * scale / 128) * 128)
        let pixelH = (pixelW * display.height / display.width).rounded()
        let pixel = CGSize(width: pixelW, height: pixelH)
        return PageImageCache.shared.image(
            documentID: appState.documentID,
            pageIndex: pageIndex,
            size: pixel,
            scale: 1
        ) {
            page.renderedDisplayImage(pixelSize: pixel, pointSize: pixel)
                ?? NSImage(size: NSSize(width: 1, height: 1))
        }
    }

    private func fittedSize(pageSize: CGSize, container: CGSize) -> CGSize {
        guard pageSize.width > 0, pageSize.height > 0,
              container.width > 0, container.height > 0 else { return .zero }
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

    // MARK: - Click to place

    private func handlePageClick(location: CGPoint, pageSize: CGSize) {
        guard pageSize.width > 0, pageSize.height > 0 else { return }

        // A click outside the field being edited just ends the edit —
        // it should not also drop a brand-new field.
        if appState.editingPlacementID != nil {
            appState.editingPlacementID = nil
            return
        }

        // Signature / initials tool armed but the library is empty:
        // guide the user to create one instead of doing nothing.
        if appState.activeTool == .signature, appState.activeSignatureID == nil {
            appState.newSignatureRole = .signature
            appState.isPresentingNewSignature = true
            return
        }
        if appState.activeTool == .initials, appState.activeInitialsID == nil {
            appState.newSignatureRole = .initials
            appState.isPresentingNewSignature = true
            return
        }

        let normalized = CGPoint(
            x: min(max(location.x / pageSize.width, 0), 1),
            y: min(max(location.y / pageSize.height, 0), 1)
        )
        appState.addPlacement(at: normalized)
    }
}
